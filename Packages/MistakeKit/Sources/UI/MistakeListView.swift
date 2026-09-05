#if os(iOS)
import SwiftUI
import Contracts

@MainActor
struct MistakeListView: View {
    let service: any AppService
    @Binding var selectedRecordID: UUID?
    let onImport: () -> Void

    @StateObject private var model: MistakeListViewModel
    @State private var showingExport = false

    init(service: any AppService, selectedRecordID: Binding<UUID?>, onImport: @escaping () -> Void) {
        self.service = service
        self._selectedRecordID = selectedRecordID
        self.onImport = onImport
        _model = StateObject(wrappedValue: MistakeListViewModel(service: service))
    }

    var body: some View {
        NavigationSplitView {
            listColumn
        } detail: {
            if let selectedRecordID {
                RecordDetailView(service: service, recordID: selectedRecordID)
            } else {
                ContentUnavailableView("选择一道错题", systemImage: "doc.text.magnifyingglass",
                                       description: Text("从列表选择题目，查看原图、识别文本、错因证据和归档。"))
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
                ForEach(model.records) { record in
                    recordRow(record)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("错题")
        .searchable(text: $model.searchText, prompt: "搜索题干、笔记或归档")
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
            }
            ToolbarItem(placement: .bottomBar) {
                filterMenu
            }
        }
        .onChange(of: model.searchText) { _, _ in model.refresh() }
        .onChange(of: model.subjectID) { _, _ in model.refresh() }
        .onChange(of: model.taxonomyNodeID) { _, _ in model.refresh() }
        .onChange(of: model.reviewRequiredOnly) { _, _ in model.refresh() }
        .refreshable { model.refresh() }
    }

    @ViewBuilder
    private func recordRow(_ record: MistakeRecord) -> some View {
        Button {
            if model.selectionMode {
                model.toggleSelection(for: record.id)
            } else {
                selectedRecordID = record.id
            }
        } label: {
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
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if record.reviewRequired || record.isAnalysisStale {
                        HStack(spacing: 8) {
                            if record.reviewRequired {
                                Label("待确认", systemImage: "questionmark.circle")
                            }
                            if record.isAnalysisStale {
                                Label("分析基于旧内容", systemImage: "clock.arrow.circlepath")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Image(systemName: model.selectionMode ? "" : "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

private extension MistakeRecord: Identifiable {}
#endif
