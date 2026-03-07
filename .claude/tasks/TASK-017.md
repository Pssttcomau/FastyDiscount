# TASK-017: Build camera scanner view with live barcode/QR detection (Vision framework)

## Description
Build a live camera scanner view that detects barcodes (UPC, EAN), QR codes, and PDF417 codes in real-time using Apple's Vision framework (`VNDetectBarcodesRequest`). The view shows a camera preview with a scanning overlay and automatically captures detected codes.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (camera usage permission in Info.plist)
- TASK-006 (theme system)

## Acceptance Criteria
- [ ] Full-screen camera preview using `AVCaptureSession` with `UIViewRepresentable` wrapper
- [ ] Vision `VNDetectBarcodesRequest` running on each video frame for barcode detection
- [ ] Supported symbologies: `.qr`, `.ean8`, `.ean13`, `.upce`, `.pdf417`, `.code128`, `.code39`
- [ ] Scanning overlay: rectangular guide frame with animated scanning line
- [ ] Haptic feedback (`UIImpactFeedbackGenerator`) on successful detection
- [ ] Detected code highlighted with a bounding box overlay on the camera preview
- [ ] Auto-capture: first successful detection pauses scanning and shows result
- [ ] Result view shows: decoded value, barcode type, option to "Create DVG" or "Scan Again"
- [ ] Camera capture of the barcode area saved as `barcodeImageData` (cropped to barcode region)
- [ ] "Switch to Text OCR" button for text-based coupons (transitions to OCR mode)
- [ ] Camera permission handling: request on first use, show settings link if denied
- [ ] Torch/flashlight toggle button for low-light scanning
- [ ] `@Observable` `ScannerViewModel` managing camera session and detection state

## Technical Notes
- Use `AVCaptureVideoDataOutput` with `setSampleBufferDelegate` to get frames
- Convert `CMSampleBuffer` to `CIImage` for Vision requests
- Run Vision requests on a background queue (not main thread)
- For barcode region capture: use `VNDetectedObjectObservation.boundingBox` to crop the frame
- Bounding box is normalized (0-1); convert to image coordinates for cropping
- On Mac Catalyst: show a placeholder directing user to photo/PDF import instead
- Memory: release camera session when view disappears
