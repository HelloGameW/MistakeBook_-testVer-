import Foundation

/// Schema owned by the optional achievements module. It is intentionally
/// independent from MistakeBook's frozen Contracts schema.
public enum AchievementModule {
    public static let schemaVersion = 1
}

public enum AchievementEventKind: String, Codable, Sendable, Equatable, CaseIterable {
    case recordCreated
    case recordImported
    case recordReviewed
    case recordMastered
    case recordClassified
    case analysisConfirmed
    case studyActivity
}

/// A small, replay-safe fact emitted by the host application. The host owns
/// the meaning of IDs; this module only requires that an ID is stable when an
/// event is retried.
public struct AchievementEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let occurredAt: Date
    public let kind: AchievementEventKind
    public let recordID: UUID?
    public let subjectID: String?
    public let amount: Int

    public init(id: String, occurredAt: Date, kind: AchievementEventKind,
                recordID: UUID? = nil, subjectID: String? = nil, amount: Int = 1) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.recordID = recordID
        self.subjectID = subjectID
        self.amount = max(0, amount)
    }

    /// Stable IDs make a producer retry harmless. Do not use a random UUID
    /// for a fact that can be emitted again after a stream reconnects.
    public static func stableID(kind: AchievementEventKind, primaryID: String,
                                revision: Int? = nil) -> String {
        var parts = [kind.rawValue, primaryID]
        if let revision { parts.append(String(revision)) }
        return parts.joined(separator: ":")
    }

    public static func recordCreated(recordID: UUID, occurredAt: Date,
                                     subjectID: String? = nil) -> AchievementEvent {
        AchievementEvent(id: stableID(kind: .recordCreated, primaryID: recordID.uuidString),
                         occurredAt: occurredAt, kind: .recordCreated,
                         recordID: recordID, subjectID: subjectID)
    }

    public static func recordReviewed(recordID: UUID, revision: Int,
                                      occurredAt: Date, subjectID: String? = nil) -> AchievementEvent {
        AchievementEvent(id: stableID(kind: .recordReviewed, primaryID: recordID.uuidString,
                                      revision: revision), occurredAt: occurredAt,
                         kind: .recordReviewed, recordID: recordID,
                         subjectID: subjectID)
    }

    public static func recordMastered(recordID: UUID, revision: Int,
                                      occurredAt: Date, subjectID: String? = nil) -> AchievementEvent {
        AchievementEvent(id: stableID(kind: .recordMastered, primaryID: recordID.uuidString,
                                      revision: revision), occurredAt: occurredAt,
                         kind: .recordMastered, recordID: recordID,
                         subjectID: subjectID)
    }

    public static func recordClassified(recordID: UUID, revision: Int,
                                        occurredAt: Date, subjectID: String? = nil) -> AchievementEvent {
        AchievementEvent(id: stableID(kind: .recordClassified, primaryID: recordID.uuidString,
                                      revision: revision), occurredAt: occurredAt,
                         kind: .recordClassified, recordID: recordID,
                         subjectID: subjectID)
    }

    public static func analysisConfirmed(recordID: UUID, revision: Int,
                                         occurredAt: Date, amount: Int = 1,
                                         subjectID: String? = nil) -> AchievementEvent {
        AchievementEvent(id: stableID(kind: .analysisConfirmed, primaryID: recordID.uuidString,
                                      revision: revision), occurredAt: occurredAt,
                         kind: .analysisConfirmed, recordID: recordID,
                         subjectID: subjectID, amount: amount)
    }

    public static func imported(batchID: UUID, occurredAt: Date, amount: Int) -> AchievementEvent {
        AchievementEvent(id: stableID(kind: .recordImported, primaryID: batchID.uuidString),
                         occurredAt: occurredAt, kind: .recordImported, amount: amount)
    }
}

public enum AchievementCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case organizing
    case reviewing
    case mastery
    case reflection
    case consistency
    case exploration
}

