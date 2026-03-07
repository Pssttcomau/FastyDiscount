# FastyDiscount -- Detailed Requirements

---

## 1. DVG Data Model

### 1.1 Supported DVG Types
- Discount codes (text promo codes, e.g. "SAVE20")
- Vouchers (fixed-value certificates)
- Gift cards (fixed or reloadable balance)
- Loyalty / reward points (e.g. Starbucks stars)
- Barcoded coupons (scannable at POS)

### 1.2 DVG Fields
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | UUID | Yes (auto) | Primary key |
| title | String | Yes | e.g. "20% off Nike" |
| code | String | No | The actual code to present |
| barcodeImageData | Data | No | Stored original barcode/QR image |
| barcodeType | Enum | No | UPC, EAN, QR, PDF417, Text |
| decodedBarcodeValue | String | No | Machine-readable decoded value |
| dvgType | Enum | Yes | discountCode, voucher, giftCard, loyaltyPoints, barcodeCoupon |
| storeName | String | Yes | Retailer name |
| tags | [Tag] relationship | No | Both fixed categories + custom |
| originalValue | Decimal | No | Face value |
| remainingBalance | Decimal | No | For gift cards |
| pointsBalance | Int | No | For loyalty type |
| discountDescription | String | No | "20%" or "$10 off" |
| minimumSpend | Decimal | No | Minimum order value |
| expirationDate | Date | No | Drives notifications |
| dateAdded | Date | Yes (auto) | Auto-populated at creation |
| source | Enum | Yes | manual, email, scan |
| status | Enum | Yes | active, used, expired, archived |
| notes | String | No | Free-form user notes |
| isFavorite | Bool | No | Quick-access flag (default false) |
| termsAndConditions | String | No | Fine print |
| notificationLeadDays | Int | No | User-configurable per DVG |
| geofenceRadius | Int | No | Meters (100-1000, default 300) |
| isDeleted | Bool | Yes | Soft-delete for CloudKit (default false) |
| lastModified | Date | Yes (auto) | For sync conflict resolution |

### 1.3 Store/Location Model
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| name | String | Store name |
| latitude | Double | From Places API |
| longitude | Double | From Places API |
| address | String | Human-readable address |
| placeID | String | Apple Maps place identifier |

Relationship: DVG has optional to-many relationship with StoreLocation.

### 1.4 Tag Model
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| name | String | Tag display name |
| isSystemTag | Bool | true = fixed category, false = user-created |
| colorHex | String | Optional color for display |

Fixed categories: Food, Clothing, Electronics, Beauty, Home, Travel, Entertainment, Health, Automotive, Other.

### 1.5 Balance Tracking
- Manual for v1: user updates `remainingBalance` or `pointsBalance` after each use
- UI provides a "Record Usage" action that prompts for amount spent
- Future: API integration for auto-balance-check

### 1.6 DVG Lifecycle
- **Active**: Default state; displayed in main list
- **Used**: User marks as used; moves to History section; remains searchable
- **Expired**: Auto-transitioned when `expirationDate` passes; shown in History
- **Archived**: User manually archives; hidden from default views

---

## 2. Email Integration

### 2.1 Supported Providers
- **Gmail**: Via Gmail REST API with OAuth 2.0 sign-in
- **Apple Mail / iCloud**: Via native iOS integration (MessageUI or mail data access)

### 2.2 Access Methods
- **Primary**: OAuth sign-in (user authenticates, app reads emails)
- **Fallback**: Email forwarding to a designated in-app address (for privacy-conscious users) -- deferred to post-v1

### 2.3 Parsing Engine
- Cloud AI parsing via LLM API (OpenAI or Anthropic)
- Sends email subject + body text to LLM with structured extraction prompt
- Returns: store name, code, type, value, expiration, terms
- Confidence score per field; low-confidence fields flagged for review

### 2.4 Scan Frequency
- v1: On-demand only (user taps "Scan Inbox" button)
- Future: Background fetch with configurable interval

