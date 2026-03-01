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
///
/// On Mac Catalyst, also handles:
/// - Menu bar commands routed via `pendingMacAction`
/// - Drag-and-drop file import via `droppedImageURL` / `droppedPDFURL`
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var router = NavigationRouter()
    // Not @State — OnboardingPendingAction is a reference type singleton; @State would
    // not observe mutations made through other reference paths (e.g., from OnboardingView).
    private let pendingAction = OnboardingPendingAction.shared
    @SceneStorage("selectedTab") private var persistedTab: String = AppState.AppTab.dashboard.rawValue

    /// Whether onboarding has been completed. Drives the full-screen cover.
    @State private var onboardingComplete: Bool = OnboardingViewModel.hasCompletedOnboarding

    // MARK: - Mac Catalyst bindings

    /// Pending Mac menu bar action from `FastyDiscountApp`.
    @Binding var pendingMacAction: MacMenuAction?

    /// File URL dropped onto the Mac window (image).
    @Binding var droppedImageURL: URL?

    /// File URL dropped onto the Mac window (PDF).
    @Binding var droppedPDFURL: URL?

    // MARK: - Import sheet (Mac drag-and-drop)

    /// Whether the import sheet is presented (triggered by file drop on Mac).
    @State private var showImportSheet = false

    /// Pre-loaded image URL to pass to ImportView when a file was dropped.
    @State private var importDroppedImageURL: URL?

    /// Pre-loaded PDF URL to pass to ImportView when a file was dropped.
    @State private var importDroppedPDFURL: URL?

    var body: some View {
        AdaptiveNavigationView()
            .environment(router)
            // MARK: Mac Catalyst: enforce minimum window size (800 x 600)
            .macWindowSizeConstraints()
            .onOpenURL { url in
                router.handleDeepLink(url)
            }
            .onAppear {
                // Restore persisted tab on launch
                if let tab = AppState.AppTab(rawValue: persistedTab) {
                    // Ensure the restored tab is valid on the current platform
                    if tab.isAvailableOnMac {
                        router.selectedTab = tab
                    }
                }
            }
            .onChange(of: router.selectedTab) { _, newTab in
                // Persist tab selection for scene restoration
                persistedTab = newTab.rawValue
            }
            // React to onboarding completion so post-onboarding navigation fires
            // after the cover is dismissed — no fragile fixed-delay needed.
            .onChange(of: onboardingComplete) { _, completed in
                guard completed else { return }
                handlePendingAction()
            }
            // MARK: Mac Catalyst: respond to menu bar commands
            .onChange(of: pendingMacAction) { _, action in
                guard let action else { return }
                pendingMacAction = nil
                handleMacMenuAction(action)
            }
            // MARK: Mac Catalyst: respond to dropped image files
            .onChange(of: droppedImageURL) { _, url in
                guard let url else { return }
                droppedImageURL = nil
                importDroppedImageURL = url
                showImportSheet = true
            }
            // MARK: Mac Catalyst: respond to dropped PDF files
            .onChange(of: droppedPDFURL) { _, url in
                guard let url else { return }
                droppedPDFURL = nil
                importDroppedPDFURL = url
                showImportSheet = true
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
                }
            }
            // MARK: Mac Catalyst: import sheet triggered by file drop
            .sheet(isPresented: $showImportSheet, onDismiss: {
                importDroppedImageURL = nil
                importDroppedPDFURL = nil
            }) {
                NavigationStack {
                    MacImportDropView(
                        droppedImageURL: importDroppedImageURL,
                        droppedPDFURL: importDroppedPDFURL
                    )
                    .environment(router)
                }
            }
    }

    // MARK: - Mac Menu Action Routing

    /// Routes a Mac menu bar action to the appropriate navigation destination.
    private func handleMacMenuAction(_ action: MacMenuAction) {
        switch action {
        case .newDVG:
            router.push(.dvgCreate(.manual))

        case .importPhoto:
            router.selectedTab = .scan
            // Push to import view on the scan tab if not already there
            router.setPath(NavigationPath(), for: .scan)

        case .importPDF:
            router.selectedTab = .scan
            router.setPath(NavigationPath(), for: .scan)

        case .showDashboard:
            router.selectedTab = .dashboard

        case .showHistory:
            router.selectedTab = .history

        case .showSettings:
            router.selectedTab = .settings

        case .search:
            router.push(.search(nil))
        }
    }

    // MARK: - Post-Onboarding Navigation

    /// Routes to the appropriate destination after onboarding completes with an action.
    private func handlePendingAction() {
        guard let action = pendingAction.pendingAction else { return }
        pendingAction.pendingAction = nil

        // Small delay to allow the full-screen cover dismissal animation to finish.
        // Uses structured do/catch so cancellation is not silently swallowed, and
        // the pending action is cleared even if the task is cancelled.
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
                switch action {
                case .scan:
                    #if targetEnvironment(macCatalyst)
                    // No camera scanner on Mac — navigate to import instead
                    router.selectedTab = .scan
                    #else
                    router.push(.cameraScanner)
                    #endif
                case .importEmail:
                    router.push(.emailScan)
                case .addManually:
                    router.push(.dvgCreate(.manual))
                }
            } catch {
                // Task was cancelled (e.g., app backgrounded during dismiss).
                // pendingAction is already nil — nothing else to clean up.
            }
        }
    }
}

// MARK: - MacImportDropView

/// A lightweight import view shown in a sheet when the user drops a file onto
/// the Mac window. Pre-populates the import with the dropped file.
///
/// Shares its `ImportViewModel` with `ImportView` so that pre-loading and
/// the user-facing UI stay in sync.
private struct MacImportDropView: View {
    let droppedImageURL: URL?
    let droppedPDFURL: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var router

    /// Shared view model — passed into ImportView so both views observe the same state.
    @State private var sharedViewModel = ImportViewModel()
    @State private var hasTriggeredImport = false

    var body: some View {
        ImportView(viewModel: sharedViewModel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                guard !hasTriggeredImport else { return }
                hasTriggeredImport = true
                if let pdfURL = droppedPDFURL {
                    await sharedViewModel.processPDF(at: pdfURL)
                } else if let imageURL = droppedImageURL {
                    await sharedViewModel.processImageFromURL(imageURL)
                }
            }
    }
}
