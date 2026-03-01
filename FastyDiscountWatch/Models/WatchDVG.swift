import Foundation
import SwiftUI

// MARK: - WatchDVG

/// Lightweight Codable struct representing a DVG on the Apple Watch.
///
/// This is a subset of the full iOS DVG model, containing only the fields
/// needed for display and barcode rendering on the watch. DVGs are synced
/// from the iPhone via Watch Connectivity and cached locally as JSON.
struct WatchDVG: Codable, Identifiable, Sendable, Hashable {

    // MARK: - Properties

    let id: UUID
    let title: String
    let storeName: String
    let code: String
    let barcodeType: String
    let dvgType: String
    let expirationDate: Date?
    let isFavorite: Bool
    let status: String

    // MARK: - Type-Safe Accessors

    /// Type-safe accessor for the barcode type.
    var barcodeTypeEnum: WatchBarcodeType {
        WatchBarcodeType(rawValue: barcodeType) ?? .text
    }

    /// Type-safe accessor for the DVG type.
    var dvgTypeEnum: WatchDVGType {
        WatchDVGType(rawValue: dvgType) ?? .discountCode
    }

    /// Type-safe accessor for the DVG status.
    var statusEnum: WatchDVGStatus {
        WatchDVGStatus(rawValue: status) ?? .active
    }

    // MARK: - Computed Properties

    /// Returns `true` if the item has an expiration date that is in the past.
    var isExpired: Bool {
        guard let expiry = expirationDate else { return false }
        return expiry < Date()
    }

    /// Number of whole days until the expiration date.
    /// Returns `nil` if there is no expiration date.
    /// Returns a negative number if already expired.
    var daysUntilExpiry: Int? {
        guard let expiry = expirationDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiry)
        return components.day
    }

    /// Human-readable text describing the time until expiration.
    var expiryText: String {
        guard let days = daysUntilExpiry else { return "No expiry" }
        switch days {
        case ..<0:
            return "Expired"
        case 0:
            return "Today"
        case 1:
            return "1 day left"
        default:
            return "\(days) days left"
        }
    }

    /// A SwiftUI `Color` reflecting the urgency of the expiration.
    var expiryColor: Color {
        guard let days = daysUntilExpiry else { return .secondary }
        switch days {
        case ..<0:
            return .red
        case 0...3:
            return .red
        case 4...7:
            return .orange
        default:
            return .green
        }
    }

    /// The value to encode into the barcode. Falls back to code if no decoded value.
    var barcodeValue: String {
        code
    }

    /// Whether this DVG is currently active (not used, expired, or archived).
    var isActive: Bool {
        statusEnum == .active && !isExpired
    }
}

// MARK: - Preview Support

extension WatchDVG {

    /// Sample DVGs for use in SwiftUI previews.
    static var previews: [WatchDVG] {
        [
            WatchDVG(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "20% off next order",
                storeName: "FastyStore",
                code: "SAVE20",
                barcodeType: WatchBarcodeType.qr.rawValue,
                dvgType: WatchDVGType.discountCode.rawValue,
                expirationDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                isFavorite: true,
                status: WatchDVGStatus.active.rawValue
            ),
            WatchDVG(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "$50 Gift Card",
                storeName: "TechShop",
                code: "GC-50-ABCDEF",
                barcodeType: WatchBarcodeType.code128.rawValue,
                dvgType: WatchDVGType.giftCard.rawValue,
                expirationDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                isFavorite: false,
                status: WatchDVGStatus.active.rawValue
            ),
            WatchDVG(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                title: "Free Coffee",
                storeName: "CafeBean",
                code: "COFFEE-FREE-123",
                barcodeType: WatchBarcodeType.qr.rawValue,
                dvgType: WatchDVGType.voucher.rawValue,
                expirationDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                isFavorite: true,
                status: WatchDVGStatus.active.rawValue
            ),
        ]
    }
}
