import Foundation
import SwiftData

// MARK: - EmailParsingError

/// Typed errors thrown during email parsing operations.
///
/// Conforms to `Sendable` for Swift 6 strict concurrency and to
/// `LocalizedError` so user-facing messages are available via `localizedDescription`.
enum EmailParsingError: LocalizedError, Sendable {

    /// The AI service returned a response that could not be decoded as JSON.
    case invalidAIResponse(detail: String)

    /// The AI service call failed for a specific email.
    case aiServiceFailed(emailSubject: String, underlying: String)

    /// A duplicate email was detected and skipped.
    case duplicateEmail(subject: String, sender: String)

    /// The model context is not available for persistence.
    case contextUnavailable

    /// Failed to save the extraction result.
    case saveFailed(detail: String)

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidAIResponse(let detail):
            return "Invalid AI response during email parsing: \(detail)"
        case .aiServiceFailed(let subject, let underlying):
            return "AI extraction failed for email '\(subject)': \(underlying)"
        case .duplicateEmail(let subject, let sender):
            return "Duplicate email skipped: '\(subject)' from \(sender)."
        case .contextUnavailable:
            return "Model context is not available for saving parsed results."
        case .saveFailed(let detail):
            return "Failed to save parsed email result: \(detail)"
        }
    }
}

// MARK: - EmailParseProgress

/// Progress updates emitted during email parsing.
///
/// Consumed by the email scan UI (TASK-015) via `AsyncStream` to display
/// per-email progress indicators and results.
enum EmailParseProgress: Sendable {

    /// An email is currently being parsed.
    ///
    /// - Parameters:
    ///   - index: Zero-based index of the email currently being processed.
    ///   - total: Total number of emails to process.
    case parsing(index: Int, total: Int)

    /// An email was successfully parsed and saved.
    ///
    /// - Parameter result: The structured extraction result from the AI.
    case parsed(DVGExtractionResult)

    /// Parsing failed for a specific email.
    ///
    /// - Parameters:
    ///   - index: Zero-based index of the email that failed.
    ///   - error: The error that occurred.
    case failed(index: Int, error: Error)

    /// All emails have been processed.
    ///
    /// - Parameter results: The successfully extracted results.
    case complete(results: [DVGExtractionResult])
}

// MARK: - EmailParsingService Protocol

/// Abstraction for the email-to-DVG extraction pipeline.
///
/// Conforming types process raw emails through an AI extraction service,
/// create `ScanResult` and `DVG` records, and stream progress updates
/// for real-time UI feedback.
///
/// Must be `@MainActor` because SwiftData `ModelContext` requires main actor access.
@MainActor
protocol EmailParsingService: AnyObject, Sendable {

    /// Parses a batch of raw emails, extracting DVG information from each.
    ///
    /// Emails are processed sequentially to respect AI API rate limits.
    /// Progress is reported via an `AsyncStream` for real-time UI updates.
    ///
    /// - Parameters:
    ///   - emails: The raw emails to parse.
    ///   - sinceDate: Optional date filter; emails older than this are skipped.
    /// - Returns: An `AsyncStream` emitting `EmailParseProgress` updates.
    func parseEmails(
        _ emails: [RawEmail],
        sinceDate: Date?
    ) -> AsyncStream<EmailParseProgress>
}

// MARK: - Prompts

/// System prompt templates for the AI extraction pipeline.
///
/// Centralised here so they can be tested and maintained independently
/// of the parsing logic.
enum EmailParsingPrompts {

    /// System prompt instructing the AI to extract DVG fields from email body text.
    ///
    /// The prompt specifies the exact JSON schema the AI must return, including
    /// per-field and overall confidence scores.
    static let extractionSystemPrompt = """
    You are a structured data extraction assistant. Your task is to extract \
    discount, voucher, and gift card information from email content.

    Analyze the provided email text and extract the following fields. Return \
    ONLY a valid JSON object with no additional text, markdown, or explanation.

    Required JSON schema:
    {
      "title": "string or null — A concise title for the deal (e.g. '20% off your next order')",
      "code": "string or null — The promotional/discount code (e.g. 'SAVE20')",
      "dvgType": "string or null — One of: 'discountCode', 'voucher', 'giftCard', 'loyaltyPoints', 'barcodeCoupon'",
      "storeName": "string or null — The store or brand name offering the promotion",
      "originalValue": "number or null — The face/monetary value (e.g. 50.0 for a $50 gift card)",
      "discountDescription": "string or null — Description of the discount (e.g. '20% off all items')",
      "expirationDate": "string or null — Expiration date in ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ). If only a date is given, use midnight UTC.",
      "termsAndConditions": "string or null — Any terms, conditions, or restrictions",
      "confidenceScore": "number — Overall confidence in the extraction, 0.0 to 1.0",
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
    - If a field cannot be determined from the email, set it to null and give \
    that field a confidence of 0.0.
    - The confidenceScore should reflect your overall confidence that this email \
    contains a valid discount/voucher/gift card. Set it below 0.5 if the email \
    does not appear to contain any promotion.
    - For dvgType, choose the most appropriate category based on the content.
    - For expirationDate, always return ISO 8601 format (e.g. "2025-12-31T00:00:00Z").
    - Extract the exact promotional code if one is present. Do not invent codes.
    - Return ONLY the JSON object. No markdown fences, no explanation.
    """

