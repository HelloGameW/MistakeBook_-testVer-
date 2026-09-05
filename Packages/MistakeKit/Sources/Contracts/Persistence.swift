// Frozen contract 1.0.0. Changes require coordinated contract migration.
import Foundation

/// nil expectedRecordRevision = create only; conflicts never silently overwrite.
public struct RecordWrite: Codable, Sendable, Equatable {
    public let record: MistakeRecord
    public let expectedRecordRevision: Int?
    public let expectedContentRevision: Int?
    public let preserveConfirmedClassification: Bool

    public init(record: MistakeRecord, expectedRecordRevision: Int?, expectedContentRevision: Int?, preserveConfirmedClassification: Bool) {
        self.record = record
        self.expectedRecordRevision = expectedRecordRevision
        self.expectedContentRevision = expectedContentRevision
        self.preserveConfirmedClassification = preserveConfirmedClassification
    }
}

public struct RecordTombstone: Codable, Sendable, Equatable {
    public let recordID: UUID
    public let deletedAt: Date
    public let lastRecordRevision: Int

    public init(recordID: UUID, deletedAt: Date, lastRecordRevision: Int) {
        self.recordID = recordID
        self.deletedAt = deletedAt
        self.lastRecordRevision = lastRecordRevision
    }
}

public struct RegionUndoState: Codable, Sendable, Equatable {
    public let token: RegionUndoToken
    public let beforeRecords: [MistakeRecord]
    public let afterVersions: [RecordVersion]
    public let beforeJobs: [ProcessingJob]
    public let createdRecordIDs: [UUID]

    public init(token: RegionUndoToken, beforeRecords: [MistakeRecord], afterVersions: [RecordVersion], beforeJobs: [ProcessingJob], createdRecordIDs: [UUID]) {
        self.token = token
        self.beforeRecords = beforeRecords
        self.afterVersions = afterVersions
        self.beforeJobs = beforeJobs
        self.createdRecordIDs = createdRecordIDs
    }
}

/// Atomic database transaction, including job relationships and tombstones. restoreRecordIDs is for explicit undo only.
public struct RepositoryTransaction: Codable, Sendable, Equatable {
    public let id: UUID
    public let recordWrites: [RecordWrite]
    public let deleteRecordIDs: [UUID]
    public let expectedDeletedVersions: [RecordVersion]
    public let restoreRecordIDs: [UUID]
    public let jobs: [ProcessingJob]
    public let batches: [ImportBatch]
    public let expectedJobStates: [JobStateGuard]
    public let tombstones: [RecordTombstone]
    public let regionUndoState: RegionUndoState?

    public init(id: UUID, recordWrites: [RecordWrite], deleteRecordIDs: [UUID], expectedDeletedVersions: [RecordVersion], restoreRecordIDs: [UUID], jobs: [ProcessingJob], batches: [ImportBatch], expectedJobStates: [JobStateGuard], tombstones: [RecordTombstone], regionUndoState: RegionUndoState?) {
        self.id = id
        self.recordWrites = recordWrites
        self.deleteRecordIDs = deleteRecordIDs
        self.expectedDeletedVersions = expectedDeletedVersions
        self.restoreRecordIDs = restoreRecordIDs
        self.jobs = jobs
        self.batches = batches
        self.expectedJobStates = expectedJobStates
        self.tombstones = tombstones
        self.regionUndoState = regionUndoState
    }
}

public struct JobStateGuard: Codable, Sendable, Equatable {
    public let jobID: UUID
    public let expectedState: JobState
    public let expectedAttempt: Int

    public init(jobID: UUID, expectedState: JobState, expectedAttempt: Int) {
        self.jobID = jobID
        self.expectedState = expectedState
        self.expectedAttempt = expectedAttempt
    }
}

public struct RepositoryCommit: Codable, Sendable, Equatable {
    public let transactionID: UUID
    public let records: [MistakeRecord]

    public init(transactionID: UUID, records: [MistakeRecord]) {
        self.transactionID = transactionID
        self.records = records
    }
}

