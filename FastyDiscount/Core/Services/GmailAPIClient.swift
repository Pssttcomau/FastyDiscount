import Foundation

// MARK: - GmailAPIError

/// Typed errors thrown by `GmailAPIClient` implementations.
///
/// Conforms to `Sendable` for Swift 6 strict concurrency and to
/// `LocalizedError` so user-facing messages are available via `localizedDescription`.
enum GmailAPIError: LocalizedError, Sendable {

    /// The user is not authenticated or the access token is invalid.
    case authFailure(detail: String)

    /// Gmail API quota has been exceeded (HTTP 429).
    case quotaExceeded

    /// The requested resource was not found (HTTP 404).
    case notFound(detail: String)

    /// Gmail returned a server error (HTTP 5xx).
    case serverError(statusCode: Int)

    /// The Gmail API response could not be decoded.
    case invalidResponse(detail: String)

    /// A transport-level failure occurred (e.g. no network, DNS failure).
    case networkError(underlying: String)

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .authFailure(let detail):
            return "Gmail authentication failed: \(detail)"
        case .quotaExceeded:
            return "Gmail API quota exceeded. Please wait before trying again."
        case .notFound(let detail):
            return "Gmail resource not found: \(detail)"
        case .serverError(let statusCode):
            return "Gmail server error (HTTP \(statusCode)). Please try again later."
        case .invalidResponse(let detail):
            return "Invalid Gmail API response: \(detail)"
        case .networkError(let underlying):
            return "Network error communicating with Gmail: \(underlying)"
        }
    }
}

// MARK: - EmailScanScope

/// Describes the scope of an email scan operation.
///
/// Used by the Gmail API client to build the appropriate query parameters
/// for listing messages. All filter fields are optional and combined with
/// AND semantics.
///
/// Conforms to `Sendable` so it can be safely passed across concurrency boundaries.
struct EmailScanScope: Sendable {

    /// Gmail label IDs to restrict the search to (e.g. `["CATEGORY_PROMOTIONS"]`).
    ///
    /// When non-empty, only messages with at least one of these labels are returned.
    let selectedLabels: [String]

    /// Sender email addresses to restrict the search to (e.g. `["store@example.com"]`).
    ///
    /// When non-empty, only messages from one of these senders are returned.
    /// Translated into Gmail query syntax: `from:addr1 OR from:addr2`.
    let senderWhitelist: [String]

    /// When `true`, scans the full inbox without label filtering.
    ///
    /// If `true`, `selectedLabels` is ignored (but `senderWhitelist` and
    /// `sinceDate` still apply).
    let scanFullInbox: Bool

    /// Only return messages received on or after this date.
    ///
    /// Translated into Gmail query syntax: `after:YYYY/MM/DD`.
    let sinceDate: Date?

    // MARK: - Init

    /// Creates a new email scan scope.
    ///
    /// - Parameters:
    ///   - selectedLabels: Gmail label IDs to filter by. Defaults to `["CATEGORY_PROMOTIONS"]`.
    ///   - senderWhitelist: Sender email addresses to filter by. Defaults to empty (all senders).
    ///   - scanFullInbox: Whether to scan the full inbox. Defaults to `false`.
    ///   - sinceDate: Only include messages after this date. Defaults to `nil`.
    init(
        selectedLabels: [String] = ["CATEGORY_PROMOTIONS"],
        senderWhitelist: [String] = [],
        scanFullInbox: Bool = false,
        sinceDate: Date? = nil
    ) {
        self.selectedLabels = selectedLabels
        self.senderWhitelist = senderWhitelist
        self.scanFullInbox = scanFullInbox
        self.sinceDate = sinceDate
    }
}

// MARK: - RawEmail

/// A decoded email message fetched from the Gmail API.
///
/// Contains the essential fields needed by the downstream email parsing
/// pipeline (TASK-014). Both the plain text and HTML body are provided;
/// `bodyText` contains either the original `text/plain` part or HTML
/// stripped to plain text if no plain-text part was available.
///
/// Conforms to `Sendable` so it can safely cross concurrency boundaries.
struct RawEmail: Sendable {

    /// The Gmail message ID.
    let id: String

    /// The email subject line.
    let subject: String

    /// The sender address (e.g. `"Store Name <store@example.com>"`).
    let sender: String

