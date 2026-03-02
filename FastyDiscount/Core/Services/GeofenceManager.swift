import Foundation
import CoreLocation
import UserNotifications
import SwiftData
import OSLog

// MARK: - GeofenceSnapshot

/// A `Sendable` value-type snapshot of DVG + StoreLocation data needed for
/// geofence ranking and registration.
///
/// `DVG` and `StoreLocation` are SwiftData `@Model` classes confined to `@MainActor`.
/// By extracting only the geofencing-relevant fields into this struct we can safely
/// pass values within the main actor without worrying about model lifecycle issues.
struct GeofenceSnapshot: Sendable {
    let dvgID: UUID
    let storeName: String
    let title: String
    let discountDescription: String
    let isFavorite: Bool
    let expirationDate: Date?
    let geofenceRadius: Double
    let locationID: UUID
    let latitude: Double
    let longitude: Double

    /// Effective geofence radius: uses the DVG-specified value, or falls back
    /// to 300 metres if not set (0.0).
    var effectiveRadius: Double {
        geofenceRadius > 0.0 ? geofenceRadius : 300.0
    }

    /// The deterministic region identifier used to map back to the DVG and location.
    /// Format: `dvg-{dvg.id}-{storeLocation.id}`
    var regionIdentifier: String {
        "dvg-\(dvgID.uuidString)-\(locationID.uuidString)"
    }
}

// MARK: - GeofenceManager

/// Manages `CLLocationManager` geofence region monitoring for active DVGs.
///
/// ### Thread Safety
/// Isolated to `@MainActor` because `CLLocationManager` must be created and
/// used on a consistent thread. The delegate callbacks arrive on the thread
/// where the manager was created (main thread in this case). This matches the
/// project-wide convention of using `@MainActor` for services.
///
/// ### 20-Region Limit
/// iOS limits each app to monitoring at most 20 `CLCircularRegion` geofences.
/// This manager uses a priority ranking algorithm to select the top 20 DVG
/// store locations and rotates them when `recalculateGeofences()` is called.
///
/// ### Priority Ranking
/// `score = (expiryUrgency * 0.6) + (proximityScore * 0.3) + (favoriteBonus * 0.1)`
/// - `expiryUrgency`: 1.0 for DVGs expiring within 3 days, linear decay to 0.0
///   at 30+ days, 0.5 for no expiry.
/// - `proximityScore`: based on distance from last known location (closer = higher,
///   normalized 0-1). Skipped if no last known location.
/// - `favoriteBonus`: 1.0 if `isFavorite`, 0.0 otherwise.
@MainActor
final class GeofenceManager: NSObject, CLLocationManagerDelegate {

    // MARK: - Constants

    /// Maximum number of geofence regions iOS allows per app.
    nonisolated static let maxMonitoredRegions = 20

    /// Maximum distance (metres) used for proximity score normalisation.
    /// Locations farther than this distance receive a proximity score of 0.0.
    nonisolated static let maxProximityDistance: Double = 50_000.0 // 50 km

    /// Minimum time interval (seconds) between notifications for the same region
    /// to avoid notification spam when the user lingers near a geofence boundary.
    nonisolated static let notificationCooldownInterval: TimeInterval = 10.0

    /// Region identifier prefix used for all geofence regions managed by this service.
    nonisolated static let regionIdentifierPrefix = "dvg-"

    /// Minimum distance (metres) the user must move before geofences are recalculated.
    /// Significant-location-change events fire approximately every 500m, so this
    /// threshold avoids redundant recalculations from small jitter.
    nonisolated static let minimumRecalculationDistance: Double = 500.0

    // MARK: - Properties

    private let locationManager: CLLocationManager
    private let modelContainer: ModelContainer

    /// Observed permission manager. GeofenceManager watches its `authorizationState`
    /// so it can start/stop monitoring when the user grants or revokes permission.
    ///
    /// Held as a strong reference; the app creates exactly one shared instance and
    /// passes it into both `GeofenceManager` and the UI layer.
    private let permissionManager: LocationPermissionManager

