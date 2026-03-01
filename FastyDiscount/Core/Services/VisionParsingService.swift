import Foundation
import os
import UIKit

// MARK: - VisionParsingError

/// Typed errors thrown during vision-based image parsing operations.
///
/// Conforms to `Sendable` for Swift 6 strict concurrency and to
/// `LocalizedError` so user-facing messages are available via `localizedDescription`.
enum VisionParsingError: LocalizedError, Sendable {

    /// The image could not be resized or re-encoded as JPEG.
    case imagePreprocessingFailed

    /// The AI service returned a response that could not be decoded as JSON.
    case invalidAIResponse(detail: String)

    /// The AI service call failed (network, auth, etc.).
    case aiServiceFailed(underlying: String)

    /// Network is unavailable; only raw OCR text is available.
    case networkUnavailable(ocrText: String?)

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .imagePreprocessingFailed:
            return "Failed to resize or compress the image before sending to the AI service."
        case .invalidAIResponse(let detail):
            return "Invalid AI response during vision parsing: \(detail)"
        case .aiServiceFailed(let underlying):
            return "AI vision extraction failed: \(underlying)"
        case .networkUnavailable:
            return "No network connection. Raw OCR text returned for manual entry."
        }
    }
}

// MARK: - VisionParsingService Protocol

/// Abstraction for the image-to-DVG visual extraction pipeline.
///
/// Conforming types accept raw image data (and optional pre-extracted OCR text),
/// send the image to a cloud AI service with a vision-optimised prompt, and return
/// a structured `DVGExtractionResult`.
///
/// Declared `Sendable` so that implementations can be safely passed across Swift 6
/// actor boundaries (e.g. from a `@MainActor` ViewModel into a background Task).
protocol VisionParsingService: Sendable {

    /// Parses an image for discount/voucher/gift-card information using cloud AI vision.
    ///
    /// The image is resized to a maximum of 1024 px on the longest edge and
    /// compressed to JPEG before transmission. If the AI service is unreachable,
    /// a fallback result is returned that signals the UI to offer manual entry
    /// with the raw OCR text pre-filled.
    ///
    /// - Parameters:
    ///   - imageData: Raw image bytes (JPEG or PNG) captured from a camera scan or
    ///     photo library. Should represent a coupon, flyer, receipt, or loyalty card.
    ///   - ocrText: Optional pre-extracted OCR text from on-device Vision framework.
    ///     When supplied, it is included in the prompt to assist the model, but the
    ///     image itself is always the primary signal.
    /// - Returns: A `DVGExtractionResult` populated from the AI response, or a
    ///   low-confidence fallback result when the network is unavailable.
    /// - Throws: `VisionParsingError` when image pre-processing fails or the AI
    ///   returns an undecodable response (network failures are handled as fallback,
    ///   not thrown).
    func parseImage(imageData: Data, ocrText: String?) async throws -> DVGExtractionResult
}

// MARK: - VisionParsingPrompts

/// System prompt templates for the AI vision extraction pipeline.
///
/// Centralised here so they can be tested and maintained independently
/// of the parsing logic.
enum VisionParsingPrompts {

