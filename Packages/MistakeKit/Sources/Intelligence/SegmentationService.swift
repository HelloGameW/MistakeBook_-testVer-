import Foundation
import Contracts

/// Conservative, explainable first-pass segmentation. It never claims that a
/// text-only bounding box contains every diagram or handwritten stroke.
public struct HeuristicSegmentationService: SegmentationService, Sendable {
    public init() {}

    public func segment(page: RecognizedPage, options: SegmentationOptions) async throws -> [SegmentationCandidate] {
        try Task.checkCancellation()
        guard !page.lines.isEmpty else {
            let region = page.regions.first ?? SourceRegion(id: UUID(), assetID: page.assetID,
                                                            normalizedRect: .fullPage, purpose: .unknown,
                                                            isUserConfirmed: false)
            let visuals = page.regions.filter { $0.id != region.id && $0.purpose == .diagram }
            return [SegmentationCandidate(id: UUID(), order: 1, regions: [region] + visuals, lineIDs: [],
                                          needsConfirmation: true,
                                          warnings: [ServiceWarning(code: "segmentation.noText",
                                                                    message: "没有可用文字定位，默认使用整页并需人工调整。",
                                                                    regionID: region.id)]
                                            + Self.visualWarnings(visuals))]
        }

        let ordered = page.lines.sorted { lhs, rhs in
            if abs(lhs.normalizedRect.y - rhs.normalizedRect.y) > 0.015 {
                return lhs.normalizedRect.y < rhs.normalizedRect.y
            }
            return lhs.normalizedRect.x < rhs.normalizedRect.x
        }
        let starts = ordered.indices.filter { Self.looksLikeQuestionStart(ordered[$0].rawText) }
        if starts.count < 2 {
            let region = try Self.boundingRegion(lines: ordered, assetID: page.assetID)
            let visuals = Self.visualRegions(in: region, from: page.regions)
            return [SegmentationCandidate(id: UUID(), order: 1, regions: [region] + visuals,
                                          lineIDs: ordered.map(\.id), needsConfirmation: true,
                                          warnings: [ServiceWarning(code: "segmentation.needsReview",
                                                                    message: "未发现足够明确的大题号，已保守合并为一题，请校对分题范围。",
                                                                    regionID: region.id)]
                                            + Self.visualWarnings(visuals))]
        }

        var candidates: [SegmentationCandidate] = []
        for index in starts.indices {
            let start = starts[index]
            let end = index + 1 < starts.count ? starts[index + 1] : ordered.count
            let group = Array(ordered[start..<end])
            let region = try Self.boundingRegion(lines: group, assetID: page.assetID)
            let visuals = Self.visualRegions(in: region, from: page.regions)
            candidates.append(SegmentationCandidate(id: UUID(), order: index + 1, regions: [region] + visuals,
                                                    lineIDs: group.map(\.id), needsConfirmation: false,
                                                    warnings: [ServiceWarning(code: "segmentation.textHeuristic",
                                                                              message: "按题号和文字区域生成，图表/跨栏/手写范围请对照原图。",
                                                                              regionID: region.id)]
                                                        + Self.visualWarnings(visuals)))
        }
        return candidates
    }

    private static func looksLikeQuestionStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"^\s*[\(（]\s*\d+\s*[\)）]"#, options: .regularExpression) != nil { return false }
        if trimmed.range(of: #"^\s*[A-Ha-h]\s*[\.、\)]"#, options: .regularExpression) != nil { return false }
        return trimmed.range(of: #"^\s*(?:第\s*\d+\s*题|\d{1,3}\s*[\.、:：])"#, options: .regularExpression) != nil
    }

    private static func boundingRegion(lines: [OCRLine], assetID: UUID) throws -> SourceRegion {
        let minX = lines.map { $0.normalizedRect.x }.min() ?? 0
        let minY = lines.map { $0.normalizedRect.y }.min() ?? 0
        let maxX = lines.map { $0.normalizedRect.x + $0.normalizedRect.width }.max() ?? 1
        let maxY = lines.map { $0.normalizedRect.y + $0.normalizedRect.height }.max() ?? 1
        let padding = 0.01
        let x = max(0, minX - padding)
        let y = max(0, minY - padding)
        let right = min(1, maxX + padding)
        let bottom = min(1, maxY + padding)
        return SourceRegion(id: UUID(), assetID: assetID,
                            normalizedRect: try NormalizedRect(x: x, y: y,
                                                               width: max(0.001, right - x),
                                                               height: max(0.001, bottom - y)),
                            purpose: .unknown, isUserConfirmed: false)
    }

    private static func visualRegions(in candidate: SourceRegion,
                                      from regions: [SourceRegion]) -> [SourceRegion] {
        regions.filter { region in
            region.id != candidate.id && region.purpose == .diagram
                && Self.overlap(candidate.normalizedRect, region.normalizedRect) > 0.01
        }
    }

    private static func visualWarnings(_ regions: [SourceRegion]) -> [ServiceWarning] {
        regions.map {
            ServiceWarning(code: "segmentation.visualRegion",
                           message: "已将图像/表格/公式候选区域随题目保留，提交前请人工确认。",
                           regionID: $0.id)
        }
    }

    private static func overlap(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        guard right > left, bottom > top else { return 0 }
        return (right - left) * (bottom - top)
    }
}
