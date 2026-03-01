import Foundation
import CoreLocation
import OSLog

// MARK: - LocationAuthorizationState

/// A simplified, UI-friendly representation of `CLAuthorizationStatus`.
///
/// Maps the system's raw enum to the states that matter for the app's
/// permission flow, making it easy for views to react to changes.
enum LocationAuthorizationState: Equatable {
    /// The user has not yet been asked for location permission.
    case notDetermined
    /// The app is restricted from accessing location (parental controls, MDM).
    case restricted
    /// The user explicitly denied location access.
    case denied
    /// Location access is granted only while the app is in the foreground.
    case whenInUse
    /// Full background location access is granted.
    case always
}

// MARK: - LocationPermissionManager

/// Observable manager that owns the two-step location permission flow.
///
/// ### Two-Step Flow
/// Apple recommends requesting "When In Use" first so the user sees immediate
/// value before being asked for the higher-privilege "Always" access:
/// 1. **Step 1** (`requestWhenInUse()`): Shown from the map or geofencing UI.
/// 2. **Step 2** (`requestAlways()`): Shown ONLY after the user has added a DVG
///    with a store location. Never call this before Step 1 is granted.
///
/// ### Explanation Sheet
/// Call `shouldShowWhenInUseExplanation` / `shouldShowAlwaysExplanation`
/// to gate presentation of a custom SwiftUI explanation view BEFORE triggering
/// the system dialog. Showing a benefit-focused explanation first significantly
/// improves the grant rate.
///
/// ### Swift 6 Concurrency
/// This class is `@Observable @MainActor` so all property mutations happen on
/// the main actor. `CLLocationManagerDelegate` callbacks are `nonisolated` and
/// hop back to `@MainActor` via a `Task { @MainActor }` trampoline.
@Observable
@MainActor
final class LocationPermissionManager: NSObject {

    // MARK: - Observable Properties

    /// The current, simplified authorization state. Observable by views and
    /// `GeofenceManager`.
    private(set) var authorizationState: LocationAuthorizationState = .notDetermined

    /// Whether the custom "When In Use" explanation sheet should be shown.
    /// Cleared once the user taps through to request permission.
    var showWhenInUseExplanation: Bool = false

    /// Whether the custom "Always" explanation sheet should be shown.
    /// Cleared once the user taps through to request permission.
    var showAlwaysExplanation: Bool = false

    // MARK: - Private Properties

    private let locationManager: CLLocationManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FastyDiscount",
        category: "LocationPermissionManager"
    )

    // MARK: - Init

    override init() {
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        // Sync state immediately with the current system status
        authorizationState = Self.map(locationManager.authorizationStatus)
        logger.info("LocationPermissionManager initialised — state: \(String(describing: self.authorizationState))")
    }

    // MARK: - Public API — Step 1: When In Use

    /// Initiates Step 1 of the permission flow.
    ///
    /// Shows a custom explanation sheet before the system dialog.
    /// Call this when the user opens the nearby map or taps "Enable Location"
    /// for the first time.
    ///
    /// - Note: No-op if permission is already determined.
    func requestWhenInUsePermission() {
        guard authorizationState == .notDetermined else {
            logger.debug("requestWhenInUsePermission called but state is already \(String(describing: self.authorizationState)) — skipping")
            return
        }
        logger.info("Presenting 'When In Use' explanation sheet")
        showWhenInUseExplanation = true
    }

    /// Called when the user taps "Allow" on the custom explanation sheet.
    ///
    /// Dismisses the explanation and triggers the system "When In Use" dialog.
    func confirmWhenInUseRequest() {
        showWhenInUseExplanation = false
        logger.info("User confirmed — triggering system 'When In Use' authorization request")
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Public API — Step 2: Always

    /// Initiates Step 2 of the permission flow.
    ///
    /// Shows a custom explanation sheet explaining the background location
    /// benefit (geofence alerts even when the app is closed).
    ///
    /// - Important: Only call this AFTER the user has added their first DVG
    ///   with a store location and `authorizationState == .whenInUse`.
    func requestAlwaysPermission() {
        guard authorizationState == .whenInUse else {
            logger.warning("requestAlwaysPermission called but state is \(String(describing: self.authorizationState)) — requires .whenInUse")
            return
        }
        logger.info("Presenting 'Always' explanation sheet")
        showAlwaysExplanation = true
    }

    /// Called when the user taps "Allow" on the custom "Always" explanation sheet.
    ///
    /// Dismisses the explanation and triggers the system "Always" upgrade dialog.
    func confirmAlwaysRequest() {
        showAlwaysExplanation = false
        logger.info("User confirmed — triggering system 'Always' authorization request")
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Public API — Settings Deep Link

    /// Opens the app's Location settings page in the iOS Settings app.
    ///
    /// Use this when `authorizationState == .denied` so the user can manually
    /// grant permission.
    func openLocationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in
            await UIApplication.shared.open(settingsURL)
        }
    }

    // MARK: - Current Location

    /// The most recent location reported by the underlying `CLLocationManager`.
    ///
    /// Returns `nil` if the manager has not yet received a location update
    /// (e.g. authorization was recently granted). Callers should guard against
    /// `nil` and treat it as "location unavailable".
    var currentCLLocation: CLLocation? {
        locationManager.location
    }

    // MARK: - Private Helpers

    /// Maps `CLAuthorizationStatus` to the app-level `LocationAuthorizationState`.
    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined:       return .notDetermined
        case .restricted:          return .restricted
        case .denied:              return .denied
        case .authorizedWhenInUse: return .whenInUse
        case .authorizedAlways:    return .always
        @unknown default:          return .notDetermined
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationPermissionManager: CLLocationManagerDelegate {

    /// Called on any authorization status change.
    ///
    /// `nonisolated` because `CLLocationManagerDelegate` is not bound to
    /// `@MainActor`. The status update hops back to the main actor via a
    /// `Task { @MainActor }` trampoline.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Capture status synchronously on the delegate thread before hopping.
        let newStatus = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            let newState = Self.map(newStatus)
            logger.info("Authorization changed: \(String(describing: newState))")
            authorizationState = newState
        }
    }
}

// MARK: - UIApplication Import

// Import UIKit here for `UIApplication.openSettingsURLString`.
// Using a conditional import keeps the file compatible with app extensions
// that do not link UIKit (the manager itself should not be included in extensions).
import UIKit
