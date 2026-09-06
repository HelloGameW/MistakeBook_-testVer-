import SwiftUI
import Contracts
import UI

@main
struct MistakeBookApp: App {
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRawValue = AppAppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            StartupView()
                .preferredColorScheme(AppAppearanceMode(rawValue: appearanceRawValue)?.colorScheme)
        }
    }
}

@MainActor
private struct StartupView: View {
    @State private var service: (any AppService)?
    @State private var error: AppError?
    @State private var attempt = UUID()

    var body: some View {
        Group {
            if let service {
                MistakeBookRootView(service: service)
            } else if let error {
                ContentUnavailableView {
                    Label("暂时无法打开错题簿", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.displayMessage)
                } actions: {
                    Button("重试") { self.error = nil; attempt = UUID() }
                }
            } else {
                ProgressView("正在打开本地错题簿…")
            }
        }
        .task(id: attempt) {
            guard service == nil else { return }
            do { service = try await ProductionAssembly.make() }
            catch is CancellationError { }
            catch { self.error = AppError.normalized(error) }
        }
    }
}
