import Foundation
import SwiftData
import SwiftUI

// MARK: - DVGType

/// The category of discount/voucher/gift-card item.
///
/// String-backed so SwiftData can persist the raw value natively.
/// iOS 26+ SwiftData handles RawRepresentable enums natively.
enum DVGType: String, Codable, CaseIterable, Sendable {
    case discountCode   = "discountCode"
    case voucher        = "voucher"
    case giftCard       = "giftCard"
    case loyaltyPoints  = "loyaltyPoints"
    case barcodeCoupon  = "barcodeCoupon"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .discountCode:   return "Discount Code"
        case .voucher:        return "Voucher"
        case .giftCard:       return "Gift Card"
        case .loyaltyPoints:  return "Loyalty Points"
        case .barcodeCoupon:  return "Barcode Coupon"
        }
    }
}

// MARK: - DVGStatus

/// The lifecycle state of a DVG item.
enum DVGStatus: String, Codable, CaseIterable, Sendable {
    case active   = "active"
    case used     = "used"
    case expired  = "expired"
    case archived = "archived"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .active:   return "Active"
        case .used:     return "Used"
        case .expired:  return "Expired"
        case .archived: return "Archived"
        }
    }
}

// MARK: - DVGSource

/// How the DVG item was added to the app.
enum DVGSource: String, Codable, CaseIterable, Hashable, Sendable {
    case manual = "manual"
    case email  = "email"
    case scan   = "scan"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .manual: return "Manual Entry"
        case .email:  return "Email"
        case .scan:   return "Camera Scan"
        }
    }
}

// MARK: - BarcodeType

/// The barcode format used to encode the DVG redemption value.
enum BarcodeType: String, Codable, CaseIterable, Sendable {
    case qr      = "qr"
    case upcA    = "upcA"
    case upcE    = "upcE"
    case ean8    = "ean8"
    case ean13   = "ean13"
    case pdf417  = "pdf417"
    case code128 = "code128"
    case code39  = "code39"
    case text    = "text"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .qr:      return "QR Code"
        case .upcA:    return "UPC-A"
        case .upcE:    return "UPC-E"
        case .ean8:    return "EAN-8"
        case .ean13:   return "EAN-13"
        case .pdf417:  return "PDF417"
        case .code128: return "Code 128"
        case .code39:  return "Code 39"
        case .text:    return "Text"
        }
    }
}

// MARK: - DVG Model

/// The primary SwiftData model representing a Discount / Voucher / Gift-card item.
///
/// ### CloudKit Compatibility
/// - No unique constraints — deduplication is handled at the repository layer.
/// - All relationship properties are optional (CloudKit requirement).
/// - `barcodeImageData` uses `.externalStorage` to avoid CloudKit record size limits.
/// - `isDeleted` implements a soft-delete pattern required by CloudKit sync.
/// - All non-optional properties have default values so CloudKit can create records
///   without requiring every field.
/// - `Double` is used for currency values; `Decimal` is not supported by CloudKit.
@Model
final class DVG {

    // MARK: - Identity

    /// Stable identifier for the item. Generated at creation time.
    var id: UUID = UUID()

    /// Human-readable title, e.g. "20% off your next order".
    var title: String = ""

    /// Redemption code string, e.g. "SAVE20". May be empty for barcode-only items.
    var code: String = ""

    // MARK: - Barcode

    /// PNG / JPEG image data for the rendered barcode, stored externally in
    /// CloudKit to avoid record-size limits (max 1 MB per field).
    @Attribute(.externalStorage)
    var barcodeImageData: Data?

    /// The barcode format stored as a raw String for SwiftData/CloudKit persistence.
    /// Access via the type-safe `barcodeTypeEnum` computed property.
    var barcodeType: String = BarcodeType.text.rawValue

    /// The decoded string value embedded in the barcode (e.g. a URL or code).
    var decodedBarcodeValue: String = ""

    // MARK: - Classification

    /// The DVG category stored as a raw String.
    /// Access via the type-safe `dvgTypeEnum` computed property.
    var dvgType: String = DVGType.discountCode.rawValue

    // MARK: - Retailer

    /// Name of the store or brand offering this promotion.
    var storeName: String = ""

    // MARK: - Value

