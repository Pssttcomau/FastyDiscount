# FastyDiscount -- Detailed Architecture

---

## 1. SwiftData Models and Relationships

### 1.1 Model Graph

```
DVG (1) ──── (*) StoreLocation     [to-many, optional]
DVG (1) ──── (*) Tag               [to-many, optional, via join]
DVG (1) ──── (1) ScanResult        [to-one, optional, cascade delete]
Tag (*) ──── (*) DVG               [inverse of DVG.tags]
```

### 1.2 CloudKit Compatibility Rules
SwiftData + CloudKit imposes these constraints:
- **No unique constraints** -- use client-side dedup logic instead
- **No required relationships** -- all relationships must be optional
- **No ordered relationships** -- use a sortOrder field if ordering needed
- **Default values for all non-optional properties**
- **Soft-delete pattern** -- `isDeleted: Bool` instead of physical delete (CloudKit tombstones)
- **Use `@Attribute(.externalStorage)` for large Data fields** (images)

### 1.3 Core Models

```swift
// DVG.swift
@Model
final class DVG {
    var id: UUID
    var title: String
    var code: String
    @Attribute(.externalStorage) var barcodeImageData: Data?
    var barcodeType: String?          // Enum raw value: "qr", "upc", "ean", "pdf417", "text"
    var decodedBarcodeValue: String?
    var dvgType: String               // Enum raw value
    var storeName: String
    var originalValue: Double?        // Using Double for CloudKit compat (no Decimal)
    var remainingBalance: Double?
    var pointsBalance: Int?
    var discountDescription: String?
    var minimumSpend: Double?
    var expirationDate: Date?
    var dateAdded: Date
    var source: String                // Enum raw value
    var status: String                // Enum raw value
    var notes: String?
    var isFavorite: Bool
    var termsAndConditions: String?
    var notificationLeadDays: Int
    var geofenceRadius: Int
    var isDeleted: Bool
    var lastModified: Date

    // Relationships (optional for CloudKit)
    var storeLocations: [StoreLocation]?
    var tags: [Tag]?
    var scanResult: ScanResult?
}

// StoreLocation.swift
@Model
final class StoreLocation {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String
    var placeID: String?
    var isDeleted: Bool
    var dvgs: [DVG]?                  // Inverse
}

// Tag.swift
@Model
final class Tag {
    var id: UUID
    var name: String
    var isSystemTag: Bool
    var colorHex: String?
    var isDeleted: Bool
    var dvgs: [DVG]?                  // Inverse
}

// ScanResult.swift -- stores email parse or OCR result metadata
@Model
final class ScanResult {
    var id: UUID
    var sourceType: String            // "email" or "camera" or "photo" or "pdf"
    var rawText: String?
    var confidenceScore: Double
    var needsReview: Bool
    var reviewedAt: Date?
    @Attribute(.externalStorage) var originalImageData: Data?
    var emailSubject: String?
    var emailSender: String?
    var emailDate: Date?
    var isDeleted: Bool
    var dvg: DVG?                     // Inverse
}
```

### 1.4 Enum Types (String-Backed for CloudKit)

```swift
enum DVGType: String, Codable, CaseIterable, Sendable {
    case discountCode, voucher, giftCard, loyaltyPoints, barcodeCoupon
}

enum DVGStatus: String, Codable, CaseIterable, Sendable {
    case active, used, expired, archived
}

enum DVGSource: String, Codable, CaseIterable, Sendable {
    case manual, email, scan
}

enum BarcodeType: String, Codable, CaseIterable, Sendable {
    case qr, upcA, upcE, ean8, ean13, pdf417, text
}
```

---

## 2. CloudKit Sync Strategy

### 2.1 Container Setup
- iCloud container: `iCloud.com.fastydiscount.app`
- SwiftData `ModelConfiguration` with `cloudKitDatabase: .automatic`
- Shared `ModelContainer` across app, widget, and share extension via App Group

