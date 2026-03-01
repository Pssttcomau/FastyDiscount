import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

// MARK: - AuthenticationService Protocol

/// Protocol defining the authentication interface used by the app.
/// Marked `@MainActor` since all auth state mutations drive UI updates.
/// Conforming to `Sendable` ensures safe use across concurrency boundaries.
@MainActor
protocol AuthenticationService: AnyObject, Sendable {
    /// Performs Sign in with Apple via an internal ASAuthorizationController.
    /// Throws on failure or cancellation.
    func signIn() async throws

    /// Handles an ASAuthorization result produced by the system SignInWithAppleButton.
    /// Call this from the button's `onCompletion` closure to process the credential.
    func handleAuthorization(_ result: Result<ASAuthorization, any Error>) async throws

    /// Signs the user out, clearing their stored credentials.
    func signOut() async throws

    /// Whether the user is currently authenticated.
    var isAuthenticated: Bool { get }
}

// MARK: - AppleAuthenticationService

/// Concrete implementation of `AuthenticationService` using Sign in with Apple.
///
/// Stores the stable Apple user identifier in the Keychain.
/// Checks credential state on initialization.
@MainActor
final class AppleAuthenticationService: NSObject, AuthenticationService {

    // MARK: - Keys

    private enum KeychainKeys {
        static let userIdentifier = "apple.user.identifier"
        static let userEmail = "apple.user.email"
        static let userFullName = "apple.user.fullName"
    }

    // MARK: - Properties

    private let keychainService: KeychainService
    private var signInContinuation: CheckedContinuation<Void, any Error>?

    private(set) var isAuthenticated: Bool = false

    // MARK: - Init

    init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService
        super.init()
    }

    // MARK: - AuthenticationService

    func signIn() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }

    func handleAuthorization(_ result: Result<ASAuthorization, any Error>) async throws {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.invalidCredential
            }
            // Re-use the shared storeCredential path; it sets isAuthenticated or throws.
            try storeCredentialThrowing(
                userIdentifier: credential.user,
                email: credential.email,
                fullName: credential.fullName
            )
        case .failure(let error):
            throw error
        }
    }

    func signOut() async throws {
        try keychainService.delete(forKey: KeychainKeys.userIdentifier)
        try keychainService.delete(forKey: KeychainKeys.userEmail)
        try keychainService.delete(forKey: KeychainKeys.userFullName)
        isAuthenticated = false
    }

    // MARK: - Credential State Check

    /// Verifies the stored credential state with Apple's servers.
    /// Call this on every app launch to detect revoked credentials.
    func checkCredentialState() async {
        guard let userIdentifier = try? keychainService.read(forKey: KeychainKeys.userIdentifier),
              !userIdentifier.isEmpty else {
            isAuthenticated = false
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userIdentifier)
            switch state {
            case .authorized:
                isAuthenticated = true
            case .revoked, .notFound:
                // Force re-authentication
                try? keychainService.delete(forKey: KeychainKeys.userIdentifier)
                try? keychainService.delete(forKey: KeychainKeys.userEmail)
                try? keychainService.delete(forKey: KeychainKeys.userFullName)
                isAuthenticated = false
            case .transferred:
                // Handle account transfer — treat as needing re-authentication
                isAuthenticated = false
            @unknown default:
                isAuthenticated = false
            }
        } catch {
            // On error, default to not authenticated to be safe
            isAuthenticated = false
        }
    }

    // MARK: - Stored User Info

    /// Returns the stored Apple user identifier, if available.
    var storedUserIdentifier: String? {
        try? keychainService.read(forKey: KeychainKeys.userIdentifier)
    }

    // MARK: - Private Helpers

    /// Throws-based credential storage used by `handleAuthorization`.
    private func storeCredentialThrowing(
        userIdentifier: String,
        email: String?,
        fullName: PersonNameComponents?
    ) throws {
        try keychainService.save(userIdentifier, forKey: KeychainKeys.userIdentifier)

        // Email and name are only returned on first sign-in.
        if let email = email, !email.isEmpty {
            try keychainService.save(email, forKey: KeychainKeys.userEmail)
        }

        if let fullName = fullName {
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: fullName)
            if !name.isEmpty {
                try keychainService.save(name, forKey: KeychainKeys.userFullName)
            }
        }

        isAuthenticated = true
    }

    /// Continuation-based wrapper called from `ASAuthorizationControllerDelegate`.
    private func storeCredential(
        userIdentifier: String,
        email: String?,
        fullName: PersonNameComponents?
    ) {
        do {
            try storeCredentialThrowing(
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
        } catch {
            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthenticationService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                self.signInContinuation?.resume(throwing: AuthError.invalidCredential)
                self.signInContinuation = nil
            }
            return
        }

        let userIdentifier = credential.user
        let email = credential.email
        let fullName = credential.fullName

        Task { @MainActor in
            self.storeCredential(
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
            self.signInContinuation?.resume()
            self.signInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        Task { @MainActor in
            self.signInContinuation?.resume(throwing: error)
            self.signInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthenticationService: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // Find the first foreground-active window scene's key window
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

// MARK: - AuthError

enum AuthError: LocalizedError, Sendable {
    case invalidCredential
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "The sign-in credential was invalid."
        case .keychainError(let message):
            return "Keychain error: \(message)"
        }
    }
}
