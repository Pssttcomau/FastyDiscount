import Foundation
import UIKit
import UserNotifications
import SwiftData

// MARK: - NotificationActionHandler

/// Handles `UNUserNotificationCenter` delegate callbacks for the app.
///
/// This object acts as the `UNUserNotificationCenterDelegate`. It routes
/// notification action responses to the appropriate handler:
///
/// - **View Code** (`view-code`): opens the app and navigates to the DVG detail
///   view via a `fastydiscount://dvg/{uuid}` deep link.
/// - **Mark as Used** (`mark-used`): marks the DVG status as `.used` in SwiftData
///   without bringing the app to the foreground.
/// - **Snooze** (`snooze`): cancels the current notification and reschedules it
///   for 24 hours later.
///
/// ### Concurrency
/// `UNUserNotificationCenterDelegate` callbacks arrive on an arbitrary queue.
/// All SwiftData and NavigationRouter access is dispatched to `@MainActor`.
/// The `ModelContainer` reference is captured at init and is `Sendable`.
///
/// ### Lifecycle
/// Create one instance and assign it to
/// `UNUserNotificationCenter.current().delegate` in the app's `init()`,
/// before the first notification can arrive.
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Properties

    /// The model container used to access SwiftData for background actions.
    /// Captured at app startup; safe to reference from any actor context.
    private let modelContainer: ModelContainer

    // MARK: - Init

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when the user taps a notification or one of its action buttons.
    ///
    /// Routes the response to the appropriate action handler based on
    /// `response.actionIdentifier`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // Extract only Sendable values from userInfo before crossing the actor boundary.
        // [AnyHashable: Any] is not Sendable; extracting the dvgID string (which is
        // Sendable) keeps Swift 6 strict concurrency happy.
        let dvgIDString = response.notification.request.content.userInfo["dvgID"] as? String
        let actionIdentifier = response.actionIdentifier

        Task { @MainActor in
            await self.handleAction(actionIdentifier, dvgIDString: dvgIDString)
            completionHandler()
        }
    }

    /// Called when a notification is delivered while the app is in the foreground.
    ///
    /// Presents the notification banner with badge, sound, and list style so that
    /// the user can see and interact with it even when the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    // MARK: - Action Routing

    /// Dispatches the incoming notification action to its handler.
    ///
    /// - Parameters:
    ///   - actionIdentifier: The `UNNotificationResponse.actionIdentifier`.
    ///   - dvgIDString: The DVG UUID string extracted from the notification's `userInfo`.
    @MainActor
    private func handleAction(_ actionIdentifier: String, dvgIDString: String?) async {
        switch actionIdentifier {
        case NotificationActionIdentifier.viewCode:
            await handleViewCode(dvgIDString: dvgIDString)

        case NotificationActionIdentifier.markUsed:
            await handleMarkUsed(dvgIDString: dvgIDString)

        case NotificationActionIdentifier.snooze:
            await handleSnooze(dvgIDString: dvgIDString)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body (no specific action button).
            // Treat this as "View Code": open the app and navigate to the detail.
            await handleViewCode(dvgIDString: dvgIDString)

        default:
            // Unknown action — no-op.
            break
        }
    }

    // MARK: - View Code Handler

    /// Opens the app at the DVG detail view using a deep link URL.
    ///
    /// Constructs a `fastydiscount://dvg/{uuid}` URL and opens it via
    /// `UIApplication.open(_:)`. The existing `ContentView.onOpenURL` handler
    /// and `NavigationRouter.handleDeepLink(_:)` resolve the navigation.
    @MainActor
    private func handleViewCode(dvgIDString: String?) async {
        guard let dvgIDString else {
            print("[NotificationActionHandler] view-code: missing dvgID in userInfo")
            return
        }

        let urlString = "\(AppConstants.DeepLink.scheme)://\(AppConstants.DeepLink.dvgPath)/\(dvgIDString)"
        guard let url = URL(string: urlString) else {
            print("[NotificationActionHandler] view-code: could not construct URL from dvgID \(dvgIDString)")
            return
        }

        await UIApplication.shared.open(url)
    }

    // MARK: - Mark as Used Handler

    /// Marks the DVG as used in SwiftData without opening the app.
    ///
    /// Works even when the app was terminated (background handler). Uses
    /// `modelContainer.mainContext` directly, consistent with the repository
    /// pattern used elsewhere in the app.
    @MainActor
    private func handleMarkUsed(dvgIDString: String?) async {
        guard
            let dvgIDString,
            let dvgID = UUID(uuidString: dvgIDString)
        else {
            print("[NotificationActionHandler] mark-used: missing or invalid dvgID in userInfo")
            return
        }

        let context = modelContainer.mainContext
        let repository = SwiftDataDVGRepository(modelContext: context)

        do {
            // Fetch the DVG by ID
            let descriptor = FetchDescriptor<DVG>(
                predicate: #Predicate<DVG> { $0.id == dvgID && $0.isDeleted == false }
            )
            guard let dvg = try context.fetch(descriptor).first else {
                print("[NotificationActionHandler] mark-used: DVG \(dvgID) not found")
                return
            }

            try await repository.markAsUsed(dvg)
            print("[NotificationActionHandler] mark-used: DVG \(dvgID) marked as used")
        } catch {
            print("[NotificationActionHandler] mark-used: failed for DVG \(dvgID): \(error)")
        }
    }

    // MARK: - Snooze Handler

    /// Cancels the current pending notification and reschedules it for 24 hours later.
    ///
    /// Uses a `UNTimeIntervalNotificationTrigger` (24 hours) rather than a
    /// `UNCalendarNotificationTrigger` so the snooze always fires ~24 hours from now,
    /// regardless of the original scheduled time.
    @MainActor
    private func handleSnooze(dvgIDString: String?) async {
        guard
            let dvgIDString,
            let dvgID = UUID(uuidString: dvgIDString)
        else {
            print("[NotificationActionHandler] snooze: missing or invalid dvgID in userInfo")
            return
        }

        let center = UNUserNotificationCenter.current()

        // Cancel the existing expiry notification for this DVG
        let existingIdentifier = "\(UNExpiryNotificationService.identifierPrefix)\(dvgID.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [existingIdentifier])

        // Build a snoozed notification with the same content
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> { $0.id == dvgID && $0.isDeleted == false }
        )

        guard let dvg = try? context.fetch(descriptor).first else {
            print("[NotificationActionHandler] snooze: DVG \(dvgID) not found — cannot reschedule")
            return
        }

        // Reuse the same content structure as the original notification
        let content = UNMutableNotificationContent()
        content.title = "DVG Expiring Soon (Snoozed)"
        content.categoryIdentifier = UNExpiryNotificationService.categoryIdentifier
        content.sound = .default
        content.userInfo["dvgID"] = dvgID.uuidString

        let storePart = dvg.storeName.isEmpty ? "" : " at \(dvg.storeName)"
        let titlePart = dvg.title.isEmpty ? "Your DVG" : dvg.title
        content.body = "\(titlePart)\(storePart) — snoozed reminder"

        // Use a snoozed identifier so it does not conflict with the original
        let snoozeIdentifier = "snooze-\(dvgID.uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 86_400, repeats: false)
        let request = UNNotificationRequest(
            identifier: snoozeIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("[NotificationActionHandler] snooze: rescheduled DVG \(dvgID) for +24h")
        } catch {
            print("[NotificationActionHandler] snooze: failed to reschedule DVG \(dvgID): \(error)")
        }
    }
}
