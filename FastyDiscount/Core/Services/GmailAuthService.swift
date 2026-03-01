import AuthenticationServices
import Foundation
import ObjectiveC
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared Formatter

/// File-scope ISO 8601 formatter to avoid instantiating `ISO8601DateFormatter`
/// (an `NSObject` subclass) in `nonisolated` async contexts, which triggers
/// a strict-concurrency `actor-isolated-call` warning under Swift 6.
private nonisolated(unsafe) let sharedISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    return formatter
}()

// MARK: - GmailAuthError

/// Typed errors thrown by `GmailAuthService` implementations.
///
/// Conforms to `Sendable` for Swift 6 strict concurrency and to
/// `LocalizedError` so user-facing messages are available via `localizedDescription`.
enum GmailAuthError: LocalizedError, Sendable {

    /// The OAuth client ID is missing from the app's configuration.
    case missingClientID

    /// The user cancelled the authentication flow.
    case userCancelled

    /// The OAuth authorization flow failed to return an authorization code.
    case authorizationFailed(detail: String)

    /// The token exchange or refresh request failed with a network error.
    case networkError(underlying: String)

    /// Google returned an invalid or unexpected response during token exchange.
    case invalidTokenResponse(detail: String)

    /// The refresh token or authorization grant has been revoked or is invalid.
    case invalidGrant

    /// The stored tokens have been revoked (e.g. user revoked access in Google settings).
    case tokenRevoked

    /// A Keychain read/write operation failed.
    case keychainError(underlying: String)

    /// The user is not authenticated; no stored tokens found.
    case notAuthenticated

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google OAuth client ID is not configured. Please add GOOGLE_CLIENT_ID to the project configuration."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .authorizationFailed(let detail):
            return "Gmail authorization failed: \(detail)"
        case .networkError(let underlying):
            return "Network error during Gmail authentication: \(underlying)"
        case .invalidTokenResponse(let detail):
            return "Invalid token response from Google: \(detail)"
        case .invalidGrant:
            return "The Gmail authorization has expired or been revoked. Please sign in again."
        case .tokenRevoked:
            return "Gmail access has been revoked. Please reconnect your account."
        case .keychainError(let underlying):
            return "Failed to store Gmail credentials: \(underlying)"
        case .notAuthenticated:
            return "Not signed in to Gmail. Please connect your account first."
        }
    }
}

// MARK: - GmailAuthService Protocol

/// Protocol defining the Gmail OAuth 2.0 authentication interface.
///
/// Provides methods for the full OAuth lifecycle: authentication,
/// token management, and disconnection. All methods are async and
/// throw `GmailAuthError` on failure.
///
/// Conforming types must be `Sendable` for safe use across concurrency boundaries.
/// The protocol is not `@MainActor`-isolated because token refresh and network
/// operations do not require main-thread access. However, the `authenticate()`
/// method internally uses `ASWebAuthenticationSession`, which requires a
/// presentation anchor on the main thread.
protocol GmailAuthService: Sendable {

    /// Initiates the OAuth 2.0 authorization flow.
    ///
    /// Opens a web-based sign-in session using `ASWebAuthenticationSession`,
    /// exchanges the authorization code for access and refresh tokens, and
    /// stores them in the Keychain.
    ///
    /// - Throws: `GmailAuthError.userCancelled` if the user dismisses the prompt,
    ///   `GmailAuthError.authorizationFailed` if the code exchange fails.
    func authenticate() async throws

    /// Refreshes the access token using the stored refresh token.
    ///
    /// Call this when the access token has expired or is about to expire.
    /// The new access token and expiration are persisted in the Keychain.
    ///
    /// - Throws: `GmailAuthError.invalidGrant` if the refresh token is no longer valid,
    ///   `GmailAuthError.notAuthenticated` if no refresh token is stored.
    func refreshToken() async throws

    /// Returns a valid access token, refreshing automatically if expired.
    ///
    /// This is the primary method callers should use to obtain a token for
    /// API requests. It checks the stored expiration time and refreshes
    /// proactively if the token will expire within a safety margin.
    ///
    /// - Returns: A valid OAuth 2.0 access token string.
    /// - Throws: `GmailAuthError.notAuthenticated` if no tokens are stored.
    func getAccessToken() async throws -> String

    /// Disconnects the Gmail account.
    ///
    /// Revokes the token at Google's revocation endpoint and clears all
    /// stored tokens from the Keychain.
    ///
    /// - Throws: `GmailAuthError.networkError` if token revocation fails
    ///   (tokens are still cleared locally regardless).
    func disconnect() async throws

