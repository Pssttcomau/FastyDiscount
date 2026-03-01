import Foundation

// MARK: - DVGSource

/// Represents how a DVG (Discount/Voucher/GiftCard) was created.
/// Placeholder definition; full implementation in a later task.
enum DVGSource: String, Hashable, Sendable {
    case manual
    case emailScan
    case cameraScan
    case shareExtension
}

// MARK: - AppDestination

/// All possible navigation destinations within the app.
///
/// Used with `NavigationStack`'s `.navigationDestination(for:)` modifier
/// to provide type-safe, programmatic navigation. Each case carries any
/// parameters needed to construct the destination view.
enum AppDestination: Hashable, Sendable {
    case dvgDetail(UUID)
    case dvgEdit(UUID)
    case dvgCreate(DVGSource)
    case emailScanResults
    case reviewQueue
    case tagManager
    case storeLocationPicker(UUID)
}
