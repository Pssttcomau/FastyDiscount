# TASK-020: Build scan results UI with pre-populated DVG creation form

## Description
Build the UI that displays scan results (from camera, photo, or PDF) and allows the user to create a DVG from the extracted data. Shows detected barcodes, OCR text, and AI-parsed fields in an editable form. This is the bridge between scanning and DVG creation.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-017 (camera scanner results)
- TASK-018 (photo/PDF import results)
- TASK-019 (AI vision parsing results)
- TASK-011 (DVG form view for creation)

## Acceptance Criteria
- [ ] Results view shows: scanned image thumbnail, detected barcode value and type, AI-extracted fields
- [ ] If AI parsing succeeded: DVG form pre-populated with extracted data, user can review and edit
- [ ] If only barcode detected (no AI): pre-populate code field and barcode type, user fills rest manually
- [ ] If only OCR text (no AI, offline): show raw text with "Create DVG Manually" button
- [ ] Confidence indicators on AI-extracted fields (same color coding as review queue)
- [ ] "Save DVG" button creates the DVG with `source = .scan` and attached `ScanResult`
- [ ] "Scan Again" button returns to scanner
- [ ] Original image saved to `ScanResult.originalImageData`
- [ ] Smooth transition from scanner/picker to results view
- [ ] `@Observable` `ScanResultsViewModel` managing the state

## Technical Notes
- This view reuses the DVG form component from TASK-011 in pre-populated mode
- The `ScanResult` model is created and linked to the DVG on save
- If the user came from the camera scanner: show the captured barcode image
- If from photo/PDF: show the selected image/first PDF page
- Consider using a `sheet` presentation from the scanner view for the results
