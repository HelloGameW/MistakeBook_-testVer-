// Contract 1.1.0. Supports optional API providers while retaining local-first defaults.
import Foundation

public enum CapabilityState: String, Codable, Sendable, Equatable, CaseIterable {
    case available
    case partial
    case notReady
    case unavailable
}

public enum CapabilityFeature: String, Codable, Sendable, Equatable, CaseIterable {
    case importImages
    case ocr
    case segmentation
    case basicAnalysis
    case enhancedAnalysis
    case mistakeValue
    case classification
    case pdfExport
}

public enum DataProtection: String, Codable, Sendable, Equatable, CaseIterable {
    case completeUntilFirstUserAuthentication
    case complete
}

public struct FeatureCapability: Codable, Sendable, Equatable {
    public let feature: CapabilityFeature
    public let subjectID: String?
    public let state: CapabilityState
    public let reason: String
    public let supportedLanguages: [String]

    public init(feature: CapabilityFeature, subjectID: String?, state: CapabilityState, reason: String, supportedLanguages: [String]) {
        self.feature = feature
        self.subjectID = subjectID
        self.state = state
        self.reason = reason
        self.supportedLanguages = supportedLanguages
    }
}

public struct CapabilityReport: Codable, Sendable, Equatable {
    public let checkedAt: Date
    public let features: [FeatureCapability]

    public init(checkedAt: Date, features: [FeatureCapability]) {
        self.checkedAt = checkedAt
        self.features = features
    }
}

/// API secrets never live in this Codable value. Only provider selection and
/// non-secret endpoint/model configuration are persisted with app settings.
public struct AppSettings: Codable, Sendable, Equatable {
    public let recognitionLanguages: [String]
    public let enhancedAnalysisEnabled: Bool
    public let autoArchivePolicy: AutoArchivePolicy

    // Added in contract 1.1. All optional to preserve decoding of 1.0 settings.
    public let processingMode: ProcessingMode?
    public let ocrProvider: OCRProviderKind?
    public let analysisProvider: AnalysisProviderKind?
    public let mistakeValueProvider: MistakeValueProviderKind?
    public let ocrModelAPI: ModelAPIConfiguration?
    public let analysisModelAPI: ModelAPIConfiguration?
    public let mistakeValueModelAPI: ModelAPIConfiguration?
    public let baiduEducation: BaiduEducationConfiguration?

    public init(recognitionLanguages: [String], enhancedAnalysisEnabled: Bool, autoArchivePolicy: AutoArchivePolicy,
                processingMode: ProcessingMode? = nil,
                ocrProvider: OCRProviderKind? = nil,
                analysisProvider: AnalysisProviderKind? = nil,
                mistakeValueProvider: MistakeValueProviderKind? = nil,
                ocrModelAPI: ModelAPIConfiguration? = nil,
                analysisModelAPI: ModelAPIConfiguration? = nil,
                mistakeValueModelAPI: ModelAPIConfiguration? = nil,
                baiduEducation: BaiduEducationConfiguration? = nil) {
        self.recognitionLanguages = recognitionLanguages
        self.enhancedAnalysisEnabled = enhancedAnalysisEnabled
        self.autoArchivePolicy = autoArchivePolicy
        self.processingMode = processingMode
        self.ocrProvider = ocrProvider
        self.analysisProvider = analysisProvider
        self.mistakeValueProvider = mistakeValueProvider
        self.ocrModelAPI = ocrModelAPI
        self.analysisModelAPI = analysisModelAPI
        self.mistakeValueModelAPI = mistakeValueModelAPI
        self.baiduEducation = baiduEducation
    }

    public var resolvedProcessingMode: ProcessingMode { processingMode ?? .local }
    public var resolvedOCRProvider: OCRProviderKind { ocrProvider ?? .appleVision }
    public var resolvedAnalysisProvider: AnalysisProviderKind {
        analysisProvider ?? (enhancedAnalysisEnabled ? .appleFoundationModels : .localRules)
    }
    public var resolvedMistakeValueProvider: MistakeValueProviderKind { mistakeValueProvider ?? .localHeuristic }
}

public struct IntelligenceConfiguration: Codable, Sendable, Equatable {
    public let recognition: RecognitionOptions
    public let analysis: AnalysisOptions
    public let value: ValueAnalysisOptions?

    public init(recognition: RecognitionOptions, analysis: AnalysisOptions, value: ValueAnalysisOptions? = nil) {
        self.recognition = recognition
        self.analysis = analysis
        self.value = value
    }
}

public struct StorageConfiguration: Codable, Sendable, Equatable {
    public let rootDirectory: URL
    public let inMemory: Bool
    public let excludeFromBackup: Bool
    public let protection: DataProtection

    public init(rootDirectory: URL, inMemory: Bool, excludeFromBackup: Bool, protection: DataProtection) {
        self.rootDirectory = rootDirectory
        self.inMemory = inMemory
        self.excludeFromBackup = excludeFromBackup
        self.protection = protection
    }
}

/// Production defaults are maxBatchSize 20 and maxConcurrentJobs 1.
public struct WorkflowConfiguration: Codable, Sendable, Equatable {
    public let maxBatchSize: Int
    public let maxConcurrentJobs: Int
    public let initialSettings: AppSettings

    public init(maxBatchSize: Int, maxConcurrentJobs: Int, initialSettings: AppSettings) {
        self.maxBatchSize = maxBatchSize
        self.maxConcurrentJobs = maxConcurrentJobs
        self.initialSettings = initialSettings
    }
}

public struct PDFExportConfiguration: Codable, Sendable, Equatable {
    public let temporaryDirectory: URL
    public let fileLifetimeSeconds: Double

    public init(temporaryDirectory: URL, fileLifetimeSeconds: Double) {
        self.temporaryDirectory = temporaryDirectory
        self.fileLifetimeSeconds = fileLifetimeSeconds
    }
}
