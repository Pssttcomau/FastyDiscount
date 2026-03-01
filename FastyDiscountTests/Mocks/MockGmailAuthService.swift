import Foundation
@testable import FastyDiscount

// MARK: - MockGmailAuthService

/// Mock implementation of `GmailAuthService` for unit testing.
final class MockGmailAuthService: GmailAuthService {

    // MARK: - State

    var isAuthenticated: Bool = false

    // MARK: - Recorded Calls

    var authenticateCallCount = 0
    var refreshTokenCallCount = 0
    var getAccessTokenCallCount = 0
    var disconnectCallCount = 0

    // MARK: - Stubbed Responses

    var authenticateError: Error?
    var refreshTokenError: Error?
    var stubbedCredential: String = "mock-credential-value"
    var getAccessTokenError: Error?
    var disconnectError: Error?

    // MARK: - GmailAuthService

    func authenticate() async throws {
        authenticateCallCount += 1
        if let error = authenticateError { throw error }
        isAuthenticated = true
    }

    func refreshToken() async throws {
        refreshTokenCallCount += 1
        if let error = refreshTokenError { throw error }
    }

    func getAccessToken() async throws -> String {
        getAccessTokenCallCount += 1
        if let error = getAccessTokenError { throw error }
        return stubbedCredential
    }

    func disconnect() async throws {
        disconnectCallCount += 1
        if let error = disconnectError { throw error }
        isAuthenticated = false
    }
}
