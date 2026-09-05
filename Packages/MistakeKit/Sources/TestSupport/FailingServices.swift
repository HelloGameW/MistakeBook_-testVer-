import Foundation
import Contracts

// Explicit failure doubles for tests; never injected by production App.
public struct FailingAssetStore: AssetStore {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func beginTransaction() async throws -> AssetTransaction {
        try Task.checkCancellation()
        throw failure
    }
    public func importPage(page: ImportedPage, transaction: AssetTransaction) async throws -> ImportedAssets {
        try Task.checkCancellation()
        throw failure
    }
    public func transform(request: ImageTransformRequest, transaction: AssetTransaction) async throws -> ImageTransformResult {
        try Task.checkCancellation()
        throw failure
    }
    public func metadata(assetID: UUID) async throws -> ImageAsset {
        try Task.checkCancellation()
        throw failure
    }
    public func loadImage(assetID: UUID) async throws -> ImagePayload {
        try Task.checkCancellation()
        throw failure
    }
    public func thumbnail(request: ThumbnailRequest) async throws -> ImagePayload {
        try Task.checkCancellation()
        throw failure
    }
    public func commit(transaction: AssetTransaction) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func rollback(transaction: AssetTransaction) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func cleanup(referencedAssetIDs: [UUID]) async throws -> AssetCleanupResult {
        try Task.checkCancellation()
        throw failure
    }
    public func acquireRetention(assetIDs: [UUID]) async throws -> AssetRetentionToken {
        try Task.checkCancellation()
        throw failure
    }
    public func releaseRetention(token: AssetRetentionToken) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func clearAll() async throws {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingOCRService: OCRService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        try Task.checkCancellation()
        throw failure
    }
    public func supportedLanguages() async throws -> [String] {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingSegmentationService: SegmentationService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func segment(page: RecognizedPage, options: SegmentationOptions) async throws -> [SegmentationCandidate] {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingAnalysisService: AnalysisService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func analyze(snapshot: RecordContentSnapshot, options: AnalysisOptions) async throws -> AnalysisResult {
        try Task.checkCancellation()
        throw failure
    }
    public func capabilities() async throws -> CapabilityReport {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingMistakeValueService: MistakeValueService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func evaluate(snapshot: RecordContentSnapshot, analysis: AnalysisResult?, options: ValueAnalysisOptions) async throws -> MistakeValueResult {
        try Task.checkCancellation()
        throw failure
    }
}

public actor FailingCredentialStore: CredentialStore {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func read(kind: CredentialKind) async throws -> String? { try Task.checkCancellation(); throw failure }
    public func write(kind: CredentialKind, value: String) async throws { try Task.checkCancellation(); throw failure }
    public func remove(kind: CredentialKind) async throws { try Task.checkCancellation(); throw failure }
    public func removeAll() async throws { try Task.checkCancellation(); throw failure }
    public func status() async throws -> CredentialStatus { try Task.checkCancellation(); throw failure }
}

public struct FailingClassificationService: ClassificationService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func classify(snapshot: RecordContentSnapshot, taxonomy: TaxonomySnapshot, options: ClassificationOptions) async throws -> ClassificationResult {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingCapabilityProvider: CapabilityProvider {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func capabilities() async throws -> CapabilityReport {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingTaxonomySeedProvider: TaxonomySeedProvider {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func loadSeed() async throws -> TaxonomySeed {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingMistakeRepository: MistakeRepository {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func create(record: MistakeRecord) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func get(id: UUID) async throws -> MistakeRecord? {
        try Task.checkCancellation()
        throw failure
    }
    public func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage {
        try Task.checkCancellation()
        throw failure
    }
    public func update(record: MistakeRecord, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken {
        try Task.checkCancellation()
        throw failure
    }
    public func restore(token: DeletionToken) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        throw failure
    }
    public func commit(transaction: RepositoryTransaction) async throws -> RepositoryCommit {
        try Task.checkCancellation()
        throw failure
    }
    public func saveJob(job: ProcessingJob) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func getJob(id: UUID) async throws -> ProcessingJob? {
        try Task.checkCancellation()
        throw failure
    }
    public func listJobs(batchID: UUID?, states: [JobState]) async throws -> [ProcessingJob] {
        try Task.checkCancellation()
        throw failure
    }
    public func saveBatch(batch: ImportBatch) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func getBatch(id: UUID) async throws -> ImportBatch? {
        try Task.checkCancellation()
        throw failure
    }
    public func listBatches() async throws -> [ImportBatch] {
        try Task.checkCancellation()
        throw failure
    }
    public func loadTaxonomy() async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw failure
    }
    public func saveTaxonomy(snapshot: TaxonomySnapshot, expectedVersion: String?) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func applyTaxonomyDeletion(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw failure
    }
    public func loadSettings() async throws -> AppSettings? {
        try Task.checkCancellation()
        throw failure
    }
    public func saveSettings(settings: AppSettings) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func loadRegionUndo(token: RegionUndoToken) async throws -> RegionUndoState {
        try Task.checkCancellation()
        throw failure
    }
    public func removeRegionUndo(token: RegionUndoToken) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func loadTombstones() async throws -> [RecordTombstone] {
        try Task.checkCancellation()
        throw failure
    }
    public func referencedAssetIDs() async throws -> [UUID] {
        try Task.checkCancellation()
        throw failure
    }
    public func inventory() async throws -> DataInventory {
        try Task.checkCancellation()
        throw failure
    }
    public func clearAll() async throws {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingPDFExportService: PDFExportService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func export(snapshot: ExportSnapshot) async throws -> ExportArtifact {
        try Task.checkCancellation()
        throw failure
    }
    public func releaseExport(artifactID: UUID) async throws {
        try Task.checkCancellation()
        throw failure
    }
}

public struct FailingAppService: AppService {
    public let failure: AppError
    public init(failure: AppError = AppError(code: .featureUnavailable)) { self.failure = failure }
    public func importPages(pages: [ImportedPage], options: ImportOptions) async throws -> UUID {
        try Task.checkCancellation()
        throw failure
    }
    public func createManualRecord(draft: ManualRecordDraft) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func observeBatch(batchID: UUID) async throws -> AsyncStream<BatchEvent> {
        try Task.checkCancellation()
        throw failure
    }
    public func observeRecords(recordID: UUID?) async throws -> AsyncStream<RecordEvent> {
        try Task.checkCancellation()
        throw failure
    }
    public func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage {
        try Task.checkCancellation()
        throw failure
    }
    public func get(id: UUID) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func loadPreview(request: ThumbnailRequest) async throws -> ImagePayload {
        try Task.checkCancellation()
        throw failure
    }
    public func loadImage(assetID: UUID) async throws -> ImagePayload {
        try Task.checkCancellation()
        throw failure
    }
    public func applyEdit(id: UUID, patch: RecordEditPatch) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func transformImage(request: RecordImageTransformRequest) async throws -> RecordImageTransformResult {
        try Task.checkCancellation()
        throw failure
    }
    public func confirmRegions(request: RegionEditRequest) async throws -> RegionEditResult {
        try Task.checkCancellation()
        throw failure
    }
    public func undoRegionEdit(token: RegionUndoToken) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        throw failure
    }
    public func retry(target: JobTarget) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func cancel(target: JobTarget) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func analyze(id: UUID, expectedContentRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func evaluateValue(id: UUID, expectedContentRevision: Int) async throws -> MistakeValueResult {
        try Task.checkCancellation()
        throw failure
    }
    public func setClassification(id: UUID, selection: ClassificationSelection) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func taxonomy() async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw failure
    }
    public func createTaxonomyNode(node: TaxonomyNode, expectedTaxonomyVersion: String) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw failure
    }
    public func updateTaxonomyNode(id: String, patch: TaxonomyNodePatch) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw failure
    }
    public func deleteTaxonomyNode(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw failure
    }
    public func updateReviewState(id: UUID, state: ReviewState, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func setArchived(id: UUID, archived: Bool, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw failure
    }
    public func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken {
        try Task.checkCancellation()
        throw failure
    }
    public func restore(token: DeletionToken) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        throw failure
    }
    public func export(request: ExportRequest) async throws -> ExportArtifact {
        try Task.checkCancellation()
        throw failure
    }
    public func releaseExport(artifactID: UUID) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func prepareClearAllData() async throws -> ClearDataConfirmation {
        try Task.checkCancellation()
        throw failure
    }
    public func clearAllData(confirmation: ClearDataConfirmation) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func capabilities() async throws -> CapabilityReport {
        try Task.checkCancellation()
        throw failure
    }
    public func settings() async throws -> AppSettings {
        try Task.checkCancellation()
        throw failure
    }
    public func updateSettings(settings: AppSettings) async throws -> AppSettings {
        try Task.checkCancellation()
        throw failure
    }
    public func credentialStatus() async throws -> CredentialStatus {
        try Task.checkCancellation()
        throw failure
    }
    public func setCredential(kind: CredentialKind, value: String) async throws {
        try Task.checkCancellation()
        throw failure
    }
    public func clearCredential(kind: CredentialKind) async throws {
        try Task.checkCancellation()
        throw failure
    }
}
