# TASK-009: Build DVGRepository service with CRUD operations and queries

## Description
Create the `DVGRepository` protocol and its SwiftData implementation. This service layer sits between ViewModels and SwiftData, providing typed queries, soft-delete logic, auto-expiry status updates, and deduplication checks. It is the single point of access for DVG data mutations.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-007 (DVG model)
- TASK-008 (related models)

## Acceptance Criteria
- [ ] `DVGRepository` protocol with methods: `fetchActive()`, `fetchExpiringSoon(within:)`, `fetchNearby(lat:lon:radius:)`, `fetchByStatus(_:)`, `fetchByTag(_:)`, `search(query:filters:sort:)`, `save(_:)`, `softDelete(_:)`, `markAsUsed(_:)`, `updateBalance(_:newBalance:)`, `fetchReviewQueue()`
- [ ] `SwiftDataDVGRepository` concrete implementation using `ModelContext`
- [ ] Soft-delete: `softDelete` sets `isDeleted = true` and `status = .archived` instead of calling `modelContext.delete`
- [ ] Auto-expiry: `fetchActive()` checks `expirationDate` and transitions expired DVGs to `.expired` status
- [ ] `lastModified` auto-updated on every save/mutation
- [ ] `search` supports text query (store name, title, code, notes) + filters (type, status, tag, expiry date range) + sort order (expiry, value, dateAdded, alphabetical)
- [ ] `fetchNearby` calculates distance from given coordinates and filters by radius (in meters)
- [ ] `fetchReviewQueue` returns DVGs with associated ScanResult where `needsReview == true`
- [ ] All methods are async and throw typed errors
- [ ] Conforms to `Sendable` (uses `@ModelActor` or is `@MainActor`)

## Technical Notes
- Use `@ModelActor` macro for background context operations, or `@MainActor` if keeping on main thread (evaluate performance)
- For `fetchNearby`: calculate Haversine distance in Swift; SwiftData does not support geo-queries natively
- Dedup check: before saving, check if a DVG with the same `code` + `storeName` already exists (warn, do not block)
- Consider a `DVGFilter` struct to encapsulate all filter parameters for the `search` method
- The repository should not directly schedule notifications -- that is the NotificationService's responsibility (called by ViewModels after save)
