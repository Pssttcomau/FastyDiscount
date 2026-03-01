import Foundation
import SwiftData
import CoreLocation
import UserNotifications

// MARK: - DVGRepositoryError

/// Typed errors thrown by `DVGRepository` operations.
enum DVGRepositoryError: LocalizedError, Sendable {
    case notFound(UUID)
    case fetchFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
    case invalidBalance(Double)
    case contextUnavailable

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "DVG item with ID \(id) was not found."
        case .fetchFailed(let detail):
            return "Failed to fetch DVG items: \(detail)"
        case .saveFailed(let detail):
            return "Failed to save DVG item: \(detail)"
        case .deleteFailed(let detail):
            return "Failed to delete DVG item: \(detail)"
        case .invalidBalance(let value):
            return "Invalid balance value: \(value). Balance must be non-negative."
        case .contextUnavailable:
            return "The model context is not available."
        }
    }
}

// MARK: - DVGSortOrder

/// Sort options for DVG queries.
enum DVGSortOrder: String, Sendable, CaseIterable {
    case expiryDateAscending
    case expiryDateDescending
    case valueDescending
    case valueAscending
    case dateAddedNewest
    case dateAddedOldest
    case alphabeticalAZ
    case alphabeticalZA

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .expiryDateAscending:   return "Expiry (Soonest First)"
        case .expiryDateDescending:  return "Expiry (Latest First)"
        case .valueDescending:       return "Value (Highest First)"
        case .valueAscending:        return "Value (Lowest First)"
        case .dateAddedNewest:       return "Date Added (Newest First)"
        case .dateAddedOldest:       return "Date Added (Oldest First)"
        case .alphabeticalAZ:        return "A - Z"
        case .alphabeticalZA:        return "Z - A"
        }
    }
}

// MARK: - DVGFilter

/// Encapsulates all filter parameters for the `search` method.
///
/// All filter fields are optional. When `nil`, the corresponding filter
/// is not applied (AND semantics: all non-nil filters must match).
struct DVGFilter: Sendable {
    /// Filter by DVG type.
    var type: DVGType?
    /// Filter by status.
    var status: DVGStatus?
    /// Filter by tag name.
    var tagName: String?
    /// Filter to items expiring on or after this date.
    var expiryDateFrom: Date?
    /// Filter to items expiring on or before this date.
    var expiryDateTo: Date?
    /// Include only favourites.
    var isFavoriteOnly: Bool = false

    /// Returns `true` when no filters are active.
    var isEmpty: Bool {
        type == nil
        && status == nil
        && tagName == nil
        && expiryDateFrom == nil
        && expiryDateTo == nil
        && !isFavoriteOnly
    }

    init(
        type: DVGType? = nil,
        status: DVGStatus? = nil,
        tagName: String? = nil,
        expiryDateFrom: Date? = nil,
        expiryDateTo: Date? = nil,
        isFavoriteOnly: Bool = false
    ) {
        self.type = type
        self.status = status
        self.tagName = tagName
        self.expiryDateFrom = expiryDateFrom
        self.expiryDateTo = expiryDateTo
        self.isFavoriteOnly = isFavoriteOnly
    }
}

// MARK: - SaveResult

/// Result of a `save` operation, carrying deduplication information.
enum SaveResult: Sendable {
    /// The item was saved successfully with no issues.
    case saved
    /// The item was saved, but a potential duplicate was detected.
    /// The associated message describes the existing match.
    case savedWithDuplicateWarning(String)
}

// MARK: - DVGRepository Protocol

/// Repository abstraction for CRUD operations and queries on `DVG` items.
///
/// All methods are async and throw `DVGRepositoryError`.
/// Implementations must be `Sendable` and filter out soft-deleted items by default.
@MainActor
protocol DVGRepository: AnyObject, Sendable {

    /// Fetches all active DVGs, auto-transitioning any expired items to `.expired` status.
    func fetchActive() async throws -> [DVG]

