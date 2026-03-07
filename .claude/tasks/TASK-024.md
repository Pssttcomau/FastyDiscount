# TASK-024: Implement significant location change monitoring and geofence recalculation

## Description
Implement the significant location change monitoring that covers DVGs beyond the top 20 geofences. When a significant location change is detected, recalculate distances to all DVG stores and rotate the geofence set based on updated proximity scores.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-023 (GeofenceManager with priority ranking)

## Acceptance Criteria
- [ ] `CLLocationManager.startMonitoringSignificantLocationChanges()` enabled
- [ ] On significant location change: call `GeofenceManager.recalculateGeofences()` with new location
- [ ] Proximity scores updated for all DVGs based on new location
- [ ] Geofence rotation: remove regions no longer in top 20, register new ones
- [ ] Background launch handling: app may be launched in background for location events
- [ ] Efficient: only recalculate if location moved more than 500m from last recalculation
- [ ] Logging: track recalculation events for debugging (count of rotated regions)
- [ ] Power efficiency: no continuous GPS; rely entirely on significant-change events

## Technical Notes
- Significant location changes fire approximately every 500m or on cell tower change
- The app may be launched cold for these events -- ensure `GeofenceManager` initializes quickly
- Keep a `lastRecalculationLocation` property to avoid unnecessary recalculations
- Haversine distance calculation for determining if 500m threshold is met
- This runs in `GeofenceManager` alongside the geofencing logic from TASK-023
- On recalculation: use `stopMonitoring(for:)` for removed regions, `startMonitoring(for:)` for new ones
