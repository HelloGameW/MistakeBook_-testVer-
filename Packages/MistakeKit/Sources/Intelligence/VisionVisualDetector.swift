#if canImport(CoreGraphics) && canImport(Vision)
import CoreGraphics
import Foundation
import Vision
import Contracts

struct VisualRegionBuildResult: Sendable {
    let regions: [SourceRegion]
    let lineRegionIDs: [UUID: UUID]
    let warnings: [ServiceWarning]
}

/// Turns Vision's rectangle observations and OCR geometry into reviewable regions.
/// The frozen contract has one diagram-purpose bucket, so the more specific visual
/// kind is carried by a warning code while the original image remains authoritative.
enum VisionVisualDetector {
    private struct DetectedRegion {
        let region: SourceRegion
        let kind: VisualKind
    }

    private enum VisualKind: Equatable {
        case image
        case table
        case formula

        var code: String {
            switch self {
            case .image:
                return "vision.visual.image"
            case .table:
                return "vision.visual.table"
            case .formula:
                return "vision.visual.formula"
            }
        }

        var message: String {
            switch self {
            case .image:
                return "检测到图像/图示候选区域，已绑定原图；请人工确认是否属于题目内容。"

            case .table:
                return "检测到表格候选区域，已保留表格整体范围和其中的文字行；请人工确认边界。"

            case .formula:
                return "检测到公式候选区域；文字结果仅作检索线索，公式原图是最终证据，不保证精确 LaTeX。"
            }
        }
    }

    static func build(
        assetID: UUID,
        rectangles: [VisionVisualObservation],
        lines: [OCRLine]
    ) throws -> VisualRegionBuildResult {
        var detected: [DetectedRegion] = []

        for observation in rectangles {
            guard observation.confidence >= 0.25,
                  let rect = try? Contracts.NormalizedRect.fromBottomLeft(
                      x: Double(observation.x),
                      y: Double(observation.y),
                      width: Double(observation.width),
                      height: Double(observation.height)
                  ),
                  rect.width * rect.height >= 0.015,
                  rect.width * rect.height <= 0.85
            else {
                continue
            }

            let inside = lines.filter {
                Self.center(
                    of: $0.normalizedRect,
                    isInside: rect
                )
            }

            let kind: VisualKind = Self.looksLikeTable(inside)
                ? .table
                : .image

            if !Self.hasStrongDuplicate(
                of: rect,
                in: detected
            ) {
                detected.append(
                    DetectedRegion(
                        region: SourceRegion(
                            id: UUID(),
                            assetID: assetID,
                            normalizedRect: rect,
                            purpose: .diagram,
                            isUserConfirmed: false
                        ),
                        kind: kind
                    )
                )
            }
        }

        if let tableLines = Self.tableLines(lines),
           !detected.contains(where: {
               if case .table = $0.kind {
                   return true
               } else {
                   return false
               }
           }),
           let rect = try? Self.boundingRect(of: tableLines) {
            detected.append(
                DetectedRegion(
                    region: SourceRegion(
                        id: UUID(),
                        assetID: assetID,
                        normalizedRect: rect,
                        purpose: .diagram,
                        isUserConfirmed: false
                    ),
                    kind: .table
                )
            )
        }

        for line in lines
        where Self.looksLikeFormula(line.rawText) {
            guard let rect = try? Self.expandedRect(
                line.normalizedRect,
                padding: 0.006
            ) else {
                continue
            }

            if !Self.hasStrongDuplicate(
                of: rect,
                in: detected,
                matching: .formula
            ) {
                detected.append(
                    DetectedRegion(
                        region: SourceRegion(
                            id: UUID(),
                            assetID: assetID,
                            normalizedRect: rect,
                            purpose: .diagram,
                            isUserConfirmed: false
                        ),
                        kind: .formula
                    )
                )
            }
        }

        var lineRegionIDs: [UUID: UUID] = [:]

        for line in lines {
            let matching = detected.filter {
                Self.center(
                    of: line.normalizedRect,
                    isInside: $0.region.normalizedRect
                )
            }

            if let best = matching.min(by: {
                Self.area($0.region.normalizedRect)
                    < Self.area($1.region.normalizedRect)
            }) {
                lineRegionIDs[line.id] = best.region.id
            }
        }

        let warnings = detected.map {
            ServiceWarning(
                code: $0.kind.code,
                message: $0.kind.message,
                regionID: $0.region.id
            )
        }

        return VisualRegionBuildResult(
            regions: detected.map(\.region),
            lineRegionIDs: lineRegionIDs,
            warnings: warnings
        )
    }

    private static func looksLikeFormula(
        _ text: String
    ) -> Bool {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return false
        }

        let mathSymbols = CharacterSet(
            charactersIn: "=±×÷√∑∫≈≠≤≥^_{}"
        )

        let hasMathSymbol = trimmed.unicodeScalars.contains {
            mathSymbols.contains($0)
        }

        let hasArithmeticPattern = trimmed.range(
            of: #"[A-Za-z0-9)]\s*[+\-*/=]\s*[A-Za-z0-9(]"#,
            options: .regularExpression
        ) != nil

        let hasGreek = trimmed.unicodeScalars.contains { scalar in
            (0x0370...0x03FF).contains(
                Int(scalar.value)
            )
        }

