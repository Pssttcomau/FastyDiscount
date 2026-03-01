import SwiftData
import Foundation

// MARK: - Placeholder Model

/// Placeholder model used to verify container setup.
/// Real @Model classes will be defined in TASK-007/008.
/// CloudKit compatibility rules are enforced:
///   - No unique constraints (client-side dedup only)
///   - All relationships optional
///   - Default values for all non-optional properties
///   - Soft-delete via `isDeleted` flag
@Model
final class PlaceholderItem {
    var id: UUID
    var createdAt: Date
    var isDeleted: Bool

    init(id: UUID = UUID(), createdAt: Date = Date(), isDeleted: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.isDeleted = isDeleted
    }
}

// MARK: - ModelContainerFactory

/// Shared factory that creates a `ModelContainer` configured with:
/// - App Group shared container URL (accessible by main app, widget, and share extension)
/// - CloudKit sync via `.cloudKitDatabase(.automatic)` — uses server-wins conflict resolution
///   by default when CloudKit sync is active.
/// - Lightweight read-only variant for widget and share extension targets.
///
/// Usage:
/// ```swift
/// // Main app (read-write + CloudKit sync)
/// let container = try ModelContainerFactory.makeContainer()
///
/// // Widget / Share Extension (read-only, no CloudKit sync)
/// let container = try ModelContainerFactory.makeReadOnlyContainer()
/// ```
enum ModelContainerFactory {

    /// The SwiftData schema used across all targets.
    static let schema = Schema([PlaceholderItem.self])

    // MARK: - Main Container (CloudKit sync enabled)

    /// Returns a fully configured `ModelContainer` with CloudKit sync.
    ///
    /// - Note: CloudKit requires the user to be signed into iCloud. If the device is
    ///   not signed in, CloudKit sync will be silently skipped but the local store
    ///   remains operational.
    /// - Note: Server-wins merge policy is the CloudKit default when using
    ///   `.cloudKitDatabase(.automatic)`. No additional configuration is needed.
    /// - Throws: `ModelContainerFactory.ContainerError` if the container cannot be created.
    static func makeContainer() throws -> ModelContainer {
        let storeURL = try sharedStoreURL()

        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: configuration
            )
        } catch {
            throw ContainerError.storeCreationFailed(error)
        }
    }

    // MARK: - Read-Only Container (for widget / share extension)

    /// Returns a lightweight read-only `ModelContainer` suitable for extensions.
    ///
    /// Extensions read from the same shared App Group store file but do not
    /// participate in CloudKit sync, reducing memory pressure and avoiding
    /// write conflicts.
    ///
    /// - Throws: `ModelContainerFactory.ContainerError` if the container cannot be created.
    static func makeReadOnlyContainer() throws -> ModelContainer {
        let storeURL = try sharedStoreURL()

        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: false
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: configuration
            )
        } catch {
            throw ContainerError.storeCreationFailed(error)
        }
    }

    // MARK: - Shared Store URL

    /// Resolves the SQLite store URL inside the App Group shared container.
    static func sharedStoreURL() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) else {
            throw ContainerError.appGroupContainerNotFound(AppConstants.appGroupIdentifier)
        }

        return containerURL.appending(
            path: "FastyDiscount.sqlite",
            directoryHint: .notDirectory
        )
    }

    // MARK: - Error

    enum ContainerError: LocalizedError, Sendable {
        case appGroupContainerNotFound(String)
        case iCloudNotAvailable
        case storeCreationFailed(any Error)

        var errorDescription: String? {
            switch self {
            case .appGroupContainerNotFound(let id):
                return "App Group container '\(id)' could not be resolved. Ensure entitlements are configured correctly."
            case .iCloudNotAvailable:
                return "iCloud is not available. Sign in to iCloud in Settings to enable sync."
            case .storeCreationFailed(let underlying):
                return "Failed to create data store: \(underlying.localizedDescription)"
            }
        }

        var failureReason: String? {
            switch self {
            case .appGroupContainerNotFound:
                return "The App Group entitlement may be missing or the group ID is incorrect."
            case .iCloudNotAvailable:
                return "The user is not signed in to iCloud."
            case .storeCreationFailed(let underlying):
                return underlying.localizedDescription
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .appGroupContainerNotFound:
                return "Check that com.apple.security.application-groups is set to '\(AppConstants.appGroupIdentifier)' in entitlements."
            case .iCloudNotAvailable:
                return "Go to Settings > [Your Name] and sign in to iCloud."
            case .storeCreationFailed:
                return "Try restarting the app. If the problem persists, reinstalling may help."
            }
        }
    }
}