    /// Face value / monetary amount (e.g. 50.0 for a $50 gift card).
    /// Uses `Double` because CloudKit does not support `Decimal`.
    var originalValue: Double = 0.0

    /// Current remaining balance (relevant for gift cards).
    var remainingBalance: Double = 0.0

    /// Loyalty points balance (relevant for loyalty programmes).
    var pointsBalance: Double = 0.0

    // MARK: - Description & Terms

    /// Free-text description of the discount (e.g. "20% off all items").
    var discountDescription: String = ""

    /// Minimum spend required to redeem this offer, `0.0` if none.
    var minimumSpend: Double = 0.0

    /// Any terms and conditions text associated with the promotion.
    var termsAndConditions: String = ""

    // MARK: - Dates

    /// Expiration date of the promotion. `nil` means no expiry.
    var expirationDate: Date?

    /// Timestamp when the item was first added to the app.
    var dateAdded: Date = Date()

    /// Timestamp of the most recent write. Updated by the repository layer before
    /// persisting any change (not auto-updated in the model itself to preserve
    /// CloudKit conflict-resolution determinism).
    var lastModified: Date = Date()

    // MARK: - Metadata

    /// How the item was added. Stored as a raw String.
    /// Access via the type-safe `sourceEnum` computed property.
    var source: String = DVGSource.manual.rawValue

    /// Current lifecycle status. Stored as a raw String.
    /// Access via the type-safe `statusEnum` computed property.
    var status: String = DVGStatus.active.rawValue

    /// Free-text notes entered by the user.
    var notes: String = ""

    /// Whether the user has marked this item as a favourite.
    var isFavorite: Bool = false

    // MARK: - Notifications & Geofencing

    /// Number of days before expiry at which to send a reminder notification.
    /// `0` means no notification.
    var notificationLeadDays: Int = 0

    /// Radius in metres for a geofence-based reminder. `0.0` means no geofence.
    var geofenceRadius: Double = 0.0

    // MARK: - Soft Delete (CloudKit)

    /// Soft-delete flag used by the CloudKit sync pattern.
    /// Items with `isDeleted == true` are filtered out by the repository and
    /// eventually purged; SwiftData's physical deletion is deferred.
    var isDeleted: Bool = false

    // MARK: - Relationships

    /// Store-location objects associated with this DVG (geofence targets).
    /// Uses `.nullify` delete rule for CloudKit compatibility (cascade is handled
    /// at the application layer). Optional per CloudKit requirement.
    @Relationship(deleteRule: .nullify)
    var storeLocations: [StoreLocation]? = nil

    /// User-defined tags attached to this item.
    /// Uses `.nullify` delete rule for CloudKit compatibility. Optional per CloudKit requirement.
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]? = nil

    /// Raw scan result captured during barcode/camera scan, if any.
    /// Uses `.nullify` delete rule for CloudKit compatibility. Optional per CloudKit requirement.
    @Relationship(deleteRule: .nullify)
    var scanResult: ScanResult? = nil

    // MARK: - Init

    /// Creates a new DVG with sensible defaults for all optional fields.
    init(
        id: UUID = UUID(),
        title: String = "",
        code: String = "",
        barcodeImageData: Data? = nil,
        barcodeType: BarcodeType = .text,
        decodedBarcodeValue: String = "",
        dvgType: DVGType = .discountCode,
        storeName: String = "",
        originalValue: Double = 0.0,
        remainingBalance: Double = 0.0,
        pointsBalance: Double = 0.0,
        discountDescription: String = "",
        minimumSpend: Double = 0.0,
        expirationDate: Date? = nil,
        dateAdded: Date = Date(),
        source: DVGSource = .manual,
        status: DVGStatus = .active,
        notes: String = "",
        isFavorite: Bool = false,
        termsAndConditions: String = "",
        notificationLeadDays: Int = 0,
        geofenceRadius: Double = 0.0,
        isDeleted: Bool = false,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.code = code
        self.barcodeImageData = barcodeImageData
        self.barcodeType = barcodeType.rawValue
        self.decodedBarcodeValue = decodedBarcodeValue
        self.dvgType = dvgType.rawValue
        self.storeName = storeName
        self.originalValue = originalValue
        self.remainingBalance = remainingBalance
        self.pointsBalance = pointsBalance
        self.discountDescription = discountDescription
        self.minimumSpend = minimumSpend
        self.expirationDate = expirationDate
        self.dateAdded = dateAdded
        self.source = source.rawValue
        self.status = status.rawValue
        self.notes = notes
        self.isFavorite = isFavorite
        self.termsAndConditions = termsAndConditions
        self.notificationLeadDays = notificationLeadDays
        self.geofenceRadius = geofenceRadius
        self.isDeleted = isDeleted
        self.lastModified = lastModified
    }
}

