// Frozen contract 1.0.0. Changes require coordinated contract migration.
import Foundation

public enum JobState: String, Codable, Sendable, Equatable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public enum JobStage: String, Codable, Sendable, Equatable, CaseIterable {
    case preprocessing
    case recognizing
    case segmenting
    case analyzing
    case classifying
    case saving
}

public enum DuplicatePolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case skipExisting
    case keepCopy
}

public enum RecordSort: String, Codable, Sendable, Equatable, CaseIterable {
    case updatedNewest
    case createdOldest
}

public enum RecordEventKind: String, Codable, Sendable, Equatable, CaseIterable {
    case initial
    case upserted
    case deleted
    case restored
    case cleared
    case failed
}

public struct ProcessingJob: Codable, Sendable, Equatable {
    public let id: UUID
    public let batchID: UUID
    public let assetID: UUID
    public let producedRecordIDs: [UUID]
    public let state: JobState
    public let stage: JobStage
    public let attempt: Int
    public let completedUnits: Int
    public let totalUnits: Int?
    public let error: AppError?
    public let inputContentRevision: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?

    public init(id: UUID, batchID: UUID, assetID: UUID, producedRecordIDs: [UUID], state: JobState, stage: JobStage, attempt: Int, completedUnits: Int, totalUnits: Int?, error: AppError?, inputContentRevision: Int, createdAt: Date, updatedAt: Date, startedAt: Date?, finishedAt: Date?) {
        self.id = id
        self.batchID = batchID
        self.assetID = assetID
        self.producedRecordIDs = producedRecordIDs
        self.state = state
        self.stage = stage
        self.attempt = attempt
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.error = error
        self.inputContentRevision = inputContentRevision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct ImportBatch: Codable, Sendable, Equatable {
    public let id: UUID
    public let jobIDs: [UUID]
    public let createdAt: Date
    public let updatedAt: Date
    public let cancelledAt: Date?
    public let warnings: [ServiceWarning]

    public init(id: UUID, jobIDs: [UUID], createdAt: Date, updatedAt: Date, cancelledAt: Date?, warnings: [ServiceWarning]) {
        self.id = id
        self.jobIDs = jobIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cancelledAt = cancelledAt
        self.warnings = warnings
    }
}

public struct BatchEvent: Codable, Sendable, Equatable {
    public let batch: ImportBatch
    public let jobs: [ProcessingJob]
    public let isTerminal: Bool
    public let error: AppError?

    public init(batch: ImportBatch, jobs: [ProcessingJob], isTerminal: Bool, error: AppError?) {
        self.batch = batch
        self.jobs = jobs
        self.isTerminal = isTerminal
        self.error = error
    }
}

public struct ImportOptions: Codable, Sendable, Equatable {
    public let duplicatePolicy: DuplicatePolicy
    public let recognition: RecognitionOptions

    public init(duplicatePolicy: DuplicatePolicy, recognition: RecognitionOptions) {
        self.duplicatePolicy = duplicatePolicy
        self.recognition = recognition
    }
}

public struct RecordQuery: Codable, Sendable, Equatable {
    public let text: String
    public let subjectID: String?
    public let taxonomyNodeID: String?
    public let includeDescendants: Bool
    public let reviewStates: [ReviewState]
    public let reviewRequiredOnly: Bool
    public let includeDeleted: Bool
    public let sort: RecordSort

    public init(text: String, subjectID: String?, taxonomyNodeID: String?, includeDescendants: Bool, reviewStates: [ReviewState], reviewRequiredOnly: Bool, includeDeleted: Bool, sort: RecordSort) {
        self.text = text
        self.subjectID = subjectID
        self.taxonomyNodeID = taxonomyNodeID
        self.includeDescendants = includeDescendants
        self.reviewStates = reviewStates
        self.reviewRequiredOnly = reviewRequiredOnly
        self.includeDeleted = includeDeleted
        self.sort = sort
    }
}

public struct PageRequest: Codable, Sendable, Equatable {
    public let cursor: String?
    public let limit: Int

    public init(cursor: String?, limit: Int) {
        self.cursor = cursor
        self.limit = limit
    }
}

public struct RecordPage: Codable, Sendable, Equatable {
    public let records: [MistakeRecord]
    public let nextCursor: String?

    public init(records: [MistakeRecord], nextCursor: String?) {
        self.records = records
        self.nextCursor = nextCursor
    }
}

public struct RecordEvent: Codable, Sendable, Equatable {
    public let kind: RecordEventKind
    public let recordID: UUID?
    public let record: MistakeRecord?
    public let error: AppError?

    public init(kind: RecordEventKind, recordID: UUID?, record: MistakeRecord?, error: AppError?) {
        self.kind = kind
        self.recordID = recordID
        self.record = record
        self.error = error
    }
}

public struct RecordVersion: Codable, Sendable, Equatable {
    public let recordID: UUID
    public let recordRevision: Int
    public let contentRevision: Int

    public init(recordID: UUID, recordRevision: Int, contentRevision: Int) {
        self.recordID = recordID
        self.recordRevision = recordRevision
        self.contentRevision = contentRevision
    }
}

/// nil recordID creates a draft; only listed replacedRecordIDs may be removed.
public struct RegionAssignment: Codable, Sendable, Equatable {
    public let recordID: UUID?
    public let regions: [SourceRegion]
    public let order: Int

    public init(recordID: UUID?, regions: [SourceRegion], order: Int) {
        self.recordID = recordID
        self.regions = regions
        self.order = order
    }
}

/// Supports cross-page manual merge; all record/job changes are atomic.
public struct RegionEditRequest: Codable, Sendable, Equatable {
    public let jobIDs: [UUID]
    public let replacedRecordIDs: [UUID]
    public let expectedVersions: [RecordVersion]
    public let assignments: [RegionAssignment]

    public init(jobIDs: [UUID], replacedRecordIDs: [UUID], expectedVersions: [RecordVersion], assignments: [RegionAssignment]) {
        self.jobIDs = jobIDs
        self.replacedRecordIDs = replacedRecordIDs
        self.expectedVersions = expectedVersions
        self.assignments = assignments
    }
}

public struct RegionUndoToken: Codable, Sendable, Equatable {
    public let id: UUID
    public let expiresAt: Date?

    public init(id: UUID, expiresAt: Date?) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

public struct RegionEditResult: Codable, Sendable, Equatable {
    public let records: [MistakeRecord]
    public let removedRecordIDs: [UUID]
    public let undoToken: RegionUndoToken

    public init(records: [MistakeRecord], removedRecordIDs: [UUID], undoToken: RegionUndoToken) {
        self.records = records
        self.removedRecordIDs = removedRecordIDs
        self.undoToken = undoToken
    }
}

public struct RecordImageTransformRequest: Codable, Sendable, Equatable {
    public let recordID: UUID
    public let expectedRecordRevision: Int
    public let transform: ImageTransformRequest

    public init(recordID: UUID, expectedRecordRevision: Int, transform: ImageTransformRequest) {
        self.recordID = recordID
        self.expectedRecordRevision = expectedRecordRevision
        self.transform = transform
    }
}

public struct RecordImageTransformResult: Codable, Sendable, Equatable {
    public let record: MistakeRecord
    public let transform: ImageTransformResult

    public init(record: MistakeRecord, transform: ImageTransformResult) {
        self.record = record
        self.transform = transform
    }
}

public struct DeletionToken: Codable, Sendable, Equatable {
    public let id: UUID
    public let recordIDs: [UUID]
    public let createdAt: Date
    public let expiresAt: Date?

    public init(id: UUID, recordIDs: [UUID], createdAt: Date, expiresAt: Date?) {
        self.id = id
        self.recordIDs = recordIDs
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct DataInventory: Codable, Sendable, Equatable {
    public let recordCount: Int
    public let assetCount: Int
    public let activeJobCount: Int

    public init(recordCount: Int, assetCount: Int, activeJobCount: Int) {
        self.recordCount = recordCount
        self.assetCount = assetCount
        self.activeJobCount = activeJobCount
    }
}

/// Issued by prepareClearAllData; one-use token submitted only after UI confirmation.
public struct ClearDataConfirmation: Codable, Sendable, Equatable {
    public let id: UUID
    public let inventory: DataInventory
    public let expiresAt: Date

    public init(id: UUID, inventory: DataInventory, expiresAt: Date) {
        self.id = id
        self.inventory = inventory
        self.expiresAt = expiresAt
    }
}

