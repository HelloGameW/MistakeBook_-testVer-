import Foundation
import XCTest
@testable import AchievementsKit

final class AchievementEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_681_600) // 2026-09-06 UTC

    func testUnlockAndDeduplicate() async throws {
        let store = InMemoryAchievementStateStore()
        let definition = AchievementDefinition(id: "test.first", category: .organizing,
            title: "First", detail: "One", iconSystemName: "star",
            requirement: .eventCount(kind: .recordCreated, target: 1))
        let engine = try AchievementEngine(definitions: [definition], store: store,
            configuration: AchievementConfiguration(timeZoneIdentifier: "UTC"),
            clock: FixedAchievementClock(date: now))
        let event = AchievementEvent(id: "record:1", occurredAt: now, kind: .recordCreated)

        let first = try await engine.ingest(event)
        XCTAssertEqual(first.acceptedEventCount, 1)
        XCTAssertEqual(first.newlyUnlocked.map(\.id), ["test.first"])
        XCTAssertEqual(first.dashboard.unlockedCount, 1)

        let retry = try await engine.ingest(event)
        XCTAssertEqual(retry.acceptedEventCount, 0)
        XCTAssertTrue(retry.newlyUnlocked.isEmpty)
        XCTAssertEqual(retry.dashboard.statistics.eventCount(for: .recordCreated), 1)
    }

    func testPersistence() async throws {
        let store = InMemoryAchievementStateStore()
        let definition = AchievementDefinition(id: "test.collector", category: .organizing,
            title: "Collector", detail: "Two", iconSystemName: "books.vertical",
            requirement: .uniqueRecordCount(kind: .recordCreated, target: 2))
        let firstEngine = try AchievementEngine(definitions: [definition], store: store)
        let firstID = UUID(); let secondID = UUID()
        _ = try await firstEngine.ingest(.recordCreated(recordID: firstID, occurredAt: now))
        let unlocked = try await firstEngine.ingest(.recordCreated(recordID: secondID, occurredAt: now))
        XCTAssertEqual(unlocked.dashboard.unlockedCount, 1)

        let secondEngine = try AchievementEngine(definitions: [definition], store: store)
        let restored = try await secondEngine.dashboard()
        XCTAssertEqual(restored.unlockedCount, 1)
        XCTAssertEqual(restored.statistics.uniqueRecordCount(for: .recordCreated), 2)
    }

    func testBridgeBaselineAndTransitions() async throws {
        let store = InMemoryAchievementStateStore()
        let definitions = [
            AchievementDefinition(id: "test.review", category: .reviewing,
                title: "Review", detail: "", iconSystemName: "arrow.clockwise",
                requirement: .eventCount(kind: .recordReviewed, target: 1)),
            AchievementDefinition(id: "test.mastery", category: .mastery,
                title: "Mastery", detail: "", iconSystemName: "checkmark",
                requirement: .uniqueRecordCount(kind: .recordMastered, target: 1))
        ]
        let engine = try AchievementEngine(definitions: definitions, store: store,
            configuration: AchievementConfiguration(timeZoneIdentifier: "UTC"),
            clock: FixedAchievementClock(date: now))
        let bridge = MistakeBookAchievementBridge(engine: engine)
        let id = UUID()
        let baseline = AchievementRecordSnapshot(id: id, recordRevision: 1, reviewState: .new,
            hasConfirmedClassification: false, acceptedAnalysisCount: 0, subjectID: "math")
        let baselineUpdate = try await bridge.ingest(AchievementRecordChange(kind: .initial, record: baseline))
        XCTAssertNil(baselineUpdate)

        let reviewing = AchievementRecordSnapshot(id: id, recordRevision: 2, reviewState: .reviewing,
            hasConfirmedClassification: false, acceptedAnalysisCount: 0, subjectID: "math")
        let reviewed = try await bridge.ingest(AchievementRecordChange(kind: .upserted, record: reviewing, occurredAt: now))
        XCTAssertEqual(reviewed?.newlyUnlocked.map(\.id), ["test.review"])

        let mastered = AchievementRecordSnapshot(id: id, recordRevision: 3, reviewState: .mastered,
            hasConfirmedClassification: false, acceptedAnalysisCount: 0, subjectID: "math")
        let masteredUpdate = try await bridge.ingest(AchievementRecordChange(kind: .upserted, record: mastered, occurredAt: now))
        XCTAssertEqual(masteredUpdate?.newlyUnlocked.map(\.id), ["test.mastery"])
    }

    func testStreak() async throws {
        let store = InMemoryAchievementStateStore()
        let definition = AchievementDefinition(id: "test.streak", category: .consistency,
            title: "Streak", detail: "Three", iconSystemName: "flame",
            requirement: .activeDayStreak(target: 3))
        let engine = try AchievementEngine(definitions: [definition], store: store,
            configuration: AchievementConfiguration(timeZoneIdentifier: "UTC"),
            clock: FixedAchievementClock(date: now))
        for offset in [-2, -1, 0] {
            let date = now.addingTimeInterval(TimeInterval(offset * 86_400))
            _ = try await engine.ingest(AchievementEvent(id: "day:\(offset)", occurredAt: date,
                kind: .studyActivity))
        }
        let dashboard = try await engine.dashboard()
        XCTAssertEqual(dashboard.progress.first?.currentValue, 3)
        XCTAssertEqual(dashboard.progress.first?.isUnlocked, true)
    }

    func testInvalidCatalog() async {
        let store = InMemoryAchievementStateStore()
        let definition = AchievementDefinition(id: "", category: .organizing,
            title: "", detail: "", iconSystemName: "star",
            requirement: .eventCount(kind: .recordCreated, target: 1))
        XCTAssertThrowsError(try AchievementEngine(definitions: [definition], store: store)) { error in
            XCTAssertEqual(error as? AchievementEngineError, .invalidDefinitionID)
        }
    }
}