### 2.2 Conflict Resolution
- **Policy**: Server wins (`.serverWins` merge policy)
- **Design principle**: Operations are idempotent; status transitions are monotonic (active -> used -> archived is one-directional)
- **lastModified** field updated on every write for audit trail

### 2.3 Sync Monitoring
- `NSPersistentCloudKitContainer.Event` notifications monitored
- Display sync status indicator in Settings (synced / syncing / error)
- Exponential backoff on sync failures

### 2.4 App Group Configuration
- App Group identifier: `group.com.fastydiscount.shared`
- Shared by: main app, widget extension, share extension, watch extension
- SwiftData store located in shared App Group container

---

## 3. MVVM Layer Structure

### 3.1 Pattern

```
View (SwiftUI)
  |
  |-- @State var viewModel = SomeViewModel()
  |
ViewModel (@Observable, @MainActor)
  |
  |-- Injected services (protocol-based)
  |
Service Layer (actors / protocols)
  |
  |-- SwiftData ModelContext
  |-- URLSession / API clients
  |-- CoreLocation / MapKit
  |-- UserNotifications
```

### 3.2 ViewModel Rules
- All ViewModels annotated `@Observable @MainActor`
- Services injected via init (protocol types for testability)
- Async operations use Swift concurrency (no Combine for new code)
- Error states exposed as published properties (`hasError`, `errorMessage`)
- Loading states explicit (`isLoading`)

### 3.3 Service Protocols

```swift
protocol DVGRepository: Sendable {
    func fetchActive() async throws -> [DVG]
    func fetchExpiringSoon(within days: Int) async throws -> [DVG]
    func fetchNearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [DVG]
    func save(_ dvg: DVG) async throws
    func delete(_ dvg: DVG) async throws  // Soft-delete
}

protocol CloudAIService: Sendable {
    func parseEmail(subject: String, body: String) async throws -> DVGExtractionResult
    func parseImage(imageData: Data, extractedText: String?) async throws -> DVGExtractionResult
}

protocol EmailScanService: Sendable {
    func authenticate() async throws
    func fetchEmails(scope: EmailScanScope) async throws -> [RawEmail]
    func disconnect() async throws
}

protocol GeofenceService: Sendable {
    func registerGeofences(for dvgs: [DVG]) async throws
    func handleRegionEntry(_ region: CLRegion) async
}

protocol NotificationService: Sendable {
    func scheduleExpiryNotification(for dvg: DVG) async throws
    func cancelNotification(for dvg: DVG) async
    func handleAction(_ action: String, for dvgID: UUID) async throws
}
```

---

## 4. Navigation Architecture

### 4.1 Tab-Based Root

```swift
enum AppTab: String, CaseIterable {
    case dashboard    // Home/Dashboard
    case nearby       // Map view
    case scan         // Camera scanner
    case history      // Used/Expired DVGs
    case settings     // Settings
}
```

### 4.2 Navigation Strategy
- **iPhone**: `TabView` with `NavigationStack` per tab
- **iPad/Mac**: `NavigationSplitView` with sidebar (tabs become sidebar items), list, detail
- Switch based on `@Environment(\.horizontalSizeClass)`

### 4.3 Deep Linking
- Custom URL scheme: `fastydiscount://dvg/{id}`
- Used by notifications, widgets, and watch app to open specific DVGs
- Handled in `App.onOpenURL` modifier

### 4.4 Destination Enum

```swift
enum AppDestination: Hashable {
    case dvgDetail(UUID)
    case dvgEdit(UUID)
    case dvgCreate(DVGSource)
    case emailScanResults
    case reviewQueue
    case tagManager
    case storeLocationPicker(UUID)  // DVG ID
}
```

---

## 5. Cloud AI Integration Pattern

### 5.1 Abstraction

```swift
protocol CloudAIClient: Sendable {
    func complete(prompt: String, systemPrompt: String) async throws -> String
    func completeWithVision(prompt: String, imageData: Data, systemPrompt: String) async throws -> String
}
```

