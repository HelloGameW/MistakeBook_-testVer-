#if os(iOS)
import SwiftUI
import Contracts

@MainActor
struct MistakeListView: View {
    let service: any AppService
    let onImport: () -> Void
    let onSettings: () -> Void

    @StateObject private var model: MistakeListViewModel
    @State private var showingExport = false

    init(service: any AppService, onImport: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.service = service
        self.onImport = onImport
        self.onSettings = onSettings
        _model = StateObject(wrappedValue: MistakeListViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            listColumn
                .navigationDestination(for: UUID.self) { recordID in
                    RecordDetailView(service: service, recordID: recordID)
                }
        }
        .sheet(isPresented: $showingExport) {
            let selected = model.records.filter { model.selectedIDs.contains($0.id) }
            ExportSheet(service: service, records: selected.isEmpty ? model.records : selected) {
                model.clearSelection()
            }
        }
    }

    private var listColumn: some View {
        List {
            if let errorMessage = model.errorMessage {
                ErrorBanner(message: errorMessage)
                    .listRowSeparator(.hidden)
            }

            if let actionMessage = model.actionMessage {
                HStack {
                    NoticeBanner(message: actionMessage)
                    if model.undoDeletionToken != nil {
                        Button("撤销") { model.undoDelete() }
                            .buttonStyle(.bordered)
                    }
                }
                .listRowSeparator(.hidden)
            }

            if model.reviewRequiredOnly {
                NoticeBanner(message: "当前只显示需要确认的题目。")
                    .listRowSeparator(.hidden)
            }

            if model.isLoading && model.records.isEmpty {
                HStack {
                    ProgressView()
                    Text("正在载入错题…")
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            } else if model.records.isEmpty {
                ContentUnavailableView {
                    Label("还没有错题", systemImage: "book.closed")
                } description: {
                    Text("拍照、从相册或文件导入图片，也可以直接手动录入。")
                } actions: {
                    Button("＋录入") { onImport() }
                        .buttonStyle(.borderedProminent)
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.records, id: \.id) { record in
                    recordRow(record)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { model.archive(record) } label: {
                                Label("归档", systemImage: "archivebox")
                            }
                            .tint(.blue)
                            Button(role: .destructive) { model.delete(record) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("错题")
        .searchable(text: $model.searchText, prompt: "搜索题干、笔记或知识点")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.selectionMode.toggle()
                    if !model.selectionMode { model.selectedIDs.removeAll() }
                } label: {
                    Text(model.selectionMode ? "完成" : "选择")
                }
                .accessibilityLabel(model.selectionMode ? "完成选择" : "选择题目导出")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.selectionMode {
                    Button {
                        showingExport = true
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.selectedIDs.isEmpty)
                } else {
                    Button {
                        onImport()
                    } label: {
                        Label("录入", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    onSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
            ToolbarItem(placement: .bottomBar) {
                filterMenu
            }
        }
        .onChange(of: model.searchText) { _, _ in model.refresh() }
        .onChange(of: model.subjectID) { _, _ in model.refresh() }
        .onChange(of: model.taxonomyNodeID) { _, _ in model.refresh() }
        .onChange(of: model.reviewRequiredOnly) { _, _ in model.refresh() }
        .onAppear { model.refresh() }
        .refreshable { model.refresh() }
    }

    @ViewBuilder
    private func recordRow(_ record: MistakeRecord) -> some View {
        if model.selectionMode {
            Button { model.toggleSelection(for: record.id) } label: {
                recordRowContent(record)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: record.id) {
                recordRowContent(record)
            }
            .buttonStyle(.plain)
        }
    }

    private func recordRowContent(_ record: MistakeRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if model.selectionMode {
                Image(systemName: model.selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.selectedIDs.contains(record.id) ? Color.accentColor : .secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(record.stem.displayText.isEmpty ? "未填写题干" : record.stem.displayText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(record.classification.subjectID ?? "待分类")
                    if let name = model.taxonomyName(for: record.classification.primaryNodeID) {
                        Text(name)
                    }
                    Text(UIStrings.reviewState(record.reviewState))
                    if let value = record.mistakeValue, !record.isMistakeValueStale {
                        Text("重要度 \(Int((value.overallScore * 100).rounded()))")
                            .foregroundStyle(value.level == .high ? .red : (value.level == .medium ? .orange : .secondary))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if record.reviewRequired || record.isAnalysisStale || record.isMistakeValueStale {
                    HStack(spacing: 8) {
                        if record.reviewRequired { Label("待确认", systemImage: "questionmark.circle") }
                        if record.isAnalysisStale { Label("分析基于旧内容", systemImage: "clock.arrow.circlepath") }
                        if record.isMistakeValueStale { Label("重要度待更新", systemImage: "gauge.with.dots.needle.33percent") }
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            if !model.selectionMode {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.stem.displayText.isEmpty ? "未填写题干" : record.stem.displayText)
        .accessibilityHint(model.selectionMode ? "切换选择状态" : "打开错题详情")
    }

    private var filterMenu: some View {
        Menu {
            Button("全部学科") { model.subjectID = nil }
            ForEach(subjectNodes, id: \.id) { node in
                Button(node.name) { model.subjectID = node.id }
            }
            Divider()
            Button("全部知识点") { model.taxonomyNodeID = nil }
            ForEach(model.taxonomySnapshot.nodes.filter(\.isActive).sorted(by: { $0.name < $1.name }), id: \.id) { node in
                Button(node.name) { model.taxonomyNodeID = node.id }
            }
            Divider()
            Toggle("只看待确认", isOn: $model.reviewRequiredOnly)
        } label: {
            Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选：\(filterLabel)")
    }

    private var subjectNodes: [TaxonomyNode] {
        model.taxonomySnapshot.nodes.filter { $0.parentID == nil && $0.subjectID == $0.id && $0.isActive }
            .sorted { $0.name < $1.name }
    }

    private var filterLabel: String {
        if let subjectID = model.subjectID,
           let subject = model.taxonomySnapshot.nodes.first(where: { $0.id == subjectID }) {
            return subject.name
        }
        if let nodeID = model.taxonomyNodeID,
           let node = model.taxonomySnapshot.nodes.first(where: { $0.id == nodeID }) {
            return node.name
        }
        return model.reviewRequiredOnly ? "待确认" : "筛选"
    }
}

#endif