    /// System prompt instructing the AI to extract DVG fields from a coupon/flyer image.
    ///
    /// Deliberately distinct from `EmailParsingPrompts.extractionSystemPrompt`:
    /// this prompt emphasises **visual layout interpretation** — the model must
    /// read graphical elements, branded colour blocks, styled typography, and
    /// visual hierarchies, not just plain text.
    static let extractionSystemPrompt = """
    You are a visual coupon and promotional-material analysis assistant. Your task \
    is to examine the visual layout of the provided image — including text, branding, \
    logos, colour blocks, styled typography, barcodes, and design hierarchy — and \
    extract structured discount/voucher/gift-card information.

    You are looking at physical or digital coupons, promotional flyers, screenshots \
    of offers, receipts with discounts, or loyalty cards. Use every visual cue \
    available: the prominence of numbers (likely values or percentages), the style \
    and placement of alphanumeric codes (often in a distinct box or large font), \
    expiry dates (frequently small print at the bottom), and store branding (logos, \
    brand colours, domain names, or taglines).

    Analyze the image and extract the following fields. Return ONLY a valid JSON \
    object with no additional text, markdown, or explanation.

    Required JSON schema:
    {
      "title": "string or null — A concise title for the deal (e.g. '20% off your next order')",
      "code": "string or null — The promotional/discount code (e.g. 'SAVE20'); look for codes in highlighted boxes, underlined text, or large bold font",
      "dvgType": "string or null — One of: 'discountCode', 'voucher', 'giftCard', 'loyaltyPoints', 'barcodeCoupon'",
      "storeName": "string or null — The store or brand name; check logos, headers, and footers",
      "originalValue": "number or null — The face/monetary value or percentage discount (e.g. 20.0 for '20% off' or 50.0 for a '$50 gift card')",
      "discountDescription": "string or null — Full description of the discount or offer visible in the image",
      "expirationDate": "string or null — Expiration date in ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ). If only a date is shown, use midnight UTC. Look for fine print, 'valid until', 'expires', or 'use by'.",
      "termsAndConditions": "string or null — Any terms, conditions, or restrictions visible in the image",
      "confidenceScore": "number — Overall confidence that this image contains a valid promotion, 0.0 to 1.0",
      "fieldConfidences": {
        "title": "number 0.0-1.0",
        "code": "number 0.0-1.0",
        "dvgType": "number 0.0-1.0",
        "storeName": "number 0.0-1.0",
        "originalValue": "number 0.0-1.0",
        "discountDescription": "number 0.0-1.0",
        "expirationDate": "number 0.0-1.0",
        "termsAndConditions": "number 0.0-1.0"
      }
    }

    Guidelines:
    - Prioritise visually prominent elements (large text, highlighted boxes, bold \
    typography) as they likely contain the most important offer details.
    - If a barcode or QR code is visible but no human-readable code is present, \
    set dvgType to 'barcodeCoupon' and leave 'code' null.
    - If a field cannot be determined from the image, set it to null and give that \
    field a confidence of 0.0.
    - The confidenceScore should reflect how certain you are that this image \
    contains a valid promotion. Set it below 0.5 if the image does not appear to \
    contain promotional material.
    - For expirationDate, always return ISO 8601 format (e.g. "2025-12-31T00:00:00Z").
    - Do not invent codes or values not visible in the image.
    - Return ONLY the JSON object. No markdown fences, no explanation.
    """

    /// Builds the user-facing prompt for vision parsing.
    ///
    /// - Parameter ocrText: Optional pre-extracted OCR text from on-device Vision
    ///   framework. When provided, it is included as supplementary context to help
    ///   the model resolve low-resolution or partially obscured text.
    /// - Returns: A formatted prompt string ready for use with `completeWithVision()`.
    static func buildUserPrompt(ocrText: String?) -> String {
        if let ocrText, !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Truncate very long OCR text to avoid inflating token usage.
            // 4000 characters is approximately 1000 tokens.
            let truncated: String
            if ocrText.count > 4000 {
                truncated = String(ocrText.prefix(4000)) + "\n[... truncated ...]"
            } else {
                truncated = ocrText
            }

            return """
            Analyze this coupon/flyer/promotional image and extract all discount, \
            voucher, or gift card information.

            The following OCR text was pre-extracted from the image by on-device \
            software (may contain errors or formatting noise — use it as a hint, \
            but trust the visual image as the authoritative source):

            --- OCR TEXT ---
            \(truncated)
            --- END OCR TEXT ---

            Return the JSON extraction result as specified.
            """
        } else {
            return """
            Analyze this coupon/flyer/promotional image and extract all discount, \
            voucher, or gift card information. Return the JSON extraction result \
            as specified.
            """
        }
    }
}

// MARK: - CloudAIVisionParsingService

