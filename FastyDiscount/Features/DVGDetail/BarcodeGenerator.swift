import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - BarcodeGenerator

/// Utility that renders barcode images from string values using Core Image CIFilters.
///
/// Supports QR codes, Code 128 (used as a fallback for UPC/EAN formats that lack
/// dedicated CIFilters on iOS), and PDF417.
///
/// All methods are synchronous and return an optional `UIImage`. They are designed
/// to be called from an async context (e.g. `Task`) to avoid blocking the main thread
/// during initial rendering.
enum BarcodeGenerator {

    // MARK: - CIContext

    /// Shared CIContext for rendering. Creating a context is expensive, so we
    /// reuse a single instance. Software rendering avoids GPU round-trips for
    /// small barcode images.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    // MARK: - Public API

    /// Generates a barcode image for the given value and barcode type.
    ///
    /// - Parameters:
    ///   - value: The string to encode in the barcode.
    ///   - type: The barcode format to use.
    ///   - size: The desired output size in points. The image is scaled to fit
    ///           this size while preserving the barcode's aspect ratio.
    /// - Returns: A `UIImage` of the rendered barcode, or `nil` if generation fails.
    static func generateBarcode(
        from value: String,
        type: BarcodeType,
        size: CGSize = CGSize(width: 300, height: 300)
    ) -> UIImage? {
        guard !value.isEmpty else { return nil }

        let ciImage: CIImage?

        switch type {
        case .qr:
            ciImage = generateQRCode(from: value)
        case .pdf417:
            ciImage = generatePDF417(from: value)
        case .upcA, .upcE, .ean8, .ean13, .code128, .code39:
            // iOS does not provide dedicated CIFilters for UPC/EAN/Code 39 formats.
            // Code 128 is used as a universal 1D barcode fallback.
            ciImage = generateCode128(from: value)
        case .text:
            // Text-only codes have no barcode representation.
            return nil
        }

        guard let image = ciImage else { return nil }
        return renderToUIImage(ciImage: image, targetSize: size)
    }

    // MARK: - QR Code

    private static func generateQRCode(from value: String) -> CIImage? {
        guard let data = value.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        return filter.outputImage
    }

    // MARK: - Code 128

    private static func generateCode128(from value: String) -> CIImage? {
        guard let data = value.data(using: .ascii) else { return nil }

        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = data
        filter.quietSpace = 7

        return filter.outputImage
    }

    // MARK: - PDF417

    private static func generatePDF417(from value: String) -> CIImage? {
        guard let data = value.data(using: .utf8) else { return nil }

        let filter = CIFilter.pdf417BarcodeGenerator()
        filter.message = data
        filter.correctionLevel = 2

        return filter.outputImage
    }

    // MARK: - Rendering

    /// Scales a CIImage to the target size and renders it as a UIImage.
    ///
    /// Barcodes are generated at very small pixel sizes (e.g. 23x23 for QR).
    /// This method scales them up using nearest-neighbour interpolation to
    /// preserve the crisp pixel edges required for scannable barcodes.
    private static func renderToUIImage(ciImage: CIImage, targetSize: CGSize) -> UIImage? {
        let extent = ciImage.extent

        guard extent.width > 0, extent.height > 0 else { return nil }

        let scaleX = targetSize.width / extent.width
        let scaleY = targetSize.height / extent.height
        let scale = min(scaleX, scaleY)

        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
