import SwiftUI
import SwiftData

@main
struct FastyDiscountApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(for: [])
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
