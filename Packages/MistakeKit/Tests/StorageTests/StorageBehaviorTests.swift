import XCTest
import Contracts
import Storage
import Foundation
import TestSupport

final class StorageBehaviorTests: XCTestCase {
    func testSavedRecordSurvivesOpeningAnotherRepository() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mistakebook-persistence-\(UUID().uuidString)")
        let configuration = StorageConfiguration(rootDirectory: root, inMemory: false, excludeFromBackup: false,
                                                 protection: .completeUntilFirstUserAuthentication)
        let original = try await StorageFactory.make(configuration: configuration)
        let record = ContractSamples.mistakeRecord()
        _ = try await original.repository.create(record: record)
        let reopened = try await StorageFactory.make(configuration: configuration)
        let loaded = try await reopened.repository.get(id: record.id)
        XCTAssertEqual(loaded, record)
    }
}
