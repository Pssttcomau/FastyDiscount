import Foundation
import SwiftData
import CoreLocation

// MARK: - StoreLocation Model

/// A physical store location associated with one or more DVG items.
///
/// ### CloudKit Compatibility
/// - All relationship properties are optional (CloudKit requirement).
/// - `isDeleted` implements the soft-delete pattern required by CloudKit sync.
/// - All non-optional stored properties have default values so CloudKit can
///   create records without requiring every field to be present.
/// - `Double` is used for lat/lng; `Decimal` is not supported by CloudKit.
///
/// ### Relationships
/// - A `StoreLocation` can be linked to multiple DVGs (many-to-many).
///   The inverse `dvgs` relationship is maintained by SwiftData automatically.
@Model
final class StoreLocation {

    // MARK: - Identity

    /// Stable identifier. Generated at creation time.
    var id: UUID = UUID()

    /// Human-readable name of the store, e.g. "Westfield Sydney — Level 2".
    var name: String = ""

    // MARK: - Location

    /// WGS-84 latitude in decimal degrees.
    var latitude: Double = 0.0

    /// WGS-84 longitude in decimal degrees.
    var longitude: Double = 0.0

    /// Street address or formatted address string for display.
    var address: String = ""

    /// Apple/Google Maps place identifier. Optional — may be absent if the
    /// location was created manually without a maps lookup.
    var placeID: String?

    // MARK: - Soft Delete (CloudKit)

    /// Soft-delete flag. Items marked `true` are filtered at the repository
    /// layer and eventually purged; physical deletion is deferred for CloudKit.
    var isDeleted: Bool = false

    // MARK: - Relationships

    /// DVG items that reference this location (inverse of `DVG.storeLocations`).
    /// Optional per CloudKit requirement.
    @Relationship(inverse: \DVG.storeLocations)
    var dvgs: [DVG]? = nil

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String = "",
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        address: String = "",
        placeID: String? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.placeID = placeID
        self.isDeleted = isDeleted
    }
}

// MARK: - MapKit Integration

extension StoreLocation {

    /// A `CLLocationCoordinate2D` suitable for use with MapKit annotations.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Preview Support

extension StoreLocation {

    /// A sample `StoreLocation` instance for use in SwiftUI previews and unit tests.
    static var preview: StoreLocation {
        StoreLocation(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "FastyStore — City Centre",
            latitude: -33.8688,
            longitude: 151.2093,
            address: "1 Market Street, Sydney NSW 2000",
            placeID: "ChIJN1t_tDeuEmsRUsoyG83frY4",
            isDeleted: false
        )
    }
}
