# TASK-045: Comprehensive unit test suite for services and view models

## Description
Create a comprehensive unit test suite covering all service protocols, view models, and business logic. Use protocol-based mocking for dependency injection. Target 80%+ code coverage on the service and view model layers.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- All service and view model tasks (Phases 1-8)

## Acceptance Criteria
- [ ] Mock implementations for all service protocols: `DVGRepository`, `CloudAIService`, `EmailScanService`, `GeofenceService`, `NotificationService`, `AdService`, `StoreKitService`, `KeychainService`
- [ ] `DVGRepository` tests: CRUD operations, soft-delete, auto-expiry, search with filters, nearby query
- [ ] `CloudAIClient` tests: request construction, response parsing, error handling, retry logic
- [ ] `EmailParsingService` tests: high/low confidence routing, dedup, progress reporting
- [ ] `GeofenceManager` tests: priority ranking algorithm, 20-region limit, rotation logic
- [ ] `ExpiryNotificationService` tests: scheduling logic, cancellation, reschedule-all
- [ ] `GmailAuthService` tests: token storage, refresh, revocation
- [ ] `DashboardViewModel` tests: section loading, empty states
- [ ] `DVGFormViewModel` tests: validation, save, edit mode population
- [ ] `SearchViewModel` tests: filter application, sort ordering, debounce
- [ ] `ScannerViewModel` tests: detection handling, result creation
- [ ] All tests use `@MainActor` where testing `@MainActor` view models
- [ ] Tests run in under 30 seconds total (no network calls, all mocked)
- [ ] Test naming convention: `test_methodName_condition_expectedResult`

## Technical Notes
- Use `Swift Testing` framework (`import Testing`) for modern test syntax (`@Test`, `#expect`, `@Suite`)
- Mock services created as classes conforming to the same protocols
- SwiftData testing: use in-memory `ModelContainer` with `ModelConfiguration(isStoredInMemoryOnly: true)`
- For async tests: use `await` and test expectations
- Geofence ranking tests: create DVGs with known expiry dates and distances, verify top 20 selection
- Search tests: verify filter combinations return correct subsets
- Consider test fixtures: `DVG.testFixture(title:store:expiry:)` factory methods
