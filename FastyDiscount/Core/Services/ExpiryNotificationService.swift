import Foundation
import UserNotifications

// MARK: - ExpiryNotificationService Protocol

/// Service responsible for scheduling, cancelling, and rescheduling expiry
/// reminder notifications for DVG items.
///
/// Implementations must be `Sendable` for Swift 6 strict concurrency.
protocol ExpiryNotificationService: Sendable {

    /// Schedules an expiry notification for the given DVG.
    ///
    /// No-ops if:
    /// - The DVG has no expiration date.
    /// - `notificationLeadDays` is 0.
    /// - The computed notification date is in the past.
    /// - Global notifications are disabled in UserDefaults.
    ///
    /// Requests notification permission if it has not yet been granted,
    /// but only when the DVG has an expiration date (deferred permission).
    ///
    /// - Parameter dvg: The item for which to schedule a reminder.
    func schedule(for dvg: DVGSnapshot) async

    /// Cancels any pending expiry notification for the given DVG.
    ///
    /// Uses the deterministic identifier `expiry-{dvg.id}` to locate
    /// the pending notification without needing to track state.
    ///
    /// - Parameter dvgID: The stable UUID of the DVG whose notification should be removed.
    func cancel(for dvgID: UUID) async

    /// Removes all `expiry-*` pending notifications and reschedules fresh
    /// ones for every active DVG that has an expiration date.
    ///
    /// Use this on app launch to recover from clock changes or missed
    /// rescheduling events, and when the user changes global notification settings.
    ///
    /// - Parameter activeDVGs: All active DVGs returned by the repository.
    func rescheduleAll(activeDVGs: [DVGSnapshot]) async
}

// MARK: - DVGSnapshot

/// A `Sendable` value-type snapshot of the notification-relevant fields of a DVG.
///
/// `DVG` is a SwiftData `@Model` class confined to `@MainActor`. By extracting
/// only the data needed for scheduling into this struct we can safely pass
/// values across actor boundaries without violating Swift 6 strict concurrency.
struct DVGSnapshot: Sendable {
    let id: UUID
    let title: String
    let storeName: String
    let expirationDate: Date?
    let notificationLeadDays: Int
    let statusEnum: DVGStatus
    let isDeleted: Bool

    /// Creates a snapshot from a live DVG model object.
    ///
    /// Must be called on `@MainActor` (where `DVG` lives).
    @MainActor
    init(dvg: DVG) {
        self.id = dvg.id
        self.title = dvg.title
        self.storeName = dvg.storeName
        self.expirationDate = dvg.expirationDate
        self.notificationLeadDays = dvg.notificationLeadDays
        self.statusEnum = dvg.statusEnum
        self.isDeleted = dvg.isDeleted
    }

    /// Creates a snapshot from individual value-type fields.
    ///
    /// Unlike `init(dvg:)`, this initialiser is nonisolated because it does
    /// not access the `@MainActor`-confined `DVG` model object. Use this when
    /// you already have the individual field values (e.g. in tests or when
    /// constructing snapshots across actor boundaries).
    init(
        id: UUID,
        title: String,
        storeName: String,
        expirationDate: Date?,
        notificationLeadDays: Int,
        statusEnum: DVGStatus,
        isDeleted: Bool
    ) {
        self.id = id
        self.title = title
        self.storeName = storeName
        self.expirationDate = expirationDate
        self.notificationLeadDays = notificationLeadDays
        self.statusEnum = statusEnum
        self.isDeleted = isDeleted
    }
}

// MARK: - UNExpiryNotificationService