Two implementations:
- `OpenAIClient` -- uses OpenAI chat completions API
- `AnthropicClient` -- uses Anthropic messages API

User selects provider and enters API key in Settings.

### 5.2 Parsing Prompts
- **Email parsing prompt**: System prompt defines output JSON schema. User prompt includes email subject + body. Returns structured `DVGExtractionResult`.
- **Vision/OCR prompt**: System prompt defines output JSON schema. Image + extracted text sent. Returns structured `DVGExtractionResult`.

### 5.3 DVGExtractionResult

```swift
struct DVGExtractionResult: Codable, Sendable {
    let title: String?
    let code: String?
    let dvgType: DVGType?
    let storeName: String?
    let originalValue: Double?
    let discountDescription: String?
    let expirationDate: Date?
    let termsAndConditions: String?
    let confidenceScore: Double       // 0.0 - 1.0
    let fieldConfidences: [String: Double]  // Per-field confidence
}
```

### 5.4 Offline Behavior
- If no network: show raw extracted text (from Vision OCR)
- User fills DVG fields manually from the raw text
- No queuing of AI requests for later (simplicity for v1)

---

## 6. Geofencing Engine Design

### 6.1 Architecture

```
GeofenceManager (actor)
  |
  ├── CLLocationManager delegate
  ├── Active geofence registry (max 20)
  ├── DVG priority ranker
  └── Notification dispatcher
```

### 6.2 Priority Ranking Algorithm
Score each DVG with a store location:
```
score = (expiryUrgency * 0.6) + (proximityScore * 0.3) + (favoriteBonus * 0.1)
```
- `expiryUrgency`: 1.0 if expiring within 3 days, scales down to 0.0 at 30+ days
- `proximityScore`: Based on last known distance (closer = higher)
- `favoriteBonus`: 1.0 if favorited, 0.0 otherwise

Top 20 by score get CLCircularRegion geofences.

### 6.3 Rotation Triggers
Recalculate and rotate geofences when:
- Significant location change detected
- DVG is added/modified/deleted
- DVG expires or is used
- App enters foreground

### 6.4 Background Operation
- `CLLocationManager.startMonitoring(for:)` persists across app termination
- `CLLocationManager.startMonitoringSignificantLocationChanges()` for non-geofenced DVGs
- App launched in background on region entry -> post notification -> return

---

## 7. Email Integration Architecture

### 7.1 Gmail API Flow

```
1. User taps "Connect Gmail"
2. ASWebAuthenticationSession opens Google OAuth consent
3. Receive authorization code
4. Exchange for access token + refresh token
5. Store tokens in Keychain
6. User taps "Scan Inbox"
7. Fetch emails matching scope (label, sender whitelist)
8. For each email: send to CloudAIService.parseEmail()
9. High-confidence results auto-saved
10. Low-confidence results queued for review
```

### 7.2 Gmail API Scopes
- `https://www.googleapis.com/auth/gmail.readonly` (read-only access)
- Minimal scope to reduce OAuth app review friction

### 7.3 Apple Mail Integration
- Use `MFMailComposeViewController` as reference but actual integration is limited on iOS
- Primary approach: User forwards emails to an in-app parser
- Alternative: Use iOS Share Sheet to share email content into the app
- This is the simpler/fallback path compared to Gmail API

### 7.4 Token Management
- Access token refreshed automatically using refresh token
- Refresh token stored in Keychain with `kSecAttrAccessibleAfterFirstUnlock`
- Token refresh failure triggers re-authentication prompt

---

## 8. Watch App Architecture

### 8.1 Data Strategy
- Watch app uses Watch Connectivity framework for data transfer
- Main app sends active DVGs as `ApplicationContext` (latest state)
- For barcode display: transfer barcode image data via `transferUserInfo`
- Watch app has local cache for offline viewing

### 8.2 Watch Views
- **DVGListView**: List of active DVGs, sorted by expiry
- **DVGCardView**: Full-screen barcode/QR display for POS scanning
- **ComplicationView**: Next expiring DVG (title + days remaining)

