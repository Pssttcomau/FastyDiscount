import CoreImage
import Foundation
import UIKit
import Vision

// MARK: - BarcodeDetectionError

/// Errors that can occur during barcode detection or text extraction.
enum BarcodeDetectionError: LocalizedError, Sendable {
    case visionRequestFailed(String)
    case noContentDetected
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .visionRequestFailed(let detail):
            return "Vision request failed: \(detail)"
        case .noContentDetected:
            return "No barcodes or text were detected in the provided content."
        case .invalidImage:
            return "The image could not be processed."
        }
    }
}

// MARK: - BarcodeDetectionResult

/// The result of running barcode detection (and optionally OCR) on an image.
struct BarcodeDetectionResult: Sendable {
    /// All barcodes detected in the image.
    let barcodes: [DetectedBarcode]
    /// All text blocks extracted via OCR (fallback when no barcodes found).
    let extractedText: [String]
    /// Whether any content (barcode or text) was found.
    var hasContent: Bool { !barcodes.isEmpty || !extractedText.isEmpty }
}

// MARK: - BarcodeDetectionServiceProtocol

/// Protocol for the barcode detection service, enabling testability.
protocol BarcodeDetectionServiceProtocol: Sendable {
    /// Detect barcodes in a CIImage. Falls back to OCR if no barcodes found.
    func detectContent(in image: CIImage) async throws -> BarcodeDetectionResult
    /// Maps a VNBarcodeSymbology to the app's BarcodeType.
    static func mapSymbology(_ symbology: VNBarcodeSymbology) -> BarcodeType
    /// Crops and compresses the barcode region from a CIImage.
    func cropBarcodeRegion(from image: CIImage, boundingBox: CGRect) -> Data?
    /// Compresses a UIImage to JPEG data under the given maximum byte size.
    func compressImage(_ image: UIImage, maxBytes: Int) -> Data?
}

// MARK: - BarcodeDetectionService

/// Shared service that encapsulates Vision barcode detection and OCR text extraction.
///
/// - All heavy processing happens on a background actor so callers
///   (typically `@MainActor` ViewModels) can `await` safely.
/// - `CIContext` is allocated once and reused for image cropping.
/// - Supports multiple symbologies matching what the camera scanner uses.
actor BarcodeDetectionService: BarcodeDetectionServiceProtocol {

    // MARK: - Shared

    static let shared = BarcodeDetectionService()

    // MARK: - Private Properties

    /// Shared CIContext for image operations (thread-safe within actor isolation).
    private let ciContext = CIContext()

    /// The set of barcode symbologies to detect.
    private let supportedSymbologies: [VNBarcodeSymbology] = [
        .qr, .ean8, .ean13, .upce, .pdf417, .code128, .code39
    ]

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Detect barcodes and/or text in a CIImage.
    ///
    /// 1. Runs `VNDetectBarcodesRequest` on the image.
    /// 2. If no barcodes found, runs `VNRecognizeTextRequest` as OCR fallback.
    /// 3. Returns all findings aggregated in a `BarcodeDetectionResult`.
    func detectContent(in image: CIImage) async throws -> BarcodeDetectionResult {
        let barcodes = try detectBarcodes(in: image)
        let extractedText: [String]

        if barcodes.isEmpty {
            // OCR fallback
            extractedText = (try? recognizeText(in: image)) ?? []
        } else {
            extractedText = []
        }

        return BarcodeDetectionResult(barcodes: barcodes, extractedText: extractedText)
    }

    // MARK: - Barcode Detection

    private func detectBarcodes(in image: CIImage) throws -> [DetectedBarcode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = supportedSymbologies

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw BarcodeDetectionError.visionRequestFailed(error.localizedDescription)
        }

        guard let results = request.results else { return [] }

        return results.compactMap { observation in
            extractDetectedBarcode(from: observation, ciImage: image)
        }
    }

    // MARK: - OCR Text Recognition

    private func recognizeText(in image: CIImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw BarcodeDetectionError.visionRequestFailed(error.localizedDescription)
        }

        guard let results = request.results else { return [] }

        return results.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Data Extraction

    /// Extracts all needed data from a `VNBarcodeObservation` into a `DetectedBarcode`.
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

    // MARK: - Image Utilities

    /// Crops the barcode region from a CIImage using the Vision bounding box.
    ///
    /// The Vision bounding box is normalized (0–1) with origin at bottom-left,
    /// matching CIImage coordinate space, so we can map directly.
    nonisolated func cropBarcodeRegion(from image: CIImage, boundingBox: CGRect) -> Data? {
        let context = CIContext()
        let imageExtent = image.extent

        let cropRect = CGRect(
            x: boundingBox.origin.x * imageExtent.width,
            y: boundingBox.origin.y * imageExtent.height,
            width: boundingBox.width * imageExtent.width,
            height: boundingBox.height * imageExtent.height
        )

        // Add 10% padding around the barcode
        let paddingX = cropRect.width * 0.1
        let paddingY = cropRect.height * 0.1
        let paddedRect = cropRect.insetBy(dx: -paddingX, dy: -paddingY)
            .intersection(imageExtent)

        let croppedImage = image.cropped(to: paddedRect)

        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.8)
    }

    /// Compresses a `UIImage` to JPEG data, reducing quality until under `maxBytes`.
    nonisolated func compressImage(_ image: UIImage, maxBytes: Int = 1_048_576) -> Data? {
        var quality: CGFloat = 0.9
        var data = image.jpegData(compressionQuality: quality)

        while let d = data, d.count > maxBytes, quality > 0.1 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }

        return data
    }

    // MARK: - Symbology Mapping

    /// Maps a Vision `VNBarcodeSymbology` to the app's `BarcodeType`.
    nonisolated static func mapSymbology(_ symbology: VNBarcodeSymbology) -> BarcodeType {
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
