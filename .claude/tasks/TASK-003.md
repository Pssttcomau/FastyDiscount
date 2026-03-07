# TASK-003: Implement Sign in with Apple authentication flow

## Description
Implement required Sign in with Apple using AuthenticationServices framework. This provides user identity for CloudKit and serves as the app's authentication gate. The user must sign in before accessing any app features.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (project structure)

## Acceptance Criteria
- [ ] `SignInWithAppleButton` presented on launch if user is not authenticated
- [ ] Successful sign-in stores user identifier in Keychain
- [ ] User credential state checked on every app launch via `ASAuthorizationAppleIDProvider.getCredentialState`
- [ ] Revoked credentials handled (force re-authentication)
- [ ] `AuthenticationService` protocol created with `signIn()`, `signOut()`, `isAuthenticated` properties
- [ ] `@Observable` `AuthViewModel` manages auth state and drives UI
- [ ] Sign-in screen follows Apple HIG (centered button, minimal UI)

## Technical Notes
- Use `ASAuthorizationController` for the sign-in flow
- Store `userIdentifier` (the stable user ID) in Keychain, not UserDefaults
- On first sign-in, Apple provides email and name; store these if needed
- Subsequent sign-ins may not return email/name -- only the identifier
- The app should not proceed past the auth gate until sign-in succeeds
- For credential revocation: listen for `ASAuthorizationAppleIDProvider.credentialRevokedNotification`
