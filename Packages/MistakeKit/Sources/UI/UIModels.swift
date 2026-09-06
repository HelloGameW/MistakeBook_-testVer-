#if os(iOS)
import Combine
import Foundation
import SwiftUI
import UIKit
import Contracts

@MainActor
final class MistakeListViewModel: ObservableObject {
    @Published var records: [MistakeRecord] = []
    @Published var taxonomySnapshot = TaxonomySnapshot(version: "", nodes: [])
    @Published var searchText = ""
    @Published var subjectID: String?
    @Published var taxonomyNodeID: String?
    @Published var reviewRequiredOnly = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?
    @Published var undoDeletionToken: DeletionToken?
    @Published var selectionMode = false
    @Published var selectedIDs: Set<UUID> = []

    private let service: any AppService
    private var loadTask: Task<Void, Never>?

    init(service: any AppService) {
        self.service = service
        refresh()
    }

    deinit {
        loadTask?.cancel()
    }

    func refresh() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let query = RecordQuery(text: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                                subjectID: subjectID,
                                taxonomyNodeID: taxonomyNodeID,
                                includeDescendants: true,
                                reviewStates: [],
                                reviewRequiredOnly: reviewRequiredOnly,
                                includeDeleted: false,
                                sort: .updatedNewest)
        loadTask = Task { [weak self, service = self.service] in
            do {
                async let page = service.list(query: query, page: PageRequest(cursor: nil, limit: 200))
                async let taxonomy = service.taxonomy()
                let (loadedPage, loadedTaxonomy) = try await (page, taxonomy)
                guard !Task.isCancelled, let self else { return }
                self.records = loadedPage.records
                self.taxonomySnapshot = loadedTaxonomy
                self.selectedIDs = self.selectedIDs.intersection(Set(loadedPage.records.map(\.id)))
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func toggleSelection(for recordID: UUID) {
        if selectedIDs.contains(recordID) {
            selectedIDs.remove(recordID)
        } else {
            selectedIDs.insert(recordID)
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
        selectionMode = false
    }

    func archive(_ record: MistakeRecord) {
        Task { [weak self, service = self.service] in
            do {
                _ = try await service.setArchived(id: record.id, archived: true,
                                                   expectedRecordRevision: record.recordRevision)
                guard let self else { return }
                self.records.removeAll { $0.id == record.id }
                self.selectedIDs.remove(record.id)
                self.actionMessage = "已归档，可在“归档”中恢复。"
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func delete(_ record: MistakeRecord) {
        Task { [weak self, service = self.service] in
            do {
                let token = try await service.delete(ids: [record.id], expectedVersions: [RecordVersion(
                    recordID: record.id, recordRevision: record.recordRevision, contentRevision: record.contentRevision)])
                guard let self else { return }
                self.records.removeAll { $0.id == record.id }
                self.selectedIDs.remove(record.id)
                self.undoDeletionToken = token
                self.actionMessage = "已删除。可在本提示消失前撤销。"
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func undoDelete() {
        guard let token = undoDeletionToken else { return }
        Task { [weak self, service = self.service] in
            do {
                _ = try await service.restore(token: token)
                guard let self else { return }
                self.undoDeletionToken = nil
                self.actionMessage = "已恢复删除的题目。"
                self.refresh()
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func taxonomyName(for nodeID: String?) -> String? {
        guard let nodeID else { return nil }
        return taxonomySnapshot.nodes.first(where: { $0.id == nodeID })?.name
    }
}

@MainActor
final class ArchivedRecordListViewModel: ObservableObject {
    @Published var records: [MistakeRecord] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?

    private let service: any AppService
    private var loadTask: Task<Void, Never>?

    init(service: any AppService) {
        self.service = service
        refresh()
    }

    deinit {
        loadTask?.cancel()
    }

    func refresh() {
        loadTask?.cancel()
        isLoading = true
        let queryText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        loadTask = Task { [weak self, service = self.service] in
            do {
                let query = RecordQuery(text: queryText, subjectID: nil, taxonomyNodeID: nil,
                                        includeDescendants: true, reviewStates: [], reviewRequiredOnly: false,
                                        includeDeleted: false, sort: .updatedNewest, includeArchived: true)
                let page = try await service.list(query: query, page: PageRequest(cursor: nil, limit: 200))
                guard !Task.isCancelled, let self else { return }
                self.records = page.records.filter { $0.isArchived }
                self.errorMessage = nil
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
                self.isLoading = false
            }
        }
    }

    func unarchive(_ record: MistakeRecord) {
        Task { [weak self, service = self.service] in
            do {
                _ = try await service.setArchived(id: record.id, archived: false,
                                                   expectedRecordRevision: record.recordRevision)
                guard let self else { return }
                self.records.removeAll { $0.id == record.id }
                self.actionMessage = "已移回错题列表。"
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func delete(_ record: MistakeRecord) {
        Task { [weak self, service = self.service] in
            do {
                _ = try await service.delete(ids: [record.id], expectedVersions: [RecordVersion(
                    recordID: record.id, recordRevision: record.recordRevision, contentRevision: record.contentRevision)])
                guard let self else { return }
                self.records.removeAll { $0.id == record.id }
                self.actionMessage = "已删除。"
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }
}

@MainActor
final class ImportFlowViewModel: ObservableObject {
    @Published var batchID: UUID?
    @Published var batchEvent: BatchEvent?
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let service: any AppService
    private var observationTask: Task<Void, Never>?

    init(service: any AppService) {
        self.service = service
    }

    deinit {
        observationTask?.cancel()
    }

    func importPages(_ pages: [ImportedPage]) {
        guard !pages.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        successMessage = nil
        let options = ImportOptions(
            duplicatePolicy: .skipExisting,
            recognition: RecognitionOptions(languages: ["zh-Hans", "en-US"], quality: .accurate,
                                            usesLanguageCorrection: true, maxPixelDimension: 4096))
        Task { [weak self, service = self.service] in
            do {
                let newBatchID = try await service.importPages(pages: pages, options: options)
                guard let self, !Task.isCancelled else { return }
                self.batchID = newBatchID
                self.successMessage = "已加入整理队列，共 \(pages.count) 页。"
                self.observe(batchID: newBatchID)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isImporting = false
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func observe(batchID: UUID) {
        observationTask?.cancel()
        observationTask = Task { [weak self, service = self.service] in
            do {
                let stream = try await service.observeBatch(batchID: batchID)
                for await event in stream {
                    guard !Task.isCancelled, let self else { return }
                    self.batchEvent = event
                    self.isImporting = !event.isTerminal
                    if event.isTerminal { break }
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isImporting = false
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func cancel() {
        guard let batchID else { return }
        Task { [weak self, service = self.service] in
            do {
                try await service.cancel(target: .batch(batchID))
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func retry(jobID: UUID) {
        Task { [weak self, service = self.service] in
            do {
                try await service.retry(target: .job(jobID))
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }
}

@MainActor
final class RecordDetailViewModel: ObservableObject {
    @Published var record: MistakeRecord?
    @Published var image: UIImage?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var actionMessage: String?

    let recordID: UUID
    private let service: any AppService
    private var loadTask: Task<Void, Never>?

    init(service: any AppService, recordID: UUID) {
        self.service = service
        self.recordID = recordID
        reload()
    }

    deinit {
        loadTask?.cancel()
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task { [weak self, service = self.service, recordID] in
            do {
                let loaded = try await service.get(id: recordID)
                var loadedImage: UIImage?
                if let assetID = loaded.sourceRegions.first?.assetID {
                    let payload = try? await service.loadImage(assetID: assetID)
                    if let bytes = payload?.bytes { loadedImage = UIImage(data: bytes) }
                }
                guard !Task.isCancelled, let self else { return }
                self.record = loaded
                self.image = loadedImage
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func save(patch: RecordEditPatch) {
        Task { [weak self, service = self.service, recordID] in
            do {
                let updated = try await service.applyEdit(id: recordID, patch: patch)
                guard let self else { return }
                self.record = updated
                self.actionMessage = "已保存，内容版本已更新。"
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func decide(hypothesis: Hypothesis, decision: UserDecision) {
        guard let record else { return }
        let patch = RecordEditPatch(expectedRecordRevision: record.recordRevision,
                                    stem: .unchanged, studentWork: .unchanged,
                                    referenceAnswer: .unchanged, referenceAnswerSource: .unchanged,
                                    sourceRegions: .unchanged, notes: .unchanged, tags: .unchanged,
                                    hypothesisDecisions: [HypothesisDecision(hypothesisID: hypothesis.id,
                                                                             inputContentRevision: record.contentRevision,
                                                                             decision: decision)])
        save(patch: patch)
    }

    func analyze() {
        guard let record else { return }
        Task { [weak self, service = self.service, recordID] in
            do {
                let updated = try await service.analyze(id: recordID, expectedContentRevision: record.contentRevision)
                guard let self else { return }
                self.record = updated
                self.actionMessage = "已完成一次分析；请依据证据确认候选。"
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    func updateReviewState(_ state: ReviewState) {
        guard let record else { return }
        Task { [weak self, service = self.service, recordID] in
            do {
                let updated = try await service.updateReviewState(id: recordID, state: state,
                                                                  expectedRecordRevision: record.recordRevision)
                guard let self else { return }
                self.record = updated
            } catch {
                guard let self else { return }
                self.errorMessage = UIErrorMessage.from(error)
            }
        }
    }
}

enum UIErrorMessage {
    static func from(_ error: Error) -> String {
        if let appError = error as? AppError { return appError.displayMessage }
        if error is CancellationError { return AppError(code: .cancelled).displayMessage }
        return "操作未完成，请重试。"
    }
}

enum UIStrings {
    static func jobState(_ state: JobState) -> String {
        switch state {
        case .queued: "等待处理"
        case .running: "处理中"
        case .succeeded: "已完成"
        case .failed: "处理失败"
        case .cancelled: "已取消"
        }
    }

    static func stage(_ stage: JobStage) -> String {
        switch stage {
        case .preprocessing: "准备图片"
        case .recognizing: "识别文字"
        case .segmenting: "建议分题"
        case .analyzing: "分析候选"
        case .classifying: "建议归档"
        case .saving: "保存草稿"
        }
    }

    static func capabilityState(_ state: CapabilityState) -> String {
        switch state {
        case .available: "可用"
        case .partial: "部分可用"
        case .notReady: "未就绪"
        case .unavailable: "不可用"
        }
    }

    static func reviewState(_ state: ReviewState) -> String {
        switch state {
        case .new: "待复习"
        case .reviewing: "复习中"
        case .mastered: "已掌握"
        }
    }

    static func analysisStatus(_ status: AnalysisStatus) -> String {
        switch status {
        case .hypotheses: "有候选错因"
        case .insufficientEvidence: "证据不足"
        case .unavailable: "分析不可用"
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

struct NoticeBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .mbGlassSurface()
    }
}
#endif
