import SwiftData
import SwiftUI

// MARK: - ScanResultsView

/// Displays the results of a barcode scan / AI extraction and offers a
/// pre-populated DVG creation form.
///
/// Handles three scenarios:
/// - **AI parsed**: Full pre-populated editable form with per-field confidence indicators.
/// - **Barcode only**: Code and barcode type pre-populated; user fills the rest.
/// - **OCR text only**: Raw text shown with a "Create DVG Manually" button.
///
/// On "Save DVG", creates a `DVG` with `source = .scan` and a linked `ScanResult`
/// (with `originalImageData` and `fieldConfidencesJSON`).
/// On "Scan Again", pops back to the scanner.
struct ScanResultsView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    // MARK: - ViewModel

    @State private var viewModel: ScanResultsViewModel

    // MARK: - Focus

    @FocusState private var focusedField: ScanResultField?

    // MARK: - Init

    init(inputData: ScanInputData) {
        _viewModel = State(initialValue: ScanResultsViewModel(inputData: inputData))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Scanned image thumbnail
                thumbnailSection

                // Scenario-specific content
                switch viewModel.scenario {
                case .aiParsed:
                    aiParsedContent
                case .barcodeOnly:
                    barcodeOnlyContent
                case .ocrFallback:
                    ocrFallbackContent
                case .ocrTextOnly:
                    ocrTextOnlyContent
                }

                // Action buttons
                actionButtons
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Scan Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .accessibilityLabel("Dismiss keyboard")
            }
        }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.saveSucceeded) { _, succeeded in
            if succeeded {
                // Navigate back to root of the scan tab after saving
                router.popToRoot()
            }
        }
    }

    // MARK: - Thumbnail Section

    @ViewBuilder
    private var thumbnailSection: some View {
        if let imageData = viewModel.originalImageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .accessibilityLabel("Scanned image")
        }
    }

    // MARK: - Detected Barcode Info Card

    @ViewBuilder
    private var barcodeInfoCard: some View {
        if let barcode = viewModel.detectedBarcode {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Detected Barcode", systemImage: "barcode.viewfinder")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: Theme.Spacing.sm) {
                    // Barcode type badge
                    Text(barcode.barcodeType.displayName)
                        .font(Theme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.primary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.primary.opacity(0.12), in: Capsule())

                    Spacer()

                    Text("Confidence: \(Int(barcode.confidence * 100))%")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text(barcode.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - AI Parsed Content

    @ViewBuilder
    private var aiParsedContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Overall confidence badge
            confidenceBadge(score: viewModel.overallConfidence, label: "AI Confidence")

            // Detected barcode info (if present)
            barcodeInfoCard

            // Pre-populated editable form
            aiFormSection
        }
    }

    @ViewBuilder
    private var aiFormSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Review & Edit")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Theme.Spacing.md) {
                // Title
                formField(
                    label: "Title",
                    hint: "Required",
                    confidence: viewModel.confidence(for: "title"),
                    isRequired: true
                ) {
                    TextField("Deal title", text: $viewModel.title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .storeName }
                }

                // Store Name
                formField(
                    label: "Store Name",
                    confidence: viewModel.confidence(for: "storeName")
                ) {
                    TextField("Store or brand", text: $viewModel.storeName)
                        .focused($focusedField, equals: .storeName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .code }
                }

                // Code
                formField(
                    label: "Code",
                    confidence: viewModel.confidence(for: "code")
                ) {
                    TextField("Promotional code", text: $viewModel.code)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .code)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .discountDescription }
                }

                // DVG Type Picker
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Type")
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        if let score = viewModel.confidence(for: "dvgType") {
                            confidenceDot(score: score)
                        }
                    }

                    Picker("Type", selection: $viewModel.dvgType) {
                        ForEach(DVGType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("DVG type: \(viewModel.dvgType.displayName)")
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

                // Description
                formField(
                    label: "Description",
                    confidence: viewModel.confidence(for: "discountDescription")
                ) {
                    TextField("Discount description", text: $viewModel.discountDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .discountDescription)
                }

                // Original Value
                formField(
                    label: "Value",
                    confidence: viewModel.confidence(for: "originalValue")
                ) {
                    TextField("0.00", text: $viewModel.originalValueText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .originalValue)
                }

                // Expiration Date
                expirationDateField

                // Terms & Conditions
                formField(
                    label: "Terms & Conditions",
                    confidence: viewModel.confidence(for: "termsAndConditions")
                ) {
                    TextField("Terms and conditions", text: $viewModel.termsAndConditions, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .termsAndConditions)
                }
            }
        }
    }

    // MARK: - Barcode Only Content

    @ViewBuilder
    private var barcodeOnlyContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Info message
            infoCard(
                icon: "barcode.viewfinder",
                title: "Barcode Detected",
                message: "Code and barcode type have been filled in. Please complete the remaining fields."
            )

            // Detected barcode info
            barcodeInfoCard

            // Minimal form with code pre-populated
            barcodeOnlyFormSection
        }
    }

    @ViewBuilder
    private var barcodeOnlyFormSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Complete the Form")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Theme.Spacing.md) {
                // Title (required)
                formField(label: "Title", hint: "Required", isRequired: true) {
                    TextField("Deal title", text: $viewModel.title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .storeName }
                }

                // Store Name
                formField(label: "Store Name") {
                    TextField("Store or brand", text: $viewModel.storeName)
                        .focused($focusedField, equals: .storeName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .code }
                }

                // Code (pre-filled from barcode)
                formField(label: "Code") {
                    TextField("Barcode value", text: $viewModel.code)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .code)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                // Description
                formField(label: "Description") {
                    TextField("Discount description", text: $viewModel.discountDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .discountDescription)
                }

                // Expiration Date
                expirationDateField
            }
        }
    }

    // MARK: - OCR Fallback Content

    @ViewBuilder
    private var ocrFallbackContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            infoCard(
                icon: "wifi.slash",
                title: "Offline Mode",
                message: "AI extraction was unavailable. Raw text is shown below. You can still create a DVG manually."
            )

            // Detected barcode info (if any)
            barcodeInfoCard

            // Raw OCR text display
            if let rawText = viewModel.rawOCRText, !rawText.isEmpty {
                rawTextCard(text: rawText)
            }

            // Manual form
            barcodeOnlyFormSection
        }
    }

    // MARK: - OCR Text Only Content

    @ViewBuilder
    private var ocrTextOnlyContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            infoCard(
                icon: "text.viewfinder",
                title: "Text Extracted",
                message: "No barcode was found. The extracted text is shown below. Use it as a reference to create a DVG manually."
            )

            // Raw OCR text
            if let rawText = viewModel.rawOCRText, !rawText.isEmpty {
                rawTextCard(text: rawText)
            }

            // Minimal manual form
            barcodeOnlyFormSection
        }
    }

    // MARK: - Raw Text Card

    @ViewBuilder
    private func rawTextCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Extracted Text", systemImage: "text.alignleft")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineLimit(12)
                .accessibilityLabel("Extracted text: \(text)")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Save DVG button
            Button {
                Task {
                    await viewModel.saveDVG(modelContext: modelContext)
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(viewModel.isSaving ? "Saving..." : "Save DVG")
                        .fontWeight(.semibold)
                }
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    viewModel.canSave
                        ? Theme.Colors.primary
                        : Theme.Colors.primary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                )
            }
            .disabled(!viewModel.canSave || viewModel.isSaving)
            .accessibilityLabel("Save DVG")
            .accessibilityHint("Creates and saves the discount voucher from the scan result")

            // Scan Again button
            Button {
                scanAgain()
            } label: {
                Label("Scan Again", systemImage: "barcode.viewfinder")
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .strokeBorder(Theme.Colors.primary, lineWidth: 1.5)
                    )
            }
            .accessibilityLabel("Scan again")
            .accessibilityHint("Returns to the scanner to scan a new barcode")
        }
    }

    // MARK: - Expiration Date Field

    @ViewBuilder
    private var expirationDateField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Expiration Date")
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if let score = viewModel.confidence(for: "expirationDate") {
                    confidenceDot(score: score)
                }
            }

            Toggle("Has Expiration Date", isOn: $viewModel.hasExpirationDate)
                .font(Theme.Typography.body)
                .tint(Theme.Colors.primary)
                .accessibilityLabel("Has expiration date")

            if viewModel.hasExpirationDate {
                DatePicker(
                    "Expiration Date",
                    selection: Binding(
                        get: { viewModel.expirationDate ?? Date() },
                        set: { viewModel.expirationDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .accessibilityLabel("Expiration date")
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    // MARK: - Reusable Sub-Views

    /// A labeled form field with optional confidence indicator.
    @ViewBuilder
    private func formField<Content: View>(
        label: String,
        hint: String? = nil,
        confidence: Double? = nil,
        isRequired: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(label)
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if let score = confidence {
                    confidenceDot(score: score)
                }

                if let hint {
                    Text("(\(hint))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                }

                Spacer()
            }

            content()
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    /// A colored dot indicating AI extraction confidence.
    @ViewBuilder
    private func confidenceDot(score: Double) -> some View {
        Circle()
            .fill(viewModel.confidenceColor(for: score))
            .frame(width: 8, height: 8)
            .accessibilityLabel("Confidence: \(Int(score * 100))%")
    }

    /// Overall confidence badge shown at the top of the AI-parsed view.
    @ViewBuilder
    private func confidenceBadge(score: Double, label: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(viewModel.confidenceColor(for: score))
                .frame(width: 10, height: 10)

            Text("\(label): \(Int(score * 100))%")
                .font(Theme.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            // Legend
            HStack(spacing: Theme.Spacing.sm) {
                confidenceLegendItem(color: Theme.Colors.success, label: "High")
                confidenceLegendItem(color: Theme.Colors.warning, label: "Med")
                confidenceLegendItem(color: Theme.Colors.error, label: "Low")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(viewModel.confidenceColor(for: score).opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(score * 100)) percent")
    }

    @ViewBuilder
    private func confidenceLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityHidden(true)
    }

    /// An informational card with an icon, title, and message.
    @ViewBuilder
    private func infoCard(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(message)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.Colors.primary.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }

    // MARK: - Actions

    /// Returns to the scanner by popping the scan results view.
    private func scanAgain() {
        router.pop()
    }
}

// MARK: - ScanResultField

/// Identifies focusable fields in the scan results form.
enum ScanResultField: Hashable {
    case title
    case storeName
    case code
    case discountDescription
    case originalValue
    case termsAndConditions
}

// MARK: - Preview

#if DEBUG
#Preview("Scan Results - AI Parsed") {
    let extraction = DVGExtractionResult(
        title: "20% off your next order",
        code: "SAVE20",
        dvgType: .discountCode,
        storeName: "FastyStore",
        originalValue: 20.0,
        discountDescription: "20% off all items storewide",
        expirationDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        termsAndConditions: "Valid on full-price items only.",
        confidenceScore: 0.87,
        fieldConfidences: [
            "title": 0.92,
            "code": 0.88,
            "dvgType": 0.79,
            "storeName": 0.95,
            "originalValue": 0.85,
            "discountDescription": 0.80,
            "expirationDate": 0.60,
            "termsAndConditions": 0.45
        ]
    )
    let inputData = ScanInputData.aiParsed(
        extraction: extraction,
        barcode: DetectedBarcode(
            value: "SAVE20",
            barcodeType: .qr,
            confidence: 0.97,
            boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4),
            imageData: nil
        ),
        originalImageData: nil
    )
    NavigationStack {
        ScanResultsView(inputData: inputData)
    }
    .environment(NavigationRouter())
    .modelContainer(for: [DVG.self, ScanResult.self], inMemory: true)
}

#Preview("Scan Results - Barcode Only") {
    let barcode = DetectedBarcode(
        value: "1234567890123",
        barcodeType: .ean13,
        confidence: 0.99,
        boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.3),
        imageData: nil
    )
    let inputData = ScanInputData.barcodeOnly(barcode: barcode, originalImageData: nil)
    NavigationStack {
        ScanResultsView(inputData: inputData)
    }
    .environment(NavigationRouter())
    .modelContainer(for: [DVG.self, ScanResult.self], inMemory: true)
}

#Preview("Scan Results - OCR Text Only") {
    let inputData = ScanInputData.ocrTextOnly(
        text: "GET 15% OFF\nUse code: SUMMER15\nValid until 31 Dec 2026\nFastyStore",
        originalImageData: nil
    )
    NavigationStack {
        ScanResultsView(inputData: inputData)
    }
    .environment(NavigationRouter())
    .modelContainer(for: [DVG.self, ScanResult.self], inMemory: true)
}
#endif