    /// Builds the user-facing prompt containing the email content for extraction.
    ///
    /// - Parameters:
    ///   - subject: The email subject line.
    ///   - sender: The email sender address.
    ///   - body: The email body text.
    /// - Returns: A formatted prompt string.
    static func buildUserPrompt(subject: String, sender: String, body: String) -> String {
        // Truncate very long email bodies to stay within token limits.
        // 8000 characters is approximately 2000 tokens, well within limits.
        let truncatedBody: String
        if body.count > 8000 {
            truncatedBody = String(body.prefix(8000)) + "\n[... truncated ...]"
        } else {
            truncatedBody = body
        }

        return """
        Extract discount/voucher/gift card information from this email:

        Subject: \(subject)
        From: \(sender)

        Email body:
        \(truncatedBody)
        """
    }
}

// MARK: - CloudAIEmailParsingService

/// Concrete implementation of `EmailParsingService` backed by `CloudAIClient`.
///
/// Processes emails sequentially through the AI extraction pipeline, creates
/// `ScanResult` and `DVG` records in SwiftData, and streams progress updates
/// for UI consumption.
///
/// ### Threading
/// `@MainActor` because SwiftData `ModelContext` operations must run on the
/// main actor. The AI calls themselves are `async` and will suspend off the
/// main thread via structured concurrency.
///
/// ### Deduplication
/// Before processing each email, checks whether a `ScanResult` with the same
/// `emailSubject + emailSender + emailDate` already exists. Duplicates are
/// silently skipped.
///
/// ### Confidence Routing
/// - Results with `confidenceScore >= 0.8` are saved with `needsReview = false`
///   (auto-accepted).
/// - Results with `confidenceScore < 0.8` are saved with `needsReview = true`
///   and routed to the review queue (TASK-016).
@MainActor
final class CloudAIEmailParsingService: EmailParsingService {

    // MARK: - Constants

    /// Confidence threshold above which results are auto-accepted.
    private static let highConfidenceThreshold: Double = 0.8

    // MARK: - Dependencies

    private let aiClient: any CloudAIClient
    private let modelContext: ModelContext

    // MARK: - Date Formatter

    /// ISO 8601 date formatter for parsing AI-returned date strings.
    ///
    /// Uses `nonisolated(unsafe)` because `ISO8601DateFormatter` (an `NSObject`
    /// subclass) does not conform to `Sendable`. Safe here because all access
    /// is confined to `@MainActor`.
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()

    /// Fallback ISO 8601 formatter without fractional seconds.
    nonisolated(unsafe) private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Init

    /// Creates a new email parsing service.
    ///
    /// - Parameters:
    ///   - aiClient: The cloud AI client for text extraction.
    ///   - modelContext: The SwiftData model context for persistence.
    init(aiClient: any CloudAIClient, modelContext: ModelContext) {
        self.aiClient = aiClient
        self.modelContext = modelContext
    }

    // MARK: - EmailParsingService

    func parseEmails(
        _ emails: [RawEmail],
        sinceDate: Date? = nil
    ) -> AsyncStream<EmailParseProgress> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                // Filter by sinceDate if provided
                let filteredEmails: [RawEmail]
                if let sinceDate {
                    filteredEmails = emails.filter { $0.date >= sinceDate }
                } else {
                    filteredEmails = emails
                }

                let total = filteredEmails.count
                var successfulResults: [DVGExtractionResult] = []

                for (index, email) in filteredEmails.enumerated() {
                    // Emit progress
                    continuation.yield(.parsing(index: index, total: total))

                    // Dedup check: skip if an identical ScanResult already exists
                    if self.isDuplicate(email: email) {
                        let error = EmailParsingError.duplicateEmail(
                            subject: email.subject,
                            sender: email.sender
                        )
                        continuation.yield(.failed(index: index, error: error))
                        continue
                    }

                    do {
                        // Call the AI to extract structured data
                        let extractionResult = try await self.extractFromEmail(email)

                        // Save ScanResult + DVG to SwiftData
                        try self.saveExtractionResult(
                            extractionResult,
                            from: email
                        )

                        successfulResults.append(extractionResult)
                        continuation.yield(.parsed(extractionResult))
                    } catch {
                        continuation.yield(.failed(index: index, error: error))
                        // Continue processing remaining emails
                    }
                }

