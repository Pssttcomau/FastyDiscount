# TASK-036: Build Apple Wallet pass generation for barcoded DVGs (PassKit)

## Description
Implement the ability to add barcoded DVGs as passes in Apple Wallet using PassKit. Generate `.pkpass` files with barcode data, store name, code, and expiry date. Passes update when DVGs are modified and are removed when used/expired.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-007 (DVG model with barcode data)
- TASK-010 (DVG detail view where "Add to Wallet" button lives)

## Acceptance Criteria
- [ ] "Add to Apple Wallet" button on DVG detail view for DVGs with barcode/QR data
- [ ] `PKPass` generation with: store name as organization, DVG title as description, barcode, expiry date
- [ ] Barcode rendering on pass: QR, Code128, PDF417, or Aztec based on `barcodeType`
- [ ] Pass type: `coupon` (most appropriate for discounts/vouchers)
- [ ] Pass fields: header (store name), primary (discount description), secondary (code), auxiliary (expiry date)
- [ ] Pass presented via `PKAddPassesViewController` for user confirmation
- [ ] Pass update: when DVG is edited, update the corresponding pass (via pass type identifier + serial number)
- [ ] Pass removal: when DVG is marked as used/expired, suggest removing the pass
- [ ] `PassKitService` protocol with `generatePass(for:)`, `addPass(_:)`, `removePass(for:)`, `isPassAdded(for:)`
- [ ] Wallet button only shown on devices that support `PKAddPassesViewController.canAddPasses()`

## Technical Notes
- PassKit requires a Pass Type ID registered in Apple Developer portal and a signing certificate
- Generating `.pkpass` files requires: `pass.json` manifest, images (logo, icon), signing with certificate
- For development: use a development signing certificate; for production: distribution certificate
- Pass serial number: use DVG's UUID string
- Pass type identifier: `pass.com.fastydiscount.dvg`
- Barcode in pass: `PKBarcodeFormat.qr`, `.code128`, `.pdf417`, or `.aztec`
- Alternative approach: use `PKAddPassButton` SwiftUI view for the button
- If signing infrastructure is too complex for v1, consider deferring to v1.1 and showing a placeholder
- Pass update requires server-side push notifications (APNs to Wallet); for v1, consider just replacing the pass