/// Concrete implementation of `VisionParsingService` backed by `CloudAIClient`.
///
/// ### Image Pre-Processing
/// Before sending to the API, the image is resized so that its longest edge is
/// at most 1024 px (using `UIGraphicsImageRenderer`) and re-encoded as JPEG at
/// quality 0.7. This controls API cost and latency while preserving enough detail
/// for text and barcode recognition.
///
/// ### Network Fallback
/// If the AI client throws any network-related error (`.networkError`, `.rateLimited`,
/// `.serverError`), the service does **not** propagate the error. Instead it returns
/// a low-confidence fallback `DVGExtractionResult` containing the raw OCR text in
/// `discountDescription`. The UI layer (TASK-020) should detect this via
/// `confidenceScore == 0.0` and offer manual-entry pre-filled with the OCR text.
///
/// ### Token Cost Logging
/// `CloudAIClient.completeWithVision()` returns a plain `String` (no token-usage
/// metadata). As a cost-tracking aid, this service logs the approximate input size
/// (image bytes + prompt characters) and response length to `os.Logger`. A future
/// enhancement could extend `CloudAIClient` to return usage metadata.
///
/// ### Swift 6 Concurrency
/// Implemented as a `struct` — all stored properties are `Sendable` (protocol
/// existential `any CloudAIClient` is `Sendable` by constraint). The struct itself
/// is automatically `Sendable`.
struct CloudAIVisionParsingService: VisionParsingService {

    // MARK: - Constants

    private enum ImageConfig {
        /// Maximum dimension (width or height) in points before downscaling.
        static let maxLongestEdge: CGFloat = 1024
        /// JPEG compression quality used when re-encoding for API transmission.
        static let jpegQuality: CGFloat = 0.7
    }

    private enum TokenEstimation {
        /// Rough character-to-token ratio for English/mixed content.
        static let charsPerToken: Double = 4.0
        /// Conservative estimate: each image byte costs ~1.5 tokens after base64 overhead.
        static let imageBytesPerToken: Double = 0.5
    }

    // MARK: - Logger

    /// Subsystem-scoped logger for cost-tracking and diagnostics.
    ///
    /// Uses `nonisolated(unsafe)` because `Logger` (backed by `OSLog`) does not
    /// conform to `Sendable`. Access is effectively read-only after initialisation.
    nonisolated(unsafe) private static let logger = Logger(
        subsystem: "com.fastydiscount.app",
        category: "VisionParsing"
    )

    // MARK: - ISO 8601 Formatters

    /// ISO 8601 date formatter with fractional seconds (primary).
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO 8601 date formatter without fractional seconds (fallback).
    nonisolated(unsafe) private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Dependencies

    private let aiClient: any CloudAIClient

    // MARK: - Init

    /// Creates a new vision parsing service.
    ///
    /// - Parameter aiClient: The cloud AI client that supports vision completions.
    init(aiClient: any CloudAIClient) {
        self.aiClient = aiClient
    }

    // MARK: - VisionParsingService

    func parseImage(imageData: Data, ocrText: String?) async throws -> DVGExtractionResult {
        // 1. Resize and re-compress the image.
        let processedImageData = try preprocessImage(imageData)

        // 2. Build the vision prompt.
        let userPrompt = VisionParsingPrompts.buildUserPrompt(ocrText: ocrText)

        // 3. Log approximate request size for cost tracking.
        logRequestCostEstimate(imageBytes: processedImageData.count, promptLength: userPrompt.count)

        // 4. Call the AI with the processed image.
        let aiResponse: String
        do {
            aiResponse = try await aiClient.completeWithVision(
                prompt: userPrompt,
                imageData: processedImageData,
                systemPrompt: VisionParsingPrompts.extractionSystemPrompt
            )
        } catch let error as CloudAIServiceError {
            return handleNetworkError(error, ocrText: ocrText)
        } catch {
            // Non-CloudAIServiceError errors (e.g. URLError) also treated as network failures.
            Self.logger.warning("Vision parsing AI call failed with unexpected error: \(error.localizedDescription)")
            return makeFallbackResult(ocrText: ocrText)
        }

        // 5. Log approximate response size.
        logResponseCostEstimate(responseLength: aiResponse.count)

        // 6. Parse the JSON response.
        return try parseAIResponse(aiResponse)
    }

