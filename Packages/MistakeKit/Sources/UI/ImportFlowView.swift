#if os(iOS)
import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Contracts

@MainActor
struct ImportFlowView: View {
    let service: any AppService
    var onBatch: (UUID) -> Void = { _ in }
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ImportFlowViewModel
    @State private var mode: InputMode = .images
    @State private var recordMode: ImportedRecordMode = .text
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var showingDocumentScanner = false
    @State private var permissionMessage: String?
    @State private var manualStem = ""
    @State private var manualStudentWork = ""
    @State private var manualReferenceAnswer = ""
    @State private var manualNotes = ""
    @State private var isSavingManual = false

    init(service: any AppService, onBatch: @escaping (UUID) -> Void = { _ in }, onChanged: @escaping () -> Void = {}) {
        self.service = service
        self.onBatch = onBatch
        self.onChanged = onChanged
        _model = StateObject(wrappedValue: ImportFlowViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("录入方式", selection: $mode) {
                        Text("图片整理").tag(InputMode.images)
                        Text("手动录入").tag(InputMode.manual)
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .images {
                    imageInputSection
                } else {
                    manualInputSection
                }

                if let permissionMessage = permissionMessage {
                    Section { ErrorBanner(message: permissionMessage) }
                }
                if let errorMessage = model.errorMessage {
                    Section { ErrorBanner(message: errorMessage) }
                }
                if let successMessage = model.successMessage {
                    Section { NoticeBanner(message: successMessage) }
                }

                if let event = model.batchEvent {
                    processingSection(event)
                }
            }
            .navigationTitle("录入错题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onChanged()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraImagePicker { imageData in
                    showingCamera = false
                    submitImageData(imageData, sourceName: "相机照片")
                } onCancel: {
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingDocumentScanner) {
                DocumentScannerView { pages in
                    showingDocumentScanner = false
                    submit(pages: pages)
                } onCancel: {
                    showingDocumentScanner = false
                } onError: { message in
                    showingDocumentScanner = false
                    permissionMessage = message
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): loadFiles(urls)
                case .failure(let error): permissionMessage = UIErrorMessage.from(error)
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                loadPhotos(items)
                photoItems = []
            }
            .onChange(of: model.batchID) { _, batchID in
                if let batchID { onBatch(batchID) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var imageInputSection: some View {
        Section {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                Label("从相册选择图片", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                requestCamera { showingCamera = true }
            } label: {
                Label("拍照录入", systemImage: "camera")
            }

            Button {
                requestCamera { showingDocumentScanner = true }
            } label: {
                Label("扫描文稿", systemImage: "doc.viewfinder")
            }

            Button {
                showingFileImporter = true
            } label: {
                Label("从文件选择图片", systemImage: "folder")
            }

            Picker("错题内容", selection: $recordMode) {
                Text("转文字").tag(ImportedRecordMode.text)
                Text("转图片").tag(ImportedRecordMode.image)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("错题内容模式")

            Text(recordModeExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("一次最多整理 20 张图片，原图始终保留。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("图片来源")
        }
    }

    private var recordModeExplanation: String {
        switch recordMode {
        case .text:
            return "识别文字作为题目内容，支持编辑与检索。"
        case .image:
            return "按题号自动截取题目区域图片作为题目内容；识别文字保留用于检索，区域可在详情页手动调整。"
        }
    }

    private var manualInputSection: some View {
        Section {
            TextEditor(text: $manualStem)
                .frame(minHeight: 100)
                .overlay(alignment: .topLeading) {
                    if manualStem.isEmpty {
                        Text("题干（必填）")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("题干")

            TextEditor(text: $manualStudentWork)
                .frame(minHeight: 90)
                .overlay(alignment: .topLeading) {
                    if manualStudentWork.isEmpty {
                        Text("学生作答或解题步骤（可选）")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("学生作答或解题步骤")

            TextEditor(text: $manualReferenceAnswer)
                .frame(minHeight: 80)
                .overlay(alignment: .topLeading) {
                    if manualReferenceAnswer.isEmpty {
                        Text("参考答案或教师批注（可选）")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("参考答案或教师批注")

            TextField("笔记（可选）", text: $manualNotes, axis: .vertical)
                .lineLimit(2...5)

            PrimaryActionButton(title: isSavingManual ? "正在保存…" : "保存手动录入",
                                systemImage: "checkmark.circle") {
                saveManualRecord()
            }
            .disabled(manualStem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingManual)
        } header: {
            Text("直接保存草稿")
        } footer: {
            Text("没有图片也可以保存；没有足够证据时，错因和归档会保持待确认。")
        }
    }

    private func processingSection(_ event: BatchEvent) -> some View {
        Section {
            if model.isImporting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在整理，页面会显示真实处理阶段…")
                        .foregroundStyle(.secondary)
                }
            } else if event.isTerminal {
                Label("本批次已结束，可关闭此页面查看已保存草稿。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            ForEach(event.jobs, id: \.id) { job in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: job.state))
                        .foregroundStyle(color(for: job.state))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("页面 \(job.id.uuidString.prefix(6))")
                            .font(.subheadline.weight(.medium))
                        Text("\(UIStrings.jobState(job.state)) · \(UIStrings.stage(job.stage))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = job.error { Text(error.displayMessage).font(.caption).foregroundStyle(.orange) }
                    }
                    Spacer()
                    if job.state == .failed || job.state == .cancelled {
                        Button("重试") { model.retry(jobID: job.id) }
                            .buttonStyle(.bordered)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if model.isImporting, let batchID = model.batchID {
                Button("取消此批次") { model.cancel() }
                    .foregroundStyle(.red)
                    .accessibilityHint("停止尚未完成的图片整理任务")
                    .id(batchID)
            }
        } header: {
            Text("整理状态")
        } footer: {
            Text("状态来自 AppService 事件；这里不把处理阶段伪装成百分比。")
        }
    }

    private func saveManualRecord() {
        isSavingManual = true
        Task { [weak model, service = self.service] in
            do {
                _ = try await service.createManualRecord(draft: ManualRecordDraft(
                    stem: manualStem,
                    studentWork: manualStudentWork,
                    referenceAnswer: manualReferenceAnswer.isEmpty ? nil : manualReferenceAnswer,
                    notes: manualNotes,
                    tags: []))
                guard let model else { return }
                model.successMessage = "已保存手动录入。"
                manualStem = ""
                manualStudentWork = ""
                manualReferenceAnswer = ""
                manualNotes = ""
                isSavingManual = false
                onChanged()
            } catch {
                guard let model else { return }
                model.errorMessage = UIErrorMessage.from(error)
                isSavingManual = false
            }
        }
    }

    private func requestCamera(_ action: @escaping () -> Void) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            permissionMessage = "此设备没有可用相机；可以改用相册、文件或手动录入。"
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            action()
        case .notDetermined:
            Task { @MainActor in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { action() }
                else { permissionMessage = "相机权限未开启；可以改用相册、文件或手动录入。" }
            }
        default:
            permissionMessage = "相机权限未开启；可以在系统设置中允许后重试，也可以改用相册、文件或手动录入。"
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        Task { @MainActor in
            var pages: [ImportedPage] = []
            for (index, item) in items.prefix(20).enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pages.append(ImportedPage(id: UUID(), bytes: data, mediaType: MediaType.detect(data: data),
                                              sourceName: "相册图片 \(index + 1)", order: index))
                }
            }
            submit(pages: pages)
        }
    }

    private func loadFiles(_ urls: [URL]) {
        Task { @MainActor in
            var pages: [ImportedPage] = []
            for (index, url) in urls.prefix(20).enumerated() {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    pages.append(ImportedPage(id: UUID(), bytes: data, mediaType: MediaType.detect(data: data, name: url.lastPathComponent),
                                              sourceName: url.lastPathComponent, order: index))
                }
            }
            submit(pages: pages)
        }
    }

    private func submitImageData(_ data: Data?, sourceName: String) {
        guard let data else { return }
        submit(pages: [ImportedPage(id: UUID(), bytes: data, mediaType: MediaType.detect(data: data), sourceName: sourceName, order: 0)])
    }

    private func submit(pages: [ImportedPage]) {
        guard !pages.isEmpty else {
            permissionMessage = "没有读到可处理的图片；可以重试或改用手动录入。"
            return
        }
        model.importPages(pages, recordMode: recordMode)
        onChanged()
    }

    private func icon(for state: JobState) -> String {
        switch state {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "pause.circle.fill"
        }
    }

    private func color(for state: JobState) -> Color {
        switch state {
        case .succeeded: .green
        case .failed: .orange
        case .cancelled: .secondary
        default: .accentColor
        }
    }
}

private enum InputMode: Hashable {
    case images
    case manual
}

private extension MediaType {
    static func detect(data: Data, name: String = "") -> MediaType {
        let lowerName = name.lowercased()
        if lowerName.hasSuffix(".png") || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if lowerName.hasSuffix(".heic") || lowerName.hasSuffix(".heif") { return .heic }
        return .jpeg
    }
}
#endif
