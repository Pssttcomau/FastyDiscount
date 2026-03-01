import SwiftUI

@Observable
@MainActor
final class AppState: Sendable {
    var isOnboardingComplete: Bool = false
    var selectedTab: AppTab = .dashboard

    enum AppTab: String, CaseIterable, Sendable {
        case dashboard
        case nearby
        case scan
        case history
        case settings
    }
}
