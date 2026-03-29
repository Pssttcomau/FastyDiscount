import CoreImage
import Foundation
import PDFKit
import PhotosUI
import SwiftUI
import Vision

// MARK: - ImportState

/// Represents the overall state of the photo/PDF import flow.
enum ImportState: Equatable, Sendable {
    /// No import in progress; waiting for user action.
    case idle
    /// Processing the selected image or PDF.
    case processing(progress: Double)
    /// Processing complete; results are available.
    case results
    /// An error occurred during processing.
    case error(String)
}

// MARK: - ImportSource

/// The source type the user is importing from.
enum ImportSource: Sendable {
    case photo
    case pdf
}

// MARK: - ImportError

/// Errors specific to the photo/PDF import flow.
enum ImportError: LocalizedError, Sendable {
    case unsupportedFileFormat
    case corruptedPDF
    case noContentDetected
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileFormat:
            return "The selected file format is not supported. Please choose a JPEG, PNG, or PDF file."
        case .corruptedPDF:
            return "The PDF file appears to be corrupted or unreadable."
        case .noContentDetected:
            return "No barcodes or readable text were found in the selected content."
        case .processingFailed(let detail):
            return "Processing failed: \(detail)"
        }
    }
}

// MARK: - ImportViewModel

/// ViewModel managing the photo library and PDF document import flow.
///
/// Responsibilities:
/// - Accepts a selected `PhotosPickerItem` or PDF file URL.
/// - Processes images via `BarcodeDetectionService` on a background actor.
/// - Renders PDF pages as `CIImage`s using `PDFKit` and processes each page.
/// - Tracks progress for multi-page PDFs.
/// - Exposes detected barcodes, extracted text, and a thumbnail image for display.
/// - Provides a `DVGSource` payload to hand off to the DVG creation form.
@Observable
@MainActor
final class ImportViewModel {

    // MARK: - Public State

    /// Current state of the import flow.
    var importState: ImportState = .idle

    /// The most prominent detected barcodes (primary result).
    var detectedBarcodes: [DetectedBarcode] = []

    /// Extracted OCR text blocks (supplementary / fallback result).
    var extractedTextBlocks: [String] = []

    /// Thumbnail of the imported image or first PDF page.
    var thumbnailImage: UIImage?

    /// Compressed JPEG data of the original image for storage.
    var barcodeImageData: Data?

    /// Whether an import result is ready to present.
    var hasResults: Bool {
        if case .results = importState { return true }
        return false
    }

    /// Whether there is any detected content (barcodes or text).
    var hasContent: Bool {
        !detectedBarcodes.isEmpty || !extractedTextBlocks.isEmpty
    }

    /// The primary barcode value (highest confidence), if any.
    var primaryBarcodeValue: String? {
        detectedBarcodes.first?.value
    }

    /// The primary barcode type, defaulting to `.text` if none detected.
    var primaryBarcodeType: BarcodeType {
        detectedBarcodes.first?.barcodeType ?? .text
    }

    /// Combined text from all extracted text blocks, joined by newlines.
    var extractedTextCombined: String {
        extractedTextBlocks.joined(separator: "\n")
    }

    /// AI extraction result from `VisionParsingService`, populated after processing.
    var aiExtractionResult: DVGExtractionResult?

    // MARK: - Private Properties

    private let detectionService: BarcodeDetectionService
    private let visionParsingService: any VisionParsingService

    // MARK: - Init

    init(
        detectionService: BarcodeDetectionService = .shared,
        visionParsingService: any VisionParsingService = CloudAIVisionParsingService(aiClient: AnthropicClient())
    ) {
        self.detectionService = detectionService
        self.visionParsingService = visionParsingService
    }

    // MARK: - Photo Import

