---
phase: coding
active-task: TASK-001
blockers: []
last-agent: code-opus-agent
last-updated: 2026-03-01T00:00:00Z
---

## Tasks

### Phase 1: Project Setup and Core Infrastructure
- [ ] TASK-001: Create Xcode project with multi-target structure (iOS, Watch, Widget, Share Extension)
- [ ] TASK-002: Configure SwiftData models with CloudKit sync and App Group shared container
- [ ] TASK-003: Implement Sign in with Apple authentication flow
- [ ] TASK-004: Build Cloud AI API client abstraction (OpenAI + Anthropic)
- [ ] TASK-005: Set up navigation architecture with adaptive layout (iPhone/iPad/Mac)
- [ ] TASK-006: Create app theme system (colors, typography, dark mode, Dynamic Type)

### Phase 2: DVG Data Model and CRUD
- [ ] TASK-007: Implement DVG SwiftData model with all fields and enum types
- [ ] TASK-008: Implement StoreLocation, Tag, and ScanResult models with relationships
- [ ] TASK-009: Build DVGRepository service with CRUD operations and queries
- [ ] TASK-010: Create DVG detail view (read-only display with barcode rendering)
- [ ] TASK-011: Create DVG form view (quick-add and full edit modes)

### Phase 3: Email Integration
- [ ] TASK-012: Implement Gmail OAuth 2.0 authentication with Keychain token storage
- [ ] TASK-013: Build Gmail API client for fetching emails by label/sender scope
- [ ] TASK-014: Implement email parsing pipeline using Cloud AI service
- [ ] TASK-015: Build email scan UI with progress tracking and scope settings
- [ ] TASK-016: Build review queue UI for low-confidence email extractions

### Phase 4: Camera Scanning and OCR
- [ ] TASK-017: Build camera scanner view with live barcode/QR detection (Vision framework)
- [ ] TASK-018: Implement photo library and PDF document import with barcode extraction
- [ ] TASK-019: Implement Cloud AI vision parsing for text coupons and flyers
- [ ] TASK-020: Build scan results UI with pre-populated DVG creation form

### Phase 5: Notifications (Expiry + Location)
- [ ] TASK-021: Implement expiry notification scheduling with UNUserNotificationCenter
- [ ] TASK-022: Implement notification action handlers (View Code, Mark Used, Snooze)
- [ ] TASK-023: Build geofencing engine with priority ranking and 20-region rotation
- [ ] TASK-024: Implement significant location change monitoring and geofence recalculation
- [ ] TASK-025: Build location permission request flow and background location entitlement

### Phase 6: UI/UX (Dashboard, Search, Map, Onboarding)
- [ ] TASK-026: Build dashboard home screen with Expiring Soon, Nearby, and Recently Added sections
- [ ] TASK-027: Build search view with text search, type/status/tag filters, and smart sorting
- [ ] TASK-028: Build nearby map view with MapKit, store pins, and DVG summary cards
- [ ] TASK-029: Build onboarding flow (3 screens + interactive first-DVG setup)
- [ ] TASK-030: Build settings view with all configuration sections
- [ ] TASK-031: Build history view for used/expired/archived DVGs
- [ ] TASK-032: Build tag management view (create, edit, delete custom tags; view system tags)

### Phase 7: Platform Extensions (Watch, Widget, Wallet, Share Sheet, Mac Catalyst)
- [ ] TASK-033: Build WidgetKit expiring-soon widget (small + medium families)
- [ ] TASK-034: Build Apple Watch app with DVG list and full-screen barcode display
- [ ] TASK-035: Implement Watch Connectivity data transfer from iPhone to Watch
- [ ] TASK-036: Build Apple Wallet pass generation for barcoded DVGs (PassKit)
- [ ] TASK-037: Build Share Sheet extension for importing text, URLs, images, and PDFs
- [ ] TASK-038: Configure Mac Catalyst with menu bar, keyboard shortcuts, and drag-and-drop

### Phase 8: Monetization (Ads + IAP)
- [ ] TASK-039: Integrate Google AdMob with banner and interstitial ad placements
- [ ] TASK-040: Implement StoreKit 2 IAP for "Remove Ads" purchase
- [ ] TASK-041: Build ad-free paywall UI and entitlement gating logic

### Phase 9: Polish and App Store Prep
- [ ] TASK-042: Accessibility audit and remediation (VoiceOver, Dynamic Type, contrast)
- [ ] TASK-043: Localization infrastructure (Localizable.xcstrings, locale-aware formatters)
- [ ] TASK-044: App Store metadata, screenshots, and privacy nutrition labels
- [ ] TASK-045: Comprehensive unit test suite for services and view models
- [ ] TASK-046: UI test suite for critical user flows (add DVG, scan, search)
