import SwiftUI
import SwiftData

// MARK: - HistoryFilter

/// The segment filter options for the History view.
enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all      = "all"
    case used     = "used"
    case expired  = "expired"
    case archived = "archived"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:      return "All"
        case .used:     return "Used"
        case .expired:  return "Expired"
        case .archived: return "Archived"
        }
    }

    /// The corresponding `DVGStatus` for non-all filters, or `nil` for `.all`.
    var dvgStatus: DVGStatus? {
        switch self {
        case .all:      return nil
        case .used:     return .used
        case .expired:  return .expired
        case .archived: return .archived
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .all:      return "No history yet"
        case .used:     return "No used DVGs yet"
        case .expired:  return "Nothing expired"
        case .archived: return "Nothing archived"
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .all:      return "DVGs you mark as used, let expire, or archive will appear here."
        case .used:     return "DVGs you mark as used will appear here."
        case .expired:  return "DVGs that have passed their expiry date will appear here."
        case .archived: return "DVGs you archive will appear here."
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .all:      return "clock"
        case .used:     return "checkmark.circle"
        case .expired:  return "calendar.badge.exclamationmark"
        case .archived: return "archivebox"
        }
    }

    var clearAllTitle: String {
        switch self {
        case .all:      return "Clear All History"
        case .used:     return "Clear Used"
        case .expired:  return "Clear Expired"
        case .archived: return "Clear Archived"
        }
    }

    var clearAllMessage: String {
        switch self {
        case .all:
            return "This will permanently delete all history items (used, expired, and archived). This cannot be undone."
        case .used:
            return "This will permanently delete all used DVGs. This cannot be undone."
        case .expired:
            return "This will permanently delete all expired DVGs. This cannot be undone."
        case .archived:
            return "This will permanently delete all archived DVGs. This cannot be undone."
        }
    }
}

// MARK: - HistoryViewModel

/// ViewModel managing filter state and DVG list for the History view.
///
/// Fetches DVGs with non-active statuses (used, expired, archived), applying
/// the selected segment filter and search query. Supports reactivating items
/// back to active status, permanent deletion (hard delete), and bulk clear all.
///
/// ### Concurrency
/// `@Observable @MainActor` per project convention. Repository calls are async
/// and run on the main actor since `SwiftDataDVGRepository` is `@MainActor`.
@Observable
@MainActor
final class HistoryViewModel {

    // MARK: - State

    /// Currently active segment filter.
    var selectedFilter: HistoryFilter = .all

    /// Text entered in the search bar.
    var searchQuery: String = ""

    /// Whether the initial load is in progress.
    private(set) var isLoading: Bool = false

    /// Whether data has been loaded at least once.
    private(set) var hasLoaded: Bool = false

    /// Non-nil when a non-fatal error should be presented.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    /// Whether the "Clear All" confirmation dialog is shown.
    var showClearAllConfirmation: Bool = false

    /// Whether the permanent delete confirmation is shown.
    var showPermanentDeleteConfirmation: Bool = false

    /// The DVG pending permanent deletion (used for confirmation flow).
    var pendingDeleteDVG: DVG?

    // MARK: - Raw Data

    /// All history DVGs (used + expired + archived), unfiltered.
    private var allDVGs: [DVG] = []

    // MARK: - Computed: Filtered List

    /// DVGs filtered by the selected segment and search query,
    /// sorted by `lastModified` descending (newest status change first).
    var filteredDVGs: [DVG] {
        var result = allDVGs

        // Apply segment filter
        if let status = selectedFilter.dvgStatus {
            let rawValue = status.rawValue
            result = result.filter { $0.status == rawValue }
        }

        // Apply search query
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let lowered = trimmed.lowercased()
            result = result.filter { dvg in
                dvg.title.lowercased().contains(lowered)
                || dvg.storeName.lowercased().contains(lowered)
                || dvg.code.lowercased().contains(lowered)
                || dvg.notes.lowercased().contains(lowered)
            }
        }

