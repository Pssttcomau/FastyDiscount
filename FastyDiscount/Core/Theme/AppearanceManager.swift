import SwiftUI

// MARK: - AppearancePreference

/// The three possible user-facing appearance modes.
enum AppearancePreference: String, CaseIterable, Sendable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Converts to SwiftUI's `ColorScheme?` for use with `.preferredColorScheme()`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - AppearanceManager

/// Observable class that manages the user's appearance preference.
/// Preference is persisted to `UserDefaults` under the key `"appearancePreference"`.
///
/// Inject at the root via `.environment(appearanceManager)` and apply
/// the preferred scheme at the root view with `.preferredColorScheme(appearanceManager.colorScheme)`.
@Observable
@MainActor
final class AppearanceManager {

    // MARK: - Constants

    private enum Key {
        static let appearancePreference = "appearancePreference"
    }

    // MARK: - Properties

    /// Currently selected appearance preference. Setting this value persists
    /// the choice to `UserDefaults` automatically.
    var preference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Key.appearancePreference)
        }
    }

    /// The `ColorScheme?` value derived from the current preference.
    /// Pass this directly to `.preferredColorScheme()` on the root view.
    var colorScheme: ColorScheme? {
        preference.colorScheme
    }

    // MARK: - Init

    init() {
        let stored = UserDefaults.standard.string(forKey: Key.appearancePreference)
        preference = AppearancePreference(rawValue: stored ?? "") ?? .system
    }
}
