# TASK-018: Implement photo library and PDF document import with barcode extraction

## Description
Build the import flow for photos from the photo library and PDF documents from Files. Extract barcodes and text from imported images/PDFs using Vision framework. This complements the live camera scanner for cases where the user already has a photo or PDF coupon.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (photo library permission in Info.plist)
- TASK-017 (shared scanner infrastructure -- VNDetectBarcodesRequest setup)

## Acceptance Criteria
- [ ] Photo picker using `PHPickerViewController` (SwiftUI `PhotosPicker`) for image selection
- [ ] Document picker using `UIDocumentPickerViewController` for PDF import
- [ ] Selected image/PDF processed through `VNDetectBarcodesRequest` for barcode detection
- [ ] Text extraction via `VNRecognizeTextRequest` for OCR fallback when no barcode found
- [ ] PDF pages rendered as images using `PDFKit` (`PDFPage.thumbnail`) for Vision processing
- [ ] Multi-page PDF: process each page, collect all detected codes and text
- [ ] Results displayed: detected barcodes listed, extracted text shown, "Create DVG" button
- [ ] Original image/PDF stored as `barcodeImageData` (compressed JPEG)
- [ ] Progress indicator for multi-page PDF processing
- [ ] Error handling: unsupported file format, corrupted PDF, no content detected

## Technical Notes
- `PHPickerViewController` does not require photo library permission for selection-only access
- For PDF: use `PDFDocument(url:)` -> iterate pages -> `PDFPage.thumbnail(of:for:)` at sufficient resolution for OCR
- Vision requests should run on background thread
- Compress images to max 1MB before storing in SwiftData (use `UIImage.jpegData(compressionQuality:)`)
- If both barcodes and text are found, present barcodes as primary results with text as supplementary
- Share common barcode detection logic with TASK-017 (extract to a shared `BarcodeDetectionService`)