### 2.5 Scan Scope
- User configurable in Settings:
  - Specific Gmail labels (default: "Promotions")
  - Sender whitelist (optional)
  - Full inbox (opt-in)
- Scope persisted in UserDefaults / app settings

### 2.6 Confirmation Flow
- Auto-save with review queue for uncertain extractions
- High-confidence extractions: saved directly, appear in "Recently Added"
- Low-confidence extractions: appear in "Review Queue" with editable fields highlighted
- User can approve, edit, or discard each extraction

---

## 3. Scanning / OCR

### 3.1 Scan Sources
- Live camera (AVCaptureSession + Vision)
- Photo library (PHPickerViewController)
- PDF document import (UIDocumentPickerViewController + PDFKit)

### 3.2 Code Recognition
- Barcodes: UPC-A, UPC-E, EAN-8, EAN-13
- QR codes
- PDF417
- Text OCR (VNRecognizeTextRequest for raw text extraction)

### 3.3 Smart Extraction
- Step 1: Apple Vision extracts raw text and/or barcode values on-device
- Step 2: If text coupon/flyer, send extracted text + image to Cloud AI for structured parsing
- Step 3: Returns same structured DVG fields as email parsing
- Offline: Show raw extracted text; user fills fields manually

### 3.4 Image Storage
- Store original image (compressed JPEG, max 1MB) as Data in SwiftData
- Store decoded barcode/QR value as text
- For display at POS: regenerate barcode from decoded value using CIFilter

---

## 4. Notifications

### 4.1 Expiry Notifications
- User-configurable lead time per DVG (default: 3 days)
- Single notification per DVG per expiry event
- Scheduled via UNUserNotificationCenter with calendar trigger

### 4.2 Notification Actions
- **View Code**: Opens DVG detail view (UNNotificationAction)
- **Mark as Used**: Updates status to .used (UNNotificationAction)
- **Snooze**: Reschedules notification for +1 day (UNNotificationAction)

### 4.3 Location Notifications
- Triggered when user enters geofenced region associated with a DVG
- Content: DVG title + store name + "You have a discount nearby!"
- Same action buttons as expiry notifications

### 4.4 Notification Settings
- Global toggle for all notifications
- Global toggle for expiry vs. location notifications separately
- Per-DVG notification lead days configurable in DVG edit form

---

## 5. Location / Geofencing

### 5.1 Store Data Entry
- Apple Maps MKLocalSearchCompleter for auto-suggest
- User confirms location from search results
- Stores latitude, longitude, address, placeID

### 5.2 Geofencing Strategy
- Top 20 DVGs (by expiry proximity, then by distance) registered as CLCircularRegion geofences
- Remaining DVGs monitored via significant location change events
- On significant location change: recalculate distances, re-rank, rotate geofences

### 5.3 Geofence Configuration
- Default radius: 300 meters
- User-configurable per DVG: 100m to 1000m
- Background monitoring: enabled even when app is terminated

### 5.4 Nearby Map View
- Dedicated "Nearby" tab using MapKit
- Shows current location + pins for stores with active DVGs
- Tapping a pin shows DVG summary card
- Distance and walking/driving time displayed

---

## 6. User Experience

### 6.1 Dashboard (Home Screen)
Sections:
1. **Expiring Soon**: DVGs expiring within 7 days, sorted by date
2. **Nearby**: DVGs with store locations within current proximity (if location authorized)
3. **Recently Added**: Last 5 DVGs added, any source
4. **Quick Actions**: Scan, Add Manual, Scan Email (floating action or toolbar)

### 6.2 Search and Filter
- Search bar: searches store name, title, code, notes
- Filters: DVG type, status, tag/category, expiry range (date picker)
- Smart sorting: by expiry (default), by value, by recently added, alphabetical
- Results update live as user types

