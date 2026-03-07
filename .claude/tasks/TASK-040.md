# TASK-040: Implement StoreKit 2 IAP for "Remove Ads" purchase

## Description
Implement the "Remove Ads" in-app purchase using StoreKit 2. This is a single non-consumable product that permanently removes all ads from the app. Includes purchase flow, transaction verification, entitlement checking, and restore purchases.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (project structure)
- TASK-039 (AdService.isAdFree flag)

## Acceptance Criteria
- [ ] `StoreKitService` protocol with `purchase(productID:)`, `restorePurchases()`, `isEntitled(to:)`, `products` property
- [ ] Product ID: `com.fastydiscount.removeads` (non-consumable)
- [ ] `Product.products(for:)` loads available products from App Store
- [ ] Purchase flow: `product.purchase()` with transaction verification
- [ ] Transaction listener: `Transaction.updates` observed for real-time entitlement changes
- [ ] Entitlement check: `Transaction.currentEntitlements` iterated on app launch
- [ ] `isAdFree` published property that gates ad display across the app
- [ ] Restore purchases: iterates `Transaction.currentEntitlements` and restores
- [ ] Receipt validation: use StoreKit 2's built-in JWS verification (no server needed)
- [ ] Error handling: purchase cancelled, purchase pending (Ask to Buy), purchase failed, network error
- [ ] Entitlement cached in UserDefaults for fast access; re-verified from StoreKit on launch

## Technical Notes
- StoreKit 2 uses async/await natively -- no need for transaction observers like StoreKit 1
- Configure the product in App Store Connect (or use a StoreKit configuration file for testing)
- Create a `Products.storekit` configuration file in the project for local testing
- `Transaction.currentEntitlements` returns all verified, non-revoked purchases
- Cache: `UserDefaults.standard.set(true, forKey: "isAdFree")` on verified purchase; re-check on launch
- Handle `Transaction.updates` in a long-running `Task` started at app launch
- For Ask to Buy (family sharing): handle `.pending` verification result
