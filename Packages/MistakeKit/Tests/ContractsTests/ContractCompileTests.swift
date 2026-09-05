import Foundation
import XCTest
import Contracts
import TestSupport

final class ContractCompileTests: XCTestCase {
    func testContractVersionAndErrorLocalization() {
        XCTAssertEqual(ContractSchema.version, "1.1.0")
        for code in AppErrorCode.allCases {
            let error = AppError(code: code, logID: "synthetic-log", isRetryable: false)
            XCTAssertFalse(error.displayMessage.isEmpty)
            XCTAssertFalse(error.localizationKey.isEmpty)
        }
    }
}

// Compiled without @testable imports. Every protocol requirement is called with public DTOs.
private func compileAllServiceCalls(
    assetStore: any AssetStore,
    oCRService: any OCRService,
    segmentationService: any SegmentationService,
    analysisService: any AnalysisService,
    mistakeValueService: any MistakeValueService,
    credentialStore: any CredentialStore,
    classificationService: any ClassificationService,
    capabilityProvider: any CapabilityProvider,
    taxonomySeedProvider: any TaxonomySeedProvider,
    mistakeRepository: any MistakeRepository,
    pDFExportService: any PDFExportService,
    appService: any AppService
) async throws {
    _ = try await assetStore.beginTransaction()
    _ = try await assetStore.importPage(page: ContractSamples.importedPage(), transaction: ContractSamples.assetTransaction())
    _ = try await assetStore.transform(request: ContractSamples.imageTransformRequest(), transaction: ContractSamples.assetTransaction())
    _ = try await assetStore.metadata(assetID: UUID())
    _ = try await assetStore.loadImage(assetID: UUID())
    _ = try await assetStore.thumbnail(request: ContractSamples.thumbnailRequest())
    _ = try await assetStore.commit(transaction: ContractSamples.assetTransaction())
    _ = try await assetStore.rollback(transaction: ContractSamples.assetTransaction())
    _ = try await assetStore.cleanup(referencedAssetIDs: [])
    _ = try await assetStore.acquireRetention(assetIDs: [])
    _ = try await assetStore.releaseRetention(token: ContractSamples.assetRetentionToken())
    _ = try await assetStore.clearAll()
    _ = try await oCRService.recognize(image: ContractSamples.imagePayload(), options: ContractSamples.recognitionOptions())
    _ = try await oCRService.supportedLanguages()
    _ = try await segmentationService.segment(page: ContractSamples.recognizedPage(), options: ContractSamples.segmentationOptions())
    _ = try await analysisService.analyze(snapshot: ContractSamples.recordContentSnapshot(), options: ContractSamples.analysisOptions())
    _ = try await analysisService.capabilities()
    _ = try await mistakeValueService.evaluate(snapshot: ContractSamples.recordContentSnapshot(), analysis: nil, options: ValueAnalysisOptions())
    _ = try await credentialStore.read(kind: .analysisModelAPIKey)
    _ = try await credentialStore.write(kind: .analysisModelAPIKey, value: "synthetic")
    _ = try await credentialStore.remove(kind: .analysisModelAPIKey)
    _ = try await credentialStore.removeAll()
    _ = try await credentialStore.status()
    _ = try await classificationService.classify(snapshot: ContractSamples.recordContentSnapshot(), taxonomy: ContractSamples.taxonomySnapshot(), options: ContractSamples.classificationOptions())
    _ = try await capabilityProvider.capabilities()
    _ = try await taxonomySeedProvider.loadSeed()
    _ = try await mistakeRepository.create(record: ContractSamples.mistakeRecord())
    _ = try await mistakeRepository.get(id: UUID())
    _ = try await mistakeRepository.list(query: ContractSamples.recordQuery(), page: ContractSamples.pageRequest())
    _ = try await mistakeRepository.update(record: ContractSamples.mistakeRecord(), expectedRecordRevision: 1)
    _ = try await mistakeRepository.delete(ids: [], expectedVersions: [])
    _ = try await mistakeRepository.restore(token: ContractSamples.deletionToken())
    _ = try await mistakeRepository.commit(transaction: ContractSamples.repositoryTransaction())
    _ = try await mistakeRepository.saveJob(job: ContractSamples.processingJob())
    _ = try await mistakeRepository.getJob(id: UUID())
    _ = try await mistakeRepository.listJobs(batchID: nil, states: [])
    _ = try await mistakeRepository.saveBatch(batch: ContractSamples.importBatch())
    _ = try await mistakeRepository.getBatch(id: UUID())
    _ = try await mistakeRepository.listBatches()
    _ = try await mistakeRepository.loadTaxonomy()
    _ = try await mistakeRepository.saveTaxonomy(snapshot: ContractSamples.taxonomySnapshot(), expectedVersion: nil)
    _ = try await mistakeRepository.applyTaxonomyDeletion(request: ContractSamples.taxonomyDeleteRequest())
    _ = try await mistakeRepository.loadSettings()
    _ = try await mistakeRepository.saveSettings(settings: ContractSamples.appSettings())
    _ = try await mistakeRepository.loadRegionUndo(token: ContractSamples.regionUndoToken())
    _ = try await mistakeRepository.removeRegionUndo(token: ContractSamples.regionUndoToken())
    _ = try await mistakeRepository.loadTombstones()
    _ = try await mistakeRepository.referencedAssetIDs()
    _ = try await mistakeRepository.inventory()
    _ = try await mistakeRepository.clearAll()
    _ = try await pDFExportService.export(snapshot: ContractSamples.exportSnapshot())
    _ = try await pDFExportService.releaseExport(artifactID: UUID())
    _ = try await appService.importPages(pages: [], options: ContractSamples.importOptions())
    _ = try await appService.createManualRecord(draft: ContractSamples.manualRecordDraft())
    _ = try await appService.observeBatch(batchID: UUID())
    _ = try await appService.observeRecords(recordID: nil)
    _ = try await appService.list(query: ContractSamples.recordQuery(), page: ContractSamples.pageRequest())
    _ = try await appService.get(id: UUID())
    _ = try await appService.loadPreview(request: ContractSamples.thumbnailRequest())
    _ = try await appService.loadImage(assetID: UUID())
    _ = try await appService.applyEdit(id: UUID(), patch: ContractSamples.recordEditPatch())
    _ = try await appService.transformImage(request: ContractSamples.recordImageTransformRequest())
    _ = try await appService.confirmRegions(request: ContractSamples.regionEditRequest())
    _ = try await appService.undoRegionEdit(token: ContractSamples.regionUndoToken())
    _ = try await appService.retry(target: .batch(UUID()))
    _ = try await appService.cancel(target: .batch(UUID()))
    _ = try await appService.analyze(id: UUID(), expectedContentRevision: 1)
    _ = try await appService.evaluateValue(id: UUID(), expectedContentRevision: 1)
    _ = try await appService.setClassification(id: UUID(), selection: ContractSamples.classificationSelection())
    _ = try await appService.taxonomy()
    _ = try await appService.createTaxonomyNode(node: ContractSamples.taxonomyNode(), expectedTaxonomyVersion: "synthetic")
    _ = try await appService.updateTaxonomyNode(id: "synthetic", patch: ContractSamples.taxonomyNodePatch())
    _ = try await appService.deleteTaxonomyNode(request: ContractSamples.taxonomyDeleteRequest())
    _ = try await appService.updateReviewState(id: UUID(), state: .reviewing, expectedRecordRevision: 1)
    _ = try await appService.delete(ids: [], expectedVersions: [])
    _ = try await appService.restore(token: ContractSamples.deletionToken())
    _ = try await appService.export(request: ContractSamples.exportRequest())
    _ = try await appService.releaseExport(artifactID: UUID())
    _ = try await appService.prepareClearAllData()
    _ = try await appService.clearAllData(confirmation: ContractSamples.clearDataConfirmation())
    _ = try await appService.capabilities()
    _ = try await appService.settings()
    _ = try await appService.updateSettings(settings: ContractSamples.appSettings())
    _ = try await appService.credentialStatus()
    _ = try await appService.setCredential(kind: .analysisModelAPIKey, value: "synthetic")
    _ = try await appService.clearCredential(kind: .analysisModelAPIKey)
}
