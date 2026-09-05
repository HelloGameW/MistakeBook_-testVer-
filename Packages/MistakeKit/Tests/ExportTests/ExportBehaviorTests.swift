#if os(iOS)
import PDFKit
import UIKit
import XCTest
import Contracts
import Export
import TestSupport

final class ExportBehaviorTests: XCTestCase {
    func testFactoryCreatesOfflineExporterAndRendersInspectablePDF() async throws {
        let assetID = UUID()
        let regionID = UUID()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 1200))
            UIColor.label.setFill()
            context.fill(CGRect(x: 100, y: 140, width: 600, height: 4))
        }
        let payload = ImagePayload(assetID: assetID, bytes: try XCTUnwrap(image.pngData()), mediaType: .png,
                                   orientation: .up, pixelWidth: 800, pixelHeight: 1200)
        let assetStore = ExportTestAssetStore(payload: payload)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mistakebook-export-\(UUID().uuidString)")
        let configuration = PDFExportConfiguration(temporaryDirectory: directory, fileLifetimeSeconds: 86400)
        let exporter = try ExportFactory.make(assetStore: assetStore, configuration: configuration)
        let record = ContractSamples.mistakeRecord()
        let region = SourceRegion(id: regionID, assetID: assetID, normalizedRect: .fullPage,
                                  purpose: .stem, isUserConfirmed: true)
        let recordWithRegion = MistakeRecord(id: record.id, schemaVersion: record.schemaVersion,
                                             recordRevision: record.recordRevision, contentRevision: record.contentRevision,
                                             createdAt: record.createdAt, updatedAt: record.updatedAt,
                                             sourceRegions: [region], ocrLines: record.ocrLines,
                                             stem: record.stem, studentWork: record.studentWork,
                                             referenceAnswer: record.referenceAnswer,
                                             referenceAnswerSource: record.referenceAnswerSource,
                                             analysisResult: record.analysisResult, classification: record.classification,
                                             notes: record.notes, tags: record.tags, reviewState: record.reviewState,
                                             reviewRequired: record.reviewRequired, reviewReasons: record.reviewReasons,
                                             processingStatus: record.processingStatus)
        let decision = ExportImageDecision(regionID: regionID, assetID: assetID, disposition: .includeFullImage,
                                           cropRect: nil, answerRisk: .unknown, userConfirmed: false)
        let exportRecord = ExportRecord(record: recordWithRegion,
                                       version: RecordVersion(recordID: record.id, recordRevision: 1, contentRevision: 1),
                                       classificationPath: ["数学", "示例"], images: [decision])
        let options = try ExportOptions(mode: .practice, includeHandwriting: false, includeHypotheses: false,
                                        blankSpace: .small, sort: .selectionOrder, pageSize: .a4)
        let snapshot = ExportSnapshot(id: UUID(), createdAt: Date(), records: [exportRecord],
                                      retentionToken: AssetRetentionToken(id: UUID(), assetIDs: [assetID], createdAt: Date()),
                                      options: options)

        let artifact = try await exporter.export(snapshot: snapshot)
        XCTAssertGreaterThanOrEqual(artifact.summary.pageCount, 1)
        let document = try XCTUnwrap(PDFDocument(url: artifact.fileURL))
        XCTAssertEqual(document.pageCount, artifact.summary.pageCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path))
        try await exporter.releaseExport(artifactID: artifact.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.fileURL.path))
    }

    func testEmptySnapshotIsRejected() async throws {
        let exporter = OfflinePDFExportService(assetStore: ExportTestAssetStore(payload: ContractSamples.imagePayload()),
                                                configuration: PDFExportConfiguration(temporaryDirectory: FileManager.default.temporaryDirectory,
                                                                                     fileLifetimeSeconds: 86400))
        let options = try ExportOptions(mode: .practice, includeHandwriting: false, includeHypotheses: false,
                                        blankSpace: .none, sort: .selectionOrder, pageSize: .a4)
        let snapshot = ExportSnapshot(id: UUID(), createdAt: Date(), records: [],
                                      retentionToken: ContractSamples.assetRetentionToken(), options: options)
        do {
            _ = try await exporter.export(snapshot: snapshot)
            XCTFail("Empty snapshots must not create a PDF")
        } catch let error as AppError {
            XCTAssertEqual(error.code, .unsupportedInput)
        }
    }
}

private actor ExportTestAssetStore: AssetStore {
    let payload: ImagePayload

    init(payload: ImagePayload) { self.payload = payload }

    func beginTransaction() async throws -> AssetTransaction { ContractSamples.assetTransaction() }
    func importPage(page: ImportedPage, transaction: AssetTransaction) async throws -> ImportedAssets { ContractSamples.importedAssets() }
    func transform(request: ImageTransformRequest, transaction: AssetTransaction) async throws -> ImageTransformResult { ContractSamples.imageTransformResult() }
    func metadata(assetID: UUID) async throws -> ImageAsset { ContractSamples.imageAsset() }
    func loadImage(assetID: UUID) async throws -> ImagePayload { payload }
    func thumbnail(request: ThumbnailRequest) async throws -> ImagePayload { payload }
    func commit(transaction: AssetTransaction) async throws {}
    func rollback(transaction: AssetTransaction) async throws {}
    func cleanup(referencedAssetIDs: [UUID]) async throws -> AssetCleanupResult { ContractSamples.assetCleanupResult() }
    func acquireRetention(assetIDs: [UUID]) async throws -> AssetRetentionToken { ContractSamples.assetRetentionToken() }
    func releaseRetention(token: AssetRetentionToken) async throws {}
    func clearAll() async throws {}
}
#else
import XCTest

final class ExportBehaviorTests: XCTestCase {
    func testPDFRenderingRequiresiOSRuntime() throws {
        throw XCTSkip("System PDF rendering requires an iOS runtime.")
    }
}
#endif
