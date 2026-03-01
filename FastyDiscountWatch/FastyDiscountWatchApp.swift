import SwiftUI
import WatchKit

// MARK: - FastyDiscountWatchApp

/// The main entry point for the FastyDiscount Apple Watch app.
///
/// Displays a scrollable list of active DVGs synced from the iPhone,
/// allows full-screen barcode viewing for POS scanning, and provides
/// watch face complications showing the next expiring discount.
@main
struct FastyDiscountWatchApp: App {

    // MARK: - Properties

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            DVGListView()
        }
    }
}

// MARK: - WatchAppDelegate

/// Application delegate for the watchOS app.
/// Activates Watch Connectivity on launch.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    func applicationDidFinishLaunching() {
        // Activate Watch Connectivity for communication with iPhone
        WatchConnectivityManager.shared.activate()
    }
}
