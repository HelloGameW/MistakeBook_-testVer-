#if os(iOS)
import Foundation
import SwiftUI

/// A local announcement. Announcements are intentionally device-local: this
/// feature provides an in-app notice channel without adding a network or
/// account dependency to the app.
struct Announcement: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var message: String
    var createdAt: Date
    var updatedAt: Date
    var isPublished: Bool

    init(id: UUID = UUID(), title: String, message: String,
         createdAt: Date = .now, updatedAt: Date = .now, isPublished: Bool = true) {
        self.id = id
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPublished = isPublished
    }
}

@MainActor
final class AnnouncementStore: ObservableObject {
    @Published private(set) var announcements: [Announcement] = []
    @Published private(set) var readIDs: Set<UUID> = []
    @Published private(set) var isLoaded = false
    @Published private(set) var errorMessage: String?

    private struct Persisted: Codable {
        var announcements: [Announcement]
        var readIDs: Set<UUID>
    }

    private let fileURL: URL
    private let fileManager = FileManager.default

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    var publishedAnnouncements: [Announcement] {
        announcements
            .filter(\.isPublished)
            .sorted { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString > rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
            }
    }

    var latestPublished: Announcement? { publishedAnnouncements.first }

    var latestUnreadPublished: Announcement? {
        publishedAnnouncements.first { !readIDs.contains($0.id) }
    }

    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let persisted = try decoder.decode(Persisted.self, from: data)
                announcements = persisted.announcements
                readIDs = persisted.readIDs
            } else {
                announcements = [Self.initialAnnouncement()]
                try persist()
            }
            errorMessage = nil
        } catch {
            announcements = []
            readIDs = []
            errorMessage = "本地公告暂时无法载入。"
        }
    }

    func add(title: String, message: String, isPublished: Bool) throws {
        let now = Date()
        let announcement = Announcement(title: title, message: message, createdAt: now,
                                        updatedAt: now, isPublished: isPublished)
        try mutate {
            announcements.append(announcement)
        }
    }

    func update(id: UUID, title: String, message: String, isPublished: Bool) throws {
        try mutate {
            guard let index = announcements.firstIndex(where: { $0.id == id }) else { return }
            announcements[index].title = title
            announcements[index].message = message
            announcements[index].updatedAt = Date()
            announcements[index].isPublished = isPublished
        }
    }

    func setPublished(id: UUID, isPublished: Bool) throws {
        try mutate {
            guard let index = announcements.firstIndex(where: { $0.id == id }) else { return }
            announcements[index].isPublished = isPublished
            announcements[index].updatedAt = Date()
        }
    }

    func delete(id: UUID) throws {
        try mutate {
            announcements.removeAll { $0.id == id }
            readIDs.remove(id)
        }
    }

    func markRead(_ id: UUID) {
        guard !readIDs.contains(id) else { return }
        readIDs.insert(id)
        try? persist()
    }

    private func mutate(_ change: () -> Void) throws {
        let previousAnnouncements = announcements
        let previousReadIDs = readIDs
        change()
        do {
            try persist()
            errorMessage = nil
        } catch {
            announcements = previousAnnouncements
            readIDs = previousReadIDs
            errorMessage = "公告保存失败，请检查本机存储空间。"
            throw error
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Persisted(announcements: announcements, readIDs: readIDs))
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MistakeBook", isDirectory: true)
            .appendingPathComponent("announcements.json")
    }

    private static func initialAnnouncement() -> Announcement {
        Announcement(title: "MistakeBook 0.8.0 已更新",
                     message: "模型选择已统一归入“模型选择”页面，图像识别默认使用智谱 glm-ocr；新增跟随系统、浅色和深色配色，以及暗色/着色 App 图标。你也可以在设置中管理本机公告。")
    }
}

@MainActor
struct AnnouncementBanner: View {
    let announcement: Announcement
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "megaphone.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(announcement.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(announcement.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .mbGlassSurface()
        .accessibilityLabel("公告：\(announcement.title)")
        .accessibilityHint("打开公告中心")
    }
}

@MainActor
struct AnnouncementCenterView: View {
    @ObservedObject var store: AnnouncementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.publishedAnnouncements.isEmpty {
                    ContentUnavailableView("暂无公告", systemImage: "megaphone")
                } else {
                    List(store.publishedAnnouncements) { announcement in
                        Button {
                            store.markRead(announcement.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(announcement.title)
                                        .font(.headline)
                                    if !store.readIDs.contains(announcement.id) {
                                        Circle()
                                            .fill(.tint)
                                            .frame(width: 7, height: 7)
                                            .accessibilityHidden(true)
                                    }
                                }
                                Text(announcement.message)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Text(announcement.updatedAt, format: .dateTime.year().month().day())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { store.load() }
    }
}

@MainActor
struct AnnouncementManagementView: View {
    @ObservedObject var store: AnnouncementStore
    @State private var showingEditor = false
    @State private var editingAnnouncement: Announcement?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if store.announcements.isEmpty {
                ContentUnavailableView("还没有公告", systemImage: "megaphone")
            } else {
                List {
                    Section {
                        ForEach(store.announcements) { announcement in
                            Button { edit(announcement) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(announcement.title)
                                            .font(.headline)
                                        Spacer()
                                        Text(announcement.isPublished ? "已发布" : "草稿")
                                            .font(.caption)
                                            .foregroundStyle(announcement.isPublished ? .tint : .secondary)
                                    }
                                    Text(announcement.message)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { remove(announcement) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("本机公告")
                    } footer: {
                        Text("公告只保存在本机，不会同步到其他设备或上传网络。")
                    }
                }
            }
        }
        .navigationTitle("管理公告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新建", systemImage: "plus") { edit(nil) }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = errorMessage ?? store.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
        .sheet(isPresented: $showingEditor) {
            AnnouncementEditorView(announcement: editingAnnouncement) { title, message, isPublished in
                save(title: title, message: message, isPublished: isPublished)
            }
        }
        .task { store.load() }
    }

    private func edit(_ announcement: Announcement?) {
        editingAnnouncement = announcement
        errorMessage = nil
        showingEditor = true
    }

    private func save(title: String, message: String, isPublished: Bool) {
        do {
            if let editingAnnouncement {
                try store.update(id: editingAnnouncement.id, title: title, message: message, isPublished: isPublished)
            } else {
                try store.add(title: title, message: message, isPublished: isPublished)
            }
            showingEditor = false
            errorMessage = nil
        } catch {
            errorMessage = "公告保存失败。"
        }
    }

    private func remove(_ announcement: Announcement) {
        do {
            try store.delete(id: announcement.id)
            errorMessage = nil
        } catch {
            errorMessage = "公告删除失败。"
        }
    }
}

@MainActor
private struct AnnouncementEditorView: View {
    let announcement: Announcement?
    let onSave: (String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var message: String
    @State private var isPublished: Bool

    init(announcement: Announcement?, onSave: @escaping (String, String, Bool) -> Void) {
        self.announcement = announcement
        self.onSave = onSave
        _title = State(initialValue: announcement?.title ?? "")
        _message = State(initialValue: announcement?.message ?? "")
        _isPublished = State(initialValue: announcement?.isPublished ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextField("标题", text: $title)
                    TextField("公告正文", text: $message, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    Toggle("立即发布", isOn: $isPublished)
                } footer: {
                    Text("发布后会在首页显示横幅，并在首次发现时弹出公告中心。")
                }
            }
            .navigationTitle(announcement == nil ? "新建公告" : "编辑公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                               message.trimmingCharacters(in: .whitespacesAndNewlines), isPublished)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
#endif
