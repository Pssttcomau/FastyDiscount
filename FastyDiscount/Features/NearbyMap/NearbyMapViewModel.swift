import Foundation
import SwiftUI
import CoreLocation
import MapKit
import OSLog

// MARK: - StoreAnnotation

/// Represents a single store location on the map, grouping all active DVGs at that store.
///
/// Identified by the `StoreLocation.id` so that annotations are stable across data refreshes.
/// Contains the pre-computed distance string from the user's current location.
struct StoreAnnotation: Identifiable, Sendable {

    /// The unique identifier of the underlying `StoreLocation`.
    let id: UUID

    /// The coordinate for map placement.
    let coordinate: CLLocationCoordinate2D

    /// Human-readable store name.
    let name: String

    /// Street address for display in the summary card.
    let address: String

    /// Formatted distance from the user's current location (e.g. "350 m", "1.2 km").
    let distanceText: String

    /// Raw distance in metres, used for sorting and filtering.
    let distanceMetres: Double

    /// The DVG type of the first (or most relevant) DVG at this store.
    /// Used to determine the pin icon.
    let primaryDVGType: DVGType

    /// All active DVGs available at this store location.
    let dvgs: [DVGSummary]
}

// MARK: - DVGSummary

/// A lightweight, `Sendable` snapshot of a DVG for display in the map summary card.
///
/// Avoids passing the full `@Model` object across view boundaries, which would
/// require the model context to be available. The `id` is the DVG's UUID,
/// enabling navigation to the detail view.
struct DVGSummary: Identifiable, Sendable {

    let id: UUID
    let title: String
    let storeName: String
    let dvgType: DVGType
    let expirationDate: Date?
    let daysUntilExpiry: Int?
    let isFavorite: Bool

    /// Human-readable display value (e.g. "20% off", "$50.00").
    let displayValue: String
}

// MARK: - NearbyMapViewModel

/// ViewModel managing the nearby map state: annotations, selected store, search, and region.
///
/// ### Responsibilities
/// - Loads active DVGs with store locations from the repository.
/// - Groups DVGs by store location to build `StoreAnnotation` items.
/// - Manages the map camera region (initial center on user, re-center button).
/// - Handles search filtering by store name.
/// - Tracks the selected store annotation for the summary card.
///
/// ### Concurrency
/// `@Observable @MainActor` per project convention. All repository calls are async
/// on the main actor since `SwiftDataDVGRepository` is `@MainActor`.
@Observable
@MainActor
final class NearbyMapViewModel {

    // MARK: - Published State

    /// All store annotations derived from active DVGs with store locations.
    private(set) var annotations: [StoreAnnotation] = []

    /// The currently selected store annotation. Shown in the summary card.
    var selectedAnnotation: StoreAnnotation?

    /// The current map camera position.
    var cameraPosition: MapCameraPosition = .automatic

    /// Search text for filtering stores by name.
    var searchText: String = ""

    /// Whether the initial data load is in progress.
    private(set) var isLoading: Bool = false

    /// Whether data has been loaded at least once.
    private(set) var hasLoaded: Bool = false

    /// Error message for display in an alert.
    var errorMessage: String?

    /// Whether the error alert is visible.
    var showError: Bool = false

    // MARK: - Computed Properties

