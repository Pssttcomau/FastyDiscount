# TASK-012: Implement Gmail OAuth 2.0 authentication with Keychain token storage

## Description
Implement the Gmail OAuth 2.0 sign-in flow using `ASWebAuthenticationSession`. Exchange the authorization code for access and refresh tokens, store them securely in Keychain, and implement automatic token refresh. This provides the auth layer for Gmail API access in subsequent tasks.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (project structure)
- TASK-004 (KeychainService from the AI client task)

## Acceptance Criteria
- [ ] `GmailAuthService` protocol with `authenticate()`, `refreshToken()`, `getAccessToken()`, `disconnect()`, `isAuthenticated` methods
- [ ] OAuth 2.0 flow using `ASWebAuthenticationSession` with Google's authorization endpoint
- [ ] Authorization code exchanged for tokens via Google's token endpoint (POST `https://oauth2.googleapis.com/token`)
- [ ] Access token and refresh token stored in Keychain via `KeychainService`
- [ ] Automatic token refresh when access token expires (check `expires_in`, refresh proactively)
- [ ] Scope: `https://www.googleapis.com/auth/gmail.readonly`
- [ ] Google OAuth client ID stored in project configuration (not hardcoded in source)
- [ ] Error handling: network errors, user cancellation, invalid grant, token revocation
- [ ] `disconnect()` clears tokens from Keychain and revokes token at Google's revocation endpoint
- [ ] All methods are async and throw typed errors (`GmailAuthError`)

## Technical Notes
- Google OAuth requires a registered OAuth client ID; this will need to be configured in Google Cloud Console
- Use `ASWebAuthenticationSession` with `callbackURLScheme` matching the app's reverse client ID
- The redirect URI format: `com.googleusercontent.apps.{CLIENT_ID}:/oauth2redirect`
- Token refresh: POST to `https://oauth2.googleapis.com/token` with `grant_type=refresh_token`
- Token revocation: POST to `https://oauth2.googleapis.com/revoke?token={token}`
- Consider storing the `expires_at` timestamp alongside the access token for proactive refresh
- Use `URLSession` for all HTTP calls -- no third-party auth libraries
