import Foundation

public enum AchievementEngineError: Error, Sendable, Equatable {
    case emptyCatalog
    case duplicateDefinitionID(String)
    case invalidDefinitionID
    case invalidTarget(String)
    case invalidEventID
    case unsupportedSchema(Int)
}

/// Serializes fact ingestion and persists only derived achievement state. It
/// never calls back into the host service, so a storage or catalog failure
/// cannot alter MistakeBook records.
public actor AchievementEngine {
    private let store: any AchievementStateStore
    private let definitions: [AchievementDefinition]
    private let configuration: AchievementConfiguration
    private let clock: any AchievementClock
    private var state = AchievementState.empty
    private var didLoad = false

    public init(definitions: [AchievementDefinition] = DefaultAchievementCatalog.definitions,
                store: any AchievementStateStore,
                configuration: AchievementConfiguration = .current,
                clock: any AchievementClock = SystemAchievementClock()) throws {
        guard !definitions.isEmpty else { throw AchievementEngineError.emptyCatalog }
        var seen = Set<String>()
        for definition in definitions {
            guard !definition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AchievementEngineError.invalidDefinitionID
            }
            guard seen.insert(definition.id).inserted else {
                throw AchievementEngineError.duplicateDefinitionID(definition.id)
            }
            guard definition.requirement.target > 0 else {
                throw AchievementEngineError.invalidTarget(definition.id)
            }
        }
        self.definitions = definitions
        self.store = store
        self.configuration = configuration
        self.clock = clock
    }

    public func dashboard() async throws -> AchievementDashboard {
        try await loadIfNeeded()
        return makeDashboard(state: state)
    }

    /// Ingesting the same event ID more than once returns a no-op update. This
    /// is the main protection against duplicate stream delivery and retries.
    public func ingest(_ event: AchievementEvent) async throws -> AchievementUpdate {
        try await ingest([event])
    }

    public func ingest(_ events: [AchievementEvent]) async throws -> AchievementUpdate {
        try await loadIfNeeded()
        var next = state
        var accepted = 0
        var newlyUnlockedIDs: [String] = []
        let alreadyProcessed = Set(state.processedEventIDs)

        for event in events {
            guard !event.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AchievementEngineError.invalidEventID
            }
            guard !alreadyProcessed.contains(event.id), !next.processedEventIDs.contains(event.id) else {
                continue
            }

            next = AchievementState(
                statistics: next.statistics.adding(event, timeZoneIdentifier: configuration.timeZoneIdentifier),
                unlockedAt: next.unlockedAt,
                processedEventIDs: next.processedEventIDs + [event.id],
                lastProcessedAt: [next.lastProcessedAt, event.occurredAt].compactMap { $0 }.max())
            accepted += 1

            let before = Set(next.unlockedAt.keys)
            var unlocks = next.unlockedAt
            for definition in definitions where !before.contains(definition.id) {
                let value = next.statistics.progress(for: definition.requirement,
                    asOf: clock.now(), timeZoneIdentifier: configuration.timeZoneIdentifier)
                if value >= definition.requirement.target { unlocks[definition.id] = event.occurredAt; newlyUnlockedIDs.append(definition.id) }
            }
            next = AchievementState(schemaVersion: next.schemaVersion, statistics: next.statistics,
                                    unlockedAt: unlocks, processedEventIDs: next.processedEventIDs,
                                    lastProcessedAt: next.lastProcessedAt)
        }

        if accepted > 0 {
            try await store.save(next)
            state = next
        }
        let dashboard = makeDashboard(state: accepted > 0 ? next : state)
        let newlyUnlocked = newlyUnlockedIDs.compactMap { id in dashboard.progress.first { $0.id == id } }
        return AchievementUpdate(acceptedEventCount: accepted, newlyUnlocked: newlyUnlocked,
                                 dashboard: dashboard)
    }

    /// Explicit reset is useful for account deletion or a user-facing reset.
    /// It touches only this module's state file/store.
    public func reset() async throws -> AchievementDashboard {
        try await loadIfNeeded()
        let empty = AchievementState.empty
        try await store.save(empty)
        state = empty
        return makeDashboard(state: empty)
    }

    private func loadIfNeeded() async throws {
        guard !didLoad else { return }
        let loadedState = try await store.load()
        if let loaded = loadedState {
            guard loaded.schemaVersion == AchievementModule.schemaVersion else {
                throw AchievementEngineError.unsupportedSchema(loaded.schemaVersion)
            }
            state = loaded
        }
        didLoad = true
    }

    private func makeDashboard(state: AchievementState) -> AchievementDashboard {
        let now = clock.now()
        let progress = definitions.map { definition in
            let raw = state.statistics.progress(for: definition.requirement, asOf: now,
                                                timeZoneIdentifier: configuration.timeZoneIdentifier)
            return AchievementProgress(definition: definition,
                                       currentValue: min(raw, definition.requirement.target),
                                       targetValue: definition.requirement.target,
                                       isUnlocked: state.unlockedAt[definition.id] != nil,
                                       unlockedAt: state.unlockedAt[definition.id])
        }
        return AchievementDashboard(statistics: state.statistics, progress: progress)
    }
}
