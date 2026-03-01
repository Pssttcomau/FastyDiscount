import Foundation
import PassKit
import UIKit

// MARK: - PassKitServiceError

/// Typed errors thrown by `PassKitService` operations.
enum PassKitServiceError: LocalizedError, Sendable {
    case passesNotSupported
    case passGenerationFailed(String)
    case passAdditionFailed(String)
    case passRemovalFailed(String)
    case passNotFound(UUID)
    case signingRequired
    case invalidBarcodeType(String)
    case invalidPassData

    var errorDescription: String? {
        switch self {
        case .passesNotSupported:
            return "This device does not support adding passes to Apple Wallet."
        case .passGenerationFailed(let detail):
            return "Failed to generate pass: \(detail)"
        case .passAdditionFailed(let detail):
            return "Failed to add pass to wallet: \(detail)"
        case .passRemovalFailed(let detail):
            return "Failed to remove pass from wallet: \(detail)"
        case .passNotFound(let id):
            return "No wallet pass found for DVG \(id)."
        case .signingRequired:
            return "Pass signing is required. A server-side signing service must be configured for production use."
        case .invalidBarcodeType(let type):
            return "Barcode type '\(type)' is not supported for Apple Wallet passes."
        case .invalidPassData:
            return "The generated pass data is invalid."
        }
    }
}

// MARK: - PassBarcodeFormat

/// String constants for barcode formats used in Apple Wallet pass.json files.
///
/// These correspond to `PKBarcodeFormat` values but are represented as strings
/// because `PKBarcodeFormat` is not available on the iOS Simulator. Using string
/// constants ensures the pass.json is correctly formatted regardless of build target.
enum PassBarcodeFormat: String, Sendable {
    case qr = "PKBarcodeFormatQR"
    case pdf417 = "PKBarcodeFormatPDF417"
    case aztec = "PKBarcodeFormatAztec"
    case code128 = "PKBarcodeFormatCode128"
}

// MARK: - DVGPassSnapshot

/// A `Sendable` value-type snapshot of DVG fields needed for pass generation.
///
/// Extracts only the data needed for PassKit operations from the SwiftData model,
/// enabling safe transfer across actor boundaries under Swift 6 strict concurrency.
struct DVGPassSnapshot: Sendable {
    let id: UUID
    let title: String
    let storeName: String
    let code: String
    let decodedBarcodeValue: String
    let discountDescription: String
    let barcodeType: BarcodeType
    let dvgType: DVGType
    let expirationDate: Date?
    let status: DVGStatus

    /// The barcode message to encode in the pass. Prefers `code`, falls back
    /// to `decodedBarcodeValue`.
    var barcodeMessage: String {
        code.isEmpty ? decodedBarcodeValue : code
    }

    /// Whether this DVG has barcode data suitable for an Apple Wallet pass.
    var isWalletEligible: Bool {
        let hasBarcode = barcodeType != .text
        let hasMessage = !barcodeMessage.isEmpty
        let isActive = status == .active
        return hasBarcode && hasMessage && isActive
    }

    /// Creates a snapshot from a live DVG model object.
    ///
    /// Must be called on `@MainActor` (where `DVG` lives).
    @MainActor
    init(dvg: DVG) {
        self.id = dvg.id
        self.title = dvg.title
        self.storeName = dvg.storeName
        self.code = dvg.code
        self.decodedBarcodeValue = dvg.decodedBarcodeValue
        self.discountDescription = dvg.discountDescription
        self.barcodeType = dvg.barcodeTypeEnum
        self.dvgType = dvg.dvgTypeEnum
        self.expirationDate = dvg.expirationDate
        self.status = dvg.statusEnum
    }
}

// MARK: - PassKitService Protocol

/// Service abstraction for Apple Wallet pass operations on DVG items.
///
/// Provides methods to generate, add, remove, and check passes in Apple Wallet.
/// Implementations must be `Sendable` for Swift 6 strict concurrency.
@MainActor
protocol PassKitService: AnyObject, Sendable {

