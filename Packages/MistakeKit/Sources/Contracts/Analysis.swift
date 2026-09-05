// Contract 1.1.0. Includes optional API analysis providers.
import Foundation

public enum AnalysisStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case hypotheses
    case insufficientEvidence
    case unavailable
}

public enum HypothesisKind: String, Codable, Sendable, Equatable, CaseIterable {
    // 1.0 compatibility cases
    case recognitionConcern
    case possibleSolutionError
    case referenceDifference
    // 1.1 structured mistake-cause taxonomy
    case reading
    case knowledge
    case confusion
    case strategy
    case reasoning
    case procedure
    case expression
}

public enum Certainty: String, Codable, Sendable, Equatable, CaseIterable {
    case tentative
    case needsConfirmation
}

public enum UserDecision: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case accepted
    case rejected
}

public enum EvidenceSource: String, Codable, Sendable, Equatable, CaseIterable {
    case student
    case reference
    case teacher
}

public struct Evidence: Codable, Sendable, Equatable {
    public let regionID: UUID
    public let lineID: UUID?
    public let quote: String?
    public let evidenceSource: EvidenceSource

    public init(regionID: UUID, lineID: UUID?, quote: String?, evidenceSource: EvidenceSource) {
        self.regionID = regionID
        self.lineID = lineID
        self.quote = quote
        self.evidenceSource = evidenceSource
    }
}

public struct ReferenceAnswerSource: Codable, Sendable, Equatable {
    public let provenance: TextProvenance
    public let label: String
    public let regionIDs: [UUID]

    public init(provenance: TextProvenance, label: String, regionIDs: [UUID]) {
        self.provenance = provenance
        self.label = label
        self.regionIDs = regionIDs
    }
}

public struct Hypothesis: Codable, Sendable, Equatable {
    public let id: UUID
    public let kind: HypothesisKind
    public let summary: String
    public let evidence: [Evidence]
    public let reason: String
    public let nextAction: String
    public let certainty: Certainty
    public let userDecision: UserDecision

    public init(id: UUID, kind: HypothesisKind, summary: String, evidence: [Evidence], reason: String, nextAction: String, certainty: Certainty, userDecision: UserDecision) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.evidence = evidence
        self.reason = reason
        self.nextAction = nextAction
        self.certainty = certainty
        self.userDecision = userDecision
    }
}

public struct AnalysisResult: Codable, Sendable, Equatable {
    public let status: AnalysisStatus
    public let hypotheses: [Hypothesis]
    public let limitations: [String]
    public let engineID: String
    public let engineVersion: String
    public let inputContentRevision: Int
    public let referenceAnswerSource: ReferenceAnswerSource?

    public init(status: AnalysisStatus, hypotheses: [Hypothesis], limitations: [String], engineID: String, engineVersion: String, inputContentRevision: Int, referenceAnswerSource: ReferenceAnswerSource?) {
        self.status = status
        self.hypotheses = hypotheses
        self.limitations = limitations
        self.engineID = engineID
        self.engineVersion = engineVersion
        self.inputContentRevision = inputContentRevision
        self.referenceAnswerSource = referenceAnswerSource
    }
}

public struct AnalysisOptions: Codable, Sendable, Equatable {
    public let useEnhancedModel: Bool
    public let language: String
    public let timeoutSeconds: Double
    public let processingMode: ProcessingMode?
    public let provider: AnalysisProviderKind?
    public let modelAPI: ModelAPIConfiguration?

    public init(useEnhancedModel: Bool, language: String, timeoutSeconds: Double,
                processingMode: ProcessingMode? = nil, provider: AnalysisProviderKind? = nil, modelAPI: ModelAPIConfiguration? = nil) {
        self.useEnhancedModel = useEnhancedModel
        self.language = language
        self.timeoutSeconds = timeoutSeconds
        self.processingMode = processingMode
        self.provider = provider
        self.modelAPI = modelAPI
    }
}

