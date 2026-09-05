#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(Vision)
import CoreGraphics
import Foundation
import ImageIO
import Vision
import Contracts

/// Apple Vision text and layout adapter. Vision observations stay inside this
/// type; the rest of the app receives only Codable value types from Contracts.
public struct VisionOCRService: OCRService, Sendable {
    public init() {}

    public func supportedLanguages() async throws -> [String] {
        try Task.checkCancellation()
        return try Self.runtimeSupportedLanguages()
    }

    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        try Task.checkCancellation()

        let pageRegionID = UUID()
        let pageRegion = SourceRegion(id: pageRegionID, assetID: image.assetID,
                                      normalizedRect: .fullPage, purpose: .unknown,
                                      isUserConfirmed: false)
        guard !image.bytes.isEmpty else {
            return Self.emptyPage(assetID: image.assetID, region: pageRegion,
                                  languages: [], warning: ServiceWarning(
                                    code: "ocr.emptyInput", message: "图片为空，已保留整页待人工录入。", regionID: pageRegionID))
        }

        guard let source = CGImageSourceCreateWithData(image.bytes as CFData, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AppError(code: .unsupportedInput)
        }

        let supported = try Self.runtimeSupportedLanguages()
        let requested = options.languages.isEmpty
            ? supported
            : options.languages.filter { requestedLanguage in
                supported.contains { Self.languageMatches(requestedLanguage, $0) }
            }
        guard !requested.isEmpty else { throw AppError(code: .unsupportedLanguage) }

        let maxDimension = max(1, options.maxPixelDimension)
        let workingImage = Self.downsample(source: source, fallback: sourceImage, maxDimension: maxDimension)
        try Task.checkCancellation()

        let requestBox = VisionRequestBox()
        let visionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let textRequest = VNRecognizeTextRequest()
            let rectangleRequest = VNDetectRectanglesRequest()
            requestBox.store(textRequest)
            requestBox.store(rectangleRequest)
            textRequest.recognitionLevel = options.quality == .accurate ? .accurate : .fast
            textRequest.recognitionLanguages = requested
            textRequest.usesLanguageCorrection = options.usesLanguageCorrection
            let handler = VNImageRequestHandler(cgImage: workingImage,
                                                 orientation: Self.cgOrientation(image.orientation),
                                                 options: [:])
            try handler.perform([textRequest, rectangleRequest])
            try Task.checkCancellation()

