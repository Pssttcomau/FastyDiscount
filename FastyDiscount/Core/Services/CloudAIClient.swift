import Foundation

// MARK: - CloudAIServiceError

/// Errors that can be thrown by a `CloudAIClient` implementation.
///
/// Conforms to `Sendable` for Swift 6 strict concurrency and to
/// `LocalizedError` so the message is surfaced to the user.
enum CloudAIServiceError: LocalizedError, Sendable {

    /// No API key is present in the Keychain — the user must supply one.
    case noAPIKey

    /// A transport-level failure occurred (e.g. no network, DNS failure).
    case networkError(underlying: String)

    /// The server returned HTTP 429 (Too Many Requests) and retries were exhausted.
    case rateLimited

    /// The server returned a response that could not be decoded.
    case invalidResponse(detail: String)

    /// The server returned a 5xx status code that could not be recovered.
    case serverError(statusCode: Int)

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key found. Please add your API key in Settings."
        case .networkError(let underlying):
            return "Network error: \(underlying)"
        case .rateLimited:
            return "Rate limit exceeded. Please wait before trying again."
        case .invalidResponse(let detail):
            return "Invalid response from AI service: \(detail)"
        case .serverError(let code):
            return "AI service server error (HTTP \(code)). Please try again later."
        }
    }
}

// MARK: - CloudAIClient Protocol

/// Abstraction over a remote language-model API.
///
/// All conforming types must be `Sendable` so that client values can be
/// freely passed across Swift 6 actor boundaries.
protocol CloudAIClient: Sendable {

    /// Sends a text-only prompt to the model.
    ///
    /// - Parameters:
    ///   - prompt: The user-role message.
    ///   - systemPrompt: The system-role instruction (used to enforce JSON output format, etc.).
    /// - Returns: The raw text completion returned by the model.
    func complete(prompt: String, systemPrompt: String) async throws -> String

    /// Sends a prompt together with a single image to the model.
    ///
    /// - Parameters:
    ///   - prompt: The user-role message.
    ///   - imageData: Raw image bytes (JPEG or PNG).
    ///   - systemPrompt: The system-role instruction.
    /// - Returns: The raw text completion returned by the model.
    func completeWithVision(prompt: String, imageData: Data, systemPrompt: String) async throws -> String
}

// MARK: - AnthropicClient

/// Concrete implementation of `CloudAIClient` backed by the Anthropic
/// Messages API (`claude-sonnet-4-20250514`).
///
/// API key is retrieved from the Keychain on every call so that it always
/// reflects the latest value saved by the user — no in-memory caching means
/// key rotations take effect immediately.
///
/// ### Retry behaviour
/// Transient failures (HTTP 429, 500, 503) are retried up to `maxRetries`
/// times with exponential back-off (base 1 s, doubles each attempt, capped
/// at 30 s).
///
/// Declared as a `struct` — all stored properties are value types or
/// themselves `Sendable`, so the compiler can verify `Sendable` conformance
/// automatically.
struct AnthropicClient: CloudAIClient {

    // MARK: - Constants

    private enum Anthropic {
        static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        static let model = "claude-sonnet-4-20250514"
        static let apiVersion = "2023-06-01"
        static let maxTokens = 4096
        static let requestTimeout: TimeInterval = 30
        static let maxRetries = 3
        static let baseBackoffSeconds: Double = 1.0
        static let maxBackoffSeconds: Double = 30.0
    }

    /// Keychain account key under which the Anthropic API key is stored.
    static let keychainKey = "anthropic_api_key"

    // MARK: - Dependencies

    private let keychain: KeychainService
    private let session: URLSession

    // MARK: - Init

