# TASK-001: Create Xcode project with multi-target structure

## Description
Create a new Xcode project for FastyDiscount with all required targets: iOS app, watchOS app, watchOS extension, WidgetKit extension, and Share Sheet extension. Configure the project for iOS 19+ deployment, Swift 6 strict concurrency, and App Group entitlements shared across all targets.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
None -- this is the first task.

## Acceptance Criteria
- [ ] Xcode project created with bundle ID `com.fastydiscount.app`
- [ ] Main iOS app target configured for iOS 19+ deployment
- [ ] watchOS app target and extension created
- [ ] WidgetKit extension target created
- [ ] Share Sheet (Action) extension target created
- [ ] App Group `group.com.fastydiscount.shared` configured on all targets
- [ ] iCloud entitlement with CloudKit container `iCloud.com.fastydiscount.app` on main target
- [ ] Swift 6 language mode enabled (`SWIFT_VERSION = 6`) on all targets
- [ ] Strict concurrency checking enabled (`SWIFT_STRICT_CONCURRENCY = complete`)
- [ ] Project folder structure matches plan (App/, Features/, Core/, Resources/)
- [ ] All targets build successfully with no errors or warnings
- [ ] `.gitignore` created for Xcode projects

## Technical Notes
- Use SwiftUI App lifecycle (`@main` struct) for the iOS app
- watchOS app should use SwiftUI App lifecycle as well
- WidgetKit target needs `WidgetBundle` entry point
- Share extension needs `NSExtensionActivationRule` in Info.plist for text, URL, image, and PDF types
- Each extension needs its own Info.plist with appropriate `NSExtension` configuration
- Enable background modes: `location`, `fetch`, `remote-notification` on main target
- Add `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` to main target Info.plist