/// Built-in requirements are Codable so a future catalog can move from Swift
/// source to a bundled JSON manifest without changing persisted state.
public enum AchievementRequirement: Codable, Sendable, Equatable {
    case eventCount(kind: AchievementEventKind, target: Int)
    case uniqueRecordCount(kind: AchievementEventKind, target: Int)
    case uniqueSubjectCount(target: Int)
    case activeDayStreak(target: Int)

    public var target: Int {
        switch self {
        case .eventCount(_, let target), .uniqueRecordCount(_, let target),
             .uniqueSubjectCount(let target), .activeDayStreak(let target):
            return target
        }
    }
}

public struct AchievementDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let version: Int
    public let category: AchievementCategory
    public let title: String
    public let detail: String
    public let iconSystemName: String
    public let requirement: AchievementRequirement

    public init(id: String, version: Int = 1, category: AchievementCategory,
                title: String, detail: String, iconSystemName: String,
                requirement: AchievementRequirement) {
        self.id = id
        self.version = version
        self.category = category
        self.title = title
        self.detail = detail
        self.iconSystemName = iconSystemName
        self.requirement = requirement
    }
}

public struct AchievementStatistics: Codable, Sendable, Equatable {
    public let eventCounts: [String: Int]
    public let uniqueRecordIDsByKind: [String: [UUID]]
    public let uniqueSubjectIDs: [String]
    public let activeDays: [String]
    public let firstEventAt: Date?
    public let lastEventAt: Date?

    public init(eventCounts: [String: Int] = [:],
                uniqueRecordIDsByKind: [String: [UUID]] = [:],
                uniqueSubjectIDs: [String] = [], activeDays: [String] = [],
                firstEventAt: Date? = nil, lastEventAt: Date? = nil) {
        self.eventCounts = eventCounts
        self.uniqueRecordIDsByKind = uniqueRecordIDsByKind
        self.uniqueSubjectIDs = uniqueSubjectIDs
        self.activeDays = activeDays
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
    }

    public func eventCount(for kind: AchievementEventKind) -> Int {
        eventCounts[kind.rawValue] ?? 0
    }

    public func uniqueRecordCount(for kind: AchievementEventKind) -> Int {
        uniqueRecordIDsByKind[kind.rawValue]?.count ?? 0
    }

    public var uniqueSubjectCount: Int { uniqueSubjectIDs.count }
    public var activeDayCount: Int { activeDays.count }

    public func progress(for requirement: AchievementRequirement, asOf date: Date,
                         timeZoneIdentifier: String) -> Int {
        switch requirement {
        case .eventCount(let kind, _): return eventCount(for: kind)
        case .uniqueRecordCount(let kind, _): return uniqueRecordCount(for: kind)
        case .uniqueSubjectCount: return uniqueSubjectCount
        case .activeDayStreak: return currentStreak(asOf: date, timeZoneIdentifier: timeZoneIdentifier)
        }
    }

    /// A streak remains active on the following calendar day, so yesterday is
    /// also accepted as the latest active day. The persisted day keys are
    /// derived using the configured user timezone.
    public func currentStreak(asOf date: Date, timeZoneIdentifier: String) -> Int {
        let calendar = AchievementCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let active = Set(activeDays)
        let today = calendar.startOfDay(date)
        let todayKey = calendar.dayKey(today)
        let yesterday = calendar.date(byAddingDays: -1, to: today)
        let start: Date
        if active.contains(todayKey) {
            start = today
        } else if active.contains(calendar.dayKey(yesterday)) {
            start = yesterday
        } else {
            return 0
        }

        var cursor = start
        var count = 0
        while active.contains(calendar.dayKey(cursor)) {
            count += 1
            cursor = calendar.date(byAddingDays: -1, to: cursor)
        }
        return count
    }

