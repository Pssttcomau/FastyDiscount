import AVFoundation
import CoreImage
import os
import SwiftUI
import Vision

// MARK: - CameraPermissionStatus

/// Represents the current camera authorization state for the scanner UI.
enum CameraPermissionStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

// MARK: - ScannerState

/// The overall state of the camera scanner flow.
enum ScannerState: Equatable, Sendable {
    /// Camera is active, scanning for barcodes.
    case scanning
    /// A barcode has been detected; camera is paused.
    case detected
    /// The scanner is paused (e.g., app in background).
    case paused
}

// MARK: - DetectedBarcode

/// Holds the result of a successful barcode detection.
struct DetectedBarcode: Sendable {
    /// The decoded string value from the barcode.
    let value: String
    /// The type of barcode that was detected.
    let barcodeType: BarcodeType
    /// Confidence score from the Vision framework (0.0 - 1.0).
    let confidence: Float
    /// Normalized bounding box of the detected barcode (in Vision coordinates: origin at bottom-left).
    let boundingBox: CGRect
    /// Cropped image data of the barcode region (JPEG).
    let imageData: Data?
}

// MARK: - ScannerViewModel

/// ViewModel managing the camera capture session, barcode detection via Vision,
/// and scanner state transitions.
///
/// This class is `@MainActor` per project conventions. The `AVCaptureSession`
/// delegate callbacks happen on a background queue; all observation data is
/// extracted on that queue and only `Sendable` types are dispatched to main.
@Observable
@MainActor
final class ScannerViewModel {

    // MARK: - Published State

    /// Current scanner state.
    var scannerState: ScannerState = .scanning

    /// Camera permission status.
    var permissionStatus: CameraPermissionStatus = .notDetermined

    /// The most recently detected barcode result.
    var detectedBarcode: DetectedBarcode?

    /// Normalized bounding box for overlay rendering (in Vision coordinates).
    /// Updated on each frame where a barcode is visible, cleared when not.
    var liveBoundingBox: CGRect?

    /// Whether the torch (flashlight) is currently on.
    var isTorchOn: Bool = false

    /// Error message to display, if any.
    var errorMessage: String?

    /// Whether an error alert should be shown.
    var showError: Bool = false

    // MARK: - Camera Session

    /// The capture session. Accessed by `CameraPreviewView` to display the live feed.
    let captureSession = AVCaptureSession()

    // MARK: - Private Properties

    /// The delegate that processes video frames on a background queue.
    /// Stored as a strong reference to keep it alive for the session lifetime.
    private var frameDelegate: FrameProcessorDelegate?

    /// Background queue for the capture session.
    private let sessionQueue = DispatchQueue(label: "com.fastydiscount.scanner.session", qos: .userInitiated)

    /// Background queue for Vision barcode detection.
    private let visionQueue = DispatchQueue(label: "com.fastydiscount.scanner.vision", qos: .userInitiated)

    /// Haptic feedback generator for barcode detection.
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Supported Vision barcode symbologies.
    private let supportedSymbologies: [VNBarcodeSymbology] = [
        .qr, .ean8, .ean13, .upce, .pdf417, .code128, .code39
    ]

    // MARK: - Init

    init() {
        hapticGenerator.prepare()
    }

    // MARK: - Permission Handling

    /// Checks the current camera authorization status and requests access if needed.
    func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            permissionStatus = .authorized
            setupCaptureSession()

        case .notDetermined:
            permissionStatus = .notDetermined
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                permissionStatus = .authorized
                setupCaptureSession()
            } else {
                permissionStatus = .denied
            }

        case .denied:
            permissionStatus = .denied

        case .restricted:
            permissionStatus = .restricted

        @unknown default:
            permissionStatus = .denied
        }
    }

    /// Opens the system Settings app so the user can grant camera permission.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Session Setup

    /// Configures the AVCaptureSession with camera input and video data output.
    private func setupCaptureSession() {
        let session = captureSession
        let symbologies = supportedSymbologies

        // The delegate extracts all data from observations on the vision queue
        // and only passes Sendable types (DetectedBarcode, CGRect?) to main.
        let delegate = FrameProcessorDelegate(
            symbologies: symbologies,
            onBarcodeDetected: { [weak self] detected in
                Task { @MainActor [weak self] in
                    self?.handleDetection(detected)
                }
            },
            onBoundingBoxUpdate: { [weak self] box in
                Task { @MainActor [weak self] in
                    self?.liveBoundingBox = box
                }
            }
        )
        self.frameDelegate = delegate

        let vQueue = visionQueue
        sessionQueue.async {
            session.beginConfiguration()
            session.sessionPreset = .high

            // Add camera input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                session.commitConfiguration()
                return
            }

            // Add video data output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(delegate, queue: vQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            session.startRunning()
        }
    }

    // MARK: - Detection Handling

    /// Called on the main actor when the frame processor has extracted a barcode.
    private func handleDetection(_ detected: DetectedBarcode) {
        guard scannerState == .scanning else { return }

        // Pause scanning and trigger haptic
        scannerState = .detected
        detectedBarcode = detected
        liveBoundingBox = detected.boundingBox
        hapticGenerator.impactOccurred()

        // Pause the frame delegate so it stops processing
        frameDelegate?.isPaused = true
    }

    // MARK: - Scanner Controls

    /// Resumes scanning after a detection, clearing the previous result.
    func resumeScanning() {
        detectedBarcode = nil
        liveBoundingBox = nil
        scannerState = .scanning
        frameDelegate?.isPaused = false
    }

    /// Pauses the scanner (e.g., when the view disappears).
    func pauseScanner() {
        scannerState = .paused
        frameDelegate?.isPaused = true
    }

    /// Stops the capture session and releases resources.
    func stopSession() {
        let session = captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        frameDelegate = nil
    }

    /// Starts the capture session if it was stopped.
    func startSession() {
        let session = captureSession
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
        if scannerState == .paused {
            scannerState = .scanning
            frameDelegate?.isPaused = false
        }
    }

    // MARK: - Torch Control

    /// Toggles the device torch (flashlight) on or off.
    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            let newMode: AVCaptureDevice.TorchMode = isTorchOn ? .off : .on
            if device.isTorchModeSupported(newMode) {
                device.torchMode = newMode
                isTorchOn = !isTorchOn
            }
            device.unlockForConfiguration()
        } catch {
            presentError("Failed to toggle flashlight.")
        }
    }

    // MARK: - Error Presentation

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - FrameProcessorDelegate

