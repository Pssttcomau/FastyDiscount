import SwiftUI
import SwiftData

// MARK: - TagPickerView

/// A sheet view that allows multi-select of tags from system tags and custom tags,
/// with the ability to create new custom tags.
///
/// Tags are displayed as a list with toggleable checkmarks. System tags appear
/// first, followed by custom tags. A text field at the top allows creating new tags.
struct TagPickerView: View {

    // MARK: - Properties

    /// The form view model that holds tag selection state.
    let viewModel: DVGFormViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var newTagName: String = ""
    @State private var availableTags: [Tag] = []
    @FocusState private var isNewTagFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                createTagSection
                systemTagsSection
                customTagsSection
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                refreshTags()
            }
        }
    }

    // MARK: - Create Tag Section

    @ViewBuilder
    private var createTagSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.sm) {
                TextField("New tag name", text: $newTagName)
                    .font(Theme.Typography.body)
                    .focused($isNewTagFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        createNewTag()
                    }
                    .accessibilityLabel("New tag name")
                    .accessibilityHint("Enter a name and tap Create to add a new tag")

                Button {
                    createNewTag()
                } label: {
                    Text("Create")
                        .font(Theme.Typography.subheadline)
                        .fontWeight(.semibold)
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Create new tag")
            }
        } header: {
            Text("Create New Tag")
        }
    }

    // MARK: - System Tags Section

    @ViewBuilder
    private var systemTagsSection: some View {
        let systemTags = availableTags.filter(\.isSystemTag)

        if !systemTags.isEmpty {
            Section {
                ForEach(systemTags, id: \.id) { tag in
                    tagRow(tag)
                }
            } header: {
                Text("System Tags")
            }
        }
    }

    // MARK: - Custom Tags Section

    @ViewBuilder
    private var customTagsSection: some View {
        let customTags = availableTags.filter { !$0.isSystemTag }

        if !customTags.isEmpty {
            Section {
                ForEach(customTags, id: \.id) { tag in
                    tagRow(tag)
                }
            } header: {
                Text("Custom Tags")
            }
        }
    }

    // MARK: - Tag Row

    @ViewBuilder
    private func tagRow(_ tag: Tag) -> some View {
        Button {
            viewModel.toggleTag(tag)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                // Color indicator
                Circle()
                    .fill(tagColor(for: tag))
                    .frame(width: 12, height: 12)

                Text(tag.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                if viewModel.isTagSelected(tag) {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.name)\(viewModel.isTagSelected(tag) ? ", selected" : "")")
        .accessibilityHint("Double-tap to \(viewModel.isTagSelected(tag) ? "deselect" : "select") this tag")
        .accessibilityAddTraits(viewModel.isTagSelected(tag) ? .isSelected : [])
    }

    // MARK: - Helpers

    private func tagColor(for tag: Tag) -> Color {
        guard let hex = tag.colorHex else {
            return Theme.Colors.accent
        }
        return Color(hex: hex) ?? Theme.Colors.accent
    }

    private func createNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // Check for duplicates
        let lowered = name.lowercased()
        let isDuplicate = availableTags.contains {
            $0.name.lowercased() == lowered
        }

        guard !isDuplicate else {
            // If it already exists, just select it
            if let existing = availableTags.first(where: { $0.name.lowercased() == lowered }) {
                if !viewModel.isTagSelected(existing) {
                    viewModel.toggleTag(existing)
                }
            }
            newTagName = ""
            return
        }

        viewModel.createTag(name: name)
        newTagName = ""
        refreshTags()
    }

    private func refreshTags() {
        availableTags = viewModel.fetchAvailableTags()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tag Picker") {
    TagPickerView(
        viewModel: DVGFormViewModel(
            mode: .create(.manual),
            repository: PreviewDVGRepository(),
            modelContext: PreviewModelContext.shared
        )
    )
}

/// Minimal preview-only repository for Tag Picker previews.
@MainActor
private final class PreviewDVGRepository: DVGRepository {
    func fetchActive() async throws -> [DVG] { [] }
    func fetchExpiringSoon(within days: Int) async throws -> [DVG] { [] }
    func fetchNearby(latitude: Double, longitude: Double, radius: Double) async throws -> [DVG] { [] }
    func fetchByStatus(_ status: DVGStatus) async throws -> [DVG] { [] }
    func fetchByTag(_ tagName: String) async throws -> [DVG] { [] }
    func search(query: String, filters: DVGFilter, sort: DVGSortOrder) async throws -> [DVG] { [] }
    func save(_ dvg: DVG) async throws -> SaveResult { .saved }
    func softDelete(_ dvg: DVG) async throws { }
    func markAsUsed(_ dvg: DVG) async throws { }
    func updateBalance(_ dvg: DVG, newBalance: Double) async throws { }
    func fetchReviewQueue() async throws -> [DVG] { [] }
}

/// Provides a shared in-memory ModelContext for previews.
@MainActor
private enum PreviewModelContext {
    static let shared: ModelContext = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: DVG.self, Tag.self, configurations: config)
        return container.mainContext
    }()
}
#endif