    // MARK: - Private: Image Pre-Processing

    /// Resizes the image to fit within `ImageConfig.maxLongestEdge` on its
    /// longest dimension and re-encodes it as JPEG at the configured quality.
    ///
    /// Uses `UIGraphicsImageRenderer` (recommended for iOS 10+ / Swift 6) rather
    /// than the deprecated `UIGraphicsBeginImageContextWithOptions`.
    ///
    /// - Parameter imageData: Raw image bytes (any format decodable by `UIImage`).
    /// - Returns: JPEG-encoded bytes of the resized image.
    /// - Throws: `VisionParsingError.imagePreprocessingFailed` when the data
    ///   cannot be decoded or re-encoded.
    private func preprocessImage(_ imageData: Data) throws -> Data {
        guard let originalImage = UIImage(data: imageData) else {
            throw VisionParsingError.imagePreprocessingFailed
        }

        let originalSize = originalImage.size
        let longestEdge = max(originalSize.width, originalSize.height)

        let targetSize: CGSize
        if longestEdge <= ImageConfig.maxLongestEdge {
            // Image is already within limits; skip resize but still re-encode to JPEG.
            targetSize = originalSize
        } else {
            let scale = ImageConfig.maxLongestEdge / longestEdge
            targetSize = CGSize(
                width: (originalSize.width * scale).rounded(),
                height: (originalSize.height * scale).rounded()
            )
        }

        // UIGraphicsImageRenderer produces a display-scale-aware context.
        // Force scale=1 so pixel dimensions match targetSize exactly.
        let renderFormat = UIGraphicsImageRendererFormat()
        renderFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: renderFormat)

        let resizedImage = renderer.image { _ in
            originalImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resizedImage.jpegData(compressionQuality: ImageConfig.jpegQuality) else {
            throw VisionParsingError.imagePreprocessingFailed
        }

        Self.logger.debug(
            "Image pre-processed: \(Int(originalSize.width))x\(Int(originalSize.height)) → \(Int(targetSize.width))x\(Int(targetSize.height)), \(jpegData.count) bytes"
        )

        return jpegData
    }

    // MARK: - Private: Network Error Handling

    /// Maps a `CloudAIServiceError` to either a fallback result (network/transient)
    /// or a thrown `VisionParsingError` (non-recoverable).
    private func handleNetworkError(_ error: CloudAIServiceError, ocrText: String?) -> DVGExtractionResult {
        switch error {
        case .networkError, .rateLimited, .serverError:
            Self.logger.warning("Vision parsing network error — returning OCR fallback: \(error.localizedDescription)")
            return makeFallbackResult(ocrText: ocrText)
        case .noAPIKey, .invalidResponse:
            // These are configuration/logic errors, not transient network failures.
            // Still return a fallback rather than crashing the scan flow.
            Self.logger.error("Vision parsing non-network error: \(error.localizedDescription)")
            return makeFallbackResult(ocrText: ocrText)
        }
    }

    /// Builds a zero-confidence fallback result for use when no network is available.
    ///
    /// The raw OCR text is placed in `discountDescription` so the scan-results UI
    /// (TASK-020) can pre-fill a manual-entry form.
    private func makeFallbackResult(ocrText: String?) -> DVGExtractionResult {
        DVGExtractionResult(
            title: nil,
            code: nil,
            dvgType: nil,
            storeName: nil,
            originalValue: nil,
            discountDescription: ocrText,
            expirationDate: nil,
            termsAndConditions: nil,
            confidenceScore: 0.0,
            fieldConfidences: [
                "title": 0.0,
                "code": 0.0,
                "dvgType": 0.0,
                "storeName": 0.0,
                "originalValue": 0.0,
                "discountDescription": ocrText != nil ? 0.3 : 0.0,
                "expirationDate": 0.0,
                "termsAndConditions": 0.0
            ]
        )
    }