    /// Fetches active DVGs that expire within the given number of days.
    ///
    /// - Parameter days: Number of days from now within which expiration must fall.
    /// - Returns: Active DVGs whose `expirationDate` is within the specified window.
    func fetchExpiringSoon(within days: Int) async throws -> [DVG]

    /// Fetches active DVGs near the given coordinates.
    ///
    /// Uses the Haversine formula to calculate distance. Only DVGs with at least
    /// one `StoreLocation` within `radius` metres are returned.
    ///
    /// - Parameters:
    ///   - latitude: WGS-84 latitude in decimal degrees.
    ///   - longitude: WGS-84 longitude in decimal degrees.
    ///   - radius: Maximum distance in metres.
    /// - Returns: Active DVGs with a store location within the radius.
    func fetchNearby(latitude: Double, longitude: Double, radius: Double) async throws -> [DVG]

    /// Fetches all DVGs with the given status.
    func fetchByStatus(_ status: DVGStatus) async throws -> [DVG]

    /// Fetches all active DVGs that have a tag with the given name.
    func fetchByTag(_ tagName: String) async throws -> [DVG]

    /// Searches DVGs with a text query, optional filters, and sort order.
    ///
    /// The text query matches against `storeName`, `title`, `code`, and `notes`.
    /// Pass an empty string to skip text matching and use only filters.
    ///
    /// - Parameters:
    ///   - query: Free-text search string (case-insensitive).
    ///   - filters: Optional filter criteria.
    ///   - sort: Sort order for results. Defaults to `.dateAddedNewest`.
    /// - Returns: Matching DVGs sorted as requested.
    func search(query: String, filters: DVGFilter, sort: DVGSortOrder) async throws -> [DVG]

    /// Persists a DVG item, performing dedup detection beforehand.
    ///
    /// If an existing non-deleted DVG with the same `code` and `storeName` is found,
    /// the save still proceeds but the result carries a duplicate warning.
    ///
    /// Sets `lastModified` to the current date before saving.
    ///
    /// - Parameter dvg: The DVG to insert or update.
    /// - Returns: A `SaveResult` indicating success or success-with-warning.
    func save(_ dvg: DVG) async throws -> SaveResult

    /// Soft-deletes a DVG by setting `isDeleted = true` and `status = .archived`.
    ///
    /// Does **not** call `modelContext.delete`; the record remains for CloudKit sync.
    /// Sets `lastModified` to the current date.
    func softDelete(_ dvg: DVG) async throws

    /// Marks a DVG as used by setting its status to `.used`.
    ///
    /// Sets `lastModified` to the current date.
    func markAsUsed(_ dvg: DVG) async throws

    /// Updates the remaining balance (or points balance for loyalty items) of a DVG.
    ///
    /// Sets `lastModified` to the current date.
    ///
    /// - Parameters:
    ///   - dvg: The DVG whose balance should be updated.
    ///   - newBalance: The new balance value. Must be non-negative.
    func updateBalance(_ dvg: DVG, newBalance: Double) async throws

    /// Fetches DVGs whose associated `ScanResult` has `needsReview == true`.
    func fetchReviewQueue() async throws -> [DVG]
}

// MARK: - SwiftDataDVGRepository

/// Concrete `DVGRepository` implementation backed by SwiftData.
///
/// Uses `@MainActor` for thread safety consistent with the rest of the app.
/// All queries filter out soft-deleted items (`isDeleted == false`) by default.
///
/// Notification scheduling is handled automatically:
/// - `save(_:)` schedules an expiry notification when the DVG has an expiration date.
/// - `softDelete(_:)`, `markAsUsed(_:)` cancel the pending notification.
@MainActor
final class SwiftDataDVGRepository: DVGRepository {

    // MARK: - Properties

    private let modelContext: ModelContext

