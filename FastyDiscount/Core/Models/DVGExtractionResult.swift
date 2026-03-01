import Foundation

// MARK: - DVGType

/// Placeholder enum for the type of discount/voucher/gift card.
/// Full definition will be completed in TASK-007.
enum DVGType: String, Codable, Sendable, CaseIterable {
    case discount
    case voucher
    case giftCard
    case coupon
    case cashback
    case unknown
}

// MARK: - DVGExtractionResult

/// The structured result produced by the AI extraction pipeline when parsing
/// an email or image for discount/voucher/gift-card information.
///
/// Conforms to `Codable` so it can be serialised to/from JSON (used as the
/// AI response format and for persistence) and to `Sendable` so it can safely
/// cross concurrency boundaries in Swift 6 strict-concurrency mode.
struct DVGExtractionResult: Codable, Sendable {

    // MARK: - Properties

    /// Human-readable title for the deal (e.g. "20% off your next order").
    let title: String?

    /// The promotional code string the user needs to redeem (e.g. "SAVE20").
    let code: String?

    /// Category of the promotion.
    let dvgType: DVGType?

    /// Name of the store or brand offering the promotion.
    let storeName: String?

    /// Face / original monetary value, e.g. `50.0` for a $50 gift card.
    let originalValue: Double?

    /// Free-text description of the discount (e.g. "20% off all items").
    let discountDescription: String?

    /// Expiration date of the promotion, if detected.
    let expirationDate: Date?

    /// Any terms and conditions text associated with the promotion.
    let termsAndConditions: String?

    /// Overall confidence score for the extraction result, in the range 0.0 – 1.0.
    let confidenceScore: Double

    /// Per-field confidence scores keyed by field name, each in the range 0.0 – 1.0.
    let fieldConfidences: [String: Double]

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case title
        case code
        case dvgType
        case storeName
        case originalValue
        case discountDescription
        case expirationDate
        case termsAndConditions
        case confidenceScore
        case fieldConfidences
    }
}
