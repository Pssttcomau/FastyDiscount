import SwiftUI
import AuthenticationServices

// MARK: - AuthViewModel

/// Manages authentication state and drives the auth gate UI.
///
/// Observes Apple's credential-revoked notification to force re-authentication
/// when the user revokes access in Settings > Apple ID > Password & Security.
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - State

    enum State: Equatable {
        case checking
        case unauthenticated
        case authenticated
    }

    // MARK: - Published Properties

    private(set) var state: State = .checking
    var isSigningIn: Bool = false
    var errorMessage: String? = nil
    var hasError: Bool = false

    // MARK: - Private

    private let authService: any AuthenticationService

    // MARK: - Init

    init(authService: any AuthenticationService) {
        self.authService = authService
    }

    // MARK: - Public API

    /// Performs the credential state check on app launch.
    /// Sets `state` to `.authenticated` or `.unauthenticated` after checking.
    func checkCredentialStateOnLaunch() async {
        state = .checking

        // Listen for credential revocation notifications.
        registerForRevocationNotification()

        guard let concreteService = authService as? AppleAuthenticationService else {
            // Fallback: use isAuthenticated property
            await resolveStateFromService()
            return
        }

        await concreteService.checkCredentialState()
        state = concreteService.isAuthenticated ? .authenticated : .unauthenticated
    }

    /// Initiates the Sign in with Apple flow.
    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        hasError = false

        do {
            try await authService.signIn()
            state = .authenticated
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // User canceled — no error message needed
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }

        isSigningIn = false
    }

    /// Signs the user out and transitions to the unauthenticated state.
    func signOut() async {
        do {
            try await authService.signOut()
            state = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    // MARK: - Private Helpers

    private func resolveStateFromService() async {
        state = authService.isAuthenticated ? .authenticated : .unauthenticated
    }

    private func registerForRevocationNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(credentialsRevoked),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
    }

    @objc private func credentialsRevoked() {
        Task { @MainActor in
            try? await self.authService.signOut()
            self.state = .unauthenticated
        }
    }
}
