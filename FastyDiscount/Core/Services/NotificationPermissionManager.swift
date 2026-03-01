import Foundation
import UserNotifications

// MARK: - NotificationPermissionManager Protocol

/// Abstracts notification-permission requests so the concrete strategy can
/// be swapped (e.g. for testing).
///
/// Implementations must be `Sendable` (called from actor-isolated contexts).
///
/// Note: implementations obtain `UNUserNotificationCenter.current()` internally
/// rather than accepting it as a parameter. This avoids Swift 6 data-race
/// diagnostics from sending the `UNUserNotificationCenter` reference across
/// actor isolation boundaries.
protocol NotificationPermissionManager: Sendable {

    /// Requests authorisation if it has not been determined yet.
    ///
    /// - Returns: `true` if the app is authorised to display notifications
    ///   after this call (whether newly granted or previously granted).
    func requestIfNeeded() async -> Bool
}

// MARK: - DefaultNotificationPermissionManager

/// Production implementation that uses `UNUserNotificationCenter` to request
/// notification authorisation the first time it is needed.
///
/// The strategy is **deferred**: we do NOT request permission at launch.
/// Permission is only requested when the first DVG with an expiration date
/// is saved (triggered from `schedule(for:)`).
///
/// This struct is `Sendable` because it contains no mutable stored state.
struct DefaultNotificationPermissionManager: NotificationPermissionManager {

    // MARK: - NotificationPermissionManager

    func requestIfNeeded() async -> Bool {
        // Obtain the shared centre on this call. `UNUserNotificationCenter.current()`
        // is safe to call from any context; we do NOT store it as an instance
        // property to avoid Sendable crossing issues.
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            // Already granted — proceed without asking again.
            return true

        case .notDetermined:
            // First time: request permission. We ask for .alert, .sound, and .badge.
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted
            } catch {
                // e.g. the app is not entitled to send notifications
                print("[NotificationPermissionManager] Permission request failed: \(error)")
                return false
            }

        case .denied:
            // User explicitly denied. Respect the decision; do not re-prompt.
            return false

        @unknown default:
            return false
        }
    }
}