    /// Generates pass data for the given DVG.
    ///
    /// Returns the structured pass data that would be used to create
    /// a `.pkpass` file. In v1, this prepares all pass content but does not perform
    /// cryptographic signing (which requires server-side infrastructure).
    ///
    /// - Parameter dvg: Snapshot of the DVG to generate a pass for.
    /// - Returns: The pass data ready for signing.
    /// - Throws: `PassKitServiceError` if the DVG is not eligible or generation fails.
    func generatePass(for dvg: DVGPassSnapshot) throws -> PassData

    /// Presents the pass to the user for addition to Apple Wallet.
    ///
    /// In v1, this creates a `PKAddPassesViewController` with the pass data.
    /// Full signing is noted as a requirement for production.
    ///
    /// - Parameter passData: The pass data to present.
    /// - Throws: `PassKitServiceError` if the device does not support passes
    ///   or the addition fails.
    func addPass(_ passData: PassData) async throws

    /// Removes the wallet pass associated with the given DVG, if one exists.
    ///
    /// Searches the user's pass library for a pass matching the DVG's serial number
    /// and pass type identifier.
    ///
    /// - Parameter dvg: Snapshot of the DVG whose pass should be removed.
    /// - Throws: `PassKitServiceError` if removal fails.
    func removePass(for dvg: DVGPassSnapshot) throws

    /// Returns whether a wallet pass for the given DVG is currently in the user's
    /// pass library.
    ///
    /// - Parameter dvg: Snapshot of the DVG to check.
    /// - Returns: `true` if a matching pass is found in Apple Wallet.
    func isPassAdded(for dvg: DVGPassSnapshot) -> Bool

    /// Returns whether the current device supports adding passes to Apple Wallet.
    ///
    /// Wraps `PKAddPassesViewController.canAddPasses()`.
    static func canAddPasses() -> Bool
}

// MARK: - PassData

/// Structured representation of a `.pkpass` file's contents before signing.
///
/// Contains the `pass.json` dictionary and associated metadata. In v1, this is
/// used to prepare pass content; actual `.pkpass` file creation requires
/// server-side signing with a Pass Type ID certificate.
///
/// Uses `@unchecked Sendable` because the `passJSON` dictionary contains only
/// value types (`String`, `Int`, `Double`, `Bool`, and nested arrays/dictionaries
/// of those types), which are safe to share across concurrency boundaries.
struct PassData: @unchecked Sendable {
    /// The pass.json content as a dictionary.
    let passJSON: [String: Any]

    /// The DVG ID this pass represents (used as serial number).
    let serialNumber: String

    /// The pass type identifier.
    let passTypeIdentifier: String

    /// Human-readable description of what this pass contains.
    let passDescription: String
}

// MARK: - AppleWalletPassKitService

/// Concrete `PassKitService` implementation that generates Apple Wallet coupon passes
/// for barcoded DVG items.
///
/// ### v1 Limitations
/// This service fully implements pass data generation including barcode encoding,
/// field layout, and pass structure. However, creating a valid `.pkpass` file
/// requires cryptographic signing with a Pass Type ID certificate, which needs
/// server-side infrastructure. The service is designed so that:
///
/// 1. `generatePass(for:)` creates the complete pass data structure.
/// 2. `addPass(_:)` documents the signing requirement and provides the
///    presentation flow for when signing is available.
/// 3. All other methods (`removePass`, `isPassAdded`) work with the PKPassLibrary.
///
/// ### Pass Structure (Coupon type)
/// - **Header**: Store name
/// - **Primary**: Discount description
/// - **Secondary**: Redemption code
/// - **Auxiliary**: Expiry date
/// - **Barcode**: QR, Code128, PDF417, or Aztec based on DVG barcode type
@Observable
@MainActor
final class AppleWalletPassKitService: PassKitService {

    // MARK: - Constants

