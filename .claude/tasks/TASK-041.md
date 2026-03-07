# TASK-041: Build ad-free paywall UI and entitlement gating logic

## Description
Build the UI for the "Remove Ads" purchase including the paywall presentation in Settings and the occasional gentle prompt after ad display. Implement the entitlement gating logic that hides ad views when the purchase is active.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: S (< 1 hour)
- Routing: code-agent

## Dependencies
- TASK-039 (AdMob integration and AdService)
- TASK-040 (StoreKit 2 purchase flow)
- TASK-030 (Settings view where paywall lives)

## Acceptance Criteria
- [ ] "Remove Ads" section in Settings showing: product description, price, purchase button, restore button
- [ ] If already purchased: section shows "Ad-Free -- Thank You!" with green checkmark
- [ ] Purchase button shows localized price from StoreKit product
- [ ] Loading state while product loads from App Store
- [ ] Occasional prompt: after every 10th ad impression, show a non-intrusive banner suggesting "Remove Ads"
- [ ] Entitlement gating: `BannerAdView` and interstitial logic check `StoreKitService.isAdFree` before displaying
- [ ] `@Observable` `PaywallViewModel` managing product loading, purchase state, and entitlement status
- [ ] Smooth transition when ads are removed (no jarring layout shifts)

## Technical Notes
- Price display: use `product.displayPrice` from StoreKit 2 for localized pricing
- After successful purchase: immediately hide all ad views (no app restart needed)
- The gentle prompt should be a small banner, not a modal -- avoid being pushy
- Track ad impression count in UserDefaults; reset on app launch
- Layout: when ads are hidden, list views should expand to fill the space (use conditional ad view)