/// Processes video frames from `AVCaptureVideoDataOutput` and runs Vision
/// barcode detection on each frame.
///
/// All Vision observation data is extracted on the calling (vision) queue.
/// Only `Sendable` types (`DetectedBarcode`, `CGRect?`) are dispatched
/// to the main actor via closures, satisfying Swift 6 strict concurrency.
///
/// Mutable state (`isPaused`, `frameCount`) is protected by
/// `OSAllocatedUnfairLock` so it can be safely written from `@MainActor`
/// and read on the serial vision queue without data races.
private final class FrameProcessorDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    /// Lock-protected pause flag. Written from `@MainActor`, read on the vision queue.
    private let pauseLock = OSAllocatedUnfairLock(initialState: false)

    /// Thread-safe accessor for the pause state.
    var isPaused: Bool {
        get { pauseLock.withLock { $0 } }
        set { pauseLock.withLock { $0 = newValue } }
    }

    private let symbologies: [VNBarcodeSymbology]
    private let onBarcodeDetected: @Sendable (DetectedBarcode) -> Void
    private let onBoundingBoxUpdate: @Sendable (CGRect?) -> Void

    /// Lock-protected frame counter. Incremented on the vision queue.
    private let frameCountLock = OSAllocatedUnfairLock(initialState: 0)
    private let processEveryNthFrame: Int = 3

    /// Shared CIContext for image cropping (thread-safe).
    private let ciContext = CIContext()

    init(
        symbologies: [VNBarcodeSymbology],
        onBarcodeDetected: @escaping @Sendable (DetectedBarcode) -> Void,
        onBoundingBoxUpdate: @escaping @Sendable (CGRect?) -> Void
    ) {
        self.symbologies = symbologies
        self.onBarcodeDetected = onBarcodeDetected
        self.onBoundingBoxUpdate = onBoundingBoxUpdate
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isPaused else { return }

        let shouldProcess = frameCountLock.withLock { count -> Bool in
            count += 1
            return count % processEveryNthFrame == 0
        }
        guard shouldProcess else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        do {
            try handler.perform([request])

            guard let results = request.results, !results.isEmpty else {
                onBoundingBoxUpdate(nil)
                return
            }

            // Take the highest-confidence result
            if let best = results.max(by: { $0.confidence < $1.confidence }) {
                onBoundingBoxUpdate(best.boundingBox)

                // Extract all data from the observation on this queue
                // so only Sendable types cross the actor boundary.
                if let detected = extractDetectedBarcode(from: best, ciImage: ciImage) {
                    onBarcodeDetected(detected)
                }
            }
        } catch {
            // Vision request failed -- silently continue to next frame
            onBoundingBoxUpdate(nil)
        }
    }

    // MARK: - Data Extraction (runs on vision queue)

    /// Extracts all needed data from a `VNBarcodeObservation` and the frame image,
    /// returning a fully `Sendable` `DetectedBarcode`.
    private func extractDetectedBarcode(from observation: VNBarcodeObservation, ciImage: CIImage) -> DetectedBarcode? {
        guard let payloadString = observation.payloadStringValue, !payloadString.isEmpty else {
            return nil
        }

        let barcodeType = Self.mapSymbology(observation.symbology)
        let boundingBox = observation.boundingBox
        let confidence = observation.confidence
        let imageData = cropBarcodeRegion(from: ciImage, boundingBox: boundingBox)

        return DetectedBarcode(
            value: payloadString,
            barcodeType: barcodeType,
            confidence: confidence,
            boundingBox: boundingBox,
            imageData: imageData
        )
    }

    /// Crops the barcode region from a CIImage using the Vision bounding box.
    ///
    /// The Vision bounding box is normalized (0-1) with origin at bottom-left.
    /// CIImage coordinates have origin at bottom-left, so we can map directly.
    private func cropBarcodeRegion(from image: CIImage, boundingBox: CGRect) -> Data? {
        let imageExtent = image.extent
        let cropRect = CGRect(
            x: boundingBox.origin.x * imageExtent.width,
            y: boundingBox.origin.y * imageExtent.height,
            width: boundingBox.width * imageExtent.width,
            height: boundingBox.height * imageExtent.height
        )

        // Add some padding around the barcode (10%)
        let paddingX = cropRect.width * 0.1
        let paddingY = cropRect.height * 0.1
        let paddedRect = cropRect.insetBy(dx: -paddingX, dy: -paddingY)
            .intersection(imageExtent)

        let croppedImage = image.cropped(to: paddedRect)

        guard let cgImage = ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.8)
    }

    /// Maps a Vision `VNBarcodeSymbology` to the app's `BarcodeType`.
    private static func mapSymbology(_ symbology: VNBarcodeSymbology) -> BarcodeType {
        switch symbology {
        case .qr:      return .qr
        case .ean8:    return .ean8
        case .ean13:   return .ean13
        case .upce:    return .upcE
        case .pdf417:  return .pdf417
        case .code128: return .code128
        case .code39:  return .code39
        default:       return .text
        }
    }
}
