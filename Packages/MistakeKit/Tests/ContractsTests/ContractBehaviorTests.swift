import Foundation
import XCTest
import Contracts
import TestSupport

@MainActor
final class ContractBehaviorTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: ContractBehaviorTests.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testRecordRoundTripPreservesCorrectionsAndEvidence() throws {
        let decoder = ContractJSON.decoder()
        let record = try decoder.decode(MistakeRecord.self, from: fixture("record-v1"))
        XCTAssertEqual(record.stem.displayText, "合成示例：2 + 2 = ？")
        XCTAssertNotEqual(record.stem.rawText, record.stem.displayText)
        XCTAssertEqual(record.ocrLines.first?.regionID, record.sourceRegions.first?.id)
        XCTAssertEqual(record.ocrLines.first?.assetID, record.sourceRegions.first?.assetID)
        XCTAssertEqual(record.contentSnapshot.contentRevision, 1)
        XCTAssertFalse(record.isAnalysisStale)
        let encoded = try ContractJSON.encoder().encode(record)
        XCTAssertEqual(record, try decoder.decode(MistakeRecord.self, from: encoded))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("2026-09-05T00:00:00Z"))
    }

    func testFixedExamplesAndFutureSchemaRejection() throws {
        let decoder = ContractJSON.decoder()
        let page = try decoder.decode(RecognizedPage.self, from: fixture("recognized-page-v1"))
        XCTAssertEqual(page.providerID, "synthetic-fixture")
        XCTAssertEqual(page.candidates.first?.lineIDs, page.lines.map(\.id))
        let seed = try decoder.decode(TaxonomySeed.self, from: fixture("taxonomy-seed-v1"))
        XCTAssertEqual(seed.nodes.first?.id, "synthetic")
        _ = try decoder.decode(ExportOptions.self, from: fixture("export-options-v1"))
        XCTAssertThrowsError(try decoder.decode(MistakeRecord.self, from: fixture("record-future-version"))) {
            XCTAssertEqual(($0 as? AppError)?.code, .unsupportedSchemaVersion)
        }
        XCTAssertThrowsError(try TaxonomySeed(schemaVersion: 2, seedVersion: "future", nodes: []))
    }

    func testExplicitClearDiffersFromUnchanged() throws {
        let decoder = ContractJSON.decoder()
        let patch = try decoder.decode(RecordEditPatch.self, from: fixture("clear-reference-patch"))
        XCTAssertEqual(patch.referenceAnswer, .set(nil))
        XCTAssertEqual(patch.stem, .unchanged)
        XCTAssertEqual(patch.notes, .set(""))
        XCTAssertEqual(patch, try decoder.decode(RecordEditPatch.self, from: ContractJSON.encoder().encode(patch)))
        let unchanged = FieldChange<String?>.unchanged
        let clear = FieldChange<String?>.set(nil)
        XCTAssertNotEqual(try ContractJSON.encoder().encode(unchanged), try ContractJSON.encoder().encode(clear))
    }

    func testNormalizedCoordinatesAndMalformedDecode() throws {
        XCTAssertEqual(try NormalizedRect(x: 0, y: 0, width: 1, height: 1), .fullPage)
        let converted = try NormalizedRect.fromBottomLeft(x: 0.25, y: 0.125, width: 0.5, height: 0.25)
        XCTAssertEqual(converted.y, 0.625, accuracy: 0.000001)
        XCTAssertThrowsError(try NormalizedRect(x: -0.1, y: 0, width: 0.2, height: 0.2))
        XCTAssertThrowsError(try NormalizedRect(x: 0.9, y: 0, width: 0.2, height: 0.2))
        XCTAssertThrowsError(try NormalizedRect(x: 0, y: 0, width: 0, height: 0.2))
        XCTAssertThrowsError(try NormalizedRect(x: .nan, y: 0, width: 0.2, height: 0.2))
        let invalid = Data(#"{"x":0,"y":0.9,"width":1,"height":0.2}"#.utf8)
        XCTAssertThrowsError(try ContractJSON.decoder().decode(NormalizedRect.self, from: invalid))
        XCTAssertEqual(try CoordinateMapping(values: [1,0,0,0,1,0,0,0,1]), .identity)
        XCTAssertEqual(try ContractJSON.decoder().decode(CoordinateMapping.self, from: ContractJSON.encoder().encode(CoordinateMapping.identity)), .identity)
        XCTAssertThrowsError(try CoordinateMapping(values: [0,0,0,0,0,0,0,0,0]))
        XCTAssertThrowsError(try CoordinateMapping(values: [1,2]))
    }

    func testPracticeOptionsCannotLeakStructuredAnswers() throws {
        XCTAssertThrowsError(try ExportOptions(mode: .practice, includeHandwriting: true,
            includeHypotheses: false, blankSpace: .none, sort: .selectionOrder, pageSize: .a4))
        XCTAssertThrowsError(try ExportOptions(mode: .practice, includeHandwriting: false,
            includeHypotheses: true, blankSpace: .none, sort: .selectionOrder, pageSize: .a4))
        let options = try ExportOptions(mode: .withSolutions, includeHandwriting: true,
            includeHypotheses: true, blankSpace: .small, sort: .subjectAndTaxonomy, pageSize: .a4)
        XCTAssertEqual(options, try ContractJSON.decoder().decode(ExportOptions.self, from: ContractJSON.encoder().encode(options)))
    }

    func testSeedRejectsOrphansDuplicateIDsAndCycles() throws {
        func node(_ id: String, _ parent: String?) -> TaxonomyNode {
            TaxonomyNode(id: id, parentID: parent, name: id, subjectID: "s", aliases: [],
                         origin: .seed, isActive: true, version: 1, userModifiedFields: [])
        }
        let root = node("s", nil)
        XCTAssertThrowsError(try TaxonomySeed(schemaVersion: 1, seedVersion: "1", nodes: [root, node("a", "missing")]))
        XCTAssertThrowsError(try TaxonomySeed(schemaVersion: 1, seedVersion: "1", nodes: [root, root]))
        XCTAssertThrowsError(try TaxonomySeed(schemaVersion: 1, seedVersion: "1", nodes: [root, node("a", "b"), node("b", "a")]))
        XCTAssertNoThrow(try TaxonomySeed(schemaVersion: 1, seedVersion: "1", nodes: [root, node("a", "s")]))
    }

    func testV1SettingsDecodeWithLocalDefaults() throws {
        let legacy = Data(#"{"recognitionLanguages":["zh-Hans","en-US"],"enhancedAnalysisEnabled":false,"autoArchivePolicy":{"version":"disabled","enabledRules":[]}}"#.utf8)
        let settings = try ContractJSON.decoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(settings.resolvedProcessingMode, .local)
        XCTAssertEqual(settings.resolvedOCRProvider, .appleVision)
        XCTAssertEqual(settings.resolvedAnalysisProvider, .localRules)
        XCTAssertEqual(settings.resolvedMistakeValueProvider, .localHeuristic)
        XCTAssertNil(settings.ocrModelAPI)
        XCTAssertNil(settings.baiduEducation)
    }

    func testAdditionalPublicConstructorsAndHelpers() throws {
        let failure = AppError(code: .modelUnavailable, logID: "synthetic", isRetryable: true)
        _ = failure.errorDescription
        XCTAssertEqual(AppError.normalized(CancellationError()).code, .cancelled)
        XCTAssertEqual(AppError.normalized(failure), failure)
        try ContractSchema.requireSupported(1)
        _ = StorageServices(repository: FailingMistakeRepository(), assets: FailingAssetStore())
        _ = IntelligenceServices(ocr: FailingOCRService(), segmentation: FailingSegmentationService(),
            analysis: FailingAnalysisService(), value: FailingMistakeValueService(), classification: FailingClassificationService(), capabilities: FailingCapabilityProvider())
        _ = FailingAppService()
        _ = FailingPDFExportService()
        _ = FailingTaxonomySeedProvider()
        _ = ScriptedOCRService(result: .failure(failure))
        _ = PreviewAppService(records: [])
        _ = RecordSelection.ids([UUID()])
        _ = RecordSelection.all(ContractSamples.recordQuery())
        _ = JobTarget.job(UUID())
        _ = JobTarget.batch(UUID())
    }

    func testFailureDoubleDoesNotReturnFakeSuccess() async throws {
        do {
            _ = try await FailingAppService().export(request: ContractSamples.exportRequest())
            XCTFail("Unimplemented export must throw")
        } catch let error as AppError {
            XCTAssertEqual(error.code, .featureUnavailable)
        }
    }

    func testScriptedOCRPropagatesCancellation() async throws {
        let service = ScriptedOCRService(result: .success(ContractSamples.recognizedPage()), delay: .seconds(10))
        let task = Task { try await service.recognize(image: ContractSamples.imagePayload(), options: ContractSamples.recognitionOptions()) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
    }
}
