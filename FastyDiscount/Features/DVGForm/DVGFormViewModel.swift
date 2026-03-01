import Foundation
import SwiftData
import SwiftUI

// MARK: - DVGFormMode

/// Whether the form is creating a new DVG or editing an existing one.
enum DVGFormMode {
    case create(DVGSource)
    case edit(DVG)
}

// MARK: - FormField

/// Identifies each focusable field in the form for keyboard management.
enum FormField: Hashable, CaseIterable, Sendable {
    case title
    case code
    case storeName
    case discountDescription
    case originalValue
    case remainingBalance
    case pointsBalance
    case minimumSpend
    case notes
    case termsAndConditions
}

// MARK: - DVGFormViewModel

/// Manages form state, validation, and save logic for creating or editing a DVG.
///
/// Supports two presentation modes:
/// - **Quick-add**: Shows only essential fields (title, code, store name, expiry).
/// - **Full edit**: Expands to show all DVG fields.
///
/// Uses `@FocusState`-compatible `FormField` enum for keyboard auto-advance.
@Observable
@MainActor
final class DVGFormViewModel {

    // MARK: - Form Fields

    var title: String = ""
    var code: String = ""
    var storeName: String = ""
    var dvgType: DVGType = .discountCode
    var discountDescription: String = ""
    var originalValue: String = ""
    var remainingBalance: String = ""
    var pointsBalance: String = ""
    var minimumSpend: String = ""
    var notes: String = ""
    var termsAndConditions: String = ""
    var notificationLeadDays: Int = 0
    var isFavorite: Bool = false

    // MARK: - Expiration Date

    var hasExpirationDate: Bool = false
    var expirationDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    // MARK: - Tags

    var selectedTagIDs: Set<UUID> = []
    var showTagPicker: Bool = false

    // MARK: - UI State

    var showAllFields: Bool = false
    var isSaving: Bool = false
    var showError: Bool = false
    var errorMessage: String?
    var showDuplicateWarning: Bool = false
    var duplicateWarningMessage: String = ""

    // MARK: - Validation

    var titleError: String?
    var storeNameError: String?

    // MARK: - Store Name Autocomplete

    var storeNameSuggestions: [String] = []
    var showStoreNameSuggestions: Bool = false

    // MARK: - Private Properties

    private let mode: DVGFormMode
    private let repository: any DVGRepository
    private let modelContext: ModelContext
    private var existingDVG: DVG?
    private var allStoreNames: [String] = []

    /// Callback invoked after a successful save so the presenting view can dismiss.
    var onSaveComplete: (() -> Void)?

    // MARK: - Init

    init(mode: DVGFormMode, repository: any DVGRepository, modelContext: ModelContext) {
        self.mode = mode
        self.repository = repository
        self.modelContext = modelContext

        switch mode {
        case .create:
            // Defaults are already set above
            break

        case .edit(let dvg):
            self.existingDVG = dvg
            self.showAllFields = true
            populateFromDVG(dvg)
        }
    }

    // MARK: - Computed Properties

    /// Whether the form is in edit mode.
    var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// The navigation title for the form.
    var navigationTitle: String {
        isEditMode ? "Edit Item" : "New Item"
    }

    /// Whether balance fields should be shown (gift card type).
    var showBalanceField: Bool {
        dvgType == .giftCard
    }

    /// Whether points fields should be shown (loyalty points type).
    var showPointsField: Bool {
        dvgType == .loyaltyPoints
    }

    /// Whether the form is valid and can be saved.
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Available notification lead day options.
    var notificationLeadDayOptions: [Int] {
        [0, 1, 2, 3, 5, 7, 14, 30]
    }

    /// Display label for a notification lead day value.
    func notificationLeadDayLabel(for days: Int) -> String {
        if days == 0 {
            return "None"
        } else if days == 1 {
            return "1 day before"
        } else {
            return "\(days) days before"
        }
    }

    // MARK: - Populate from Existing DVG

    private func populateFromDVG(_ dvg: DVG) {
        title = dvg.title
        code = dvg.code
        storeName = dvg.storeName
        dvgType = dvg.dvgTypeEnum
        discountDescription = dvg.discountDescription
        originalValue = dvg.originalValue > 0 ? String(dvg.originalValue) : ""
        remainingBalance = dvg.remainingBalance > 0 ? String(dvg.remainingBalance) : ""
        pointsBalance = dvg.pointsBalance > 0 ? String(dvg.pointsBalance) : ""
        minimumSpend = dvg.minimumSpend > 0 ? String(dvg.minimumSpend) : ""
        notes = dvg.notes
        termsAndConditions = dvg.termsAndConditions
        notificationLeadDays = dvg.notificationLeadDays
        isFavorite = dvg.isFavorite

        if let expiry = dvg.expirationDate {
            hasExpirationDate = true
            expirationDate = expiry
        }

        // Collect existing tag IDs
        if let tags = dvg.tags {
            selectedTagIDs = Set(tags.filter { !$0.isDeleted }.map(\.id))
        }
    }

    // MARK: - Store Name Autocomplete

    /// Loads distinct store names from existing DVGs for autocomplete suggestions.
    func loadStoreNames() {
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> { $0.isDeleted == false }
        )

        guard let dvgs = try? modelContext.fetch(descriptor) else { return }

        // Extract distinct, non-empty store names sorted alphabetically
        let names = Set(dvgs.compactMap { dvg -> String? in
            let name = dvg.storeName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        })

        allStoreNames = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Updates autocomplete suggestions based on current store name input.
    func updateStoreNameSuggestions() {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            storeNameSuggestions = []
            showStoreNameSuggestions = false
            return
        }