// MARK: - Type-Safe Computed Properties

extension DVG {

    /// Type-safe accessor for the `barcodeType` raw-string property.
    var barcodeTypeEnum: BarcodeType {
        get { BarcodeType(rawValue: barcodeType) ?? .text }
        set { barcodeType = newValue.rawValue }
    }

    /// Type-safe accessor for the `dvgType` raw-string property.
    var dvgTypeEnum: DVGType {
        get { DVGType(rawValue: dvgType) ?? .discountCode }
        set { dvgType = newValue.rawValue }
    }

    /// Type-safe accessor for the `source` raw-string property.
    var sourceEnum: DVGSource {
        get { DVGSource(rawValue: source) ?? .manual }
        set { source = newValue.rawValue }
    }

    /// Type-safe accessor for the `status` raw-string property.
    var statusEnum: DVGStatus {
        get { DVGStatus(rawValue: status) ?? .active }
        set { status = newValue.rawValue }
    }
}

// MARK: - Computed Properties

extension DVG {

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

    /// Formatted display value appropriate for the DVG type.
    ///
    /// - Gift cards and vouchers show a currency-formatted remaining balance
    ///   (or original value if balance is zero).
    /// - Loyalty points show the points balance.
    /// - Discount codes show a percentage if `originalValue` looks like a percentage
    ///   (1–100 range), otherwise a currency amount.
    /// - Barcode coupons show the decoded barcode value or discount description.
    var displayValue: String {
        let currencyFormatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.maximumFractionDigits = 2
            f.minimumFractionDigits = 0
            return f
        }()

        switch dvgTypeEnum {
        case .giftCard:
            let balance = remainingBalance > 0 ? remainingBalance : originalValue
            return currencyFormatter.string(from: NSNumber(value: balance)) ?? "$\(balance)"

        case .voucher:
            if originalValue > 0 {
                return currencyFormatter.string(from: NSNumber(value: originalValue)) ?? "$\(originalValue)"
            }
            return discountDescription.isEmpty ? "Voucher" : discountDescription

        case .loyaltyPoints:
            let points = Int(pointsBalance)
            return "\(points) pts"

        case .discountCode:
            if originalValue > 0 && originalValue <= 100 {
                return "\(Int(originalValue))% off"
            } else if originalValue > 100 {
                return currencyFormatter.string(from: NSNumber(value: originalValue)) ?? "$\(originalValue)"
            }
            return discountDescription.isEmpty ? code : discountDescription

        case .barcodeCoupon:
            return decodedBarcodeValue.isEmpty ? discountDescription : decodedBarcodeValue
        }
    }

    /// A SwiftUI `Color` reflecting the current status of the item.
    var statusColor: Color {
        switch statusEnum {
        case .active:
            if let days = daysUntilExpiry, days <= 7 {
                return .orange   // Expiring soon
            }
            return .green
        case .used:     return .secondary
        case .expired:  return .red
        case .archived: return .gray
        }
    }
}

// MARK: - Preview Support

extension DVG {

    /// A sample DVG instance for use in SwiftUI previews and unit tests.
    static var preview: DVG {
        DVG(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "20% off your next order",
            code: "SAVE20",
            barcodeImageData: nil,
            barcodeType: .qr,
            decodedBarcodeValue: "SAVE20",
            dvgType: .discountCode,
            storeName: "FastyStore",
            originalValue: 20.0,
            remainingBalance: 0.0,
            pointsBalance: 0.0,
            discountDescription: "20% off all items storewide",
            minimumSpend: 50.0,
            expirationDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            dateAdded: Date(),
            source: .email,
            status: .active,
            notes: "From welcome email",
            isFavorite: true,
            termsAndConditions: "Valid on full-price items only. Cannot be combined with other offers.",
            notificationLeadDays: 3,
            geofenceRadius: 0.0,
            isDeleted: false,
            lastModified: Date()
        )
    }
}

