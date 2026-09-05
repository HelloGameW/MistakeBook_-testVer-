import Foundation
import Contracts

/// Read-only synthetic preview. Unsupported mutations throw, never pretend to save/export.
public struct PreviewAppService: AppService {
    public let records: [MistakeRecord]
    public init(records: [MistakeRecord]) { self.records = records }
    public func importPages(pages: [ImportedPage], options: ImportOptions) async throws -> UUID {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func createManualRecord(draft: ManualRecordDraft) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func observeBatch(batchID: UUID) async throws -> AsyncStream<BatchEvent> {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func observeRecords(recordID: UUID?) async throws -> AsyncStream<RecordEvent> {
        try Task.checkCancellation()
        let selected = records.filter { recordID == nil || $0.id == recordID }
        return AsyncStream { continuation in
            for record in selected { continuation.yield(RecordEvent(kind: .initial, recordID: record.id, record: record, error: nil)) }
            continuation.finish()
        }
    }
    public func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage {
        try Task.checkCancellation()
        let filtered = records.filter { query.includeArchived || !$0.isArchived }
        return RecordPage(records: Array(filtered.prefix(page.limit)), nextCursor: nil)
    }
    public func get(id: UUID) async throws -> MistakeRecord {
        try Task.checkCancellation()
        guard let record = records.first(where: { $0.id == id }) else { throw AppError(code: .notFound) }
        return record
    }
    public func loadPreview(request: ThumbnailRequest) async throws -> ImagePayload {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func loadImage(assetID: UUID) async throws -> ImagePayload {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func applyEdit(id: UUID, patch: RecordEditPatch) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func transformImage(request: RecordImageTransformRequest) async throws -> RecordImageTransformResult {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func confirmRegions(request: RegionEditRequest) async throws -> RegionEditResult {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func undoRegionEdit(token: RegionUndoToken) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func retry(target: JobTarget) async throws {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func cancel(target: JobTarget) async throws {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func analyze(id: UUID, expectedContentRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func evaluateValue(id: UUID, expectedContentRevision: Int) async throws -> MistakeValueResult {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func setClassification(id: UUID, selection: ClassificationSelection) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func taxonomy() async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        return TaxonomySnapshot(version: "synthetic-preview", nodes: [])
    }
    public func createTaxonomyNode(node: TaxonomyNode, expectedTaxonomyVersion: String) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func updateTaxonomyNode(id: String, patch: TaxonomyNodePatch) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func deleteTaxonomyNode(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func updateReviewState(id: UUID, state: ReviewState, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func setArchived(id: UUID, archived: Bool, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func restore(token: DeletionToken) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func export(request: ExportRequest) async throws -> ExportArtifact {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func releaseExport(artifactID: UUID) async throws {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func prepareClearAllData() async throws -> ClearDataConfirmation {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func clearAllData(confirmation: ClearDataConfirmation) async throws {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func capabilities() async throws -> CapabilityReport {
        try Task.checkCancellation()
        return CapabilityReport(checkedAt: Date(timeIntervalSince1970: 1_700_000_000), features: CapabilityFeature.allCases.map { FeatureCapability(feature: $0, subjectID: nil, state: .unavailable, reason: "合成预览，尚未接入业务服务", supportedLanguages: []) })
    }
    public func settings() async throws -> AppSettings {
        try Task.checkCancellation()
        return AppSettings(recognitionLanguages: ["zh-Hans", "en-US"], enhancedAnalysisEnabled: false, autoArchivePolicy: AutoArchivePolicy(version: "disabled", enabledRules: []))
    }
    public func updateSettings(settings: AppSettings) async throws -> AppSettings {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func credentialStatus() async throws -> CredentialStatus {
        try Task.checkCancellation()
        return CredentialStatus(configured: [])
    }
    public func setCredential(kind: CredentialKind, value: String) async throws {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
    public func clearCredential(kind: CredentialKind) async throws {
        try Task.checkCancellation()
        throw AppError(code: .featureUnavailable)
    }
}