    /// The date the email was received.
    let date: Date

    /// The plain-text body content.
    ///
    /// If the email had a `text/plain` MIME part, this is the decoded content.
    /// If only `text/html` was available, this contains the HTML stripped of tags.
    let bodyText: String

    /// The raw HTML body content, if a `text/html` MIME part was present.
    ///
    /// `nil` when the email contained only a `text/plain` part.
    let bodyHTML: String?

    /// Gmail's pre-generated snippet (short preview text).
    let snippet: String
}

// MARK: - EmailFetchPage

/// A page of email results from the Gmail API, supporting cursor-based pagination.
struct EmailFetchPage: Sendable {

    /// The emails in this page.
    let emails: [RawEmail]

    /// The token for fetching the next page, or `nil` if this is the last page.
    let nextPageToken: String?
}

// MARK: - GmailAPIClient Protocol

/// Protocol defining the Gmail API email-fetching interface.
///
/// Provides methods for listing and fetching email messages from Gmail.
/// Uses an authenticated access token obtained from `GmailAuthService`.
///
/// Conforming types must be `Sendable` for safe use across concurrency boundaries.
protocol GmailAPIClient: Sendable {

    /// Fetches a page of emails matching the given scope.
    ///
    /// Builds a Gmail API query from the scope parameters, lists matching message IDs,
    /// then fetches the full content of each message. Emails are returned with decoded
    /// body content (both plain text and HTML).
    ///
    /// - Parameters:
    ///   - scope: The email scan scope defining label, sender, and date filters.
    ///   - maxResults: Maximum number of emails to return per page (1-500). Defaults to 20.
    ///   - pageToken: Pagination token from a previous call's `nextPageToken`. Pass `nil` for the first page.
    /// - Returns: An `EmailFetchPage` containing the emails and an optional next page token.
    /// - Throws: `GmailAPIError` on failure.
    func fetchEmails(
        scope: EmailScanScope,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailFetchPage
}

// MARK: - GmailAPIConfig

/// Configuration constants for the Gmail REST API.
private enum GmailAPIConfig {

    /// Base URL for the Gmail API v1.
    static let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    /// HTTP request timeout for Gmail API calls.
    static let requestTimeout: TimeInterval = 30

    /// Maximum number of concurrent message-detail fetches per batch.
    /// Keeps us well within Gmail's 250 quota-units-per-second limit.
    /// (Each messages.get costs 5 quota units; 10 concurrent = 50 units.)
    static let maxConcurrentFetches = 10
}

// MARK: - GoogleGmailAPIClient

/// Concrete implementation of `GmailAPIClient` backed by the Gmail REST API.
///
/// Uses `URLSession` for all HTTP calls and delegates authentication to
/// a `GmailAuthService` instance. Automatically retries once on HTTP 401
/// by refreshing the access token.
///
/// ### Rate Limiting
/// Gmail API enforces a quota of 250 quota units per user per second.
/// - `messages.list` costs 5 units per call.
/// - `messages.get` costs 5 units per call.
///
/// To respect this quota, message detail fetches are batched with a
/// concurrency limit of 10 (50 units per batch). A small delay is
/// inserted between batches when needed.
///
/// ### Thread Safety
/// This type is a `struct` with only `Sendable` stored properties, making
/// it safe for use across concurrency domains under Swift 6 strict concurrency.
struct GoogleGmailAPIClient: GmailAPIClient {

    // MARK: - Dependencies

    private let authService: any GmailAuthService
    private let session: URLSession

    // MARK: - Init

    /// Creates a new Gmail API client.
    ///
    /// - Parameters:
    ///   - authService: The authentication service for obtaining access tokens.
    ///   - session: The URL session for network requests (injectable for testing).
    init(
        authService: any GmailAuthService,
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = GmailAPIConfig.requestTimeout
            config.timeoutIntervalForResource = GmailAPIConfig.requestTimeout
            return URLSession(configuration: config)
        }()
    ) {
        self.authService = authService
        self.session = session
    }

    // MARK: - GmailAPIClient

