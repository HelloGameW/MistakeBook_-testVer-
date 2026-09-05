#if os(iOS)
import SwiftUI
import Contracts

@MainActor
struct ArchivedRecordListView: View {
    let service: any AppService
    let onSettings: () -> Void
    let onManageTaxonomy: () -> Void

    @StateObject private var model: ArchivedRecordListViewModel

    init(service: any AppService, onSettings: @escaping () -> Void, onManageTaxonomy: @escaping () -> Void) {
        self.service = service
        self.onSettings = onSettings
        self.onManageTaxonomy = onManageTaxonomy
        _model = StateObject(wrappedValue: ArchivedRecordListViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage)
                        .listRowSeparator(.hidden)
                }
                if let actionMessage = model.actionMessage {
                    NoticeBanner(message: actionMessage)
                        .listRowSeparator(.hidden)
                }
                if model.isLoading && model.records.isEmpty {
                    HStack {
                        ProgressView()
                        Text("正在载入归档题目…")
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                } else if model.records.isEmpty {
                    ContentUnavailableView {
                        Label("还没有归档题目", systemImage: "archivebox")
                    } description: {
                        Text("在错题列表中左滑题目即可归档；归档后仍可恢复。")
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(model.records, id: \.id) { record in
                        NavigationLink {
                            RecordDetailView(service: service, recordID: record.id)
                        } label: {
                            archivedRow(record)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { model.unarchive(record) } label: {
                                Label("移回错题", systemImage: "arrow.uturn.backward")
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
            .navigationTitle("归档")
            .searchable(text: $model.searchText, prompt: "搜索已归档题目")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("知识分类", action: onManageTaxonomy)
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .onAppear { model.refresh() }
            .refreshable { model.refresh() }
            .onChange(of: model.searchText) { _, _ in model.refresh() }
        }
    }

    private func archivedRow(_ record: MistakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.stem.displayText.isEmpty ? "未填写题干" : record.stem.displayText)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(record.classification.subjectID ?? "待分类")
                Text("已归档")
                if let value = record.mistakeValue, !record.isMistakeValueStale {
                    Text("重要度 \(Int((value.overallScore * 100).rounded()))")
                        .foregroundStyle(value.level == .high ? .red : (value.level == .medium ? .orange : .secondary))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.stem.displayText.isEmpty ? "未填写题干" : record.stem.displayText)
        .accessibilityHint("打开已归档错题详情")
    }
}

#endif
