import Foundation
import AchievementsKit

@main
struct AchievementsKitValidation {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_788_681_600)
        let store = InMemoryAchievementStateStore()
        let definition = AchievementDefinition(id: "validation.first", category: .organizing,
            title: "First", detail: "", iconSystemName: "star",
            requirement: .eventCount(kind: .recordCreated, target: 1))
        let engine = try AchievementEngine(definitions: [definition], store: store,
            configuration: AchievementConfiguration(timeZoneIdentifier: "UTC"),
            clock: FixedAchievementClock(date: now))
        let event = AchievementEvent(id: "validation:record", occurredAt: now, kind: .recordCreated)

        let first = try await engine.ingest(event)
        precondition(first.acceptedEventCount == 1)
        precondition(first.newlyUnlocked.map(\.id) == ["validation.first"])

        let retry = try await engine.ingest(event)
        precondition(retry.acceptedEventCount == 0)
        precondition(retry.dashboard.statistics.eventCount(for: .recordCreated) == 1)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AchievementsKit-validation-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let fileStore = JSONFileAchievementStateStore(fileURL: fileURL)
        let fileEngine = try AchievementEngine(definitions: [definition], store: fileStore,
            configuration: AchievementConfiguration(timeZoneIdentifier: "UTC"),
            clock: FixedAchievementClock(date: now))
        _ = try await fileEngine.ingest(event)
        let restoredEngine = try AchievementEngine(definitions: [definition], store: fileStore,
            configuration: AchievementConfiguration(timeZoneIdentifier: "UTC"),
            clock: FixedAchievementClock(date: now))
        let restored = try await restoredEngine.dashboard()
        precondition(restored.unlockedCount == 1)
        try? FileManager.default.removeItem(at: fileURL)

        let id = UUID()
        let bridge = MistakeBookAchievementBridge(engine: engine)
        let baseline = AchievementRecordSnapshot(id: id, recordRevision: 1, reviewState: .new,
            hasConfirmedClassification: false, acceptedAnalysisCount: 0, subjectID: "math")
        let baselineUpdate = try await bridge.ingest(AchievementRecordChange(kind: .initial, record: baseline))
        precondition(baselineUpdate == nil)
        let reviewing = AchievementRecordSnapshot(id: id, recordRevision: 2, reviewState: .reviewing,
            hasConfirmedClassification: false, acceptedAnalysisCount: 0, subjectID: "math")
        let reviewingUpdate = try await bridge.ingest(AchievementRecordChange(kind: .upserted, record: reviewing))
        precondition(reviewingUpdate?.acceptedEventCount == 1)

        print("AchievementsKit validation passed")
    }
}
