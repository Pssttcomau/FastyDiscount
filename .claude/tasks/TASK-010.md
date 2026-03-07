# TASK-010: Create DVG detail view (read-only display with barcode rendering)

## Description
Build the DVG detail view that displays all DVG information in a clean, scannable layout. The view must render barcodes/QR codes for POS display, show balance and points, display store locations on a mini-map, and provide action buttons (Mark Used, Edit, Share, Add to Wallet).

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-007 (DVG model)
- TASK-006 (theme system)
- TASK-005 (navigation, for destination routing)

## Acceptance Criteria
- [ ] Full DVG detail layout with sections: Code Display, Details, Store/Location, Notes/Terms
- [ ] Barcode/QR rendering from `decodedBarcodeValue` using `CIFilter` barcode generators (`CICode128BarcodeGenerator`, `CIQRCodeGenerator`, etc.)
- [ ] If `barcodeImageData` exists, display original scanned image as alternative
- [ ] Code text displayed in large, monospace font with tap-to-copy functionality
- [ ] Expiry date with color-coded urgency (green > 7 days, yellow 3-7 days, red < 3 days)
- [ ] Balance/points display for gift card and loyalty types with "Record Usage" button
- [ ] Mini-map showing store location(s) if available (MapKit snapshot)
- [ ] Tags displayed as colored pills/chips
- [ ] Action toolbar: Mark as Used, Edit (navigates to form), Favorite toggle, Share (UIActivityViewController)
- [ ] Adaptive layout: compact on iPhone, wider on iPad with side-by-side sections
- [ ] VoiceOver labels for all interactive elements
- [ ] Dynamic Type support for all text

## Technical Notes
- Use `CIFilter` for barcode generation: `CICode128BarcodeGenerator` for 1D codes, `CIQRCodeGenerator` for QR
- For UPC/EAN: use `CICode128BarcodeGenerator` as fallback since iOS does not have dedicated UPC CIFilter
- Tap-to-copy: use `UIPasteboard.general.string = code` with a brief "Copied!" toast
- Mini-map: use `MKMapSnapshotter` for a static image, or a small `Map` view with a pin
- The "Record Usage" button for gift cards should show an alert/sheet asking for amount spent, then update `remainingBalance`
- Share action: share the code text and store name
