import SwiftUI

// MARK: - CameraScannerView

/// Full-screen camera scanner view with live barcode/QR detection.
///
/// Features:
/// - Live camera preview with scanning overlay
/// - Real-time barcode bounding box visualization
/// - Animated scanning line within the guide frame
/// - Auto-capture on first detection with haptic feedback
/// - Result view with options to create a DVG or scan again
/// - Torch toggle for low-light scanning
/// - Camera permission handling with settings link
/// - Mac Catalyst placeholder
struct CameraScannerView: View {

    // MARK: - Environment

    @Environment(NavigationRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var viewModel = ScannerViewModel()
    @State private var importViewModel = ImportViewModel()
    @State private var isProcessingPhoto: Bool = false

    // MARK: - Body

    var body: some View {
        #if targetEnvironment(macCatalyst)
        macCatalystPlaceholder
        #else
        scannerContent
        #endif
    }

    // MARK: - Scanner Content

    @ViewBuilder
    private var scannerContent: some View {
        ZStack {
            switch viewModel.permissionStatus {
            case .authorized:
                cameraView
            case .denied, .restricted:
                permissionDeniedView
            case .notDetermined:
                permissionRequestView
            }
        }
        .ignoresSafeArea(.all, edges: .all)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                closeButton
            }
        }
        .task {
            await viewModel.checkCameraPermission()
        }
        .onDisappear {
            viewModel.stopSession()
        }
        .onChange(of: viewModel.capturedImageData) { _, newData in
            guard let data = newData else { return }
            Task {
                await processAndNavigate(imageData: data)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Camera View (Authorized)

    @ViewBuilder
    private var cameraView: some View {
        ZStack {
            // Layer 1: Camera preview
            CameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()

            // Layer 2: Scanning overlay with guide frame
            if viewModel.scannerState == .scanning {
                ScanningOverlayView(liveBoundingBox: viewModel.liveBoundingBox)
            }

            // Layer 3: Bounding box highlight for detected barcode
            if viewModel.scannerState == .detected, let barcode = viewModel.detectedBarcode {
                BoundingBoxOverlay(boundingBox: barcode.boundingBox)
            }

            // Layer 4: Controls overlay
            VStack {
                Spacer()

                if viewModel.scannerState == .detected, let barcode = viewModel.detectedBarcode {
                    ScanResultCardView(
                        barcode: barcode,
                        onCreateDVG: { createDVG(from: barcode) },
                        onScanAgain: { viewModel.resumeScanning() },
                        onSwitchToOCR: { switchToTextOCR() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.scannerState == .scanning {
                    scanningControlsBar
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.scannerState)
        }
    }

    // MARK: - Scanning Controls Bar

    @ViewBuilder
    private var scanningControlsBar: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Take Photo button — centered, prominent shutter button
            Button {
                viewModel.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 70, height: 70)
                    Circle()
                        .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                        .frame(width: 82, height: 82)
                    if viewModel.isCapturing || isProcessingPhoto {
                        ProgressView()
                            .tint(Theme.Colors.primary)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
            }
            .disabled(viewModel.isCapturing || isProcessingPhoto)
            .accessibilityLabel("Take photo")
            .accessibilityHint("Captures the current camera frame and extracts coupon details using AI")

            // Secondary controls row
            HStack(spacing: Theme.Spacing.lg) {
                // Torch toggle
                Button {
                    viewModel.toggleTorch()
                } label: {
                    Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(viewModel.isTorchOn ? "Turn off flashlight" : "Turn on flashlight")
                .accessibilityHint("Toggles the device flashlight for low-light scanning")

                Spacer()

                // Switch to OCR
                Button {
                    switchToTextOCR()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "text.viewfinder")
                        Text("Text OCR")
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Switch to text OCR mode")
                .accessibilityHint("Use text recognition instead of barcode scanning")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xl + 20)
    }

    // MARK: - Close Button

    @ViewBuilder
    private var closeButton: some View {
        Button {
            viewModel.stopSession()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Close scanner")
        .accessibilityHint("Stops the camera and returns to the previous screen")
    }

    // MARK: - Permission Denied View

    @ViewBuilder
    private var permissionDeniedView: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "camera.fill")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)

                Text("Camera Access Required")
                    .font(Theme.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("FastyDiscount needs camera access to scan barcodes and QR codes on your discount vouchers.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)

                Button {
                    viewModel.openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .accessibilityHint("Opens the Settings app to enable camera permission")
            }
        }
    }

    // MARK: - Permission Request View (Loading)

    @ViewBuilder
    private var permissionRequestView: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.Colors.primary)

                Text("Requesting camera access...")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Mac Catalyst Placeholder

    @ViewBuilder
    private var macCatalystPlaceholder: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "camera.metering.unknown")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)

            Text("Camera Not Available")
                .font(Theme.Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Camera scanning is not available on Mac.\nPlease use photo or PDF import instead.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
        }
        .padding(Theme.Spacing.xl)
        .navigationTitle("Scanner")
    }

    // MARK: - Actions

    /// Navigates to the scan results view with the detected barcode as input.
    ///
    /// The scanner session is stopped before navigation so the camera is released.
    /// Also records the scan in `ScanCounter` to track interstitial ad thresholds.
    private func createDVG(from barcode: DetectedBarcode) {
        viewModel.stopSession()
        // Record the completed scan so the interstitial threshold can be tracked.
        ScanCounter.shared.recordScan()
        let inputData = ScanInputData.barcodeOnly(
            barcode: barcode,
            originalImageData: barcode.imageData
        )
        router.push(.scanResults(inputData))
    }

    /// Switches to text OCR mode.
    private func switchToTextOCR() {
        viewModel.stopSession()
        router.push(.textOCR)
    }

    /// Processes captured image data through the import pipeline (barcode detection + OCR + AI),
    /// then navigates to the scan results view.
    private func processAndNavigate(imageData: Data) async {
        // Stop the camera session while processing
        viewModel.stopSession()
        viewModel.clearCapturedPhoto()
        ScanCounter.shared.recordScan()

        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        await importViewModel.processRawImageData(imageData)

        // Construct ScanInputData from the processing results
        let inputData: ScanInputData

        if let aiResult = importViewModel.aiExtractionResult, aiResult.confidenceScore > 0 {
            // AI parsing succeeded — use the richest result
            let barcode = importViewModel.detectedBarcodes.first
            inputData = .aiParsed(
                extraction: aiResult,
                barcode: barcode,
                originalImageData: importViewModel.barcodeImageData
            )
        } else if let primaryBarcode = importViewModel.detectedBarcodes.first {
            // AI not available but a barcode was detected
            inputData = .barcodeOnly(
                barcode: primaryBarcode,
                originalImageData: importViewModel.barcodeImageData
            )
        } else {
            // Fall back to OCR text only
            let ocrText = importViewModel.extractedTextCombined
            inputData = .ocrTextOnly(
                text: ocrText.isEmpty ? "No content detected" : ocrText,
                originalImageData: importViewModel.barcodeImageData
            )
        }

        router.push(.scanResults(inputData))
    }
}

// MARK: - ScanningOverlayView

/// Draws the scanning guide frame with animated scanning line
/// and darkened border regions.
private struct ScanningOverlayView: View {

