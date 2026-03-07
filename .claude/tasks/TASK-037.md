# TASK-037: Build Share Sheet extension for importing text, URLs, images, and PDFs

## Description
Build an iOS Share Sheet (Action) extension that accepts shared content from other apps and creates DVGs from it. The extension performs lightweight on-device parsing and saves to the shared SwiftData container. Complex AI parsing is deferred to the main app.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (Share extension target with App Group)
- TASK-002 (shared SwiftData container)
- TASK-007 (DVG model)
- TASK-017 (barcode detection logic, reusable)

## Acceptance Criteria
- [ ] Share extension accepts: `public.plain-text`, `public.url`, `public.image`, `com.adobe.pdf`
- [ ] `NSExtensionActivationRule` configured in Info.plist with type-specific rules
- [ ] Text input: regex extraction for common code patterns (alphanumeric codes, percentages, dollar amounts)
- [ ] URL input: extract domain as potential store name, show URL in notes
- [ ] Image input: run `VNDetectBarcodesRequest` for barcode detection, `VNRecognizeTextRequest` for OCR
- [ ] PDF input: render first page as image, process through barcode + OCR pipeline
- [ ] Compact DVG creation form in the extension (title, code, store, type picker)
- [ ] Pre-populated fields from extraction results
- [ ] Save button writes to shared SwiftData container (App Group)
- [ ] Cancel button dismisses extension without saving
- [ ] Saved DVG marked with `source = .scan` and a note indicating "Imported via Share Sheet"
- [ ] Extension runs within memory limits (~120MB) -- no Cloud AI calls
- [ ] Main app detects new DVGs on next launch and shows "Review imported DVGs" if AI parsing would help

## Technical Notes
- Share extension uses `NSExtensionContext` to receive items
- Extract `NSItemProvider` for each attachment type
- For images: `loadItem(forTypeIdentifier: UTType.image.identifier)` returns `UIImage` or `Data`
- For PDFs: `loadItem(forTypeIdentifier: UTType.pdf.identifier)` returns `URL` to temp file
- Vision processing must be fast -- use `.fast` recognition level for OCR
- The extension UI should be a compact SwiftUI view embedded in a `UIHostingController`
- shared `ModelContainer` from the App Group container (same as TASK-002)
- Consider using `@MainActor` for the extension's view controller