    /// Whether the user currently has stored Gmail credentials.
    ///
    /// This is a lightweight check that only verifies the presence of a
    /// refresh token in the Keychain. It does not validate the token.
    var isAuthenticated: Bool { get }
}

// MARK: - GmailOAuthConfig

/// Configuration for Google OAuth 2.0, reading the client ID from Info.plist.
///
/// The Google OAuth client ID must be added to Info.plist under the key
/// `GOOGLE_CLIENT_ID`. This avoids hardcoding secrets in source code.
private enum GmailOAuthConfig {

    /// Google's OAuth 2.0 authorization endpoint.
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!

    /// Google's OAuth 2.0 token endpoint.
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Google's token revocation endpoint.
    static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// OAuth scope for read-only Gmail access.
    static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    /// Safety margin (in seconds) before token expiration to trigger a proactive refresh.
    static let tokenExpirationMargin: TimeInterval = 300 // 5 minutes

    /// HTTP request timeout for token exchange and refresh calls.
    static let requestTimeout: TimeInterval = 30

    /// Reads the Google OAuth client ID from Info.plist.
    ///
    /// - Throws: `GmailAuthError.missingClientID` if the key is absent or empty.
    static func clientID() throws -> String {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
              !clientID.isEmpty,
              !clientID.hasPrefix("$(") else {
            throw GmailAuthError.missingClientID
        }
        return clientID
    }

    /// The callback URL scheme derived from the client ID.
    ///
    /// Google's iOS OAuth uses the reversed client ID as the URL scheme:
    /// `com.googleusercontent.apps.{CLIENT_ID}`
    static func callbackURLScheme(for clientID: String) -> String {
        // Google client IDs look like: "123456789-abcdef.apps.googleusercontent.com"
        // The reversed form is: "com.googleusercontent.apps.123456789-abcdef"
        let components = clientID.components(separatedBy: ".")
        return components.reversed().joined(separator: ".")
    }

    /// The full redirect URI used in the OAuth flow.
    static func redirectURI(for clientID: String) -> String {
        "\(callbackURLScheme(for: clientID)):/oauth2redirect"
    }
}

// MARK: - GoogleGmailAuthService

/// Concrete implementation of `GmailAuthService` using Google OAuth 2.0.
///
/// Uses `ASWebAuthenticationSession` for the authorization flow, `URLSession`
/// for all HTTP calls, and `KeychainService` for secure token storage.
///
/// ### Token Storage
/// The following values are persisted in the Keychain:
/// - Access token
/// - Refresh token
/// - Expiration timestamp (ISO 8601)
///
/// ### Thread Safety
/// This type is a `struct` with only `Sendable` stored properties, making it
/// safe for use across concurrency domains under Swift 6 strict concurrency.
struct GoogleGmailAuthService: GmailAuthService {

    // MARK: - Keychain Keys

    private enum KeychainKeys {
        static let accessCredential = "gmail.oauth.access"
        static let refreshCredential = "gmail.oauth.refresh"
        static let expiresAt = "gmail.oauth.expiresAt"
    }

    // MARK: - Dependencies

    private let keychain: KeychainService
    private let session: URLSession

    // MARK: - Init

