import XCTest
import Contracts
import Storage
import Workflow
import Intelligence
import TestSupport

final class WorkflowBehaviorTests: XCTestCase {
    func testManualEditUsesContentRevisionAndRejectsStaleWrite() async throws {
        let service = try await makeService()
        let record = try await service.createManualRecord(draft: ManualRecordDraft(stem: "1 + 1", studentWork: "3", referenceAnswer: "2", notes: "", tags: []))
        let editedText = EditableText(rawText: "1 + 1", correctedText: "1 + 1 = 2", provenance: .user, isLocked: true)
        let patch = RecordEditPatch(expectedRecordRevision: record.recordRevision, stem: .set(editedText), studentWork: .unchanged, referenceAnswer: .unchanged, referenceAnswerSource: .unchanged, sourceRegions: .unchanged, notes: .unchanged, tags: .unchanged, hypothesisDecisions: [])
        let edited = try await service.applyEdit(id: record.id, patch: patch)
        XCTAssertEqual(edited.recordRevision, record.recordRevision + 1)
        XCTAssertEqual(edited.contentRevision, record.contentRevision + 1)
        do {
            _ = try await service.applyEdit(id: record.id, patch: patch)
            XCTFail("stale revision must not overwrite the edited record")
        } catch let error as AppError { XCTAssertEqual(error.code, .revisionConflict) }
    }

    func testDeleteAndRestoreKeepsTombstoneRevisionChain() async throws {
        let service = try await makeService()
        let record = try await service.createManualRecord(draft: ManualRecordDraft(stem: "题目", studentWork: "作答", referenceAnswer: nil, notes: "", tags: []))
        let token = try await service.delete(ids: [record.id], expectedVersions: [RecordVersion(recordID: record.id, recordRevision: record.recordRevision, contentRevision: record.contentRevision)])
        do { _ = try await service.get(id: record.id); XCTFail("soft-deleted record must not be listed as active") } catch let error as AppError { XCTAssertEqual(error.code, .notFound) }
        let restored = try await service.restore(token: token)
        XCTAssertEqual(restored.first?.recordRevision, record.recordRevision + 1)
        let fetched = try await service.get(id: record.id)
        XCTAssertEqual(fetched.stem.displayText, "题目")
    }

    func testSeedInitializationAndUserClassificationLock() async throws {
        let service = try await makeService()
        let taxonomy = try await service.taxonomy()
        XCTAssertTrue(taxonomy.nodes.contains { $0.id == "math/algebra/sets/subsets" })
        let record = try await service.createManualRecord(draft: ManualRecordDraft(stem: "集合子集", studentWork: "", referenceAnswer: nil, notes: "", tags: []))
        let selection = ClassificationSelection(primaryNodeID: "math/algebra/sets/subsets", tags: ["重点"], expectedRecordRevision: record.recordRevision, expectedTaxonomyVersion: taxonomy.version)
        let classified = try await service.setClassification(id: record.id, selection: selection)
        XCTAssertEqual(classified.classification.assignmentState, .userConfirmed)
        XCTAssertEqual(classified.classification.primaryNodeID, "math/algebra/sets/subsets")
    }

    func testClearConfirmationIsOneUse() async throws {
        let service = try await makeService()
        _ = try await service.createManualRecord(draft: ManualRecordDraft(stem: "将被清空", studentWork: "", referenceAnswer: nil, notes: "", tags: []))
        let confirmation = try await service.prepareClearAllData()
        try await service.clearAllData(confirmation: confirmation)
        do {
            try await service.clearAllData(confirmation: confirmation)
            XCTFail("clear confirmation must be single-use")
        } catch let error as AppError { XCTAssertEqual(error.code, .invalidConfirmation) }
    }

    private func makeService() async throws -> any AppService {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mistakebook-workflow-\(UUID().uuidString)")
        let storage = try await StorageFactory.make(configuration: StorageConfiguration(rootDirectory: root, inMemory: true, excludeFromBackup: false, protection: .completeUntilFirstUserAuthentication))
        let seed = try TaxonomySeed(schemaVersion: 1, seedVersion: "test-seed", nodes: [
            TaxonomyNode(id: "math", parentID: nil, name: "数学", subjectID: "math", aliases: ["math"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/algebra", parentID: "math", name: "代数", subjectID: "math", aliases: ["algebra"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/algebra/sets", parentID: "math/algebra", name: "集合", subjectID: "math", aliases: ["集合"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/algebra/sets/subsets", parentID: "math/algebra/sets", name: "子集", subjectID: "math", aliases: ["subset"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/geometry", parentID: "math", name: "几何", subjectID: "math", aliases: ["geometry"], origin: .seed, isActive: true, version: 1, userModifiedFields: [])
        ])
        let intelligence = IntelligenceServices(ocr: FailingOCRService(), segmentation: FailingSegmentationService(), analysis: FailingAnalysisService(), value: FailingMistakeValueService(), classification: FailingClassificationService(), capabilities: FailingCapabilityProvider())
        // The unsalted no-credential store keeps clearAllData independent of the
        // simulator's Keychain availability under unsigned test runners.
        let service = try await WorkflowFactory.make(repository: storage.repository, assets: storage.assets, intelligence: intelligence, exporter: FailingPDFExportService(), seedProvider: InlineSeedProvider(seed: seed), configuration: WorkflowConfiguration(maxBatchSize: 20, maxConcurrentJobs: 1, initialSettings: AppSettings(recognitionLanguages: ["zh-Hans", "en-US"], enhancedAnalysisEnabled: false, autoArchivePolicy: AutoArchivePolicy(version: "none", enabledRules: []))), credentialStore: UnavailableCredentialStore())
        return service
    }
}

private struct InlineSeedProvider: TaxonomySeedProvider {
    let seed: TaxonomySeed
    func loadSeed() async throws -> TaxonomySeed { seed }
}
