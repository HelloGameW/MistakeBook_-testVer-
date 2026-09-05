import Foundation

// All IO boundaries are Sendable and async throws, with cooperative CancellationError propagation.
// No protocol is MainActor isolated. UI awaits these methods and updates view state on MainActor.
// Stream setup errors throw; later errors are typed events. See docs/CONTRACTS.md for lifetime rules.

public protocol AssetStore: Sendable {
    func beginTransaction() async throws -> AssetTransaction
    func importPage(page: ImportedPage, transaction: AssetTransaction) async throws -> ImportedAssets
    func transform(request: ImageTransformRequest, transaction: AssetTransaction) async throws -> ImageTransformResult
    func metadata(assetID: UUID) async throws -> ImageAsset
    func loadImage(assetID: UUID) async throws -> ImagePayload
    func thumbnail(request: ThumbnailRequest) async throws -> ImagePayload
    func commit(transaction: AssetTransaction) async throws
    func rollback(transaction: AssetTransaction) async throws
    func cleanup(referencedAssetIDs: [UUID]) async throws -> AssetCleanupResult
    func acquireRetention(assetIDs: [UUID]) async throws -> AssetRetentionToken
    func releaseRetention(token: AssetRetentionToken) async throws
    func clearAll() async throws
}

public protocol OCRService: Sendable {
    func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage
    func supportedLanguages() async throws -> [String]
}

public protocol SegmentationService: Sendable {
    func segment(page: RecognizedPage, options: SegmentationOptions) async throws -> [SegmentationCandidate]
}

public protocol AnalysisService: Sendable {
    func analyze(snapshot: RecordContentSnapshot, options: AnalysisOptions) async throws -> AnalysisResult
    func capabilities() async throws -> CapabilityReport
}

public protocol MistakeValueService: Sendable {
    func evaluate(snapshot: RecordContentSnapshot, analysis: AnalysisResult?, options: ValueAnalysisOptions) async throws -> MistakeValueResult
}

/// Secure secret storage boundary. Implementations must not persist secret values
/// in SwiftData, UserDefaults, plist files, logs, or Codable settings.
public protocol CredentialStore: Sendable {
    func read(kind: CredentialKind) async throws -> String?
    func write(kind: CredentialKind, value: String) async throws
    func remove(kind: CredentialKind) async throws
    func removeAll() async throws
    func status() async throws -> CredentialStatus
}

public protocol ClassificationService: Sendable {
    func classify(snapshot: RecordContentSnapshot, taxonomy: TaxonomySnapshot, options: ClassificationOptions) async throws -> ClassificationResult
}

public protocol CapabilityProvider: Sendable {
    func capabilities() async throws -> CapabilityReport
}

public protocol TaxonomySeedProvider: Sendable {
    func loadSeed() async throws -> TaxonomySeed
}

public protocol MistakeRepository: Sendable {
    func create(record: MistakeRecord) async throws -> MistakeRecord
    func get(id: UUID) async throws -> MistakeRecord?
    func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage
    func update(record: MistakeRecord, expectedRecordRevision: Int) async throws -> MistakeRecord
    func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken
    func restore(token: DeletionToken) async throws -> [MistakeRecord]
    func commit(transaction: RepositoryTransaction) async throws -> RepositoryCommit
    func saveJob(job: ProcessingJob) async throws
    func getJob(id: UUID) async throws -> ProcessingJob?
    func listJobs(batchID: UUID?, states: [JobState]) async throws -> [ProcessingJob]
    func saveBatch(batch: ImportBatch) async throws
    func getBatch(id: UUID) async throws -> ImportBatch?
    func listBatches() async throws -> [ImportBatch]
    func loadTaxonomy() async throws -> TaxonomySnapshot
    func saveTaxonomy(snapshot: TaxonomySnapshot, expectedVersion: String?) async throws
    func applyTaxonomyDeletion(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot
    func loadSettings() async throws -> AppSettings?
    func saveSettings(settings: AppSettings) async throws
    func loadRegionUndo(token: RegionUndoToken) async throws -> RegionUndoState
    func removeRegionUndo(token: RegionUndoToken) async throws
    func loadTombstones() async throws -> [RecordTombstone]
    func referencedAssetIDs() async throws -> [UUID]
    func inventory() async throws -> DataInventory
    func clearAll() async throws
}

public protocol PDFExportService: Sendable {
    func export(snapshot: ExportSnapshot) async throws -> ExportArtifact
    func releaseExport(artifactID: UUID) async throws
}

public protocol AppService: Sendable {
    func importPages(pages: [ImportedPage], options: ImportOptions) async throws -> UUID
    func createManualRecord(draft: ManualRecordDraft) async throws -> MistakeRecord
    func observeBatch(batchID: UUID) async throws -> AsyncStream<BatchEvent>
    func observeRecords(recordID: UUID?) async throws -> AsyncStream<RecordEvent>
    func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage
    func get(id: UUID) async throws -> MistakeRecord
    func loadPreview(request: ThumbnailRequest) async throws -> ImagePayload
    func loadImage(assetID: UUID) async throws -> ImagePayload
    func applyEdit(id: UUID, patch: RecordEditPatch) async throws -> MistakeRecord
    func transformImage(request: RecordImageTransformRequest) async throws -> RecordImageTransformResult
    func confirmRegions(request: RegionEditRequest) async throws -> RegionEditResult
    func undoRegionEdit(token: RegionUndoToken) async throws -> [MistakeRecord]
    func retry(target: JobTarget) async throws
    func cancel(target: JobTarget) async throws
    func analyze(id: UUID, expectedContentRevision: Int) async throws -> MistakeRecord
    func evaluateValue(id: UUID, expectedContentRevision: Int) async throws -> MistakeValueResult
    func setClassification(id: UUID, selection: ClassificationSelection) async throws -> MistakeRecord
    func taxonomy() async throws -> TaxonomySnapshot
    func createTaxonomyNode(node: TaxonomyNode, expectedTaxonomyVersion: String) async throws -> TaxonomySnapshot
    func updateTaxonomyNode(id: String, patch: TaxonomyNodePatch) async throws -> TaxonomySnapshot
    func deleteTaxonomyNode(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot
    func updateReviewState(id: UUID, state: ReviewState, expectedRecordRevision: Int) async throws -> MistakeRecord
    func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken
    func restore(token: DeletionToken) async throws -> [MistakeRecord]
    func export(request: ExportRequest) async throws -> ExportArtifact
    func releaseExport(artifactID: UUID) async throws
    func prepareClearAllData() async throws -> ClearDataConfirmation
    func clearAllData(confirmation: ClearDataConfirmation) async throws
    func capabilities() async throws -> CapabilityReport
    func settings() async throws -> AppSettings
    func updateSettings(settings: AppSettings) async throws -> AppSettings
    func credentialStatus() async throws -> CredentialStatus
    func setCredential(kind: CredentialKind, value: String) async throws
    func clearCredential(kind: CredentialKind) async throws
}
