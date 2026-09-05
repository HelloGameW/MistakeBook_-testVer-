// Contract 1.1.0. Includes switchable OCR providers.
import Foundation

public enum ScriptStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case printed
    case handwritten
    case unknown
}

public enum TextProvenance: String, Codable, Sendable, Equatable, CaseIterable {
    case ocr
    case user
    case teacher
}

public enum OCRQuality: String, Codable, Sendable, Equatable, CaseIterable {
    case accurate
    case fast
}

/// Rect is in the full referenced working image, never relative to a region.
public struct OCRLine: Codable, Sendable, Equatable {
    public let id: UUID
    public let regionID: UUID
    public let assetID: UUID
    public let rawText: String
    public let confidence: Confidence?
    public let scriptStyle: ScriptStyle
    public let normalizedRect: NormalizedRect

    public init(id: UUID, regionID: UUID, assetID: UUID, rawText: String, confidence: Confidence?, scriptStyle: ScriptStyle, normalizedRect: NormalizedRect) {
        self.id = id
        self.regionID = regionID
        self.assetID = assetID
        self.rawText = rawText
        self.confidence = confidence
        self.scriptStyle = scriptStyle
        self.normalizedRect = normalizedRect
    }
}

public struct SegmentationCandidate: Codable, Sendable, Equatable {
    public let id: UUID
    public let order: Int
    public let regions: [SourceRegion]
    public let lineIDs: [UUID]
    public let needsConfirmation: Bool
    public let warnings: [ServiceWarning]

    public init(id: UUID, order: Int, regions: [SourceRegion], lineIDs: [UUID], needsConfirmation: Bool, warnings: [ServiceWarning]) {
        self.id = id
        self.order = order
        self.regions = regions
        self.lineIDs = lineIDs
        self.needsConfirmation = needsConfirmation
        self.warnings = warnings
    }
}

public struct RecognizedPage: Codable, Sendable, Equatable {
    public let assetID: UUID
    public let regions: [SourceRegion]
    public let lines: [OCRLine]
    public let providerID: String
    public let providerVersion: String
    public let supportedLanguages: [String]
    public let warnings: [ServiceWarning]
    public let candidates: [SegmentationCandidate]

    public init(assetID: UUID, regions: [SourceRegion], lines: [OCRLine], providerID: String, providerVersion: String, supportedLanguages: [String], warnings: [ServiceWarning], candidates: [SegmentationCandidate]) {
        self.assetID = assetID
        self.regions = regions
        self.lines = lines
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.supportedLanguages = supportedLanguages
        self.warnings = warnings
        self.candidates = candidates
    }
}

public struct RecognitionOptions: Codable, Sendable, Equatable {
    public let languages: [String]
    public let quality: OCRQuality
    public let usesLanguageCorrection: Bool
    public let maxPixelDimension: Int
    public let processingMode: ProcessingMode?
    public let provider: OCRProviderKind?
    public let modelAPI: ModelAPIConfiguration?
    public let baiduEducation: BaiduEducationConfiguration?

    public init(languages: [String], quality: OCRQuality, usesLanguageCorrection: Bool, maxPixelDimension: Int,
                processingMode: ProcessingMode? = nil, provider: OCRProviderKind? = nil, modelAPI: ModelAPIConfiguration? = nil,
                baiduEducation: BaiduEducationConfiguration? = nil) {
        self.languages = languages
        self.quality = quality
        self.usesLanguageCorrection = usesLanguageCorrection
        self.maxPixelDimension = maxPixelDimension
        self.processingMode = processingMode
        self.provider = provider
        self.modelAPI = modelAPI
        self.baiduEducation = baiduEducation
    }
}

public struct SegmentationOptions: Codable, Sendable, Equatable {
    public let allowOverlappingRegions: Bool

    public init(allowOverlappingRegions: Bool) {
        self.allowOverlappingRegions = allowOverlappingRegions
    }
}

public struct EditableText: Codable, Sendable, Equatable {
    public let rawText: String
    public let correctedText: String?
    public let provenance: TextProvenance
    public let isLocked: Bool

    public init(rawText: String, correctedText: String?, provenance: TextProvenance, isLocked: Bool) {
        self.rawText = rawText
        self.correctedText = correctedText
        self.provenance = provenance
        self.isLocked = isLocked
    }
}