    /// Service used to schedule and cancel expiry reminder notifications.
    /// Injected at init to allow testing with a mock implementation.
    private let notificationService: (any ExpiryNotificationService)?

    // MARK: - Init

    /// Creates a repository operating on the given `ModelContext`.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData context to use for all operations.
    ///   - notificationService: Optional service for scheduling expiry notifications.
    ///     Pass `nil` to disable notification integration (useful in tests).
    init(
        modelContext: ModelContext,
        notificationService: (any ExpiryNotificationService)? = UNExpiryNotificationService()
    ) {
        self.modelContext = modelContext
        self.notificationService = notificationService
    }

    // MARK: - Fetch Active

    func fetchActive() async throws -> [DVG] {
        let activeRaw = DVGStatus.active.rawValue

        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false && $0.status == activeRaw
            },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )

        let results: [DVG]
        do {
            results = try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }

        // Auto-expire DVGs whose expiration date has passed
        let now = Date()
        let expiredRaw = DVGStatus.expired.rawValue

        for dvg in results where dvg.isExpired {
            dvg.status = expiredRaw
            dvg.lastModified = now
        }

        // Save any status transitions
        try saveContext()

        // Return only items that are still active (not transitioned)
        return results.filter { $0.status == activeRaw }
    }

    // MARK: - Fetch Expiring Soon

    func fetchExpiringSoon(within days: Int) async throws -> [DVG] {
        let now = Date()
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: days, to: now) else {
            return []
        }

        let activeRaw = DVGStatus.active.rawValue

        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false
                && $0.status == activeRaw
                && $0.expirationDate != nil
            },
            sortBy: [SortDescriptor(\.expirationDate, order: .forward)]
        )

        let results: [DVG]
        do {
            results = try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }

        // Filter in memory: expirationDate between now and cutoff
        return results.filter { dvg in
            guard let expiry = dvg.expirationDate else { return false }
            return expiry >= now && expiry <= cutoffDate
        }
    }

    // MARK: - Fetch Nearby

    func fetchNearby(latitude: Double, longitude: Double, radius: Double) async throws -> [DVG] {
        let activeRaw = DVGStatus.active.rawValue

        // Fetch all active, non-deleted DVGs that might have store locations
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false && $0.status == activeRaw
            }
        )

        let results: [DVG]
        do {
            results = try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }

        // Filter to DVGs with at least one store location within the radius
        return results.filter { dvg in
            guard let locations = dvg.storeLocations else { return false }
            return locations.contains { location in
                guard !location.isDeleted else { return false }
                let distance = Self.haversineDistance(
                    lat1: latitude, lon1: longitude,
                    lat2: location.latitude, lon2: location.longitude
                )
                return distance <= radius
            }
        }
    }

    // MARK: - Fetch by Status

    func fetchByStatus(_ status: DVGStatus) async throws -> [DVG] {
        let statusRaw = status.rawValue

        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false && $0.status == statusRaw
            },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Fetch by Tag

    func fetchByTag(_ tagName: String) async throws -> [DVG] {
        let activeRaw = DVGStatus.active.rawValue

        // SwiftData #Predicate does not support traversing relationship collections
        // with string comparisons well. Fetch active DVGs and filter in memory.
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false && $0.status == activeRaw
            },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )

        let results: [DVG]
        do {
            results = try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }

        return results.filter { dvg in
            guard let tags = dvg.tags else { return false }
            return tags.contains { tag in
                !tag.isDeleted && tag.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame
            }
        }
    }

    // MARK: - Search

    func search(query: String, filters: DVGFilter, sort: DVGSortOrder) async throws -> [DVG] {
        // Base predicate: not deleted
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false
            }
        )

        let allItems: [DVG]
        do {
            allItems = try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }

        // Apply text query filter (case-insensitive)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered: [DVG]

        if trimmedQuery.isEmpty {
            filtered = allItems
        } else {
            let lowered = trimmedQuery.lowercased()
            filtered = allItems.filter { dvg in
                dvg.storeName.lowercased().contains(lowered)
                || dvg.title.lowercased().contains(lowered)
                || dvg.code.lowercased().contains(lowered)
                || dvg.notes.lowercased().contains(lowered)
            }
        }

        // Apply structured filters
        filtered = applyFilters(filtered, filters: filters)

        // Apply sort
        filtered = applySortOrder(filtered, sort: sort)

        return filtered
    }

    // MARK: - Save

    @discardableResult
    func save(_ dvg: DVG) async throws -> SaveResult {
        // Dedup check: look for existing non-deleted DVG with same code + storeName
        let duplicateWarning = checkForDuplicate(dvg)

        dvg.lastModified = Date()
        modelContext.insert(dvg)
        try saveContext()

        // Schedule expiry notification after a successful save.
        // Only fires when the DVG has an expiration date and lead days > 0.
        if dvg.expirationDate != nil, dvg.notificationLeadDays > 0 {
            let snapshot = DVGSnapshot(dvg: dvg)
            await notificationService?.schedule(for: snapshot)
        }

        if let warning = duplicateWarning {
            return .savedWithDuplicateWarning(warning)
        }
        return .saved
    }

    // MARK: - Soft Delete

    func softDelete(_ dvg: DVG) async throws {
        let dvgID = dvg.id

        dvg.isDeleted = true
        dvg.status = DVGStatus.archived.rawValue
        dvg.lastModified = Date()
        try saveContext()

        // Cancel any pending expiry notification for this DVG.
        await notificationService?.cancel(for: dvgID)
    }

    // MARK: - Mark as Used

    func markAsUsed(_ dvg: DVG) async throws {
        let dvgID = dvg.id

        dvg.status = DVGStatus.used.rawValue
        dvg.lastModified = Date()
        try saveContext()

        // Cancel any pending expiry notification — the DVG is no longer relevant.
        await notificationService?.cancel(for: dvgID)
    }

    // MARK: - Update Balance

    func updateBalance(_ dvg: DVG, newBalance: Double) async throws {
        guard newBalance >= 0 else {
            throw DVGRepositoryError.invalidBalance(newBalance)
        }

        let dvgID = dvg.id
        let willAutoMarkUsed = dvg.dvgTypeEnum == .giftCard && newBalance == 0

        // Update the appropriate balance field based on DVG type
        if dvg.dvgTypeEnum == .loyaltyPoints {
            dvg.pointsBalance = newBalance
        } else {
            dvg.remainingBalance = newBalance
        }

        // Auto-mark as used if balance reaches zero for gift cards
        if willAutoMarkUsed {
            dvg.status = DVGStatus.used.rawValue
        }

        dvg.lastModified = Date()
        try saveContext()

        // Cancel notification if the DVG was auto-marked as used
        if willAutoMarkUsed {
            await notificationService?.cancel(for: dvgID)
        }
    }

    // MARK: - Fetch Review Queue

    func fetchReviewQueue() async throws -> [DVG] {
        // SwiftData #Predicate does not support traversing optional relationship
        // properties with field access well. Fetch all non-deleted DVGs and filter
        // in memory for those with a ScanResult where needsReview is true.
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )

        let results: [DVG]
        do {
            results = try modelContext.fetch(descriptor)
        } catch {
            throw DVGRepositoryError.fetchFailed(error.localizedDescription)
        }

        return results.filter { dvg in
            guard let scanResult = dvg.scanResult else { return false }
            return scanResult.needsReview && !scanResult.isDeleted
        }
    }
}

