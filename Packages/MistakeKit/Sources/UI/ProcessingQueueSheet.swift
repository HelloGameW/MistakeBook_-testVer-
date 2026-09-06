#if os(iOS)
import SwiftUI
import Contracts

/// Processing queue for the most recent import batch: per-page state with retry.
@MainActor
struct ProcessingQueueSheet: View {
    let service: any AppService
    let batchID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var event: BatchEvent?
    @State private var reloadToken = 0
    @State private var errorMessage: String?

    private var orderedJobs: [ProcessingJob] {
        (event?.jobs ?? []).sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
                if event != nil {
                    Section {
                        if event?.isTerminal == true {
                            let allSucceeded = orderedJobs.allSatisfy { $0.state == .succeeded }
                            Label(allSucceeded ? "本批任务全部完成。" : "本批任务已结束。",
                                  systemImage: allSucceeded ? "checkmark.circle" : "info.circle")
                                .foregroundStyle(allSucceeded ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在处理，可以离开这个页面，稍后回来看进度。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("批次状态")
                    }
                    Section {
                        ForEach(Array(orderedJobs.enumerated()), id: \.element.id) { index, job in
                            jobRow(pageNumber: index + 1, job: job)
                        }
                    } header: {
                        Text("任务（\(orderedJobs.count) 项）")
                    } footer: {
                        Text("每一项对应一页图片；失败的任务可以重试，不会影响已完成的页。")
                    }
                } else {
                    Section { ProgressView("正在载入处理状态…") }
                }
            }
            .navigationTitle("处理队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: reloadToken) { observe() }
    }

    private func jobRow(pageNumber: Int, job: ProcessingJob) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Self.icon(for: job.state))
                .foregroundStyle(Self.color(for: job.state))
            VStack(alignment: .leading, spacing: 4) {
                Text("第 \(pageNumber) 页")
                    .font(.subheadline.weight(.medium))
                Text("\(UIStrings.jobState(job.state)) · \(UIStrings.stage(job.stage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = job.error { Text(error.displayMessage).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            if job.state == .failed || job.state == .cancelled {
                Button("重试") { retry(job) }
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func observe() {
        errorMessage = nil
        Task {
            do {
                let stream = try await service.observeBatch(batchID: batchID)
                for await next in stream {
                    event = next
                    if next.isTerminal { break }
                }
            } catch {
                errorMessage = UIErrorMessage.from(error)
            }
        }
    }

    private func retry(_ job: ProcessingJob) {
        Task {
            do { try await service.retry(target: .job(job.id)); reloadToken += 1 }
            catch { errorMessage = UIErrorMessage.from(error) }
        }
    }

    private static func icon(for state: JobState) -> String {
        switch state {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "pause.circle.fill"
        }
    }

    private static func color(for state: JobState) -> Color {
        switch state {
        case .succeeded: .green
        case .failed: .orange
        case .cancelled: .secondary
        default: .accentColor
        }
    }
}
#endif
