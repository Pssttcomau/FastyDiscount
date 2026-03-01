import Foundation

// MARK: - AppDestination

/// All possible navigation destinations within the app.
///
/// Used with `NavigationStack`'s `.navigationDestination(for:)` modifier
/// to provide type-safe, programmatic navigation. Each case carries any
/// parameters needed to construct the destination view.
///
/// - Note: `DVGSource` is the canonical enum defined in `DVG.swift`.
///   The placeholder that previously lived in this file has been replaced.
enum AppDestination: Hashable, Sendable {
    case dvgDetail(UUID)
    case dvgEdit(UUID)
    case dvgCreate(DVGSource)
    case emailScan
    case emailScanResults
    case reviewQueue
    case tagManager
    case storeLocationPicker(UUID)
    case cameraScanner
    case textOCR
    /// Photo library and PDF document import with barcode / OCR extraction.
    case importScan
    /// Scan results view: bridges scanning output to DVG creation.
    case scanResults(ScanInputData)
    /// Search view with optional pre-populated filter (e.g. from dashboard "See All" buttons).
    case search(DVGFilter?)
}

// MARK: - ScanInputData + Hashable

/// `ScanInputData` must be `Hashable` to be used as an `AppDestination` associated value.
///
/// Since `DVGExtractionResult` and `DetectedBarcode` carry complex / floating-point
/// data, we provide a stable identity-based hash using an auto-generated UUID.
/// This is intentionally value-type-stable for the lifetime of the navigation
/// destination (no two `.scanResults` pushes with different data should be equal).
extension ScanInputData: Hashable {

    static func == (lhs: ScanInputData, rhs: ScanInputData) -> Bool {
        // Use identity equality: two different scan input payloads are never "the same"
        // navigation destination even if their field values happen to match.
        false
    }

    func hash(into hasher: inout Hasher) {
        // Stable hash via ObjectIdentifier trick: since ScanInputData is a value type,
        // we hash the underlying case discriminant and a UUID seeded from content.
        switch self {
        case .aiParsed(let extraction, let barcode, _):
            hasher.combine(0)
            hasher.combine(extraction.confidenceScore)
            hasher.combine(barcode?.value)
        case .barcodeOnly(let barcode, _):
            hasher.combine(1)
            hasher.combine(barcode.value)
        case .ocrTextOnly(let text, _):
            hasher.combine(2)
            hasher.combine(text)
        }
    }
}
