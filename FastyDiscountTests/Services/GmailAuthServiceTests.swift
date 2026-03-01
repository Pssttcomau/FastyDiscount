import Testing
import Foundation
@testable import FastyDiscount

// MARK: - GmailAuthServiceTests

@Suite("GmailAuthService Tests")
struct GmailAuthServiceTests {

    // MARK: - Authentication State

    @Test("test_isAuthenticated_noToken_returnsFalse")
    func test_isAuthenticated_noToken_returnsFalse() {
        let mock = MockGmailAuthService()
        #expect(mock.isAuthenticated == false)
    }

    @Test("test_isAuthenticated_afterAuthenticate_returnsTrue")
    func test_isAuthenticated_afterAuthenticate_returnsTrue() async throws {
        let mock = MockGmailAuthService()
        try await mock.authenticate()
        #expect(mock.isAuthenticated == true)
    }

    // MARK: - Token Refresh

    @Test("test_refreshToken_callsRefreshOnce")
    func test_refreshToken_callsRefreshOnce() async throws {
        let mock = MockGmailAuthService()
        try await mock.refreshToken()
        #expect(mock.refreshTokenCallCount == 1)
    }

    @Test("test_refreshToken_error_throws")
    func test_refreshToken_error_throws() async {
        let mock = MockGmailAuthService()
        mock.refreshTokenError = GmailAuthError.invalidGrant

        do {
            try await mock.refreshToken()
            Issue.record("Expected error")
        } catch let error as GmailAuthError {
            if case .invalidGrant = error {
                // expected
            } else {
                Issue.record("Wrong error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - Access Token

    @Test("test_getAccessToken_returnsToken")
    func test_getAccessToken_returnsToken() async throws {
        let mock = MockGmailAuthService()
        mock.stubbedCredential = "mock-credential-value"

        let credential = try await mock.getAccessToken()

        #expect(credential == "mock-credential-value")
        #expect(mock.getAccessTokenCallCount == 1)
    }

    @Test("test_getAccessToken_error_throwsNotAuthenticated")
    func test_getAccessToken_error_throwsNotAuthenticated() async {
        let mock = MockGmailAuthService()
        mock.getAccessTokenError = GmailAuthError.notAuthenticated

        do {
            _ = try await mock.getAccessToken()
            Issue.record("Expected error")
        } catch let error as GmailAuthError {
            if case .notAuthenticated = error {
                // expected
            } else {
                Issue.record("Wrong error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - Revocation / Disconnect

    @Test("test_disconnect_clearsAuthentication")
    func test_disconnect_clearsAuthentication() async throws {
        let mock = MockGmailAuthService()
        mock.isAuthenticated = true

        try await mock.disconnect()

        #expect(mock.isAuthenticated == false)
        #expect(mock.disconnectCallCount == 1)
    }

    @Test("test_disconnect_error_throws")
    func test_disconnect_error_throws() async {
        let mock = MockGmailAuthService()
        mock.isAuthenticated = true
        mock.disconnectError = GmailAuthError.networkError(underlying: "timeout")

        do {
            try await mock.disconnect()
            Issue.record("Expected error")
        } catch let error as GmailAuthError {
            if case .networkError = error {
                // expected
            } else {
                Issue.record("Wrong error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - GmailAuthError Tests

    @Test("test_gmailAuthError_descriptions_notEmpty")
    func test_gmailAuthError_descriptions_notEmpty() {
        let errors: [GmailAuthError] = [
            .missingClientID,
            .userCancelled,
            .authorizationFailed(detail: "test"),
            .networkError(underlying: "timeout"),
            .invalidTokenResponse(detail: "bad response"),
            .invalidGrant,
            .tokenRevoked,
            .keychainError(underlying: "access denied"),
            .notAuthenticated
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("test_gmailAuthError_missingClientID_containsMessage")
    func test_gmailAuthError_missingClientID_containsMessage() {
        let error = GmailAuthError.missingClientID
        #expect(error.errorDescription?.contains("client ID") == true)
    }
}
