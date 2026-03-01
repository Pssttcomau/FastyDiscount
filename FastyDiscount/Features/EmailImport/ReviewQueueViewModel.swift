import Foundation
import SwiftData

// MARK: - ReviewQueueViewModel

/// ViewModel managing the review queue for low-confidence email extractions.
///
/// Loads DVGs whose associated `ScanResult` has `needsReview == true`,
/// and exposes actions to approve, discard, or navigate to edit each item.
///
/// - Approve: sets `ScanResult.needsReview = false` and `reviewedAt = Date()`.
/// - Discard: sets `DVG.isDeleted = true` and `ScanResult.needsReview = false`.
/// - Edit: navigation is handled by the view via `router.push(.dvgEdit(dvgID:))`.
@Observable
@MainActor
final class ReviewQueueViewModel {

    // MARK: - Public State

    /// Items in the review queue, sorted newest first by `DVG.dateAdded`.
    var items: [DVG] = []

    /// `true` while the initial load is in progress.
    var isLoading: Bool = false

    /// `true` when an error alert should be shown.
    var hasError: Bool = false

    /// The error message to display in the alert.
    var errorMessage: String = ""

    /// Controls visibility of the "Approve All" confirmation alert.
    var showApproveAllConfirmation: Bool = false

    /// Controls visibility of the "Discard All" confirmation alert.
    var showDiscardAllConfirmation: Bool = false

    // MARK: - Computed Properties

    /// Number of items currently pending review.
    var pendingCount: Int { items.count }

    // MARK: - Dependencies

    private let repository: any DVGRepository
    private let modelContext: ModelContext

    // MARK: - Init

    /// Creates a `ReviewQueueViewModel` with the given repository and model context.
    ///
    /// - Parameters:
    ///   - repository: The DVG repository used to fetch and mutate items.
    ///   - modelContext: The SwiftData context used for direct `ScanResult` mutations.
    init(repository: any DVGRepository, modelContext: ModelContext) {
        self.repository = repository
        self.modelContext = modelContext
    }

    // MARK: - Load

    /// Fetches all DVGs that need review from the repository.
    ///
    /// Results are sorted newest-first by `DVG.dateAdded`.
    func loadReviewQueue() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await repository.fetchReviewQueue()
            // Sort newest first (repository returns reverse-date order,
            // but we sort explicitly for safety).
            items = fetched.sorted { $0.dateAdded > $1.dateAdded }
        } catch {
            presentError("Failed to load review queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Approve

    /// Approves a single DVG by marking its `ScanResult.needsReview = false`
    /// and setting `reviewedAt` to now. The DVG is removed from the local list.
    ///
    /// - Parameter dvg: The DVG to approve.
    func approve(_ dvg: DVG) {
        guard let scanResult = dvg.scanResult else {
            removeFromList(dvg)
            return
        }

        scanResult.needsReview = false
        scanResult.reviewedAt = Date()

        saveContext()
        removeFromList(dvg)
    }

    // MARK: - Discard

    /// Discards a single DVG by soft-deleting it and clearing its review flag.
    ///
    /// Sets `DVG.isDeleted = true` and `ScanResult.needsReview = false`.
    ///
    /// - Parameter dvg: The DVG to discard.
    func discard(_ dvg: DVG) {
        dvg.isDeleted = true
        dvg.lastModified = Date()

        if let scanResult = dvg.scanResult {
            scanResult.needsReview = false
            scanResult.reviewedAt = Date()
        }

        saveContext()
        removeFromList(dvg)
    }

    // MARK: - Batch Actions

    /// Approves all items currently in the review queue.
    ///
    /// Call after the user confirms the "Approve All" alert.
    func approveAll() {
        let currentItems = items

        for dvg in currentItems {
            if let scanResult = dvg.scanResult {
                scanResult.needsReview = false
                scanResult.reviewedAt = Date()
            }
        }

        saveContext()
        items = []
    }

    /// Discards all items currently in the review queue.
    ///
    /// Call after the user confirms the "Discard All" alert.
    func discardAll() {
        let currentItems = items
        let now = Date()

        for dvg in currentItems {
            dvg.isDeleted = true
            dvg.lastModified = now

            if let scanResult = dvg.scanResult {
                scanResult.needsReview = false
                scanResult.reviewedAt = now
            }
        }

        saveContext()
        items = []
    }

    // MARK: - Private Helpers

    private func removeFromList(_ dvg: DVG) {
        items.removeAll { $0.id == dvg.id }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            presentError("Failed to save changes: \(error.localizedDescription)")
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        hasError = true
    }
}