    func adding(_ event: AchievementEvent, timeZoneIdentifier: String) -> AchievementStatistics {
        guard event.amount > 0 else { return self }
        var counts = eventCounts
        counts[event.kind.rawValue] = Self.saturatingAdd(counts[event.kind.rawValue] ?? 0, event.amount)

        var records = uniqueRecordIDsByKind
        if let recordID = event.recordID {
            var ids = records[event.kind.rawValue] ?? []
            if !ids.contains(recordID) { ids.append(recordID); ids.sort { $0.uuidString < $1.uuidString } }
            records[event.kind.rawValue] = ids
        }

        var subjects = Set(uniqueSubjectIDs)
        if let subjectID = event.subjectID, !subjectID.isEmpty { subjects.insert(subjectID) }

        var days = Set(activeDays)
        days.insert(AchievementCalendar(timeZoneIdentifier: timeZoneIdentifier).dayKey(event.occurredAt))

        let first = [firstEventAt, event.occurredAt].compactMap { $0 }.min()
        let last = [lastEventAt, event.occurredAt].compactMap { $0 }.max()
        return AchievementStatistics(eventCounts: counts,
                                     uniqueRecordIDsByKind: records,
                                     uniqueSubjectIDs: subjects.sorted(),
                                     activeDays: days.sorted(),
                                     firstEventAt: first, lastEventAt: last)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : value
    }
}

public struct AchievementState: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let statistics: AchievementStatistics
    public let unlockedAt: [String: Date]
    public let processedEventIDs: [String]
    public let lastProcessedAt: Date?

    public init(schemaVersion: Int = AchievementModule.schemaVersion,
                statistics: AchievementStatistics = AchievementStatistics(),
                unlockedAt: [String: Date] = [:], processedEventIDs: [String] = [],
                lastProcessedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.statistics = statistics
        self.unlockedAt = unlockedAt
        self.processedEventIDs = processedEventIDs
        self.lastProcessedAt = lastProcessedAt
    }

    public static let empty = AchievementState()
}

public struct AchievementProgress: Codable, Sendable, Equatable, Identifiable {
    public let definition: AchievementDefinition
    public let currentValue: Int
    public let targetValue: Int
    public let isUnlocked: Bool
    public let unlockedAt: Date?

    public var id: String { definition.id }

    public init(definition: AchievementDefinition, currentValue: Int,
                targetValue: Int, isUnlocked: Bool, unlockedAt: Date?) {
        self.definition = definition
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.isUnlocked = isUnlocked
        self.unlockedAt = unlockedAt
    }
}

public struct AchievementDashboard: Codable, Sendable, Equatable {
    public let moduleSchemaVersion: Int
    public let statistics: AchievementStatistics
    public let progress: [AchievementProgress]

    public init(moduleSchemaVersion: Int = AchievementModule.schemaVersion,
                statistics: AchievementStatistics, progress: [AchievementProgress]) {
        self.moduleSchemaVersion = moduleSchemaVersion
        self.statistics = statistics
        self.progress = progress
    }

    public var unlockedCount: Int { progress.filter(\.isUnlocked).count }
}

public struct AchievementUpdate: Codable, Sendable, Equatable {
    public let acceptedEventCount: Int
    public let newlyUnlocked: [AchievementProgress]
    public let dashboard: AchievementDashboard

    public init(acceptedEventCount: Int, newlyUnlocked: [AchievementProgress],
                dashboard: AchievementDashboard) {
        self.acceptedEventCount = acceptedEventCount
        self.newlyUnlocked = newlyUnlocked
        self.dashboard = dashboard
    }
}

public struct AchievementConfiguration: Codable, Sendable, Equatable {
    public let timeZoneIdentifier: String

    public init(timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static var current: AchievementConfiguration { AchievementConfiguration() }
}

public protocol AchievementClock: Sendable {
    func now() -> Date
}

public struct SystemAchievementClock: AchievementClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Useful for deterministic host tests and previews; production can keep the
/// default SystemAchievementClock.
public struct FixedAchievementClock: AchievementClock {
    public let date: Date
    public init(date: Date) { self.date = date }
    public func now() -> Date { date }
}

fileprivate struct AchievementCalendar: Sendable {
    private let calendar: Calendar

    init(timeZoneIdentifier: String) {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        calendar = value
    }

    func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    func date(byAddingDays days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    func dayKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0,
                      components.month ?? 0, components.day ?? 0)
    }
}
