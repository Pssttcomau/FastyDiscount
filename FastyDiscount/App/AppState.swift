import SwiftUI

@Observable
@MainActor
final class AppState: Sendable {
    var isOnboardingComplete: Bool = false
    var selectedTab: AppTab = .dashboard

    // MARK: - Container Error State

    /// Set when the ModelContainer fails to initialize.
    /// The UI should present a user-facing error when this is non-nil.
    var containerError: (any Error)?

    var hasContainerError: Bool {
        containerError != nil
    }

    var containerErrorMessage: String {
        containerError?.localizedDescription ?? ""
    }

    // MARK: - AppTab

    /// Represents each root tab in the app.
    ///
    /// Conforms to `Identifiable` for `List(selection:)` binding in the iPad sidebar,
    /// and to `CaseIterable` for iterating all tabs. Each case provides a user-facing
    /// title and SF Symbol icon name.
    enum AppTab: String, CaseIterable, Identifiable, Sendable {
        case dashboard
        case nearby
        case scan
        case history
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .nearby: "Nearby"
            case .scan: "Scan"
            case .history: "History"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: "house.fill"
            case .nearby: "map.fill"
            case .scan: "square.and.arrow.down"
            case .history: "clock.fill"
            case .settings: "gearshape.fill"
            }
        }

        /// Title shown in the Mac sidebar (may differ from tab bar label).
        var macTitle: String {
            switch self {
            case .scan: "Import"
            default: title
            }
        }

        /// SF Symbol shown in the Mac sidebar (may differ from tab bar icon).
        var macSystemImage: String {
            switch self {
            case .scan: "square.and.arrow.down"
            default: systemImage
            }
        }

        /// Whether this tab should be visible when running on Mac Catalyst.
        /// The camera scanner tab is replaced by the Import view on Mac.
        /// Geofencing / Nearby features require always-on location which
        /// is not appropriate for a Mac app; the tab is hidden.
        var isAvailableOnMac: Bool {
            #if targetEnvironment(macCatalyst)
            switch self {
            case .nearby: return false
            default: return true
            }
            #else
            return true
            #endif
        }

        /// All tabs filtered for the current platform.
        static var platformCases: [AppTab] {
            allCases.filter { $0.isAvailableOnMac }
        }
    }
}
