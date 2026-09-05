#if os(iOS)
import SwiftUI
import Contracts

/// The production root owns navigation only. All business work is delegated to AppService.
@MainActor
public struct MistakeBookRootView: View {
    private let service: any AppService
    @State private var selectedTab: RootTab = .mistakes
    @State private var showingImport = false
    @State private var showingSettings = false
    @State private var selectedRecordID: UUID?
    @State private var dataRefreshID = 0

    public init(service: any AppService) {
        self.service = service
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            MistakeListView(service: service, selectedRecordID: $selectedRecordID,
                            onImport: { showingImport = true })
                .id(dataRefreshID)
                .tabItem { Label("错题", systemImage: "book.closed") }
                .tag(RootTab.mistakes)

            ArchiveView(service: service)
                .tabItem { Label("归档", systemImage: "folder") }
                .tag(RootTab.archive)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .accessibilityLabel("设置")
            }
            .mbGlassControl()
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showingImport) {
            ImportFlowView(service: service) { dataRefreshID += 1 }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(service: service)
        }
    }
}

private enum RootTab: Hashable {
    case mistakes
    case archive
}

/// A small reusable surface that uses the system Liquid Glass API on iOS 26 and
/// a readable material fallback when accessibility or an older supported runtime requires it.
extension View {
    @ViewBuilder
    func mbGlassControl() -> some View {
        modifier(AccessibleGlass(isControl: true))
    }

    @ViewBuilder
    func mbGlassSurface() -> some View {
        modifier(AccessibleGlass(isControl: false))
    }
}

private struct AccessibleGlass: ViewModifier {
    let isControl: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.padding(isControl ? 8 : 0)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        } else if reduceMotion {
            content.padding(isControl ? 8 : 0).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        } else {
            content.padding(isControl ? 8 : 0).glassEffect()
        }
    }
}
#endif
