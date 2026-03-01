import Foundation
import SwiftData
import SwiftUI

// MARK: - TagManagerError

/// Typed errors thrown by `TagManagerViewModel` operations.
enum TagManagerError: LocalizedError {
    case duplicateName(String)
    case saveFailed(String)
    case deleteFailed(String)
    case cannotModifySystemTag

    var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return "A tag named \"\(name)\" already exists."
        case .saveFailed(let detail):
            return "Failed to save tag: \(detail)"
        case .deleteFailed(let detail):
            return "Failed to delete tag: \(detail)"
        case .cannotModifySystemTag:
            return "System tags cannot be modified."
        }
    }
}

// MARK: - TagManagerViewModel

/// Manages CRUD operations for tags: create, rename, delete, and display.
///
/// Tags are grouped into two sections:
/// - **System Tags**: Seeded by `TagSeeder`; displayed with a lock icon; not editable.
/// - **Custom Tags**: User-created; can be renamed or deleted.
///
/// ### Deletion
/// Custom tags are soft-deleted (`isDeleted = true`) and removed from all
/// associated DVGs (the DVG's `tags` relationship is updated).
///
/// ### Duplicate Prevention
/// Tag names are checked case-insensitively before creating or renaming.
@Observable
@MainActor
final class TagManagerViewModel {

    // MARK: - State

    /// All non-deleted tags. Use `systemTags` / `customTags` for grouped display.
    private(set) var allTags: [Tag] = []

    /// Current text in the search bar.
    var searchQuery: String = ""

    /// Whether the "Add Tag" form sheet is presented.
    var isAddingTag: Bool = false

    /// Name field for the new-tag form.
    var newTagName: String = ""

    /// Selected color hex string for the new-tag form (optional).
    var newTagColorHex: String? = nil

    /// The tag currently being edited (rename). `nil` when no edit is active.
    var editingTag: Tag? = nil

    /// Inline text while renaming an existing tag.
    var editingTagName: String = ""

    /// The tag for which a delete confirmation is pending.
    var tagPendingDelete: Tag? = nil

    /// Number of DVGs using `tagPendingDelete` (used in the confirmation message).
    private(set) var dvgCountForPendingDelete: Int = 0

    /// Whether an operation is in progress.
    private(set) var isLoading: Bool = false

    /// Error to display in an alert.
    var errorMessage: String? = nil
    var showError: Bool = false

    // MARK: - Predefined Colors

    /// A grid of predefined tag colors (hex strings) for the color picker.
    static let predefinedColors: [String] = [
        "#FF6B35", // Orange
        "#F72585", // Pink
        "#9B5DE5", // Purple
        "#0077B6", // Blue
        "#4CC9F0", // Sky
        "#06D6A0", // Teal
        "#2DC653", // Green
        "#FFD166", // Yellow
        "#EF233C", // Red
        "#8D99AE", // Slate
        "#FF9F1C", // Amber
        "#2B9348", // Dark Green
    ]

    // MARK: - Derived Collections

    /// System tags, optionally filtered by `searchQuery`, sorted alphabetically.
    var systemTags: [Tag] {
        filter(allTags.filter(\.isSystemTag))
    }

    /// Custom (user-created) tags, optionally filtered by `searchQuery`, sorted alphabetically.
    var customTags: [Tag] {
        filter(allTags.filter { !$0.isSystemTag })
    }

    // MARK: - Private

    private let modelContext: ModelContext

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Load

    /// Fetches all non-deleted tags from the model context.
    func loadTags() {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.isDeleted == false },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )

        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        allTags = fetched
    }

    // MARK: - Create

    /// Creates a new custom tag with the given name and optional color.
    ///
    /// Throws `TagManagerError.duplicateName` if a tag with the same name
    /// already exists (case-insensitive check).
    func createTag() throws {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        try assertNoDuplicate(name: trimmedName, excludingID: nil)

        let tag = Tag(name: trimmedName, isSystemTag: false, colorHex: newTagColorHex)
        modelContext.insert(tag)

        do {
            try modelContext.save()
        } catch {
            throw TagManagerError.saveFailed(error.localizedDescription)
        }

        // Reset form
        newTagName = ""
        newTagColorHex = nil
        isAddingTag = false

        loadTags()
    }

    // MARK: - Rename

    /// Begins renaming the given custom tag (populates `editingTagName`).
    func beginEditing(_ tag: Tag) {
        guard !tag.isSystemTag else { return }
        editingTag = tag
        editingTagName = tag.name
    }

    /// Commits the rename for `editingTag`.
    ///
    /// Throws `TagManagerError.duplicateName` if a different tag with the
    /// same name already exists.
    func commitEdit() throws {
        guard let tag = editingTag else { return }
        let trimmedName = editingTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            cancelEdit()
            return
        }

        // No-op if name is unchanged
        if trimmedName.lowercased() == tag.name.lowercased() {
            cancelEdit()
            return
        }

        try assertNoDuplicate(name: trimmedName, excludingID: tag.id)

        tag.name = trimmedName

        do {
            try modelContext.save()
        } catch {
            throw TagManagerError.saveFailed(error.localizedDescription)
        }

        cancelEdit()
        loadTags()
    }

    /// Cancels the rename operation without saving.
    func cancelEdit() {
        editingTag = nil
        editingTagName = ""
    }

    // MARK: - Delete

    /// Prepares to delete a custom tag by computing the number of DVGs
    /// that use it and presenting the confirmation alert.
    func requestDelete(_ tag: Tag) {
        guard !tag.isSystemTag else { return }
        tagPendingDelete = tag
        dvgCountForPendingDelete = dvgCount(for: tag)
    }

    /// Cancels a pending delete.
    func cancelDelete() {
        tagPendingDelete = nil
        dvgCountForPendingDelete = 0
    }

    /// Soft-deletes `tagPendingDelete` and removes it from all associated DVGs.
    func confirmDelete() throws {
        guard let tag = tagPendingDelete else { return }

        // Remove tag from all associated DVGs
        if let dvgs = tag.dvgs {
            for dvg in dvgs {
                dvg.tags?.removeAll { $0.id == tag.id }
            }
        }

        // Soft-delete the tag
        tag.isDeleted = true

        do {
            try modelContext.save()
        } catch {
            tagPendingDelete = nil
            dvgCountForPendingDelete = 0
            throw TagManagerError.deleteFailed(error.localizedDescription)
        }

        tagPendingDelete = nil
        dvgCountForPendingDelete = 0

        loadTags()
    }

    // MARK: - Error Handling

    /// Presents an error alert with the given message.
    func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - Private Helpers

    /// Filters a tag array by the current `searchQuery` (case-insensitive).
    private func filter(_ tags: [Tag]) -> [Tag] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tags }
        let lowered = trimmedQuery.lowercased()
        return tags.filter { $0.name.lowercased().contains(lowered) }
    }

    /// Returns the number of non-deleted DVGs that have the given tag.
    private func dvgCount(for tag: Tag) -> Int {
        guard let dvgs = tag.dvgs else { return 0 }
        return dvgs.filter { !$0.isDeleted }.count
    }

    /// Asserts that no non-deleted tag with the given name exists.
    /// Pass `excludingID` when renaming so the current tag is not matched.
    private func assertNoDuplicate(name: String, excludingID: UUID?) throws {
        let lowered = name.lowercased()
        let isDuplicate = allTags.contains { tag in
            guard tag.id != excludingID else { return false }
            return tag.name.lowercased() == lowered
        }
        if isDuplicate {
            throw TagManagerError.duplicateName(name)
        }
    }
}
