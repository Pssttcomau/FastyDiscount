import SwiftUI

@main
struct FastyDiscountWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

struct WatchContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("FastyDiscount")
                    .font(.headline)
            }
            .navigationTitle("Discounts")
        }
    }
}
