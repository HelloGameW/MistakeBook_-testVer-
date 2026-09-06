#if os(iOS)
import Foundation
import UIKit
#else
import Foundation
#endif
import Contracts

public enum ExportFactory {
    public static func make(assetStore: any AssetStore,
                            configuration: PDFExportConfiguration) throws -> any PDFExportService {
        #if os(iOS)
        return OfflinePDFExportService(assetStore: assetStore, configuration: configuration)
        #else
        throw AppError(code: .featureUnavailable)
        #endif
    }
}

/// Offline PDF implementation. The exporter never queries a repository or taxonomy;
/// the snapshot already contains the final order, labels and image decisions.
public struct OfflinePDFExportService: PDFExportService {
    private let assetStore: any AssetStore
    private let configuration: PDFExportConfiguration

    public init(assetStore: any AssetStore, configuration: PDFExportConfiguration) {
        self.assetStore = assetStore
        self.configuration = configuration
    }

    public func export(snapshot: ExportSnapshot) async throws -> ExportArtifact {
        #if os(iOS)
        return try await render(snapshot: snapshot)
        #else
        throw AppError(code: .featureUnavailable)
        #endif
    }

    public func releaseExport(artifactID: UUID) async throws {
        let url = configuration.temporaryDirectory.appendingPathComponent("MistakeBook-\(artifactID.uuidString).pdf")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    #if os(iOS)
    private func render(snapshot: ExportSnapshot) async throws -> ExportArtifact {
        guard !snapshot.records.isEmpty else {
            throw AppError(code: .unsupportedInput)
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: configuration.temporaryDirectory,
                                            withIntermediateDirectories: true)
        } catch {
            throw AppError(code: .storageFull, isRetryable: true)
        }

        let artifactID = UUID()
        let url = configuration.temporaryDirectory.appendingPathComponent("MistakeBook-\(artifactID.uuidString).pdf")
        var warnings: [ServiceWarning] = []

        do {
            try Task.checkCancellation()
            func shouldRenderImage(_ decision: ExportImageDecision, record: MistakeRecord) -> Bool {
                guard decision.disposition != .exclude else { return false }
                let purpose = record.sourceRegions.first(where: { $0.id == decision.regionID })?.purpose
                if snapshot.options.mode == .practice,
                   purpose == .studentWork || purpose == .referenceAnswer { return false }
                if snapshot.options.mode == .withSolutions, !snapshot.options.includeHandwriting, purpose == .studentWork { return false }
                return true
            }

            var loadedImageBytes: [UUID: Data] = [:]
            for exportRecord in snapshot.records {
                for decision in exportRecord.images where shouldRenderImage(decision, record: exportRecord.record) {
                    try Task.checkCancellation()
                    if decision.answerRisk != .userConfirmedClean {
                        warnings.append(ServiceWarning(code: "image-answer-risk",
                                                       message: "原图可能包含答案或批注，请在练习前人工确认。",
                                                       regionID: decision.regionID))
                    }
                    if loadedImageBytes[decision.assetID] == nil {
                        let payload: ImagePayload
                        do {
                            payload = try await assetStore.loadImage(assetID: decision.assetID)
                        } catch {
                            throw AppError(code: .assetMissing, isRetryable: true)
                        }
                        guard UIImage(data: payload.bytes) != nil else {
                            throw AppError(code: .assetMissing, isRetryable: true)
                        }
                        loadedImageBytes[decision.assetID] = payload.bytes
                    }
                }
            }

            let pageRect = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
            var pageCount = 0
            var drawingError: AppError?

            try renderer.writePDF(to: url) { context in
                let margin: CGFloat = 48
                let contentWidth = pageRect.width - margin * 2
                let top = margin
                let bottom = pageRect.height - margin
                let bodyFont = UIFont.systemFont(ofSize: 13)
                let smallFont = UIFont.systemFont(ofSize: 10)
                let titleFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
                var cursorY = top
                var currentPage = 0

                func drawFooter() {
                    let footer = "错题簿  ·  第 \(currentPage) 页"
                    footer.draw(at: CGPoint(x: margin, y: pageRect.height - 25),
                                withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
                }

                func beginPage() {
                    context.beginPage()
                    pageCount += 1
                    currentPage = pageCount
                    cursorY = top
                    "错题簿".draw(at: CGPoint(x: margin, y: 18),
                                  withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
                }

                func finishPage() {
                    drawFooter()
                }

                func ensureSpace(_ height: CGFloat) {
                    if cursorY + height > bottom - 30 {
                        finishPage()
                        beginPage()
                    }
                }

                func width(of text: String, font: UIFont) -> CGFloat {
                    (text as NSString).size(withAttributes: [.font: font]).width
                }

                func wrappedLines(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
                    var result: [String] = []
                    for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
                        var line = ""
                        for character in rawLine {
                            let candidate = line + String(character)
                            if !line.isEmpty && width(of: candidate, font: font) > maxWidth {
                                result.append(line)
                                line = String(character)
                            } else {
                                line = candidate
                            }
                        }
                        result.append(line)
                    }
                    return result.isEmpty ? [""] : result
                }

                func drawWrapped(_ text: String, font: UIFont, color: UIColor, spacing: CGFloat) {
                    for line in wrappedLines(text, font: font, maxWidth: contentWidth) {
                        let lineHeight = font.lineHeight + spacing
                        ensureSpace(lineHeight)
                        line.draw(at: CGPoint(x: margin, y: cursorY),
                                  withAttributes: [.font: font, .foregroundColor: color])
                        cursorY += lineHeight
                    }
                }

                func drawWrapped(_ text: String) {
                    drawWrapped(text, font: bodyFont, color: .label, spacing: 5)
                }

                func drawWrapped(_ text: String, font: UIFont) {
                    drawWrapped(text, font: font, color: .label, spacing: 5)
                }

                func drawHeading(_ text: String) {
                    ensureSpace(30)
                    text.draw(at: CGPoint(x: margin, y: cursorY),
                              withAttributes: [.font: titleFont, .foregroundColor: UIColor.label])
                    cursorY += titleFont.lineHeight + 10
                }

                func cropImage(_ image: UIImage, rect: NormalizedRect?) -> UIImage? {
                    guard let rect, let cgImage = image.cgImage else { return image }
                    let pixelRect = CGRect(x: rect.x * CGFloat(cgImage.width),
                                           y: rect.y * CGFloat(cgImage.height),
                                           width: rect.width * CGFloat(cgImage.width),
                                           height: rect.height * CGFloat(cgImage.height)).integral
                    guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
                    return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
                }

                func drawImage(_ image: UIImage, cropRect: NormalizedRect?, label: String?) {
                    guard let image = cropImage(image, rect: cropRect), let cgImage = image.cgImage else {
                        drawingError = AppError(code: .assetMissing, isRetryable: true)
                        return
                    }
                    let sourceWidth = CGFloat(cgImage.width)
                    let sourceHeight = CGFloat(cgImage.height)
                    guard sourceWidth > 0, sourceHeight > 0 else {
                        drawingError = AppError(code: .assetMissing, isRetryable: true)
                        return
                    }
                    let targetWidth = min(contentWidth, sourceWidth)
                    let pointsPerPixel = targetWidth / sourceWidth
                    let maxImageHeight = bottom - top - 46
                    var sourceY: CGFloat = 0
                    var partIndex = 0

                    while sourceY < sourceHeight {
                        let remainingHeight = sourceHeight - sourceY
                        let partPixelHeight = min(remainingHeight, maxImageHeight / pointsPerPixel)
                        let partRect = CGRect(x: 0, y: sourceY, width: sourceWidth, height: partPixelHeight).integral
                        guard let partCG = cgImage.cropping(to: partRect) else {
                            drawingError = AppError(code: .assetMissing, isRetryable: true)
                            return
                        }
                        let partImage = UIImage(cgImage: partCG, scale: image.scale, orientation: .up)
                        let targetHeight = partPixelHeight * pointsPerPixel
                        let labelHeight: CGFloat = label == nil ? 0 : 18
                        ensureSpace(targetHeight + labelHeight + 8)
                        if let label {
                            "图片：\(label)".draw(at: CGPoint(x: margin, y: cursorY),
                                                  withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
                            cursorY += labelHeight
                        }
                        partImage.draw(in: CGRect(x: margin, y: cursorY, width: targetWidth, height: targetHeight))
                        cursorY += targetHeight + 10
                        sourceY += partPixelHeight
                        partIndex += 1
                        if sourceY < sourceHeight {
                            finishPage()
                            beginPage()
                            "图片续页 \(partIndex + 1)".draw(at: CGPoint(x: margin, y: cursorY),
                                                         withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
                            cursorY += smallFont.lineHeight + 5
                        }
                    }
                }

                func drawBlankSpace(_ blankSpace: BlankSpace) {
                    let height: CGFloat
                    switch blankSpace {
                    case .none: return
                    case .small: height = 78
                    case .medium: height = 158
                    case .large: height = 238
                    }
                    ensureSpace(height)
                    let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: height)
                    UIColor.separator.setStroke()
                    UIBezierPath(rect: rect).stroke()
                    let lineSpacing: CGFloat = 28
                    var lineY = rect.minY + lineSpacing
                    while lineY < rect.maxY - 8 {
                        UIBezierPath(roundedRect: CGRect(x: rect.minX + 14, y: lineY,
                                                         width: rect.width - 28, height: 0.5), cornerRadius: 0).fill()
                        lineY += lineSpacing
                    }
                    cursorY += height + 12
                }

                beginPage()
                for (index, exportRecord) in snapshot.records.enumerated() {
                    if Task.isCancelled {
                        drawingError = AppError(code: .cancelled)
                        return
                    }
                    let record = exportRecord.record
                    drawHeading("第 \(index + 1) 题")
                    if !exportRecord.classificationPath.isEmpty {
                        drawWrapped(exportRecord.classificationPath.joined(separator: " / "), font: smallFont,
                                    color: .secondaryLabel, spacing: 2)
                    }
                    drawWrapped(record.stem.displayText.isEmpty ? "（未填写题干）" : record.stem.displayText)

                    for decision in exportRecord.images where shouldRenderImage(decision, record: record) {
                        guard let imageBytes = loadedImageBytes[decision.assetID],
                              let image = UIImage(data: imageBytes) else {
                            drawingError = AppError(code: .assetMissing, isRetryable: true)
                            return
                        }
                        drawImage(image, cropRect: decision.disposition == .crop ? decision.cropRect : nil,
                                  label: decision.answerRisk == .unknown ? nil : (decision.answerRisk == .mayContainAnswer ? "可能含答案" : "已确认裁切"))
                    }

                    if snapshot.options.mode == .withSolutions {
                        if snapshot.options.includeHandwriting, !record.studentWork.displayText.isEmpty {
                            drawWrapped("学生作答 / 解题步骤", font: titleFont)
                            drawWrapped(record.studentWork.displayText)
                        }
                        if let reference = record.referenceAnswer, !reference.displayText.isEmpty {
                            drawWrapped("参考答案", font: titleFont)
                            drawWrapped(reference.displayText)
                        }
                        if snapshot.options.includeHypotheses,
                           let analysis = record.analysisResult,
                           !record.isAnalysisStale {
                            let visible = analysis.hypotheses.filter { $0.userDecision != .rejected }
                            if !visible.isEmpty {
                                drawWrapped("可能错因", font: titleFont)
                                for hypothesis in visible {
                                    let prefix = hypothesis.userDecision == .pending ? "候选：" : "已接受候选（非正确性保证）："
                                    drawWrapped(prefix + hypothesis.summary)
                                    drawWrapped(hypothesis.reason, font: smallFont, color: .secondaryLabel, spacing: 5)
                                }
                            }
                        }
                        if !record.notes.isEmpty {
                            drawWrapped("笔记", font: titleFont)
                            drawWrapped(record.notes)
                        }
                    } else {
                        drawBlankSpace(snapshot.options.blankSpace)
                    }
                    cursorY += 10
                }
                finishPage()
            }

            if let drawingError { throw drawingError }

            try Task.checkCancellation()
            let summary = ExportSummary(recordCount: snapshot.records.count, pageCount: pageCount, warnings: warnings)
            return ExportArtifact(id: artifactID, fileURL: url, summary: summary, createdAt: Date())
        } catch {
            try? fileManager.removeItem(at: url)
            throw AppError.normalized(error)
        }
    }
    #endif
}