    /// Live bounding box of any detected barcode (for real-time feedback).
    let liveBoundingBox: CGRect?

    /// Animation state for the scanning line.
    @State private var scanLineOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geometry in
            let guideSize = min(geometry.size.width * 0.7, geometry.size.height * 0.4)
            let guideRect = CGRect(
                x: (geometry.size.width - guideSize) / 2,
                y: (geometry.size.height - guideSize) / 2 - 40,
                width: guideSize,
                height: guideSize
            )

            ZStack {
                // Darkened overlay outside the guide frame
                ScannerMaskShape(guideRect: guideRect)
                    .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()

                // Guide frame corners
                GuideFrameView(rect: guideRect)

                // Animated scanning line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.Colors.primary.opacity(0),
                                Theme.Colors.primary.opacity(0.8),
                                Theme.Colors.primary.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: guideSize - 20, height: 2)
                    .offset(
                        x: 0,
                        y: guideRect.midY - geometry.size.height / 2 + (scanLineOffset * (guideSize / 2 - 10))
                    )

                // Instruction text
                VStack {
                    Spacer()
                        .frame(height: guideRect.maxY + Theme.Spacing.lg)

                    Text("Align barcode within the frame")
                        .font(Theme.Typography.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                scanLineOffset = 1.0
            }
        }
    }
}

// MARK: - ScannerMaskShape

