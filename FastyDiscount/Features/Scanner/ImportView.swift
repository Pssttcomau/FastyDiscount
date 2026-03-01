import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ImportView

/// View for importing photos or PDF documents and extracting barcode / text content.
///
/// Presents two import options (photo picker and document picker), processes
/// the selected content via `ImportViewModel`, and displays the results
/// with a "Create DVG" button to hand off to the DVG creation form.
struct ImportView: View {

    // MARK: - Environment

    @Environment(NavigationRouter.self) private var router

    // MARK: - State

    @State private var viewModel = ImportViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var showDVGForm = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                switch viewModel.importState {
                case .idle:
                    idleContent
                case .processing(let progress):
                    processingContent(progress: progress)
                case .results:
                    resultsContent
                case .error(let message):
                    errorContent(message: message)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                await viewModel.processPhoto(item)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                Task {
                    await viewModel.processPDF(at: url)
                }
            }
        }
        .sheet(isPresented: $showDVGForm) {
            DVGFormView(mode: .create(viewModel.dvgSource))
        }
        .toolbar {
            if viewModel.hasResults {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Reset") {
                        viewModel.reset()
                        selectedPhotoItem = nil
                    }
                    .accessibilityLabel("Reset import")
                    .accessibilityHint("Clears the current results and returns to the import screen")
                }
            }
        }
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Hero icon
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Colors.primary)
                .accessibilityHidden(true)

            Text("Import & Scan")
                .font(Theme.Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Select a photo or PDF containing a barcode or coupon. The app will automatically detect and extract the code.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Import option buttons
            importOptionsView
        }
    }

    private var importOptionsView: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Photo picker button
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                ImportOptionRow(
                    icon: "photo.on.rectangle",
                    title: "Choose from Photos",
                    subtitle: "Select a photo from your library"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose photo from library")
            .accessibilityHint("Opens your photo library to select an image")

            // Document picker button
            Button {
                showDocumentPicker = true
            } label: {
                ImportOptionRow(
                    icon: "doc.richtext",
                    title: "Import PDF Document",
                    subtitle: "Open a PDF containing barcodes or coupons"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import PDF document")
            .accessibilityHint("Opens the file browser to select a PDF")
        }
    }

    // MARK: - Processing Content

    private func processingContent(progress: Double) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            if let thumbnail = viewModel.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .accessibilityLabel("Preview of imported content")
            } else {
                // Placeholder while rendering first page
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.surface)
                    .frame(height: 150)
                    .overlay {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityHidden(true)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ProgressView(value: progress)
                    .tint(Theme.Colors.primary)
                    .accessibilityLabel("Processing progress: \(Int(progress * 100))%")

                Text(processingMessage(for: progress))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private func processingMessage(for progress: Double) -> String {
        switch progress {
        case 0..<0.3:
            return "Loading content..."
        case 0.3..<0.5:
            return "Preparing image..."
        case 0.5..<0.8:
            return "Scanning for barcodes..."
        case 0.8..<1.0:
            return "Extracting text..."
        default:
            return "Finishing up..."
        }
    }

    // MARK: - Results Content

    @ViewBuilder
    private var resultsContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Thumbnail
            if let thumbnail = viewModel.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .accessibilityLabel("Preview of imported content")
            }

            // Detected barcodes section
            if !viewModel.detectedBarcodes.isEmpty {
                detectedBarcodesSection
            }

            // Extracted text section (shown as supplementary)
            if !viewModel.extractedTextBlocks.isEmpty {
                extractedTextSection
            }

            // No content at all
            if !viewModel.hasContent {
                noContentView
            }

            // Create DVG button
            if viewModel.hasContent {
                createDVGButton
            }
        }
    }

    // MARK: - Detected Barcodes Section

    private var detectedBarcodesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Detected Barcodes", systemImage: "barcode.viewfinder")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(viewModel.detectedBarcodes.enumerated()), id: \.offset) { _, barcode in
                    BarcodeResultRow(barcode: barcode)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Extracted Text Section

    private var extractedTextSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(
                viewModel.detectedBarcodes.isEmpty ? "Extracted Text" : "Supplementary Text",
                systemImage: "text.viewfinder"
            )
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)

            Text(viewModel.extractedTextCombined)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(8)
                .accessibilityLabel("Extracted text: \(viewModel.extractedTextCombined)")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    // MARK: - No Content View

    private var noContentView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)

            Text("No Content Found")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("No barcodes or readable text were detected. Try a different image or PDF.")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Create DVG Button

    private var createDVGButton: some View {
        Button {
            showDVGForm = true
        } label: {
            Label("Create DVG", systemImage: "plus.circle.fill")
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .accessibilityLabel("Create new DVG from scan results")
        .accessibilityHint("Opens the form to save this barcode as a new discount, voucher, or gift card")
    }

    // MARK: - Error Content

    private func errorContent(message: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.Colors.warning)
                .accessibilityHidden(true)

            Text("Import Failed")
                .font(Theme.Typography.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.reset()
                selectedPhotoItem = nil
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .accessibilityLabel("Try importing again")
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

// MARK: - ImportOptionRow

/// A tappable row displaying an import option (photo or PDF).
private struct ImportOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
    }
}

// MARK: - BarcodeResultRow

/// Displays a single detected barcode with its type, value, and confidence.
private struct BarcodeResultRow: View {
    let barcode: DetectedBarcode

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Barcode type icon
            Image(systemName: barcodeIcon(for: barcode.barcodeType))
                .font(.system(size: 22))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(barcode.value)
                    .font(Theme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.sm) {
                    Text(barcode.barcodeType.displayName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("•")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityHidden(true)

                    Text("\(Int(barcode.confidence * 100))% confidence")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(barcode.barcodeType.displayName): \(barcode.value), \(Int(barcode.confidence * 100))% confidence")
    }

    private func barcodeIcon(for type: BarcodeType) -> String {
        switch type {
        case .qr:      return "qrcode"
        case .ean8, .ean13, .upcA, .upcE: return "barcode"
        case .pdf417:  return "doc.richtext"
        case .code128, .code39: return "barcode"
        case .text:    return "text.alignleft"
        }
    }
}

// MARK: - DocumentPickerView

/// UIViewControllerRepresentable wrapper for `UIDocumentPickerViewController`.
///
/// Accepts PDF files only and calls `onPick` with the selected URL.
struct DocumentPickerView: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate, @unchecked Sendable {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Import - Idle") {
    NavigationStack {
        ImportView()
            .environment(NavigationRouter())
    }
}
#endif
