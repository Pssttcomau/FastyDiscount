import Foundation
import SwiftData

// MARK: - ScanSourceType

/// How the scan was captured.
enum ScanSourceType: String, Codable, CaseIterable, Sendable {
    case camera = "camera"
    case email  = "email"
    case import_ = "import"

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .camera:  return "Camera"
        case .email:   return "Email"
        case .import_: return "Import"
        }
    }
}

// MARK: - ScanResult Model

/// Captures the raw output of a barcode/image scan or email extraction,
/// linked one-to-one to the DVG it produced.
///
/// ### CloudKit Compatibility
/// - All relationship properties are optional (CloudKit requirement).
/// - `isDeleted` implements the soft-delete pattern required by CloudKit sync.
/// - All non-optional stored properties have default values.
/// - `originalImageData` uses `.externalStorage` to avoid CloudKit record-size
///   limits (max 1 MB per field).
@Model
final class ScanResult {

    // MARK: - Identity

    /// Stable identifier. Generated at creation time.
    var id: UUID = UUID()

    // MARK: - Scan Metadata

    /// How the scan was captured. Stored as a raw String for SwiftData persistence.
    /// Access via the type-safe `sourceTypeEnum` computed property.
    var sourceType: String = ScanSourceType.camera.rawValue

    /// The raw text extracted from the scanned image or email.
    var rawText: String = ""

    /// Model confidence score in the range 0.0–1.0.
    /// `1.0` means fully confident; `0.0` means unable to determine.
    var confidenceScore: Double = 0.0

    // MARK: - Review

    /// `true` if the extraction result requires human review before being accepted.
    var needsReview: Bool = false

    /// Timestamp when a user reviewed and approved/rejected the result.
    /// `nil` if the result has not been reviewed yet.
    var reviewedAt: Date?

    // MARK: - Source Image

    /// Original scan image stored externally to avoid CloudKit record-size limits.
    /// May be `nil` for email-sourced results or when the image was discarded.
    @Attribute(.externalStorage)
    var originalImageData: Data?

    // MARK: - Email Metadata

    /// Subject line of the source email (populated for `.email` source type).
    var emailSubject: String = ""

    /// Sender address of the source email.
    var emailSender: String = ""

    /// Date the source email was received.
    var emailDate: Date?

    // MARK: - Soft Delete (CloudKit)

    /// Soft-delete flag. Items marked `true` are filtered at the repository
    /// layer and eventually purged; physical deletion is deferred for CloudKit.
    var isDeleted: Bool = false

    // MARK: - Relationships

    /// The DVG item this scan result produced (inverse of `DVG.scanResult`).
    /// One-to-one; optional per CloudKit requirement.
    @Relationship(inverse: \DVG.scanResult)
    var dvg: DVG? = nil

    // MARK: - Init

    init(
        id: UUID = UUID(),
        sourceType: ScanSourceType = .camera,
        rawText: String = "",
        confidenceScore: Double = 0.0,
        needsReview: Bool = false,
        reviewedAt: Date? = nil,
        originalImageData: Data? = nil,
        emailSubject: String = "",
        emailSender: String = "",
        emailDate: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.sourceType = sourceType.rawValue
        self.rawText = rawText
        self.confidenceScore = confidenceScore
        self.needsReview = needsReview
        self.reviewedAt = reviewedAt
        self.originalImageData = originalImageData
        self.emailSubject = emailSubject
        self.emailSender = emailSender
        self.emailDate = emailDate
        self.isDeleted = isDeleted
    }
}

// MARK: - Type-Safe Computed Properties

extension ScanResult {

    /// Type-safe accessor for the `sourceType` raw-string property.
    var sourceTypeEnum: ScanSourceType {
        get { ScanSourceType(rawValue: sourceType) ?? .camera }
        set { sourceType = newValue.rawValue }
    }

    /// `true` if the result has been reviewed by a user.
    var isReviewed: Bool {
        reviewedAt != nil
    }
}

// MARK: - Preview Support

extension ScanResult {

    /// A sample `ScanResult` for use in SwiftUI previews and unit tests.
    static var preview: ScanResult {
        ScanResult(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            sourceType: .camera,
            rawText: "SAVE20",
            confidenceScore: 0.97,
            needsReview: false,
            reviewedAt: nil,
            originalImageData: nil,
            emailSubject: "",
            emailSender: "",
            emailDate: nil,
            isDeleted: false
        )
    }

    /// A sample email-sourced `ScanResult` for previews.
    static var previewEmail: ScanResult {
        ScanResult(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            sourceType: .email,
            rawText: "Use code WELCOME10 for 10% off your first order.",
            confidenceScore: 0.85,
            needsReview: true,
            reviewedAt: nil,
            originalImageData: nil,
            emailSubject: "Welcome to FastyStore — here's your discount",
            emailSender: "noreply@fastystore.com",
            emailDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            isDeleted: false
        )
    }
}
