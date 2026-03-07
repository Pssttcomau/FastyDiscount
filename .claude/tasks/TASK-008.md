# TASK-008: Implement StoreLocation, Tag, and ScanResult models with relationships

## Description
Define the supporting SwiftData models: `StoreLocation`, `Tag`, and `ScanResult`. Establish the relationships to `DVG`. Seed the system tags (fixed categories) on first launch. All models must be CloudKit-compatible.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-007 (DVG model must exist for relationship targets)

## Acceptance Criteria
- [ ] `StoreLocation` @Model: id, name, latitude, longitude, address, placeID (optional), isDeleted; inverse relationship to `[DVG]?`
- [ ] `Tag` @Model: id, name, isSystemTag, colorHex (optional), isDeleted; inverse relationship to `[DVG]?`
- [ ] `ScanResult` @Model: id, sourceType, rawText, confidenceScore, needsReview, reviewedAt, originalImageData (@externalStorage), emailSubject, emailSender, emailDate, isDeleted; inverse relationship to `DVG?`
- [ ] DVG relationships fully connected: `storeLocations: [StoreLocation]?`, `tags: [Tag]?`, `scanResult: ScanResult?`
- [ ] System tags seeded on first launch: Food, Clothing, Electronics, Beauty, Home, Travel, Entertainment, Health, Automotive, Other
- [ ] `TagSeeder` service that checks if system tags exist and creates them if missing (idempotent)
- [ ] All models registered in `ModelContainer` schema
- [ ] All relationships are optional (CloudKit requirement)
- [ ] All models have `isDeleted` soft-delete field

## Technical Notes
- Relationships in SwiftData with CloudKit must be optional and cannot have cascade delete rules enforced by CloudKit -- handle cascade in application logic
- `ScanResult.originalImageData` uses `@Attribute(.externalStorage)` for large image data
- `TagSeeder` should run on first launch and also on model migration (in case new system tags are added in future versions)
- Consider a `CLLocationCoordinate2D` computed property on `StoreLocation` for MapKit integration
- `StoreLocation` may be shared across multiple DVGs (same store, different discounts)
- Preview/sample data: create static `preview` properties on each model for SwiftUI previews
