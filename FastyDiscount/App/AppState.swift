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

    enum AppTab: String, CaseIterable, Sendable {
        case dashboard
        case nearby
        case scan
        case history
        case settings
    }
}
