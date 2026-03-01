import SwiftUI

// MARK: - NavigationRouter

/// Centralized navigation state manager for the app.
///
/// Manages the selected tab and per-tab `NavigationPath` stacks so that
/// each tab preserves its own navigation history. Injected into the
/// environment via `.environment()` and consumed with `@Environment`.
///
/// Deep link handling is built in: call `handleDeepLink(_:)` with an
/// incoming URL and the router will parse it, switch to the correct tab,
/// and push the appropriate destination.
@Observable
@MainActor
final class NavigationRouter {

    // MARK: - Properties

    /// The currently selected tab. Persisted across app restarts via
    /// `@SceneStorage` in the hosting view.
    var selectedTab: AppState.AppTab = .dashboard

    /// Per-tab navigation paths, keyed by `AppTab`.
    /// Each tab maintains its own independent navigation stack.
    var paths: [AppState.AppTab: NavigationPath] = [
        .dashboard: NavigationPath(),
        .nearby: NavigationPath(),
        .scan: NavigationPath(),
        .history: NavigationPath(),
        .settings: NavigationPath(),
    ]

    // MARK: - Navigation Path Access

    /// Returns a binding to the navigation path for the given tab.
    /// Falls back to an empty path if the tab has not been visited yet.
    func path(for tab: AppState.AppTab) -> NavigationPath {
        paths[tab] ?? NavigationPath()
    }

    /// Sets the navigation path for the given tab.
    func setPath(_ path: NavigationPath, for tab: AppState.AppTab) {
        paths[tab] = path
    }

    // MARK: - Programmatic Navigation

    /// Pushes a destination onto the current tab's navigation stack.
    func push(_ destination: AppDestination) {
        paths[selectedTab, default: NavigationPath()].append(destination)
    }

    /// Pushes a destination onto a specific tab's navigation stack.
    func push(_ destination: AppDestination, on tab: AppState.AppTab) {
        paths[tab, default: NavigationPath()].append(destination)
    }

    /// Pops the top destination from the current tab's navigation stack.
    func pop() {
        guard var currentPath = paths[selectedTab], !currentPath.isEmpty else { return }
        currentPath.removeLast()
        paths[selectedTab] = currentPath
    }

    /// Pops all destinations from the current tab, returning to its root view.
    func popToRoot() {
        paths[selectedTab] = NavigationPath()
    }

    /// Pops all destinations from a specific tab.
    func popToRoot(for tab: AppState.AppTab) {
        paths[tab] = NavigationPath()
    }

    // MARK: - Deep Link Handling

    /// Parses an incoming URL and navigates to the appropriate destination.
    ///
    /// Supported URL format: `fastydiscount://dvg/{uuid}`
    ///
    /// - Parameter url: The incoming deep link URL.
    /// - Returns: `true` if the URL was handled, `false` otherwise.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme == AppConstants.DeepLink.scheme else { return false }

        let host = url.host(percentEncoded: false)
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case AppConstants.DeepLink.dvgPath:
            // Format: fastydiscount://dvg/{uuid}
            // The UUID is the first path component (or the host content for host-style URLs)
            if let uuidString = pathComponents.first, let uuid = UUID(uuidString: uuidString) {
                navigateToDVGDetail(uuid)
                return true
            }

            // Fallback: try parsing the rest of the URL path for simpler formats
            // e.g., fastydiscount://dvg/SOME-UUID
            return false

        default:
            // Also handle: fastydiscount://dvg/UUID where "dvg" could be host
            // Some URL parsers treat the first component differently.
            // Try: scheme://dvg/{id} where dvg is host and {id} is path
            if host == AppConstants.DeepLink.dvgPath, pathComponents.isEmpty {
                // No path components beyond host; URL might be malformed
                return false
            }
            return false
        }
    }

    // MARK: - Private Helpers

    private func navigateToDVGDetail(_ id: UUID) {
        selectedTab = .dashboard
        // Clear existing navigation stack for dashboard, then push the detail
        paths[.dashboard] = NavigationPath()
        paths[.dashboard, default: NavigationPath()].append(AppDestination.dvgDetail(id))
    }
}