    /// Pass type identifier registered in Apple Developer portal.
    static let passTypeIdentifier = AppConstants.PassKit.passTypeIdentifier

    /// Team identifier from Apple Developer account.
    static let teamIdentifier = AppConstants.PassKit.teamIdentifier

    /// Organization name displayed on the pass.
    static let defaultOrganizationName = AppConstants.PassKit.organizationName

    // MARK: - State

    /// Whether a pass operation is currently in progress.
    private(set) var isProcessing: Bool = false

    /// Error message from the most recent operation, if any.
    private(set) var lastError: String?

    // MARK: - Static

    static func canAddPasses() -> Bool {
        PKAddPassesViewController.canAddPasses()
    }

    // MARK: - Generate Pass

    func generatePass(for dvg: DVGPassSnapshot) throws -> PassData {
        guard dvg.isWalletEligible else {
            throw PassKitServiceError.passGenerationFailed(
                "DVG is not eligible for Apple Wallet. It must have a barcode type, "
                + "a barcode message, and be in active status."
            )
        }

        let barcodeFormat = try passBarcodeFormat(for: dvg.barcodeType)

        // Build pass.json structure
        var passDict: [String: Any] = [:]

        // Required top-level keys
        passDict["formatVersion"] = 1
        passDict["passTypeIdentifier"] = Self.passTypeIdentifier
        passDict["serialNumber"] = dvg.id.uuidString
        passDict["teamIdentifier"] = Self.teamIdentifier
        passDict["organizationName"] = dvg.storeName.isEmpty
            ? Self.defaultOrganizationName
            : dvg.storeName
        passDict["description"] = dvg.title.isEmpty
            ? "Discount Coupon"
            : dvg.title

        // Visual appearance
        passDict["foregroundColor"] = "rgb(255, 255, 255)"
        passDict["backgroundColor"] = "rgb(13, 148, 136)"  // Teal brand color
        passDict["labelColor"] = "rgb(255, 255, 255)"

        // Barcode
        let barcodeDict: [String: Any] = [
            "message": dvg.barcodeMessage,
            "format": barcodeFormat.rawValue,
            "messageEncoding": "iso-8859-1"
        ]
        passDict["barcodes"] = [barcodeDict]
        // Legacy single barcode field for older iOS versions
        passDict["barcode"] = barcodeDict

        // Coupon-specific fields
        var couponDict: [String: Any] = [:]

        // Header fields: store name
        if !dvg.storeName.isEmpty {
            couponDict["headerFields"] = [
                [
                    "key": "store",
                    "label": "STORE",
                    "value": dvg.storeName
                ] as [String: Any]
            ]
        }

        // Primary fields: discount description
        let primaryValue = dvg.discountDescription.isEmpty
            ? dvg.title
            : dvg.discountDescription
        couponDict["primaryFields"] = [
            [
                "key": "discount",
                "label": "OFFER",
                "value": primaryValue
            ] as [String: Any]
        ]

        // Secondary fields: redemption code
        couponDict["secondaryFields"] = [
            [
                "key": "code",
                "label": "CODE",
                "value": dvg.barcodeMessage
            ] as [String: Any]
        ]

        // Auxiliary fields: expiry date
        if let expiryDate = dvg.expirationDate {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate]
            let dateString = isoFormatter.string(from: expiryDate)

            couponDict["auxiliaryFields"] = [
                [
                    "key": "expiry",
                    "label": "EXPIRES",
                    "value": dateString,
                    "dateStyle": "PKDateStyleMedium"
                ] as [String: Any]
            ]

            // Set pass expiration
            let fullISOFormatter = ISO8601DateFormatter()
            passDict["expirationDate"] = fullISOFormatter.string(from: expiryDate)
        }

        // Back fields: additional information
        var backFields: [[String: Any]] = []

        if !dvg.title.isEmpty {
            backFields.append([
                "key": "title",
                "label": "Title",
                "value": dvg.title
            ])
        }

