import Foundation
import SwiftData
import Contracts

/// Actor-isolated SwiftData repository. Only encoded Contracts values cross the
/// actor boundary; SwiftData model objects never escape this type.
public actor SwiftDataMistakeRepository: ModelActor, MistakeRepository {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private var context: ModelContext { modelContext }

    public init(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelContainer = container
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    public func create(record: MistakeRecord) async throws -> MistakeRecord {
        try Task.checkCancellation()
        return try applyTransaction(RepositoryTransaction(id: UUID(),
            recordWrites: [RecordWrite(record: record, expectedRecordRevision: nil, expectedContentRevision: nil, preserveConfirmedClassification: false)],
            deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [], batches: [],
            expectedJobStates: [], tombstones: [], regionUndoState: nil)).records.first ?? record
    }

    public func get(id: UUID) async throws -> MistakeRecord? {
        try Task.checkCancellation()
        return try fetchRecord(id: id, includeDeleted: false)
    }

    public func list(query: RecordQuery, page: PageRequest) async throws -> RecordPage {
        try Task.checkCancellation()
        guard (1...200).contains(page.limit) else { throw AppError(code: .unsupportedInput) }
        let fingerprint = try Self.fingerprint(query)
        let offset = try Self.decodeCursor(page.cursor, fingerprint: fingerprint)
        let taxonomy = try currentTaxonomy()
        var values = try context.fetch(FetchDescriptor<StoredRecordEntity>()).compactMap { entity -> (MistakeRecord, StoredRecordEntity)? in
            guard query.includeDeleted || !entity.isDeleted else { return nil }
            let record = try decodeRecord(entity.payload)
            guard query.includeDeleted || !entity.isDeleted else { return nil }
            return (record, entity)
        }
        values = values.filter { record, entity in
            if !query.includeDeleted && entity.isDeleted { return false }
            if let subjectID = query.subjectID, record.classification.subjectID != subjectID { return false }
            if let nodeID = query.taxonomyNodeID {
                let allowed = query.includeDescendants ? Self.descendantIDs(nodeID: nodeID, taxonomy: taxonomy) : [nodeID]
                guard allowed.contains(record.classification.primaryNodeID ?? "") else { return false }
            }
            if !query.reviewStates.isEmpty && !query.reviewStates.contains(record.reviewState) { return false }
            if query.reviewRequiredOnly && !record.reviewRequired { return false }
            if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let byID = Dictionary(uniqueKeysWithValues: taxonomy.nodes.map { ($0.id, $0) })
                var path: [String] = []; var nodeID = record.classification.primaryNodeID; var seen: Set<String> = []
                while let id = nodeID, let node = byID[id], seen.insert(id).inserted { path.append(node.name); nodeID = node.parentID }
                guard (entity.searchText + " " + path.joined(separator: " ")).localizedCaseInsensitiveContains(query.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            }
            return true
        }
        values.sort { lhs, rhs in
            let leftDate = query.sort == .updatedNewest ? lhs.0.updatedAt : lhs.0.createdAt
            let rightDate = query.sort == .updatedNewest ? rhs.0.updatedAt : rhs.0.createdAt
            if leftDate != rightDate { return query.sort == .updatedNewest ? leftDate > rightDate : leftDate < rightDate }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        let slice = Array(values.dropFirst(offset).prefix(page.limit)).map(\.0)
        let nextOffset = offset + slice.count < values.count ? offset + slice.count : nil
        return RecordPage(records: slice, nextCursor: nextOffset.map { Self.encodeCursor(offset: $0, fingerprint: fingerprint) })
    }

    public func update(record: MistakeRecord, expectedRecordRevision: Int) async throws -> MistakeRecord {
        try Task.checkCancellation()
        return try applyTransaction(RepositoryTransaction(id: UUID(),
            recordWrites: [RecordWrite(record: record, expectedRecordRevision: expectedRecordRevision,
                                       expectedContentRevision: nil, preserveConfirmedClassification: true)],
            deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [], batches: [],
            expectedJobStates: [], tombstones: [], regionUndoState: nil)).records.first ?? record
    }

    public func delete(ids: [UUID], expectedVersions: [RecordVersion]) async throws -> DeletionToken {
        try Task.checkCancellation()
        guard !ids.isEmpty, ids.count == expectedVersions.count, Set(ids).count == ids.count else { throw AppError(code: .unsupportedInput) }
        let tombstones = try ids.map { id -> RecordTombstone in
            guard let record = try fetchRecord(id: id, includeDeleted: false) else { throw AppError(code: .notFound) }
            return RecordTombstone(recordID: id, deletedAt: Date(), lastRecordRevision: record.recordRevision)
        }
        let token = DeletionToken(id: UUID(), recordIDs: ids, createdAt: Date(), expiresAt: Date().addingTimeInterval(600))
        _ = try applyTransaction(RepositoryTransaction(id: UUID(), recordWrites: [], deleteRecordIDs: ids,
            expectedDeletedVersions: expectedVersions, restoreRecordIDs: [], jobs: [], batches: [],
            expectedJobStates: [], tombstones: tombstones, regionUndoState: nil), persist: false)
        context.insert(StoredDeletionEntity(idString: token.id.uuidString, payload: try encode(token), isConsumed: false))
        try saveContext()
        return token
    }

    public func restore(token: DeletionToken) async throws -> [MistakeRecord] {
        try Task.checkCancellation()
        guard let entity = try findDeletion(token.id), !entity.isConsumed,
              token == (try decode(DeletionToken.self, entity.payload)),
              token.expiresAt.map({ $0 > Date() }) ?? true else { throw AppError(code: .expiredToken) }
        var writes: [RecordWrite] = []
        for id in token.recordIDs {
            guard let entity = try findRecordEntity(id), entity.isDeleted else { throw AppError(code: .revisionConflict) }
            let current = try decodeRecord(entity.payload)
            let restored = Self.withRevisions(current, recordRevision: current.recordRevision + 1, updatedAt: Date())
            writes.append(RecordWrite(record: restored, expectedRecordRevision: current.recordRevision,
                                      expectedContentRevision: current.contentRevision, preserveConfirmedClassification: false))
        }
        let commit = try applyTransaction(RepositoryTransaction(id: UUID(), recordWrites: writes,
            deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: token.recordIDs, jobs: [], batches: [],
            expectedJobStates: [], tombstones: [], regionUndoState: nil), persist: false)
        entity.isConsumed = true
        try saveContext()
        return commit.records
    }

    public func commit(transaction: RepositoryTransaction) async throws -> RepositoryCommit {
        try Task.checkCancellation()
        return try applyTransaction(transaction)
    }

    public func saveJob(job: ProcessingJob) async throws {
        try Task.checkCancellation()
        let current = try findJobEntity(job.id).flatMap { try? decode(ProcessingJob.self, $0.payload) }
        let guardValue = current.map { JobStateGuard(jobID: job.id, expectedState: $0.state, expectedAttempt: $0.attempt) }
        _ = try applyTransaction(RepositoryTransaction(id: UUID(), recordWrites: [], deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [job], batches: [], expectedJobStates: guardValue.map { [$0] } ?? [], tombstones: [], regionUndoState: nil))
    }

    public func getJob(id: UUID) async throws -> ProcessingJob? {
        try Task.checkCancellation()
        guard let entity = try findJobEntity(id) else { return nil }
        return try decode(ProcessingJob.self, entity.payload)
    }

    public func listJobs(batchID: UUID?, states: [JobState]) async throws -> [ProcessingJob] {
        try Task.checkCancellation()
        return try context.fetch(FetchDescriptor<StoredJobEntity>()).compactMap { entity in
            let job = try decode(ProcessingJob.self, entity.payload)
            guard (batchID == nil || job.batchID == batchID),
                  (states.isEmpty || states.contains(job.state)) else { return nil }
            return job
        }.sorted { $0.createdAt < $1.createdAt }
    }

    public func saveBatch(batch: ImportBatch) async throws {
        try Task.checkCancellation()
        let current = try findBatchEntity(batch.id).flatMap { try? decode(ImportBatch.self, $0.payload) }
        if let current, current.cancelledAt != nil && batch.cancelledAt == nil { throw AppError(code: .revisionConflict) }
        let data = try encode(batch)
        if let entity = try findBatchEntity(batch.id) { entity.payload = data; entity.updatedAt = batch.updatedAt }
        else { context.insert(StoredBatchEntity(idString: batch.id.uuidString, payload: data, updatedAt: batch.updatedAt)) }
        try saveContext()
    }

    public func getBatch(id: UUID) async throws -> ImportBatch? {
        try Task.checkCancellation()
        guard let entity = try findBatchEntity(id) else { return nil }
        return try decode(ImportBatch.self, entity.payload)
    }

    public func listBatches() async throws -> [ImportBatch] {
        try Task.checkCancellation()
        return try context.fetch(FetchDescriptor<StoredBatchEntity>()).map { try decode(ImportBatch.self, $0.payload) }.sorted { $0.createdAt < $1.createdAt }
    }

    public func loadTaxonomy() async throws -> TaxonomySnapshot { try currentTaxonomy() }

    public func saveTaxonomy(snapshot: TaxonomySnapshot, expectedVersion: String?) async throws {
        try Task.checkCancellation()
        try Self.validateTaxonomy(snapshot)
        let current = try currentTaxonomy()
        if current.nodes.isEmpty {
            guard expectedVersion == nil || expectedVersion == "0" else { throw AppError(code: .revisionConflict) }
        } else if expectedVersion != current.version { throw AppError(code: .revisionConflict) }
        let data = try encode(snapshot)
        if let entity = try findTaxonomyEntity() { entity.payload = data; entity.version = snapshot.version }
        else { context.insert(StoredTaxonomyEntity(idString: "root", payload: data, version: snapshot.version)) }
        try saveContext()
    }

    public func applyTaxonomyDeletion(request: TaxonomyDeleteRequest) async throws -> TaxonomySnapshot {
        try Task.checkCancellation()
        var snapshot = try currentTaxonomy()
        guard snapshot.version == request.expectedTaxonomyVersion,
              let target = snapshot.nodes.first(where: { $0.id == request.nodeID }), target.parentID != nil else { throw AppError(code: .invalidTaxonomy) }
        let children = snapshot.nodes.filter { $0.parentID == target.id }
        let affected = try context.fetch(FetchDescriptor<StoredRecordEntity>()).compactMap { entity -> MistakeRecord? in
            let record = try decodeRecord(entity.payload)
            guard record.classification.primaryNodeID == target.id || record.classification.candidates.contains(where: { $0.nodeID == target.id }) else { return nil }
            return record
        }
        guard request.mode != .rejectIfReferenced || (affected.isEmpty && children.isEmpty) else { throw AppError(code: .invalidTaxonomy) }
        if !children.isEmpty && request.mode != .moveToParent { throw AppError(code: .invalidTaxonomy) }
        let parentID = target.parentID
        for child in children {
            snapshot = Self.replaceNode(child.id, in: snapshot) { node in
                TaxonomyNode(id: node.id, parentID: parentID, name: node.name, subjectID: node.subjectID, aliases: node.aliases, origin: node.origin, isActive: node.isActive, version: node.version + 1, userModifiedFields: node.userModifiedFields)
            }
        }
        snapshot = TaxonomySnapshot(version: Self.nextVersion(snapshot.version), nodes: snapshot.nodes.filter { $0.id != target.id })
        var writes: [RecordWrite] = []
        for record in affected {
            let classification: ClassificationResult
            switch request.mode {
            case .moveToParent:
                let candidate = record.classification.candidates.map { $0.nodeID == target.id ? ClassificationCandidate(nodeID: parentID ?? "", score: $0.score, basis: $0.basis + "；原节点已移除", evidence: $0.evidence, source: $0.source, calibrated: $0.calibrated, validationPolicyID: $0.validationPolicyID) : $0 }
                classification = ClassificationResult(subjectID: record.classification.subjectID, candidates: candidate, primaryNodeID: record.classification.primaryNodeID == target.id ? parentID : record.classification.primaryNodeID, assignmentState: .suggested, assignedBy: .rule, taxonomyVersion: snapshot.version, inputContentRevision: record.contentRevision, suggestedTags: record.classification.suggestedTags)
            case .makeUnclassified:
                classification = ClassificationResult(subjectID: record.classification.subjectID, candidates: record.classification.candidates.filter { $0.nodeID != target.id }, primaryNodeID: nil, assignmentState: .unclassified, assignedBy: .none, taxonomyVersion: snapshot.version, inputContentRevision: record.contentRevision, suggestedTags: record.classification.suggestedTags)
            case .rejectIfReferenced: continue
            }
            writes.append(RecordWrite(record: Self.withClassification(record, classification: classification), expectedRecordRevision: record.recordRevision, expectedContentRevision: record.contentRevision, preserveConfirmedClassification: false))
        }
        try Self.validateTaxonomy(snapshot)
        let data = try encode(snapshot)
        _ = try applyTransaction(RepositoryTransaction(id: UUID(), recordWrites: writes, deleteRecordIDs: [], expectedDeletedVersions: [], restoreRecordIDs: [], jobs: [], batches: [], expectedJobStates: [], tombstones: [], regionUndoState: nil), persist: false)
        if let entity = try findTaxonomyEntity() { entity.payload = data; entity.version = snapshot.version }
        else { context.insert(StoredTaxonomyEntity(idString: "root", payload: data, version: snapshot.version)) }
        try saveContext()
        return snapshot
    }

    public func loadSettings() async throws -> AppSettings? {
        try Task.checkCancellation()
        guard let entity = try context.fetch(FetchDescriptor<StoredSettingsEntity>()).first else { return nil }
        return try decode(AppSettings.self, entity.payload)
    }

    public func saveSettings(settings: AppSettings) async throws {
        try Task.checkCancellation()
        let data = try encode(settings)
        if let entity = try context.fetch(FetchDescriptor<StoredSettingsEntity>()).first { entity.payload = data }
        else { context.insert(StoredSettingsEntity(idString: "settings", payload: data)) }
        try saveContext()
    }

    public func loadRegionUndo(token: RegionUndoToken) async throws -> RegionUndoState {
        guard let entity = try context.fetch(FetchDescriptor<StoredRegionUndoEntity>()).first(where: { $0.idString == token.id.uuidString }),
              let state = try? decode(RegionUndoState.self, entity.payload), state.token == token, state.token.expiresAt.map({ $0 > Date() }) ?? true else { throw AppError(code: .expiredToken) }
        return state
    }

    public func removeRegionUndo(token: RegionUndoToken) async throws {
        if let entity = try context.fetch(FetchDescriptor<StoredRegionUndoEntity>()).first(where: { $0.idString == token.id.uuidString }) { context.delete(entity); try saveContext() }
    }

    public func loadTombstones() async throws -> [RecordTombstone] {
        try Task.checkCancellation()
        return try context.fetch(FetchDescriptor<StoredTombstoneEntity>()).map { try decode(RecordTombstone.self, $0.payload) }
    }

    public func referencedAssetIDs() async throws -> [UUID] {
        try Task.checkCancellation()
        let records = try context.fetch(FetchDescriptor<StoredRecordEntity>()).map { try decodeRecord($0.payload) }
        let jobs = try await listJobs(batchID: nil, states: [])
        return Array(Set(records.flatMap { $0.sourceRegions.map(\.assetID) + $0.ocrLines.map(\.assetID) } + jobs.map(\.assetID)))
    }

    public func inventory() async throws -> DataInventory {
        let records = try context.fetch(FetchDescriptor<StoredRecordEntity>()).filter { !$0.isDeleted }.count
        let assets = try await referencedAssetIDs()
        let activeJobs = try await listJobs(batchID: nil, states: [.queued, .running]).count
        return DataInventory(recordCount: records, assetCount: assets.count, activeJobCount: activeJobs)
    }

    public func clearAll() async throws {
        try Task.checkCancellation()
        for entity in try context.fetch(FetchDescriptor<StoredRecordEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredJobEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredBatchEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredTaxonomyEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredSettingsEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredTombstoneEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredRegionUndoEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredDeletionEntity>()) { context.delete(entity) }
        for entity in try context.fetch(FetchDescriptor<StoredTransactionEntity>()) { context.delete(entity) }
        try saveContext()
    }

    private func applyTransaction(_ transaction: RepositoryTransaction, persist: Bool = true) throws -> RepositoryCommit {
        do {
            let result = try stageTransaction(transaction)
            if persist { try saveContext() }
            return result
        } catch { context.rollback(); throw error }
    }

    private func stageTransaction(_ transaction: RepositoryTransaction) throws -> RepositoryCommit {
        guard Set(transaction.recordWrites.map { $0.record.id }).count == transaction.recordWrites.count,
              Set(transaction.expectedDeletedVersions.map(\.recordID)).count == transaction.expectedDeletedVersions.count,
              Set(transaction.expectedJobStates.map(\.jobID)).count == transaction.expectedJobStates.count,
              Set(transaction.tombstones.map(\.recordID)).count == transaction.tombstones.count,
              Set(transaction.jobs.map(\.id)).count == transaction.jobs.count,
              Set(transaction.batches.map(\.id)).count == transaction.batches.count else { throw AppError(code: .unsupportedInput) }
        if let seen = try context.fetch(FetchDescriptor<StoredTransactionEntity>()).first(where: { $0.idString == transaction.id.uuidString }) {
            return try decode(RepositoryCommit.self, seen.payload)
        }
        var entities = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<StoredRecordEntity>()).compactMap { entity in
            guard let id = UUID(uuidString: entity.idString) else { return nil }
            return (id, entity)
        })
        var records: [MistakeRecord] = []
        var mergedWrites: [(MistakeRecord, StoredRecordEntity?, Bool)] = []
        for write in transaction.recordWrites {
            guard write.record.schemaVersion == ContractSchema.schemaVersion,
                  write.record.recordRevision >= 1, write.record.contentRevision >= 1 else { throw AppError(code: .unsupportedSchemaVersion) }
            let current = entities[write.record.id]
            if let current {
                let isRestoring = transaction.restoreRecordIDs.contains(write.record.id)
                guard (!current.isDeleted || isRestoring), let currentRecord = try? decodeRecord(current.payload),
                      write.expectedRecordRevision == currentRecord.recordRevision,
                      write.record.recordRevision == currentRecord.recordRevision + 1 else { throw AppError(code: .revisionConflict) }
                if let expected = write.expectedContentRevision, expected != currentRecord.contentRevision { throw AppError(code: .revisionConflict) }
                var value = write.record
                if write.preserveConfirmedClassification && currentRecord.classification.assignmentState == .userConfirmed {
                    value = Self.withClassification(value, classification: currentRecord.classification, advanceRevision: false)
                }
                mergedWrites.append((value, current, false)); records.append(value)
            } else {
                guard write.expectedRecordRevision == nil, write.record.recordRevision == 1 else { throw AppError(code: .revisionConflict) }
                mergedWrites.append((write.record, nil, false)); records.append(write.record)
            }
        }
        let deleteVersions = Dictionary(uniqueKeysWithValues: transaction.expectedDeletedVersions.map { ($0.recordID, $0) })
        guard deleteVersions.count == transaction.deleteRecordIDs.count else { throw AppError(code: .revisionConflict) }
        for id in transaction.deleteRecordIDs {
            guard let entity = entities[id], !entity.isDeleted, let record = try? decodeRecord(entity.payload),
                  let version = deleteVersions[id], version.recordRevision == record.recordRevision,
                  version.contentRevision == record.contentRevision else { throw AppError(code: .revisionConflict) }
        }
        for id in transaction.restoreRecordIDs {
            guard let entity = entities[id], entity.isDeleted,
                  let tombstone = try context.fetch(FetchDescriptor<StoredTombstoneEntity>()).first(where: { $0.idString == id.uuidString }),
                  let value = try? decode(RecordTombstone.self, tombstone.payload), value.lastRecordRevision == transaction.recordWrites.first(where: { $0.record.id == id })?.expectedRecordRevision else { throw AppError(code: .revisionConflict) }
        }
        let jobEntities = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<StoredJobEntity>()).compactMap { entity in
            guard let id = UUID(uuidString: entity.idString) else { return nil }
            return (id, entity)
        })
        let guards = Dictionary(uniqueKeysWithValues: transaction.expectedJobStates.map { ($0.jobID, $0) })
        for job in transaction.jobs {
            if let existing = jobEntities[job.id] {
                guard let current = try? decode(ProcessingJob.self, existing.payload),
                      let stateGuard = guards[job.id], current.state == stateGuard.expectedState,
                      current.attempt == stateGuard.expectedAttempt, job.attempt >= current.attempt else { throw AppError(code: .revisionConflict) }
                if current.state == .succeeded || current.state == .failed || current.state == .cancelled {
                    if job.attempt == current.attempt && job.state != current.state { throw AppError(code: .revisionConflict) }
                    if job.attempt > current.attempt && (job.attempt != current.attempt + 1 || job.state != .queued) { throw AppError(code: .revisionConflict) }
                }
                guard current.assetID == job.assetID, current.batchID == job.batchID else { throw AppError(code: .revisionConflict) }
            } else if guards[job.id] != nil { throw AppError(code: .revisionConflict) }
        }
        let batchEntities = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<StoredBatchEntity>()).compactMap { entity in
            guard let id = UUID(uuidString: entity.idString) else { return nil }
            return (id, entity)
        })
        for batch in transaction.batches {
            if let existing = batchEntities[batch.id], let current = try? decode(ImportBatch.self, existing.payload), current.cancelledAt != nil && batch.cancelledAt == nil { throw AppError(code: .revisionConflict) }
        }
        let encodedRecords = try mergedWrites.map { try encode($0.0) }
        for (index, item) in mergedWrites.enumerated() {
            let value = item.0; let payload = encodedRecords[index]
            if let entity = item.1 { Self.update(entity: entity, record: value, payload: payload, deleted: false) }
            else {
                let entity = StoredRecordEntity(idString: value.id.uuidString, payload: payload, isDeleted: false,
                    recordRevision: value.recordRevision, contentRevision: value.contentRevision, createdAt: value.createdAt,
                    updatedAt: value.updatedAt, searchText: Self.searchText(value), subjectID: value.classification.subjectID,
                    primaryNodeID: value.classification.primaryNodeID)
                context.insert(entity); entities[value.id] = entity
            }
        }
        let tombstoneValues = Dictionary(uniqueKeysWithValues: transaction.tombstones.map { ($0.recordID, $0) })
        for id in transaction.deleteRecordIDs {
            if let entity = entities[id] { entity.isDeleted = true; if let tombstone = tombstoneValues[id] { context.insert(StoredTombstoneEntity(idString: id.uuidString, payload: try encode(tombstone))) } }
        }
        for id in transaction.restoreRecordIDs {
            if let entity = entities[id] { entity.isDeleted = false }
            if let tombstone = try context.fetch(FetchDescriptor<StoredTombstoneEntity>()).first(where: { $0.idString == id.uuidString }) { context.delete(tombstone) }
        }
        for job in transaction.jobs {
            let data = try encode(job)
            if let entity = jobEntities[job.id] { entity.payload = data; entity.stateRaw = job.state.rawValue; entity.attempt = job.attempt; entity.updatedAt = job.updatedAt }
            else { context.insert(StoredJobEntity(idString: job.id.uuidString, payload: data, stateRaw: job.state.rawValue, attempt: job.attempt, updatedAt: job.updatedAt)) }
        }
        for batch in transaction.batches {
            let data = try encode(batch)
            if let entity = batchEntities[batch.id] { entity.payload = data; entity.updatedAt = batch.updatedAt }
            else { context.insert(StoredBatchEntity(idString: batch.id.uuidString, payload: data, updatedAt: batch.updatedAt)) }
        }
        if let undo = transaction.regionUndoState { context.insert(StoredRegionUndoEntity(idString: undo.token.id.uuidString, payload: try encode(undo))) }
        let commit = RepositoryCommit(transactionID: transaction.id, records: records)
        context.insert(StoredTransactionEntity(idString: transaction.id.uuidString, payload: try encode(commit)))
        return commit
    }

    private func fetchRecord(id: UUID, includeDeleted: Bool) throws -> MistakeRecord? {
        guard let entity = try findRecordEntity(id), includeDeleted || !entity.isDeleted else { return nil }
        return try decodeRecord(entity.payload)
    }
    private func findRecordEntity(_ id: UUID) throws -> StoredRecordEntity? { try context.fetch(FetchDescriptor<StoredRecordEntity>()).first { $0.idString == id.uuidString } }
    private func findJobEntity(_ id: UUID) throws -> StoredJobEntity? { try context.fetch(FetchDescriptor<StoredJobEntity>()).first { $0.idString == id.uuidString } }
    private func findBatchEntity(_ id: UUID) throws -> StoredBatchEntity? { try context.fetch(FetchDescriptor<StoredBatchEntity>()).first { $0.idString == id.uuidString } }
    private func findDeletion(_ id: UUID) throws -> StoredDeletionEntity? { try context.fetch(FetchDescriptor<StoredDeletionEntity>()).first { $0.idString == id.uuidString } }
    private func findTaxonomyEntity() throws -> StoredTaxonomyEntity? { try context.fetch(FetchDescriptor<StoredTaxonomyEntity>()).first }
    private func currentTaxonomy() throws -> TaxonomySnapshot {
        guard let entity = try findTaxonomyEntity() else { return TaxonomySnapshot(version: "0", nodes: []) }
        return try decode(TaxonomySnapshot.self, entity.payload)
    }
    private func saveContext() throws { do { try context.save() } catch { context.rollback(); throw AppError(code: .internalFailure, isRetryable: true) } }
    private func encode<T: Encodable>(_ value: T) throws -> Data { try ContractJSON.encoder().encode(value) }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T { try ContractJSON.decoder().decode(type, from: data) }
    private func decodeRecord(_ data: Data) throws -> MistakeRecord { try decode(MistakeRecord.self, data) }

    private static func searchText(_ record: MistakeRecord) -> String {
        ([record.stem.displayText, record.studentWork.displayText, record.referenceAnswer?.displayText ?? "", record.notes, record.tags.joined(separator: " "), record.classification.primaryNodeID ?? "", record.classification.suggestedTags.joined(separator: " ")]).joined(separator: " ")
    }
    private static func update(entity: StoredRecordEntity, record: MistakeRecord, payload: Data, deleted: Bool) {
        entity.payload = payload; entity.isDeleted = deleted; entity.recordRevision = record.recordRevision; entity.contentRevision = record.contentRevision; entity.createdAt = record.createdAt; entity.updatedAt = record.updatedAt; entity.searchText = searchText(record); entity.subjectID = record.classification.subjectID; entity.primaryNodeID = record.classification.primaryNodeID
    }
    private static func withRevisions(_ record: MistakeRecord, recordRevision: Int, updatedAt: Date) -> MistakeRecord {
        MistakeRecord(id: record.id, schemaVersion: record.schemaVersion, recordRevision: recordRevision, contentRevision: record.contentRevision, createdAt: record.createdAt, updatedAt: updatedAt, sourceRegions: record.sourceRegions, ocrLines: record.ocrLines, stem: record.stem, studentWork: record.studentWork, referenceAnswer: record.referenceAnswer, referenceAnswerSource: record.referenceAnswerSource, analysisResult: record.analysisResult, classification: record.classification, notes: record.notes, tags: record.tags, reviewState: record.reviewState, reviewRequired: record.reviewRequired, reviewReasons: record.reviewReasons, processingStatus: record.processingStatus)
    }
    private static func withClassification(_ record: MistakeRecord, classification: ClassificationResult, advanceRevision: Bool = true) -> MistakeRecord {
        MistakeRecord(id: record.id, schemaVersion: record.schemaVersion, recordRevision: record.recordRevision + (advanceRevision ? 1 : 0), contentRevision: record.contentRevision, createdAt: record.createdAt, updatedAt: Date(), sourceRegions: record.sourceRegions, ocrLines: record.ocrLines, stem: record.stem, studentWork: record.studentWork, referenceAnswer: record.referenceAnswer, referenceAnswerSource: record.referenceAnswerSource, analysisResult: record.analysisResult, classification: classification, notes: record.notes, tags: record.tags, reviewState: record.reviewState, reviewRequired: advanceRevision || record.reviewRequired, reviewReasons: advanceRevision ? Array(Set(record.reviewReasons + [.unclassified])) : record.reviewReasons, processingStatus: record.processingStatus)
    }
    private static func replaceNode(_ id: String, in snapshot: TaxonomySnapshot, transform: (TaxonomyNode) -> TaxonomyNode) -> TaxonomySnapshot {
        TaxonomySnapshot(version: snapshot.version, nodes: snapshot.nodes.map { $0.id == id ? transform($0) : $0 })
    }
    private static func nextVersion(_ version: String) -> String { "\(version)-next" }
    private static func validateTaxonomy(_ snapshot: TaxonomySnapshot) throws {
        guard !snapshot.version.isEmpty else { throw AppError(code: .invalidTaxonomy) }
        let ids = Set(snapshot.nodes.map(\.id)); guard ids.count == snapshot.nodes.count else { throw AppError(code: .invalidTaxonomy) }
        let byID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        for node in snapshot.nodes {
            guard !node.name.isEmpty, node.version >= 1, let root = byID[node.subjectID], root.parentID == nil, root.id == root.subjectID else { throw AppError(code: .invalidTaxonomy) }
            var visited: Set<String> = [node.id]; var parent = node.parentID
            while let parentID = parent { guard let parentNode = byID[parentID], parentNode.subjectID == node.subjectID, visited.insert(parentID).inserted else { throw AppError(code: .invalidTaxonomy) }; parent = parentNode.parentID }
        }
    }
    private static func descendantIDs(nodeID: String, taxonomy: TaxonomySnapshot) -> [String] {
        var result = [nodeID]; var changed = true
        while changed {
            changed = false
            for node in taxonomy.nodes {
                if let parentID = node.parentID, result.contains(parentID), !result.contains(node.id) {
                    result.append(node.id); changed = true
                }
            }
        }
        return result
    }
    private static func fingerprint(_ query: RecordQuery) throws -> String { String(data: try ContractJSON.encoder().encode(query), encoding: .utf8) ?? "" }
    private static func encodeCursor(offset: Int, fingerprint: String) -> String { Data("\(offset)|\(fingerprint)".utf8).base64EncodedString() }
    private static func decodeCursor(_ cursor: String?, fingerprint: String) throws -> Int {
        guard let cursor else { return 0 }
        guard let data = Data(base64Encoded: cursor), let value = String(data: data, encoding: .utf8), let split = value.firstIndex(of: "|"), let offset = Int(value[..<split]), String(value[value.index(after: split)...]) == fingerprint, offset >= 0 else { throw AppError(code: .unsupportedInput) }
        return offset
    }
}
