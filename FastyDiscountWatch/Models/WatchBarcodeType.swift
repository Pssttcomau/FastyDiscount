import Foundation

// MARK: - WatchBarcodeType

/// The barcode format used to encode the DVG redemption value.
/// Mirrors the iOS app's BarcodeType enum but is self-contained for the watchOS target.
enum WatchBarcodeType: String, Codable, CaseIterable, Sendable {
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

    /// Whether this barcode type produces a 2D barcode (QR, PDF417) as opposed to 1D.
    var is2D: Bool {
        switch self {
        case .qr, .pdf417:
            return true
        default:
            return false
        }
    }
}
