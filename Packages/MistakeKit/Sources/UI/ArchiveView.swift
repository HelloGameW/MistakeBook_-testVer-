#if os(iOS)
import SwiftUI
import UIKit
import Contracts

/// 年级视图的共享约定（seed.json 中 `grade:` 前缀别名的解析与展示）。
enum ArchiveGradeMeta {
    static let prefix = "grade:"
    static let semesterKeys = ["g1s1", "g1s2", "g2s1", "g2s2"]
    static let semesterTitles = ["g1s1": "高一 · 上学期", "g1s2": "高一 · 下学期",
                                 "g2s1": "高二 · 上学期", "g2s2": "高二 · 下学期"]
    static let semesterChips = ["g1s1": "高一上", "g1s2": "高一下", "g2s1": "高二上", "g2s2": "高二下"]
    /// 固定科目展示顺序（年级视图），未列出的学科根按名称排在末尾。
    static let curriculumOrder = ["chinese", "math", "english", "physics", "chemistry",
                                  "biology", "history", "geography", "civics"]
    static let knownAliases: Set<String> = ["grade:g1", "grade:g2", "grade:g3",
                                            "grade:g1s1", "grade:g1s2",
                                            "grade:g2s1", "grade:g2s2",
                                            "grade:g3s1", "grade:g3s2"]

    /// 解析节点别名的年级键（`grade:` 前缀之后的部分）。
    static func gradeKeys(of node: TaxonomyNode) -> Set<String> {
        Set(node.aliases.compactMap { alias in
            guard alias.hasPrefix(prefix) else { return nil }
            return String(alias.dropFirst(prefix.count))
        })
    }

    /// 年级标签展开为可编辑的学期集合（全年标签展开到两个学期）。
    static func editableSemesters(of node: TaxonomyNode) -> Set<String> {
        var result: Set<String> = []
        for key in gradeKeys(of: node) {
            switch key {
            case "g1s1", "g1s2", "g2s1", "g2s2": result.insert(key)
            case "g1": result.formUnion(["g1s1", "g1s2"])
            case "g2": result.formUnion(["g2s1", "g2s2"])
            default: break
            }
        }
        return result
    }

    /// 由学期选择生成 `grade:` 元数据；同年级两学期都勾选时收敛为全年标签。
    /// 未识别的年级标签（如手工添加的 grade:g3）原样保留。
    static func metaAliases(for selection: Set<String>, preserving original: [String]) -> [String] {
        var metas: [String] = []
        for year in ["1", "2"] {
            let first = selection.contains("g\(year)s1")
            let second = selection.contains("g\(year)s2")
            if first && second {
                metas.append("grade:g\(year)")
            } else {
                if first { metas.append("grade:g\(year)s1") }
                if second { metas.append("grade:g\(year)s2") }
            }
        }
        let extras = original.filter { $0.hasPrefix(prefix) && !knownAliases.contains($0) }
        return metas + extras
    }

    static func nonMetaAliases(of node: TaxonomyNode) -> [String] {
        node.aliases.filter { !$0.hasPrefix(prefix) }
    }
}

