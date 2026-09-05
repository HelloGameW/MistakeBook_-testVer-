#if os(iOS)
import PDFKit
import SwiftUI
import UIKit
import Contracts

struct ExportSheet: View {
    let service: any AppService
    let records: [MistakeRecord]
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: ExportMode = .practice
    @State private var includeHandwriting = false
    @State private var includeHypotheses = false
    @State private var blankSpace: BlankSpace = .medium
    @State private var sort: ExportSort = .selectionOrder
    @State private var includeRiskyImages = false
    @State private var isExporting = false
    @State private var artifact: ExportArtifact?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if records.isEmpty {
                    ContentUnavailableView("没有可导出的题目", systemImage: "doc.badge.questionmark",
                                           description: Text("请先保存题目，或返回选择需要导出的题目。"))
                } else if let artifact {
                    previewSection(artifact)
                } else {
                    optionsSection
                }
                if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
            }
            .navigationTitle("导出 PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { close() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { releaseArtifact() }
    }

    private var optionsSection: some View {
        Section {
            Picker("导出模式", selection: $mode) {
                Text("练习版").tag(ExportMode.practice)
                Text("含解析版").tag(ExportMode.withSolutions)
            }
            .pickerStyle(.segmented)

            Picker("题目顺序", selection: $sort) {
                Text("当前选择顺序").tag(ExportSort.selectionOrder)
                Text("按学科和知识点").tag(ExportSort.subjectAndTaxonomy)
            }
            Picker("留白", selection: $blankSpace) {
                Text("无").tag(BlankSpace.none)
                Text("小").tag(BlankSpace.small)
                Text("中").tag(BlankSpace.medium)
                Text("大").tag(BlankSpace.large)
            }
            Toggle("加入手写过程", isOn: $includeHandwriting)
                .disabled(mode == .practice)
            Toggle("加入候选错因", isOn: $includeHypotheses)
                .disabled(mode == .practice)
            Toggle("保留可能含答案的原图", isOn: $includeRiskyImages)

            if mode == .practice {
                NoticeBanner(message: "练习版不会输出结构化学生答案、参考答案、错因或笔记；原图本身若含手写/批注，仍可能带答案。")
            } else {
                NoticeBanner(message: "过时分析和被拒绝候选不会进入正式解析；待确认候选会明确标注为候选。")
            }

            Text("将导出 \(records.count) 道题，页面大小固定为 A4 纵向。长题按内容分页，图片保持比例。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PrimaryActionButton(title: isExporting ? "正在生成…" : "生成 PDF", systemImage: "doc.richtext") {
                export()
            }
            .disabled(isExporting)
        } header: {
            Text("导出选项")
        }
    }

    private func previewSection(_ artifact: ExportArtifact) -> some View {
        Section {
            Label("已生成 \(artifact.summary.pageCount) 页 PDF", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            PDFPreviewView(url: artifact.fileURL)
                .frame(minHeight: 320, maxHeight: 560)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .accessibilityLabel("PDF 预览")
            ShareLink(item: artifact.fileURL) {
                Label("分享或保存 PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if !artifact.summary.warnings.isEmpty {
                ForEach(Array(artifact.summary.warnings.enumerated()), id: \.offset) { _, warning in
                    ErrorBanner(message: warning.message)
                }
            }
            Button("完成") { close() }
        } header: {
            Text("预览与分享")
        } footer: {
            Text("文件会保留到显式释放、下次启动清理或系统生命周期结束；分享界面由系统提供。")
        }
    }

    private func export() {
        guard let options = try? ExportOptions(mode: mode,
                                                includeHandwriting: mode == .withSolutions && includeHandwriting,
                                                includeHypotheses: mode == .withSolutions && includeHypotheses,
                                                blankSpace: blankSpace, sort: sort, pageSize: .a4) else {
            errorMessage = "导出选项组合无效，请重新选择。"
            return
        }
        isExporting = true
        errorMessage = nil
        let request = ExportRequest(selection: .ids(records.map(\.id)), options: options,
                                    imageDecisions: makeImageDecisions())
        Task {
            do {
                artifact = try await service.export(request: request)
                onFinished()
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
            isExporting = false
        }
    }

    private func makeImageDecisions() -> [ExportImageDecision] {
        records.flatMap { record in
            record.sourceRegions.map { region in
                let isStudentWork = region.purpose == .studentWork
                let isReferenceAnswer = region.purpose == .referenceAnswer
                let shouldExclude = mode == .practice && (isStudentWork || isReferenceAnswer) && !includeRiskyImages
                return ExportImageDecision(regionID: region.id, assetID: region.assetID,
                                           disposition: shouldExclude ? .exclude : .includeFullImage,
                                           cropRect: nil,
                                           answerRisk: isStudentWork ? .mayContainAnswer : .unknown,
                                           userConfirmed: includeRiskyImages && isStudentWork)
            }
        }
    }

    private func close() {
        releaseArtifact()
        dismiss()
    }

    private func releaseArtifact() {
        guard let artifact else { return }
        self.artifact = nil
        Task { try? await service.releaseExport(artifactID: artifact.id) }
    }
}

struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(url: url)
    }
}
#endif