/// Concrete implementation of `ExpiryNotificationService` backed by
/// `UNUserNotificationCenter`.
///
/// ### Concurrency
/// This actor does NOT store `UNUserNotificationCenter` as an instance property.
/// Instead each method calls `UNUserNotificationCenter.current()` locally.
/// This satisfies Swift 6 strict concurrency: `UNUserNotificationCenter` is not
/// `Sendable`, so we must not pass it across actor isolation boundaries.
///
/// ### 64-Notification Limit
/// iOS limits pending local notifications to 64. `rescheduleAll` sorts by
/// soonest expiry and schedules at most 64 entries.
actor UNExpiryNotificationService: ExpiryNotificationService {

    // MARK: - Constants

    /// Category identifier registered early at app start (TASK-022 adds action buttons).
    static let categoryIdentifier = "dvg-expiry"

    /// Prefix for all notification identifiers managed by this service.
    static let identifierPrefix = "expiry-"

    /// UserDefaults key for the global notifications-enabled toggle.
    static let notificationsEnabledKey = "notificationsEnabled"

    /// Maximum number of pending local notifications iOS allows.
    static let maxPendingNotifications = 64

    /// Hour of day (24-hour clock) at which the notification fires.
    static let defaultNotificationHour = 9

    // MARK: - Dependencies

    /// Permission manager handles the one-time system prompt.
    private let permissionManager: any NotificationPermissionManager

    // MARK: - Init

    /// Creates the service with real or injected dependencies.
    ///
    /// - Parameter permissionManager: Defaults to a `DefaultNotificationPermissionManager`.
    init(permissionManager: any NotificationPermissionManager = DefaultNotificationPermissionManager()) {
        self.permissionManager = permissionManager
    }

    // MARK: - ExpiryNotificationService

    func schedule(for dvg: DVGSnapshot) async {
        guard isNotificationsGloballyEnabled() else { return }
        guard let notificationDate = computeNotificationDate(for: dvg) else { return }

        // Skip if the notification date is already in the past
        guard notificationDate > Date() else { return }

        // Request permission if needed (deferred: only when we actually have something to schedule)
        let granted = await permissionManager.requestIfNeeded()
        guard granted else { return }

        let request = buildNotificationRequest(dvg: dvg, notificationDate: notificationDate)
        let center = UNUserNotificationCenter.current()

        do {
            try await center.add(request)
        } catch {
            // Non-fatal: log and continue. Permission may have been revoked.
            print("[ExpiryNotificationService] Failed to schedule notification for \(dvg.id): \(error)")
        }
    }

    func cancel(for dvgID: UUID) async {
        let identifier = notificationIdentifier(for: dvgID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func rescheduleAll(activeDVGs: [DVGSnapshot]) async {
        // Remove all pending expiry-* notifications
        await removeAllExpiryNotifications()

        guard isNotificationsGloballyEnabled() else { return }
        guard !activeDVGs.isEmpty else { return }

        // Filter to DVGs that actually need a notification
        let now = Date()
        let schedulable = activeDVGs
            .filter { dvg in
                guard !dvg.isDeleted else { return false }
                guard dvg.statusEnum == .active else { return false }
                guard let date = computeNotificationDate(for: dvg) else { return false }
                return date > now
            }
            // Sort by soonest expiry to prioritise within the 64-item limit
            .sorted { lhs, rhs in
                switch (lhs.expirationDate, rhs.expirationDate) {
                case (.some(let l), .some(let r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }
            .prefix(Self.maxPendingNotifications)

        guard !schedulable.isEmpty else { return }

        // Request permission once before batch scheduling
        let granted = await permissionManager.requestIfNeeded()
        guard granted else { return }

        let center = UNUserNotificationCenter.current()

        for dvg in schedulable {
            guard let notificationDate = computeNotificationDate(for: dvg) else { continue }
            guard notificationDate > now else { continue }

            let request = buildNotificationRequest(dvg: dvg, notificationDate: notificationDate)
            do {
                try await center.add(request)
            } catch {
                print("[ExpiryNotificationService] Failed to schedule during rescheduleAll for \(dvg.id): \(error)")
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns the deterministic notification identifier for a DVG ID.
    private func notificationIdentifier(for dvgID: UUID) -> String {
        "\(Self.identifierPrefix)\(dvgID.uuidString)"
    }

    /// Returns `true` if the global notifications-enabled flag is set (default true).
    ///
    /// Marked `nonisolated` so it can be called without an actor hop.
    /// `UserDefaults.standard` is safe to access from any context.
    nonisolated private func isNotificationsGloballyEnabled() -> Bool {
        // When the key has never been set, UserDefaults.standard.bool returns false.
        // We treat absence as enabled (default true).
        if UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.notificationsEnabledKey)
    }

    /// Computes the target date/time for the notification trigger.
    ///
    /// Returns `nil` when:
    /// - There is no expiration date.
    /// - `notificationLeadDays` is 0 (opt-out).
    /// - The calendar subtraction fails.
    private func computeNotificationDate(for dvg: DVGSnapshot) -> Date? {
        guard let expirationDate = dvg.expirationDate else { return nil }
        guard dvg.notificationLeadDays > 0 else { return nil }

        let calendar = Calendar.current

        // Step 1: subtract lead days from the expiry date
        guard let leadDate = calendar.date(
            byAdding: .day,
            value: -dvg.notificationLeadDays,
            to: expirationDate
        ) else { return nil }

        // Step 2: pin to 9:00 AM on that day
        var components = calendar.dateComponents([.year, .month, .day], from: leadDate)
        components.hour = Self.defaultNotificationHour
        components.minute = 0
        components.second = 0

        return calendar.date(from: components)
    }

    /// Builds a `UNNotificationRequest` for the given DVG.
    private func buildNotificationRequest(
        dvg: DVGSnapshot,
        notificationDate: Date
    ) -> UNNotificationRequest {
        let content = buildContent(dvg: dvg, notificationDate: notificationDate)
        let trigger = buildTrigger(from: notificationDate)
        let identifier = notificationIdentifier(for: dvg.id)

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }

    /// Assembles the `UNMutableNotificationContent` for a DVG notification.
    private func buildContent(dvg: DVGSnapshot, notificationDate: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "DVG Expiring Soon"
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        content.userInfo["dvgID"] = dvg.id.uuidString

        // Build body: calculate days remaining relative to expirationDate at notification fire time
        let daysRemaining: Int
        if let expirationDate = dvg.expirationDate {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: notificationDate, to: expirationDate)
            daysRemaining = max(components.day ?? dvg.notificationLeadDays, 0)
        } else {
            daysRemaining = dvg.notificationLeadDays
        }

        let storePart = dvg.storeName.isEmpty ? "" : " at \(dvg.storeName)"
        let titlePart = dvg.title.isEmpty ? "Your DVG" : dvg.title
        content.body = "\(titlePart)\(storePart) expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")"

        return content
    }

    /// Creates a `UNCalendarNotificationTrigger` from the target `Date`.
    private func buildTrigger(from date: Date) -> UNCalendarNotificationTrigger {
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    /// Removes all pending notifications whose identifier starts with `expiry-`.
    private func removeAllExpiryNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let expiryIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }

        guard !expiryIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: expiryIDs)
    }
}

// MARK: - NotificationActionIdentifier

/// String constants for notification action identifiers used across
/// both `dvg-expiry` and `dvg-location` notification categories.
///
/// Defined here (in `ExpiryNotificationService.swift`) so they are available
/// to all targets that compile this file (main app, widget, share extension).
enum NotificationActionIdentifier {
    /// Opens the app and navigates to the DVG detail view.
    static let viewCode = "view-code"
    /// Marks the DVG as used without bringing the app to the foreground.
    static let markUsed = "mark-used"
    /// Reschedules the notification for 24 hours later.
    static let snooze   = "snooze"
}

// MARK: - NotificationCategoryRegistrar

/// Registers `UNNotificationCategory` entries for DVG notifications.
///
/// Two categories are registered:
/// - `dvg-expiry`: Fired when a DVG is approaching its expiration date.
/// - `dvg-location`: Fired when the user enters the geofence of a store.
///
/// Both categories share the same three action buttons:
/// - **View Code** (`view-code`): foreground action — opens the app and navigates
///   to the DVG detail view.
/// - **Mark as Used** (`mark-used`): background action — updates DVG status to
///   `.used` without bringing the app to the foreground.
/// - **Snooze** (`snooze`): background action — reschedules the notification
///   for 24 hours later.
///
/// Call `registerCategories()` before the first notification can arrive
/// (i.e. during `FastyDiscountApp.init()` or as early as possible at launch).
/// Safe to call multiple times — later registrations replace earlier ones.
enum NotificationCategoryRegistrar {

    /// Location-based notification category identifier.
    static let locationCategoryIdentifier = "dvg-location"

    /// Registers both `dvg-expiry` and `dvg-location` categories with
    /// `UNUserNotificationCenter`, including their shared action buttons.
    ///
    /// Call this during app startup (e.g. in `FastyDiscountApp.init()`).
    @MainActor
    static func registerCategories() {
        // MARK: Shared Actions

        // "View Code" — foreground action: tapping this will bring the app to
        // the front and navigate to the DVG detail view.
        let viewCodeAction = UNNotificationAction(
            identifier: NotificationActionIdentifier.viewCode,
            title: "View Code",
            options: [.foreground]
        )

        // "Mark as Used" — background action: the DVG is updated in SwiftData
        // without the app being brought to the foreground.
        let markUsedAction = UNNotificationAction(
            identifier: NotificationActionIdentifier.markUsed,
            title: "Mark as Used",
            options: []
        )

        // "Snooze" — background action: cancels the current notification and
        // reschedules it for 24 hours later.
        let snoozeAction = UNNotificationAction(
            identifier: NotificationActionIdentifier.snooze,
            title: "Snooze",
            options: []
        )

        let sharedActions = [viewCodeAction, markUsedAction, snoozeAction]

        // MARK: Expiry Category

        let expiryCategory = UNNotificationCategory(
            identifier: UNExpiryNotificationService.categoryIdentifier,
            actions: sharedActions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // MARK: Location Category

        let locationCategory = UNNotificationCategory(
            identifier: locationCategoryIdentifier,
            actions: sharedActions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([expiryCategory, locationCategory])
    }
}