    /// Annotations filtered by the current search text.
    /// Returns all annotations when the search text is empty.
    var filteredAnnotations: [StoreAnnotation] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return annotations }
        let lowered = trimmed.lowercased()
        return annotations.filter { annotation in
            annotation.name.lowercased().contains(lowered)
        }
    }

    /// Whether the empty state should be shown (loaded but no store locations found).
    var showEmptyState: Bool {
        hasLoaded && annotations.isEmpty
    }

    // MARK: - Dependencies

    private let repository: any DVGRepository
    private let locationManager: LocationPermissionManager

    /// Search radius in metres for nearby DVG lookup.
    private let searchRadius: Double = 50_000 // 50 km — wide radius for map view

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FastyDiscount",
        category: "NearbyMapViewModel"
    )

    // MARK: - Init

    /// Creates a NearbyMapViewModel.
    ///
    /// - Parameters:
    ///   - repository: The DVG repository for data access.
    ///   - locationManager: The location permission manager for coordinate access.
    init(repository: any DVGRepository, locationManager: LocationPermissionManager) {
        self.repository = repository
        self.locationManager = locationManager
    }

    // MARK: - Load Data

    /// Loads all active DVGs with store locations and builds annotations.
    ///
    /// Centers the map on the user's current location with a ~5 km radius on
    /// the first load.
    func loadAnnotations() async {
        if !hasLoaded {
            isLoading = true
        }

        defer {
            isLoading = false
            hasLoaded = true
        }

        // Center map on user location if this is the first load
        if !hasLoaded {
            centerOnUserLocation()
        }

        guard let userLocation = locationManager.currentCLLocation else {
            // No location available — fetch all active DVGs and build annotations
            // without distance information.
            await loadAllActiveDVGs(userLocation: nil)
            return
        }

        await loadAllActiveDVGs(userLocation: userLocation)
    }

    /// Refreshes annotations. Called by pull-to-refresh or manual refresh.
    func refresh() async {
        guard let userLocation = locationManager.currentCLLocation else {
            await loadAllActiveDVGs(userLocation: nil)
            return
        }

        await loadAllActiveDVGs(userLocation: userLocation)
    }

    // MARK: - Map Actions

    /// Centers the map camera on the user's current location with a ~5 km span.
    func centerOnUserLocation() {
        guard let location = locationManager.currentCLLocation else {
            logger.warning("centerOnUserLocation called but no location available")
            return
        }

        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 5_000,
            longitudinalMeters: 5_000
        )
        cameraPosition = .region(region)
    }

    /// Selects a store annotation by ID. Called when a map pin is tapped.
    func selectAnnotation(_ annotation: StoreAnnotation) {
        selectedAnnotation = annotation
    }

    /// Deselects the current annotation. Called when the summary card is dismissed.
    func deselectAnnotation() {
        selectedAnnotation = nil
    }

    /// Opens Apple Maps with driving directions to the given store location.
    func openDirections(to annotation: StoreAnnotation) {
        let coordinate = annotation.coordinate
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = annotation.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Private Helpers

    /// Fetches all active DVGs and builds store annotations.
    private func loadAllActiveDVGs(userLocation: CLLocation?) async {
        do {
            let activeDVGs = try await repository.fetchActive()
            buildAnnotations(from: activeDVGs, userLocation: userLocation)
            logger.info("Built \(self.annotations.count) store annotations from \(activeDVGs.count) active DVGs")
        } catch {
            handleError(error, context: "loading nearby stores")
        }
    }

    /// Groups DVGs by their store locations and creates `StoreAnnotation` objects.
    ///
    /// A single DVG may appear at multiple store locations. The annotations are
    /// deduplicated by `StoreLocation.id` and sorted by distance (nearest first).
    private func buildAnnotations(from dvgs: [DVG], userLocation: CLLocation?) {
        // Dictionary keyed by StoreLocation.id, accumulating DVGs per store
        var storeMap: [UUID: (location: StoreLocation, dvgs: [DVG])] = [:]

        for dvg in dvgs {
            guard let locations = dvg.storeLocations else { continue }
            for storeLocation in locations where !storeLocation.isDeleted {
                // Skip store locations with zero coordinates (unset)
                guard storeLocation.latitude != 0.0 || storeLocation.longitude != 0.0 else { continue }

                if var existing = storeMap[storeLocation.id] {
                    existing.dvgs.append(dvg)
                    storeMap[storeLocation.id] = existing
                } else {
                    storeMap[storeLocation.id] = (location: storeLocation, dvgs: [dvg])
                }
            }
        }

        // Build annotations
        var result: [StoreAnnotation] = []

        for (storeID, entry) in storeMap {
            let storeLocation = entry.location
            let storeDVGs = entry.dvgs

            // Calculate distance
            let distanceMetres: Double
            let distanceText: String

            if let userLocation {
                let storeCLLocation = CLLocation(
                    latitude: storeLocation.latitude,
                    longitude: storeLocation.longitude
                )
                distanceMetres = userLocation.distance(from: storeCLLocation)
                distanceText = Self.formatDistance(distanceMetres)
            } else {
                distanceMetres = .greatestFiniteMagnitude
                distanceText = "--"
            }

            // Determine primary DVG type (most common, or first)
            let primaryType = storeDVGs.first?.dvgTypeEnum ?? .discountCode

            // Build DVG summaries
            let summaries = storeDVGs.map { dvg in
                DVGSummary(
                    id: dvg.id,
                    title: dvg.title,
                    storeName: dvg.storeName,
                    dvgType: dvg.dvgTypeEnum,
                    expirationDate: dvg.expirationDate,
                    daysUntilExpiry: dvg.daysUntilExpiry,
                    isFavorite: dvg.isFavorite,
                    displayValue: dvg.displayValue
                )
            }

            let annotation = StoreAnnotation(
                id: storeID,
                coordinate: storeLocation.coordinate,
                name: storeLocation.name.isEmpty ? (storeDVGs.first?.storeName ?? "Store") : storeLocation.name,
                address: storeLocation.address,
                distanceText: distanceText,
                distanceMetres: distanceMetres,
                primaryDVGType: primaryType,
                dvgs: summaries
            )

            result.append(annotation)
        }

        // Sort by distance (nearest first)
        result.sort { $0.distanceMetres < $1.distanceMetres }

        annotations = result
    }

    /// Formats a distance in metres to a human-readable string.
    static func formatDistance(_ metres: Double) -> String {
        if metres < 1000 {
            return "\(Int(metres)) m"
        } else {
            let km = metres / 1000.0
            if km < 10 {
                return String(format: "%.1f km", km)
            } else {
                return "\(Int(km)) km"
            }
        }
    }

    /// Records a non-fatal error for display.
    private func handleError(_ error: Error, context: String) {
        errorMessage = "Failed \(context): \(error.localizedDescription)"
        showError = true
        logger.error("Error \(context): \(error.localizedDescription)")
    }
}
