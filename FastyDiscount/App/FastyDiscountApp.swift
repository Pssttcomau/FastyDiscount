import SwiftUI
import SwiftData

@main
struct FastyDiscountApp: App {
    @State private var appState = AppState()

    /// Shared ModelContainer configured with CloudKit sync and App Group storage.
    /// Initialized once at app startup; errors are surfaced via AppState.
    private let modelContainer: ModelContainer

    init() {
        let state = AppState()
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
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
        }
        .modelContainer(modelContainer)
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "house.fill") {
                NavigationStack {
                    Text("Dashboard")
                        .navigationTitle("Dashboard")
                }
            }

            Tab("Nearby", systemImage: "map.fill") {
                NavigationStack {
                    Text("Nearby")
                        .navigationTitle("Nearby")
                }
            }

            Tab("Scan", systemImage: "barcode.viewfinder") {
                NavigationStack {
                    Text("Scan")
                        .navigationTitle("Scan")
                }
            }

            Tab("History", systemImage: "clock.fill") {
                NavigationStack {
                    Text("History")
                        .navigationTitle("History")
                }
            }

            Tab("Settings", systemImage: "gearshape.fill") {
                NavigationStack {
                    Text("Settings")
                        .navigationTitle("Settings")
                }
            }
        }
    }
}