@MainActor
struct ArchiveView: View {
    let service: any AppService
    @State private var taxonomy = TaxonomySnapshot(version: "", nodes: [])
    @State private var mode: ArchiveMode = .module
    @State private var selectedNodeID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var showingCreate = false
    @State private var editedName = ""
    @State private var editedAliases = ""
    @State private var gradeSelection: Set<String> = []
    @State private var editorNodeVersion: Int?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNodeID) {
                if let errorMessage { ErrorBanner(message: errorMessage).listRowSeparator(.hidden) }
                Picker("浏览模式", selection: $mode) {
                    ForEach(ArchiveMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                if isLoading && taxonomy.nodes.isEmpty {
                    HStack { ProgressView(); Text("正在载入知识树…") }
                        .listRowSeparator(.hidden)
                } else if taxonomy.nodes.isEmpty {
                    ContentUnavailableView("知识树暂不可用", systemImage: "folder.badge.questionmark",
                                           description: Text("业务服务尚未提供可编辑的知识节点。"))
                        .listRowSeparator(.hidden)
                } else if mode == .module {
                    ForEach(rootNodes, id: \.id) { node in
                        TaxonomyTreeNodeView(node: node, nodes: taxonomy.nodes, selectedNodeID: $selectedNodeID)
                    }
                } else {
                    ForEach(semesterGroups, id: \.key) { group in
                        Section(group.title) {
                            ForEach(group.subjects) { subjectGroup in
                                GradeSubjectTreeView(subjectGroup: subjectGroup)
                            }
                        }
                    }
                    Section {
                        ForEach(reviewGroups) { subjectGroup in
                            GradeSubjectTreeView(subjectGroup: subjectGroup)
                        }
                    } header: {
                        Text("高三 · 总复习")
                    } footer: {
                        Text("总复习按知识板块推进，覆盖全部考点，无需逐条标注年级。")
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
                                       description: Text("可在「知识板块」或「年级知识」模式下浏览；记录关联的是稳定节点 ID，改名不会丢失归档。"))
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
                GradeTagEditor(selection: $gradeSelection)
                HStack {
                    Text(node.origin == .seed ? "种子节点" : "用户节点")
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
        guard editorNodeVersion != selectedNode.version || editedAliases.isEmpty else { return }
        editorNodeVersion = selectedNode.version
        editedName = selectedNode.name
        editedAliases = ArchiveGradeMeta.nonMetaAliases(of: selectedNode).joined(separator: ", ")
        gradeSelection = ArchiveGradeMeta.editableSemesters(of: selectedNode)
    }

    private func update(_ node: TaxonomyNode) {
        let aliases = editedAliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fullAliases = aliases + ArchiveGradeMeta.metaAliases(for: gradeSelection, preserving: node.aliases)
        let patch = TaxonomyNodePatch(expectedVersion: node.version, name: .set(editedName), parentID: .unchanged,
                                      aliases: .set(fullAliases), isActive: .unchanged)
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

// MARK: - 年级视图投影

private extension ArchiveView {
    /// 年级视图（高一～高二）：按学期分组，从考点节点的 `grade:` 元数据派生。
    var semesterGroups: [GradeSemesterGroup] {
        ArchiveGradeMeta.semesterKeys.map { key in
            GradeSemesterGroup(key: key, title: ArchiveGradeMeta.semesterTitles[key] ?? key,
                               subjects: subjectGroups(for: key))
        }.filter { !$0.subjects.isEmpty }
    }

    /// 高三组：总复习投影，按学科罗列全部板块，不依赖年级标注。
    var reviewGroups: [GradeSubjectGroup] {
        let active = taxonomy.nodes.filter(\.isActive)
        let childIDs = Set(active.compactMap(\.parentID))
        return orderedSubjectRoots.compactMap { root in
            var blocks: [GradeBlock] = []
            var looseLeaves: [TaxonomyNode] = []
            for child in active.filter({ $0.parentID == root.id }).sorted(by: { $0.name < $1.name }) {
                if childIDs.contains(child.id) {
                    let leaves = active.filter { $0.parentID == child.id }.sorted { $0.name < $1.name }
                    blocks.append(GradeBlock(header: child, leaves: leaves))
                } else {
                    looseLeaves.append(child)
                }
            }
            if !looseLeaves.isEmpty {
                blocks.append(GradeBlock(header: nil, leaves: looseLeaves))
            }
            guard !blocks.isEmpty else { return nil }
            return GradeSubjectGroup(subject: root, blocks: blocks)
        }
    }

    var orderedSubjectRoots: [TaxonomyNode] {
        let roots = taxonomy.nodes.filter { $0.parentID == nil && $0.isActive }
        let known = ArchiveGradeMeta.curriculumOrder.compactMap { id in roots.first(where: { $0.id == id }) }
        let extra = roots.filter { !ArchiveGradeMeta.curriculumOrder.contains($0.id) }.sorted { $0.name < $1.name }
        return known + extra
    }

    /// 某学期下有考点的学科分组：学科 → 板块 → 考点；直接挂在学科根下的考点单独成组。
    func subjectGroups(for semester: String) -> [GradeSubjectGroup] {
        let active = taxonomy.nodes.filter(\.isActive)
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let childIDs = Set(active.compactMap(\.parentID))
        return orderedSubjectRoots.compactMap { root in
            let tagged = active.filter { node in
                node.subjectID == root.id
                    && !childIDs.contains(node.id)
                    && ArchiveGradeMeta.gradeKeys(of: node).contains(semester)
            }
            guard !tagged.isEmpty else { return nil }
            var grouped: [String: [TaxonomyNode]] = [:]
            for leaf in tagged { grouped[leaf.parentID ?? root.id, default: []].append(leaf) }
            var blocks: [GradeBlock] = []
            for (parentID, leaves) in grouped {
                if parentID == root.id {
                    blocks.append(GradeBlock(header: nil, leaves: leaves.sorted { $0.name < $1.name }))
                } else if let header = byID[parentID] {
                    blocks.append(GradeBlock(header: header, leaves: leaves.sorted { $0.name < $1.name }))
                }
            }
            blocks.sort { ($0.header?.name ?? "") < ($1.header?.name ?? "") }
            return GradeSubjectGroup(subject: root, blocks: blocks)
        }
    }
}

private enum ArchiveMode: String, CaseIterable, Identifiable {
    case module
    case grade

    var id: String { rawValue }
    var title: String { self == .module ? "知识板块" : "年级知识" }
}

private struct GradeSemesterGroup {
    let key: String
    let title: String
    let subjects: [GradeSubjectGroup]
}

private struct GradeSubjectGroup: Identifiable {
    let subject: TaxonomyNode
    let blocks: [GradeBlock]

    var id: String { subject.id }
}

/// header 为 nil 时 leaves 直接展示在学科名下（考点挂在学科根上的情形）。
private struct GradeBlock: Identifiable {
    let header: TaxonomyNode?
    let leaves: [TaxonomyNode]

    var id: String { header?.id ?? leaves.map(\.id).joined(separator: "+") }
}

private struct GradeSubjectTreeView: View {
    let subjectGroup: GradeSubjectGroup

    var body: some View {
        DisclosureGroup {
            ForEach(subjectGroup.blocks) { block in
                if let header = block.header {
                    DisclosureGroup {
                        ForEach(block.leaves, id: \.id) { leaf in
                            Text(leaf.name).tag(leaf.id)
                        }
                    } label: {
                        Text(header.name).tag(header.id)
                    }
                } else {
                    ForEach(block.leaves, id: \.id) { leaf in
                        Text(leaf.name).tag(leaf.id)
                    }
                }
            }
        } label: {
            Label(subjectGroup.subject.name, systemImage: "book.closed")
                .tag(subjectGroup.subject.id)
        }
    }
}

private struct GradeTagEditor: View {
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("学年归属（年级视图）")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack(spacing: 8) {
                ForEach(ArchiveGradeMeta.semesterKeys, id: \.self) { key in
                    gradeChip(key: key, title: ArchiveGradeMeta.semesterChips[key] ?? key)
                }
            }
            Text("勾选后该考点会出现在对应学期组；同年级两个学期都勾选按全年处理。高三总复习自动覆盖全部考点。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func gradeChip(key: String, title: String) -> some View {
        let isOn = selection.contains(key)
        return Button {
            if isOn { selection.remove(key) } else { selection.insert(key) }
        } label: {
            Text(title)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                .contextMenu { Text(node.origin == .seed ? "种子节点" : "用户节点") }
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
