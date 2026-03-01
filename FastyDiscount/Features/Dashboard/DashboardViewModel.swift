import SwiftUI
import SwiftData
import CoreLocation

// MARK: - DashboardViewModel

/// ViewModel for the dashboard home screen. Manages loading and state for three
/// independent sections: Expiring Soon, Nearby, and Recently Added.
///
/// Each section can be loaded independently. Loads execute sequentially on the
/// main actor. The ViewModel also handles pull-to-refresh and favourite toggling.
///
/// ### Concurrency
/// `@Observable @MainActor` per project convention. Repository calls are async
/// and run on the main actor since `SwiftDataDVGRepository` is `@MainActor`.
@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - Section Data

    /// DVGs expiring within 7 days, sorted by expiry date ascending.
    private(set) var expiringSoon: [DVG] = []

    /// DVGs near the user's current location.
    private(set) var nearbyDVGs: [DVG] = []

    /// Last 5 active DVGs sorted by dateAdded descending.
    private(set) var recentlyAdded: [DVG] = []

    // MARK: - Loading State

    /// Whether the initial load is in progress (shows skeleton/spinner on first load).
    private(set) var isLoading: Bool = false

    /// Whether any data has been loaded at least once.
    private(set) var hasLoaded: Bool = false

    /// Error message to display, if any.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    // MARK: - Location State

    /// Whether location is authorized for the Nearby section.
    /// Derived from `LocationPermissionManager` at load time.
    private(set) var isLocationAuthorized: Bool = false

    /// Distances for nearby DVGs, keyed by DVG id.
    /// Calculated from the user's current location.
    private(set) var nearbyDistances: [UUID: String] = [:]

    // MARK: - Dependencies

    private let repository: any DVGRepository
    private let locationManager: LocationPermissionManager?

    /// Radius in metres for nearby DVG search.
    private let nearbyRadius: Double = 10_000 // 10 km

    // MARK: - Init

    /// Creates a DashboardViewModel.
    ///
    /// - Parameters:
    ///   - repository: The DVG repository for data access.
    ///   - locationManager: The location permission manager for checking auth state
    ///     and fetching the user's current position. Pass `nil` to disable Nearby.
    init(repository: any DVGRepository, locationManager: LocationPermissionManager? = nil) {
        self.repository = repository
        self.locationManager = locationManager
    }

    // MARK: - Computed Properties

    /// Returns `true` when the user has no active DVGs at all (overall empty state).
    ///
    /// Uses `recentlyAdded` (sourced from `fetchActive()`) and `expiringSoon` as a
    /// proxy for the total active DVG count. `nearbyDVGs` is intentionally excluded
    /// because it is empty whenever location is not authorized, which would
    /// incorrectly trigger the empty state for users who have DVGs but have not
    /// granted location permission.
    var hasNoDVGs: Bool {
        hasLoaded && recentlyAdded.isEmpty && expiringSoon.isEmpty
    }

    /// Whether the Nearby section should be visible.
    /// Hidden when location is not authorized or no nearby DVGs exist.
    var showNearbySection: Bool {
        isLocationAuthorized && !nearbyDVGs.isEmpty
    }

    // MARK: - Load All Sections

    /// Loads all dashboard sections.
    /// Call from `.task` or `.refreshable` on the view.
    func loadAll() async {
        if !hasLoaded {
            isLoading = true
        }

        // Check location authorization state
        updateLocationAuthState()

        // Sections load sequentially on @MainActor — parallelism not possible
        // since all operations access the same @MainActor-isolated context.
        await loadExpiringSoon()
        await loadNearby()
        await loadRecentlyAdded()

        hasLoaded = true
        isLoading = false
    }

    /// Refreshes all sections. Called by pull-to-refresh.
    func refresh() async {
        updateLocationAuthState()

        await loadExpiringSoon()
        await loadNearby()
        await loadRecentlyAdded()
    }

    // MARK: - Load Individual Sections

    /// Loads the Expiring Soon section: DVGs expiring within 7 days.
    func loadExpiringSoon() async {
        do {
            expiringSoon = try await repository.fetchExpiringSoon(within: 7)
        } catch {
            handleError(error, context: "Expiring Soon")
        }
    }

    /// Loads the Nearby section: DVGs near the user's current location.
    /// No-op if location is not authorized.
    func loadNearby() async {
        guard isLocationAuthorized else {
            nearbyDVGs = []
            nearbyDistances = [:]
            return
        }

        guard let coordinate = currentUserLocation() else {
            nearbyDVGs = []
            nearbyDistances = [:]
            return
        }

        do {
            let results = try await repository.fetchNearby(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: nearbyRadius
            )
            nearbyDVGs = results
            calculateDistances(from: coordinate, for: results)
        } catch {
            handleError(error, context: "Nearby")
        }
    }

    /// Loads the Recently Added section: last 5 active DVGs.
    func loadRecentlyAdded() async {
        do {
            let active = try await repository.fetchActive()
            recentlyAdded = Array(active.prefix(5))
        } catch {
            handleError(error, context: "Recently Added")
        }
    }

    // MARK: - Actions

    /// Toggles the favourite status of a DVG.
    func toggleFavorite(_ dvg: DVG) {
        dvg.isFavorite.toggle()
        dvg.lastModified = Date()
    }

    // MARK: - Private Helpers

    /// Updates the cached location authorization state.
    private func updateLocationAuthState() {
        guard let manager = locationManager else {
            isLocationAuthorized = false
            return
        }

        let state = manager.authorizationState
        isLocationAuthorized = (state == .whenInUse || state == .always)
    }

    /// Returns the user's current location coordinate, if available.
    ///
    /// Reads from the `LocationPermissionManager`'s existing `CLLocationManager`
    /// instance rather than creating a new one (a newly-created manager has no
    /// cached location and would always return `nil`).
    private func currentUserLocation() -> CLLocationCoordinate2D? {
        locationManager?.currentCLLocation?.coordinate
    }

    /// Calculates human-readable distance strings for nearby DVGs.
    private func calculateDistances(from userCoordinate: CLLocationCoordinate2D, for dvgs: [DVG]) {
        var distances: [UUID: String] = [:]
        let userLocation = CLLocation(
            latitude: userCoordinate.latitude,
            longitude: userCoordinate.longitude
        )

        for dvg in dvgs {
            guard let locations = dvg.storeLocations else { continue }

            // Find the closest non-deleted store location
            var minDistance: CLLocationDistance = .greatestFiniteMagnitude

            for storeLocation in locations where !storeLocation.isDeleted {
                let storeCLLocation = CLLocation(
                    latitude: storeLocation.latitude,
                    longitude: storeLocation.longitude
                )
                let distance = userLocation.distance(from: storeCLLocation)
                minDistance = min(minDistance, distance)
            }

            if minDistance < .greatestFiniteMagnitude {
                distances[dvg.id] = formatDistance(minDistance)
            }
        }

        nearbyDistances = distances
    }

    /// Formats a distance in metres to a human-readable string.
    private func formatDistance(_ metres: Double) -> String {
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
        errorMessage = "Failed to load \(context): \(error.localizedDescription)"
        showError = true
    }
}