                // Emit completion
                continuation.yield(.complete(results: successfulResults))
                continuation.finish()
            }
        }
    }

    // MARK: - Private: AI Extraction

    /// Sends an email's content to the AI for structured extraction.
    ///
    /// - Parameter email: The raw email to extract from.
    /// - Returns: A `DVGExtractionResult` parsed from the AI response.
    /// - Throws: `EmailParsingError` if the AI call or response parsing fails.
    private func extractFromEmail(_ email: RawEmail) async throws -> DVGExtractionResult {
        let userPrompt = EmailParsingPrompts.buildUserPrompt(
            subject: email.subject,
            sender: email.sender,
            body: email.bodyText
        )

        let aiResponse: String
        do {
            aiResponse = try await aiClient.complete(
                prompt: userPrompt,
                systemPrompt: EmailParsingPrompts.extractionSystemPrompt
            )
        } catch {
            throw EmailParsingError.aiServiceFailed(
                emailSubject: email.subject,
                underlying: error.localizedDescription
            )
        }

        return try parseAIResponse(aiResponse)
    }

    /// Parses the raw AI response string into a `DVGExtractionResult`.
    ///
    /// The AI is instructed to return pure JSON, but may occasionally wrap it
    /// in markdown code fences. This method strips any such wrapping before
    /// decoding.
    ///
    /// - Parameter response: The raw string returned by the AI.
    /// - Returns: A decoded `DVGExtractionResult`.
    /// - Throws: `EmailParsingError.invalidAIResponse` if decoding fails.
    private func parseAIResponse(_ response: String) throws -> DVGExtractionResult {
        // Strip markdown code fences if present
        let cleaned = Self.stripMarkdownCodeFences(response)

        guard let data = cleaned.data(using: .utf8) else {
            throw EmailParsingError.invalidAIResponse(
                detail: "Response could not be converted to UTF-8 data."
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds
            if let date = Self.iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO 8601 without fractional seconds
            if let date = Self.iso8601FallbackFormatter.date(from: dateString) {
                return date
            }

            // Try date-only format (YYYY-MM-DD)
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
            throw EmailParsingError.invalidAIResponse(
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
            // Find the end of the first line (the opening fence line)
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

    // MARK: - Private: Persistence

    /// Saves the extraction result as a `ScanResult` and `DVG` in SwiftData.
    ///
    /// - High-confidence results (`>= 0.8`) are saved with `needsReview = false`.
    /// - Low-confidence results are saved with `needsReview = true` for the review queue.
    ///
    /// - Parameters:
    ///   - result: The extracted DVG information.
    ///   - email: The source email.
    /// - Throws: `EmailParsingError.saveFailed` if SwiftData persistence fails.
    private func saveExtractionResult(
        _ result: DVGExtractionResult,
        from email: RawEmail
    ) throws {
        let needsReview = result.confidenceScore < Self.highConfidenceThreshold

        // Create ScanResult
        let scanResult = ScanResult(
            sourceType: .email,
            rawText: email.bodyText,
            confidenceScore: result.confidenceScore,
            needsReview: needsReview,
            emailSubject: email.subject,
            emailSender: email.sender,
            emailDate: email.date,
            isDeleted: false
        )

        // Persist per-field confidence scores as JSON
        if let jsonData = try? JSONEncoder().encode(result.fieldConfidences),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            scanResult.fieldConfidencesJSON = jsonString
        }

        // Create DVG from extraction result
        let dvg = DVG(
            title: result.title ?? "",
            code: result.code ?? "",
            dvgType: result.dvgType ?? .discountCode,
            storeName: result.storeName ?? "",
            originalValue: result.originalValue ?? 0.0,
            remainingBalance: result.originalValue ?? 0.0,
            discountDescription: result.discountDescription ?? "",
            expirationDate: result.expirationDate,
            source: .email,
            status: .active,
            termsAndConditions: result.termsAndConditions ?? "",
            isDeleted: false
        )

        // Link the ScanResult to the DVG
        dvg.scanResult = scanResult

        // Insert into SwiftData context
        modelContext.insert(dvg)
        modelContext.insert(scanResult)

        do {
            try modelContext.save()
        } catch {
            throw EmailParsingError.saveFailed(
                detail: error.localizedDescription
            )
        }
    }

    // MARK: - Private: Deduplication

    /// Checks whether a `ScanResult` already exists for the given email.
    ///
    /// Deduplication uses the combination of `emailSubject`, `emailSender`,
    /// and `emailDate` to identify previously processed emails.
    ///
    /// - Parameter email: The raw email to check.
    /// - Returns: `true` if a matching `ScanResult` already exists.
    private func isDuplicate(email: RawEmail) -> Bool {
        let subject = email.subject
        let sender = email.sender
        let emailDate = email.date
        let emailSourceType = ScanSourceType.email.rawValue

        let descriptor = FetchDescriptor<ScanResult>(
            predicate: #Predicate<ScanResult> {
                $0.isDeleted == false
                && $0.sourceType == emailSourceType
                && $0.emailSubject == subject
                && $0.emailSender == sender
                && $0.emailDate == emailDate
            }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            // If the fetch fails, assume no duplicate and proceed
            return false
        }
    }
}
