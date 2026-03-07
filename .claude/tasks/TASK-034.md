# TASK-034: Build Apple Watch app with DVG list and full-screen barcode display

## Description
Build the watchOS companion app that displays active DVGs in a scrollable list and allows the user to tap a DVG to show its barcode/QR code in full-screen mode for scanning at POS. The watch app also shows a complication for the next expiring DVG.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (watchOS app and extension targets)
- TASK-035 (Watch Connectivity for data transfer -- can be developed in parallel)
- TASK-007 (DVG model for shared data types)

## Acceptance Criteria
- [ ] watchOS app entry point with SwiftUI `@main` App
- [ ] `DVGListView`: scrollable list of active DVGs showing title, store, expiry badge, type icon
- [ ] Tapping a DVG opens `DVGBarcodeView`: full-screen barcode/QR code display
- [ ] Barcode rendering: use CIFilter to generate barcode from decoded value (same as iOS app)
- [ ] Brightness auto-increased to maximum when showing barcode (for scanner readability)
- [ ] Code text displayed below barcode for manual entry fallback
- [ ] "Mark as Used" button on the barcode view (sends action to iPhone via Watch Connectivity)
- [ ] Complication: `WidgetFamily.accessoryCircular` showing days until next expiry
- [ ] Complication: `WidgetFamily.accessoryRectangular` showing next DVG title + days
- [ ] Empty state when no DVGs synced ("Open FastyDiscount on iPhone to sync")
- [ ] DVGs sorted by expiry date (soonest first), then by favorite status
- [ ] Local data cache on watch for offline viewing

## Technical Notes
- Watch app uses its own local storage (not shared SwiftData container)
- DVGs synced from iPhone via Watch Connectivity (`WCSession.transferUserInfo` or `updateApplicationContext`)
- Define a lightweight `WatchDVG` Codable struct for watch-side storage (subset of full DVG fields)
- Barcode rendering on watch: `CIFilter` is available on watchOS; use `CIQRCodeGenerator` and `CICode128BarcodeGenerator`
- Brightness: use `WKInterfaceDevice.current().play(.click)` and request bright mode
- Complications: use `WidgetKit` for watchOS complications (iOS 17+)
- Local cache: store `[WatchDVG]` as JSON in watch's local documents directory
- "Mark as Used" sends message to iPhone app via `WCSession.sendMessage` with DVG ID
