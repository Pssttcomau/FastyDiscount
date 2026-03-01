# FastyDiscount — Privacy Nutrition Labels (App Store Connect)

## Overview

App Store Connect requires you to declare which data types your app collects,
how they are used, and whether they are linked to the user's identity or used
for tracking. The declarations below must be entered manually in App Store Connect
under **App Privacy > Data Types**.

---

## Data Types Collected

### 1. Location — Precise Location
- **Collected**: Yes
- **Purpose(s)**: App Functionality (geofencing for store alerts)
- **Linked to identity**: No
- **Used for tracking**: No
- **Notes**: Precise location is used on-device only to determine when the user
  enters a geofence region. It is never sent to FastyDiscount servers.

### 2. Identifiers — Device ID
- **Collected**: Yes (when AdMob is integrated)
- **Purpose(s)**: Third-Party Advertising, Analytics
- **Linked to identity**: No
- **Used for tracking**: Yes
- **Notes**: IDFA (Identifier for Advertisers) is accessed by Google AdMob for
  personalised ad delivery. Requires App Tracking Transparency (ATT) consent
  prompt. If the user declines ATT, only contextual (non-personalised) ads are shown.

### 3. Purchases — Purchase History
- **Collected**: Yes
- **Purpose(s)**: App Functionality (entitlement verification for "Remove Ads" IAP)
- **Linked to identity**: Yes (linked to Apple ID via StoreKit 2)
- **Used for tracking**: No
- **Notes**: Purchase history is managed entirely by StoreKit 2 / Apple's servers.
  FastyDiscount does not store purchase receipts on its own servers.

### 4. Contact Info — Email Address
- **Collected**: Yes (optional, via Gmail API integration)
- **Purpose(s)**: App Functionality (import vouchers from Gmail)
- **Linked to identity**: Yes
- **Used for tracking**: No
- **Notes**: Email address (and Gmail message content) is accessed only with explicit
  OAuth consent. It is processed on-device to extract voucher data; raw email content
  is never stored on FastyDiscount servers.

### 5. Identifiers — User ID
- **Collected**: Yes
- **Purpose(s)**: App Functionality (Sign in with Apple user identifier)
- **Linked to identity**: Yes
- **Used for tracking**: No
- **Notes**: The Sign in with Apple stable user identifier is used solely to identify
  the user's iCloud sync container. It is never shared with third parties.

---

## Data NOT Collected

The following common data types are explicitly NOT collected:

- Health & Fitness data
- Financial data (credit card numbers, bank details)
- Sensitive info (racial or ethnic data, religious beliefs, etc.)
- Browsing history
- Search history
- Usage data (beyond crash diagnostics via Apple, which is opt-in)
- Diagnostics (optional, via Apple's own aggregated crash reporting)

---

## Third-Party SDKs and Their Data Declarations

| SDK | Data Collected | Tracking |
|---|---|---|
| Google AdMob | Device identifiers (IDFA), coarse location | Yes (with ATT consent) |
| CloudKit (Apple) | User identifier, iCloud data | No |
| Gmail API (Google) | Email address, email content | No |
| Sign in with Apple | User identifier, name (first-time only) | No |

---

## Privacy Manifest Summary (PrivacyInfo.xcprivacy)

See `PrivacyInfo.xcprivacy` in the project root for the machine-readable privacy
manifest required for iOS 17+. It declares:

- `NSPrivacyAccessedAPICategoryUserDefaults` — user defaults accessed for settings and ad-free state
- `NSPrivacyAccessedAPICategoryFileTimestamp` — file timestamps accessed for voucher import
- `NSPrivacyAccessedAPICategoryDiskSpace` — disk space checked before writing large assets

---

## Privacy Policy

Privacy Policy URL: **https://fastydiscount.app/privacy**

The privacy policy must describe:
1. What data is collected and why
2. How location data is used (on-device only, not shared)
3. How advertising identifiers are used (AdMob, ATT consent)
4. How Gmail data is used (on-device extraction only)
5. How to contact us to request data deletion
6. GDPR / CCPA compliance statements
