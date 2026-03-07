# TASK-039: Integrate Google AdMob with banner and interstitial ad placements

## Description
Integrate the Google Mobile Ads SDK (AdMob) for displaying banner ads at the bottom of list views and interstitial ads after every 5th scan operation. Ads are hidden when the user has purchased the "Remove Ads" IAP.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (project structure)
- TASK-026 (dashboard view for ad placement)
- TASK-027 (search view for ad placement)
- TASK-031 (history view for ad placement)

## Acceptance Criteria
- [ ] Google Mobile Ads SDK added via Swift Package Manager
- [ ] `AdService` protocol with `loadBannerAd()`, `loadInterstitialAd()`, `showInterstitialAd()`, `isAdFree` property
- [ ] `AdMobService` implementation with real ad unit IDs (test IDs for development)
- [ ] Banner ad component (`BannerAdView`) using `UIViewRepresentable` wrapper for `GADBannerView`
- [ ] Banner ads placed at bottom of: Dashboard, Search, History views
- [ ] Interstitial ad loaded and shown after every 5th scan (email or camera); count tracked in UserDefaults
- [ ] Ads hidden when `isAdFree` is true (checked from StoreKit entitlements)
- [ ] App Tracking Transparency (ATT) prompt shown before first ad load (required if AdMob uses IDFA)
- [ ] `GADMobileAds.sharedInstance().start()` called in app initialization
- [ ] Ad errors handled gracefully (failed loads do not show broken UI)
- [ ] No ads shown on DVG detail view or during onboarding

## Technical Notes
- AdMob SPM: `https://github.com/googleads/swift-package-manager-google-mobile-ads`
- Test banner ad unit ID: `ca-app-pub-3940256099942544/2435281174`
- Test interstitial ad unit ID: `ca-app-pub-3940256099942544/4411468910`
- ATT: `ATTrackingManager.requestTrackingAuthorization()` before ad SDK init
- Add `NSUserTrackingUsageDescription` to Info.plist
- Banner size: `GADAdSizeBanner` (320x50) or adaptive banner
- Consider a `ScanCounter` utility that increments on each scan and triggers interstitial at threshold
- Ad-free check: `AdService.isAdFree` reads from a shared source (set by TASK-040)
