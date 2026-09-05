import Foundation

public enum MistakeValueLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case low
    case medium
    case high
}

/// Individual model/heuristic judgments remain inspectable. `overallScore` is
/// calculated by production code from these dimensions rather than trusted as
/// an opaque model-provided number.
public struct MistakeValueDimensions: Codable, Sendable, Equatable {
    public let knowledgeValue: Double
    public let representativeness: Double
    public let recurrenceRisk: Double
    public let reasoningValue: Double
    public let examValue: Double
    public let reviewPriority: Double

    public init(knowledgeValue: Double, representativeness: Double, recurrenceRisk: Double,
                reasoningValue: Double, examValue: Double, reviewPriority: Double) {
        self.knowledgeValue = knowledgeValue
        self.representativeness = representativeness
        self.recurrenceRisk = recurrenceRisk
        self.reasoningValue = reasoningValue
        self.examValue = examValue
        self.reviewPriority = reviewPriority
    }
}

public struct MistakeValueResult: Codable, Sendable, Equatable {
    public let dimensions: MistakeValueDimensions
    public let overallScore: Double
    public let level: MistakeValueLevel
    public let reason: String
    public let engineID: String
    public let engineVersion: String
    public let inputContentRevision: Int

    public init(dimensions: MistakeValueDimensions, overallScore: Double, level: MistakeValueLevel,
                reason: String, engineID: String, engineVersion: String, inputContentRevision: Int) {
        self.dimensions = dimensions
        self.overallScore = overallScore
        self.level = level
        self.reason = reason
        self.engineID = engineID
        self.engineVersion = engineVersion
        self.inputContentRevision = inputContentRevision
    }
}

public struct ValueAnalysisOptions: Codable, Sendable, Equatable {
    public let processingMode: ProcessingMode?
    public let provider: MistakeValueProviderKind
    public let modelAPI: ModelAPIConfiguration?
    public let language: String
    public let timeoutSeconds: Double

    public init(processingMode: ProcessingMode? = nil, provider: MistakeValueProviderKind = .localHeuristic, modelAPI: ModelAPIConfiguration? = nil,
                language: String = "zh-Hans", timeoutSeconds: Double = 20) {
        self.processingMode = processingMode
        self.provider = provider
        self.modelAPI = modelAPI
        self.language = language
        self.timeoutSeconds = timeoutSeconds
    }
}
