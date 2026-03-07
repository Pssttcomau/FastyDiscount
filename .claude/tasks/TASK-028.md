# TASK-028: Build nearby map view with MapKit, store pins, and DVG summary cards

## Description
Build the "Nearby" tab that shows a MapKit map centered on the user's current location with pins for all stores that have active DVGs. Tapping a pin shows a summary card with the associated DVG(s) and quick actions.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-008 (StoreLocation model with coordinates)
- TASK-009 (DVGRepository for nearby queries)
- TASK-025 (location permission)
- TASK-006 (theme system)
- TASK-010 (DVG detail for navigation)

## Acceptance Criteria
- [ ] Full-screen `Map` view (MapKit SwiftUI) centered on user's current location
- [ ] Custom annotation pins for each store with active DVGs (use DVG type icon as pin)
- [ ] Clustered annotations when zoomed out (MKClusterAnnotation)
- [ ] Tapping a pin shows a summary card at the bottom of the map
- [ ] Summary card shows: store name, address, distance, list of DVGs at that store
- [ ] Each DVG in the card shows: title, type, expiry badge, "View" button
- [ ] "View" button navigates to DVG detail view
- [ ] "Directions" button opens Apple Maps with directions to the store
- [ ] User location button to re-center map on current location
- [ ] Search bar overlay to filter stores by name
- [ ] Empty state when no DVGs have store locations ("Add store locations to your DVGs to see them here")
- [ ] Location permission handling: show request flow if not authorized (delegates to TASK-025)
- [ ] `@Observable` `NearbyMapViewModel` managing map region, annotations, and selected store

## Technical Notes
- Use SwiftUI `Map` with `MapContentBuilder` (iOS 17+) for annotations
- Custom annotations: `Annotation` view with SF Symbol icon colored by DVG type
- Summary card: use a `sheet` with detent `.medium` or a custom bottom card view
- Distance calculation: `CLLocation.distance(from:)` for accurate distances
- "Directions" button: `MKMapItem(placemark:).openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])`
- Map region should initially show ~5km radius around user
- If multiple DVGs share a store location, group them in the summary card
- On iPad: map takes full width with summary card as sidebar panel
