import Foundation
import AuthenticationServices

// MARK: - MockAuthenticationService

/// A mock implementation of `AuthenticationService` used for previews and testing.
/// Not included in production builds.
#if DEBUG
@MainActor
final class MockAuthenticationService: AuthenticationService {

    private(set) var isAuthenticated: Bool

    var shouldFailSignIn: Bool = false
    var signInDelay: Duration = .milliseconds(500)

    init(isAuthenticated: Bool = false) {
        self.isAuthenticated = isAuthenticated
    }

    func signIn() async throws {
        try await Task.sleep(for: signInDelay)
        if shouldFailSignIn {
            throw AuthError.invalidCredential
        }
        isAuthenticated = true
    }

    func handleAuthorization(_ result: Result<ASAuthorization, any Error>) async throws {
        switch result {
        case .success:
            isAuthenticated = true
        case .failure(let error):
            throw error
        }
    }

    func signOut() async throws {
        isAuthenticated = false
    }
}
#endif