        let hasOperand = trimmed.range(
            of: #"[A-Za-z0-9]"#,
            options: .regularExpression
        ) != nil

        return hasOperand
            && (
                hasMathSymbol
                || hasArithmeticPattern
                || hasGreek
            )
    }

    private static func looksLikeTable(
        _ lines: [OCRLine]
    ) -> Bool {
        guard let tableLines = tableLines(lines) else {
            return false
        }

        return tableLines.count >= 4
    }

    private static func tableLines(
        _ lines: [OCRLine]
    ) -> [OCRLine]? {
        guard lines.count >= 4 else {
            return nil
        }

        let rows = rowGroups(lines)

        let populatedRows = rows.filter {
            distinctColumnCount($0) >= 2
        }

        guard populatedRows.count >= 2 else {
            return nil
        }

        return populatedRows.flatMap {
            $0
        }
    }

    private static func rowGroups(
        _ lines: [OCRLine]
    ) -> [[OCRLine]] {
        var groups: [[OCRLine]] = []

        for line in lines.sorted(by: {
            center(of: $0.normalizedRect).y
                < center(of: $1.normalizedRect).y
        }) {
            let lineCenter = center(
                of: line.normalizedRect
            ).y

            var assigned = false

            for index in groups.indices {
                let rowCenter = groups[index]
                    .map {
                        center(
                            of: $0.normalizedRect
                        ).y
                    }
                    .reduce(0, +)
                    / Double(groups[index].count)

                if abs(rowCenter - lineCenter)
                    <= max(
                        0.012,
                        line.normalizedRect.height * 1.5
                    ) {
                    groups[index].append(line)
                    assigned = true
                    break
                }
            }

            if !assigned {
                groups.append([line])
            }
        }

        return groups
    }

    private static func distinctColumnCount(
        _ lines: [OCRLine]
    ) -> Int {
        var columns: [Double] = []

        for line in lines.sorted(by: {
            $0.normalizedRect.x
                < $1.normalizedRect.x
        }) {
            let x = line.normalizedRect.x

            if columns.allSatisfy({
                abs($0 - x) > 0.045
            }) {
                columns.append(x)
            }
        }

        return columns.count
    }

    private static func center(
        of rect: Contracts.NormalizedRect
    ) -> (x: Double, y: Double) {
        (
            rect.x + rect.width / 2,
            rect.y + rect.height / 2
        )
    }

    private static func center(
        of lineRect: Contracts.NormalizedRect,
        isInside region: Contracts.NormalizedRect
    ) -> Bool {
        let point = center(of: lineRect)

        return point.x >= region.x
            && point.x <= region.x + region.width
            && point.y >= region.y
            && point.y <= region.y + region.height
    }

    private static func area(
        _ rect: Contracts.NormalizedRect
    ) -> Double {
        rect.width * rect.height
    }

    private static func hasStrongDuplicate(
        of rect: Contracts.NormalizedRect,
        in detected: [DetectedRegion],
        matching kind: VisualKind? = nil
    ) -> Bool {
        detected.contains { item in
            if let kind,
               item.kind != kind {
                return false
            }

            return overlap(
                rect,
                item.region.normalizedRect
            ) >= 0.68
        }
    }

    private static func overlap(
        _ lhs: Contracts.NormalizedRect,
        _ rhs: Contracts.NormalizedRect
    ) -> Double {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)

        let right = min(
            lhs.x + lhs.width,
            rhs.x + rhs.width
        )

        let bottom = min(
            lhs.y + lhs.height,
            rhs.y + rhs.height
        )

        guard right > left,
              bottom > top
        else {
            return 0
        }

        return (right - left)
            * (bottom - top)
            / min(
                area(lhs),
                area(rhs)
            )
    }

    private static func expandedRect(
        _ rect: Contracts.NormalizedRect,
        padding: Double
    ) throws -> Contracts.NormalizedRect {
        let x = max(
            0,
            rect.x - padding
        )

        let y = max(
            0,
            rect.y - padding
        )

        let right = min(
            1,
            rect.x + rect.width + padding
        )

        let bottom = min(
            1,
            rect.y + rect.height + padding
        )

        return try Contracts.NormalizedRect(
            x: x,
            y: y,
            width: max(
                0.001,
                right - x
            ),
            height: max(
                0.001,
                bottom - y
            )
        )
    }

    private static func boundingRect(
        of lines: [OCRLine]
    ) throws -> Contracts.NormalizedRect {
        let minX = lines
            .map {
                $0.normalizedRect.x
            }
            .min() ?? 0

        let minY = lines
            .map {
                $0.normalizedRect.y
            }
            .min() ?? 0

        let maxX = lines
            .map {
                $0.normalizedRect.x
                    + $0.normalizedRect.width
            }
            .max() ?? 1

        let maxY = lines
            .map {
                $0.normalizedRect.y
                    + $0.normalizedRect.height
            }
            .max() ?? 1

        let x = max(
            0,
            minX - 0.01
        )

        let y = max(
            0,
            minY - 0.01
        )

        return try Contracts.NormalizedRect(
            x: x,
            y: y,
            width: max(
                0.001,
                min(
                    1,
                    maxX + 0.01
                ) - x
            ),
            height: max(
                0.001,
                min(
                    1,
                    maxY + 0.01
                ) - y
            )
        )
    }
}
#endif
