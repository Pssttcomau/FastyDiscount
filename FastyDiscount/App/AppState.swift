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
            case .scan: "barcode.viewfinder"
            case .history: "clock.fill"
            case .settings: "gearshape.fill"
            }
        }
    }
}
