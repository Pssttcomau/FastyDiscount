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
}
