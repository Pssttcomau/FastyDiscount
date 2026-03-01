import SwiftUI

// MARK: - ShareExtensionView

/// Compact SwiftUI form for creating a DVG from shared content.
///
/// Displayed within the share extension's `UIHostingController`. The form
/// fields are pre-populated from extraction results and can be edited
/// by the user before saving.
struct ShareExtensionView: View {

    // MARK: - Properties

    @Bindable var viewModel: ShareExtensionViewModel

    /// Closure called to dismiss the extension (cancel or after save).
    var onDismiss: () -> Void

    /// Closure called after a successful save (completes the extension request).
    var onSave: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Save Discount")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onDismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            performSave()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .processing:
            processingView

        case .ready:
            formView

        case .error(let message):
            errorView(message: message)

        case .saved:
            savedView
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Processing shared content...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Form View

    private var formView: some View {
        Form {
            // Content type indicator
            if let extraction = viewModel.extractionResult {
                Section {
                    HStack(spacing: 10) {
                        contentTypeIcon(for: extraction.contentType)
                            .font(.title3)
                            .foregroundStyle(.tint)
                        Text(contentTypeLabel(for: extraction.contentType))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Main fields
            Section("Details") {
                TextField("Title", text: $viewModel.title)
                    .textInputAutocapitalization(.words)

                TextField("Code", text: $viewModel.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)

                TextField("Store Name", text: $viewModel.storeName)
                    .textInputAutocapitalization(.words)
            }

            // Type picker
            Section("Type") {
                Picker("Category", selection: $viewModel.selectedDVGType) {
                    ForEach(DVGType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.iconName)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            // Description
            if !viewModel.discountDescription.isEmpty {
                Section("Description") {
                    Text(viewModel.discountDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Notes
            Section("Notes") {
                TextField("Notes", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Saved View

    private var savedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Saved!")
                .font(.headline)
            Text("Open FastyDiscount to review.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var canSave: Bool {
        switch viewModel.state {
        case .ready:
            return !viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private func performSave() {
        let success = viewModel.save()
        if success {
            // Brief delay to show the saved confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onSave()
            }
        }
    }

    private func contentTypeIcon(for type: ShareContentType) -> Image {
        switch type {
        case .text:  return Image(systemName: "text.alignleft")
        case .url:   return Image(systemName: "link")
        case .image: return Image(systemName: "photo")
        case .pdf:   return Image(systemName: "doc.richtext")
        }
    }

    private func contentTypeLabel(for type: ShareContentType) -> String {
        switch type {
        case .text:  return "Shared text"
        case .url:   return "Shared link"
        case .image: return "Shared image"
        case .pdf:   return "Shared PDF"
        }
    }
}
