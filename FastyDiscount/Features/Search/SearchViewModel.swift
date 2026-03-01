import SwiftUI
import SwiftData

// MARK: - SearchViewModel

/// ViewModel for the search screen.
///
/// Manages free-text query, multi-select type/status filters, tag filter,
/// expiry date range, sort order, and the resulting DVG list.
///
/// ### Debounce
/// Text input is debounced with a 300 ms delay using a cancellable `Task`.
/// Each new character cancels the in-flight task before creating a new one.
///
/// ### Multi-select filters
/// `DVGFilter` supports a single `type` and `status`. For multi-select, the
/// ViewModel calls `repository.search()` with `type = nil` and `status = nil`,
/// then applies multi-select filtering in memory.
@Observable
@MainActor
final class SearchViewModel {

    // MARK: - Search State

    /// The raw text entered by the user in the search bar.
    var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }

    // MARK: - Filter State

    /// Selected DVG types (multi-select). Empty means "all types".
    var selectedTypes: Set<DVGType> = [] {
        didSet { performSearch() }
    }

    /// Selected statuses (multi-select). Empty means "all statuses".
    var selectedStatuses: Set<DVGStatus> = [] {
        didSet { performSearch() }
    }

    /// Selected tag name filter. `nil` means no tag filter.
    var selectedTagName: String? = nil {
        didSet { performSearch() }
    }

    /// Expiry date range: from date. `nil` means no lower bound.
    var expiryDateFrom: Date? = nil {
        didSet { performSearch() }
    }

    /// Expiry date range: to date. `nil` means no upper bound.
    var expiryDateTo: Date? = nil {
        didSet { performSearch() }
    }

    // MARK: - Sort State

    /// Currently selected sort order.
    var sortOrder: DVGSortOrder = .expiryDateAscending {
        didSet { performSearch() }
    }

    // MARK: - Results

    /// The filtered and sorted DVG results.
    private(set) var results: [DVG] = []

    /// All tags available for the tag filter picker (fetched once on load).
    private(set) var availableTags: [Tag] = []

    // MARK: - Loading & Error State

    /// Whether a search is currently in progress.
    private(set) var isLoading: Bool = false

    /// Error message to display, if any.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    // MARK: - Initial Filter

    /// Optional initial filter applied when the view first appears.
    /// Allows "See All" buttons from the dashboard to pre-populate filters.
    let initialFilter: DVGFilter?

    // MARK: - Dependencies

    private let repository: any DVGRepository
    private let modelContext: ModelContext

    /// In-flight debounce task. Cancelled on each new query change.
    private var debounceTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// The total count of active non-empty filters.
    var activeFilterCount: Int {
        var count = 0
        if !selectedTypes.isEmpty { count += 1 }
        if !selectedStatuses.isEmpty { count += 1 }
        if selectedTagName != nil { count += 1 }
        if expiryDateFrom != nil || expiryDateTo != nil { count += 1 }
        return count
    }

    /// Whether any filter is currently active.
    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    /// Whether the search is idle (no query and no results).
    var isEmptyState: Bool {
        !isLoading && results.isEmpty
    }

    // MARK: - Init

    /// Creates a `SearchViewModel`.
    ///
    /// - Parameters:
    ///   - repository: The DVG data repository.
    ///   - modelContext: The SwiftData model context (used to fetch tags).
    ///   - initialFilter: An optional filter to pre-apply on first load.
    init(
        repository: any DVGRepository,
        modelContext: ModelContext,
        initialFilter: DVGFilter? = nil
    ) {
        self.repository = repository
        self.modelContext = modelContext
        self.initialFilter = initialFilter
    }

    // MARK: - Lifecycle

    /// Called on view appear. Loads tags and applies the initial filter if provided.
    func onAppear() async {
        await loadAvailableTags()
        applyInitialFilterIfNeeded()
        await runSearch()
    }

    // MARK: - Clear Filters

    /// Clears all active filters and re-runs the search.
    func clearAllFilters() {
        selectedTypes = []
        selectedStatuses = []
        selectedTagName = nil
        expiryDateFrom = nil
        expiryDateTo = nil
    }

    // MARK: - Favorite Toggle

    /// Toggles the favourite state of a DVG.
    func toggleFavorite(_ dvg: DVG) {
        dvg.isFavorite.toggle()
        try? modelContext.save()
    }

    // MARK: - Swipe Actions

    /// Marks a DVG as used via the repository.
    func markAsUsed(_ dvg: DVG) {
        Task {
            do {
                try await repository.markAsUsed(dvg)
                await runSearch()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Soft-deletes a DVG via the repository.
    func delete(_ dvg: DVG) {
        Task {
            do {
                try await repository.softDelete(dvg)
                await runSearch()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Private: Debounce

    /// Schedules a debounced search. Cancels any in-flight task and waits 300 ms.
    private func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await runSearch()
            } catch {
                // Task was cancelled — no action needed.
            }
        }
    }

    /// Immediately performs a search without debounce (used for filter/sort changes).
    private func performSearch() {
        debounceTask?.cancel()
        Task {
            await runSearch()
        }
    }

    // MARK: - Private: Search Execution

    /// Executes the search against the repository and applies in-memory multi-select filters.
    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }

        // Build DVGFilter: pass nil for type/status since we multi-select in memory.
        let filter = DVGFilter(
            type: nil,
            status: nil,
            tagName: selectedTagName,
            expiryDateFrom: expiryDateFrom,
            expiryDateTo: expiryDateTo,
            isFavoriteOnly: false
        )

        do {
            var items = try await repository.search(
                query: searchQuery,
                filters: filter,
                sort: sortOrder
            )

            // Apply multi-select type filter in memory
            if !selectedTypes.isEmpty {
                items = items.filter { selectedTypes.contains($0.dvgTypeEnum) }
            }

            // Apply multi-select status filter in memory
            if !selectedStatuses.isEmpty {
                items = items.filter { selectedStatuses.contains($0.statusEnum) }
            }

            results = items
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Private: Tag Loading

    /// Fetches all non-deleted tags from SwiftData for the tag filter UI.
    private func loadAvailableTags() async {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { !$0.isDeleted },
            sortBy: [
                SortDescriptor(\.isSystemTag, order: .reverse),
                SortDescriptor(\.name, order: .forward)
            ]
        )
        availableTags = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Initial Filter

    /// Applies `initialFilter` to the ViewModel state on first appear.
    private func applyInitialFilterIfNeeded() {
        guard let filter = initialFilter else { return }
        if let type = filter.type {
            selectedTypes = [type]
        }
        if let status = filter.status {
            selectedStatuses = [status]
        }
        if let tagName = filter.tagName {
            selectedTagName = tagName
        }
        if let from = filter.expiryDateFrom {
            expiryDateFrom = from
        }
        if let to = filter.expiryDateTo {
            expiryDateTo = to
        }
    }
}
