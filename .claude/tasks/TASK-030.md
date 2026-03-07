# TASK-030: Build settings view with all configuration sections

## Description
Build the comprehensive settings view with sections for account, email, notifications, location, AI, appearance, and about. This is the central configuration hub for the app.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-003 (Sign in with Apple status)
- TASK-006 (theme system, appearance manager)
- TASK-012 (Gmail auth status)
- TASK-025 (location permission status)

## Acceptance Criteria
- [ ] Settings organized in `Form` with `Section` groups
- [ ] **Account**: Sign in with Apple status (signed in user info), CloudKit sync status indicator (synced/syncing/error), sign out button
- [ ] **Email**: Gmail connection status, connect/disconnect button, scan scope settings link
- [ ] **Notifications**: Global toggle, expiry notifications toggle, location notifications toggle
- [ ] **Location**: Geofencing enable/disable, default radius slider (100m-1000m), current permission status
- [ ] **AI**: Provider picker (OpenAI/Anthropic), API key entry (secure text field), usage stats (parse count)
- [ ] **Appearance**: Dark mode picker (System/Light/Dark)
- [ ] **About**: App version, privacy policy link, open source licenses link, contact/feedback link
- [ ] **Remove Ads**: "Remove Ads" IAP button (placeholder, implemented in TASK-041)
- [ ] All settings persisted in UserDefaults (except Keychain items)
- [ ] `@Observable` `SettingsViewModel` managing all settings state
- [ ] API key field masked with reveal toggle (SecureField with eye icon)

## Technical Notes
- Use SwiftUI `Form` for native settings look
- CloudKit sync status: observe `NSPersistentCloudKitContainer.Event` notifications or use CKContainer status
- Gmail connection: show email address if connected, "Not Connected" otherwise
- Notification toggles: check `UNUserNotificationCenter.current().getNotificationSettings()` for system-level status; if system denied, show "Enable in Settings" link
- Location permission: show current authorization status and link to system settings if denied
- API key: store in Keychain via `KeychainService`; display masked in UI
- "Restore Purchases" button in the Remove Ads section (for StoreKit 2)
- Privacy policy and licenses can be web links or local HTML files
