import Foundation
import SwiftData
import SwiftUI

// MARK: - ScanInputData

/// Encapsulates the three possible result types from the scanning pipeline.
///
/// This enum bridges the three upstream sources (camera scanner, photo/PDF import,
/// AI vision parsing) into a single type-safe payload consumed by `ScanResultsView`.
///
/// Conforms to `Sendable` so it can be safely passed across actor boundaries.
enum ScanInputData: Sendable {

    /// AI parsing succeeded: all fields extracted with confidence scores.
    case aiParsed(
        extraction: DVGExtractionResult,
        barcode: DetectedBarcode?,
        originalImageData: Data?
    )

    /// Only a barcode was detected (no AI parsing).
    /// Pre-populate code and barcode type; user fills the rest manually.
    case barcodeOnly(
        barcode: DetectedBarcode,
        originalImageData: Data?
    )

    /// Only OCR text was extracted (offline/fallback).
    /// Show raw text with a "Create DVG Manually" button.
    case ocrTextOnly(
        text: String,
        originalImageData: Data?
    )
}

// MARK: - ScanResultsViewModel

/// Manages state for the scan results view.
///
/// Handles all three result scenarios:
/// - AI-parsed: pre-populated editable form with confidence indicators
/// - Barcode-only: code/barcodeType pre-populated, rest empty
/// - OCR-text-only: raw text display with manual-entry option
///
/// Responsible for creating the `DVG` + `ScanResult` pair in SwiftData.
@Observable
@MainActor
final class ScanResultsViewModel {

    // MARK: - Input

    /// The scan data passed in from the upstream scanner.
    let inputData: ScanInputData

    // MARK: - Form Fields (editable by user)

    var title: String = ""
    var code: String = ""
    var storeName: String = ""
    var dvgType: DVGType = .discountCode
    var discountDescription: String = ""
    var originalValueText: String = ""
    var expirationDate: Date?
    var hasExpirationDate: Bool = false
    var termsAndConditions: String = ""

    // Barcode fields
    var barcodeType: BarcodeType = .text
    var decodedBarcodeValue: String = ""

    /// URL extracted from a barcode value (e.g. QR code linking to a website).
    /// Populated instead of `code` when the barcode value is a URL.
    var websiteURL: String = ""

    // MARK: - Confidence Data (from AI)

    /// Per-field confidence scores from the AI extraction result.
    var fieldConfidences: [String: Double] = [:]

    /// Overall confidence score from the AI.
    var overallConfidence: Double = 0.0

    // MARK: - UI State

    var isSaving: Bool = false
    var hasError: Bool = false
    var errorMessage: String = ""
    var saveSucceeded: Bool = false

    /// Whether to show the full form (AI result case) or simplified form.
    var showFullForm: Bool = false

    // MARK: - Computed Properties

    /// Returns the display scenario based on input data.
    var scenario: ScanScenario {
        switch inputData {
        case .aiParsed(let extraction, _, _):
            if extraction.confidenceScore > 0.0 {
                return .aiParsed
            } else {
                // Confidence 0 means network unavailable / fallback
                let hasOCR = !(extraction.discountDescription ?? "").isEmpty
                return hasOCR ? .ocrFallback : .barcodeOnly
            }
        case .barcodeOnly:
            return .barcodeOnly
        case .ocrTextOnly:
            return .ocrTextOnly
        }
    }

    /// The raw OCR text available for display (OCR fallback scenario).
    var rawOCRText: String? {
        switch inputData {
        case .aiParsed(let extraction, _, _):
            return extraction.discountDescription
        case .ocrTextOnly(let text, _):
            return text
        default:
            return nil
        }
    }

    /// The original image data from the scan.
    var originalImageData: Data? {
        switch inputData {
        case .aiParsed(_, _, let data): return data
        case .barcodeOnly(_, let data): return data
        case .ocrTextOnly(_, let data): return data
        }
    }

    /// The detected barcode (if any).
    var detectedBarcode: DetectedBarcode? {
        switch inputData {
        case .aiParsed(_, let barcode, _): return barcode
        case .barcodeOnly(let barcode, _): return barcode
        case .ocrTextOnly: return nil
        }
    }

    /// Whether the form can be saved (basic validation).
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Init

    /// Creates a new `ScanResultsViewModel` with the given scan input data.
    ///
    /// - Parameter inputData: The scan result to display and optionally pre-populate.
    init(inputData: ScanInputData) {
        self.inputData = inputData
        populateFields()
    }

    // MARK: - Field Population