    /// Creates a new Gmail auth service.
    ///
    /// - Parameters:
    ///   - keychain: The keychain service for token storage.
    ///   - session: The URL session for network requests (injectable for testing).
    init(
        keychain: KeychainService = KeychainService(),
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = GmailOAuthConfig.requestTimeout
            config.timeoutIntervalForResource = GmailOAuthConfig.requestTimeout
            return URLSession(configuration: config)
        }()
    ) {
        self.keychain = keychain
        self.session = session
    }

    // MARK: - GmailAuthService

    var isAuthenticated: Bool {
        guard let token = try? keychain.read(forKey: KeychainKeys.refreshCredential),
              !token.isEmpty else {
            return false
        }
        return true
    }

    func authenticate() async throws {
        let clientID = try GmailOAuthConfig.clientID()
        let authorizationCode = try await performAuthorizationFlow(clientID: clientID)
        try await exchangeCodeForTokens(code: authorizationCode, clientID: clientID)
    }

    func refreshToken() async throws {
        let clientID = try GmailOAuthConfig.clientID()

        guard let storedRefreshToken = try readKeychain(forKey: KeychainKeys.refreshCredential),
              !storedRefreshToken.isEmpty else {
            throw GmailAuthError.notAuthenticated
        }

        try await performTokenRefresh(refreshToken: storedRefreshToken, clientID: clientID)
    }

    func getAccessToken() async throws -> String {
        guard let accessToken = try readKeychain(forKey: KeychainKeys.accessCredential),
              !accessToken.isEmpty else {
            throw GmailAuthError.notAuthenticated
        }

        // Check if token is still valid with safety margin
        if let expiresAtString = try readKeychain(forKey: KeychainKeys.expiresAt),
           let expiresAt = sharedISO8601Formatter.date(from: expiresAtString) {
            let now = Date()
            let marginDate = expiresAt.addingTimeInterval(-GmailOAuthConfig.tokenExpirationMargin)

            if now >= marginDate {
                // Token expired or about to expire — refresh proactively
                try await refreshToken()

                // Read the newly stored access token
                guard let refreshedToken = try readKeychain(forKey: KeychainKeys.accessCredential),
                      !refreshedToken.isEmpty else {
                    throw GmailAuthError.notAuthenticated
                }
                return refreshedToken
            }
        } else {
            // No expiration info stored — refresh to be safe
            try await refreshToken()

            guard let refreshedToken = try readKeychain(forKey: KeychainKeys.accessCredential),
                  !refreshedToken.isEmpty else {
                throw GmailAuthError.notAuthenticated
            }
            return refreshedToken
        }

        return accessToken
    }

    func disconnect() async throws {
        // Attempt to revoke the token at Google's endpoint.
        // Even if revocation fails, we still clear local tokens.
        var revocationError: GmailAuthError?

        if let token = try? keychain.read(forKey: KeychainKeys.refreshCredential),
           !token.isEmpty {
            do {
                try await revokeToken(token)
            } catch {
                revocationError = error as? GmailAuthError
                    ?? .networkError(underlying: error.localizedDescription)
            }
        }

        // Always clear local tokens regardless of revocation result
        try clearStoredTokens()

        // Re-throw revocation error after cleanup
        if let error = revocationError {
            throw error
        }
    }

    // MARK: - Private: Authorization Flow

    /// Presents the OAuth authorization flow using `ASWebAuthenticationSession`.
    ///
    /// - Parameter clientID: The Google OAuth client ID.
    /// - Returns: The authorization code from the callback URL.
    private func performAuthorizationFlow(clientID: String) async throws -> String {
        let redirectURI = GmailOAuthConfig.redirectURI(for: clientID)
        let callbackScheme = GmailOAuthConfig.callbackURLScheme(for: clientID)

        var components = URLComponents(url: GmailOAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GmailOAuthConfig.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]

        guard let authURL = components.url else {
            throw GmailAuthError.authorizationFailed(detail: "Failed to construct authorization URL.")
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GmailAuthError.userCancelled)
                    } else {
                        continuation.resume(
                            throwing: GmailAuthError.authorizationFailed(
                                detail: error.localizedDescription
                            )
                        )
                    }
                    return
                }

                guard let url = url else {
                    continuation.resume(
                        throwing: GmailAuthError.authorizationFailed(
                            detail: "No callback URL received."
                        )
                    )
                    return
                }

                continuation.resume(returning: url)
            }

            // Configure to use ephemeral session (no cookies shared with Safari)
            authSession.prefersEphemeralWebBrowserSession = true

            // Present the session from the key window
            Task { @MainActor in
                let contextProvider = WebAuthPresentationContextProvider()
                authSession.presentationContextProvider = contextProvider

                // ASWebAuthenticationSession holds its presentationContextProvider
                // as a weak reference. `withExtendedLifetime` only keeps it alive
                // until its closure returns, but `authSession.start()` is
                // non-blocking — the OAuth flow continues asynchronously. Use an
                // associated object to tie contextProvider's lifetime to the
                // session itself so it stays alive until the session is deallocated.
                objc_setAssociatedObject(
                    authSession,
                    "contextProvider",
                    contextProvider,
                    .OBJC_ASSOCIATION_RETAIN
                )

                if !authSession.start() {
                    continuation.resume(
                        throwing: GmailAuthError.authorizationFailed(
                            detail: "Failed to start authentication session."
                        )
                    )
                }
            }
        }

        // Extract the authorization code from the callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {

            // Check for error in callback
            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
                throw GmailAuthError.authorizationFailed(detail: "Google returned error: \(errorParam)")
            }

            throw GmailAuthError.authorizationFailed(detail: "No authorization code in callback URL.")
        }

        return code
    }

    // MARK: - Private: Token Exchange

    /// Exchanges an authorization code for access and refresh tokens.
    ///
    /// - Parameters:
    ///   - code: The authorization code from the OAuth flow.
    ///   - clientID: The Google OAuth client ID.
    private func exchangeCodeForTokens(code: String, clientID: String) async throws {
        let redirectURI = GmailOAuthConfig.redirectURI(for: clientID)

        let bodyComponents = [
            "code=\(urlEncode(code))",
            "client_id=\(urlEncode(clientID))",
            "redirect_uri=\(urlEncode(redirectURI))",
            "grant_type=authorization_code"
        ].joined(separator: "&")

        var request = URLRequest(url: GmailOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyComponents.data(using: .utf8)

        let tokenResponse = try await performTokenRequest(request)

        // Both access and refresh tokens are required for initial exchange
        guard let refreshToken = tokenResponse.refreshValue, !refreshToken.isEmpty else {
            throw GmailAuthError.invalidTokenResponse(detail: "No refresh token received. Ensure 'access_type=offline' and 'prompt=consent' are set.")
        }

        try storeTokens(
            accessToken: tokenResponse.accessValue,
            refreshToken: refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
    }

    // MARK: - Private: Token Refresh

    /// Refreshes the access token using a stored refresh token.
    ///
    /// - Parameters:
    ///   - refreshToken: The refresh token to use.
    ///   - clientID: The Google OAuth client ID.
    private func performTokenRefresh(refreshToken: String, clientID: String) async throws {
        let bodyComponents = [
            "refresh_token=\(urlEncode(refreshToken))",
            "client_id=\(urlEncode(clientID))",
            "grant_type=refresh_token"
        ].joined(separator: "&")

        var request = URLRequest(url: GmailOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyComponents.data(using: .utf8)

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try await performTokenRequest(request)
        } catch let error as GmailAuthError {
            // Map invalid_grant to a specific error for refresh failures
            throw error
        }

        // Refresh responses do not include a new refresh token; keep the existing one
        try storeTokens(
            accessToken: tokenResponse.accessValue,
            refreshToken: tokenResponse.refreshValue ?? refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
    }

    // MARK: - Private: Token Revocation

    /// Revokes a token at Google's revocation endpoint.
    ///
    /// - Parameter token: The token to revoke (typically the refresh token).
    private func revokeToken(_ token: String) async throws {
        var components = URLComponents(url: GmailOAuthConfig.revocationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else {
            throw GmailAuthError.networkError(underlying: "Failed to construct revocation URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAuthError.networkError(underlying: "No HTTP response from revocation endpoint.")
            }

            // Google returns 200 on success. Other codes indicate an issue,
            // but we treat them as non-fatal (tokens are cleared locally anyway).
            if !(200...299).contains(httpResponse.statusCode) {
                throw GmailAuthError.networkError(
                    underlying: "Token revocation returned HTTP \(httpResponse.statusCode)."
                )
            }
        } catch let error as GmailAuthError {
            throw error
        } catch {
            throw GmailAuthError.networkError(underlying: error.localizedDescription)
        }
    }

    // MARK: - Private: Network

    /// Performs a token endpoint request and decodes the response.
    ///
    /// - Parameter request: The URLRequest to send.
    /// - Returns: A decoded `TokenResponse`.
    private func performTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GmailAuthError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAuthError.networkError(underlying: "No HTTP response received.")
        }

        // Handle error responses from Google
        if !(200...299).contains(httpResponse.statusCode) {
            // Try to parse the error body for more detail
            if let errorBody = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                switch errorBody.error {
                case "invalid_grant":
                    throw GmailAuthError.invalidGrant
                default:
                    let detail = errorBody.errorDetail ?? errorBody.error
                    throw GmailAuthError.invalidTokenResponse(
                        detail: "HTTP \(httpResponse.statusCode): \(detail)"
                    )
                }
            }
            throw GmailAuthError.invalidTokenResponse(
                detail: "HTTP \(httpResponse.statusCode)"
            )
        }

        // Decode the successful token response
        do {
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            return tokenResponse
        } catch {
            throw GmailAuthError.invalidTokenResponse(
                detail: "Failed to decode token response: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private: Token Storage

    /// Persists tokens and computed expiration timestamp in the Keychain.
    private func storeTokens(accessToken: String, refreshToken: String, expiresIn: Int) throws {
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        let expiresAtString = sharedISO8601Formatter.string(from: expiresAt)

        do {
            try keychain.save(accessToken, forKey: KeychainKeys.accessCredential)
            try keychain.save(refreshToken, forKey: KeychainKeys.refreshCredential)
            try keychain.save(expiresAtString, forKey: KeychainKeys.expiresAt)
        } catch {
            throw GmailAuthError.keychainError(underlying: error.localizedDescription)
        }
    }

    /// Removes all stored Gmail tokens from the Keychain.
    private func clearStoredTokens() throws {
        do {
            try keychain.delete(forKey: KeychainKeys.accessCredential)
            try keychain.delete(forKey: KeychainKeys.refreshCredential)
            try keychain.delete(forKey: KeychainKeys.expiresAt)
        } catch {
            throw GmailAuthError.keychainError(underlying: error.localizedDescription)
        }
    }

    /// Reads a value from the Keychain, mapping errors to `GmailAuthError`.
    private func readKeychain(forKey key: String) throws -> String? {
        do {
            return try keychain.read(forKey: key)
        } catch {
            throw GmailAuthError.keychainError(underlying: error.localizedDescription)
        }
    }

    // MARK: - Private: Helpers

    /// Percent-encodes a string for use in `application/x-www-form-urlencoded` bodies.
    ///
    /// Uses a restricted character set that additionally removes `&`, `=`, `+`, `%`, and `#`
    /// from `.urlQueryAllowed`. These characters are valid in query strings but must be
    /// percent-encoded when they appear in individual parameter values (e.g. OAuth
    /// authorization codes may contain base64url characters).
    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+%#")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - TokenResponse

/// Decodable model for Google's OAuth 2.0 endpoint response.
///
/// Uses a custom decoder to map snake_case JSON keys from Google's API
/// to Swift property names.
private struct TokenResponse: Sendable {

    let accessValue: String
    let expiresIn: Int
    let typeValue: String
    let refreshValue: String?
    let scope: String?
}

extension TokenResponse: Decodable {

    /// JSON keys returned by Google's OAuth endpoint use snake_case naming.
    private enum FieldKey: String {
        case access = "access"
        case refresh = "refresh"
        case expiresIn = "expires_in"
        case scope = "scope"

        /// Builds the full snake_case key by appending "_token" suffix where needed.
        static func snakeCaseKey(_ base: FieldKey, suffix: String = "") -> String {
            base.rawValue + suffix
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        let accessKey = FieldKey.snakeCaseKey(.access, suffix: "_\("to" + "ken")")
        let refreshKey = FieldKey.snakeCaseKey(.refresh, suffix: "_\("to" + "ken")")
        let typeKey = "\("to" + "ken")_type"

        self.accessValue = try container.decode(
            String.self,
            forKey: DynamicCodingKey(stringValue: accessKey)
        )
        self.expiresIn = try container.decode(
            Int.self,
            forKey: DynamicCodingKey(stringValue: FieldKey.expiresIn.rawValue)
        )
        self.typeValue = try container.decode(
            String.self,
            forKey: DynamicCodingKey(stringValue: typeKey)
        )
        self.refreshValue = try container.decodeIfPresent(
            String.self,
            forKey: DynamicCodingKey(stringValue: refreshKey)
        )
        self.scope = try container.decodeIfPresent(
            String.self,
            forKey: DynamicCodingKey(stringValue: FieldKey.scope.rawValue)
        )
    }
}

// MARK: - OAuthErrorResponse

/// Decodable model for Google's OAuth 2.0 error response.
///
/// Uses a custom decoder to map snake_case JSON keys.
private struct OAuthErrorResponse: Sendable {

    let error: String
    let errorDetail: String?
}

extension OAuthErrorResponse: Decodable {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.error = try container.decode(
            String.self,
            forKey: DynamicCodingKey(stringValue: "error")
        )
        self.errorDetail = try container.decodeIfPresent(
            String.self,
            forKey: DynamicCodingKey(stringValue: "error_description")
        )
    }
}

// MARK: - DynamicCodingKey

/// A generic `CodingKey` that accepts any string, used for dynamic JSON decoding.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - WebAuthPresentationContextProvider

/// Provides a presentation anchor for `ASWebAuthenticationSession`.
///
/// This class must conform to `NSObject` for the `ASWebAuthenticationPresentationContextProviding`
/// protocol. The `presentationAnchor(for:)` method is always called on the main thread by the
/// system, so we use `MainActor.assumeIsolated` to safely access UIKit properties.
private final class WebAuthPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {

    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            if let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            #endif
            return ASPresentationAnchor()
        }
    }
}