### 6.3 Manual DVG Entry
- Quick-add mode: title + code + store + expiry (4 fields)
- "Show more fields" expands to full form
- Store name has auto-complete from previously used stores
- Tag picker with both fixed categories and custom tags

### 6.4 Dark Mode
- Follows system setting by default
- Manual override in Settings (Light / Dark / System)
- All custom colors defined in Asset Catalog with light/dark variants

### 6.5 Onboarding
- Screen 1: App value proposition ("Never waste a discount again")
- Screen 2: Key features overview (Email scan, Camera scan, Alerts)
- Screen 3: Interactive -- add your first DVG (guided quick-add)
- Permission requests: notifications, location, camera (requested contextually, not upfront)

### 6.6 Settings
- Account: Sign in with Apple status, CloudKit sync status
- Email: Connected accounts, scan scope, re-authenticate
- Notifications: Global toggle, expiry toggle, location toggle
- Location: Enable/disable geofencing, default radius
- AI: API key management, usage stats
- Appearance: Dark mode override
- About: Version, privacy policy, licenses
- Ads: "Remove Ads" IAP button

---

## 7. Platform Extensions

### 7.1 Home Screen Widget (WidgetKit)
- Small widget: Next expiring DVG (title + store + days remaining)
- Medium widget: Top 3 expiring DVGs
- Tap opens corresponding DVG detail in app

### 7.2 Apple Watch App
- View list of active DVGs (sorted by expiry)
- Tap to show barcode/QR code (full screen for scanning at POS)
- Receive expiry and location notifications on watch
- Complication: Next expiring DVG

### 7.3 Apple Wallet Integration
- Generate PKPass for DVGs with barcode data
- Pass includes: store name, code, barcode, expiry date
- Update pass when DVG is modified
- Remove pass when DVG is used/expired

### 7.4 Share Sheet Extension
- Accept shared text, URLs, and images from other apps
- Parse shared content to pre-populate DVG creation form
- If image: run through barcode/OCR pipeline
- If text/URL: attempt to extract code and store name

### 7.5 iPad Adaptive Layout
- NavigationSplitView with sidebar (categories/tags), list, detail
- Drag-and-drop support for organizing DVGs
- Keyboard shortcuts for power users

### 7.6 Mac Catalyst
- Menu bar integration (File, Edit, View menus)
- Keyboard shortcuts
- Window resizing with adaptive layout
- Touch Bar support (if applicable, though deprecated)

---

## 8. Monetization

### 8.1 Ad Integration
- Google AdMob banner ads at bottom of main list views
- Interstitial ad after every 5th email scan or camera scan
- No ads on DVG detail view (preserves UX when showing code at POS)

### 8.2 In-App Purchase
- Single non-consumable IAP: "Remove Ads"
- StoreKit 2 API
- Restore purchases support
- Receipt validation

### 8.3 Paywall
- Settings screen shows "Remove Ads" with price
- Occasional gentle prompt after ad display

---

## 9. Non-Functional Requirements

### 9.1 Performance
- App launch to interactive: under 1 second
- DVG list scroll: 60fps
- Camera scan to result: under 2 seconds (on-device portion)
- Email scan: progress indicator with per-email status

### 9.2 Security
- Sign in with Apple for identity
- OAuth tokens stored in Keychain
- AI API key stored in Keychain
- No DVG data sent to third parties except AI API for parsing (user consented)
- CloudKit encryption at rest

### 9.3 Accessibility
- Full VoiceOver support
- Dynamic Type (all text scales)
- High contrast mode support
- Minimum 44pt touch targets
- Semantic colors throughout

### 9.4 Localization
- English only for v1
- All user-facing strings in Localizable.xcstrings
- Date/currency formatting via Foundation formatters (locale-aware)
- No hardcoded strings in views

### 9.5 App Store Compliance
- Privacy nutrition labels accurate
- App Tracking Transparency if AdMob uses IDFA
- Location usage descriptions in Info.plist
- Camera usage description
- Photo library usage description
