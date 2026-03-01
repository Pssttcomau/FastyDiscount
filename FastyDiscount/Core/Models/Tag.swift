import Foundation
import SwiftData

// MARK: - SystemTag

/// The set of built-in system tags seeded on first launch.
/// New cases added here will be created by `TagSeeder` on the next launch.
enum SystemTag: String, CaseIterable, Sendable {
    case food           = "Food"
    case clothing       = "Clothing"
    case electronics    = "Electronics"
    case beauty         = "Beauty"
    case home           = "Home"
    case travel         = "Travel"
    case entertainment  = "Entertainment"
    case health         = "Health"
    case automotive     = "Automotive"
    case other          = "Other"

    /// Default color hex string for each system tag.
    var defaultColorHex: String {
        switch self {
        case .food:          return "#FF6B35"
        case .clothing:      return "#9B5DE5"
        case .electronics:   return "#0077B6"
        case .beauty:        return "#F72585"
        case .home:          return "#4CC9F0"
        case .travel:        return "#06D6A0"
        case .entertainment: return "#FFD166"
        case .health:        return "#2DC653"
        case .automotive:    return "#EF233C"
        case .other:         return "#8D99AE"
        }
    }
}

// MARK: - Tag Model

/// A label that can be applied to one or more DVG items for organisation.
///
/// Tags are either system-generated (see `SystemTag`) or user-created.
///
/// ### CloudKit Compatibility
/// - All relationship properties are optional (CloudKit requirement).
/// - `isDeleted` implements the soft-delete pattern required by CloudKit sync.
/// - All non-optional stored properties have default values.
///
/// ### Relationships
/// - A `Tag` can be linked to multiple DVGs (many-to-many).
///   The inverse `dvgs` relationship is maintained by SwiftData automatically.
@Model
final class Tag {

    // MARK: - Identity

    /// Stable identifier. Generated at creation time.
    var id: UUID = UUID()

    /// Display name of the tag, e.g. "Food" or "My Custom Tag".
    var name: String = ""

    // MARK: - Classification

    /// `true` for tags seeded by `TagSeeder`; `false` for user-created tags.
    /// System tags cannot be deleted by the user.
    var isSystemTag: Bool = false

    /// Optional hex color string (e.g. `"#FF6B35"`) for UI display.
    /// `nil` means use the default accent color.
    var colorHex: String?

    // MARK: - Soft Delete (CloudKit)

    /// Soft-delete flag. Items marked `true` are filtered at the repository
    /// layer and eventually purged; physical deletion is deferred for CloudKit.
    var isDeleted: Bool = false

    // MARK: - Relationships

    /// DVG items that have this tag applied (inverse of `DVG.tags`).
    /// Optional per CloudKit requirement.
    @Relationship(inverse: \DVG.tags)
    var dvgs: [DVG]? = nil

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String = "",
        isSystemTag: Bool = false,
        colorHex: String? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isSystemTag = isSystemTag
        self.colorHex = colorHex
        self.isDeleted = isDeleted
    }
}

// MARK: - Convenience Init from SystemTag

extension Tag {

    /// Creates a `Tag` pre-populated from a `SystemTag` definition.
    convenience init(systemTag: SystemTag) {
        self.init(
            name: systemTag.rawValue,
            isSystemTag: true,
            colorHex: systemTag.defaultColorHex
        )
    }
}

// MARK: - Preview Support

extension Tag {

    /// A sample user-created `Tag` for use in SwiftUI previews and unit tests.
    static var preview: Tag {
        Tag(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            name: "Food",
            isSystemTag: true,
            colorHex: "#FF6B35",
            isDeleted: false
        )
    }

    /// A sample user-created `Tag` (non-system) for previews.
    static var previewCustom: Tag {
        Tag(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            name: "Weekend Deals",
            isSystemTag: false,
            colorHex: "#FFD166",
            isDeleted: false
        )
    }
}