        // Sort by lastModified descending (newest status change first)
        return result.sorted { $0.lastModified > $1.lastModified }
    }

    var isEmpty: Bool {
        hasLoaded && filteredDVGs.isEmpty
    }

    // MARK: - Dependencies

    private let repository: any DVGRepository
    private let modelContext: ModelContext
    private let notificationService: (any ExpiryNotificationService)?

    // MARK: - Init

    /// Creates a HistoryViewModel.
    ///
    /// - Parameters:
    ///   - repository: The DVG repository for data access.
    ///   - modelContext: The SwiftData model context (used for hard delete).
    ///   - notificationService: Service for rescheduling notifications on reactivation.
    init(
        repository: any DVGRepository,
        modelContext: ModelContext,
        notificationService: (any ExpiryNotificationService)? = UNExpiryNotificationService()
    ) {
        self.repository = repository
        self.modelContext = modelContext
        self.notificationService = notificationService
    }

    // MARK: - Load

    /// Loads all history DVGs (used, expired, archived).
    /// Call from `.task` or `.refreshable`.
    func load() async {
        if !hasLoaded {
            isLoading = true
        }
        defer { isLoading = false }

        await fetchHistory()

        hasLoaded = true
    }

    /// Refreshes history data. Called by pull-to-refresh.
    func refresh() async {
        await fetchHistory()
    }

    // MARK: - Actions

    /// Reactivates a DVG by setting its status back to `.active`.
    ///
    /// Clears `isDeleted` if it was set, and reschedules expiry notifications
    /// if the DVG has an expiration date.
    func reactivate(_ dvg: DVG) async {
        dvg.status = DVGStatus.active.rawValue
        dvg.isDeleted = false
        dvg.lastModified = Date()

        do {
            try modelContext.save()
        } catch {
            handleError(error, context: "reactivation")
            return
        }

        // Reschedule notification if applicable
        if dvg.expirationDate != nil, dvg.notificationLeadDays > 0 {
            let snapshot = DVGSnapshot(dvg: dvg)
            await notificationService?.schedule(for: snapshot)
        }

        // Remove from local list after reactivation
        allDVGs.removeAll { $0.id == dvg.id }
    }

    /// Confirms and permanently deletes a single DVG (hard delete).
    ///
    /// This is the only hard delete in the app. Removes the record from SwiftData.
    func permanentlyDelete(_ dvg: DVG) async {
        modelContext.delete(dvg)

        do {
            try modelContext.save()
        } catch {
            handleError(error, context: "permanent delete")
            return
        }

        allDVGs.removeAll { $0.id == dvg.id }
    }

    /// Initiates the permanent delete confirmation flow for a single DVG.
    func requestPermanentDelete(_ dvg: DVG) {
        pendingDeleteDVG = dvg
        showPermanentDeleteConfirmation = true
    }

    /// Confirms deletion of the pending DVG (after user confirmation).
    func confirmPermanentDelete() async {
        guard let dvg = pendingDeleteDVG else { return }
        await permanentlyDelete(dvg)
        pendingDeleteDVG = nil
    }

    /// Permanently deletes all DVGs in the current segment filter.
    ///
    /// If the filter is `.all`, deletes all history items across all statuses.
    func clearAll() async {
        let dvgsToDelete: [DVG]

        if let status = selectedFilter.dvgStatus {
            let rawValue = status.rawValue
            dvgsToDelete = allDVGs.filter { $0.status == rawValue }
        } else {
            dvgsToDelete = allDVGs
        }

        for dvg in dvgsToDelete {
            modelContext.delete(dvg)
        }

        do {
            try modelContext.save()
        } catch {
            handleError(error, context: "clear all")
            return
        }

        if let status = selectedFilter.dvgStatus {
            let rawValue = status.rawValue
            allDVGs.removeAll { $0.status == rawValue }
        } else {
            allDVGs.removeAll()
        }
    }

    // MARK: - Private Helpers

    /// Fetches all history DVGs (used, expired, and archived) from the repository.
    ///
    /// Uses three sequential calls since the repository's `fetchByStatus` filters to
    /// a single status at a time. Calls run sequentially on `@MainActor` since
    /// `SwiftDataDVGRepository` is also `@MainActor`.
    private func fetchHistory() async {
        do {
            let used     = try await repository.fetchByStatus(.used)
            let expired  = try await repository.fetchByStatus(.expired)
            let archived = try await repository.fetchByStatus(.archived)

            allDVGs = used + expired + archived
        } catch {
            handleError(error, context: "history")
        }
    }

    /// Records a non-fatal error for display.
    private func handleError(_ error: Error, context: String) {
        errorMessage = "Failed to load \(context): \(error.localizedDescription)"
        showError = true
    }
}
