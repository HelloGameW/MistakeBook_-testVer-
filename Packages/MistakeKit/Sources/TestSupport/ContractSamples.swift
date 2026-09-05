// Synthetic data for contract compilation and previews; never OCR quality evidence.
import Foundation
import Contracts

public enum ContractSamples {
    public static func confidence() -> Confidence {
        Confidence(value: 0.5, source: .vision, calibrated: false)
    }
    public static func serviceWarning() -> ServiceWarning {
        ServiceWarning(code: "synthetic", message: "synthetic", regionID: nil)
    }
    public static func imageTransformMetadata() -> ImageTransformMetadata {
        ImageTransformMetadata(operation: nil, sourceRect: nil, mappingToParent: nil)
    }
    public static func imageAsset() -> ImageAsset {
        ImageAsset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, parentAssetID: nil, role: .raw, pixelWidth: 1, pixelHeight: 1, contentHash: "synthetic", mediaType: .jpeg, relativePath: "synthetic", transform: ContractSamples.imageTransformMetadata(), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    public static func importedPage() -> ImportedPage {
        ImportedPage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, bytes: Data([0]), mediaType: .jpeg, sourceName: "synthetic", order: 1)
    }
    public static func imagePayload() -> ImagePayload {
        ImagePayload(assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, bytes: Data([0]), mediaType: .jpeg, orientation: .up, pixelWidth: 1, pixelHeight: 1)
    }
    public static func sourceRegion() -> SourceRegion {
        SourceRegion(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, normalizedRect: .fullPage, purpose: .stem, isUserConfirmed: false)
    }
    public static func assetTransaction() -> AssetTransaction {
        AssetTransaction(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    public static func importedAssets() -> ImportedAssets {
        ImportedAssets(raw: ContractSamples.imageAsset(), working: ContractSamples.imageAsset(), duplicateOfAssetID: nil)
    }
    public static func imageTransformRequest() -> ImageTransformRequest {
        ImageTransformRequest(sourceAssetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, operation: .rotateClockwise90, cropRect: nil, affectedRegions: [])
    }
    public static func imageTransformResult() -> ImageTransformResult {
        ImageTransformResult(derivedAsset: ContractSamples.imageAsset(), sourceToDerived: nil, affectedRegions: [], warnings: [])
    }
    public static func assetRetentionToken() -> AssetRetentionToken {
        AssetRetentionToken(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assetIDs: [], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    public static func assetCleanupResult() -> AssetCleanupResult {
        AssetCleanupResult(removedAssetIDs: [], warnings: [])
    }
    public static func thumbnailRequest() -> ThumbnailRequest {
        ThumbnailRequest(assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, maxPixelDimension: 1)
    }
    public static func oCRLine() -> OCRLine {
        OCRLine(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, regionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, rawText: "synthetic", confidence: nil, scriptStyle: .printed, normalizedRect: .fullPage)
    }
    public static func segmentationCandidate() -> SegmentationCandidate {
        SegmentationCandidate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, order: 1, regions: [], lineIDs: [], needsConfirmation: false, warnings: [])
    }
    public static func recognizedPage() -> RecognizedPage {
        RecognizedPage(assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, regions: [], lines: [], providerID: "synthetic", providerVersion: "synthetic", supportedLanguages: [], warnings: [], candidates: [])
    }
    public static func recognitionOptions() -> RecognitionOptions {
        RecognitionOptions(languages: [], quality: .accurate, usesLanguageCorrection: false, maxPixelDimension: 1)
    }
    public static func segmentationOptions() -> SegmentationOptions {
        SegmentationOptions(allowOverlappingRegions: false)
    }
    public static func editableText() -> EditableText {
        EditableText(rawText: "synthetic", correctedText: nil, provenance: .ocr, isLocked: false)
    }
    public static func evidence() -> Evidence {
        Evidence(regionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, lineID: nil, quote: nil, evidenceSource: .student)
    }
    public static func referenceAnswerSource() -> ReferenceAnswerSource {
        ReferenceAnswerSource(provenance: .ocr, label: "synthetic", regionIDs: [])
    }
    public static func hypothesis() -> Hypothesis {
        Hypothesis(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, kind: .recognitionConcern, summary: "synthetic", evidence: [], reason: "synthetic", nextAction: "synthetic", certainty: .tentative, userDecision: .pending)
    }
    public static func analysisResult() -> AnalysisResult {
        AnalysisResult(status: .hypotheses, hypotheses: [], limitations: [], engineID: "synthetic", engineVersion: "synthetic", inputContentRevision: 1, referenceAnswerSource: nil)
    }
    public static func analysisOptions() -> AnalysisOptions {
        AnalysisOptions(useEnhancedModel: false, language: "synthetic", timeoutSeconds: 0.5)
    }
    public static func taxonomyNode() -> TaxonomyNode {
        TaxonomyNode(id: "synthetic", parentID: nil, name: "synthetic", subjectID: "synthetic", aliases: [], origin: .seed, isActive: false, version: 1, userModifiedFields: [])
    }
    public static func classificationCandidate() -> ClassificationCandidate {
        ClassificationCandidate(nodeID: "synthetic", score: nil, basis: "synthetic", evidence: [], source: .none, calibrated: false, validationPolicyID: nil)
    }
    public static func classificationResult() -> ClassificationResult {
        ClassificationResult(subjectID: nil, candidates: [], primaryNodeID: nil, assignmentState: .unclassified, assignedBy: .none, taxonomyVersion: "synthetic", inputContentRevision: 1, suggestedTags: [])
    }
    public static func taxonomySnapshot() -> TaxonomySnapshot {
        TaxonomySnapshot(version: "synthetic", nodes: [])
    }
    public static func autoArchiveRule() -> AutoArchiveRule {
        AutoArchiveRule(id: "synthetic", nodeID: "synthetic", minimumScore: nil, validationEvidenceID: "synthetic")
    }
    public static func autoArchivePolicy() -> AutoArchivePolicy {
        AutoArchivePolicy(version: "synthetic", enabledRules: [])
    }
    public static func classificationOptions() -> ClassificationOptions {
        ClassificationOptions(policy: ContractSamples.autoArchivePolicy(), useEnhancedModel: false)
    }
    public static func taxonomyNodePatch() -> TaxonomyNodePatch {
        TaxonomyNodePatch(expectedVersion: 1, name: .unchanged, parentID: .unchanged, aliases: .unchanged, isActive: .unchanged)
    }
    public static func taxonomyDeleteRequest() -> TaxonomyDeleteRequest {
        TaxonomyDeleteRequest(nodeID: "synthetic", expectedTaxonomyVersion: "synthetic", mode: .rejectIfReferenced)
    }
    public static func classificationSelection() -> ClassificationSelection {
        ClassificationSelection(primaryNodeID: nil, tags: [], expectedRecordRevision: 1, expectedTaxonomyVersion: "synthetic")
    }
    public static func operationOutcome() -> OperationOutcome {
        OperationOutcome(state: .pending, error: nil, inputContentRevision: 1)
    }
    public static func recordProcessingStatus() -> RecordProcessingStatus {
        RecordProcessingStatus(ocr: ContractSamples.operationOutcome(), analysis: ContractSamples.operationOutcome(), classification: ContractSamples.operationOutcome())
    }
    public static func mistakeRecord() -> MistakeRecord {
        MistakeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, schemaVersion: 1, recordRevision: 1, contentRevision: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000), sourceRegions: [], ocrLines: [], stem: ContractSamples.editableText(), studentWork: ContractSamples.editableText(), referenceAnswer: nil, referenceAnswerSource: nil, analysisResult: nil, classification: ContractSamples.classificationResult(), notes: "synthetic", tags: [], reviewState: .new, reviewRequired: false, reviewReasons: [], processingStatus: ContractSamples.recordProcessingStatus())
    }
    public static func recordContentSnapshot() -> RecordContentSnapshot {
        RecordContentSnapshot(recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, contentRevision: 1, sourceRegions: [], ocrLines: [], stem: ContractSamples.editableText(), studentWork: ContractSamples.editableText(), referenceAnswer: nil, referenceAnswerSource: nil)
    }
    public static func hypothesisDecision() -> HypothesisDecision {
        HypothesisDecision(hypothesisID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, inputContentRevision: 1, decision: .pending)
    }
    public static func recordEditPatch() -> RecordEditPatch {
        RecordEditPatch(expectedRecordRevision: 1, stem: .unchanged, studentWork: .unchanged, referenceAnswer: .unchanged, referenceAnswerSource: .unchanged, sourceRegions: .unchanged, notes: .unchanged, tags: .unchanged, hypothesisDecisions: [])
    }
    public static func manualRecordDraft() -> ManualRecordDraft {
        ManualRecordDraft(stem: "synthetic", studentWork: "synthetic", referenceAnswer: nil, notes: "synthetic", tags: [])
    }
    public static func processingJob() -> ProcessingJob {
        ProcessingJob(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, batchID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, producedRecordIDs: [], state: .queued, stage: .preprocessing, attempt: 1, completedUnits: 1, totalUnits: nil, error: nil, inputContentRevision: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000), startedAt: nil, finishedAt: nil)
    }
    public static func importBatch() -> ImportBatch {
        ImportBatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, jobIDs: [], createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000), cancelledAt: nil, warnings: [])
    }
    public static func batchEvent() -> BatchEvent {
        BatchEvent(batch: ContractSamples.importBatch(), jobs: [], isTerminal: false, error: nil)
    }
    public static func importOptions() -> ImportOptions {
        ImportOptions(duplicatePolicy: .skipExisting, recognition: ContractSamples.recognitionOptions())
    }
    public static func recordQuery() -> RecordQuery {
        RecordQuery(text: "synthetic", subjectID: nil, taxonomyNodeID: nil, includeDescendants: false, reviewStates: [], reviewRequiredOnly: false, includeDeleted: false, sort: .updatedNewest)
    }
    public static func pageRequest() -> PageRequest {
        PageRequest(cursor: nil, limit: 1)
    }
    public static func recordPage() -> RecordPage {
        RecordPage(records: [], nextCursor: nil)
    }
    public static func recordEvent() -> RecordEvent {
        RecordEvent(kind: .initial, recordID: nil, record: nil, error: nil)
    }
    public static func recordVersion() -> RecordVersion {
        RecordVersion(recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, recordRevision: 1, contentRevision: 1)
    }
    public static func regionAssignment() -> RegionAssignment {
        RegionAssignment(recordID: nil, regions: [], order: 1)
    }
    public static func regionEditRequest() -> RegionEditRequest {
        RegionEditRequest(jobIDs: [], replacedRecordIDs: [], expectedVersions: [], assignments: [])
    }
    public static func regionUndoToken() -> RegionUndoToken {
        RegionUndoToken(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, expiresAt: nil)
    }
    public static func regionEditResult() -> RegionEditResult {
        RegionEditResult(records: [], removedRecordIDs: [], undoToken: ContractSamples.regionUndoToken())
    }
    public static func recordImageTransformRequest() -> RecordImageTransformRequest {
        RecordImageTransformRequest(recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, expectedRecordRevision: 1, transform: ContractSamples.imageTransformRequest())
    }
    public static func recordImageTransformResult() -> RecordImageTransformResult {
        RecordImageTransformResult(record: ContractSamples.mistakeRecord(), transform: ContractSamples.imageTransformResult())
    }
    public static func deletionToken() -> DeletionToken {
        DeletionToken(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, recordIDs: [], createdAt: Date(timeIntervalSince1970: 1_700_000_000), expiresAt: nil)
    }
    public static func dataInventory() -> DataInventory {
        DataInventory(recordCount: 1, assetCount: 1, activeJobCount: 1)
    }
    public static func clearDataConfirmation() -> ClearDataConfirmation {
        ClearDataConfirmation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, inventory: ContractSamples.dataInventory(), expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    public static func recordWrite() -> RecordWrite {
        RecordWrite(record: ContractSamples.mistakeRecord(), expectedRecordRevision: nil, expectedContentRevision: nil, preserveConfirmedClassification: false)
    }
    public static func recordTombstone() -> RecordTombstone {
        RecordTombstone(recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, deletedAt: Date(timeIntervalSince1970: 1_700_000_000), lastRecordRevision: 1)
    }
    public static func regionUndoState() -> RegionUndoState {
        RegionUndoState(token: ContractSamples.regionUndoToken(), beforeRecords: [], afterVersions: [], beforeJobs: [], createdRecordIDs: [])
    }
    public static func repositoryTransaction() -> RepositoryTransaction {
        RepositoryTransaction(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, recordWrites: [], deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [], batches: [], expectedJobStates: [], tombstones: [], regionUndoState: nil)
    }
    public static func jobStateGuard() -> JobStateGuard {
        JobStateGuard(jobID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, expectedState: .queued, expectedAttempt: 1)
    }
    public static func repositoryCommit() -> RepositoryCommit {
        RepositoryCommit(transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, records: [])
    }
    public static func exportImageDecision() -> ExportImageDecision {
        ExportImageDecision(regionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, disposition: .includeFullImage, cropRect: nil, answerRisk: .unknown, userConfirmed: false)
    }
    public static func exportRecord() -> ExportRecord {
        ExportRecord(record: ContractSamples.mistakeRecord(), version: ContractSamples.recordVersion(), classificationPath: [], images: [])
    }
    public static func exportSnapshot() -> ExportSnapshot {
        ExportSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: Date(timeIntervalSince1970: 1_700_000_000), records: [], retentionToken: ContractSamples.assetRetentionToken(), options: try! ExportOptions(mode: .practice, includeHandwriting: false, includeHypotheses: false, blankSpace: .medium, sort: .selectionOrder, pageSize: .a4))
    }
    public static func exportRequest() -> ExportRequest {
        ExportRequest(selection: ContractSamples.recordSelection(), options: try! ExportOptions(mode: .practice, includeHandwriting: false, includeHypotheses: false, blankSpace: .medium, sort: .selectionOrder, pageSize: .a4), imageDecisions: [])
    }
    public static func exportSummary() -> ExportSummary {
        ExportSummary(recordCount: 1, pageCount: 1, warnings: [])
    }
    public static func exportArtifact() -> ExportArtifact {
        ExportArtifact(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, fileURL: URL(fileURLWithPath: "/tmp/mistakebook-synthetic"), summary: ContractSamples.exportSummary(), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    public static func featureCapability() -> FeatureCapability {
        FeatureCapability(feature: .importImages, subjectID: nil, state: .available, reason: "synthetic", supportedLanguages: [])
    }
    public static func capabilityReport() -> CapabilityReport {
        CapabilityReport(checkedAt: Date(timeIntervalSince1970: 1_700_000_000), features: [])
    }
    public static func appSettings() -> AppSettings {
        AppSettings(recognitionLanguages: [], enhancedAnalysisEnabled: false, autoArchivePolicy: ContractSamples.autoArchivePolicy())
    }
    public static func intelligenceConfiguration() -> IntelligenceConfiguration {
        IntelligenceConfiguration(recognition: ContractSamples.recognitionOptions(), analysis: ContractSamples.analysisOptions())
    }
    public static func storageConfiguration() -> StorageConfiguration {
        StorageConfiguration(rootDirectory: URL(fileURLWithPath: "/tmp/mistakebook-synthetic"), inMemory: false, excludeFromBackup: false, protection: .completeUntilFirstUserAuthentication)
    }
    public static func workflowConfiguration() -> WorkflowConfiguration {
        WorkflowConfiguration(maxBatchSize: 1, maxConcurrentJobs: 1, initialSettings: ContractSamples.appSettings())
    }
    public static func pDFExportConfiguration() -> PDFExportConfiguration {
        PDFExportConfiguration(temporaryDirectory: URL(fileURLWithPath: "/tmp/mistakebook-synthetic"), fileLifetimeSeconds: 0.5)
    }
    public static func recordSelection() -> RecordSelection { .all(RecordQuery(text: "", subjectID: nil, taxonomyNodeID: nil, includeDescendants: true, reviewStates: [], reviewRequiredOnly: false, includeDeleted: false, sort: .updatedNewest)) }
}
