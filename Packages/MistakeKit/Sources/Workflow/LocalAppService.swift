import Foundation
import Contracts

/// The single business boundary used by UI. It composes protocol values only;
/// no Storage, Intelligence or Export implementation type is imported here.
public actor LocalAppService: AppService {
    private let repository: any MistakeRepository
    private let assets: any AssetStore
    private let intelligence: IntelligenceServices
    private let exporter: any PDFExportService
    private let seedProvider: any TaxonomySeedProvider
    private let configuration: WorkflowConfiguration
    private let credentialStore: any CredentialStore

    private var currentSettings: AppSettings
    private var didStart = false
    private var clearing = false
    private var activeOperations = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var queue: [UUID] = []
    private var runningJobID: UUID?
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var batchSubscribers: [UUID: [UUID: AsyncStream<BatchEvent>.Continuation]] = [:]
    private var globalRecordSubscribers: [UUID: AsyncStream<RecordEvent>.Continuation] = [:]
    private var recordSubscribers: [UUID: [UUID: AsyncStream<RecordEvent>.Continuation]] = [:]
    private var clearConfirmations: [UUID: ClearDataConfirmation] = [:]
    /// Import-time record content mode per unfinished batch; terminal batches are dropped.
    private var batchRecordModes: [UUID: ImportedRecordMode] = [:]

    public init(repository: any MistakeRepository, assets: any AssetStore,
                intelligence: IntelligenceServices, exporter: any PDFExportService,
                seedProvider: any TaxonomySeedProvider, configuration: WorkflowConfiguration,
                credentialStore: any CredentialStore = KeychainCredentialStore()) {
        self.repository = repository; self.assets = assets; self.intelligence = intelligence
        self.exporter = exporter; self.seedProvider = seedProvider; self.configuration = configuration
        self.credentialStore = credentialStore
        self.currentSettings = configuration.initialSettings
    }

    public func startup() async throws {
        guard !didStart else { return }
        guard configuration.maxBatchSize > 0, configuration.maxBatchSize <= 20,
              configuration.maxConcurrentJobs == 1 else { throw AppError(code: .unsupportedInput) }
        if var stored = try await repository.loadSettings() {
            // One-time default switch (GLM OCR): settings saved by an older
            // build carry the old default pair (local + Vision); upgrade them
            // so "default GLM OCR" also applies to existing installs. Explicit
            // non-default choices never match this guard and are preserved.
            if stored.resolvedProcessingMode == .local, stored.resolvedOCRProvider == .appleVision {
                stored = AppSettings(recognitionLanguages: stored.recognitionLanguages,
                    enhancedAnalysisEnabled: stored.enhancedAnalysisEnabled,
                    autoArchivePolicy: stored.autoArchivePolicy,
                    processingMode: .api, ocrProvider: .glm,
                    analysisProvider: stored.analysisProvider,
                    mistakeValueProvider: stored.mistakeValueProvider,
                    ocrModelAPI: stored.ocrModelAPI,
                    analysisModelAPI: stored.analysisModelAPI,
                    mistakeValueModelAPI: stored.mistakeValueModelAPI,
                    baiduEducation: stored.baiduEducation)
                try await repository.saveSettings(settings: stored)
            }
            currentSettings = stored
        } else { try await repository.saveSettings(settings: currentSettings) }
        let taxonomy = try await repository.loadTaxonomy()
        if taxonomy.nodes.isEmpty {
            let seed = try await seedProvider.loadSeed()
            try await repository.saveTaxonomy(snapshot: TaxonomySnapshot(version: seed.seedVersion, nodes: seed.nodes), expectedVersion: nil)
        }
        let interrupted = try await repository.listJobs(batchID: nil, states: [.running])
        for job in interrupted {
            let queued = Self.job(job, state: .queued, stage: .preprocessing, error: nil, finishedAt: nil)
            try await repository.saveJob(job: queued)
            queue.append(queued.id)
            await emitBatch(batchID: queued.batchID)
        }
        let queued = try await repository.listJobs(batchID: nil, states: [.queued])
        queue.append(contentsOf: queued.map(\.id).filter { !queue.contains($0) })
        didStart = true
        scheduleNext()
    }

    public func importPages(pages: [ImportedPage], options: ImportOptions) async throws -> UUID {
        try beginOperation()
        defer { endOperation() }
       
        try await ensureStarted()
        try Task.checkCancellation()
        guard !pages.isEmpty, pages.count <= configuration.maxBatchSize else { throw AppError(code: .unsupportedInput) }
        let batchID = UUID(); let now = Date(); var jobIDs: [UUID] = []; var warnings: [ServiceWarning] = []
        for page in pages.sorted(by: { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }) {
            var transaction: AssetTransaction?
            do {
                transaction = try await assets.beginTransaction()
                guard let transaction else { throw AppError(code: .internalFailure, isRetryable: true) }
                let imported = try await assets.importPage(page: page, transaction: transaction)
                if imported.duplicateOfAssetID != nil && options.duplicatePolicy == .skipExisting {
                    try await assets.rollback(transaction: transaction)
                    warnings.append(ServiceWarning(code: "import.duplicate", message: "发现相同图片，已跳过重复导入。", regionID: nil))
                    continue
                }
                try await assets.commit(transaction: transaction)
                let job = ProcessingJob(id: UUID(), batchID: batchID, assetID: imported.working.id,
                                        producedRecordIDs: [], state: .queued, stage: .preprocessing,
                                        attempt: 1, completedUnits: 0, totalUnits: 1, error: nil,
                                        inputContentRevision: 0, createdAt: now, updatedAt: Date(), startedAt: nil, finishedAt: nil)
                try await repository.saveJob(job: job); jobIDs.append(job.id)
            } catch is CancellationError {
                if let transaction { try? await assets.rollback(transaction: transaction) }
                throw CancellationError()
            } catch let error as AppError {
                if let transaction { try? await assets.rollback(transaction: transaction) }
                warnings.append(ServiceWarning(code: "import.pageFailed", message: error.displayMessage, regionID: nil))
            } catch {
                if let transaction { try? await assets.rollback(transaction: transaction) }
                warnings.append(ServiceWarning(code: "import.pageFailed", message: "单页导入失败，可稍后重试。", regionID: nil))
            }
        }
        let batch = ImportBatch(id: batchID, jobIDs: jobIDs, createdAt: now, updatedAt: Date(), cancelledAt: nil, warnings: warnings)
        do { try await repository.saveBatch(batch: batch) }
        catch {
            // Do not globally collect assets during a failed write: another
            // operation may have committed files but not their database references.
            throw error
        }
        batchRecordModes[batchID] = options.recordMode ?? .text
        await emitBatch(batchID: batchID)
        for id in jobIDs { enqueue(id) }
        return batchID
    }

    public func createManualRecord(draft: ManualRecordDraft) async throws -> MistakeRecord {
        try beginOperation()
        defer { endOperation() }
       
        try await ensureStarted(); try Task.checkCancellation()
        let record = Self.manualRecord(draft: draft)
        let saved = try await repository.create(record: record)
        await emitRecord(kind: .upserted, record: saved); return saved
    }

    public func observeBatch(batchID: UUID) async throws -> AsyncStream<BatchEvent> {
        try await ensureStarted()
        guard try await repository.getBatch(id: batchID) != nil else { throw AppError(code: .notFound) }
        let (stream, continuation) = AsyncStream<BatchEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let subscriptionID = UUID()
        batchSubscribers[batchID, default: [:]][subscriptionID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeBatchSubscriber(batchID: batchID, id: subscriptionID) }
        }
        await emitBatch(batchID: batchID, only: subscriptionID)
        return stream
    }

    public func observeRecords(recordID: UUID?) async throws -> AsyncStream<RecordEvent> {
        try await ensureStarted()
        if let recordID, try await repository.get(id: recordID) == nil { throw AppError(code: .notFound) }
        let (stream, continuation) = AsyncStream<RecordEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let subscriptionID = UUID()
        if let recordID { recordSubscribers[recordID, default: [:]][subscriptionID] = continuation }
        else { globalRecordSubscribers[subscriptionID] = continuation }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeRecordSubscriber(recordID: recordID, id: subscriptionID) }
        }
        if let recordID, let record = try await repository.get(id: recordID) {
            continuation.yield(RecordEvent(kind: .initial, recordID: recordID, record: record, error: nil))
        } else {
            let page = try await repository.list(query: Self.allRecordsQuery, page: PageRequest(cursor: nil, limit: 200))
            for record in page.records { continuation.yield(RecordEvent(kind: .initial, recordID: record.id, record: record, error: nil)) }
        }
        return stream
    }

    public func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage { try await repository.list(query: query, page: page) }

    public func get(id: UUID) async throws -> MistakeRecord { guard let value = try await repository.get(id: id) else { throw AppError(code: .notFound) }; return value }
    public func loadPreview(request: ThumbnailRequest) async throws -> ImagePayload { try await assets.thumbnail(request: request) }
    public func loadImage(assetID: UUID) async throws -> ImagePayload { try await assets.loadImage(assetID: assetID) }

    public func applyEdit(id: UUID, patch: RecordEditPatch) async throws -> MistakeRecord {
        try beginOperation()
        defer { endOperation() }
       
        guard let current = try await repository.get(id: id) else { throw AppError(code: .notFound) }
        guard current.recordRevision == patch.expectedRecordRevision else { throw AppError(code: .revisionConflict) }
        var stem = current.stem; var student = current.studentWork; var reference = current.referenceAnswer; var sourceRegions = current.sourceRegions; var referenceSource = current.referenceAnswerSource; var notes = current.notes; var tags = current.tags
        var contentChanged = false
        if case .set(let value) = patch.stem { if value != stem { contentChanged = true }; stem = value }
        if case .set(let value) = patch.studentWork { if value != student { contentChanged = true }; student = value }
        if case .set(let value) = patch.referenceAnswer { if value != reference { contentChanged = true }; reference = value }
        if case .set(let value) = patch.referenceAnswerSource { if value != referenceSource { contentChanged = true }; referenceSource = value }
        if case .set(let value) = patch.sourceRegions { if value != sourceRegions { contentChanged = true }; sourceRegions = value }
        if case .set(let value) = patch.notes { notes = value }
        if case .set(let value) = patch.tags { tags = value }
        var analysis = current.analysisResult
        if !patch.hypothesisDecisions.isEmpty {
            guard let existing = analysis, existing.inputContentRevision == current.contentRevision else { throw AppError(code: .revisionConflict) }
            var hypotheses = existing.hypotheses
            for decision in patch.hypothesisDecisions {
                guard decision.inputContentRevision == current.contentRevision, let index = hypotheses.firstIndex(where: { $0.id == decision.hypothesisID }) else { throw AppError(code: .revisionConflict) }
                let old = hypotheses[index]
                hypotheses[index] = Hypothesis(id: old.id, kind: old.kind, summary: old.summary, evidence: old.evidence, reason: old.reason, nextAction: old.nextAction, certainty: old.certainty, userDecision: decision.decision)
            }
            analysis = AnalysisResult(status: existing.status, hypotheses: hypotheses, limitations: existing.limitations, engineID: existing.engineID, engineVersion: existing.engineVersion, inputContentRevision: existing.inputContentRevision, referenceAnswerSource: existing.referenceAnswerSource)
        }
        let newContentRevision = contentChanged ? current.contentRevision + 1 : current.contentRevision
        let processing = contentChanged ? RecordProcessingStatus(ocr: current.processingStatus.ocr,
            analysis: OperationOutcome(state: .stale, error: nil, inputContentRevision: current.contentRevision),
            classification: OperationOutcome(state: .stale, error: nil, inputContentRevision: current.contentRevision)) : current.processingStatus
        let reasons = contentChanged ? Self.addReasons(current.reviewReasons, [.staleAnalysis, .staleClassification]) : current.reviewReasons
        let updated = Self.record(current, recordRevision: current.recordRevision + 1, contentRevision: newContentRevision,
                                   sourceRegions: sourceRegions, stem: stem, studentWork: student,
                                   referenceAnswer: reference, referenceAnswerSource: referenceSource,
                                   analysisResult: analysis, notes: notes, tags: tags,
                                   reviewRequired: contentChanged || current.reviewRequired, reviewReasons: reasons,
                                   processingStatus: processing,
                                   mistakeValue: contentChanged ? .some(nil) : .none)
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(record: updated, expectedRecordRevision: current.recordRevision, expectedContentRevision: current.contentRevision, preserveConfirmedClassification: true))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved); return saved
    }

    public func transformImage(request: RecordImageTransformRequest) async throws -> RecordImageTransformResult {
        try beginOperation()
        defer { endOperation() }
       
        guard let current = try await repository.get(id: request.recordID), current.recordRevision == request.expectedRecordRevision else { throw AppError(code: .revisionConflict) }
        let transaction = try await assets.beginTransaction()
        do {
            let transformed = try await assets.transform(request: request.transform, transaction: transaction)
            try await assets.commit(transaction: transaction)
            let updatedRegions = current.sourceRegions.map { old in transformed.affectedRegions.first(where: { $0.id == old.id }) ?? old }
            let updated = Self.record(current, recordRevision: current.recordRevision + 1, contentRevision: current.contentRevision + 1,
                                       sourceRegions: updatedRegions, stem: current.stem, studentWork: current.studentWork,
                                       referenceAnswer: current.referenceAnswer, referenceAnswerSource: current.referenceAnswerSource,
                                       analysisResult: current.analysisResult, notes: current.notes, tags: current.tags,
                                       reviewRequired: true, reviewReasons: Self.addReasons(current.reviewReasons, [.staleAnalysis, .staleClassification]),
                                       processingStatus: RecordProcessingStatus(ocr: current.processingStatus.ocr,
                                        analysis: OperationOutcome(state: .stale, error: nil, inputContentRevision: current.contentRevision),
                                        classification: OperationOutcome(state: .stale, error: nil, inputContentRevision: current.contentRevision)),
                                       mistakeValue: .some(nil))
            do {
                let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(record: updated, expectedRecordRevision: current.recordRevision, expectedContentRevision: current.contentRevision, preserveConfirmedClassification: true))).records.first ?? updated
                await emitRecord(kind: .upserted, record: saved); return RecordImageTransformResult(record: saved, transform: transformed)
            } catch {
                // Leave unreferenced files for maintenance; global cleanup here
                // can delete another in-flight operation's committed assets.
                throw error
            }
        } catch {
            try? await assets.rollback(transaction: transaction)
            throw error
        }
    }

    public func confirmRegions(request: RegionEditRequest) async throws -> RegionEditResult {
        try beginOperation()
        defer { endOperation() }
       
        guard !request.assignments.isEmpty, Set(request.replacedRecordIDs).count == request.replacedRecordIDs.count else { throw AppError(code: .unsupportedInput) }
        var oldRecords: [MistakeRecord] = []; var oldJobs: [ProcessingJob] = []
        for id in request.replacedRecordIDs { guard let record = try await repository.get(id: id) else { throw AppError(code: .notFound) }; oldRecords.append(record) }
        let relatedJobs = try await repository.listJobs(batchID: nil, states: [])
        oldJobs = relatedJobs.filter { job in request.jobIDs.contains(job.id) || !Set(job.producedRecordIDs).isDisjoint(with: request.replacedRecordIDs) }
        guard request.jobIDs.allSatisfy({ id in oldJobs.contains { $0.id == id } }),
              !oldJobs.contains(where: { $0.state == .queued || $0.state == .running }) else { throw AppError(code: .revisionConflict) }
        guard Set(request.expectedVersions.map(\.recordID)).count == request.expectedVersions.count,
              Set(request.expectedVersions.map(\.recordID)) == Set(request.replacedRecordIDs),
              Set(request.assignments.compactMap(\.recordID)).count == request.assignments.compactMap(\.recordID).count else { throw AppError(code: .unsupportedInput) }
        let expected = Dictionary(uniqueKeysWithValues: request.expectedVersions.map { ($0.recordID, $0) })
        guard expected.count == request.expectedVersions.count,
              oldRecords.allSatisfy({ expected[$0.id]?.recordRevision == $0.recordRevision && expected[$0.id]?.contentRevision == $0.contentRevision }) else { throw AppError(code: .revisionConflict) }
        let now = Date(); var writes: [RecordWrite] = []; var output: [MistakeRecord] = []; var used: Set<UUID> = []; var created: [UUID] = []
        for assignment in request.assignments.sorted(by: { $0.order < $1.order }) {
            if let assignedID = assignment.recordID, !request.replacedRecordIDs.contains(assignedID) { throw AppError(code: .unsupportedInput) }
            let matching = oldRecords.filter { record in record.sourceRegions.contains(where: { region in assignment.regions.contains(where: { $0.id == region.id }) }) }
            let base = assignment.recordID.flatMap { id in oldRecords.first(where: { $0.id == id }) }
            let value: MistakeRecord
            if let base {
                used.insert(base.id)
                value = Self.record(base, recordRevision: base.recordRevision + 1, contentRevision: base.contentRevision + 1,
                                    sourceRegions: assignment.regions, ocrLines: Self.linesForRegions(oldRecords.flatMap(\.ocrLines), regions: assignment.regions), stem: base.stem, studentWork: base.studentWork,
                                    referenceAnswer: base.referenceAnswer, referenceAnswerSource: base.referenceAnswerSource,
                                    analysisResult: base.analysisResult, notes: base.notes, tags: base.tags, reviewRequired: true,
                                    reviewReasons: Self.addReasons(base.reviewReasons, [.staleAnalysis, .staleClassification]),
                                    processingStatus: RecordProcessingStatus(ocr: base.processingStatus.ocr,
                                        analysis: OperationOutcome(state: .stale, error: nil, inputContentRevision: base.contentRevision),
                                        classification: OperationOutcome(state: .stale, error: nil, inputContentRevision: base.contentRevision)))
                writes.append(RecordWrite(record: value, expectedRecordRevision: base.recordRevision, expectedContentRevision: base.contentRevision, preserveConfirmedClassification: true))
            } else {
                let id = UUID(); created.append(id)
                let lines = Self.linesForRegions(oldRecords.flatMap(\.ocrLines), regions: assignment.regions)
                let text = lines.map(\.rawText).joined(separator: "\n")
                value = Self.emptyRecord(id: id, regions: assignment.regions, ocrLines: lines,
                    stem: text.isEmpty ? matching.map { $0.stem.displayText }.joined(separator: "\n") : text,
                    studentWork: lines.filter { $0.scriptStyle == .handwritten }.map(\.rawText).joined(separator: "\n"),
                    ocrOutcome: OperationOutcome(state: lines.isEmpty ? .unavailable : .success, error: nil, inputContentRevision: 1), reviewReasons: [.unknownRegion, .unclassified])
                writes.append(RecordWrite(record: value, expectedRecordRevision: nil, expectedContentRevision: nil, preserveConfirmedClassification: false))
            }
            output.append(value)
        }
        let removed = request.replacedRecordIDs.filter { !used.contains($0) }
        let versions = oldRecords.filter { removed.contains($0.id) }.map { RecordVersion(recordID: $0.id, recordRevision: $0.recordRevision, contentRevision: $0.contentRevision) }
        let tombstones = oldRecords.filter { removed.contains($0.id) }.map { RecordTombstone(recordID: $0.id, deletedAt: now, lastRecordRevision: $0.recordRevision) }
        let updatedJobs = oldJobs.map { job in
            let associated = output.filter { record in record.sourceRegions.contains { $0.assetID == job.assetID } }.map(\.id)
            let ids = job.producedRecordIDs.filter { !request.replacedRecordIDs.contains($0) } + associated
            return Self.job(job, producedRecordIDs: Array(Set(ids)), updatedAt: now)
        }
        let token = RegionUndoToken(id: UUID(), expiresAt: now.addingTimeInterval(600))
        let undo = RegionUndoState(token: token, beforeRecords: oldRecords, afterVersions: output.map { RecordVersion(recordID: $0.id, recordRevision: $0.recordRevision, contentRevision: $0.contentRevision) }, beforeJobs: oldJobs, createdRecordIDs: created)
        let transaction = RepositoryTransaction(id: UUID(), recordWrites: writes, deleteRecordIDs: removed,
            expectedDeletedVersions: versions, restoreRecordIDs: [], jobs: updatedJobs, batches: [],
            expectedJobStates: oldJobs.map { JobStateGuard(jobID: $0.id, expectedState: $0.state, expectedAttempt: $0.attempt) }, tombstones: tombstones, regionUndoState: undo)
        _ = try await repository.commit(transaction: transaction)
        for record in output { await emitRecord(kind: .upserted, record: record) }
        for id in removed { await emitRecord(kind: .deleted, recordID: id) }
        for job in updatedJobs { await emitBatch(batchID: job.batchID) }
        return RegionEditResult(records: output, removedRecordIDs: removed, undoToken: token)
    }

    public func undoRegionEdit(token: RegionUndoToken) async throws -> [MistakeRecord] {
        try beginOperation()
        defer { endOperation() }
       
        let state = try await repository.loadRegionUndo(token: token)
        guard token.expiresAt.map({ $0 > Date() }) ?? true else { throw AppError(code: .expiredToken) }
        var writes: [RecordWrite] = []; var restore: [UUID] = []; var delete: [UUID] = []; var deleteVersions: [RecordVersion] = []
        for before in state.beforeRecords {
            guard let current = try await repository.get(id: before.id) else {
                let tombstones = try await repository.loadTombstones(); guard tombstones.contains(where: { $0.recordID == before.id }) else { throw AppError(code: .revisionConflict) }; restore.append(before.id); writes.append(RecordWrite(record: Self.record(before, recordRevision: before.recordRevision + 1, contentRevision: before.contentRevision + 1, updatedAt: Date()), expectedRecordRevision: before.recordRevision, expectedContentRevision: before.contentRevision, preserveConfirmedClassification: false)); continue
            }
            guard state.afterVersions.contains(where: { $0.recordID == current.id && $0.recordRevision == current.recordRevision && $0.contentRevision == current.contentRevision }) else { throw AppError(code: .revisionConflict) }
            writes.append(RecordWrite(record: Self.record(before, recordRevision: current.recordRevision + 1, contentRevision: current.contentRevision + 1, updatedAt: Date()), expectedRecordRevision: current.recordRevision, expectedContentRevision: current.contentRevision, preserveConfirmedClassification: false))
        }
        for id in state.createdRecordIDs {
            if let current = try await repository.get(id: id) {
                guard state.afterVersions.contains(where: { $0.recordID == id && $0.recordRevision == current.recordRevision }) else { throw AppError(code: .revisionConflict) }
                delete.append(id); deleteVersions.append(RecordVersion(recordID: id, recordRevision: current.recordRevision, contentRevision: current.contentRevision))
            }
        }
        let currentJobs = try await repository.listJobs(batchID: nil, states: [])
        guard state.beforeJobs.allSatisfy({ old in currentJobs.contains { $0.id == old.id && $0.attempt == old.attempt && $0.state == old.state } }) else { throw AppError(code: .revisionConflict) }
        let jobs = try await reconstructJobs(before: state.beforeJobs)
        let jobGuards = try await guardsForJobs(jobs)
        let restoreTombstones = delete.map { id in
            RecordTombstone(recordID: id, deletedAt: Date(), lastRecordRevision: deleteVersions.first(where: { $0.recordID == id })?.recordRevision ?? 1)
        }
        _ = try await repository.commit(transaction: RepositoryTransaction(id: UUID(), recordWrites: writes, deleteRecordIDs: delete, expectedDeletedVersions: deleteVersions, restoreRecordIDs: restore, jobs: jobs, batches: [], expectedJobStates: jobGuards, tombstones: restoreTombstones, regionUndoState: nil))
        try await repository.removeRegionUndo(token: token)
        for before in state.beforeRecords { if let record = try await repository.get(id: before.id) { await emitRecord(kind: .restored, record: record) } }
        for id in state.createdRecordIDs { await emitRecord(kind: .deleted, recordID: id) }
        var restored: [MistakeRecord] = []
        for before in state.beforeRecords { if let record = try await repository.get(id: before.id) { restored.append(record) } }
        return restored
    }

    public func retry(target: JobTarget) async throws {
        try beginOperation()
        defer { endOperation() }
       
        let jobs = try await jobs(for: target)
        for job in jobs where job.state == .failed || job.state == .cancelled {
            let next = Self.job(job, state: .queued, stage: .preprocessing, attempt: job.attempt + 1, error: nil, finishedAt: nil, updatedAt: Date())
            try await repository.saveJob(job: next); enqueue(next.id); await emitBatch(batchID: next.batchID)
        }
    }

    public func cancel(target: JobTarget) async throws {
        let jobs = try await jobs(for: target)
        for job in jobs where job.state == .queued || job.state == .running {
            runningTasks[job.id]?.cancel()
            let cancelled = Self.job(job, state: .cancelled, error: AppError(code: .cancelled), finishedAt: Date(), updatedAt: Date())
            try await repository.saveJob(job: cancelled); queue.removeAll { $0 == job.id }; await emitBatch(batchID: job.batchID)
        }
    }

    public func analyze(id: UUID, expectedContentRevision: Int) async throws -> MistakeRecord {
        try beginOperation()
        defer { endOperation() }
       
        guard let current = try await repository.get(id: id), current.contentRevision == expectedContentRevision else { throw AppError(code: .revisionConflict) }
        return try await performAnalysis(current: current)
    }

    public func evaluateValue(id: UUID, expectedContentRevision: Int) async throws -> MistakeValueResult {
        try beginOperation()
        defer { endOperation() }
        try await ensureStarted()
        guard let current = try await repository.get(id: id), current.contentRevision == expectedContentRevision else {
            throw AppError(code: .revisionConflict)
        }
        let result = try await intelligence.value.evaluate(snapshot: current.contentSnapshot,
            analysis: current.analysisResult, options: currentSettingsValue())
        guard result.inputContentRevision == expectedContentRevision else { throw AppError(code: .invalidModelOutput) }
        // 课程量化：用课标属性层与行为信号（同考点重复次数/掌握度/复习时效）修正复习价值。
        let quantified = await applyCurriculumQuantification(base: result, record: current)
        guard quantified.inputContentRevision == expectedContentRevision else { throw AppError(code: .invalidModelOutput) }
        let updated = Self.record(current, recordRevision: current.recordRevision + 1,
                                  mistakeValue: .some(quantified))
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(
            record: updated, expectedRecordRevision: current.recordRevision,
            expectedContentRevision: current.contentRevision, preserveConfirmedClassification: true))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved)
        return quantified
    }

    /// 课标量化体系应用：同考点出错次数 → F_repeat；复习状态 → 掌握度与到期因子。
    private func applyCurriculumQuantification(base: MistakeValueResult, record: MistakeRecord) async -> MistakeValueResult {
        guard let nodeID = record.classification.primaryNodeID, !nodeID.isEmpty else { return base }
        let times = await repeatCount(ofNode: nodeID)
        let mastery = Self.masteryValue(for: record.reviewState)
        let due: CurriculumDueState = record.reviewState == .mastered ? .notDue : .firstPending
        let kinds = record.analysisResult?.hypotheses.map(\.kind) ?? []
        return await intelligence.curriculumQuantification.quantifiedResult(
            base: base, nodeID: nodeID, hypothesisKinds: kinds, times: times, mastery: mastery, due: due) ?? base
    }

    /// 同一考点的累计错题数（含当前记录）。仓库侧走索引计数，避免全表解码。
    private func repeatCount(ofNode nodeID: String) async -> Int {
        (try? await repository.countRecords(primaryNodeID: nodeID)) ?? 0
    }

    private static func masteryValue(for state: ReviewState) -> Double {
        switch state {
        case .new: 0
        case .reviewing: 0.4
        case .mastered: 1
        }
    }

    public func setClassification(id: UUID, selection: ClassificationSelection) async throws -> MistakeRecord {
        try beginOperation()
        defer { endOperation() }
       
        guard let current = try await repository.get(id: id) else { throw AppError(code: .notFound) }
        guard current.recordRevision == selection.expectedRecordRevision else { throw AppError(code: .revisionConflict) }
        let taxonomy = try await repository.loadTaxonomy()
        guard taxonomy.version == selection.expectedTaxonomyVersion else { throw AppError(code: .revisionConflict) }
        if let nodeID = selection.primaryNodeID, taxonomy.nodes.first(where: { $0.id == nodeID && $0.isActive }) == nil { throw AppError(code: .invalidTaxonomy) }
        let subject = selection.primaryNodeID.flatMap { id in taxonomy.nodes.first(where: { $0.id == id })?.subjectID } ?? current.classification.subjectID
        let classification = ClassificationResult(subjectID: subject, candidates: current.classification.candidates,
            primaryNodeID: selection.primaryNodeID, assignmentState: .userConfirmed, assignedBy: .user,
            taxonomyVersion: taxonomy.version, inputContentRevision: current.contentRevision, suggestedTags: selection.tags)
        let updated = Self.record(current, recordRevision: current.recordRevision + 1, classification: classification,
                                  tags: selection.tags, reviewRequired: current.reviewReasons.contains { $0 != .unclassified && $0 != .staleClassification }, reviewReasons: current.reviewReasons.filter { $0 != .unclassified && $0 != .staleClassification })
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(record: updated, expectedRecordRevision: current.recordRevision, expectedContentRevision: current.contentRevision, preserveConfirmedClassification: false))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved); return saved
    }

    public func taxonomy() async throws -> TaxonomySnapshot { try await repository.loadTaxonomy() }

    public func createTaxonomyNode(node: TaxonomyNode, expectedTaxonomyVersion: String) async throws -> TaxonomySnapshot {
        try beginOperation()
        defer { endOperation() }
       
        let current = try await repository.loadTaxonomy(); guard current.version == expectedTaxonomyVersion, !current.nodes.contains(where: { $0.id == node.id }) else { throw AppError(code: .revisionConflict) }
        guard node.origin == .user, node.version >= 1 else { throw AppError(code: .invalidTaxonomy) }
        if let parentID = node.parentID {
            guard let parent = current.nodes.first(where: { $0.id == parentID }), parent.subjectID == node.subjectID else { throw AppError(code: .invalidTaxonomy) }
        } else if node.id != node.subjectID { throw AppError(code: .invalidTaxonomy) }
        let next = TaxonomySnapshot(version: Self.nextVersion(current.version), nodes: current.nodes + [node])
        try await repository.saveTaxonomy(snapshot: next, expectedVersion: current.version); return next
    }

    public func updateTaxonomyNode(id: String, patch: TaxonomyNodePatch) async throws -> TaxonomySnapshot {
        try beginOperation()
        defer { endOperation() }
       
        let current = try await repository.loadTaxonomy(); guard let old = current.nodes.first(where: { $0.id == id }), old.version == patch.expectedVersion else { throw AppError(code: .revisionConflict) }
        var name = old.name; var parentID = old.parentID; var aliases = old.aliases; var active = old.isActive; var modified = Set(old.userModifiedFields)
        if case .set(let value) = patch.name { name = value; modified.insert("name") }
        if case .set(let value) = patch.parentID { parentID = value; modified.insert("parentID") }
        if case .set(let value) = patch.aliases { aliases = value; modified.insert("aliases") }
        if case .set(let value) = patch.isActive { active = value; modified.insert("isActive") }
        let updated = TaxonomyNode(id: old.id, parentID: parentID, name: name, subjectID: old.subjectID, aliases: aliases, origin: old.origin, isActive: active, version: old.version + 1, userModifiedFields: Array(modified).sorted())
        var nodes = current.nodes; nodes[nodes.firstIndex(where: { $0.id == id })!] = updated
        let next = TaxonomySnapshot(version: Self.nextVersion(current.version), nodes: nodes)
        try await repository.saveTaxonomy(snapshot: next, expectedVersion: current.version); return next
    }

    public func deleteTaxonomyNode(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot {
        try beginOperation()
        defer { endOperation() }
        return try await repository.applyTaxonomyDeletion(request: request) }

    public func updateReviewState(id: UUID, state: ReviewState, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try beginOperation()
        defer { endOperation() }
       
        guard let current = try await repository.get(id: id), current.recordRevision == expectedRecordRevision else { throw AppError(code: .revisionConflict) }
        let updated = Self.record(current, recordRevision: current.recordRevision + 1, reviewState: state)
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(record: updated, expectedRecordRevision: current.recordRevision, expectedContentRevision: current.contentRevision, preserveConfirmedClassification: true))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved); return saved
    }

    public func setArchived(id: UUID, archived: Bool, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try beginOperation()
        defer { endOperation() }

        guard let current = try await repository.get(id: id),
              current.recordRevision == expectedRecordRevision else { throw AppError(code: .revisionConflict) }
        guard current.isArchived != archived else { return current }
        let updated = Self.record(current, recordRevision: current.recordRevision + 1, isArchived: archived)
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(
            record: updated, expectedRecordRevision: current.recordRevision,
            expectedContentRevision: current.contentRevision, preserveConfirmedClassification: true))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved)
        return saved
    }

    public func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken {
        try beginOperation()
        defer { endOperation() }
       
        let token = try await repository.delete(ids: ids, expectedVersions: expectedVersions)
        for id in ids { await emitRecord(kind: .deleted, recordID: id) }; return token
    }
    public func restore(token: DeletionToken) async throws -> [MistakeRecord] {
        try beginOperation()
        defer { endOperation() }
        let records = try await repository.restore(token: token); for record in records { await emitRecord(kind: .restored, record: record) }; return records }

    public func export(request: ExportRequest) async throws -> ExportArtifact {
        try beginOperation()
        defer { endOperation() }
       
        let records = try await selectedRecords(request.selection); guard !records.isEmpty else { throw AppError(code: .unsupportedInput) }
        let taxonomy = try await repository.loadTaxonomy(); var warnings: [ServiceWarning] = []; var exportRecords: [ExportRecord] = []; var assetIDs: [UUID] = []
        for record in records {
            let decisions = try Self.imageDecisions(record: record, request: request, warnings: &warnings)
            assetIDs.append(contentsOf: decisions.filter { $0.disposition != .exclude }.map(\.assetID))
            exportRecords.append(ExportRecord(record: record, version: RecordVersion(recordID: record.id, recordRevision: record.recordRevision, contentRevision: record.contentRevision), classificationPath: Self.classificationPath(record: record, taxonomy: taxonomy), images: decisions))
        }
        let retention = try await assets.acquireRetention(assetIDs: Array(Set(assetIDs)))
        let snapshot = ExportSnapshot(id: UUID(), createdAt: Date(), records: exportRecords, retentionToken: retention, options: request.options)
        do { let artifact = try await exporter.export(snapshot: snapshot); try? await assets.releaseRetention(token: retention); return artifact }
        catch { try? await assets.releaseRetention(token: retention); throw error }
    }
    public func releaseExport(artifactID: UUID) async throws { try await exporter.releaseExport(artifactID: artifactID) }

    public func prepareClearAllData() async throws -> ClearDataConfirmation { let token = ClearDataConfirmation(id: UUID(), inventory: try await repository.inventory(), expiresAt: Date().addingTimeInterval(60)); clearConfirmations[token.id] = token; return token }
    public func clearAllData(confirmation: ClearDataConfirmation) async throws {
        guard let issued = clearConfirmations.removeValue(forKey: confirmation.id), issued == confirmation, issued.expiresAt > Date() else { throw AppError(code: .invalidConfirmation) }
        guard !clearing else { throw AppError(code: .invalidConfirmation) }
        clearing = true
        defer { clearing = false }
        clearConfirmations.removeAll()
        for task in runningTasks.values { task.cancel() }
        queue.removeAll()
        await waitUntilIdle()
        runningJobID = nil
        try await repository.clearAll()
        try await assets.clearAll()
        try await credentialStore.removeAll()
        currentSettings = configuration.initialSettings
        for subscriptions in batchSubscribers.values { for continuation in subscriptions.values { continuation.finish() } }
        batchSubscribers.removeAll()
        for continuation in globalRecordSubscribers.values { continuation.yield(RecordEvent(kind: .cleared, recordID: nil, record: nil, error: nil)); continuation.finish() }
        for subscriptions in recordSubscribers.values { for continuation in subscriptions.values { continuation.yield(RecordEvent(kind: .cleared, recordID: nil, record: nil, error: nil)); continuation.finish() } }
        globalRecordSubscribers.removeAll(); recordSubscribers.removeAll(); didStart = false
    }
    public func capabilities() async throws -> CapabilityReport {
        let report = try await intelligence.capabilities.capabilities()
        let extras = [FeatureCapability(feature: .importImages, subjectID: nil, state: .available, reason: "支持相册、文件和扫描导入。", supportedLanguages: []), FeatureCapability(feature: .pdfExport, subjectID: nil, state: .available, reason: "可生成练习版或含解析版 PDF。", supportedLanguages: [])]
        return CapabilityReport(checkedAt: Date(), features: report.features + extras)
    }
    public func settings() async throws -> AppSettings { try await ensureStarted(); return currentSettings }
    public func updateSettings(settings: AppSettings) async throws -> AppSettings {
        try beginOperation()
        defer { endOperation() }
        try await ensureStarted(); try await repository.saveSettings(settings: settings); currentSettings = settings; return settings }
    public func credentialStatus() async throws -> CredentialStatus {
        try await ensureStarted(); return try await credentialStore.status()
    }
    public func setCredential(kind: CredentialKind, value: String) async throws {
        try await ensureStarted(); try await credentialStore.write(kind: kind, value: value)
    }
    public func clearCredential(kind: CredentialKind) async throws {
        try await ensureStarted(); try await credentialStore.remove(kind: kind)
    }

    private func ensureStarted() async throws {
        guard !clearing else { throw CancellationError() }
        if !didStart { try await startup() }
    }
    private func beginOperation() throws {
        guard !clearing else { throw CancellationError() }
        activeOperations += 1
    }
    private func endOperation() {
        activeOperations -= 1
        if activeOperations == 0 {
            let waiters = idleWaiters; idleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }
    private func waitUntilIdle() async {
        if activeOperations == 0 { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }
    private func removeBatchSubscriber(batchID: UUID, id: UUID) {
        batchSubscribers[batchID]?.removeValue(forKey: id)
        if batchSubscribers[batchID]?.isEmpty == true { batchSubscribers.removeValue(forKey: batchID) }
    }
    private func removeRecordSubscriber(recordID: UUID?, id: UUID) {
        if let recordID {
            recordSubscribers[recordID]?.removeValue(forKey: id)
            if recordSubscribers[recordID]?.isEmpty == true { recordSubscribers.removeValue(forKey: recordID) }
        } else { globalRecordSubscribers.removeValue(forKey: id) }
    }

    private func scheduleNext() {
        guard !clearing, runningJobID == nil, let next = queue.first else { return }
        queue.removeFirst(); runningJobID = next
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.run(jobID: next)
        }
        runningTasks[next] = task
    }
    private func enqueue(_ id: UUID) { if !queue.contains(id) && runningJobID != id { queue.append(id) }; scheduleNext() }

    private func run(jobID: UUID) async {
        do { try beginOperation() } catch { return }
        defer { endOperation() }
        defer { runningTasks.removeValue(forKey: jobID); if runningJobID == jobID { runningJobID = nil }; scheduleNext() }
        let initial: ProcessingJob
        do {
            guard let value = try await repository.getJob(id: jobID) else { return }
            initial = value
        } catch { return }
        guard initial.state == .queued else { return }
        do {
            guard let running = try await transition(jobID: jobID, state: .running, stage: .preprocessing) else { return }
            let image: ImagePayload
            do { image = try await assets.loadImage(assetID: running.assetID) }
            catch { throw AppError(code: .assetMissing) }
            try Task.checkCancellation(); _ = try await transition(jobID: jobID, state: .running, stage: .recognizing)
            let page: RecognizedPage
            do { page = try await intelligence.ocr.recognize(image: image, options: currentSettingsRecognition()) }
            catch is CancellationError { throw CancellationError() }
            // 识别失败：保留原图草稿供人工录入，但任务状态必须如实标记为失败（可重试）。
            catch let error as AppError { try await createOCRFailureDraft(job: running, error: error); try await finish(jobID: jobID, state: .failed, error: error); return }
            catch { try await createOCRFailureDraft(job: running, error: AppError(code: .internalFailure, isRetryable: true)); try await finish(jobID: jobID, state: .failed, error: AppError(code: .internalFailure, isRetryable: true)); return }
            try Task.checkCancellation(); _ = try await transition(jobID: jobID, state: .running, stage: .segmenting)
            let candidates: [SegmentationCandidate]
            do { candidates = try await intelligence.segmentation.segment(page: page, options: SegmentationOptions(allowOverlappingRegions: true)) }
            catch is CancellationError { throw CancellationError() }
            catch { candidates = [Self.fullPageCandidate(page: page, assetID: running.assetID)] }
            let recordMode = batchRecordModes[running.batchID] ?? .text
            let records = try await ensureRecords(job: running, page: page, candidates: candidates, recordMode: recordMode)
            _ = try await transition(jobID: jobID, state: .running, stage: .analyzing)
            for record in records {
                try Task.checkCancellation()
                do { _ = try await performAnalysis(current: record) }
                catch let error as AppError where error.code == .revisionConflict || error.code == .notFound { continue }
            }
            _ = try await transition(jobID: jobID, state: .running, stage: .classifying)
            for record in records {
                try Task.checkCancellation()
                if let latest = try? await repository.get(id: record.id), latest.classification.assignmentState != .userConfirmed {
                    _ = try await performClassification(current: latest)
                }
            }
            _ = try await transition(jobID: jobID, state: .running, stage: .saving)
            try await finish(jobID: jobID, state: .succeeded, error: nil)
        } catch is CancellationError { try? await finish(jobID: jobID, state: .cancelled, error: AppError(code: .cancelled)) }
        catch let error as AppError { try? await finish(jobID: jobID, state: .failed, error: error) }
        catch { try? await finish(jobID: jobID, state: .failed, error: AppError(code: .internalFailure, isRetryable: true)) }
    }

    private func transition(jobID: UUID, state: JobState, stage: JobStage) async throws -> ProcessingJob? {
        guard let current = try await repository.getJob(id: jobID), current.state != .cancelled else { return nil }
        let updated = Self.job(current, state: state, stage: stage, startedAt: current.startedAt ?? Date(), updatedAt: Date())
        try await repository.saveJob(job: updated); await emitBatch(batchID: updated.batchID); return updated
    }
    private func finish(jobID: UUID, state: JobState, error: AppError?) async throws {
        guard let current = try await repository.getJob(id: jobID), current.state != .cancelled else { return }
        let updated = Self.job(current, state: state, error: error, finishedAt: Date(), completedUnits: state == .succeeded ? current.totalUnits ?? 1 : current.completedUnits, updatedAt: Date())
        try await repository.saveJob(job: updated); await emitBatch(batchID: updated.batchID)
    }

    private func ensureRecords(job: ProcessingJob, page: RecognizedPage, candidates: [SegmentationCandidate],
                               recordMode: ImportedRecordMode) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        guard let current = try await repository.getJob(id: job.id), current.state == .running, current.attempt == job.attempt else { throw CancellationError() }
        if !current.producedRecordIDs.isEmpty {
            var existing: [MistakeRecord] = []
            for id in current.producedRecordIDs { if let record = try await repository.get(id: id) { existing.append(record) } }
            return existing
        }
        // Providers must reference the job's working image; normalize any
        // provider-side asset id so cropping and image loading stay consistent.
        let normalizedCandidates = candidates.map { candidate in
            SegmentationCandidate(id: candidate.id, order: candidate.order,
                regions: candidate.regions.map { Self.rebasingRegion($0, from: page.assetID, to: job.assetID) },
                lineIDs: candidate.lineIDs, needsConfirmation: candidate.needsConfirmation, warnings: candidate.warnings)
        }
        let normalizedLines = page.lines.map { Self.rebasingLine($0, from: page.assetID, to: job.assetID) }
        var values: [MistakeRecord] = []
        for candidate in (normalizedCandidates.isEmpty ? [Self.fullPageCandidate(page: page, assetID: job.assetID)] : normalizedCandidates).sorted(by: { $0.order < $1.order }) {
            let lines = Self.linesForRegions(normalizedLines.filter { candidate.lineIDs.contains($0.id) }, regions: candidate.regions)
            let stemLines = lines.filter { line in candidate.regions.first(where: { $0.id == line.regionID })?.purpose != .studentWork && line.scriptStyle != .handwritten }
            let studentLines = lines.filter { line in candidate.regions.first(where: { $0.id == line.regionID })?.purpose == .studentWork || line.scriptStyle == .handwritten }
            var reasons: [ReviewReason] = [.unclassified]
            if candidate.needsConfirmation { reasons.append(.unknownRegion) }
            if lines.contains(where: { ($0.confidence?.value ?? 1) < 0.6 }) { reasons.append(.lowConfidence) }
            if lines.isEmpty { reasons.append(.emptyText) }
            // Image mode crops the question region per 题号 candidate; a failed
            // crop falls back to the uncropped regions instead of dropping the record.
            let regions: [SourceRegion]
            if recordMode == .image, !candidate.regions.isEmpty {
                regions = (try? await cropCandidateRegions(candidate.regions)) ?? candidate.regions
            } else {
                regions = candidate.regions
            }
            // Red-pen grading strokes on the question image mark likely-wrong answers.
            var recordReasons = reasons
            if let markAssetID = regions.first?.assetID, let markPayload = try? await assets.loadImage(assetID: markAssetID) {
                let focus: NormalizedRect? = regions.first?.assetID == job.assetID ? Self.unionNormalizedRect(of: regions) : nil
                if await intelligence.gradingMarkDetection.detectGradingMarks(payload: markPayload, focus: focus) {
                    recordReasons.append(.redPenMarks)
                }
            }
            values.append(Self.emptyRecord(id: UUID(), regions: regions, ocrLines: lines,
                stem: stemLines.map(\.rawText).joined(separator: "\n"), studentWork: studentLines.map(\.rawText).joined(separator: "\n"),
                ocrOutcome: OperationOutcome(state: .success, error: nil, inputContentRevision: 1), reviewReasons: recordReasons))
        }
        return try await saveDrafts(values, job: current)
    }

    /// Crops the union of the candidate's regions from the working image into a
    /// derived asset and rebinds the regions to it.
    private func cropCandidateRegions(_ regions: [SourceRegion]) async throws -> [SourceRegion] {
        guard let sourceAssetID = regions.first?.assetID, let union = Self.unionNormalizedRect(of: regions) else { return regions }
        let transaction = try await assets.beginTransaction()
        do {
            let transformed = try await assets.transform(request: ImageTransformRequest(
                sourceAssetID: sourceAssetID, operation: .crop, cropRect: union, affectedRegions: regions),
                transaction: transaction)
            try await assets.commit(transaction: transaction)
            return transformed.affectedRegions.isEmpty ? regions : transformed.affectedRegions
        } catch {
            try? await assets.rollback(transaction: transaction)
            throw error
        }
    }

    private static func unionNormalizedRect(of regions: [SourceRegion]) -> NormalizedRect? {
        guard let first = regions.first else { return nil }
        let minX = regions.map { $0.normalizedRect.x }.min() ?? first.normalizedRect.x
        let minY = regions.map { $0.normalizedRect.y }.min() ?? first.normalizedRect.y
        let maxX = regions.map { $0.normalizedRect.x + $0.normalizedRect.width }.max() ?? 1
        let maxY = regions.map { $0.normalizedRect.y + $0.normalizedRect.height }.max() ?? 1
        let x = max(0, minX), y = max(0, minY)
        let right = min(1, maxX), bottom = min(1, maxY)
        return try? NormalizedRect(x: x, y: y, width: max(0.001, right - x), height: max(0.001, bottom - y))
    }

    private static func rebasingRegion(_ region: SourceRegion, from pageAssetID: UUID, to jobAssetID: UUID) -> SourceRegion {
        guard region.assetID == pageAssetID, pageAssetID != jobAssetID else { return region }
        return SourceRegion(id: region.id, assetID: jobAssetID, normalizedRect: region.normalizedRect,
                            purpose: region.purpose, isUserConfirmed: region.isUserConfirmed)
    }

    private static func rebasingLine(_ line: OCRLine, from pageAssetID: UUID, to jobAssetID: UUID) -> OCRLine {
        guard line.assetID == pageAssetID, pageAssetID != jobAssetID else { return line }
        return OCRLine(id: line.id, regionID: line.regionID, assetID: jobAssetID, rawText: line.rawText,
                       confidence: line.confidence, scriptStyle: line.scriptStyle, normalizedRect: line.normalizedRect)
    }

    private func saveDrafts(_ records: [MistakeRecord], job: ProcessingJob) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        let updated = Self.job(job, producedRecordIDs: records.map(\.id), totalUnits: max(1, records.count), inputContentRevision: 1)
        let commit = try await repository.commit(transaction: RepositoryTransaction(id: job.id,
            recordWrites: records.map { RecordWrite(record: $0, expectedRecordRevision: nil, expectedContentRevision: nil, preserveConfirmedClassification: false) },
            deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [updated], batches: [],
            expectedJobStates: [JobStateGuard(jobID: job.id, expectedState: .running, expectedAttempt: job.attempt)], tombstones: [], regionUndoState: nil))
        await emitBatch(batchID: job.batchID)
        for record in commit.records { await emitRecord(kind: .upserted, record: record) }
        return commit.records
    }

    private func createOCRFailureDraft(job: ProcessingJob, error: AppError) async throws {
        try Task.checkCancellation()
        guard let current = try await repository.getJob(id: job.id), current.state == .running, current.attempt == job.attempt else { throw CancellationError() }
        if !current.producedRecordIDs.isEmpty { return }
        let region = SourceRegion(id: UUID(), assetID: job.assetID, normalizedRect: .fullPage, purpose: .unknown, isUserConfirmed: false)
        let record = Self.emptyRecord(id: UUID(), regions: [region], ocrLines: [], stem: "", studentWork: "", ocrOutcome: OperationOutcome(state: .failed, error: error, inputContentRevision: 1), reviewReasons: [.ocrFailed, .emptyText, .unclassified])
        _ = try await saveDrafts([record], job: current)
    }

    private static func linesForRegions(_ lines: [OCRLine], regions: [SourceRegion]) -> [OCRLine] {
        var seen: Set<UUID> = []
        return lines.compactMap { line in
            guard seen.insert(line.id).inserted else { return nil }
            let x = line.normalizedRect.x + line.normalizedRect.width / 2
            let y = line.normalizedRect.y + line.normalizedRect.height / 2
            guard let region = regions.first(where: { r in r.assetID == line.assetID && x >= r.normalizedRect.x && x <= r.normalizedRect.x + r.normalizedRect.width && y >= r.normalizedRect.y && y <= r.normalizedRect.y + r.normalizedRect.height }) else { return nil }
            return OCRLine(id: line.id, regionID: region.id, assetID: line.assetID, rawText: line.rawText, confidence: line.confidence, scriptStyle: line.scriptStyle, normalizedRect: line.normalizedRect)
        }
    }

    private func performAnalysis(current: MistakeRecord) async throws -> MistakeRecord {
        let expected = current.contentRevision; let result: AnalysisResult
        do { result = try await intelligence.analysis.analyze(snapshot: current.contentSnapshot, options: currentSettingsAnalysis()) }
        catch is CancellationError { throw CancellationError() }
        catch let error as AppError {
            return try await updateAnalysisStatus(id: current.id, expectedContentRevision: expected, state: .failed, error: error, result: nil)
        } catch { return try await updateAnalysisStatus(id: current.id, expectedContentRevision: expected, state: .failed, error: AppError(code: .internalFailure, isRetryable: true), result: nil) }
        guard result.inputContentRevision == expected else { throw AppError(code: .invalidModelOutput) }
        try Task.checkCancellation()
        let state: OperationState = result.status == .unavailable ? .unavailable : .success
        return try await updateAnalysisStatus(id: current.id, expectedContentRevision: expected, state: state, error: nil, result: result)
    }

    private func updateAnalysisStatus(id: UUID, expectedContentRevision: Int, state: OperationState, error: AppError?, result: AnalysisResult?) async throws -> MistakeRecord {
        guard let latest = try await repository.get(id: id), latest.contentRevision == expectedContentRevision else { throw AppError(code: .revisionConflict) }
        let updated = Self.record(latest, recordRevision: latest.recordRevision + 1, analysisResult: result,
            reviewRequired: state != .success || latest.reviewRequired,
            reviewReasons: state == .success ? latest.reviewReasons.filter { $0 != .staleAnalysis } : Self.addReasons(latest.reviewReasons, [.modelUnavailable]),
            processingStatus: RecordProcessingStatus(ocr: latest.processingStatus.ocr,
                analysis: OperationOutcome(state: state, error: error, inputContentRevision: expectedContentRevision), classification: latest.processingStatus.classification))
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(record: updated, expectedRecordRevision: latest.recordRevision, expectedContentRevision: expectedContentRevision, preserveConfirmedClassification: true))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved); return saved
    }

    private func performClassification(current: MistakeRecord) async throws -> MistakeRecord {
        let taxonomy = try await repository.loadTaxonomy()
        let result = try await intelligence.classification.classify(snapshot: current.contentSnapshot, taxonomy: taxonomy, options: ClassificationOptions(policy: currentSettings.autoArchivePolicy, useEnhancedModel: currentSettings.enhancedAnalysisEnabled))
        guard result.inputContentRevision == current.contentRevision, result.candidates.allSatisfy({ candidate in taxonomy.nodes.contains { $0.id == candidate.nodeID && $0.isActive } }) else { throw AppError(code: .invalidModelOutput) }
        let final = Self.applyAutomaticPolicy(result, policy: currentSettings.autoArchivePolicy)
        let updated = Self.record(current, recordRevision: current.recordRevision + 1, classification: final,
                                  reviewRequired: final.assignmentState != .automatic && final.assignmentState != .userConfirmed,
                                  reviewReasons: final.assignmentState == .automatic ? current.reviewReasons.filter { $0 != .unclassified } : Self.addReasons(current.reviewReasons, [.unclassified]),
                                  processingStatus: RecordProcessingStatus(ocr: current.processingStatus.ocr, analysis: current.processingStatus.analysis, classification: OperationOutcome(state: .success, error: nil, inputContentRevision: current.contentRevision)))
        let saved = try await repository.commit(transaction: Self.recordTransaction(id: UUID(), write: RecordWrite(record: updated, expectedRecordRevision: current.recordRevision, expectedContentRevision: current.contentRevision, preserveConfirmedClassification: true))).records.first ?? updated
        await emitRecord(kind: .upserted, record: saved); return saved
    }

    private func transitionForJob(_ id: UUID, _ state: JobState) async throws -> ProcessingJob? { try await transition(jobID: id, state: state, stage: .preprocessing) }
    private func jobs(for target: JobTarget) async throws -> [ProcessingJob] { switch target { case .job(let id): guard let job = try await repository.getJob(id: id) else { throw AppError(code: .notFound) }; return [job]; case .batch(let id): return try await repository.listJobs(batchID: id, states: []) } }
    private func reconstructJobs(before: [ProcessingJob]) async throws -> [ProcessingJob] { before.map { old in Self.job(old, updatedAt: Date()) } }
    private func guardsForJobs(_ jobs: [ProcessingJob]) async throws -> [JobStateGuard] {
        var result: [JobStateGuard] = []
        for job in jobs {
            if let current = try await repository.getJob(id: job.id) {
                result.append(JobStateGuard(jobID: current.id, expectedState: current.state, expectedAttempt: current.attempt))
            }
        }
        return result
    }

    private func currentSettingsRecognition() -> RecognitionOptions {
        RecognitionOptions(languages: currentSettings.recognitionLanguages, quality: .accurate,
            usesLanguageCorrection: true, maxPixelDimension: 4096,
            processingMode: currentSettings.resolvedProcessingMode,
            provider: currentSettings.resolvedOCRProvider,
            modelAPI: currentSettings.ocrModelAPI,
            baiduEducation: currentSettings.baiduEducation)
    }
    private func currentSettingsAnalysis() -> AnalysisOptions {
        AnalysisOptions(useEnhancedModel: currentSettings.enhancedAnalysisEnabled,
            language: currentSettings.recognitionLanguages.first ?? "zh-Hans", timeoutSeconds: 60,
            processingMode: currentSettings.resolvedProcessingMode,
            provider: currentSettings.resolvedAnalysisProvider,
            modelAPI: currentSettings.analysisModelAPI)
    }
    private func currentSettingsValue() -> ValueAnalysisOptions {
        ValueAnalysisOptions(processingMode: currentSettings.resolvedProcessingMode,
            provider: currentSettings.resolvedMistakeValueProvider,
            modelAPI: currentSettings.mistakeValueModelAPI,
            language: currentSettings.recognitionLanguages.first ?? "zh-Hans", timeoutSeconds: 30)
    }

    private func selectedRecords(_ selection: RecordSelection) async throws -> [MistakeRecord] {
        switch selection { case .ids(let ids): var values: [MistakeRecord] = []; for id in ids { guard let value = try await repository.get(id: id) else { throw AppError(code: .notFound) }; values.append(value) }; return values; case .all(let query): var result: [MistakeRecord] = []; var cursor: String? = nil; repeat { let page = try await repository.list(query: query, page: PageRequest(cursor: cursor, limit: 200)); result.append(contentsOf: page.records); cursor = page.nextCursor } while cursor != nil; return result }
    }

    private func emitBatch(batchID: UUID, only subscriptionID: UUID? = nil) async {
        let batch: ImportBatch
        do { guard let value = try await repository.getBatch(id: batchID) else { return }; batch = value }
        catch { return }
        let jobs = (try? await repository.listJobs(batchID: batchID, states: [])) ?? []; let terminal = jobs.allSatisfy { $0.state == .succeeded || $0.state == .failed || $0.state == .cancelled }
        let event = BatchEvent(batch: batch, jobs: jobs, isTerminal: terminal, error: jobs.first(where: { $0.error != nil })?.error)
        if let only = subscriptionID { batchSubscribers[batchID]?[only]?.yield(event) }
        else { for continuation in batchSubscribers[batchID]?.map { $0.value } ?? [] { continuation.yield(event) } }
        if terminal { batchRecordModes.removeValue(forKey: batchID); for continuation in batchSubscribers.removeValue(forKey: batchID)?.map { $0.value } ?? [] { continuation.finish() } }
    }
    private func emitRecord(kind: RecordEventKind, recordID: UUID? = nil, record: MistakeRecord? = nil) async {
        let id = record?.id ?? recordID; let event = RecordEvent(kind: kind, recordID: id, record: record, error: nil)
        for continuation in globalRecordSubscribers.values { continuation.yield(event) }
        if let id { for continuation in recordSubscribers[id]?.map { $0.value } ?? [] { continuation.yield(event) } }
        if kind == .deleted, let id {
            for continuation in recordSubscribers.removeValue(forKey: id)?.map({ $0.value }) ?? [] { continuation.finish() }
        }
    }

    private static let allRecordsQuery = RecordQuery(text: "", subjectID: nil, taxonomyNodeID: nil, includeDescendants: true, reviewStates: [], reviewRequiredOnly: false, includeDeleted: false, sort: .updatedNewest)

    private static func recordTransaction(id: UUID, write: RecordWrite) -> RepositoryTransaction { RepositoryTransaction(id: id, recordWrites: [write], deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [], batches: [], expectedJobStates: [], tombstones: [], regionUndoState: nil) }
    private static func job(_ job: ProcessingJob, state: JobState? = nil, stage: JobStage? = nil, producedRecordIDs: [UUID]? = nil, attempt: Int? = nil, error: AppError? = nil, finishedAt: Date? = nil, startedAt: Date? = nil, completedUnits: Int? = nil, totalUnits: Int? = nil, inputContentRevision: Int? = nil, updatedAt: Date? = nil) -> ProcessingJob { ProcessingJob(id: job.id, batchID: job.batchID, assetID: job.assetID, producedRecordIDs: producedRecordIDs ?? job.producedRecordIDs, state: state ?? job.state, stage: stage ?? job.stage, attempt: attempt ?? job.attempt, completedUnits: completedUnits ?? job.completedUnits, totalUnits: totalUnits ?? job.totalUnits, error: error, inputContentRevision: inputContentRevision ?? job.inputContentRevision, createdAt: job.createdAt, updatedAt: updatedAt ?? Date(), startedAt: startedAt ?? job.startedAt, finishedAt: finishedAt) }
    private static func emptyRecord(id: UUID, regions: [SourceRegion], ocrLines: [OCRLine], stem: String, studentWork: String, ocrOutcome: OperationOutcome, reviewReasons: [ReviewReason] = [.unclassified]) -> MistakeRecord { let classification = ClassificationResult(subjectID: nil, candidates: [], primaryNodeID: nil, assignmentState: .unclassified, assignedBy: .none, taxonomyVersion: "0", inputContentRevision: 1, suggestedTags: []); return MistakeRecord(id: id, schemaVersion: ContractSchema.schemaVersion, recordRevision: 1, contentRevision: 1, createdAt: Date(), updatedAt: Date(), sourceRegions: regions, ocrLines: ocrLines, stem: EditableText(rawText: stem, correctedText: nil, provenance: .ocr, isLocked: false), studentWork: EditableText(rawText: studentWork, correctedText: nil, provenance: .ocr, isLocked: false), referenceAnswer: nil, referenceAnswerSource: nil, analysisResult: nil, classification: classification, notes: "", tags: [], reviewState: .new, reviewRequired: true, reviewReasons: reviewReasons, processingStatus: RecordProcessingStatus(ocr: ocrOutcome, analysis: OperationOutcome(state: .pending, error: nil, inputContentRevision: 1), classification: OperationOutcome(state: .pending, error: nil, inputContentRevision: 1))) }
    private static func manualRecord(draft: ManualRecordDraft) -> MistakeRecord { emptyRecord(id: UUID(), regions: [], ocrLines: [], stem: draft.stem, studentWork: draft.studentWork, ocrOutcome: OperationOutcome(state: .unavailable, error: nil, inputContentRevision: 1), reviewReasons: [.unclassified]).withManualFields(notes: draft.notes, tags: draft.tags, referenceAnswer: draft.referenceAnswer) }
    private static func record(_ base: MistakeRecord, recordRevision: Int? = nil, contentRevision: Int? = nil, sourceRegions: [SourceRegion]? = nil, ocrLines: [OCRLine]? = nil, stem: EditableText? = nil, studentWork: EditableText? = nil, referenceAnswer: EditableText?? = nil, referenceAnswerSource: ReferenceAnswerSource?? = nil, analysisResult: AnalysisResult?? = nil, classification: ClassificationResult? = nil, notes: String? = nil, tags: [String]? = nil, reviewState: ReviewState? = nil, reviewRequired: Bool? = nil, reviewReasons: [ReviewReason]? = nil, processingStatus: RecordProcessingStatus? = nil, isArchived: Bool? = nil, mistakeValue: MistakeValueResult?? = nil, updatedAt: Date? = nil) -> MistakeRecord { MistakeRecord(id: base.id, schemaVersion: base.schemaVersion, recordRevision: recordRevision ?? base.recordRevision, contentRevision: contentRevision ?? base.contentRevision, createdAt: base.createdAt, updatedAt: updatedAt ?? Date(), sourceRegions: sourceRegions ?? base.sourceRegions, ocrLines: ocrLines ?? base.ocrLines, stem: stem ?? base.stem, studentWork: studentWork ?? base.studentWork, referenceAnswer: referenceAnswer ?? base.referenceAnswer, referenceAnswerSource: referenceAnswerSource ?? base.referenceAnswerSource, analysisResult: analysisResult ?? base.analysisResult, classification: classification ?? base.classification, notes: notes ?? base.notes, tags: tags ?? base.tags, reviewState: reviewState ?? base.reviewState, reviewRequired: reviewRequired ?? base.reviewRequired, reviewReasons: reviewReasons ?? base.reviewReasons, processingStatus: processingStatus ?? base.processingStatus, isArchived: isArchived ?? base.isArchived, mistakeValue: mistakeValue ?? base.mistakeValue) }
    private static func addReasons(_ base: [ReviewReason], _ additions: [ReviewReason]) -> [ReviewReason] { var result = base; for value in additions where !result.contains(value) { result.append(value) }; return result }
    private static func nextVersion(_ value: String) -> String { value + ".next" }
    private static func applyAutomaticPolicy(_ result: ClassificationResult, policy: AutoArchivePolicy) -> ClassificationResult { guard let candidate = result.candidates.first, candidate.source == .rule, candidate.calibrated, let id = candidate.validationPolicyID, let rule = policy.enabledRules.first(where: { $0.id == id && $0.nodeID == candidate.nodeID }), rule.minimumScore.map({ (candidate.score ?? -Double.infinity) >= $0 }) ?? true, !candidate.evidence.isEmpty else { return result }; return ClassificationResult(subjectID: result.subjectID, candidates: result.candidates, primaryNodeID: candidate.nodeID, assignmentState: .automatic, assignedBy: .rule, taxonomyVersion: result.taxonomyVersion, inputContentRevision: result.inputContentRevision, suggestedTags: result.suggestedTags) }
    private static func fullPageCandidate(page: RecognizedPage, assetID: UUID) -> SegmentationCandidate { let region = page.regions.first ?? SourceRegion(id: UUID(), assetID: assetID, normalizedRect: .fullPage, purpose: .unknown, isUserConfirmed: false); let rebased = SourceRegion(id: region.id, assetID: assetID, normalizedRect: region.normalizedRect, purpose: region.purpose, isUserConfirmed: region.isUserConfirmed); let visuals = page.regions.filter { $0.id != region.id && $0.purpose == .diagram }.map { Self.rebasingRegion($0, from: page.assetID, to: assetID) }; return SegmentationCandidate(id: UUID(), order: 1, regions: [rebased] + visuals, lineIDs: page.lines.map(\.id), needsConfirmation: true, warnings: [ServiceWarning(code: "segmentation.fallback", message: "分题服务失败，已回退整页草稿；图像/表格/公式候选区域已保留。", regionID: region.id)]) }
    private static func classificationPath(record: MistakeRecord, taxonomy: TaxonomySnapshot) -> [String] { guard var id = record.classification.primaryNodeID else { return ["待分类"] }; let byID = Dictionary(uniqueKeysWithValues: taxonomy.nodes.map { ($0.id, $0) }); var result: [String] = []; var seen: Set<String> = []; while let node = byID[id], seen.insert(id).inserted { result.insert(node.name, at: 0); guard let parent = node.parentID else { break }; id = parent }; return result }
    private static func imageDecisions(record: MistakeRecord, request: ExportRequest, warnings: inout [ServiceWarning]) throws -> [ExportImageDecision] { var result: [ExportImageDecision] = []; for region in record.sourceRegions { if let provided = request.imageDecisions.first(where: { $0.regionID == region.id }) { if provided.disposition == .crop && provided.cropRect == nil { throw AppError(code: .unsupportedInput) }; result.append(provided); continue }; let risky = region.purpose == .studentWork || region.purpose == .referenceAnswer; let disposition: ExportImageDisposition = request.options.mode == .practice && risky ? .exclude : (request.options.includeHandwriting || !risky ? .includeFullImage : .exclude); if risky && request.options.mode == .practice { warnings.append(ServiceWarning(code: "export.answerRisk", message: "练习版已排除未经确认的答案/批注区域。", regionID: region.id)) }; result.append(ExportImageDecision(regionID: region.id, assetID: region.assetID, disposition: disposition, cropRect: nil, answerRisk: risky ? .mayContainAnswer : .unknown, userConfirmed: false)) }; return result }
}

private extension MistakeRecord {
    func withManualFields(notes: String, tags: [String], referenceAnswer: String?) -> MistakeRecord { MistakeRecord(id: id, schemaVersion: schemaVersion, recordRevision: recordRevision, contentRevision: contentRevision, createdAt: createdAt, updatedAt: updatedAt, sourceRegions: sourceRegions, ocrLines: ocrLines, stem: stem, studentWork: studentWork, referenceAnswer: referenceAnswer.map { EditableText(rawText: $0, correctedText: nil, provenance: .user, isLocked: false) }, referenceAnswerSource: referenceAnswer.map { _ in ReferenceAnswerSource(provenance: .user, label: "手动录入", regionIDs: []) }, analysisResult: analysisResult, classification: classification, notes: notes, tags: tags, reviewState: reviewState, reviewRequired: reviewRequired, reviewReasons: reviewReasons, processingStatus: processingStatus, isArchived: isArchived, mistakeValue: mistakeValue) }
}