        let lowered = trimmed.lowercased()
        storeNameSuggestions = allStoreNames.filter {
            $0.lowercased().contains(lowered) && $0.lowercased() != lowered
        }

        showStoreNameSuggestions = !storeNameSuggestions.isEmpty
    }

    /// Selects a store name from the autocomplete suggestions.
    func selectStoreName(_ name: String) {
        storeName = name
        storeNameSuggestions = []
        showStoreNameSuggestions = false
    }

    // MARK: - Validation

    /// Validates all form fields and sets inline error messages.
    /// Returns `true` if the form is valid.
    @discardableResult
    func validate() -> Bool {
        var valid = true

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            titleError = "Title is required"
            valid = false
        } else {
            titleError = nil
        }

        let trimmedStore = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStore.isEmpty {
            storeNameError = "Store name is required"
            valid = false
        } else {
            storeNameError = nil
        }

        return valid
    }

    /// Clears validation errors when the user starts typing.
    func clearTitleError() {
        if titleError != nil {
            titleError = nil
        }
    }

    /// Clears store name validation error when the user starts typing.
    func clearStoreNameError() {
        if storeNameError != nil {
            storeNameError = nil
        }
    }

    // MARK: - Tags

    /// Fetches all available tags (system + custom, non-deleted).
    /// Returns system tags first, then custom tags, each sorted alphabetically.
    func fetchAvailableTags() -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.isDeleted == false }
        )

        let tags = (try? modelContext.fetch(descriptor)) ?? []

        // Sort: system tags first, then alphabetical within each group
        return tags.sorted { lhs, rhs in
            if lhs.isSystemTag != rhs.isSystemTag {
                return lhs.isSystemTag
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Creates a new custom tag with the given name and selects it.
    func createTag(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tag = Tag(name: trimmed, isSystemTag: false)
        modelContext.insert(tag)

        do {
            try modelContext.save()
            selectedTagIDs.insert(tag.id)
        } catch {
            errorMessage = "Failed to create tag: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Toggles a tag's selection state.
    func toggleTag(_ tag: Tag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    /// Whether a tag is currently selected.
    func isTagSelected(_ tag: Tag) -> Bool {
        selectedTagIDs.contains(tag.id)
    }

    // MARK: - Save

    /// Validates and saves the form. Calls `onSaveComplete` on success.
    func save() async {
        guard validate() else { return }
        guard !isSaving else { return }

        isSaving = true

        do {
            let dvg: DVG

            if let existing = existingDVG {
                // Update existing DVG
                dvg = existing
                applyFieldsToDVG(dvg)
            } else {
                // Create new DVG
                let source: DVGSource
                if case .create(let s) = mode {
                    source = s
                } else {
                    source = .manual
                }

                dvg = DVG(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                    dvgType: dvgType,
                    storeName: storeName.trimmingCharacters(in: .whitespacesAndNewlines),
                    originalValue: Double(originalValue) ?? 0.0,
                    remainingBalance: Double(remainingBalance) ?? 0.0,
                    pointsBalance: Double(pointsBalance) ?? 0.0,
                    discountDescription: discountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    minimumSpend: Double(minimumSpend) ?? 0.0,
                    expirationDate: hasExpirationDate ? expirationDate : nil,
                    source: source,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFavorite: isFavorite,
                    termsAndConditions: termsAndConditions.trimmingCharacters(in: .whitespacesAndNewlines),
                    notificationLeadDays: notificationLeadDays
                )
            }

            // Resolve selected tags
            let allTags = fetchAvailableTags()
            let resolvedTags = allTags.filter { selectedTagIDs.contains($0.id) }
            dvg.tags = resolvedTags

            let result = try await repository.save(dvg)

            switch result {
            case .saved:
                onSaveComplete?()

            case .savedWithDuplicateWarning(let message):
                duplicateWarningMessage = message
                showDuplicateWarning = true
                // Still saved successfully, dismiss after user acknowledges
                onSaveComplete?()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }

    // MARK: - Apply Fields to Existing DVG

    private func applyFieldsToDVG(_ dvg: DVG) {
        dvg.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        dvg.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        dvg.storeName = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        dvg.dvgTypeEnum = dvgType
        dvg.discountDescription = discountDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        dvg.originalValue = Double(originalValue) ?? 0.0
        dvg.remainingBalance = Double(remainingBalance) ?? 0.0
        dvg.pointsBalance = Double(pointsBalance) ?? 0.0
        dvg.minimumSpend = Double(minimumSpend) ?? 0.0
        dvg.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        dvg.termsAndConditions = termsAndConditions.trimmingCharacters(in: .whitespacesAndNewlines)
        dvg.notificationLeadDays = notificationLeadDays
        dvg.isFavorite = isFavorite
        dvg.expirationDate = hasExpirationDate ? expirationDate : nil
    }

    // MARK: - Focus Management

    /// Returns the next field in the form for keyboard auto-advance.
    func nextField(after field: FormField) -> FormField? {
        let quickFields: [FormField] = [.title, .code, .storeName]
        let allFields: [FormField] = [
            .title, .code, .storeName,
            .discountDescription, .originalValue,
            .remainingBalance, .pointsBalance,
            .minimumSpend, .notes, .termsAndConditions
        ]

        let fields = showAllFields ? allFields : quickFields

        guard let currentIndex = fields.firstIndex(of: field) else { return nil }
        let nextIndex = fields.index(after: currentIndex)

        guard nextIndex < fields.endIndex else { return nil }
        let candidate = fields[nextIndex]

        // Skip balance/points fields based on DVG type
        if candidate == .remainingBalance && !showBalanceField {
            return nextField(after: candidate)
        }
        if candidate == .pointsBalance && !showPointsField {
            return nextField(after: candidate)
        }

        return candidate
    }
}
