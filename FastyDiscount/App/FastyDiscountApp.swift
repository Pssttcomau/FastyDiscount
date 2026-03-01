import SwiftUI
import SwiftData
import UserNotifications

@main
struct FastyDiscountApp: App {
    @State private var appState = AppState()
    @State private var authViewModel: AuthViewModel
    @State private var appearanceManager = AppearanceManager()

    /// Shared ModelContainer configured with CloudKit sync and App Group storage.
    /// Initialized once at app startup; errors are surfaced via AppState.
    private let modelContainer: ModelContainer

    init() {
        let state = AppState()
        let authService = AppleAuthenticationService()
        let viewModel = AuthViewModel(authService: authService)

        do {
            modelContainer = try ModelContainerFactory.makeContainer()
        } catch {
            // Graceful degradation: surface the error through AppState so the
            // UI can show a user-facing message. A placeholder in-memory
            // container keeps the app from crashing.
            state.containerError = error
            modelContainer = (try? ModelContainer(
                for: ModelContainerFactory.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )) ?? {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }()
        }

        _appState = State(initialValue: state)
        _authViewModel = State(initialValue: viewModel)
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView(authViewModel: authViewModel)
                .environment(appState)
                .environment(appearanceManager)
                .preferredColorScheme(appearanceManager.colorScheme)
                .alert(
                    "Data Unavailable",
                    isPresented: Binding(
                        get: { appState.hasContainerError },
                        set: { _ in }
                    )
                ) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(appState.containerErrorMessage)
                }
                .task {
                    // Register the dvg-expiry notification category.
                    // TASK-022 will add action buttons to this category. Registering
                    // here (on @MainActor via .task) avoids calling a @MainActor
                    // function from init() which can trigger Swift 6 diagnostics.
                    NotificationCategoryRegistrar.registerCategories()

                    // Reschedule all expiry notifications at launch to recover from
                    // clock changes, app kills, or missed rescheduling events.
                    let context = modelContainer.mainContext
                    let repository = SwiftDataDVGRepository(modelContext: context)
                    let activeDVGs = (try? await repository.fetchActive()) ?? []
                    let service = UNExpiryNotificationService()
                    await service.rescheduleAll(activeDVGs: activeDVGs.map(DVGSnapshot.init))
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - AuthGateView

/// Routes between `SignInView` and the main `ContentView` based on auth state.
/// Shows a neutral loading state while credentials are being checked.
private struct AuthGateView: View {
    @State var authViewModel: AuthViewModel

    var body: some View {
        Group {
            switch authViewModel.state {
            case .checking:
                // Splash / loading -- neutral background, no spinner to avoid flash
                Color(.systemBackground)
                    .ignoresSafeArea()

            case .unauthenticated:
                SignInView(viewModel: authViewModel)
                    .transition(.opacity)

            case .authenticated:
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authViewModel.state)
        .task {
            await authViewModel.checkCredentialStateOnLaunch()
        }
    }
}
