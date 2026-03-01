import SwiftUI
import SwiftData
import UserNotifications
import CoreLocation

@main
struct FastyDiscountApp: App {
    @State private var appState = AppState()
    @State private var authViewModel: AuthViewModel
    @State private var appearanceManager = AppearanceManager()

    /// Shared ModelContainer configured with CloudKit sync and App Group storage.
    /// Initialized once at app startup; errors are surfaced via AppState.
    private let modelContainer: ModelContainer

    /// Notification action handler set as the `UNUserNotificationCenter` delegate.
    ///
    /// Retained here (as a strong reference on the `@main` App struct) so it is
    /// never released while the app is running. The delegate is set in `init()`
    /// — before any notification can arrive — as required by Apple's documentation.
    private let notificationActionHandler: NotificationActionHandler

    /// Geofence manager responsible for monitoring store-location regions and
    /// sending location-based notifications. Retained here so the
    /// `CLLocationManager` (and its delegate) live for the entire app lifecycle.
    private let geofenceManager: GeofenceManager

    /// Shared location permission manager. Owns the two-step permission flow and
    /// exposes the current `authorizationState` as an observable property. Passed
    /// to `GeofenceManager` and made available to the environment so child views
    /// (map, DVG form) can trigger permission requests.
    private let locationPermissionManager: LocationPermissionManager

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

        // Set up the notification delegate BEFORE the app finishes launching
        // so no notification response is ever missed. The delegate must be set
        // here in init(), not in .task or .onAppear.
        let handler = NotificationActionHandler(modelContainer: modelContainer)
        notificationActionHandler = handler
        UNUserNotificationCenter.current().delegate = handler

        // Create the shared location permission manager. This is the single source
        // of truth for location authorization state, used by both the UI and GeofenceManager.
        let permManager = LocationPermissionManager()
        locationPermissionManager = permManager

        // Initialise the geofence manager. It creates and owns a CLLocationManager
        // on the main thread. Actual geofence registration happens in .task below.
        geofenceManager = GeofenceManager(modelContainer: modelContainer, permissionManager: permManager)

        // Register notification categories early so that any delivered
        // notifications already in the system use the correct action buttons.
        // `NotificationCategoryRegistrar.registerCategories()` is @MainActor,
        // so it is also called in the .task modifier below (on @MainActor).
        // The call here is intentionally omitted because init() is not isolated
        // to @MainActor; the .task call below handles this reliably.

        _appState = State(initialValue: state)
        _authViewModel = State(initialValue: viewModel)
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView(authViewModel: authViewModel)
                .environment(appState)
                .environment(appearanceManager)
                .environment(locationPermissionManager)
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
                    // Register the dvg-expiry and dvg-location notification categories
                    // (with View Code, Mark as Used, and Snooze action buttons).
                    // Registering here (on @MainActor via .task) avoids calling a
                    // @MainActor function from init() which triggers Swift 6 diagnostics.
                    NotificationCategoryRegistrar.registerCategories()

                    // Reschedule all expiry notifications at launch to recover from
                    // clock changes, app kills, or missed rescheduling events.
                    let context = modelContainer.mainContext
                    let repository = SwiftDataDVGRepository(modelContext: context)
                    let activeDVGs = (try? await repository.fetchActive()) ?? []
                    let service = UNExpiryNotificationService()
                    await service.rescheduleAll(activeDVGs: activeDVGs.map(DVGSnapshot.init))

                    // Recalculate geofences at launch so the top-20 monitored
                    // regions reflect current DVG state and user location.
                    await geofenceManager.recalculateGeofences()

                    // Start monitoring for significant location changes so geofences
                    // are recalculated when the user moves 500m+. This also handles
                    // background and cold-launch wakeups triggered by the OS.
                    geofenceManager.startSignificantLocationMonitoring()
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
