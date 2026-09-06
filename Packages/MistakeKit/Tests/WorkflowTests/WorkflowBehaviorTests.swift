import XCTest
import UIKit
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

    func testImageModeCropsQuestionRegionImages() async throws {
        // Force scale 1: the default format inherits the display scale (3x on
        // modern simulators), which would silently triple the PNG's pixel size.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        let assetID = UUID()
        let topRegion = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: try NormalizedRect(x: 0, y: 0, width: 1, height: 0.5), purpose: .stem, isUserConfirmed: false)
        let bottomRegion = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: try NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5), purpose: .stem, isUserConfirmed: false)
        let topLine = OCRLine(id: UUID(), regionID: topRegion.id, assetID: assetID, rawText: "1. 第一题", confidence: nil, scriptStyle: .printed, normalizedRect: try NormalizedRect(x: 0.05, y: 0.06, width: 0.9, height: 0.03))
        let bottomLine = OCRLine(id: UUID(), regionID: bottomRegion.id, assetID: assetID, rawText: "2. 第二题", confidence: nil, scriptStyle: .printed, normalizedRect: try NormalizedRect(x: 0.05, y: 0.56, width: 0.9, height: 0.03))
        let recognized = RecognizedPage(assetID: assetID, regions: [topRegion, bottomRegion], lines: [topLine, bottomLine],
                                        providerID: "scripted", providerVersion: "1", supportedLanguages: [], warnings: [],
                                        candidates: [SegmentationCandidate(id: UUID(), order: 1, regions: [topRegion], lineIDs: [topLine.id], needsConfirmation: false, warnings: []),
                                                     SegmentationCandidate(id: UUID(), order: 2, regions: [bottomRegion], lineIDs: [bottomLine.id], needsConfirmation: false, warnings: [])])
        let service = try await makeService(ocr: ScriptedOCRService(result: .success(recognized)), segmentation: PassThroughSegmentationService())
        let batchID = try await service.importPages(pages: [ImportedPage(id: UUID(), bytes: try XCTUnwrap(image.pngData()), mediaType: .png, sourceName: "worksheet", order: 0)],
            options: ImportOptions(duplicatePolicy: .skipExisting,
                                   recognition: RecognitionOptions(languages: ["zh-Hans"], quality: .accurate, usesLanguageCorrection: false, maxPixelDimension: 4096),
                                   recordMode: .image))
        for await event in try await service.observeBatch(batchID: batchID) where event.isTerminal { break }
        let records = try await service.list(query: RecordQuery(text: "", subjectID: nil, taxonomyNodeID: nil, includeDescendants: true,
            reviewStates: [], reviewRequiredOnly: false, includeDeleted: false, sort: .updatedNewest), page: PageRequest(cursor: nil, limit: 50)).records
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.contains { $0.stem.displayText.contains("第一题") })
        XCTAssertTrue(records.contains { $0.stem.displayText.contains("第二题") })
        for record in records {
            let croppedAssetID = try XCTUnwrap(record.sourceRegions.first?.assetID)
            let payload = try await service.loadImage(assetID: croppedAssetID)
            XCTAssertEqual(payload.pixelWidth, 400)
            XCTAssertEqual(payload.pixelHeight, 300)
        }
    }

    private func makeService(ocr: any OCRService = FailingOCRService(),
                             segmentation: any SegmentationService = FailingSegmentationService()) async throws -> any AppService {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mistakebook-workflow-\(UUID().uuidString)")
        let storage = try await StorageFactory.make(configuration: StorageConfiguration(rootDirectory: root, inMemory: true, excludeFromBackup: false, protection: .completeUntilFirstUserAuthentication))
        let seed = try TaxonomySeed(schemaVersion: 1, seedVersion: "test-seed", nodes: [
            TaxonomyNode(id: "math", parentID: nil, name: "数学", subjectID: "math", aliases: ["math"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/algebra", parentID: "math", name: "代数", subjectID: "math", aliases: ["algebra"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/algebra/sets", parentID: "math/algebra", name: "集合", subjectID: "math", aliases: ["集合"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/algebra/sets/subsets", parentID: "math/algebra/sets", name: "子集", subjectID: "math", aliases: ["subset"], origin: .seed, isActive: true, version: 1, userModifiedFields: []),
            TaxonomyNode(id: "math/geometry", parentID: "math", name: "几何", subjectID: "math", aliases: ["geometry"], origin: .seed, isActive: true, version: 1, userModifiedFields: [])
        ])
        let intelligence = IntelligenceServices(ocr: ocr, segmentation: segmentation, analysis: FailingAnalysisService(), value: FailingMistakeValueService(), classification: FailingClassificationService(), capabilities: FailingCapabilityProvider())
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

private struct PassThroughSegmentationService: SegmentationService {
    func segment(page: RecognizedPage, options: SegmentationOptions) async throws -> [SegmentationCandidate] { page.candidates }
}
