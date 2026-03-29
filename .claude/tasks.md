---
phase: coding
active-task: NONE
blockers: []
last-agent: review-agent
last-updated: 2026-03-02T17:00:00Z
---

## Tasks

### Phase 1: Project Setup and Core Infrastructure
- [x] TASK-001: Create Xcode project with multi-target structure (iOS, Watch, Widget, Share Extension) ✅ COMPLETED
- [x] TASK-002: Configure SwiftData models with CloudKit sync and App Group shared container ✅ COMPLETED
- [x] TASK-003: Implement Sign in with Apple authentication flow ✅ COMPLETED
- [x] TASK-004: Build Cloud AI API client abstraction (Anthropic only) ✅ COMPLETED
- [x] TASK-005: Set up navigation architecture with adaptive layout (iPhone/iPad/Mac) ✅ COMPLETED
- [x] TASK-006: Create app theme system (colors, typography, dark mode, Dynamic Type) ✅ COMPLETED

### Phase 2: DVG Data Model and CRUD
- [x] TASK-007: Implement DVG SwiftData model with all fields and enum types ✅ COMPLETED
- [x] TASK-008: Implement StoreLocation, Tag, and ScanResult models with relationships ✅ COMPLETED
- [x] TASK-009: Build DVGRepository service with CRUD operations and queries ✅ COMPLETED
- [x] TASK-010: Create DVG detail view (read-only display with barcode rendering) ✅ COMPLETED
- [x] TASK-011: Create DVG form view (quick-add and full edit modes) ✅ COMPLETED

### Phase 3: Email Integration
- [x] TASK-012: Implement Gmail OAuth 2.0 authentication with Keychain token storage ✅ COMPLETED
- [x] TASK-013: Build Gmail API client for fetching emails by label/sender scope ✅ COMPLETED
- [x] TASK-014: Implement email parsing pipeline using Cloud AI service ✅ COMPLETED
- [x] TASK-015: Build email scan UI with progress tracking and scope settings ✅ COMPLETED
- [x] TASK-016: Build review queue UI for low-confidence email extractions ✅ COMPLETED

### Phase 4: Camera Scanning and OCR
- [x] TASK-017: Build camera scanner view with live barcode/QR detection (Vision framework) ✅ COMPLETED
- [x] TASK-018: Implement photo library and PDF document import with barcode extraction ✅ COMPLETED
- [x] TASK-019: Implement Cloud AI vision parsing for text coupons and flyers ✅ COMPLETED
- [x] TASK-020: Build scan results UI with pre-populated DVG creation form ✅ COMPLETED

### Phase 5: Notifications (Expiry + Location)
- [x] TASK-021: Implement expiry notification scheduling with UNUserNotificationCenter ✅ COMPLETED
- [x] TASK-022: Implement notification action handlers (View Code, Mark Used, Snooze) ✅ COMPLETED
- [x] TASK-023: Build geofencing engine with priority ranking and 20-region rotation ✅ COMPLETED
- [x] TASK-024: Implement significant location change monitoring and geofence recalculation ✅ COMPLETED
- [x] TASK-025: Build location permission request flow and background location entitlement ✅ COMPLETED

### Phase 6: UI/UX (Dashboard, Search, Map, Onboarding)
- [x] TASK-026: Build dashboard home screen with Expiring Soon, Nearby, and Recently Added sections ✅ COMPLETED
- [x] TASK-027: Build search view with text search, type/status/tag filters, and smart sorting ✅ COMPLETED
- [x] TASK-028: Build nearby map view with MapKit, store pins, and DVG summary cards ✅ COMPLETED
- [x] TASK-029: Build onboarding flow (3 screens + interactive first-DVG setup) ✅ COMPLETED
- [x] TASK-030: Build settings view with all configuration sections ✅ COMPLETED
- [x] TASK-031: Build history view for used/expired/archived DVGs ✅ COMPLETED
- [x] TASK-032: Build tag management view (create, edit, delete custom tags; view system tags) ✅ COMPLETED

### Phase 7: Platform Extensions (Watch, Widget, Wallet, Share Sheet, Mac Catalyst)
- [x] TASK-033: Build WidgetKit expiring-soon widget (small + medium families) ✅ COMPLETED
- [x] TASK-034: Build Apple Watch app with DVG list and full-screen barcode display ✅ COMPLETED
- [x] TASK-035: Implement Watch Connectivity data transfer from iPhone to Watch ✅ COMPLETED
- [x] TASK-036: Build Apple Wallet pass generation for barcoded DVGs (PassKit) ✅ COMPLETED
- [x] TASK-037: Build Share Sheet extension for importing text, URLs, images, and PDFs ✅ COMPLETED
- [x] TASK-038: Configure Mac Catalyst with menu bar, keyboard shortcuts, and drag-and-drop ✅ COMPLETED

### Phase 8: Monetization (Ads + IAP)
- [x] TASK-039: Integrate Google AdMob with banner and interstitial ad placements ✅ COMPLETED
- [x] TASK-040: Implement StoreKit 2 IAP for "Remove Ads" purchase ✅ COMPLETED
- [x] TASK-041: Build ad-free paywall UI and entitlement gating logic ✅ COMPLETED

### Phase 9: Polish and App Store Prep
- [x] TASK-042: Accessibility audit and remediation (VoiceOver, Dynamic Type, contrast) ✅ COMPLETED
- [x] TASK-043: Localization infrastructure (Localizable.xcstrings, locale-aware formatters) ✅ COMPLETED
- [x] TASK-044: App Store metadata, screenshots, and privacy nutrition labels ✅ COMPLETED
- [x] TASK-045: Comprehensive unit test suite for services and view models ✅ COMPLETED
- [x] TASK-046: UI test suite for critical user flows (add DVG, scan, search) ✅ COMPLETED

### Bug Fixes
- [x] TASK-047: Wire VisionParsingService into ImportViewModel so photo/PDF import uses AI extraction to populate form fields ✅ COMPLETED
- [x] TASK-048: Fix barcode+text import: pass OCR text alongside barcode, separate URL from Code field, make URLs tappable ✅ COMPLETED
- [x] TASK-049: Add "take photo" button to camera scanner for AI text extraction ✅ COMPLETED
