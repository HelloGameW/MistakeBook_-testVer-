// Frozen contract 1.0.0. Changes require coordinated contract migration.
import Foundation

public enum ReviewState: String, Codable, Sendable, Equatable, CaseIterable {
    case new
    case reviewing
    case mastered
}

public enum ReviewReason: String, Codable, Sendable, Equatable, CaseIterable {
    case lowConfidence
    case unknownRegion
    case unclassified
    case modelUnavailable
    case ocrFailed
    case emptyText
    case staleAnalysis
    case staleClassification
}

public enum OperationState: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case success
    case unavailable
    case failed
    case stale
}

public struct OperationOutcome: Codable, Sendable, Equatable {
    public let state: OperationState
    public let error: AppError?
    public let inputContentRevision: Int

    public init(state: OperationState, error: AppError?, inputContentRevision: Int) {
        self.state = state
        self.error = error
        self.inputContentRevision = inputContentRevision
    }
}

public struct RecordProcessingStatus: Codable, Sendable, Equatable {
    public let ocr: OperationOutcome
    public let analysis: OperationOutcome
    public let classification: OperationOutcome

    public init(ocr: OperationOutcome, analysis: OperationOutcome, classification: OperationOutcome) {
        self.ocr = ocr
        self.analysis = analysis
        self.classification = classification
    }
}

public struct MistakeRecord: Codable, Sendable, Equatable {
    public let id: UUID
    public let schemaVersion: Int
    public let recordRevision: Int
    public let contentRevision: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let sourceRegions: [SourceRegion]
    public let ocrLines: [OCRLine]
    public let stem: EditableText
    public let studentWork: EditableText
    public let referenceAnswer: EditableText?
    public let referenceAnswerSource: ReferenceAnswerSource?
    public let analysisResult: AnalysisResult?
    public let classification: ClassificationResult
    public let notes: String
    public let tags: [String]
    public let reviewState: ReviewState
    public let reviewRequired: Bool
    public let reviewReasons: [ReviewReason]
    public let processingStatus: RecordProcessingStatus

    public init(id: UUID, schemaVersion: Int, recordRevision: Int, contentRevision: Int, createdAt: Date, updatedAt: Date, sourceRegions: [SourceRegion], ocrLines: [OCRLine], stem: EditableText, studentWork: EditableText, referenceAnswer: EditableText?, referenceAnswerSource: ReferenceAnswerSource?, analysisResult: AnalysisResult?, classification: ClassificationResult, notes: String, tags: [String], reviewState: ReviewState, reviewRequired: Bool, reviewReasons: [ReviewReason], processingStatus: RecordProcessingStatus) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.recordRevision = recordRevision
        self.contentRevision = contentRevision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceRegions = sourceRegions
        self.ocrLines = ocrLines
        self.stem = stem
        self.studentWork = studentWork
        self.referenceAnswer = referenceAnswer
        self.referenceAnswerSource = referenceAnswerSource
        self.analysisResult = analysisResult
        self.classification = classification
        self.notes = notes
        self.tags = tags
        self.reviewState = reviewState
        self.reviewRequired = reviewRequired
        self.reviewReasons = reviewReasons
        self.processingStatus = processingStatus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        try ContractSchema.requireSupported(version)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.recordRevision = try c.decode(Int.self, forKey: .recordRevision)
        self.contentRevision = try c.decode(Int.self, forKey: .contentRevision)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.sourceRegions = try c.decode([SourceRegion].self, forKey: .sourceRegions)
        self.ocrLines = try c.decode([OCRLine].self, forKey: .ocrLines)
        self.stem = try c.decode(EditableText.self, forKey: .stem)
        self.studentWork = try c.decode(EditableText.self, forKey: .studentWork)
        self.referenceAnswer = try c.decodeIfPresent(EditableText.self, forKey: .referenceAnswer)
        self.referenceAnswerSource = try c.decodeIfPresent(ReferenceAnswerSource.self, forKey: .referenceAnswerSource)
        self.analysisResult = try c.decodeIfPresent(AnalysisResult.self, forKey: .analysisResult)
        self.classification = try c.decode(ClassificationResult.self, forKey: .classification)
        self.notes = try c.decode(String.self, forKey: .notes)
        self.tags = try c.decode([String].self, forKey: .tags)
        self.reviewState = try c.decode(ReviewState.self, forKey: .reviewState)
        self.reviewRequired = try c.decode(Bool.self, forKey: .reviewRequired)
        self.reviewReasons = try c.decode([ReviewReason].self, forKey: .reviewReasons)
        self.processingStatus = try c.decode(RecordProcessingStatus.self, forKey: .processingStatus)
    }
}