    /// Processes a photo selected via `PhotosPicker`.
    ///
    /// - Parameter item: The `PhotosPickerItem` selected by the user.
    func processPhoto(_ item: PhotosPickerItem) async {
        importState = .processing(progress: 0.0)
        resetResults()

        do {
            // Load image data from the picker item
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importState = .error(ImportError.processingFailed("Could not load image data.").localizedDescription)
                return
            }

            guard let uiImage = UIImage(data: data) else {
                importState = .error(ImportError.processingFailed("Could not decode image.").localizedDescription)
                return
            }

            importState = .processing(progress: 0.3)

            // Set thumbnail
            thumbnailImage = uiImage

            // Compress for storage (max 1MB)
            barcodeImageData = compressImageSync(uiImage)

            importState = .processing(progress: 0.5)

            // Convert to CIImage and run detection
            guard let ciImage = CIImage(image: uiImage) else {
                importState = .error(ImportError.invalidImage.localizedDescription)
                return
            }

            let result = try await detectionService.detectContent(in: ciImage)

            importState = .processing(progress: 0.8)

            // Run AI parsing on the compressed image data
            if let imageData = barcodeImageData {
                let ocrText = result.extractedText.isEmpty ? nil : result.extractedText.joined(separator: "\n")
                importState = .processing(progress: 0.9)
                aiExtractionResult = try? await visionParsingService.parseImage(
                    imageData: imageData,
                    ocrText: ocrText
                )
            }

            importState = .processing(progress: 1.0)

            applyResult(result)

        } catch let importErr as ImportError {
            importState = .error(importErr.localizedDescription)
        } catch {
            importState = .error(ImportError.processingFailed(error.localizedDescription).localizedDescription)
        }
    }

    // MARK: - PDF Import

    /// Processes a PDF file imported via `UIDocumentPickerViewController`.
    ///
    /// Renders each page as a `CIImage` at a resolution suitable for OCR,
    /// then runs barcode detection on each page. Collects all findings.
    ///
    /// - Parameter url: The URL of the PDF file (must be accessible, security-scoped).
    func processPDF(at url: URL) async {
        importState = .processing(progress: 0.0)
        resetResults()

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            guard let pdfDocument = PDFDocument(url: url) else {
                throw ImportError.corruptedPDF
            }

            let pageCount = pdfDocument.pageCount
            guard pageCount > 0 else {
                throw ImportError.corruptedPDF
            }

            var allBarcodes: [DetectedBarcode] = []
            var allTextBlocks: [String] = []
            var firstPageImage: UIImage?

            // Render size: ~300 DPI equivalent for A4 (roughly 2480 x 3508 points at 300 dpi)
            // We use a width target of 1200px which gives good OCR quality without being too large.
            let renderWidth: CGFloat = 1200

            for pageIndex in 0..<pageCount {
                let progress = Double(pageIndex) / Double(pageCount)
                importState = .processing(progress: progress)

                guard let page = pdfDocument.page(at: pageIndex) else { continue }

                let pageBounds = page.bounds(for: .mediaBox)
                let scale = renderWidth / pageBounds.width
                let renderSize = CGSize(
                    width: pageBounds.width * scale,
                    height: pageBounds.height * scale
                )

                guard let pageImage = renderPDFPage(page, size: renderSize) else { continue }

                // Store the first page as thumbnail
                if pageIndex == 0 {
                    firstPageImage = pageImage
                }

                guard let ciImage = CIImage(image: pageImage) else { continue }

                do {
                    let result = try await detectionService.detectContent(in: ciImage)
                    allBarcodes.append(contentsOf: result.barcodes)
                    allTextBlocks.append(contentsOf: result.extractedText)
                } catch {
                    // Continue processing remaining pages even if one fails
                    continue
                }
            }

            importState = .processing(progress: 1.0)

            // Set thumbnail from first page
            if let firstPage = firstPageImage {
                thumbnailImage = firstPage
                barcodeImageData = compressImageSync(firstPage)
            }

            // De-duplicate barcodes by value
            let uniqueBarcodes = deduplicateBarcodes(allBarcodes)
            let uniqueText = deduplicateText(allTextBlocks)

            if uniqueBarcodes.isEmpty && uniqueText.isEmpty {
                importState = .error(ImportError.noContentDetected.localizedDescription)
                return
            }

            detectedBarcodes = uniqueBarcodes
            extractedTextBlocks = uniqueText

            // Run AI parsing on the first-page image data
            if let imageData = barcodeImageData {
                let ocrText = uniqueText.isEmpty ? nil : uniqueText.joined(separator: "\n")
                importState = .processing(progress: 0.9)
                aiExtractionResult = try? await visionParsingService.parseImage(
                    imageData: imageData,
                    ocrText: ocrText
                )
            }

            importState = .results

        } catch let importErr as ImportError {
            importState = .error(importErr.localizedDescription)
        } catch {
            importState = .error(ImportError.processingFailed(error.localizedDescription).localizedDescription)
        }
    }

    // MARK: - Image URL Import (Mac Catalyst drag-and-drop)

    /// Processes an image file at the given URL.
    ///
    /// Used on Mac Catalyst when the user drops an image file onto the window.
    ///
    /// - Parameter url: A file URL pointing to an image (JPEG, PNG, HEIC, etc.).
    func processImageFromURL(_ url: URL) async {
        importState = .processing(progress: 0.0)
        resetResults()

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)

            guard let uiImage = UIImage(data: data) else {
                importState = .error(ImportError.processingFailed("Could not decode image.").localizedDescription)
                return
            }

            importState = .processing(progress: 0.3)

            thumbnailImage = uiImage
            barcodeImageData = compressImageSync(uiImage)

            importState = .processing(progress: 0.5)

            guard let ciImage = CIImage(image: uiImage) else {
                importState = .error(ImportError.invalidImage.localizedDescription)
                return
            }

            let result = try await detectionService.detectContent(in: ciImage)

            importState = .processing(progress: 0.8)

            // Run AI parsing on the compressed image data
            if let imageData = barcodeImageData {
                let ocrText = result.extractedText.isEmpty ? nil : result.extractedText.joined(separator: "\n")
                importState = .processing(progress: 0.9)
                aiExtractionResult = try? await visionParsingService.parseImage(
                    imageData: imageData,
                    ocrText: ocrText
                )
            }

            importState = .processing(progress: 1.0)
            applyResult(result)

        } catch let importErr as ImportError {
            importState = .error(importErr.localizedDescription)
        } catch {
            importState = .error(ImportError.processingFailed(error.localizedDescription).localizedDescription)
        }
    }

    // MARK: - Reset

    /// Resets all results and returns to idle state.
    func reset() {
        resetResults()
        importState = .idle
    }

    // MARK: - DVG Source Payload

    /// Returns the `DVGSource` to use when creating a DVG from import results.
    var dvgSource: DVGSource { .scan }

    // MARK: - Private Helpers

    private func resetResults() {
        detectedBarcodes = []
        extractedTextBlocks = []
        thumbnailImage = nil
        barcodeImageData = nil
        aiExtractionResult = nil
    }

    private func applyResult(_ result: BarcodeDetectionResult) {
        if result.barcodes.isEmpty && result.extractedText.isEmpty {
            importState = .error(ImportError.noContentDetected.localizedDescription)
            return
        }

        // Sort barcodes: highest confidence first
        detectedBarcodes = result.barcodes.sorted { $0.confidence > $1.confidence }
        extractedTextBlocks = result.extractedText
        importState = .results
    }

    /// Renders a single PDF page to a UIImage at the given size.
    ///
    /// `PDFPage.thumbnail(of:for:)` is called synchronously here on the
    /// `@MainActor` since `PDFPage` is not `Sendable` and cannot be
    /// passed across actor boundaries. The call is fast for typical pages.
    private func renderPDFPage(_ page: PDFPage, size: CGSize) -> UIImage? {
        // PDFPage.thumbnail(of:for:) is the recommended API for rendering PDF pages
        page.thumbnail(of: size, for: .mediaBox)
    }

    /// Compresses a UIImage synchronously.
    ///
    /// `UIImage` is not `Sendable` across actor boundaries so we call this
    /// directly on `@MainActor` rather than spinning up a detached task.
    private func compressImageSync(_ image: UIImage) -> Data? {
        BarcodeDetectionService.shared.compressImage(image, maxBytes: 1_048_576)
    }

    /// Removes duplicate barcodes (same value), keeping the highest-confidence one.
    private func deduplicateBarcodes(_ barcodes: [DetectedBarcode]) -> [DetectedBarcode] {
        var seen: [String: DetectedBarcode] = [:]
        for barcode in barcodes {
            if let existing = seen[barcode.value] {
                if barcode.confidence > existing.confidence {
                    seen[barcode.value] = barcode
                }
            } else {
                seen[barcode.value] = barcode
            }
        }
        return seen.values.sorted { $0.confidence > $1.confidence }
    }

    /// Removes duplicate text blocks (exact duplicates only), preserving order.
    private func deduplicateText(_ blocks: [String]) -> [String] {
        var seen = Set<String>()
        return blocks.filter { block in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return seen.insert(trimmed).inserted
        }
    }
}

// MARK: - ImportError extension

extension ImportError {
    static var invalidImage: ImportError { .processingFailed("The image could not be converted for processing.") }
}
