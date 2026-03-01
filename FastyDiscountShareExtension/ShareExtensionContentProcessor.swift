import CoreImage
import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

// MARK: - ShareContentType

/// The type of content received from the share sheet.
enum ShareContentType: Sendable {
    case text
    case url
    case image
    case pdf
}

// MARK: - ShareExtractionResult

/// Aggregated extraction results from processing shared content.
///
/// This is a lightweight, `Sendable` value type that captures all fields
/// extracted from the shared input. The share extension UI pre-populates
/// the DVG creation form from these values.
struct ShareExtractionResult: Sendable {
    var suggestedTitle: String = ""
    var extractedCode: String = ""
    var suggestedStoreName: String = ""
    var suggestedDVGType: DVGType = .discountCode
    var suggestedBarcodeType: BarcodeType = .text
    var barcodeImageData: Data?
    var notes: String = ""
    var contentType: ShareContentType = .text
    var rawText: String = ""
    var discountDescription: String = ""
}

// MARK: - ShareExtensionContentProcessor

/// Processes shared content from the iOS Share Sheet into structured DVG field data.
///
/// Runs entirely on-device within the ~120MB share extension memory budget.
/// Uses Vision framework for barcode detection and OCR with `.fast` recognition
/// level to minimize processing time and memory consumption.
///
/// This actor isolates all heavy processing (Vision requests, PDF rendering)
/// to avoid data races under Swift 6 strict concurrency.
actor ShareExtensionContentProcessor {

    // MARK: - Private Properties

    private let ciContext = CIContext()

    /// Barcode symbologies to detect (matches main app).
    private let supportedSymbologies: [VNBarcodeSymbology] = [
        .qr, .ean8, .ean13, .upce, .pdf417, .code128, .code39
    ]

    // MARK: - Public API

    /// Processes a text string shared from another app.
    ///
    /// Runs regex extraction for common discount code patterns:
    /// alphanumeric codes, percentages, and dollar amounts.
    func processText(_ text: String) -> ShareExtractionResult {
        var result = ShareExtractionResult()
        result.contentType = .text
        result.rawText = text

        // Extract discount code patterns
        let codePatterns = extractCodePatterns(from: text)

        if let bestCode = codePatterns.first {
            result.extractedCode = bestCode
        }

        // Extract percentage values (e.g., "20%", "50% off")
        if let percentage = extractPercentage(from: text) {
            result.discountDescription = "\(percentage)% off"
            result.suggestedDVGType = .discountCode
            result.suggestedTitle = "\(percentage)% off"
        }

        // Extract dollar amounts (e.g., "$50", "$25.00")
        if let amount = extractDollarAmount(from: text) {
            if result.suggestedTitle.isEmpty {
                result.suggestedTitle = "$\(amount) value"
            }
            // Dollar amounts often indicate gift cards or vouchers
            if result.suggestedDVGType == .discountCode && !text.lowercased().contains("off") {
                result.suggestedDVGType = .giftCard
            }
        }

        // Use the text itself as a fallback title
        if result.suggestedTitle.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
            result.suggestedTitle = String(firstLine.prefix(80))
        }

        result.notes = "Imported via Share Sheet"

        return result
    }

    /// Processes a URL shared from another app.
    ///
    /// Extracts the domain as a potential store name and stores the full URL
    /// in the notes field.
    func processURL(_ url: URL) -> ShareExtractionResult {
        var result = ShareExtractionResult()
        result.contentType = .url
        result.rawText = url.absoluteString

        // Extract domain as potential store name
        if let host = url.host() {
            let domain = host
                .replacingOccurrences(of: "www.", with: "")
                .replacingOccurrences(of: ".com", with: "")
                .replacingOccurrences(of: ".co.uk", with: "")
                .replacingOccurrences(of: ".com.au", with: "")
                .replacingOccurrences(of: ".net", with: "")
                .replacingOccurrences(of: ".org", with: "")

            result.suggestedStoreName = domain.capitalized
        }

        // Check URL path for coupon/discount indicators
        let path = url.path().lowercased()
        if path.contains("coupon") || path.contains("promo") || path.contains("discount") {
            result.suggestedTitle = "Discount from \(result.suggestedStoreName)"
            result.suggestedDVGType = .discountCode
        } else if path.contains("gift") || path.contains("card") {
            result.suggestedTitle = "Gift Card from \(result.suggestedStoreName)"
            result.suggestedDVGType = .giftCard
        } else if path.contains("voucher") {
            result.suggestedTitle = "Voucher from \(result.suggestedStoreName)"
            result.suggestedDVGType = .voucher
        } else {
            result.suggestedTitle = "Deal from \(result.suggestedStoreName)"
        }

        // Extract code from URL query parameters
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let codeParams = ["code", "promo", "coupon", "voucher", "ref"]
        if let codeItem = queryItems?.first(where: { codeParams.contains($0.name.lowercased()) }),
           let value = codeItem.value, !value.isEmpty {
            result.extractedCode = value
        }

        result.notes = "URL: \(url.absoluteString)\nImported via Share Sheet"

        return result
    }

    /// Processes an image shared from another app.
    ///
    /// Runs `VNDetectBarcodesRequest` for barcode detection. If no barcodes
    /// are found, falls back to `VNRecognizeTextRequest` (OCR) with `.fast`
    /// recognition level.
    func processImage(_ image: UIImage) async -> ShareExtractionResult {
        var result = ShareExtractionResult()
        result.contentType = .image

        guard let ciImage = CIImage(image: image) else {
            result.suggestedTitle = "Imported Image"
            result.notes = "Imported via Share Sheet (could not process image)"
            return result
        }

        // Try barcode detection first
        let barcodeResult = detectBarcodes(in: ciImage)

        if let barcode = barcodeResult.first {
            result.extractedCode = barcode.value
            result.suggestedBarcodeType = barcode.barcodeType
            result.barcodeImageData = barcode.imageData
            result.suggestedTitle = "Scanned \(barcode.barcodeType.displayName)"
            result.suggestedDVGType = .barcodeCoupon

            // Try to extract text from the rest of the image for context
            let ocrTexts = recognizeText(in: ciImage)
            if !ocrTexts.isEmpty {
                result.rawText = ocrTexts.joined(separator: "\n")
                // Look for store name or additional context
                enrichFromOCRText(&result, texts: ocrTexts)
            }
        } else {
            // Fallback to OCR
            let ocrTexts = recognizeText(in: ciImage)
            result.rawText = ocrTexts.joined(separator: "\n")

            if !ocrTexts.isEmpty {
                enrichFromOCRText(&result, texts: ocrTexts)

                // Extract codes from OCR text
                let combinedText = ocrTexts.joined(separator: " ")
                let codes = extractCodePatterns(from: combinedText)
                if let bestCode = codes.first {
                    result.extractedCode = bestCode
                }
            }

            if result.suggestedTitle.isEmpty {
                result.suggestedTitle = "Imported Image"
            }
        }

        result.notes = "Imported via Share Sheet"

        return result
    }

    /// Processes a PDF shared from another app.
    ///
    /// Renders the first page as an image and processes it through the
    /// barcode detection and OCR pipeline.
    func processPDF(at fileURL: URL) async -> ShareExtractionResult {
        var result = ShareExtractionResult()
        result.contentType = .pdf

        guard let pdfDocument = PDFDocument(url: fileURL),
              let firstPage = pdfDocument.page(at: 0) else {
            result.suggestedTitle = "Imported PDF"
            result.notes = "Imported via Share Sheet (could not process PDF)"
            return result
        }

        // Render the first page to a UIImage
        let pageRect = firstPage.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let pageImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(pageRect)

            ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)

            firstPage.draw(with: .mediaBox, to: ctx.cgContext)
        }

        // Process rendered page image through the same pipeline
        result = await processImage(pageImage)
        result.contentType = .pdf

        // Override notes to indicate PDF source
        let existingNotes = result.notes.replacingOccurrences(of: "Imported via Share Sheet", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if existingNotes.isEmpty {
            result.notes = "Imported via Share Sheet (from PDF)"
        } else {
            result.notes = "\(existingNotes)\nImported via Share Sheet (from PDF)"
        }

        return result
    }

    // MARK: - Vision Processing

    /// Detects barcodes in a CIImage using the Vision framework.
    private func detectBarcodes(in image: CIImage) -> [BarcodeResult] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = supportedSymbologies

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let results = request.results else { return [] }

        return results.compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else {
                return nil
            }

            let barcodeType = Self.mapSymbology(observation.symbology)
            let imageData = cropBarcodeRegion(
                from: image,
                boundingBox: observation.boundingBox
            )

            return BarcodeResult(
                value: payload,
                barcodeType: barcodeType,
                imageData: imageData
            )
        }
    }

    /// Runs OCR text recognition on a CIImage with `.fast` recognition level.
    private func recognizeText(in image: CIImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let results = request.results else { return [] }

        return results.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Image Utilities

    /// Maps a Vision `VNBarcodeSymbology` to the app's `BarcodeType`.
    ///
    /// Mirrors the canonical mapping in `BarcodeDetectionService` (which is not
    /// compiled in the share extension target to avoid pulling in extra dependencies).
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

    /// Crops the barcode region from a CIImage using the Vision bounding box.
    ///
    /// The Vision bounding box is normalized (0-1) with origin at bottom-left,
    /// matching CIImage coordinate space. Adds 10% padding around the barcode.
    private func cropBarcodeRegion(from image: CIImage, boundingBox: CGRect) -> Data? {
        let imageExtent = image.extent

        let cropRect = CGRect(
            x: boundingBox.origin.x * imageExtent.width,
            y: boundingBox.origin.y * imageExtent.height,
            width: boundingBox.width * imageExtent.width,
            height: boundingBox.height * imageExtent.height
        )

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

    // MARK: - Text Extraction Patterns

    /// Extracts alphanumeric discount code patterns from text.
    ///
    /// Matches patterns like:
    /// - Uppercase codes: "SAVE20", "WELCOME50"
    /// - Mixed case codes: "Gift2024"
    /// - Codes after keywords: "code: SAVE20", "promo WELCOME"
    private func extractCodePatterns(from text: String) -> [String] {
        var codes: [String] = []

        // Pattern 1: Code after keyword (e.g., "code: SAVE20", "promo: WELCOME50")
        let keywordPattern = #"(?:code|promo|coupon|voucher|discount)\s*[:=\s]\s*([A-Z0-9][A-Z0-9\-_]{2,20})"#
        if let regex = try? NSRegularExpression(pattern: keywordPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: text) {
                    codes.append(String(text[codeRange]))
                }
            }
        }

        // Pattern 2: Standalone uppercase alphanumeric codes (4-20 chars, must contain both letters and digits)
        let standalonePattern = #"\b([A-Z][A-Z0-9\-]{3,19})\b"#
        if let regex = try? NSRegularExpression(pattern: standalonePattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: text) {
                    let candidate = String(text[codeRange])
                    // Must contain at least one digit to distinguish from regular words
                    if candidate.rangeOfCharacter(from: .decimalDigits) != nil {
                        codes.append(candidate)
                    }
                }
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    /// Extracts a percentage value from text (e.g., "20%", "50% off").
    private func extractPercentage(from text: String) -> Int? {
        let pattern = #"(\d{1,3})\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Int(text[range]),
              value > 0, value <= 100 else {
            return nil
        }
        return value
    }

    /// Extracts a dollar amount from text (e.g., "$50", "$25.00").
    private func extractDollarAmount(from text: String) -> String? {
        let pattern = #"\$(\d+(?:\.\d{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    // MARK: - OCR Enrichment

    /// Enriches extraction results with data parsed from OCR text blocks.
    private func enrichFromOCRText(_ result: inout ShareExtractionResult, texts: [String]) {
        let combined = texts.joined(separator: " ").lowercased()

        // Detect DVG type from text content
        if combined.contains("gift card") || combined.contains("giftcard") {
            result.suggestedDVGType = .giftCard
        } else if combined.contains("voucher") {
            result.suggestedDVGType = .voucher
        } else if combined.contains("loyalty") || combined.contains("points") || combined.contains("rewards") {
            result.suggestedDVGType = .loyaltyPoints
        } else if combined.contains("coupon") || combined.contains("barcode") {
            result.suggestedDVGType = .barcodeCoupon
        }

        // Extract percentage
        if let pct = extractPercentage(from: combined) {
            result.discountDescription = "\(pct)% off"
            if result.suggestedTitle.isEmpty || result.suggestedTitle == "Imported Image" {
                result.suggestedTitle = "\(pct)% off"
            }
        }

        // Extract dollar amount
        if let amount = extractDollarAmount(from: combined) {
            if result.suggestedTitle.isEmpty || result.suggestedTitle == "Imported Image" {
                result.suggestedTitle = "$\(amount) value"
            }
        }

        // Look for store names in the first few lines (often headers)
        if result.suggestedStoreName.isEmpty, let firstText = texts.first {
            let trimmed = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
            // If the first line is short and doesn't look like a sentence, use it as store name
            if trimmed.count <= 30 && !trimmed.contains(" ") || trimmed.allSatisfy({ $0.isUppercase || $0.isWhitespace }) {
                result.suggestedStoreName = trimmed
            }
        }
    }
}

// MARK: - BarcodeResult

/// Lightweight barcode detection result for share extension processing.
private struct BarcodeResult: Sendable {
    let value: String
    let barcodeType: BarcodeType
    let imageData: Data?
}
