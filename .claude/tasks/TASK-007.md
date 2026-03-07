# TASK-007: Implement DVG SwiftData model with all fields and enum types

## Description
Define the primary `DVG` SwiftData `@Model` class with all 22+ fields as specified in the requirements. Define all associated enum types as String-backed Codable enums for CloudKit compatibility. Include computed properties for display (formatted values, status color, etc.).

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-002 (SwiftData container setup)

## Acceptance Criteria
- [ ] `DVG` @Model class with all fields from requirements (id, title, code, barcodeImageData, barcodeType, decodedBarcodeValue, dvgType, storeName, originalValue, remainingBalance, pointsBalance, discountDescription, minimumSpend, expirationDate, dateAdded, source, status, notes, isFavorite, termsAndConditions, notificationLeadDays, geofenceRadius, isDeleted, lastModified)
- [ ] `barcodeImageData` marked with `@Attribute(.externalStorage)` for CloudKit large data
- [ ] `DVGType` enum: discountCode, voucher, giftCard, loyaltyPoints, barcodeCoupon (String-backed, Codable, CaseIterable, Sendable)
- [ ] `DVGStatus` enum: active, used, expired, archived
- [ ] `DVGSource` enum: manual, email, scan
- [ ] `BarcodeType` enum: qr, upcA, upcE, ean8, ean13, pdf417, text
- [ ] Default values for all non-optional properties (CloudKit requirement)
- [ ] Computed properties: `isExpired`, `daysUntilExpiry`, `displayValue` (formatted currency/percentage), `statusColor`
- [ ] `init` with sensible defaults for optional fields
- [ ] All types conform to `Sendable`
- [ ] Relationship stubs for `storeLocations`, `tags`, `scanResult` (defined as optional arrays/optionals)

## Technical Notes
- Use `Double` instead of `Decimal` for currency values (CloudKit does not support Decimal)
- Enum properties stored as `String` raw values in SwiftData; use computed properties with type-safe getters/setters
- `isDeleted` is for soft-delete pattern required by CloudKit (not the same as SwiftData's actual deletion)
- `lastModified` should be auto-updated in a `willSave` or via repository layer
- Consider a `DVG.preview` static property for SwiftUI previews
- No unique constraints (CloudKit restriction) -- dedup handled at repository layer
