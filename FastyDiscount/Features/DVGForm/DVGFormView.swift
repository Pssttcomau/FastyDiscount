import SwiftUI
import SwiftData

// MARK: - DVGFormView

/// A form view for creating or editing DVG items.
///
/// Supports two content modes:
/// - **Quick-add mode**: Shows essential fields (title, code, store name, expiration).
///   A "Show More Fields" button expands to the full form.
/// - **Full edit mode**: Shows all DVG fields. Always expanded in edit mode.
///
/// Supports two presentation styles:
/// - **Sheet** (`isEmbedded = false`, default): Wraps content in its own
///   `NavigationStack` with Cancel and Save toolbar buttons.
/// - **Embedded** (`isEmbedded = true`): No wrapping `NavigationStack`; intended
///   for use when pushed onto an existing `NavigationStack` via `DestinationView`.
///
/// The form uses `@FocusState` for keyboard management, auto-advancing to the
/// next field on submit. Store name provides autocomplete suggestions from
/// previously used store names.
struct DVGFormView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var viewModel: DVGFormViewModel?
    @FocusState private var focusedField: FormField?

    /// The form mode: create (with source) or edit (with existing DVG).
    let mode: DVGFormMode

    /// When `true`, the view omits its own `NavigationStack` wrapper, assuming
    /// it is already inside one (e.g., pushed via `DestinationView`).
    var isEmbedded: Bool = false

    // MARK: - Body

    var body: some View {
        if isEmbedded {
            embeddedBody
        } else {
            sheetBody
        }
    }

    // MARK: - Sheet Body (own NavigationStack)

    private var sheetBody: some View {
        NavigationStack {
            innerContent
        }
    }

    // MARK: - Embedded Body (no NavigationStack)

    private var embeddedBody: some View {
        innerContent
    }

    // MARK: - Inner Content

    private var innerContent: some View {
        Group {
            if let viewModel {
                formContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
            }
        }
        .navigationTitle(viewModel?.navigationTitle ?? "New Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("dvg-form-cancel-button")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        await viewModel?.save()
                    }
                } label: {
                    if viewModel?.isSaving == true {
                        ProgressView()
                    } else {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(viewModel?.isSaving == true)
                .accessibilityLabel("Save")
                .accessibilityHint("Saves the item and closes the form")
                .accessibilityIdentifier("dvg-form-save-button")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    focusedField = nil
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
        .task {
            setupViewModel()
        }
        .alert("Error", isPresented: alertBinding(\.showError)) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.errorMessage ?? "An unknown error occurred.")
        }
        .alert("Duplicate Warning", isPresented: alertBinding(\.showDuplicateWarning)) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.duplicateWarningMessage ?? "")
        }
        .sheet(isPresented: sheetBinding(\.showTagPicker)) {
            if let viewModel {
                TagPickerView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard viewModel == nil else { return }

        let repository = SwiftDataDVGRepository(modelContext: modelContext)
        let vm = DVGFormViewModel(mode: mode, repository: repository, modelContext: modelContext)

        vm.onSaveComplete = { [dismiss] in
            dismiss()
        }

        vm.loadStoreNames()
        viewModel = vm
    }

    // MARK: - Form Content

    @ViewBuilder
    private func formContent(viewModel: DVGFormViewModel) -> some View {
        Form {
            // Note: accessibility identifier is set on the Form wrapper
            // Quick-add fields (always visible)
            essentialFieldsSection(viewModel: viewModel)

            // Expiration date section (always visible)
            expirationDateSection(viewModel: viewModel)

            // Show More / Show Less toggle (only in create mode)
            if !viewModel.isEditMode {
                expandToggleSection(viewModel: viewModel)
            }

            // Extended fields (shown when expanded or in edit mode)
            if viewModel.showAllFields {
                typeSection(viewModel: viewModel)
                conditionalBalanceSection(viewModel: viewModel)
                detailsSection(viewModel: viewModel)
                tagsSection(viewModel: viewModel)
                notificationSection(viewModel: viewModel)
                notesSection(viewModel: viewModel)
            }
        }
    }

    // MARK: - Essential Fields Section

    @ViewBuilder
    private func essentialFieldsSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            // Title
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TextField("Title", text: bindable(viewModel).title)
                    .font(Theme.Typography.body)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { advanceFocus(from: .title, viewModel: viewModel) }
                    .onChange(of: viewModel.title) {
                        viewModel.clearTitleError()
                    }
                    .accessibilityLabel("Title")
                    .accessibilityHint("Required. Enter a title for this item")
                    .accessibilityIdentifier("dvg-form-title-field")

                if let error = viewModel.titleError {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.error)
                        .accessibilityLabel("Error: \(error)")
                }
            }

            // Code
            TextField("Code (e.g., SAVE20)", text: bindable(viewModel).code)
                .font(Theme.Typography.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .focused($focusedField, equals: .code)
                .submitLabel(.next)
                .onSubmit { advanceFocus(from: .code, viewModel: viewModel) }
                .accessibilityLabel("Code")
                .accessibilityHint("Optional. Enter the discount or voucher code")
                .accessibilityIdentifier("dvg-form-code-field")

            // Store Name with autocomplete
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TextField("Store Name", text: bindable(viewModel).storeName)
                    .font(Theme.Typography.body)
                    .focused($focusedField, equals: .storeName)
                    .submitLabel(viewModel.showAllFields ? .next : .done)
                    .onSubmit {
                        viewModel.showStoreNameSuggestions = false
                        if viewModel.showAllFields {
                            advanceFocus(from: .storeName, viewModel: viewModel)
                        } else {
                            focusedField = nil
                        }
                    }
                    .onChange(of: viewModel.storeName) {
                        viewModel.clearStoreNameError()
                        viewModel.updateStoreNameSuggestions()
                    }
                    .accessibilityLabel("Store Name")
                    .accessibilityHint("Required. Enter the store or brand name")
                    .accessibilityIdentifier("dvg-form-store-name-field")

                if let error = viewModel.storeNameError {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.error)
                        .accessibilityLabel("Error: \(error)")
                }

                // Autocomplete suggestions
                if viewModel.showStoreNameSuggestions {
                    storeNameSuggestionsView(viewModel: viewModel)
                }
            }
        } header: {
            Text("Essential Information")
        }
    }

    // MARK: - Store Name Suggestions

    @ViewBuilder
    private func storeNameSuggestionsView(viewModel: DVGFormViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.storeNameSuggestions.prefix(5), id: \.self) { suggestion in
                Button {
                    viewModel.selectStoreName(suggestion)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "storefront")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Text(suggestion)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suggestion: \(suggestion)")
                .accessibilityHint("Double-tap to use this store name")

                if suggestion != viewModel.storeNameSuggestions.prefix(5).last {
                    Divider()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    // MARK: - Expiration Date Section

    @ViewBuilder
    private func expirationDateSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            Toggle("Has Expiration Date", isOn: bindable(viewModel).hasExpirationDate)
                .font(Theme.Typography.body)
                .accessibilityLabel("Has expiration date")
                .accessibilityHint("Toggle to set an expiration date")

            if viewModel.hasExpirationDate {
                DatePicker(
                    "Expiration Date",
                    selection: bindable(viewModel).expirationDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityLabel("Expiration date")
            }
        } header: {
            Text("Expiration")
        }
    }

    // MARK: - Expand Toggle Section

    @ViewBuilder
    private func expandToggleSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showAllFields.toggle()
                }
            } label: {
                HStack {
                    Label(
                        viewModel.showAllFields ? "Show Fewer Fields" : "Show More Fields",
                        systemImage: viewModel.showAllFields ? "chevron.up" : "chevron.down"
                    )
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.primary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.showAllFields ? "Show fewer fields" : "Show more fields")
            .accessibilityHint("Double-tap to \(viewModel.showAllFields ? "collapse" : "expand") additional fields")
        }
    }

    // MARK: - Type Section

    @ViewBuilder
    private func typeSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            Picker("Type", selection: bindable(viewModel).dvgType) {
                ForEach(DVGType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("DVG Type")

            // Favourite toggle
            Toggle("Favourite", isOn: bindable(viewModel).isFavorite)
                .font(Theme.Typography.body)
                .accessibilityLabel("Favourite")
                .accessibilityHint("Mark this item as a favourite")
        } header: {
            Text("Type")
        }
    }

    // MARK: - Conditional Balance Section

    @ViewBuilder
    private func conditionalBalanceSection(viewModel: DVGFormViewModel) -> some View {
        if viewModel.showBalanceField {
            Section {
                // Original Value
                HStack {
                    Text("Original Value")
                        .font(Theme.Typography.body)
                    Spacer()
                    TextField("0.00", text: bindable(viewModel).originalValue)
                        .font(Theme.Typography.body)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .focused($focusedField, equals: .originalValue)
                        .accessibilityLabel("Original value")
                }

                // Remaining Balance
                HStack {
                    Text("Remaining Balance")
                        .font(Theme.Typography.body)
                    Spacer()
                    TextField("0.00", text: bindable(viewModel).remainingBalance)
                        .font(Theme.Typography.body)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .focused($focusedField, equals: .remainingBalance)
                        .accessibilityLabel("Remaining balance")
                }
            } header: {
                Text("Gift Card Balance")
            }
        }

        if viewModel.showPointsField {
            Section {
                // Points Balance
                HStack {
                    Text("Points Balance")
                        .font(Theme.Typography.body)
                    Spacer()
                    TextField("0", text: bindable(viewModel).pointsBalance)
                        .font(Theme.Typography.body)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .focused($focusedField, equals: .pointsBalance)
                        .accessibilityLabel("Points balance")
                }
            } header: {
                Text("Loyalty Points")
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            // Description
            TextField("Description", text: bindable(viewModel).discountDescription, axis: .vertical)
                .font(Theme.Typography.body)
                .lineLimit(2...4)
                .focused($focusedField, equals: .discountDescription)
                .accessibilityLabel("Description")
                .accessibilityHint("Optional. Describe the discount or offer")

            if !viewModel.showBalanceField && !viewModel.showPointsField {
                // Value (for non-gift-card, non-loyalty types)
                HStack {
                    Text("Value")
                        .font(Theme.Typography.body)
                    Spacer()
                    TextField("0.00", text: bindable(viewModel).originalValue)
                        .font(Theme.Typography.body)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .focused($focusedField, equals: .originalValue)
                        .accessibilityLabel("Value")
                }
            }

            // Minimum Spend
            HStack {
                Text("Minimum Spend")
                    .font(Theme.Typography.body)
                Spacer()
                TextField("0.00", text: bindable(viewModel).minimumSpend)
                    .font(Theme.Typography.body)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .focused($focusedField, equals: .minimumSpend)
                    .accessibilityLabel("Minimum spend")
            }
        } header: {
            Text("Details")
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            Button {
                viewModel.showTagPicker = true
            } label: {
                HStack {
                    Label("Select Tags", systemImage: "tag")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    if !viewModel.selectedTagIDs.isEmpty {
                        Text("\(viewModel.selectedTagIDs.count) selected")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select tags, \(viewModel.selectedTagIDs.count) selected")
            .accessibilityHint("Opens the tag picker")

            // Show selected tag chips
            if !viewModel.selectedTagIDs.isEmpty {
                selectedTagsPreview(viewModel: viewModel)
            }
        } header: {
            Text("Tags")
        }
    }

    // MARK: - Selected Tags Preview

    @ViewBuilder
    private func selectedTagsPreview(viewModel: DVGFormViewModel) -> some View {
        let allTags = viewModel.fetchAvailableTags()
        let selectedTags = allTags.filter { viewModel.selectedTagIDs.contains($0.id) }

        if !selectedTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(selectedTags, id: \.id) { tag in
                        HStack(spacing: Theme.Spacing.xs) {
                            Circle()
                                .fill(tagColor(for: tag))
                                .frame(width: 8, height: 8)

                            Text(tag.name)
                                .font(Theme.Typography.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(tagColor(for: tag).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected tags: \(selectedTags.map(\.name).joined(separator: ", "))")
        }
    }

    // MARK: - Notification Section

    @ViewBuilder
    private func notificationSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            Picker("Reminder", selection: bindable(viewModel).notificationLeadDays) {
                ForEach(viewModel.notificationLeadDayOptions, id: \.self) { days in
                    Text(viewModel.notificationLeadDayLabel(for: days))
                        .tag(days)
                }
            }
            .font(Theme.Typography.body)
            .accessibilityLabel("Expiration reminder")
            .accessibilityHint("Choose how many days before expiry to receive a reminder")
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private func notesSection(viewModel: DVGFormViewModel) -> some View {
        Section {
            TextField("Notes", text: bindable(viewModel).notes, axis: .vertical)
                .font(Theme.Typography.body)
                .lineLimit(3...6)
                .focused($focusedField, equals: .notes)
                .accessibilityLabel("Notes")
                .accessibilityHint("Optional. Add any personal notes")

            TextField("Terms & Conditions", text: bindable(viewModel).termsAndConditions, axis: .vertical)
                .font(Theme.Typography.body)
                .lineLimit(3...6)
                .focused($focusedField, equals: .termsAndConditions)
                .accessibilityLabel("Terms and conditions")
                .accessibilityHint("Optional. Enter any terms and conditions")
        } header: {
            Text("Notes & Terms")
        }
    }

    // MARK: - Focus Management

    private func advanceFocus(from field: FormField, viewModel: DVGFormViewModel) {
        if let next = viewModel.nextField(after: field) {
            focusedField = next
        } else {
            focusedField = nil
        }
    }

    // MARK: - Binding Helpers

    /// Creates `Binding` values from `DVGFormViewModel` properties.
    private func bindable(_ viewModel: DVGFormViewModel) -> Bindable<DVGFormViewModel> {
        Bindable(viewModel)
    }

    /// Creates a Binding<Bool> for alert presentation tied to a viewModel property.
    private func alertBinding(_ keyPath: ReferenceWritableKeyPath<DVGFormViewModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel?[keyPath: keyPath] ?? false },
            set: { viewModel?[keyPath: keyPath] = $0 }
        )
    }

    /// Creates a Binding<Bool> for sheet presentation tied to a viewModel property.
    private func sheetBinding(_ keyPath: ReferenceWritableKeyPath<DVGFormViewModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel?[keyPath: keyPath] ?? false },
            set: { viewModel?[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Tag Color Helper

    private func tagColor(for tag: Tag) -> Color {
        guard let hex = tag.colorHex else {
            return Theme.Colors.accent
        }
        return Color(hex: hex) ?? Theme.Colors.accent
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DVG Form - Create") {
    DVGFormView(mode: .create(.manual))
        .modelContainer(for: DVG.self, inMemory: true)
}

#Preview("DVG Form - Edit") {
    DVGFormView(mode: .edit(DVG.preview))
        .modelContainer(for: DVG.self, inMemory: true)
}
#endif
