# TASK-025: Build location permission request flow and background location entitlement

## Description
Implement the location permission request flow that follows Apple's best practices: request "When In Use" first, then upgrade to "Always" with clear explanation of why background location is needed. Configure the background location entitlement and usage descriptions.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (Info.plist with location usage descriptions)
- TASK-023 (GeofenceManager that needs location permission)

## Acceptance Criteria
- [ ] `LocationPermissionManager` observable class managing permission state
- [ ] Step 1: Request "When In Use" permission with explanation sheet ("We use your location to alert you when you're near a store where you have a discount")
- [ ] Step 2: After user engages with location features, request upgrade to "Always" with explanation
- [ ] Custom explanation view shown before system dialog (improves grant rate)
- [ ] Handle all authorization states: notDetermined, restricted, denied, authorizedWhenInUse, authorizedAlways
- [ ] "Denied" state: show settings deep-link button to open app's Location settings
- [ ] Permission state persisted and observable by GeofenceManager
- [ ] Background location indicator handling: ensure app behaves correctly with blue status bar
- [ ] Info.plist descriptions: `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`
- [ ] Background mode `location` enabled in capabilities

## Technical Notes
- Apple strongly recommends requesting "When In Use" first, then requesting "Always" after user sees value
- Do NOT request "Always" on first launch -- request it after the user adds their first DVG with a store location
- `CLLocationManager.requestAlwaysAuthorization()` must be called after `requestWhenInUseAuthorization()` was granted
- On iOS 13+: "Always" permission may initially grant "When In Use" with a provisional "Always" that the user confirms later via system prompt
- Usage description strings should be specific and benefit-focused, not generic
- The permission flow should be triggered from TASK-028 (nearby map) or TASK-023 (geofencing setup), not from onboarding
