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
    @State private var showingTaxonomy = false
    @State private var showingAnnouncements = false
    @State private var didAutoPresentAnnouncement = false
    @State private var dataRefreshID = 0
    @State private var lastBatchID: UUID?
    @StateObject private var announcementStore: AnnouncementStore

    public init(service: any AppService) {
        self.service = service
        _announcementStore = StateObject(wrappedValue: AnnouncementStore())
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            // refreshToken nudges the list to re-query after imports; rebuilding
            // the whole subtree with .id() discarded view state and re-created
            // the view model, which made every import feel like a restart.
            MistakeListView(service: service, lastBatchID: lastBatchID, refreshToken: dataRefreshID,
                            onImport: { showingImport = true },
                            onSettings: { showingSettings = true })
                .tabItem { Label("错题", systemImage: "book.closed") }
                .tag(RootTab.mistakes)

            ArchivedRecordListView(service: service, onSettings: { showingSettings = true },
                                   onManageTaxonomy: { showingTaxonomy = true })
                .tabItem { Label("归档", systemImage: "folder") }
                .tag(RootTab.archive)
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            if let announcement = announcementStore.latestPublished {
                AnnouncementBanner(announcement: announcement) {
                    announcementStore.markRead(announcement.id)
                    showingAnnouncements = true
                }
                .padding(.horizontal)
            }
        }
        .task { announcementStore.load() }
        .onChange(of: announcementStore.latestUnreadPublished?.id) { _, _ in
            guard !didAutoPresentAnnouncement,
                  let announcement = announcementStore.latestUnreadPublished else { return }
            didAutoPresentAnnouncement = true
            announcementStore.markRead(announcement.id)
            showingAnnouncements = true
        }
        .sheet(isPresented: $showingImport) {
            ImportFlowView(service: service, onBatch: { lastBatchID = $0 }) { dataRefreshID += 1 }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(service: service, announcementStore: announcementStore)
        }
        .sheet(isPresented: $showingAnnouncements) {
            AnnouncementCenterView(store: announcementStore)
        }
        .sheet(isPresented: $showingTaxonomy) {
            ArchiveView(service: service)
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