        if !dvg.discountDescription.isEmpty {
            backFields.append([
                "key": "description",
                "label": "Description",
                "value": dvg.discountDescription
            ])
        }

        backFields.append([
            "key": "type",
            "label": "Type",
            "value": dvg.dvgType.displayName
        ])

        if !backFields.isEmpty {
            couponDict["backFields"] = backFields
        }

        passDict["coupon"] = couponDict

        return PassData(
            passJSON: passDict,
            serialNumber: dvg.id.uuidString,
            passTypeIdentifier: Self.passTypeIdentifier,
            passDescription: dvg.title.isEmpty ? "Discount Coupon" : dvg.title
        )
    }

    // MARK: - Add Pass

    func addPass(_ passData: PassData) async throws {
        guard Self.canAddPasses() else {
            throw PassKitServiceError.passesNotSupported
        }

        isProcessing = true
        defer { isProcessing = false }

        // v1 Note: Creating a valid PKPass requires a signed .pkpass bundle.
        // The signing process requires:
        // 1. A Pass Type ID certificate from Apple Developer portal
        // 2. The certificate's private key
        // 3. Apple's WWDR intermediate certificate
        // 4. Creating a PKCS#7 detached signature of the manifest
        //
        // This is typically done server-side. For v1, we prepare all the pass data
        // and throw a descriptive error indicating signing is needed.
        //
        // When a signing backend is available, the flow will be:
        // 1. Send passData.passJSON to the signing service
        // 2. Receive signed .pkpass data
        // 3. Create PKPass(data: signedData)
        // 4. Present via PKAddPassesViewController

        throw PassKitServiceError.signingRequired
    }

    // MARK: - Remove Pass

    func removePass(for dvg: DVGPassSnapshot) throws {
        let passLibrary = PKPassLibrary()
        let passes = passLibrary.passes()

        guard let matchingPass = passes.first(where: { pass in
            pass.serialNumber == dvg.id.uuidString
            && pass.passTypeIdentifier == Self.passTypeIdentifier
        }) else {
            throw PassKitServiceError.passNotFound(dvg.id)
        }

        passLibrary.removePass(matchingPass)
    }

    // MARK: - Is Pass Added

    func isPassAdded(for dvg: DVGPassSnapshot) -> Bool {
        let passLibrary = PKPassLibrary()
        let passes = passLibrary.passes()

        return passes.contains { pass in
            pass.serialNumber == dvg.id.uuidString
            && pass.passTypeIdentifier == Self.passTypeIdentifier
        }
    }

    // MARK: - Barcode Mapping

    /// Maps a `BarcodeType` to the corresponding `PassBarcodeFormat` string constant.
    ///
    /// Not all barcode types have a direct PassKit equivalent. Types without
    /// a mapping fall back to Code 128 where possible, or throw an error.
    ///
    /// Supported mappings:
    /// - `.qr` -> `PKBarcodeFormatQR`
    /// - `.pdf417` -> `PKBarcodeFormatPDF417`
    /// - `.code128`, `.code39`, `.upcA`, `.upcE`, `.ean8`, `.ean13` -> `PKBarcodeFormatCode128`
    /// - `.text` -> throws (no barcode representation)
    private func passBarcodeFormat(for barcodeType: BarcodeType) throws -> PassBarcodeFormat {
        switch barcodeType {
        case .qr:
            return .qr
        case .pdf417:
            return .pdf417
        case .code128, .code39, .upcA, .upcE, .ean8, .ean13:
            // Code 128 is a superset that can encode all these 1D formats
            return .code128
        case .text:
            throw PassKitServiceError.invalidBarcodeType("text")
        }
    }
}

// MARK: - PassData JSON Serialization

extension PassData {

    /// Serializes the pass.json dictionary to JSON data.
    ///
    /// - Returns: UTF-8 encoded JSON data.
    /// - Throws: If serialization fails.
    func jsonData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: passJSON,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
