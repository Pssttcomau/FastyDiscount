import Foundation

// MARK: - WatchDVGType

/// The category of discount/voucher/gift-card item on the watch.
/// Mirrors the iOS app's DVGType enum but is self-contained for the watchOS target.
enum WatchDVGType: String, Codable, CaseIterable, Sendable {
    case discountCode  = "discountCode"
    case voucher       = "voucher"
    case giftCard      = "giftCard"
    case loyaltyPoints = "loyaltyPoints"
    case barcodeCoupon = "barcodeCoupon"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .discountCode:  return "Discount Code"
        case .voucher:       return "Voucher"
        case .giftCard:      return "Gift Card"
        case .loyaltyPoints: return "Loyalty Points"
        case .barcodeCoupon: return "Barcode Coupon"
        }
    }

    /// SF Symbol name representing this DVG type category.
    var iconName: String {
        switch self {
        case .discountCode:  return "percent"
        case .voucher:       return "ticket"
        case .giftCard:      return "giftcard"
        case .loyaltyPoints: return "star.circle"
        case .barcodeCoupon: return "barcode"
        }
    }
}

// MARK: - WatchDVGStatus

/// The lifecycle state of a DVG item on the watch.
enum WatchDVGStatus: String, Codable, CaseIterable, Sendable {
    case active   = "active"
    case used     = "used"
    case expired  = "expired"
    case archived = "archived"
}
