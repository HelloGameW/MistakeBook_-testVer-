#if os(iOS)
import SwiftUI

/// Controls the app's appearance independently of the system setting when the
/// user chooses to do so. The default remains fully system-driven.
public enum AppAppearanceMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "mistakebook.appearance.mode"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif
