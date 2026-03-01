import SwiftUI

// MARK: - ContentView

/// The main content view shown after authentication.
///
/// Owns the `NavigationRouter` and injects it into the environment for all
/// child views. Wraps `AdaptiveNavigationView` and handles deep links
/// via `onOpenURL`. Persists the selected tab across app restarts using
/// `@SceneStorage`.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var router = NavigationRouter()
    @SceneStorage("selectedTab") private var persistedTab: String = AppState.AppTab.dashboard.rawValue

    var body: some View {
        AdaptiveNavigationView()
            .environment(router)
            .onOpenURL { url in
                router.handleDeepLink(url)
            }
            .onAppear {
                // Restore persisted tab on launch
                if let tab = AppState.AppTab(rawValue: persistedTab) {
                    router.selectedTab = tab
                }
            }
            .onChange(of: router.selectedTab) { _, newTab in
                // Persist tab selection for scene restoration
                persistedTab = newTab.rawValue
            }
    }
}
