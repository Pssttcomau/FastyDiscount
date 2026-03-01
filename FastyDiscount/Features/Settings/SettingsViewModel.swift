import Foundation
import CloudKit
import UserNotifications

// MARK: - CloudKitSyncStatus

/// Represents the CloudKit account / sync status shown in the Account section.
enum CloudKitSyncStatus: Equatable {
    case unknown
    case available
    case syncing
    case error(String)

    var label: String {
        switch self {
        case .unknown:        return "Checking..."
        case .available:      return "Synced"
        case .syncing:        return "Syncing..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:  return "icloud"
        case .available: return "checkmark.icloud"
        case .syncing:  return "arrow.clockwise.icloud"
        case .error:    return "xmark.icloud"
        }
    }
}

// MARK: - NotificationSystemStatus

/// Represents the current system-level notification authorization status.
enum NotificationSystemStatus: Equatable {
    case unknown
    case authorized
    case denied
}

// MARK: - SettingsViewModel

/// View model managing all settings state for the Settings tab.
///
/// Settings are persisted in UserDefaults except the API key, which is stored
/// with a TODO noting it should use Keychain in production.
///
/// - Note: API key is stored in UserDefaults for now.
///   TODO: Move API key to Keychain in production for security.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let expiryNotificationsEnabled = "expiryNotificationsEnabled"
        static let locationNotificationsEnabled = "locationNotificationsEnabled"
        static let geofencingEnabled = "geofencingEnabled"
        static let defaultGeofenceRadius = "defaultGeofenceRadius"
        // TODO: Move aiProviderKey to Keychain in production
        static let aiProviderKey = "aiProviderKey"
        static let parseCount = "anthropicParseCount"
    }

    // MARK: - Account

    /// Whether the user is signed in with Apple.
    private(set) var isSignedIn: Bool = false

    /// The CloudKit sync status.
    private(set) var cloudKitStatus: CloudKitSyncStatus = .unknown

    // MARK: - Email (Gmail)

    /// Whether Gmail is currently connected.
    private(set) var isGmailConnected: Bool = false

    /// Whether a Gmail connection/disconnection operation is in progress.
    private(set) var isGmailOperationInProgress: Bool = false

    /// Error message from Gmail operations, if any.
    var gmailErrorMessage: String? = nil

    // MARK: - Notifications

    /// The system-level notification authorization status.
    private(set) var notificationSystemStatus: NotificationSystemStatus = .unknown

    /// Global notifications toggle. Persisted to UserDefaults.
    var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.notificationsEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    /// Expiry reminder notifications toggle. Persisted to UserDefaults.
    var expiryNotificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.expiryNotificationsEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.expiryNotificationsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.expiryNotificationsEnabled) }
    }

    /// Location (geofence) notifications toggle. Persisted to UserDefaults.
    var locationNotificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.locationNotificationsEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.locationNotificationsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.locationNotificationsEnabled) }
    }

    // MARK: - Location

    /// Whether geofencing is enabled. Persisted to UserDefaults.
    var geofencingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.geofencingEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.geofencingEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.geofencingEnabled) }
    }

    /// Default geofence radius in metres (100m–1000m). Persisted to UserDefaults.
    var defaultGeofenceRadius: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.defaultGeofenceRadius)
            return stored > 0 ? stored : 300
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.defaultGeofenceRadius) }
    }

    // MARK: - AI (Anthropic only)

    /// The Anthropic API key.
    ///
    /// TODO: Move this to Keychain in production for security.
    /// Currently stored in UserDefaults for simplicity during development.
    var anthropicAPIKey: String {
        get { UserDefaults.standard.string(forKey: Keys.aiProviderKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.aiProviderKey) }
    }

    /// Whether the API key secure field is revealed.
    var isAPIKeyRevealed: Bool = false

    /// Number of AI parses performed. Read-only counter from UserDefaults.
    var parseCount: Int {
        UserDefaults.standard.integer(forKey: Keys.parseCount)
    }

    // MARK: - Appearance (managed externally by AppearanceManager)
    // The AppearanceManager is injected via environment — no duplication here.

    // MARK: - Dependencies

    private let gmailAuthService: any GmailAuthService

    // MARK: - Init

    init(gmailAuthService: any GmailAuthService = GoogleGmailAuthService()) {
        self.gmailAuthService = gmailAuthService
    }

    // MARK: - Lifecycle

    /// Called when the Settings view appears to refresh all status values.
    func onAppear() async {
        await refreshAuthStatus()
        await refreshCloudKitStatus()
        refreshGmailStatus()
        await refreshNotificationStatus()
    }

    // MARK: - Account Actions

    /// Signs the user out via the provided sign-out closure.
    func signOut(using signOutAction: @escaping () async -> Void) async {
        await signOutAction()
        isSignedIn = false
    }

    // MARK: - Gmail Actions

    /// Connects the Gmail account.
    func connectGmail() async {
        guard !isGmailOperationInProgress else { return }
        isGmailOperationInProgress = true
        gmailErrorMessage = nil

        do {
            try await gmailAuthService.authenticate()
            isGmailConnected = true
        } catch GmailAuthError.userCancelled {
            // User cancelled — not an error
        } catch {
            gmailErrorMessage = error.localizedDescription
        }

        isGmailOperationInProgress = false
    }

    /// Disconnects the Gmail account.
    func disconnectGmail() async {
        guard !isGmailOperationInProgress else { return }
        isGmailOperationInProgress = true
        gmailErrorMessage = nil

        do {
            try await gmailAuthService.disconnect()
            isGmailConnected = false
        } catch {
            gmailErrorMessage = error.localizedDescription
        }

        isGmailOperationInProgress = false
    }

    // MARK: - Private: Status Refresh

    private func refreshAuthStatus() async {
        // Check Apple Sign-In credential state
        // We rely on AppState.isOnboardingComplete as a proxy here;
        // in practice the AuthViewModel owns the true auth state.
        // Set isSignedIn from the keychain if user identifier exists.
        let keychainService = KeychainService()
        let userID = try? keychainService.read(forKey: "apple.user.identifier")
        isSignedIn = (userID != nil && !(userID?.isEmpty ?? true))
    }

    private func refreshCloudKitStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                cloudKitStatus = .available
            case .noAccount:
                cloudKitStatus = .error("No iCloud account")
            case .restricted:
                cloudKitStatus = .error("Restricted")
            case .couldNotDetermine:
                cloudKitStatus = .error("Could not determine")
            case .temporarilyUnavailable:
                cloudKitStatus = .error("Temporarily unavailable")
            @unknown default:
                cloudKitStatus = .unknown
            }
        } catch {
            cloudKitStatus = .error(error.localizedDescription)
        }
    }

    private func refreshGmailStatus() {
        isGmailConnected = gmailAuthService.isAuthenticated
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationSystemStatus = .authorized
        case .denied:
            notificationSystemStatus = .denied
        case .notDetermined:
            notificationSystemStatus = .unknown
        @unknown default:
            notificationSystemStatus = .unknown
        }
    }
}
