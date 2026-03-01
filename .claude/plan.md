# FastyDiscount -- Architecture Plan

**Status**: Planning complete -- ready for implementation
**Platform**: iOS 19+ / Swift 6 / SwiftUI / SwiftData
**Architecture**: MVVM with @Observable
**Last Updated**: 2026-02-24

---

## Goals

FastyDiscount is a native Apple-ecosystem app for managing discount codes, vouchers, gift cards, loyalty points, and barcoded coupons (collectively "DVGs"). The app imports DVGs from email (Gmail + Apple Mail), camera/photo scanning with cloud AI OCR, and manual entry. It alerts users when DVGs are expiring and when they are near relevant stores. It syncs across iPhone, iPad, Mac Catalyst, and Apple Watch via iCloud/CloudKit.

**Primary user**: A single person who accumulates DVGs from shopping, emails, and promotions and wants to never forget or waste them.

**Monetization**: Free with ads; paid IAP to remove ads.

---

## Architecture Overview

- **UI Layer**: SwiftUI views with adaptive layouts (iPhone / iPad / Mac Catalyst)
- **ViewModel Layer**: @Observable classes, @MainActor, Swift 6 strict concurrency
- **Data Layer**: SwiftData models with CloudKit sync (iCloud container from day one)
- **Services Layer**: Protocol-based service abstractions for AI API, Gmail API, location, notifications
- **Extensions**: WidgetKit widget, WatchKit app, Share Sheet extension, Apple Wallet pass generation
- **Cloud AI**: Single API client abstraction used by both email parsing and vision OCR (OpenAI / Anthropic)
- **Auth**: Sign in with Apple required (provides CloudKit identity)

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI (iOS 19+) |
| Persistence | SwiftData + CloudKit |
| Networking | URLSession (async/await) |
| Barcode scanning | Apple Vision (VNDetectBarcodesRequest) |
| OCR | Apple Vision (VNRecognizeTextRequest) + Cloud AI for smart extraction |
| Email (Gmail) | Gmail REST API via OAuth 2.0 |
| Email (Apple Mail) | Apple MessageUI / native integration |
| Maps | MapKit |
| Location | CoreLocation (geofencing + significant location changes) |
| Notifications | UserNotifications + UNNotificationAction |
| Watch | WatchKit + Watch Connectivity |
| Widgets | WidgetKit |
| Wallet | PassKit |
| Ads | AdMob (Google Mobile Ads SDK) |
| IAP | StoreKit 2 |
| Auth | AuthenticationServices (Sign in with Apple) |

---

## Project Structure

```
FastyDiscount/
├── FastyDiscount/                    # Main iOS app target
│   ├── App/
│   │   ├── FastyDiscountApp.swift
│   │   ├── AppState.swift
│   │   └── AppConstants.swift
│   ├── Features/
│   │   ├── Onboarding/
│   │   ├── Dashboard/
│   │   ├── DVGDetail/
│   │   ├── DVGForm/
│   │   ├── EmailImport/
│   │   ├── Scanner/
│   │   ├── NearbyMap/
│   │   ├── Search/
│   │   ├── Settings/
│   │   └── History/
│   ├── Core/
│   │   ├── Models/                   # SwiftData @Model classes
│   │   ├── Services/                 # API clients, location, notifications
│   │   ├── Navigation/               # NavigationPath + Destination enum
│   │   ├── Extensions/
│   │   ├── Utilities/
│   │   └── Theme/                    # Colors, typography, adaptive layout
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Localizable.xcstrings
│       └── Info.plist
├── FastyDiscountWatch/               # watchOS app target
├── FastyDiscountWatchExtension/      # Watch extension
├── FastyDiscountWidget/              # WidgetKit target
├── FastyDiscountShareExtension/      # Share Sheet extension
├── FastyDiscountTests/               # Unit tests
├── FastyDiscountUITests/             # UI tests
└── Package.swift (or .xcodeproj)
```

---

## Phases Overview

| Phase | Name | Tasks | Milestone |
|-------|------|-------|-----------|
| 1 | Project Setup and Core Infrastructure | 6 | Xcode project builds, SwiftData + CloudKit configured, AI client ready |
| 2 | DVG Data Model and CRUD | 5 | Can create, read, update, delete DVGs with full field set |
| 3 | Email Integration | 5 | Gmail OAuth + Apple Mail scan, cloud AI parsing, review queue |
| 4 | Camera Scanning and OCR | 4 | Camera/photo/PDF scanning with barcode + AI-powered OCR |
| 5 | Notifications (Expiry + Location) | 5 | Expiry alerts with actions, geofencing engine, background location |
| 6 | UI/UX (Dashboard, Search, Map, Onboarding) | 7 | Full dashboard, search/filter, nearby map, onboarding, settings |
| 7 | Platform Extensions | 6 | Watch app, widget, Apple Wallet, Share Sheet, Mac Catalyst, iPad |
| 8 | Monetization | 3 | AdMob integration, StoreKit 2 IAP, paywall |
| 9 | Polish and App Store Prep | 5 | Accessibility, localization prep, App Store assets, final QA |

**Total**: 46 tasks

---

## Key Architectural Decisions

1. **iCloud from day one**: SwiftData models use CloudKit-compatible types only (no optionals on relationships without careful handling, no unique constraints, use soft-delete patterns). This is the single most impactful decision -- it constrains the data model.
2. **Cloud AI only for parsing**: No on-device ML fallback. Email and OCR parsing require network. Graceful degradation shows raw text when offline.
3. **Single AI API client**: One `CloudAIService` protocol used by both email parsing and vision OCR, supporting OpenAI and Anthropic backends.
4. **Geofence rotation**: iOS limits to 20 geofences. Top 20 by expiry proximity are geofenced; remaining use significant-location-change monitoring.
5. **Adaptive layout from start**: Use `NavigationSplitView` for iPad/Mac, `NavigationStack` for iPhone, with `horizontalSizeClass` switching.
6. **Share data via App Groups**: Main app, widget, share extension, and watch app share data through App Groups and the same SwiftData container.

---

## Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| CloudKit sync conflicts with SwiftData | High | Medium | Use server-wins merge policy; design idempotent operations |
| Gmail API OAuth App Review | Medium | High | Submit for Google verification early; use restricted scopes |
| Cloud AI API costs per parse | Medium | Medium | Cache results; batch email parsing; set user-facing usage limits |
| 20-geofence iOS limit | Low | Certain | Rotation algorithm based on proximity + expiry; significant-location fallback |
| App Store rejection (background location) | High | Medium | Justify with clear user benefit; provide settings to disable; follow Apple guidelines precisely |
| Mac Catalyst UI gaps | Low | Medium | Defer complex Catalyst-specific adjustments to Phase 7; prioritize iPhone/iPad |

---

## References

- Detailed requirements: [plan/requirements.md](plan/requirements.md)
- Detailed architecture: [plan/architecture.md](plan/architecture.md)
- Task index: [../tasks.md](../tasks.md)
- Task details: [../tasks/](../tasks/)
