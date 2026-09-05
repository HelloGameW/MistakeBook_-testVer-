#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Contracts

@MainActor
struct RecordDetailView: View {
    let service: any AppService
    let recordID: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: RecordDetailViewModel
    @State private var stemText = ""
    @State private var studentWorkText = ""
    @State private var referenceText = ""
    @State private var notesText = ""
    @State private var tagsText = ""
    @State private var showingReference = false
    @State private var showingRegionEditor = false
    @State private var editorSeed: Int?

    init(service: any AppService, recordID: UUID) {
        self.service = service
        self.recordID = recordID
        _model = StateObject(wrappedValue: RecordDetailViewModel(service: service, recordID: recordID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.isLoading && model.record == nil {
                    ProgressView("正在载入错题…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let record = model.record {
                    VStack(alignment: .leading, spacing: 20) {
                        if let errorMessage = model.errorMessage { ErrorBanner(message: errorMessage) }
                        if let actionMessage = model.actionMessage { NoticeBanner(message: actionMessage) }
                        sourceSection(record)
                        editorSection(record)
                        analysisSection(record)
                        MistakeValueSection(service: service, record: record) { updated in
                            model.record = updated
                            model.actionMessage = "重要度已保存，可在题目列表中直接查看。"
                        }
                        classificationSection(record)
                        reviewSection(record)
                    }
                    .padding()
                } else if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage)
                        .padding()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("错题详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") { model.reload() }
                        .accessibilityLabel("刷新错题详情")
                }
            }
            .onChange(of: model.record?.recordRevision) { _, _ in seedEditorIfNeeded() }
            .onAppear { seedEditorIfNeeded() }
            .sheet(isPresented: $showingRegionEditor) {
                if let record = model.record {
                    RegionAdjustmentSheet(service: service, record: record, image: model.image) { updated in
                        model.record = updated
                        model.actionMessage = "分题区域已保存，相关旧分析需重新确认。"
                    }
                }
            }
        }
    }

    private func seedEditorIfNeeded() {
        guard let record = model.record, editorSeed != record.recordRevision else { return }
        editorSeed = record.recordRevision
        stemText = record.stem.displayText
        studentWorkText = record.studentWork.displayText
        referenceText = record.referenceAnswer?.displayText ?? ""
        notesText = record.notes
        tagsText = record.tags.joined(separator: ", ")
        showingReference = record.referenceAnswer != nil
    }

    @ViewBuilder
    private func sourceSection(_ record: MistakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "原图与证据", systemImage: "photo")
            if let image = model.image {
                NormalizedImageCanvas(image: image, regions: record.sourceRegions)
                    .frame(minHeight: 230, maxHeight: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                    .accessibilityLabel("原题图片，显示 \(record.sourceRegions.count) 个证据区域")
            } else if record.sourceRegions.isEmpty {
                NoticeBanner(message: "这是一条无图片的手动录入。")
            } else {
                NoticeBanner(message: "原图暂时无法载入；题目文字仍可编辑。")
            }
            if !record.sourceRegions.isEmpty {
                HStack {
                    Text("已保存 \(record.sourceRegions.count) 个区域")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("调整分题区域") { showingRegionEditor = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func editorSection(_ record: MistakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "校对内容", systemImage: "pencil.line")
            editorField("题干", text: $stemText, minHeight: 100)
            editorField("学生作答或解题步骤", text: $studentWorkText, minHeight: 100)

            DisclosureGroup(isExpanded: $showingReference) {
                editorField("参考答案 / 教师批注", text: $referenceText, minHeight: 90)
            } label: {
                Label("参考答案入口", systemImage: "checkmark.seal")
            }

            TextField("笔记", text: $notesText, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            TextField("标签（用逗号分隔）", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            if record.ocrLines.contains(where: { ($0.confidence?.value ?? 1) < 0.65 }) {
                NoticeBanner(message: "部分识别内容置信度较低，请对照原图校正；复杂公式和手写可能需要保留图片证据。")
            }

            PrimaryActionButton(title: "保存校对", systemImage: "checkmark") {
                model.save(patch: makePatch(from: record))
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func editorField(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium))
            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func analysisSection(_ record: MistakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "可能错因", systemImage: "lightbulb")
                Spacer()
                Button("重新分析") { model.analyze() }
                    .buttonStyle(.bordered)
            }

            if record.isAnalysisStale {
                ErrorBanner(message: "当前错因基于旧内容，已排除在正式解析导出之外；请重新分析。")
            }

            if let analysis = record.analysisResult {
                Text(UIStrings.analysisStatus(analysis.status))
                    .font(.subheadline.weight(.medium))
                if analysis.status == .insufficientEvidence {
                    NoticeBanner(message: "证据不足时不会硬猜错因；请补充学生作答、参考答案或教师批注后再分析。")
                }
                ForEach(analysis.hypotheses, id: \.id) { hypothesis in
                    HypothesisCard(hypothesis: hypothesis,
                                  onDecision: { decision in model.decide(hypothesis: hypothesis, decision: decision) })
                }
                ForEach(analysis.limitations, id: \.self) { limitation in
                    Label(limitation, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                NoticeBanner(message: "尚未分析。可以先保存题目；没有足够证据时系统会保持“信息不足，暂无法判断”。")
            }
        }
    }

    private func classificationSection(_ record: MistakeRecord) -> some View {
        ClassificationSection(service: service, record: record) { updated in
            model.record = updated
            model.actionMessage = "归档选择已保存。"
        }
    }

    private func reviewSection(_ record: MistakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "复习状态", systemImage: "checklist")
            Picker("掌握状态", selection: Binding(get: { record.reviewState }, set: { model.updateReviewState($0) })) {
                ForEach(ReviewState.allCases, id: \.self) { state in
                    Text(UIStrings.reviewState(state)).tag(state)
                }
            }
            .pickerStyle(.segmented)
            if record.reviewRequired {
                NoticeBanner(message: "这道题仍需人工确认：\(record.reviewReasons.map(reasonLabel).joined(separator: "、"))")
            }
        }
    }

    private func makePatch(from record: MistakeRecord) -> RecordEditPatch {
        let stem: FieldChange<EditableText> = stemText == record.stem.displayText
            ? .unchanged
            : .set(EditableText(rawText: record.stem.rawText, correctedText: stemText, provenance: .user, isLocked: true))
        let studentWork: FieldChange<EditableText> = studentWorkText == record.studentWork.displayText
            ? .unchanged
            : .set(EditableText(rawText: record.studentWork.rawText, correctedText: studentWorkText, provenance: .user, isLocked: true))

        let oldReference = record.referenceAnswer?.displayText ?? ""
        let referenceAnswer: FieldChange<EditableText?>
        let referenceSource: FieldChange<ReferenceAnswerSource?>
        if !showingReference && record.referenceAnswer != nil {
            referenceAnswer = .set(nil)
            referenceSource = .set(nil)
        } else if showingReference && referenceText != oldReference {
            referenceAnswer = .set(EditableText(rawText: record.referenceAnswer?.rawText ?? "",
                                                correctedText: referenceText, provenance: .user, isLocked: true))
            referenceSource = .set(ReferenceAnswerSource(provenance: .user, label: "用户输入", regionIDs: []))
        } else {
            referenceAnswer = .unchanged
            referenceSource = .unchanged
        }

        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return RecordEditPatch(expectedRecordRevision: record.recordRevision,
                               stem: stem, studentWork: studentWork,
                               referenceAnswer: referenceAnswer, referenceAnswerSource: referenceSource,
                               sourceRegions: .unchanged, notes: notesText == record.notes ? .unchanged : .set(notesText),
                               tags: tags == record.tags ? .unchanged : .set(tags), hypothesisDecisions: [])
    }

    private func reasonLabel(_ reason: ReviewReason) -> String {
        switch reason {
        case .lowConfidence: "低置信识别"
        case .unknownRegion: "区域待确认"
        case .unclassified: "尚未归档"
        case .modelUnavailable: "增强模型不可用"
        case .ocrFailed: "识别失败"
        case .emptyText: "文字为空"
        case .staleAnalysis: "错因已过时"
        case .staleClassification: "归档建议已过时"
        }
    }
}

struct HypothesisCard: View {
    let hypothesis: Hypothesis
    let onDecision: (UserDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text(hypothesis.summary)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(hypothesis.userDecision == .pending ? "待确认" : (hypothesis.userDecision == .accepted ? "已接受" : "已拒绝"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(hypothesis.reason).font(.callout)
            Label("下一步：\(hypothesis.nextAction)", systemImage: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(hypothesis.evidence.enumerated()), id: \.offset) { _, evidence in
                VStack(alignment: .leading, spacing: 3) {
                    Label(evidence.evidenceSource == .reference ? "参考材料" : "学生材料", systemImage: "quote.bubble")
                        .font(.caption.weight(.medium))
                    if let quote = evidence.quote, !quote.isEmpty { Text("“\(quote)”").font(.caption) }
                    Text("区域证据：\(evidence.regionID.uuidString.prefix(8))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if hypothesis.userDecision == .pending {
                HStack {
                    Button("接受候选") { onDecision(.accepted) }
                    Button("拒绝") { onDecision(.rejected) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}


struct MistakeValueSection: View {
    let service: any AppService
    let record: MistakeRecord
    let onUpdated: (MistakeRecord) -> Void
    @State private var result: MistakeValueResult?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "错题价值", systemImage: "gauge.with.dots.needle.50percent")
                Spacer()
                Button(isLoading ? "量化中…" : "评估") { evaluate() }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
            if let result = result ?? record.mistakeValue, !record.isMistakeValueStale {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int((result.overallScore * 100).rounded()))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("/ 100 · \(levelTitle(result.level))")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: result.overallScore)
                valueRow("知识价值", result.dimensions.knowledgeValue)
                valueRow("典型性", result.dimensions.representativeness)
                valueRow("重复犯错风险", result.dimensions.recurrenceRisk)
                valueRow("推理训练价值", result.dimensions.reasoningValue)
                valueRow("考试复习相关性", result.dimensions.examValue)
                valueRow("复习优先级", result.dimensions.reviewPriority)
                Text(result.reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(record.isMistakeValueStale ? "题目内容已修改，原重要度已失效，请重新评估。" : "尚未评估重要度；评估后会保存到题目并显示在列表中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func valueRow(_ title: String, _ value: Double) -> some View {
        HStack { Text(title).font(.caption); Spacer(); Text("\(Int((value * 100).rounded()))").font(.caption.monospacedDigit()) }
    }
    private func levelTitle(_ level: MistakeValueLevel) -> String {
        switch level { case .low: "低"; case .medium: "中"; case .high: "高" }
    }
    private func evaluate() {
        isLoading = true
        Task {
            do {
                result = try await service.evaluateValue(id: record.id, expectedContentRevision: record.contentRevision)
                let refreshed = try await service.get(id: record.id)
                onUpdated(refreshed)
                errorMessage = nil
            } catch { errorMessage = UIErrorMessage.from(error) }
            isLoading = false
        }
    }
}

struct ClassificationSection: View {
    let service: any AppService
    let record: MistakeRecord
    let onUpdated: (MistakeRecord) -> Void

    @State private var taxonomy = TaxonomySnapshot(version: "", nodes: [])
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "归档", systemImage: "folder")
            if let subjectID = record.classification.subjectID {
                Text("学科：\(nodeName(subjectID) ?? subjectID)")
                    .font(.subheadline)
            }
            if let primaryID = record.classification.primaryNodeID {
                Text("当前路径：\(path(for: primaryID).joined(separator: " / "))")
                    .font(.subheadline)
            } else {
                Text("当前：待分类").font(.subheadline).foregroundStyle(.secondary)
            }
            Menu {
                Button("保留待分类") { select(nil) }
                ForEach(record.classification.candidates, id: \.nodeID) { candidate in
                    Button(nodeName(candidate.nodeID) ?? candidate.nodeID) { select(candidate.nodeID) }
                }
                Divider()
                ForEach(taxonomy.nodes.filter(\.isActive).sorted(by: { $0.name < $1.name }), id: \.id) { node in
                    Button(node.name) { select(node.id) }
                }
            } label: {
                Label("选择主分类", systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.bordered)

            if !record.classification.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("候选依据").font(.caption.weight(.medium))
                    ForEach(record.classification.candidates, id: \.nodeID) { candidate in
                        Text("• \(nodeName(candidate.nodeID) ?? candidate.nodeID)：\(candidate.basis)")
                            .font(.caption)
                    }
                }
            }
            if let errorMessage { ErrorBanner(message: errorMessage) }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .task {
            isLoading = true
            taxonomy = (try? await service.taxonomy()) ?? taxonomy
            isLoading = false
        }
        .overlay { if isLoading { ProgressView().controlSize(.small) } }
    }

    private func nodeName(_ id: String) -> String? {
        taxonomy.nodes.first(where: { $0.id == id })?.name
    }

    private func path(for id: String) -> [String] {
        var names: [String] = []
        var current = taxonomy.nodes.first(where: { $0.id == id })
        var seen = Set<String>()
        while let node = current, seen.insert(node.id).inserted {
            names.insert(node.name, at: 0)
            current = node.parentID.flatMap { parentID in taxonomy.nodes.first(where: { $0.id == parentID }) }
        }
        return names.isEmpty ? [id] : names
    }

    private func select(_ nodeID: String?) {
        Task {
            do {
                let updated = try await service.setClassification(
                    id: record.id,
                    selection: ClassificationSelection(primaryNodeID: nodeID, tags: record.tags,
                                                       expectedRecordRevision: record.recordRevision,
                                                       expectedTaxonomyVersion: taxonomy.version))
                onUpdated(updated)
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
        }
    }
}

struct NormalizedImageCanvas: View {
    let image: UIImage
    let regions: [SourceRegion]

    var body: some View {
        GeometryReader { proxy in
            let layout = ImageCanvasLayout(container: proxy.size, imageSize: image.size)
            ZStack {
                Color(uiColor: .systemBackground)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                    .position(x: layout.imageOrigin.x + layout.imageSize.width / 2,
                              y: layout.imageOrigin.y + layout.imageSize.height / 2)
                ForEach(regions, id: \.id) { region in
                    let rect = layout.rect(for: region.normalizedRect)
                    Rectangle()
                        .stroke(region.isUserConfirmed ? Color.green : Color.orange, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .clipped()
        }
    }
}

struct RegionAdjustmentSheet: View {
    let service: any AppService
    let record: MistakeRecord
    let image: UIImage?
    let onSaved: (MistakeRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var region: SourceRegion
    @State private var pendingRegions: [SourceRegion]
    @State private var lastUndoToken: RegionUndoToken?
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(service: any AppService, record: MistakeRecord, image: UIImage?, onSaved: @escaping (MistakeRecord) -> Void) {
        self.service = service
        self.record = record
        self.image = image
        self.onSaved = onSaved
        let initial = record.sourceRegions.first ?? SourceRegion(id: UUID(), assetID: UUID(), normalizedRect: .fullPage, purpose: .stem, isUserConfirmed: false)
        _region = State(initialValue: initial)
        _pendingRegions = State(initialValue: record.sourceRegions.isEmpty ? [initial] : record.sourceRegions)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let image {
                    NormalizedRegionEditor(image: image, region: $region)
                        .frame(minHeight: 300, maxHeight: 560)
                } else {
                    ContentUnavailableView("原图暂不可用", systemImage: "photo.badge.exclamationmark",
                                           description: Text("可以稍后重试载入原图。"))
                }
                Text("拖动绿色边框调整区域。坐标按被引用工作图保存；不会覆盖原图。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                HStack {
                    Button("拆分为两段") { splitRegion() }
                        .buttonStyle(.bordered)
                    Button("合并区域") { mergeRegions() }
                        .buttonStyle(.bordered)
                        .disabled(pendingRegions.count < 2)
                }
                if let lastUndoToken {
                    HStack {
                        Label("区域修改已保存", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("撤销") { undo(lastUndoToken) }
                        Button("完成") { dismiss() }
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                }
                if let errorMessage { ErrorBanner(message: errorMessage).padding(.horizontal) }
                Spacer()
            }
            .padding(.top)
            .navigationTitle("调整分题区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if lastUndoToken == nil {
                        Button(isSaving ? "保存中…" : "保存") { save() }
                            .disabled(isSaving)
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        pendingRegions[0] = SourceRegion(id: region.id, assetID: region.assetID,
                                         normalizedRect: region.normalizedRect, purpose: region.purpose,
                                         isUserConfirmed: true)
        let request = RegionEditRequest(
            jobIDs: [], replacedRecordIDs: [record.id],
            expectedVersions: [RecordVersion(recordID: record.id, recordRevision: record.recordRevision,
                                             contentRevision: record.contentRevision)],
            assignments: [RegionAssignment(recordID: record.id, regions: pendingRegions, order: 0)])
        Task {
            do {
                let result = try await service.confirmRegions(request: request)
                onSaved(result.records.first ?? record)
                lastUndoToken = result.undoToken
                isSaving = false
            } catch {
                errorMessage = UIErrorMessage.from(error)
                isSaving = false
            }
        }
    }

    private func splitRegion() {
        guard pendingRegions.count == 1 else { return }
        let source = region
        let halfWidth = source.normalizedRect.width / 2
        guard let left = try? NormalizedRect(x: source.normalizedRect.x, y: source.normalizedRect.y,
                                             width: halfWidth, height: source.normalizedRect.height),
              let right = try? NormalizedRect(x: source.normalizedRect.x + halfWidth, y: source.normalizedRect.y,
                                              width: halfWidth, height: source.normalizedRect.height) else { return }
        pendingRegions = [
            SourceRegion(id: source.id, assetID: source.assetID, normalizedRect: left, purpose: source.purpose, isUserConfirmed: false),
            SourceRegion(id: UUID(), assetID: source.assetID, normalizedRect: right, purpose: source.purpose, isUserConfirmed: false)
        ]
    }

    private func mergeRegions() {
        guard pendingRegions.count > 1 else { return }
        let rects = pendingRegions.map(\.normalizedRect)
        let minX = rects.map(\.x).min() ?? 0
        let minY = rects.map(\.y).min() ?? 0
        let maxX = rects.map { $0.x + $0.width }.max() ?? 1
        let maxY = rects.map { $0.y + $0.height }.max() ?? 1
        guard let merged = try? NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) else { return }
        let source = pendingRegions[0]
        region = SourceRegion(id: source.id, assetID: source.assetID, normalizedRect: merged,
                              purpose: source.purpose, isUserConfirmed: false)
        pendingRegions = [region]
    }

    private func undo(_ token: RegionUndoToken) {
        Task {
            do {
                let restored = try await service.undoRegionEdit(token: token)
                if let first = restored.first {
                    onSaved(first)
                    region = first.sourceRegions.first ?? region
                    pendingRegions = first.sourceRegions
                }
                lastUndoToken = nil
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
        }
    }
}

struct NormalizedRegionEditor: View {
    let image: UIImage
    @Binding var region: SourceRegion
    @State private var dragStart: NormalizedRect?

    var body: some View {
        GeometryReader { proxy in
            let layout = ImageCanvasLayout(container: proxy.size, imageSize: image.size)
            ZStack {
                Color(uiColor: .systemBackground)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                    .position(x: layout.imageOrigin.x + layout.imageSize.width / 2,
                              y: layout.imageOrigin.y + layout.imageSize.height / 2)
                let rect = layout.rect(for: region.normalizedRect)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle().inset(by: -20))
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = region.normalizedRect }
                        guard let start = dragStart else { return }
                        let dx = value.translation.width / max(layout.imageSize.width, 1)
                        let dy = value.translation.height / max(layout.imageSize.height, 1)
                        let nextX = min(max(start.x + dx, 0), 1 - start.width)
                        let nextY = min(max(start.y + dy, 0), 1 - start.height)
                        if let next = try? NormalizedRect(x: nextX, y: nextY, width: start.width, height: start.height) {
                            region = SourceRegion(id: region.id, assetID: region.assetID, normalizedRect: next,
                                                  purpose: region.purpose, isUserConfirmed: false)
                        }
                    }.onEnded { _ in dragStart = nil })
            }
            .clipped()
        }
    }
}

private struct ImageCanvasLayout {
    let imageOrigin: CGPoint
    let imageSize: CGSize

    init(container: CGSize, imageSize: CGSize) {
        let scale = min(container.width / max(imageSize.width, 1), container.height / max(imageSize.height, 1))
        self.imageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        self.imageOrigin = CGPoint(x: (container.width - self.imageSize.width) / 2,
                                   y: (container.height - self.imageSize.height) / 2)
    }

    func rect(for normalized: NormalizedRect) -> CGRect {
        CGRect(x: imageOrigin.x + normalized.x * imageSize.width,
               y: imageOrigin.y + normalized.y * imageSize.height,
               width: normalized.width * imageSize.width,
               height: normalized.height * imageSize.height)
    }
}
#endif
