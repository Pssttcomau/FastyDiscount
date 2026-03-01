import SwiftUI
import SwiftData

// MARK: - TagManagerView

/// Displays all tags grouped into System Tags and Custom Tags sections.
///
/// - **System Tags**: Shown with a lock icon; non-editable.
/// - **Custom Tags**: Editable via tap-to-rename and swipe-to-delete.
/// - **Add Tag**: A toolbar button opens a form sheet with a name field
///   and an optional color picker.
/// - **Search**: A search bar at the top filters both sections.
///
/// This view is used:
/// 1. As a NavigationLink destination from `SettingsView`.
/// 2. As a sheet from `TagPickerView` (TASK-011).
struct TagManagerView: View {

    // MARK: - Properties

    @State private var viewModel: TagManagerViewModel
    @Environment(\.modelContext) private var modelContext

    // MARK: - Init

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: TagManagerViewModel(modelContext: modelContext))
    }

    // MARK: - Body

    var body: some View {
        List {
            systemTagsSection
            customTagsSection
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchQuery, prompt: "Search tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isAddingTag = true
                } label: {
                    Label("Add Tag", systemImage: "plus")
                }
                .accessibilityLabel("Add Tag")
            }
        }
        .task {
            viewModel.loadTags()
        }
        // Add Tag sheet
        .sheet(isPresented: $viewModel.isAddingTag) {
            addTagSheet
        }
        // Delete confirmation alert
        .alert(deleteAlertTitle, isPresented: Binding(
            get: { viewModel.tagPendingDelete != nil },
            set: { if !$0 { viewModel.cancelDelete() } }
        )) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Remove", role: .destructive) {
                do {
                    try viewModel.confirmDelete()
                } catch {
                    viewModel.presentError(error.localizedDescription)
                }
            }
        } message: {
            Text(deleteAlertMessage)
        }
        // Error alert
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unexpected error occurred.")
        }
    }

    // MARK: - System Tags Section

    @ViewBuilder
    private var systemTagsSection: some View {
        Section {
            if viewModel.systemTags.isEmpty {
                emptyRow(message: viewModel.searchQuery.isEmpty
                    ? "No system tags"
                    : "No system tags match your search")
            } else {
                ForEach(viewModel.systemTags, id: \.id) { tag in
                    systemTagRow(tag)
                }
            }
        } header: {
            Text("System Tags")
        } footer: {
            Text("System tags are built-in and cannot be modified.")
                .font(Theme.Typography.caption)
        }
    }

    @ViewBuilder
    private func systemTagRow(_ tag: Tag) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            tagColorCircle(colorHex: tag.colorHex)

            Text(tag.name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            Image(systemName: "lock.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag.name), system tag, locked")
    }

    // MARK: - Custom Tags Section

    @ViewBuilder
    private var customTagsSection: some View {
        Section {
            if viewModel.customTags.isEmpty {
                emptyRow(message: viewModel.searchQuery.isEmpty
                    ? "No custom tags yet. Tap + to add one."
                    : "No custom tags match your search")
            } else {
                ForEach(viewModel.customTags, id: \.id) { tag in
                    customTagRow(tag)
                }
                .onDelete { indexSet in
                    deleteCustomTags(at: indexSet)
                }
            }
        } header: {
            Text("Custom Tags")
        } footer: {
            Text("Tap a custom tag to rename it. Swipe left to delete.")
                .font(Theme.Typography.caption)
        }
    }

    @ViewBuilder
    private func customTagRow(_ tag: Tag) -> some View {
        Group {
            if viewModel.editingTag?.id == tag.id {
                // Inline rename row
                HStack(spacing: Theme.Spacing.sm) {
                    tagColorCircle(colorHex: tag.colorHex)

                    TextField("Tag name", text: $viewModel.editingTagName)
                        .font(Theme.Typography.body)
                        .submitLabel(.done)
                        .onSubmit {
                            commitEdit()
                        }

                    Spacer()

                    Button {
                        commitEdit()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save tag name")

                    Button {
                        viewModel.cancelEdit()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel rename")
                }
                .padding(.vertical, Theme.Spacing.xs)
            } else {
                // Normal display row — tap to edit
                Button {
                    viewModel.beginEditing(tag)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        tagColorCircle(colorHex: tag.colorHex)

                        Text(tag.name)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Image(systemName: "pencil")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, Theme.Spacing.xs)
                .accessibilityLabel("\(tag.name), custom tag. Double-tap to rename.")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.requestDelete(tag)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Add Tag Sheet

    @ViewBuilder
    private var addTagSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tag name", text: $viewModel.newTagName)
                        .font(Theme.Typography.body)
                        .submitLabel(.done)
                        .onSubmit {
                            submitNewTag()
                        }
                        .accessibilityLabel("Tag name")
                        .accessibilityHint("Enter a name for the new tag")
                } header: {
                    Text("Name")
                }

                Section {
                    colorPickerGrid
                } header: {
                    Text("Color (optional)")
                } footer: {
                    Text("Choose a display color for this tag.")
                        .font(Theme.Typography.caption)
                }
            }
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.newTagName = ""
                        viewModel.newTagColorHex = nil
                        viewModel.isAddingTag = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        submitNewTag()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Color Picker Grid

    @ViewBuilder
    private var colorPickerGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm),
                            count: 6)

        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            // "No color" option
            Button {
                viewModel.newTagColorHex = nil
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.Colors.border, lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .overlay {
                    if viewModel.newTagColorHex == nil {
                        Circle()
                            .strokeBorder(Theme.Colors.primary, lineWidth: 2.5)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No color selected")

            // Predefined color swatches
            ForEach(TagManagerViewModel.predefinedColors, id: \.self) { hex in
                Button {
                    viewModel.newTagColorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? Theme.Colors.accent)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if viewModel.newTagColorHex == hex {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 2)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            if viewModel.newTagColorHex == hex {
                                Circle()
                                    .strokeBorder(Color(hex: hex) ?? Theme.Colors.accent, lineWidth: 3)
                                    .scaleEffect(1.2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(hex)")
                .accessibilityAddTraits(viewModel.newTagColorHex == hex ? .isSelected : [])
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func tagColorCircle(colorHex: String?) -> some View {
        if let hex = colorHex, let color = Color(hex: hex) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: 12, height: 12)
        }
    }

    @ViewBuilder
    private func emptyRow(message: String) -> some View {
        Text(message)
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
            .padding(.vertical, Theme.Spacing.sm)
    }

    private var deleteAlertTitle: String {
        "Delete Tag?"
    }

    private var deleteAlertMessage: String {
        guard let tag = viewModel.tagPendingDelete else { return "" }
        let count = viewModel.dvgCountForPendingDelete
        if count > 0 {
            return "This tag is used by \(count) DVG\(count == 1 ? "" : "s"). Remove tag from all?"
        }
        return "Are you sure you want to delete the tag \"\(tag.name)\"?"
    }

    private func submitNewTag() {
        do {
            try viewModel.createTag()
        } catch {
            viewModel.presentError(error.localizedDescription)
        }
    }

    private func commitEdit() {
        do {
            try viewModel.commitEdit()
        } catch {
            viewModel.presentError(error.localizedDescription)
        }
    }

    private func deleteCustomTags(at offsets: IndexSet) {
        let tagsToDelete = offsets.map { viewModel.customTags[$0] }
        for tag in tagsToDelete {
            viewModel.requestDelete(tag)
        }
    }
}

// MARK: - Color Hex Extension (local)

private extension Color {
    /// Creates a `Color` from a hex string such as `"#FF6B35"` or `"FF6B35"`.
    /// Returns `nil` if the string cannot be parsed.
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgbValue) else { return nil }

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tag Manager") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Tag.self, DVG.self, configurations: config)
    let context = container.mainContext

    // Seed preview tags
    let systemTag1 = Tag(name: "Food", isSystemTag: true, colorHex: "#FF6B35")
    let systemTag2 = Tag(name: "Electronics", isSystemTag: true, colorHex: "#0077B6")
    let systemTag3 = Tag(name: "Travel", isSystemTag: true, colorHex: "#06D6A0")
    let customTag1 = Tag(name: "Weekend Deals", isSystemTag: false, colorHex: "#FFD166")
    let customTag2 = Tag(name: "Summer Sale", isSystemTag: false, colorHex: "#F72585")

    context.insert(systemTag1)
    context.insert(systemTag2)
    context.insert(systemTag3)
    context.insert(customTag1)
    context.insert(customTag2)

    return NavigationStack {
        TagManagerView(modelContext: context)
    }
    .modelContainer(container)
}
#endif
