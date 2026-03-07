# TASK-023: Build geofencing engine with priority ranking and 20-region rotation

## Description
Implement the geofencing engine that manages the iOS 20-region limit by prioritizing DVGs based on expiry urgency, proximity, and favorite status. The engine registers `CLCircularRegion` geofences for the top 20 DVGs and triggers location-based notifications when the user enters a store region.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-007 (DVG model with geofenceRadius)
- TASK-008 (StoreLocation model with coordinates)
- TASK-009 (DVGRepository for queries)
- TASK-022 (notification actions for location notifications)

## Acceptance Criteria
- [ ] `GeofenceManager` actor that owns the `CLLocationManager` and manages region monitoring
- [ ] Priority ranking algorithm: `score = (expiryUrgency * 0.6) + (proximityScore * 0.3) + (favoriteBonus * 0.1)`
- [ ] `expiryUrgency`: 1.0 for DVGs expiring within 3 days, linear decay to 0.0 at 30+ days, 0.5 for no expiry
- [ ] `proximityScore`: based on distance from last known location (closer = higher, normalized 0-1)
- [ ] `favoriteBonus`: 1.0 if `isFavorite`, 0.0 otherwise
- [ ] Top 20 DVGs by score get `CLCircularRegion` geofences registered
- [ ] Geofence radius per DVG from `DVG.geofenceRadius` (default 300m)
- [ ] `CLLocationManagerDelegate` handles `didEnterRegion` to trigger location notification
- [ ] Location notification content: "You have a discount at {store}! {title} -- {discountDescription}"
- [ ] `recalculateGeofences()` method: re-ranks all DVGs, removes old regions, registers new top 20
- [ ] Geofences persist across app termination (iOS handles this natively)
- [ ] Region identifier format: `dvg-{dvg.id}-{storeLocation.id}` for mapping back to DVG

## Technical Notes
- `CLLocationManager.startMonitoring(for:)` supports max 20 regions per app
- `CLCircularRegion(center:radius:identifier:)` -- set `notifyOnEntry = true`, `notifyOnExit = false`
- The actor pattern ensures thread-safe access to the region registry
- For proximity scoring: use last known location from `CLLocationManager.location`
- If no last known location: skip proximity score (weight redistributed to expiry)
- `didEnterRegion` may fire with the app terminated -- handle in AppDelegate's `application(_:didFinishLaunchingWithOptions:)` with launch options check
- Consider a 10-second cooldown between same-region notifications to avoid spam