/// A shape that fills the entire frame except for the rectangular guide area.
private struct ScannerMaskShape: Shape {
    let guideRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: guideRect, cornerSize: CGSize(width: 12, height: 12))
        return path
    }
}

// MARK: - GuideFrameView

/// Draws corner brackets around the scanning guide rectangle.
private struct GuideFrameView: View {
    let rect: CGRect

    private let cornerLength: CGFloat = 30
    private let lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, _ in
            let color = Theme.Colors.primary

            // Top-left corner
            drawCorner(context: &context, origin: CGPoint(x: rect.minX, y: rect.minY),
                       dx: cornerLength, dy: cornerLength, color: color)

            // Top-right corner
            drawCorner(context: &context, origin: CGPoint(x: rect.maxX, y: rect.minY),
                       dx: -cornerLength, dy: cornerLength, color: color)

            // Bottom-left corner
            drawCorner(context: &context, origin: CGPoint(x: rect.minX, y: rect.maxY),
                       dx: cornerLength, dy: -cornerLength, color: color)

            // Bottom-right corner
            drawCorner(context: &context, origin: CGPoint(x: rect.maxX, y: rect.maxY),
                       dx: -cornerLength, dy: -cornerLength, color: color)
        }
    }

    private func drawCorner(
        context: inout GraphicsContext,
        origin: CGPoint,
        dx: CGFloat,
        dy: CGFloat,
        color: Color
    ) {
        var path = Path()
        path.move(to: CGPoint(x: origin.x + dx, y: origin.y))
        path.addLine(to: origin)
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + dy))

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - BoundingBoxOverlay

/// Draws a highlighted bounding box around a detected barcode on the camera preview.
///
/// Vision bounding boxes are normalized (0-1) with origin at bottom-left.
/// This view converts to SwiftUI coordinates (origin at top-left).
private struct BoundingBoxOverlay: View {
    let boundingBox: CGRect

    var body: some View {
        GeometryReader { geometry in
            let convertedRect = convertToViewCoordinates(
                boundingBox: boundingBox,
                viewSize: geometry.size
            )

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.Colors.success, lineWidth: 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Colors.success.opacity(0.15))
                )
                .frame(width: convertedRect.width, height: convertedRect.height)
                .position(
                    x: convertedRect.midX,
                    y: convertedRect.midY
                )
        }
        .allowsHitTesting(false)
    }

    /// Converts Vision normalized coordinates (bottom-left origin) to
    /// SwiftUI view coordinates (top-left origin).
    private func convertToViewCoordinates(boundingBox: CGRect, viewSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.origin.x * viewSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * viewSize.height,
            width: boundingBox.width * viewSize.width,
            height: boundingBox.height * viewSize.height
        )
    }
}

// MARK: - ScanResultCardView

/// Card shown after a barcode is successfully detected, displaying the
/// decoded value and barcode type with action buttons.
private struct ScanResultCardView: View {

    let barcode: DetectedBarcode
    let onCreateDVG: () -> Void
    let onScanAgain: () -> Void
    let onSwitchToOCR: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Header
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.success)
                    .accessibilityHidden(true)

                Text("Barcode Detected")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()
            }

            // Decoded value
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Value")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text(barcode.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Barcode type badge
            HStack(spacing: Theme.Spacing.sm) {
                Text("Type")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text(barcode.barcodeType.displayName)
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(
                        Theme.Colors.primary.opacity(0.12),
                        in: Capsule()
                    )

                Spacer()

                Text("Confidence: \(Int(barcode.confidence * 100))%")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Divider()
                .background(Theme.Colors.border)

            // Action buttons
            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    onCreateDVG()
                } label: {
                    Label("Create DVG", systemImage: "plus.circle.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .accessibilityLabel("Create a new discount voucher from this barcode")

                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        onScanAgain()
                    } label: {
                        Label("Scan Again", systemImage: "barcode.viewfinder")
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .strokeBorder(Theme.Colors.primary, lineWidth: 1.5)
                            )
                    }
                    .accessibilityLabel("Scan another barcode")

                    Button {
                        onSwitchToOCR()
                    } label: {
                        Label("Text OCR", systemImage: "text.viewfinder")
                            .font(Theme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 1.5)
                            )
                    }
                    .accessibilityLabel("Switch to text recognition mode")
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -4)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Camera Scanner") {
    NavigationStack {
        CameraScannerView()
    }
    .environment(NavigationRouter())
}
#endif