public struct RecordContentSnapshot: Codable, Sendable, Equatable {
    public let recordID: UUID
    public let contentRevision: Int
    public let sourceRegions: [SourceRegion]
    public let ocrLines: [OCRLine]
    public let stem: EditableText
    public let studentWork: EditableText
    public let referenceAnswer: EditableText?
    public let referenceAnswerSource: ReferenceAnswerSource?

    public init(recordID: UUID, contentRevision: Int, sourceRegions: [SourceRegion], ocrLines: [OCRLine], stem: EditableText, studentWork: EditableText, referenceAnswer: EditableText?, referenceAnswerSource: ReferenceAnswerSource?) {
        self.recordID = recordID
        self.contentRevision = contentRevision
        self.sourceRegions = sourceRegions
        self.ocrLines = ocrLines
        self.stem = stem
        self.studentWork = studentWork
        self.referenceAnswer = referenceAnswer
        self.referenceAnswerSource = referenceAnswerSource
    }
}

public struct HypothesisDecision: Codable, Sendable, Equatable {
    public let hypothesisID: UUID
    public let inputContentRevision: Int
    public let decision: UserDecision

    public init(hypothesisID: UUID, inputContentRevision: Int, decision: UserDecision) {
        self.hypothesisID = hypothesisID
        self.inputContentRevision = inputContentRevision
        self.decision = decision
    }
}

public struct RecordEditPatch: Codable, Sendable, Equatable {
    public let expectedRecordRevision: Int
    public let stem: FieldChange<EditableText>
    public let studentWork: FieldChange<EditableText>
    public let referenceAnswer: FieldChange<EditableText?>
    public let referenceAnswerSource: FieldChange<ReferenceAnswerSource?>
    public let sourceRegions: FieldChange<[SourceRegion]>
    public let notes: FieldChange<String>
    public let tags: FieldChange<[String]>
    public let hypothesisDecisions: [HypothesisDecision]

    public init(expectedRecordRevision: Int, stem: FieldChange<EditableText>, studentWork: FieldChange<EditableText>, referenceAnswer: FieldChange<EditableText?>, referenceAnswerSource: FieldChange<ReferenceAnswerSource?>, sourceRegions: FieldChange<[SourceRegion]>, notes: FieldChange<String>, tags: FieldChange<[String]>, hypothesisDecisions: [HypothesisDecision]) {
        self.expectedRecordRevision = expectedRecordRevision
        self.stem = stem
        self.studentWork = studentWork
        self.referenceAnswer = referenceAnswer
        self.referenceAnswerSource = referenceAnswerSource
        self.sourceRegions = sourceRegions
        self.notes = notes
        self.tags = tags
        self.hypothesisDecisions = hypothesisDecisions
    }
}

public struct ManualRecordDraft: Codable, Sendable, Equatable {
    public let stem: String
    public let studentWork: String
    public let referenceAnswer: String?
    public let notes: String
    public let tags: [String]

    public init(stem: String, studentWork: String, referenceAnswer: String?, notes: String, tags: [String]) {
        self.stem = stem
        self.studentWork = studentWork
        self.referenceAnswer = referenceAnswer
        self.notes = notes
        self.tags = tags
    }
}