    // MARK: - Private: AI Response Parsing

    /// Parses the raw AI response string into a `DVGExtractionResult`.
    ///
    /// The AI is instructed to return pure JSON, but may occasionally wrap it
    /// in markdown code fences. This method strips any such wrapping before decoding.
    ///
    /// - Parameter response: The raw string returned by the AI.
    /// - Returns: A decoded `DVGExtractionResult`.
    /// - Throws: `VisionParsingError.invalidAIResponse` if decoding fails.
    private func parseAIResponse(_ response: String) throws -> DVGExtractionResult {
        let cleaned = Self.stripMarkdownCodeFences(response)

        guard let data = cleaned.data(using: .utf8) else {
            throw VisionParsingError.invalidAIResponse(
                detail: "Response could not be converted to UTF-8 data."
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds.
            if let date = Self.iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO 8601 without fractional seconds.
            if let date = Self.iso8601FallbackFormatter.date(from: dateString) {
                return date
            }

            // Try date-only format (YYYY-MM-DD) by appending midnight UTC.
            if dateString.count == 10,
               let date = Self.iso8601FallbackFormatter.date(from: dateString + "T00:00:00Z") {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }

        do {
            return try decoder.decode(DVGExtractionResult.self, from: data)
        } catch {
            throw VisionParsingError.invalidAIResponse(
                detail: "Failed to decode AI response: \(error.localizedDescription). Response: \(String(cleaned.prefix(200)))"
            )
        }
    }

    /// Strips markdown code fences (```json ... ``` or ``` ... ```) from a string.
    ///
    /// The AI occasionally wraps JSON in markdown despite instructions not to.
    /// This ensures robust parsing regardless.
    ///
    /// - Parameter text: The raw text that may contain code fences.
    /// - Returns: The text with code fences removed.
    private static func stripMarkdownCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove opening code fence (```json or ```)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
        }

        // Remove closing code fence
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private: Token Cost Logging

    /// Logs an estimated token cost for the request to `os.Logger`.
    ///
    /// `CloudAIClient.completeWithVision()` returns only the text response
    /// (no usage metadata). This estimate is logged to help the user monitor
    /// approximate API costs. A future enhancement could add usage metadata
    /// to the `CloudAIClient` protocol return type.
    ///
    /// Token estimates:
    /// - Image: base64 expands bytes by ~1.33x; Anthropic charges ~1 token per 750px²
    ///   for vision. We use a simple bytes-based approximation.
    /// - Text: ~4 characters per token (typical for English).
    private func logRequestCostEstimate(imageBytes: Int, promptLength: Int) {
        let imageTokenEstimate = Int(Double(imageBytes) / TokenEstimation.imageBytesPerToken)
        let promptTokenEstimate = Int(Double(promptLength) / TokenEstimation.charsPerToken)
        let systemPromptTokenEstimate = Int(
            Double(VisionParsingPrompts.extractionSystemPrompt.count) / TokenEstimation.charsPerToken
        )
        let totalInputEstimate = imageTokenEstimate + promptTokenEstimate + systemPromptTokenEstimate

        Self.logger.info(
            "[VisionParsing] Request — image: ~\(imageTokenEstimate) tokens, prompt: ~\(promptTokenEstimate) tokens, system: ~\(systemPromptTokenEstimate) tokens, total input estimate: ~\(totalInputEstimate) tokens"
        )
    }

    /// Logs an estimated token cost for the AI response.
    private func logResponseCostEstimate(responseLength: Int) {
        let outputTokenEstimate = Int(Double(responseLength) / TokenEstimation.charsPerToken)
        Self.logger.info(
            "[VisionParsing] Response — output: ~\(outputTokenEstimate) tokens"
        )
    }
}