    func fetchEmails(
        scope: EmailScanScope,
        maxResults: Int = 20,
        pageToken: String? = nil
    ) async throws -> EmailFetchPage {
        let clampedMaxResults = min(max(maxResults, 1), 500)

        // Step 1: List message IDs matching the scope
        let listResult = try await listMessages(
            scope: scope,
            maxResults: clampedMaxResults,
            pageToken: pageToken
        )

        guard !listResult.messageIDs.isEmpty else {
            return EmailFetchPage(emails: [], nextPageToken: listResult.nextPageToken)
        }

        // Step 2: Fetch full message content for each ID (batched for rate limiting)
        let emails = try await fetchMessageDetails(messageIDs: listResult.messageIDs)

        return EmailFetchPage(emails: emails, nextPageToken: listResult.nextPageToken)
    }

    // MARK: - Private: List Messages

    /// Result of a `messages.list` call, containing message IDs and pagination info.
    private struct ListResult: Sendable {
        let messageIDs: [String]
        let nextPageToken: String?
    }

    /// Lists message IDs matching the given scope using the Gmail `messages.list` endpoint.
    ///
    /// - Parameters:
    ///   - scope: The email scan scope.
    ///   - maxResults: Maximum number of results.
    ///   - pageToken: Pagination token.
    /// - Returns: A `ListResult` with message IDs and optional next page token.
    private func listMessages(
        scope: EmailScanScope,
        maxResults: Int,
        pageToken: String?
    ) async throws -> ListResult {
        var urlComponents = URLComponents(string: "\(GmailAPIConfig.baseURL)/messages")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        // Build the Gmail search query string
        let queryString = buildQueryString(from: scope)
        if !queryString.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: queryString))
        }

        // Add label IDs as separate parameters (Gmail API accepts multiple labelIds params)
        if !scope.scanFullInbox {
            for label in scope.selectedLabels {
                queryItems.append(URLQueryItem(name: "labelIds", value: label))
            }
        }

        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidResponse(detail: "Failed to construct messages list URL.")
        }

        let data = try await performAuthenticatedRequest(url: url)

        // Parse the list response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GmailAPIError.invalidResponse(detail: "messages.list response is not valid JSON.")
        }

        let nextToken = json["nextPageToken"] as? String

        // If no messages match, the "messages" key may be absent
        guard let messagesArray = json["messages"] as? [[String: Any]] else {
            return ListResult(messageIDs: [], nextPageToken: nextToken)
        }

        let messageIDs = messagesArray.compactMap { $0["id"] as? String }
        return ListResult(messageIDs: messageIDs, nextPageToken: nextToken)
    }

    /// Builds a Gmail search query string from an `EmailScanScope`.
    ///
    /// Example output: `"from:store@example.com OR from:other@example.com after:2025/01/15"`
    private func buildQueryString(from scope: EmailScanScope) -> String {
        var parts: [String] = []

        // Sender whitelist: combine with OR
        if !scope.senderWhitelist.isEmpty {
            if scope.senderWhitelist.count == 1 {
                parts.append("from:\(scope.senderWhitelist[0])")
            } else {
                let senderClauses = scope.senderWhitelist.map { "from:\($0)" }
                parts.append("(\(senderClauses.joined(separator: " OR ")))")
            }
        }

        // Date filter
        if let sinceDate = scope.sinceDate {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: sinceDate)
            let month = calendar.component(.month, from: sinceDate)
            let day = calendar.component(.day, from: sinceDate)
            parts.append("after:\(year)/\(month)/\(day)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Private: Fetch Message Details

    /// Fetches full message content for each message ID, respecting rate limits.
    ///
    /// Uses `TaskGroup` with a concurrency limit to avoid exceeding Gmail's
    /// 250 quota-units-per-second limit.
    ///
    /// - Parameter messageIDs: The Gmail message IDs to fetch.
    /// - Returns: An array of `RawEmail` values in the same order as the input IDs.
    private func fetchMessageDetails(messageIDs: [String]) async throws -> [RawEmail] {
        // Process in batches to respect rate limits
        var allEmails: [RawEmail] = []

        let batchSize = GmailAPIConfig.maxConcurrentFetches
        let batches = stride(from: 0, to: messageIDs.count, by: batchSize)

        for batchStart in batches {
            let batchEnd = min(batchStart + batchSize, messageIDs.count)
            let batchIDs = Array(messageIDs[batchStart..<batchEnd])

            let batchEmails = try await withThrowingTaskGroup(
                of: (Int, RawEmail?).self
            ) { group in
                for (index, messageID) in batchIDs.enumerated() {
                    group.addTask {
                        do {
                            let email = try await self.fetchSingleMessage(id: messageID)
                            return (index, email)
                        } catch {
                            // Log but continue: individual message failures should not
                            // abort the entire batch. The caller receives only
                            // successfully fetched emails.
                            return (index, nil)
                        }
                    }
                }

                var results: [(Int, RawEmail?)] = []
                for try await result in group {
                    results.append(result)
                }

                // Sort by original index to maintain ordering
                return results
                    .sorted { $0.0 < $1.0 }
                    .compactMap { $0.1 }
            }

            allEmails.append(contentsOf: batchEmails)

            // Small delay between batches to respect rate limits
            // (only if there are more batches to process)
            if batchEnd < messageIDs.count {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }

        return allEmails
    }

    /// Fetches a single message by ID using the Gmail `messages.get` endpoint with `format=full`.
    ///
    /// - Parameter id: The Gmail message ID.
    /// - Returns: A decoded `RawEmail`.
    private func fetchSingleMessage(id: String) async throws -> RawEmail {
        guard let url = URL(string: "\(GmailAPIConfig.baseURL)/messages/\(id)?format=full") else {
            throw GmailAPIError.invalidResponse(detail: "Failed to construct message URL for ID: \(id).")
        }

        let data = try await performAuthenticatedRequest(url: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GmailAPIError.invalidResponse(detail: "messages.get response is not valid JSON for ID: \(id).")
        }

        return try parseMessage(json: json)
    }

    // MARK: - Private: Message Parsing

    /// Parses a Gmail API message JSON object into a `RawEmail`.
    ///
    /// Extracts headers (Subject, From, Date), body content from MIME parts,
    /// and the snippet. Body data is decoded from Gmail's base64url encoding.
    private func parseMessage(json: [String: Any]) throws -> RawEmail {
        guard let messageID = json["id"] as? String else {
            throw GmailAPIError.invalidResponse(detail: "Message missing 'id' field.")
        }

        let snippet = json["snippet"] as? String ?? ""

        // Parse headers from the payload
        guard let payload = json["payload"] as? [String: Any] else {
            throw GmailAPIError.invalidResponse(detail: "Message \(messageID) missing 'payload'.")
        }

        let headers = payload["headers"] as? [[String: Any]] ?? []
        let subject = headerValue(name: "Subject", in: headers) ?? "(No Subject)"
        let sender = headerValue(name: "From", in: headers) ?? "(Unknown Sender)"
        let dateString = headerValue(name: "Date", in: headers) ?? ""

        // Parse the received date
        let date = parseEmailDate(dateString) ?? Date(timeIntervalSince1970: 0)

        // Extract body content from MIME parts
        let (plainText, htmlText) = extractBodyParts(from: payload)

        // Build the bodyText: prefer plain text, fall back to stripped HTML
        let bodyText: String
        if let plain = plainText, !plain.isEmpty {
            bodyText = plain
        } else if let html = htmlText, !html.isEmpty {
            bodyText = Self.stripHTML(html)
        } else {
            bodyText = snippet
        }

        return RawEmail(
            id: messageID,
            subject: subject,
            sender: sender,
            date: date,
            bodyText: bodyText,
            bodyHTML: htmlText,
            snippet: snippet
        )
    }

    /// Extracts the value of a header by name from a Gmail headers array.
    ///
    /// - Parameters:
    ///   - name: The header name (case-insensitive).
    ///   - headers: The array of header dictionaries from the Gmail API.
    /// - Returns: The header value, or `nil` if not found.
    private func headerValue(name: String, in headers: [[String: Any]]) -> String? {
        let lowered = name.lowercased()
        for header in headers {
            if let headerName = header["name"] as? String,
               headerName.lowercased() == lowered,
               let value = header["value"] as? String {
                return value
            }
        }
        return nil
    }

    /// Recursively extracts `text/plain` and `text/html` body parts from a Gmail MIME payload.
    ///
    /// Gmail messages can have various MIME structures:
    /// - Simple: body data directly on the payload
    /// - Multipart: body data nested in `payload.parts[].body.data`
    /// - Nested multipart: `payload.parts[].parts[].body.data`
    ///
    /// - Parameter payload: The Gmail payload dictionary.
    /// - Returns: A tuple of (plainText, htmlText), either or both of which may be `nil`.
    private func extractBodyParts(from payload: [String: Any]) -> (String?, String?) {
        var plainText: String?
        var htmlText: String?

        // Check if this payload itself has body data
        let mimeType = payload["mimeType"] as? String ?? ""

        if let body = payload["body"] as? [String: Any],
           let data = body["data"] as? String,
           !data.isEmpty {
            if mimeType == "text/plain" {
                plainText = decodeBase64URL(data)
            } else if mimeType == "text/html" {
                htmlText = decodeBase64URL(data)
            }
        }

        // Recursively check parts (multipart messages)
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                let (partPlain, partHTML) = extractBodyParts(from: part)
                if plainText == nil, let partPlain {
                    plainText = partPlain
                }
                if htmlText == nil, let partHTML {
                    htmlText = partHTML
                }
                // Stop once we have both
                if plainText != nil && htmlText != nil {
                    break
                }
            }
        }

        return (plainText, htmlText)
    }

    /// Decodes a Gmail base64url-encoded string to a UTF-8 string.
    ///
    /// Gmail uses a URL-safe variant of base64 (RFC 4648 Section 5) where:
    /// - `+` is replaced with `-`
    /// - `/` is replaced with `_`
    /// - Padding `=` characters may be omitted
    ///
    /// - Parameter base64url: The base64url-encoded string.
    /// - Returns: The decoded UTF-8 string, or `nil` if decoding fails.
    private func decodeBase64URL(_ base64url: String) -> String? {
        // Convert base64url to standard base64
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if necessary
        let paddingNeeded = (4 - base64.count % 4) % 4
        base64.append(contentsOf: String(repeating: "=", count: paddingNeeded))

        guard let data = Data(base64Encoded: base64) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Parses an email `Date` header into a `Date` value.
    ///
    /// Supports the common RFC 2822 format used in email headers:
    /// `"Mon, 15 Jan 2025 10:30:00 +0000"` or `"15 Jan 2025 10:30:00 +0000"`
    ///
    /// - Parameter dateString: The raw date header value.
    /// - Returns: A parsed `Date`, or `nil` if the format is not recognized.
    private func parseEmailDate(_ dateString: String) -> Date? {
        // Try RFC 2822 with day-of-week
        if let date = Self.rfc2822FormatterWithDay.date(from: dateString) {
            return date
        }

        // Try RFC 2822 without day-of-week
        if let date = Self.rfc2822FormatterNoDay.date(from: dateString) {
            return date
        }

        // Try ISO 8601 as a last resort
        if let date = Self.iso8601Formatter.date(from: dateString) {
            return date
        }

        // Try extracting a timestamp from internalDate if the string is purely numeric
        if let millis = Double(dateString) {
            return Date(timeIntervalSince1970: millis / 1000.0)
        }

        return nil
    }

    // MARK: - Private: HTML Stripping

    /// Strips HTML tags from a string using a lightweight regex-based approach.
    ///
    /// This is used in a nonisolated context, so we avoid `NSAttributedString`
    /// HTML parsing (which requires `@MainActor`). The approach:
    /// 1. Removes `<style>` and `<script>` blocks entirely
    /// 2. Replaces `<br>`, `<p>`, `<div>`, and `<li>` tags with newlines
    /// 3. Strips all remaining HTML tags
    /// 4. Decodes common HTML entities
    /// 5. Collapses excessive whitespace
    ///
    /// - Parameter html: The raw HTML string.
    /// - Returns: The plain-text content.
    static func stripHTML(_ html: String) -> String {
        var result = html

        // Remove style and script blocks entirely
        result = result.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )

        // Replace block-level elements with newlines for readability
        result = result.replacingOccurrences(
            of: "<br[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "</p>",
            with: "\n\n",
            options: .caseInsensitive
        )
        result = result.replacingOccurrences(
            of: "</div>",
            with: "\n",
            options: .caseInsensitive
        )
        result = result.replacingOccurrences(
            of: "</li>",
            with: "\n",
            options: .caseInsensitive
        )
        result = result.replacingOccurrences(
            of: "</tr>",
            with: "\n",
            options: .caseInsensitive
        )
        result = result.replacingOccurrences(
            of: "</td>",
            with: " ",
            options: .caseInsensitive
        )

        // Strip all remaining HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        result = decodeHTMLEntities(result)

        // Collapse multiple whitespace/newlines
        result = result.replacingOccurrences(
            of: "[ \\t]+",
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes common HTML entities to their plain-text equivalents.
    ///
    /// Handles named entities (e.g. `&amp;`) and decimal numeric entities
    /// (e.g. `&#8217;`).
    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        // Replace named entities
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}"),
            ("&copy;", "\u{00A9}"),
            ("&reg;", "\u{00AE}"),
            ("&trade;", "\u{2122}"),
            ("&bull;", "\u{2022}"),
            ("&laquo;", "\u{00AB}"),
            ("&raquo;", "\u{00BB}")
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode decimal numeric entities (e.g. &#8217;)
        result = replaceNumericEntities(in: result)

        return result
    }

    /// Replaces numeric HTML entities (e.g. `&#8217;`) with their Unicode characters.
    private static func replaceNumericEntities(in string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(\\d+);") else {
            return string
        }

        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))

        guard !matches.isEmpty else { return string }

        var result = string
        // Process matches in reverse order to preserve range validity
        for match in matches.reversed() {
            let fullRange = Range(match.range, in: result)!
            let numberRange = Range(match.range(at: 1), in: result)!
            let numberString = String(result[numberRange])

            if let codePoint = UInt32(numberString),
               let scalar = Unicode.Scalar(codePoint) {
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }

        return result
    }

    // MARK: - Private: Authenticated Requests

    /// Performs an authenticated GET request to the Gmail API.
    ///
    /// If the initial request returns HTTP 401, automatically refreshes the
    /// access token via `GmailAuthService.refreshToken()` and retries once.
    ///
    /// - Parameter url: The Gmail API endpoint URL.
    /// - Returns: The response data on success.
    /// - Throws: `GmailAPIError` on failure.
    private func performAuthenticatedRequest(url: URL) async throws -> Data {
        let accessToken = try await authService.getAccessToken()

        do {
            return try await executeRequest(url: url, accessToken: accessToken)
        } catch let error as GmailAPIError {
            // Retry once on auth failure (401) by refreshing the token
            if case .authFailure = error {
                try await authService.refreshToken()
                let refreshedToken = try await authService.getAccessToken()
                return try await executeRequest(url: url, accessToken: refreshedToken)
            }
            throw error
        }
    }

    /// Executes a single authenticated GET request.
    ///
    /// - Parameters:
    ///   - url: The request URL.
    ///   - accessToken: The OAuth 2.0 access token.
    /// - Returns: The response body data.
    /// - Throws: `GmailAPIError` mapped from the HTTP status code.
    private func executeRequest(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GmailAPIError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError(underlying: "No HTTP response received.")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data

        case 401:
            throw GmailAPIError.authFailure(detail: "Access token is invalid or expired (HTTP 401).")

        case 404:
            throw GmailAPIError.notFound(detail: "Requested resource not found (HTTP 404).")

        case 429:
            throw GmailAPIError.quotaExceeded

        case 500...599:
            throw GmailAPIError.serverError(statusCode: httpResponse.statusCode)

        default:
            // Try to extract an error message from the response body
            let detail: String
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJSON["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                detail = "HTTP \(httpResponse.statusCode): \(message)"
            } else {
                detail = "HTTP \(httpResponse.statusCode)"
            }
            throw GmailAPIError.invalidResponse(detail: detail)
        }
    }

    // MARK: - Private: Date Formatters

    /// RFC 2822 date formatter with day-of-week prefix.
    ///
    /// Format: `"Mon, 15 Jan 2025 10:30:00 +0000"`
    private static let rfc2822FormatterWithDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    /// RFC 2822 date formatter without day-of-week prefix.
    ///
    /// Format: `"15 Jan 2025 10:30:00 +0000"`
    private static let rfc2822FormatterNoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    /// ISO 8601 date formatter as a fallback.
    ///
    /// Uses `nonisolated(unsafe)` because `ISO8601DateFormatter` (an `NSObject`
    /// subclass) does not conform to `Sendable`.
    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
}
