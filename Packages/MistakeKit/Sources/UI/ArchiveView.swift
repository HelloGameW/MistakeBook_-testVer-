#if os(iOS)
import SwiftUI
import UIKit
import Contracts

@MainActor
struct ArchiveView: View {
    let service: any AppService
    @State private var taxonomy = TaxonomySnapshot(version: "", nodes: [])
    @State private var selectedNodeID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var showingCreate = false
    @State private var editedName = ""
    @State private var editedAliases = ""
    @State private var editorNodeVersion: Int?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNodeID) {
                if let errorMessage { ErrorBanner(message: errorMessage).listRowSeparator(.hidden) }
                if isLoading && taxonomy.nodes.isEmpty {
                    HStack { ProgressView(); Text("正在载入知识树…") }
                        .listRowSeparator(.hidden)
                } else if taxonomy.nodes.isEmpty {
                    ContentUnavailableView("知识树暂不可用", systemImage: "folder.badge.questionmark",
                                           description: Text("业务服务尚未提供可编辑的知识节点。"))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(rootNodes, id: \.id) { node in
                        TaxonomyTreeNodeView(node: node, nodes: taxonomy.nodes, selectedNodeID: $selectedNodeID)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("归档")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreate = true } label: {
                        Label("新建节点", systemImage: "folder.badge.plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("刷新") { loadTaxonomy() }
                }
            }
        } detail: {
            if let node = selectedNode {
                nodeEditor(node)
            } else {
                ContentUnavailableView("选择知识节点", systemImage: "folder",
                                       description: Text("浏览、修改或维护本地知识树。记录关联的是稳定节点 ID，改名不会丢失归档。"))
            }
        }
        .task { loadTaxonomy() }
        .sheet(isPresented: $showingCreate) {
            CreateTaxonomyNodeSheet(service: service, taxonomy: taxonomy) { updated in
                taxonomy = updated
                actionMessage = "已创建用户知识节点。"
            }
        }
    }

    private var rootNodes: [TaxonomyNode] {
        taxonomy.nodes.filter { $0.parentID == nil && $0.isActive }.sorted { $0.name < $1.name }
    }

    private var selectedNode: TaxonomyNode? {
        guard let selectedNodeID else { return nil }
        return taxonomy.nodes.first(where: { $0.id == selectedNodeID })
    }

    private func loadTaxonomy() {
        isLoading = true
        Task {
            do {
                taxonomy = try await service.taxonomy()
                errorMessage = nil
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
            isLoading = false
        }
    }

    private func nodeEditor(_ node: TaxonomyNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "知识节点", systemImage: "folder")
                if let actionMessage { NoticeBanner(message: actionMessage) }
                Text("稳定 ID：\(node.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                TextField("节点名称", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                TextField("别名（用逗号分隔）", text: $editedAliases)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text(node.origin == .seed ? "示例种子" : "用户节点")
                    Text(node.isActive ? "启用" : "停用")
                    Text("版本 \(node.version)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("保存节点修改") { update(node) }
                    .buttonStyle(.borderedProminent)
                Button("删除并移至父节点") { delete(node) }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                Text("删除操作由业务层检查记录引用、树环和版本冲突；失败时会在此处显示具体结果。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: selectedNodeID) { _, _ in seedEditor() }
        .onAppear { seedEditor() }
    }

    private func seedEditor() {
        guard let selectedNode else { return }
        guard editorNodeVersion != selectedNode.version || editedName.isEmpty else { return }
        editorNodeVersion = selectedNode.version
        editedName = selectedNode.name
        editedAliases = selectedNode.aliases.joined(separator: ", ")
    }

    private func update(_ node: TaxonomyNode) {
        let aliases = editedAliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let patch = TaxonomyNodePatch(expectedVersion: node.version, name: .set(editedName), parentID: .unchanged,
                                      aliases: .set(aliases), isActive: .unchanged)
        Task {
            do {
                taxonomy = try await service.updateTaxonomyNode(id: node.id, patch: patch)
                actionMessage = "节点已保存；记录仍关联原稳定 ID。"
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    private func delete(_ node: TaxonomyNode) {
        Task {
            do {
                taxonomy = try await service.deleteTaxonomyNode(request: TaxonomyDeleteRequest(
                    nodeID: node.id, expectedTaxonomyVersion: taxonomy.version, mode: .moveToParent))
                selectedNodeID = nil
                actionMessage = "节点已删除或按业务规则迁移。"
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
        }
    }
}

private struct TaxonomyTreeNodeView: View {
    let node: TaxonomyNode
    let nodes: [TaxonomyNode]
    @Binding var selectedNodeID: String?

    private var children: [TaxonomyNode] {
        nodes.filter { $0.parentID == node.id && $0.isActive }.sorted { $0.name < $1.name }
    }

    var body: some View {
        if children.isEmpty {
            Text(node.name)
                .tag(node.id)
                .contextMenu { Text(node.origin == .seed ? "示例节点" : "用户节点") }
        } else {
            DisclosureGroup {
                ForEach(children, id: \.id) { child in
                    TaxonomyTreeNodeView(node: child, nodes: nodes, selectedNodeID: $selectedNodeID)
                }
            } label: {
                Text(node.name).tag(node.id)
            }
        }
    }
}

struct CreateTaxonomyNodeSheet: View {
    let service: any AppService
    let taxonomy: TaxonomySnapshot
    let onCreated: (TaxonomySnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var aliases = ""
    @State private var parentID: String?
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("节点") {
                    TextField("名称", text: $name)
                    TextField("别名（可选）", text: $aliases)
                    Picker("父节点", selection: $parentID) {
                        Text("无（新学科根节点）").tag(String?.none)
                        ForEach(taxonomy.nodes.filter(\.isActive).sorted(by: { $0.name < $1.name }), id: \.id) { node in
                            Text(node.name).tag(Optional(node.id))
                        }
                    }
                    if parentID == nil {
                        Text("自定义根节点会使用自己的稳定 ID 作为学科 ID。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { ErrorBanner(message: errorMessage) }
                Button(isSaving ? "保存中…" : "创建节点") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
            .navigationTitle("新建知识节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func create() {
        isSaving = true
        let id = "user/\(UUID().uuidString.lowercased())"
        let parent = parentID.flatMap { selectedParentID in
            taxonomy.nodes.first(where: { $0.id == selectedParentID })
        }
        let actualSubjectID = parent?.subjectID ?? id
        let node = TaxonomyNode(id: id, parentID: parentID, name: name,
                                subjectID: actualSubjectID, aliases: aliases.split(separator: ",").map(String.init),
                                origin: .user, isActive: true, version: 1, userModifiedFields: ["name", "parentID", "aliases"])
        Task {
            do {
                let updated = try await service.createTaxonomyNode(node: node, expectedTaxonomyVersion: taxonomy.version)
                onCreated(updated)
                dismiss()
            } catch {
                errorMessage = UIErrorMessage.from(error)
                isSaving = false
            }
        }
    }
}
#endif