    /// - Parameters:
    ///   - keychain: The keychain service used to retrieve the API key.
    ///   - session: The URLSession used for network calls (injectable for testing).
    init(
        keychain: KeychainService = KeychainService(),
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Anthropic.requestTimeout
            config.timeoutIntervalForResource = Anthropic.requestTimeout
            return URLSession(configuration: config)
        }()
    ) {
        self.keychain = keychain
        self.session = session
    }

    // MARK: - CloudAIClient

    func complete(prompt: String, systemPrompt: String) async throws -> String {
        let apiKey = try retrieveAPIKey()
        let body = makeTextBody(prompt: prompt, systemPrompt: systemPrompt)
        return try await performRequest(body: body, apiKey: apiKey)
    }

    func completeWithVision(prompt: String, imageData: Data, systemPrompt: String) async throws -> String {
        let apiKey = try retrieveAPIKey()
        let body = makeVisionBody(prompt: prompt, imageData: imageData, systemPrompt: systemPrompt)
        return try await performRequest(body: body, apiKey: apiKey)
    }

    // MARK: - Private: API Key

    private func retrieveAPIKey() throws -> String {
        do {
            guard let key = try keychain.read(forKey: AnthropicClient.keychainKey),
                  !key.isEmpty else {
                throw CloudAIServiceError.noAPIKey
            }
            return key
        } catch let error as CloudAIServiceError {
            throw error
        } catch {
            throw CloudAIServiceError.noAPIKey
        }
    }

    // MARK: - Private: Request Bodies

    /// Builds the JSON body for a text-only completion.
    private func makeTextBody(prompt: String, systemPrompt: String) -> [String: Any] {
        [
            "model": Anthropic.model,
            "max_tokens": Anthropic.maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
    }

    /// Builds the JSON body for a vision completion.
    ///
    /// Anthropic vision requests embed the image as a base64-encoded `image`
    /// content block alongside the text prompt in the same user message.
    private func makeVisionBody(
        prompt: String,
        imageData: Data,
        systemPrompt: String
    ) -> [String: Any] {
        let base64Image = imageData.base64EncodedString()
        let mediaType = imageData.inferredImageMediaType

        let imageBlock: [String: Any] = [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": mediaType,
                "data": base64Image
            ]
        ]

        let textBlock: [String: Any] = [
            "type": "text",
            "text": prompt
        ]

        return [
            "model": Anthropic.model,
            "max_tokens": Anthropic.maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": [imageBlock, textBlock]]
            ]
        ]
    }

    // MARK: - Private: Network

    /// Builds a URLRequest for the Anthropic Messages endpoint.
    private func buildRequest(body: [String: Any], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: Anthropic.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Anthropic.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw CloudAIServiceError.invalidResponse(detail: "Failed to serialise request body: \(error.localizedDescription)")
        }

        return request
    }

    /// Performs the network request with exponential-backoff retry for transient errors.
    private func performRequest(body: [String: Any], apiKey: String) async throws -> String {
        let request = try buildRequest(body: body, apiKey: apiKey)

        var lastError: Error = CloudAIServiceError.serverError(statusCode: 0)

        for attempt in 0..<Anthropic.maxRetries {
            if attempt > 0 {
                let backoff = min(
                    Anthropic.baseBackoffSeconds * pow(2.0, Double(attempt - 1)),
                    Anthropic.maxBackoffSeconds
                )
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CloudAIServiceError.invalidResponse(detail: "No HTTP response received.")
                }

                switch httpResponse.statusCode {
                case 200...299:
                    return try parseResponse(data: data)

                case 429:
                    lastError = CloudAIServiceError.rateLimited
                    // Retry on rate limit

                case 500, 503:
                    lastError = CloudAIServiceError.serverError(statusCode: httpResponse.statusCode)
                    // Retry on transient server error

                default:
                    // Non-retryable HTTP error — throw immediately
                    throw CloudAIServiceError.serverError(statusCode: httpResponse.statusCode)
                }

            } catch let error as CloudAIServiceError {
                // Re-throw non-retryable CloudAIServiceErrors immediately
                switch error {
                case .rateLimited, .serverError:
                    lastError = error
                    // Continue to retry
                default:
                    throw error
                }
            } catch {
                // URLSession transport errors may be transient
                lastError = CloudAIServiceError.networkError(underlying: error.localizedDescription)
            }
        }

        throw lastError
    }

    /// Decodes the Anthropic Messages API JSON response and returns the text content.
    private func parseResponse(data: Data) throws -> String {
        // Anthropic response shape (abbreviated):
        // { "content": [ { "type": "text", "text": "..." } ], ... }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudAIServiceError.invalidResponse(detail: "Response is not valid JSON.")
        }

        guard let contentArray = json["content"] as? [[String: Any]] else {
            throw CloudAIServiceError.invalidResponse(detail: "Missing 'content' array in response.")
        }

        // Collect all text blocks and join them.
        let textParts = contentArray.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }

        guard !textParts.isEmpty else {
            throw CloudAIServiceError.invalidResponse(detail: "No text content blocks found in response.")
        }

        return textParts.joined()
    }
}

// MARK: - Data + Image Media Type

private extension Data {
    /// Heuristically determines the MIME type of raw image data by inspecting
    /// the leading magic bytes.  Falls back to `"image/jpeg"` when unknown.
    var inferredImageMediaType: String {
        var firstByte: UInt8 = 0
        copyBytes(to: &firstByte, count: 1)

        switch firstByte {
        case 0x89:
            return "image/png"     // PNG magic: 0x89 0x50 0x4E 0x47
        case 0xFF:
            return "image/jpeg"    // JPEG magic: 0xFF 0xD8
        case 0x47:
            return "image/gif"     // GIF magic: 0x47 0x49 0x46
        case 0x52:
            return "image/webp"    // RIFF/WebP: 0x52 0x49 0x46 0x46
        default:
            return "image/jpeg"
        }
    }
}