    /// Populates form fields from the scan input data.
    private func populateFields() {
        switch inputData {

        case .aiParsed(let extraction, let barcode, _):
            // Populate from AI extraction result
            title = extraction.title ?? ""
            code = extraction.code ?? ""
            storeName = extraction.storeName ?? ""
            dvgType = extraction.dvgType ?? .discountCode
            discountDescription = extraction.discountDescription ?? ""
            originalValueText = extraction.originalValue.map { String($0) } ?? ""
            termsAndConditions = extraction.termsAndConditions ?? ""
            fieldConfidences = extraction.fieldConfidences
            overallConfidence = extraction.confidenceScore

            if let date = extraction.expirationDate {
                hasExpirationDate = true
                expirationDate = date
            }

            // Also set barcode fields if barcode was detected
            if let bc = barcode {
                barcodeType = bc.barcodeType
                decodedBarcodeValue = bc.value
                // Separate URLs from codes: URLs go to websiteURL, codes go to code
                if isURL(bc.value) {
                    websiteURL = bc.value
                } else if code.isEmpty {
                    code = bc.value
                }
            }

            showFullForm = extraction.confidenceScore > 0.0

        case .barcodeOnly(let barcode, _):
            // Pre-populate from barcode detection only
            barcodeType = barcode.barcodeType
            decodedBarcodeValue = barcode.value
            // Separate URLs from codes
            if isURL(barcode.value) {
                websiteURL = barcode.value
            } else {
                code = barcode.value
            }
            dvgType = .barcodeCoupon
            showFullForm = false

        case .ocrTextOnly(let text, _):
            // OCR only: pre-fill description with raw text as a hint
            discountDescription = text
            showFullForm = false
        }
    }

    // MARK: - Confidence Color

    /// Returns the semantic color for a given confidence score.
    ///
    /// - Green (>= 0.8): high confidence
    /// - Yellow (0.5 – 0.8): medium confidence
    /// - Red (< 0.5): low confidence
    func confidenceColor(for score: Double) -> Color {
        if score >= 0.8 {
            return Theme.Colors.success
        } else if score >= 0.5 {
            return Theme.Colors.warning
        } else {
            return Theme.Colors.error
        }
    }

    /// Returns the confidence score for a named field, or nil if unavailable.
    func confidence(for fieldName: String) -> Double? {
        guard !fieldConfidences.isEmpty else { return nil }
        return fieldConfidences[fieldName]
    }

    // MARK: - Save

    /// Creates a DVG with `source = .scan` plus a linked `ScanResult`,
    /// then saves both via the provided `ModelContext`.
    ///
    /// - Parameter modelContext: The SwiftData context to use for saving.
    func saveDVG(modelContext: ModelContext) async {
        guard canSave, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            // 1. Build the DVG
            let dvg = DVG(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                barcodeImageData: detectedBarcode?.imageData,
                barcodeType: barcodeType,
                decodedBarcodeValue: decodedBarcodeValue,
                dvgType: dvgType,
                storeName: storeName.trimmingCharacters(in: .whitespacesAndNewlines),
                originalValue: Double(originalValueText) ?? 0.0,
                discountDescription: discountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                expirationDate: hasExpirationDate ? expirationDate : nil,
                source: .scan,
                termsAndConditions: termsAndConditions.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // 2. Build the ScanResult
            let sourceType = determineScanSourceType()
            let rawText = buildRawText()
            let fieldConfidencesJSON = encodeFieldConfidences()
            let needsReview = overallConfidence > 0.0 && overallConfidence < 0.7

            let scanResult = ScanResult(
                sourceType: sourceType,
                rawText: rawText,
                confidenceScore: overallConfidence,
                needsReview: needsReview,
                originalImageData: originalImageData
            )
            scanResult.fieldConfidencesJSON = fieldConfidencesJSON

            // 3. Link them together
            dvg.scanResult = scanResult
            scanResult.dvg = dvg

            // 4. Insert both into SwiftData
            modelContext.insert(dvg)
            modelContext.insert(scanResult)

            try modelContext.save()

            saveSucceeded = true

        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    // MARK: - Private Helpers

    /// Returns `true` if the given string looks like a URL (starts with http:// or https://).
    private func isURL(_ string: String) -> Bool {
        let lowered = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    /// Determines the appropriate `ScanSourceType` based on the input data.
    private func determineScanSourceType() -> ScanSourceType {
        switch inputData {
        case .barcodeOnly:
            return .camera
        case .aiParsed, .ocrTextOnly:
            return .import_
        }
    }

    /// Builds the raw text representation for the `ScanResult`.
    private func buildRawText() -> String {
        switch inputData {
        case .aiParsed(let extraction, let barcode, _):
            var parts: [String] = []
            if let bc = barcode { parts.append("Barcode: \(bc.value)") }
            if let desc = extraction.discountDescription, !desc.isEmpty { parts.append(desc) }
            return parts.joined(separator: "\n")

        case .barcodeOnly(let barcode, _):
            return barcode.value

        case .ocrTextOnly(let text, _):
            return text
        }
    }

    /// JSON-encodes the field confidence dictionary for storage.
    private func encodeFieldConfidences() -> String {
        guard !fieldConfidences.isEmpty,
              let data = try? JSONEncoder().encode(fieldConfidences),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}

// MARK: - ScanScenario

/// The display scenario for the scan results view.
enum ScanScenario {
    /// AI parsing succeeded with confidence > 0.
    case aiParsed
    /// Only a barcode was detected (no AI parsing or confidence == 0 without OCR).
    case barcodeOnly
    /// OCR text is available but AI parsing failed or was not attempted.
    case ocrFallback
    /// Only raw OCR text, no barcode and no AI.
    case ocrTextOnly
}
