import Foundation

/// Deliberately mirrors only the fields needed by the achievements module.
/// It avoids importing MistakeBook.Contracts and keeps this package removable.
public enum AchievementReviewState: String, Codable, Sendable, Equatable {
    case new
    case reviewing
    case mastered
}

public struct AchievementRecordSnapshot: Codable, Sendable, Equatable {
    public let id: UUID
    public let recordRevision: Int
    public let reviewState: AchievementReviewState
    public let hasConfirmedClassification: Bool
    public let acceptedAnalysisCount: Int
    public let subjectID: String?

    public init(id: UUID, recordRevision: Int, reviewState: AchievementReviewState,
                hasConfirmedClassification: Bool, acceptedAnalysisCount: Int,
                subjectID: String?) {
        self.id = id
        self.recordRevision = recordRevision
        self.reviewState = reviewState
        self.hasConfirmedClassification = hasConfirmedClassification
        self.acceptedAnalysisCount = max(0, acceptedAnalysisCount)
        self.subjectID = subjectID
    }
}

public enum AchievementRecordChangeKind: String, Codable, Sendable, Equatable {
    case initial
    case upserted
    case restored
    case deleted
    case cleared
}

public struct AchievementRecordChange: Codable, Sendable, Equatable {
    public let kind: AchievementRecordChangeKind
    public let recordID: UUID?
    public let record: AchievementRecordSnapshot?
    public let occurredAt: Date

    public init(kind: AchievementRecordChangeKind, recordID: UUID? = nil,
                record: AchievementRecordSnapshot? = nil, occurredAt: Date = Date()) {
        self.kind = kind
        self.recordID = recordID ?? record?.id
        self.record = record
        self.occurredAt = occurredAt
    }
}

/// Converts the existing AppService record stream into facts. `.initial` is
/// treated as a baseline and never awards an achievement for old records.
/// This is important when the module is enabled on an existing installation.
public actor MistakeBookAchievementBridge {
    private let engine: AchievementEngine
    private var knownRecords: [UUID: AchievementRecordSnapshot] = [:]

    public init(engine: AchievementEngine) {
        self.engine = engine
    }

    /// Returns nil for baseline/deletion events or an upsert that emits no new
    /// fact. The host may ignore the returned update in that case.
    public func ingest(_ change: AchievementRecordChange) async throws -> AchievementUpdate? {
        switch change.kind {
        case .initial:
            if let record = change.record { knownRecords[record.id] = record }
            return nil
        case .cleared:
            knownRecords.removeAll()
            return nil
        case .deleted:
            // Keep the previous snapshot so a later restore is not mistaken
            // for a newly created record.
            return nil
        case .upserted, .restored:
            guard let record = change.record else { return nil }
            let previous = knownRecords.updateValue(record, forKey: record.id)
            let events = Self.events(previous: previous, current: record,
                                     changeKind: change.kind, occurredAt: change.occurredAt)
            guard !events.isEmpty else { return nil }
            return try await engine.ingest(events)
        }
    }

    public func resetBaseline() {
        knownRecords.removeAll()
    }

    private static func events(previous: AchievementRecordSnapshot?,
                               current: AchievementRecordSnapshot,
                               changeKind: AchievementRecordChangeKind,
                               occurredAt: Date) -> [AchievementEvent] {
        guard let previous else {
            // A restored record is not a new record. An upsert without a
            // previous snapshot is the normal new-record path.
            guard changeKind == .upserted else { return [] }
            return [AchievementEvent.recordCreated(recordID: current.id, occurredAt: occurredAt,
                                                   subjectID: current.subjectID)]
        }

        var events: [AchievementEvent] = []
        if previous.reviewState != .reviewing && current.reviewState == .reviewing {
            events.append(.recordReviewed(recordID: current.id, revision: current.recordRevision,
                                          occurredAt: occurredAt, subjectID: current.subjectID))
        }
        if previous.reviewState != .mastered && current.reviewState == .mastered {
            events.append(.recordMastered(recordID: current.id, revision: current.recordRevision,
                                          occurredAt: occurredAt, subjectID: current.subjectID))
        }
        if !previous.hasConfirmedClassification && current.hasConfirmedClassification {
            events.append(.recordClassified(recordID: current.id, revision: current.recordRevision,
                                            occurredAt: occurredAt, subjectID: current.subjectID))
        }
        let delta = current.acceptedAnalysisCount - previous.acceptedAnalysisCount
        if delta > 0 {
            events.append(.analysisConfirmed(recordID: current.id, revision: current.recordRevision,
                                             occurredAt: occurredAt, amount: delta,
                                             subjectID: current.subjectID))
        }
        return events
    }
}