// MARK: - Private Helpers

extension SwiftDataDVGRepository {

    /// Saves the model context, wrapping any errors in `DVGRepositoryError`.
    private func saveContext() throws {
        do {
            try modelContext.save()
        } catch {
            throw DVGRepositoryError.saveFailed(error.localizedDescription)
        }
    }

    /// Checks whether a non-deleted DVG with the same `code` and `storeName` already exists.
    ///
    /// Only checks when both `code` and `storeName` are non-empty.
    /// Returns a warning message if a duplicate is found, or `nil` otherwise.
    private func checkForDuplicate(_ dvg: DVG) -> String? {
        let code = dvg.code
        let storeName = dvg.storeName

        guard !code.isEmpty, !storeName.isEmpty else { return nil }

        let dvgID = dvg.id

        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false
                && $0.code == code
                && $0.storeName == storeName
                && $0.id != dvgID
            }
        )

        guard let existing = try? modelContext.fetch(descriptor), !existing.isEmpty else {
            return nil
        }

        let matchTitles = existing
            .prefix(3)
            .map { $0.title.isEmpty ? $0.code : $0.title }
            .joined(separator: ", ")

        return "A DVG with code '\(code)' at '\(storeName)' already exists: \(matchTitles). The new item was saved anyway."
    }

    /// Applies `DVGFilter` criteria to an array of DVGs.
    private func applyFilters(_ items: [DVG], filters: DVGFilter) -> [DVG] {
        guard !filters.isEmpty else { return items }

        return items.filter { dvg in
            // Type filter
            if let type = filters.type, dvg.dvgTypeEnum != type {
                return false
            }

            // Status filter
            if let status = filters.status, dvg.statusEnum != status {
                return false
            }

            // Tag filter
            if let tagName = filters.tagName {
                let hasTag = dvg.tags?.contains { tag in
                    !tag.isDeleted
                    && tag.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame
                } ?? false
                if !hasTag { return false }
            }

            // Expiry date range filter
            if let from = filters.expiryDateFrom {
                guard let expiry = dvg.expirationDate, expiry >= from else {
                    return false
                }
            }

            if let to = filters.expiryDateTo {
                guard let expiry = dvg.expirationDate, expiry <= to else {
                    return false
                }
            }

            // Favourite filter
            if filters.isFavoriteOnly && !dvg.isFavorite {
                return false
            }

            return true
        }
    }

    /// Sorts an array of DVGs according to the given sort order.
    private func applySortOrder(_ items: [DVG], sort: DVGSortOrder) -> [DVG] {
        switch sort {
        case .expiryDateAscending:
            return items.sorted { lhs, rhs in
                // Items without expiry go to the end
                switch (lhs.expirationDate, rhs.expirationDate) {
                case (.some(let l), .some(let r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }

        case .expiryDateDescending:
            return items.sorted { lhs, rhs in
                switch (lhs.expirationDate, rhs.expirationDate) {
                case (.some(let l), .some(let r)): return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }

        case .valueDescending:
            return items.sorted { $0.originalValue > $1.originalValue }

        case .valueAscending:
            return items.sorted { $0.originalValue < $1.originalValue }

        case .dateAddedNewest:
            return items.sorted { $0.dateAdded > $1.dateAdded }

        case .dateAddedOldest:
            return items.sorted { $0.dateAdded < $1.dateAdded }

        case .alphabeticalAZ:
            return items.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        case .alphabeticalZA:
            return items.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
            }
        }
    }

    // MARK: - Haversine Distance

    /// Calculates the great-circle distance between two points on Earth using
    /// the Haversine formula.
    ///
    /// - Parameters:
    ///   - lat1: Latitude of point 1 in decimal degrees.
    ///   - lon1: Longitude of point 1 in decimal degrees.
    ///   - lat2: Latitude of point 2 in decimal degrees.
    ///   - lon2: Longitude of point 2 in decimal degrees.
    /// - Returns: Distance in metres.
    static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadiusMetres: Double = 6_371_000

        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0

        let radLat1 = lat1 * .pi / 180.0
        let radLat2 = lat2 * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(radLat1) * cos(radLat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusMetres * c
    }
}
