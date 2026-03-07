# TASK-035: Implement Watch Connectivity data transfer from iPhone to Watch

## Description
Implement the Watch Connectivity framework integration on both iPhone and Apple Watch sides. The iPhone sends active DVG data to the watch, and the watch sends "Mark as Used" actions back. Data syncs automatically when either device is in range.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-007 (DVG model)
- TASK-034 (Watch app that receives data)

## Acceptance Criteria
- [ ] `WatchConnectivityService` class on iPhone implementing `WCSessionDelegate`
- [ ] `WatchConnectivityService` class on Watch implementing `WCSessionDelegate`
- [ ] iPhone sends active DVGs via `updateApplicationContext` (latest state, replaces previous)
- [ ] `WatchDVG` lightweight Codable struct: id, title, storeName, code, decodedBarcodeValue, barcodeType, dvgType, expirationDate, discountDescription, isFavorite
- [ ] Barcode image data transferred via `transferUserInfo` (too large for application context)
- [ ] Watch receives and caches DVG data locally (JSON file in documents)
- [ ] Watch sends "Mark as Used" action via `sendMessage` (real-time) with fallback to `transferUserInfo` (background)
- [ ] iPhone handles "Mark as Used" by updating DVG via `DVGRepository`
- [ ] Auto-sync triggers: on DVG create/update/delete, on app launch, on watch app activation
- [ ] Error handling: session not supported, session not activated, transfer failures

## Technical Notes
- `WCSession.default.activate()` must be called on both sides at app launch
- `applicationContext` is limited to ~262KB -- if DVG list is large, send only essential fields
- For barcode images: use `transferUserInfo` which queues and sends in background
- Consider sending only changed DVGs via `transferUserInfo` to reduce bandwidth
- `sendMessage` requires the counterpart app to be reachable; use `isReachable` check
- Fallback: if not reachable, queue the action and send when connection is restored
- Watch Connectivity runs on a background thread -- dispatch UI updates to main actor
