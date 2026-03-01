import SwiftUI

// MARK: - ContentView

/// The main content view shown after authentication.
///
/// Owns the `NavigationRouter` and injects it into the environment for all
/// child views. Wraps `AdaptiveNavigationView` and handles deep links
/// via `onOpenURL`. Persists the selected tab across app restarts using
/// `@SceneStorage`.
///
/// On first launch, shows `OnboardingView` as a full-screen cover.
/// Completion is tracked in `UserDefaults` via `OnboardingViewModel.hasCompletedOnboarding`.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var router = NavigationRouter()
    @State private var pendingAction = OnboardingPendingAction.shared
    @SceneStorage("selectedTab") private var persistedTab: String = AppState.AppTab.dashboard.rawValue

    /// Whether onboarding has been completed. Drives the full-screen cover.
    @State private var onboardingComplete: Bool = OnboardingViewModel.hasCompletedOnboarding

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
            .fullScreenCover(isPresented: Binding(
                get: { !onboardingComplete },
                set: { showOnboarding in
                    if !showOnboarding {
                        onboardingComplete = true
                    }
                }
            )) {
                OnboardingView {
                    onboardingComplete = true
                    // After the full-screen cover is dismissed, handle any pending navigation
                    handlePendingAction()
                }
            }
    }

    // MARK: - Post-Onboarding Navigation

    /// Routes to the appropriate destination after onboarding completes with an action.
    private func handlePendingAction() {
        guard let action = pendingAction.pendingAction else { return }
        pendingAction.pendingAction = nil

        // Small delay to allow the full-screen cover dismissal animation to finish
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            switch action {
            case .scan:
                router.push(.cameraScanner)
            case .importEmail:
                router.push(.emailScan)
            case .addManually:
                router.push(.dvgCreate(.manual))
            }
        }
    }
}