            let textObservations = (textRequest.results as? [VNRecognizedTextObservation]) ?? []
            let lines = textObservations.compactMap { observation -> VisionLineObservation? in
                guard let candidate = observation.topCandidates(1).first,
                      !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let rect = observation.boundingBox
                guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy({ $0.isFinite }),
                      rect.width > 0, rect.height > 0 else { return nil }
                let confidence = Double(observation.confidence)
                return VisionLineObservation(text: candidate.string, x: rect.origin.x,
                                             y: rect.origin.y, width: rect.width,
                                             height: rect.height,
                                             confidence: confidence.isFinite && (0...1).contains(confidence) ? confidence : nil)
            }
            let rectangles = (rectangleRequest.results as? [VNRectangleObservation] ?? []).compactMap {
                VisionVisualObservation(x: $0.boundingBox.origin.x,
                                        y: $0.boundingBox.origin.y,
                                        width: $0.boundingBox.width,
                                        height: $0.boundingBox.height,
                                        confidence: Double($0.confidence))
            }
            return VisionPassResult(lines: lines, rectangles: rectangles)
        }

        let pass: VisionPassResult
        do {
            pass = try await withTaskCancellationHandler(operation: {
                try await visionTask.value
            }, onCancel: {
                visionTask.cancel()
                requestBox.cancel()
            })
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError(code: .internalFailure, isRetryable: true)
        }
        try Task.checkCancellation()

        var lines: [OCRLine] = []
        lines.reserveCapacity(pass.lines.count)
        for observation in pass.lines {
            let rect = try NormalizedRect.fromBottomLeft(x: observation.x, y: observation.y,
                                                         width: observation.width, height: observation.height)
            lines.append(OCRLine(id: UUID(), regionID: pageRegionID, assetID: image.assetID,
                                 rawText: observation.text,
                                 confidence: observation.confidence.map {
                                    Confidence(value: $0, source: .vision, calibrated: false)
                                 },
                                  scriptStyle: .unknown, normalizedRect: rect))
        }
        let visualResult = try VisionVisualDetector.build(assetID: image.assetID,
                                                          rectangles: pass.rectangles,
                                                          lines: lines)
        for index in lines.indices {
            if let regionID = visualResult.lineRegionIDs[lines[index].id] {
                let line = lines[index]
                lines[index] = OCRLine(id: line.id, regionID: regionID, assetID: line.assetID,
                                       rawText: line.rawText, confidence: line.confidence,
                                       scriptStyle: line.scriptStyle, normalizedRect: line.normalizedRect)
            }
        }
        lines.sort { lhs, rhs in
            if abs(lhs.normalizedRect.y - rhs.normalizedRect.y) > 0.015 {
                return lhs.normalizedRect.y < rhs.normalizedRect.y
            }
            return lhs.normalizedRect.x < rhs.normalizedRect.x
        }

        var warnings: [ServiceWarning] = []
        if lines.isEmpty {
            warnings.append(ServiceWarning(code: "ocr.noText",
                                           message: "未识别到可确认文字，已保留整页原图和待校对草稿。",
                                           regionID: pageRegionID))
        }
        warnings.append(contentsOf: visualResult.warnings)
        return RecognizedPage(assetID: image.assetID,
                              regions: [pageRegion] + visualResult.regions,
                              lines: lines,
                              providerID: "apple.vision.text-and-layout",
                              providerVersion: "VNRecognizeTextRequestRevision3+VNDetectRectanglesRequest",
                              supportedLanguages: supported, warnings: warnings, candidates: [])
    }

    fileprivate static func runtimeSupportedLanguages() throws -> [String] {
        try VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate,
                                                                  revision: VNRecognizeTextRequestRevision3)
    }

    fileprivate static func languageMatches(_ requested: String, _ supported: String) -> Bool {
        requested.caseInsensitiveCompare(supported) == .orderedSame
            || requested.split(separator: "-").first?.lowercased() == supported.split(separator: "-").first?.lowercased()
    }

    private static func emptyPage(assetID: UUID, region: SourceRegion, languages: [String], warning: ServiceWarning) -> RecognizedPage {
        RecognizedPage(assetID: assetID, regions: [region], lines: [], providerID: "apple.vision.text-and-layout",
                       providerVersion: "VNRecognizeTextRequestRevision3+VNDetectRectanglesRequest", supportedLanguages: languages,
                       warnings: [warning], candidates: [])
    }

    private static func downsample(source: CGImageSource, fallback: CGImage, maxDimension: Int) -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) ?? fallback
    }

    private static func cgOrientation(_ orientation: ImageOrientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }
}

struct VisionPassResult: Sendable {
    let lines: [VisionLineObservation]
    let rectangles: [VisionVisualObservation]
}

struct VisionLineObservation: Sendable {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let confidence: Double?
}

struct VisionVisualObservation: Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let confidence: Double

    init?(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, confidence: Double) {
        guard [x, y, width, height].allSatisfy({ $0.isFinite }),
              width > 0, height > 0, confidence.isFinite else { return nil }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

private final class VisionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [VNRequest] = []
    private var cancelled = false

    func store(_ request: VNRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        if cancelled { request.cancel() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        requests.forEach { $0.cancel() }
    }
}
#else
import Foundation
import Contracts

/// The package remains host-testable on systems without Vision; this fallback
/// reports an unavailable capability instead of returning synthetic OCR.
public struct VisionOCRService: OCRService, Sendable {
    public init() {}
    public func supportedLanguages() async throws -> [String] { [] }
    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        throw AppError(code: .featureUnavailable)
    }
}
#endif