    /// Structured logger for geofence and significant-location-change events.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FastyDiscount",
                                category: "GeofenceManager")

    /// Tracks the last time a notification was sent for each region identifier.
    /// Used to enforce the cooldown interval.
    private var lastNotificationTimes: [String: Date] = [:]

    /// The location at which geofences were last recalculated.
    ///
    /// Used to implement the 500m threshold: geofences are only recalculated when
    /// the user has moved at least `minimumRecalculationDistance` from this point.
    /// `nil` means no recalculation has occurred yet (first recalculation always runs).
    private var lastRecalculationLocation: CLLocation?

    // MARK: - Init

    /// Creates a `GeofenceManager` with the given `ModelContainer` and permission manager.
    ///
    /// The `CLLocationManager` is created on `@MainActor`, ensuring all delegate
    /// callbacks arrive on the main thread.
    ///
    /// - Parameters:
    ///   - modelContainer: The SwiftData container for fetching DVGs.
    ///   - permissionManager: The shared `LocationPermissionManager` instance.
    ///     `GeofenceManager` observes its `authorizationState` to know when to
    ///     start or stop region monitoring.
    init(modelContainer: ModelContainer, permissionManager: LocationPermissionManager) {
        self.modelContainer = modelContainer
        self.permissionManager = permissionManager
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Background location updates must be enabled so the system can deliver
        // significant-location-change events and geofence transitions while the
        // app is running in the background. The app may also be cold-launched by
        // the OS specifically to handle these events.
        locationManager.allowsBackgroundLocationUpdates = true
    }

    // MARK: - Public API

    /// Starts monitoring for significant location changes.
    ///
    /// Significant-location changes fire approximately every 500m or when the
    /// device connects to a different cell tower. This is a low-power alternative
    /// to continuous GPS: the system batches events and can even relaunch the app
    /// from a terminated state to deliver them.
    ///
    /// Only starts monitoring when the app has sufficient location authorisation
    /// (`.authorizedAlways` or `.authorizedWhenInUse`). Calling this when already
    /// monitoring is a no-op (the system deduplicates the request).
    func startSignificantLocationMonitoring() {
        guard isAuthorizedForRegionMonitoring() else {
            logger.info("Significant location monitoring not started: insufficient authorisation")
            return
        }
        locationManager.startMonitoringSignificantLocationChanges()
        logger.info("Significant location change monitoring started")
    }

    /// Re-ranks all active DVGs with store locations, removes old geofence regions,
    /// and registers the top 20 by priority score.
    ///
    /// Call this:
    /// - At app launch (after authentication).
    /// - When DVGs are added, edited, or deleted.
    /// - When the user's location changes significantly.
    /// - When location permission changes.
    func recalculateGeofences() async {
        // Check that we have location permission for region monitoring
        guard isAuthorizedForRegionMonitoring() else {
            removeAllManagedRegions()
            return
        }

        // Fetch all active DVGs with their store locations
        let snapshots = await fetchGeofenceSnapshots()
        guard !snapshots.isEmpty else {
            removeAllManagedRegions()
            return
        }

        // Score and rank all snapshots
        let lastLocation = locationManager.location
        let ranked = rankSnapshots(snapshots, lastLocation: lastLocation)

        // Take the top 20
        let topRegions = Array(ranked.prefix(Self.maxMonitoredRegions))

        // Determine which region identifiers we want monitored
        let desiredIdentifiers = Set(topRegions.map(\.regionIdentifier))

        // Remove regions that are no longer in the top 20
        let currentRegions = locationManager.monitoredRegions
        var removedCount = 0
        for region in currentRegions {
            if region.identifier.hasPrefix(Self.regionIdentifierPrefix)
                && !desiredIdentifiers.contains(region.identifier) {
                locationManager.stopMonitoring(for: region)
                removedCount += 1
            }
        }

        // Register new top regions (skip already-monitored ones)
        let currentIdentifiers = Set(currentRegions.map(\.identifier))
        var addedCount = 0
        for snapshot in topRegions {
            if !currentIdentifiers.contains(snapshot.regionIdentifier) {
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(
                        latitude: snapshot.latitude,
                        longitude: snapshot.longitude
                    ),
                    radius: snapshot.effectiveRadius,
                    identifier: snapshot.regionIdentifier
                )
                region.notifyOnEntry = true
                region.notifyOnExit = false
                locationManager.startMonitoring(for: region)
                addedCount += 1
            }
        }

        // Update the recalculation anchor so future significant-location-change
        // events can skip unnecessary recalculations via the 500m threshold.
        if let location = lastLocation {
            lastRecalculationLocation = location
        }

        logger.info("Geofence recalculation complete — added: \(addedCount), removed: \(removedCount), total monitored: \(topRegions.count)")
    }

    // MARK: - CLLocationManagerDelegate

    /// Called when the user enters a monitored geofence region.
    ///
    /// This method fires even if the app was terminated. iOS relaunches the app
    /// into the background to deliver this event. The notification is sent via
    /// `UNUserNotificationCenter` with the `dvg-location` category.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion,
              circularRegion.identifier.hasPrefix(GeofenceManager.regionIdentifierPrefix) else {
            return
        }

        let identifier = circularRegion.identifier
        Task { @MainActor [weak self] in
            await self?.handleRegionEntry(identifier: identifier)
        }
    }

    /// Called when significant location changes are delivered by the system.
    ///
    /// This delegate method is the callback for `startMonitoringSignificantLocationChanges()`.
    /// It fires approximately every 500m or on a cell-tower change. The app may be
    /// cold-launched into the background by the OS specifically to receive this event.
    ///
    /// ### Swift 6 Concurrency
    /// This method is `nonisolated` because `CLLocationManagerDelegate` is not
    /// `@MainActor`-bound. Location data is extracted from `CLLocation` (a `Sendable`
    /// type) here on the calling thread, then the main-actor work is dispatched via
    /// a `Task { @MainActor }` closure. This avoids any data-race issues.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Extract the most recent location. `CLLocation` is Sendable, so this is
        // safe to capture and pass across actor boundaries.
        guard let newLocation = locations.last else { return }

        Task { @MainActor [weak self] in
            await self?.handleSignificantLocationChange(to: newLocation)
        }
    }

    /// Called when region monitoring fails for a specific region.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: any Error
    ) {
        let regionID = region?.identifier ?? "unknown"
        print("[GeofenceManager] Monitoring failed for region \(regionID): \(error.localizedDescription)")
    }

    /// Called when the location manager's authorisation status changes.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // (Re)start significant-location monitoring in case we just gained authorisation.
            self.startSignificantLocationMonitoring()
            await self.recalculateGeofences()
        }
    }

    // MARK: - Significant Location Change Handling

    /// Processes a significant location change event.
    ///
    /// Only triggers a full geofence recalculation if the user has moved at least
    /// `minimumRecalculationDistance` (500m) from the location used for the last
    /// recalculation. This guards against multiple rapid events firing in quick
    /// succession without meaningful movement.
    ///
    /// If no previous recalculation has occurred (`lastRecalculationLocation == nil`),
    /// the recalculation always runs.
    ///
    /// - Parameter newLocation: The most recent significant location fix.
    private func handleSignificantLocationChange(to newLocation: CLLocation) async {
        let distanceMoved: CLLocationDistance
        if let lastLocation = lastRecalculationLocation {
            distanceMoved = newLocation.distance(from: lastLocation)
        } else {
            // First ever recalculation — always proceed.
            distanceMoved = Self.minimumRecalculationDistance
        }

        guard distanceMoved >= Self.minimumRecalculationDistance else {
            logger.debug("Significant location change ignored: moved \(distanceMoved, format: .fixed(precision: 0))m (threshold: \(Self.minimumRecalculationDistance)m)")
            return
        }

        logger.info("Significant location change: moved \(distanceMoved, format: .fixed(precision: 0))m — recalculating geofences")
        await recalculateGeofences()
    }

    // MARK: - Region Entry Handling

    /// Processes a geofence region entry event.
    ///
    /// Parses the region identifier to extract the DVG ID, fetches the DVG data,
    /// and posts a local notification with the `dvg-location` category.
    private func handleRegionEntry(identifier: String) async {
        // Enforce cooldown to prevent notification spam
        let now = Date()
        if let lastTime = lastNotificationTimes[identifier],
           now.timeIntervalSince(lastTime) < Self.notificationCooldownInterval {
            return
        }
        lastNotificationTimes[identifier] = now

        // Parse the region identifier to extract the DVG ID
        guard let dvgID = parseDVGID(from: identifier) else {
            print("[GeofenceManager] Could not parse DVG ID from region identifier: \(identifier)")
            return
        }

        // Fetch the DVG to build notification content
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> { $0.id == dvgID && $0.isDeleted == false }
        )

        guard let dvg = try? context.fetch(descriptor).first else {
            print("[GeofenceManager] DVG \(dvgID) not found for region entry notification")
            return
        }

        // Only notify for active DVGs
        guard dvg.statusEnum == .active else {
            return
        }

        // Build and send the location notification
        await sendLocationNotification(for: dvg)
    }

    /// Sends a local notification for a DVG location entry event.
    ///
    /// Content format: "You have a discount at {store}! {title} -- {discountDescription}"
    private func sendLocationNotification(for dvg: DVG) async {
        let content = UNMutableNotificationContent()
        content.title = "Discount Nearby"
        content.categoryIdentifier = NotificationCategoryRegistrar.locationCategoryIdentifier
        content.sound = .default
        content.userInfo["dvgID"] = dvg.id.uuidString

        // Build body: "You have a discount at {store}! {title} -- {discountDescription}"
        let storePart = dvg.storeName.isEmpty ? "a nearby store" : dvg.storeName
        let titlePart = dvg.title.isEmpty ? "Discount" : dvg.title
        let descriptionPart = dvg.discountDescription.isEmpty ? "" : " \u{2014} \(dvg.discountDescription)"
        content.body = "You have a discount at \(storePart)! \(titlePart)\(descriptionPart)"

        // Use a unique identifier per DVG so repeated entries update the same notification
        let notificationIdentifier = "location-\(dvg.id.uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[GeofenceManager] Failed to send location notification for DVG \(dvg.id): \(error)")
        }
    }

    // MARK: - Priority Ranking

    /// Ranks geofence snapshots by the priority scoring algorithm.
    ///
    /// `score = (expiryUrgency * 0.6) + (proximityScore * 0.3) + (favoriteBonus * 0.1)`
    ///
    /// When no last known location is available, proximity is skipped and its weight
    /// is redistributed to expiry urgency:
    /// `score = (expiryUrgency * 0.9) + (favoriteBonus * 0.1)`
    ///
    /// - Parameters:
    ///   - snapshots: All geofence-eligible DVG/location pairs.
    ///   - lastLocation: The user's last known location, or `nil`.
    /// - Returns: Snapshots sorted by descending score.
    private func rankSnapshots(
        _ snapshots: [GeofenceSnapshot],
        lastLocation: CLLocation?
    ) -> [GeofenceSnapshot] {
        let scored: [(snapshot: GeofenceSnapshot, score: Double)] = snapshots.map { snapshot in
            let expiryUrgency = computeExpiryUrgency(expirationDate: snapshot.expirationDate)
            let favoriteBonus: Double = snapshot.isFavorite ? 1.0 : 0.0

            let score: Double
            if let location = lastLocation {
                let proximity = computeProximityScore(
                    latitude: snapshot.latitude,
                    longitude: snapshot.longitude,
                    from: location
                )
                score = (expiryUrgency * 0.6) + (proximity * 0.3) + (favoriteBonus * 0.1)
            } else {
                // No location: redistribute proximity weight to expiry
                score = (expiryUrgency * 0.9) + (favoriteBonus * 0.1)
            }

            return (snapshot, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.snapshot)
    }

    /// Computes the expiry urgency score for a DVG.
    ///
    /// - 1.0 for DVGs expiring within 3 days.
    /// - Linear decay from 1.0 to 0.0 between 3 and 30 days.
    /// - 0.0 for DVGs expiring in 30+ days.
    /// - 0.5 for DVGs with no expiry date.
    ///
    /// - Parameter expirationDate: The DVG's expiration date, or `nil`.
    /// - Returns: A value between 0.0 and 1.0.
    private func computeExpiryUrgency(expirationDate: Date?) -> Double {
        guard let expirationDate else {
            return 0.5
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        guard let daysRemaining = components.day else {
            return 0.5
        }

        if daysRemaining <= 3 {
            return 1.0
        } else if daysRemaining >= 30 {
            return 0.0
        } else {
            // Linear decay from 1.0 at 3 days to 0.0 at 30 days
            // daysRemaining is in (3, 30)
            return Double(30 - daysRemaining) / Double(30 - 3)
        }
    }

    /// Computes the proximity score based on distance from the user's last known location.
    ///
    /// Normalised to 0-1: closer locations score higher.
    /// Locations beyond `maxProximityDistance` (50 km) receive 0.0.
    ///
    /// - Parameters:
    ///   - latitude: Store location latitude.
    ///   - longitude: Store location longitude.
    ///   - from: The user's last known location.
    /// - Returns: A value between 0.0 and 1.0.
    private func computeProximityScore(
        latitude: Double,
        longitude: Double,
        from userLocation: CLLocation
    ) -> Double {
        let storeLocation = CLLocation(latitude: latitude, longitude: longitude)
        let distanceMetres = userLocation.distance(from: storeLocation)

        if distanceMetres >= Self.maxProximityDistance {
            return 0.0
        }

        // Linear: 1.0 at distance 0, 0.0 at maxProximityDistance
        return 1.0 - (distanceMetres / Self.maxProximityDistance)
    }

    // MARK: - Data Fetching

    /// Fetches all active, non-deleted DVGs that have store locations with a
    /// non-zero geofence eligibility, and returns `GeofenceSnapshot` values
    /// for each DVG/location pair.
    ///
    /// A DVG is eligible if:
    /// - It is active and not deleted.
    /// - It has at least one non-deleted store location.
    /// - Its geofence radius is >= 0 (0 uses the 300m default).
    private func fetchGeofenceSnapshots() async -> [GeofenceSnapshot] {
        let context = modelContainer.mainContext
        let activeRaw = DVGStatus.active.rawValue

        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> {
                $0.isDeleted == false && $0.status == activeRaw
            }
        )

        guard let dvgs = try? context.fetch(descriptor) else {
            return []
        }

        var snapshots: [GeofenceSnapshot] = []

        for dvg in dvgs {
            guard let locations = dvg.storeLocations else { continue }

            for location in locations {
                guard !location.isDeleted else { continue }
                // Skip locations at 0,0 (unset coordinates)
                guard location.latitude != 0.0 || location.longitude != 0.0 else { continue }

                snapshots.append(GeofenceSnapshot(
                    dvgID: dvg.id,
                    storeName: dvg.storeName,
                    title: dvg.title,
                    discountDescription: dvg.discountDescription,
                    isFavorite: dvg.isFavorite,
                    expirationDate: dvg.expirationDate,
                    geofenceRadius: dvg.geofenceRadius,
                    locationID: location.id,
                    latitude: location.latitude,
                    longitude: location.longitude
                ))
            }
        }

        return snapshots
    }

    // MARK: - Helpers

    /// Checks whether the app has sufficient location authorisation for region monitoring.
    ///
    /// Delegates to `LocationPermissionManager.authorizationState` so that this
    /// check is always consistent with the observable permission state used by the UI.
    ///
    /// Region monitoring requires `.whenInUse` or `.always`.
    /// Note: `.whenInUse` allows region monitoring on iOS 14+ but geofence
    /// notifications from a *terminated* app require `.always`.
    private func isAuthorizedForRegionMonitoring() -> Bool {
        let state = permissionManager.authorizationState
        return state == .whenInUse || state == .always
    }

    /// Removes all geofence regions managed by this service.
    ///
    /// Only removes regions whose identifier starts with the `dvg-` prefix to
    /// avoid interfering with regions registered by other parts of the app.
    private func removeAllManagedRegions() {
        for region in locationManager.monitoredRegions {
            if region.identifier.hasPrefix(Self.regionIdentifierPrefix) {
                locationManager.stopMonitoring(for: region)
            }
        }
    }

    /// Parses the DVG UUID from a region identifier.
    ///
    /// Expected format: `dvg-{dvg.id}-{storeLocation.id}`
    /// where both IDs are UUID strings (36 characters each).
    ///
    /// - Parameter identifier: The region identifier string.
    /// - Returns: The DVG UUID, or `nil` if parsing fails.
    private func parseDVGID(from identifier: String) -> UUID? {
        // Format: "dvg-{UUID}-{UUID}"
        // "dvg-" prefix is 4 characters
        // UUID string is 36 characters
        // Total: "dvg-" (4) + UUID (36) + "-" (1) + UUID (36) = 77 characters
        guard identifier.hasPrefix(Self.regionIdentifierPrefix) else { return nil }

        let withoutPrefix = String(identifier.dropFirst(Self.regionIdentifierPrefix.count))
        // withoutPrefix should be "{UUID}-{UUID}" = 36 + 1 + 36 = 73 characters
        // The DVG UUID is the first 36 characters
        guard withoutPrefix.count >= 36 else { return nil }

        let dvgIDString = String(withoutPrefix.prefix(36))
        return UUID(uuidString: dvgIDString)
    }
}
