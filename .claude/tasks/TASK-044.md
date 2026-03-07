# TASK-044: App Store metadata, screenshots, and privacy nutrition labels

## Description
Prepare all App Store Connect metadata including app description, keywords, screenshots specification, privacy nutrition labels, and required legal documents. Create the App Store listing content and configure privacy declarations.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- All feature tasks complete (Phases 1-8)

## Acceptance Criteria
- [ ] App Store description written (short description + full description)
- [ ] Keywords list optimized for discoverability (100 character limit)
- [ ] Category selected: Shopping (primary), Utilities (secondary)
- [ ] Age rating questionnaire answers documented
- [ ] Privacy nutrition labels configured: data collected, data linked to identity, tracking
- [ ] `PrivacyInfo.xcprivacy` file created with required API declarations (iOS 17+)
- [ ] Privacy policy URL prepared (even if placeholder)
- [ ] Screenshot specifications documented: sizes needed for iPhone, iPad, Apple Watch
- [ ] App icon in all required sizes (1024x1024 for App Store, plus all device sizes)
- [ ] Launch screen configured (simple branded splash, not a storyboard)
- [ ] `NSAppTransportSecurity` exceptions documented if any (for API endpoints)
- [ ] Required device capabilities declared in Info.plist

## Technical Notes
- Privacy nutrition labels must declare: location data (precise), email data (if accessed via Gmail), purchases (IAP)
- Required API declarations for `PrivacyInfo.xcprivacy`: UserDefaults, file timestamp, disk space (commonly flagged)
- App icon: use a single 1024x1024 source image; Xcode generates all sizes
- Launch screen: use Info.plist-based launch screen (background color + app name) instead of storyboard
- Screenshots: 6.7" (iPhone 15 Pro Max), 6.5" (iPhone 11 Pro Max), 12.9" (iPad Pro) -- specify content for each
- Keywords: "discount codes, vouchers, gift cards, coupons, barcode scanner, expiry reminder, deals, savings"
- Required capabilities: `armv7` removed (modern devices only); consider requiring `location-services` and `camera`