### 8.3 Watch Notifications
- Notifications forwarded from iPhone automatically
- Custom notification UI shows DVG title + store name
- Action buttons: View Code, Mark as Used

---

## 9. Widget Architecture

### 9.1 Widget Families
- `.systemSmall`: Single next-expiring DVG
- `.systemMedium`: Top 3 expiring DVGs

### 9.2 Data Access
- Widget reads from shared SwiftData container (App Group)
- `TimelineProvider` queries DVGs sorted by expirationDate
- Timeline refresh: every 6 hours or on significant DVG changes

### 9.3 Widget Deep Links
- Each widget entry links to `fastydiscount://dvg/{id}`
- Tapping opens DVG detail in main app

---

## 10. Share Sheet Extension Architecture

### 10.1 Accepted Types
- `public.plain-text` -- text containing codes/URLs
- `public.url` -- URLs that might contain discount info
- `public.image` -- screenshots or photos of coupons
- `public.pdf` -- PDF coupons

### 10.2 Extension Flow
1. Receive shared content
2. If image/PDF: run Vision barcode detection + OCR on-device
3. If text/URL: extract potential code patterns via regex
4. Present compact DVG creation form pre-populated with extracted data
5. Save to shared SwiftData container (App Group)
6. Main app picks up new DVG on next launch

### 10.3 Constraints
- Share extensions have limited memory (max ~120MB)
- No Cloud AI calls from extension (too slow, memory-constrained)
- Pre-populate what we can on-device; user completes in main app

---

## 11. Mac Catalyst Considerations

### 11.1 Adaptations
- `UIBehavioralStyle.mac` for native Mac look
- Menu bar: File (New DVG, Import), Edit (standard), View (filters)
- Keyboard shortcuts: Cmd+N (new DVG), Cmd+F (search), Cmd+, (settings)
- Window minimum size: 800x600
- Sidebar navigation (NavigationSplitView already handles this)

### 11.2 Excluded Features on Mac
- Camera scanning (use photo/PDF import instead)
- Geofencing/location (optional, less relevant on desktop)
- Apple Wallet (iOS only)

### 11.3 Mac-Specific Features
- Drag-and-drop files (images, PDFs) onto app window to import
- Multi-window support (view multiple DVGs side by side)

---

## 12. Ad Integration Pattern

### 12.1 Architecture

```swift
protocol AdService: Sendable {
    func loadBannerAd() async -> AdBannerView?
    func loadInterstitialAd() async -> Bool
    func showInterstitialAd() async
    var isAdFree: Bool { get }
}
```

### 12.2 Ad Placement Rules
- Banner: Bottom of Dashboard, Search, History list views
- Interstitial: After every 5th scan (email or camera)
- Never show ads on DVG detail view (user is at POS, showing code)
- Never show ads during onboarding

### 12.3 Ad-Free Upgrade
- When `isAdFree` is true (IAP purchased), all ad views hidden
- Check `isAdFree` from StoreKit 2 `Transaction.currentEntitlements`
- Persist entitlement status in UserDefaults as cache (re-verify on launch)

---

## 13. Dependency Graph (Phase Order)

```
Phase 1 (Setup) ─────────────────────────┐
                                          v
Phase 2 (Data Model) ──┬─────────────> Phase 6 (UI/UX)
                        │                  ^
Phase 3 (Email) ────────┤                  |
                        │                  |
Phase 4 (Scanner) ──────┤                  |
                        │                  |
Phase 5 (Notifications) ┘─────────────────┘
                                          |
Phase 7 (Extensions) <────────────────────┘
                                          |
Phase 8 (Monetization) <──────────────────┘
                                          |
Phase 9 (Polish) <────────────────────────┘
```

Phases 3, 4, and 5 can be parallelized after Phase 2 is complete.
Phase 6 depends on Phase 2 but can begin in parallel with Phases 3-5.
Phase 7 depends on Phase 6 (needs UI patterns established).
Phase 8 can begin after Phase 6.
Phase 9 is the final sequential phase.
