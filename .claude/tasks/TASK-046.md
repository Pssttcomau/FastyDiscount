# TASK-046: UI test suite for critical user flows (add DVG, scan, search)

## Description
Create UI tests for the most critical user flows using XCTest UI testing framework. Cover the end-to-end flows that users perform most frequently: adding a DVG manually, searching/filtering, viewing a DVG detail, and navigating between tabs.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- All UI tasks (Phases 2-7)
- TASK-045 (unit tests should be done first)

## Acceptance Criteria
- [ ] UI test target configured in Xcode project
- [ ] Test: Complete manual DVG creation flow (tap Add, fill fields, save, verify appears in list)
- [ ] Test: DVG detail view displays all fields correctly
- [ ] Test: Search by store name returns matching results
- [ ] Test: Filter by DVG type shows only matching DVGs
- [ ] Test: Mark DVG as used, verify it moves to history
- [ ] Test: Tab navigation (dashboard, nearby, scan, history, settings)
- [ ] Test: Onboarding flow completes and shows dashboard
- [ ] Test: Settings view loads all sections
- [ ] Test data seeded via launch arguments (use `ProcessInfo.processInfo.arguments` to detect test mode)
- [ ] Tests use accessibility identifiers for reliable element queries
- [ ] All tests pass on iPhone simulator (iPhone 15 Pro)
- [ ] Tests run in under 2 minutes total

## Technical Notes
- Use `XCUIApplication` for launching and interacting with the app
- Seed test data: pass `-UITestMode` as launch argument; app detects and loads mock data
- Accessibility identifiers: add `.accessibilityIdentifier("dvg-list-row-\(dvg.id)")` to key elements
- For camera scanner: skip in UI tests (cannot simulate camera); test the results view with mock data
- Use `XCTAssertTrue(app.staticTexts["DVG Title"].waitForExistence(timeout: 5))` for async UI
- Consider page object pattern: `DashboardPage`, `DVGFormPage`, `SearchPage` classes encapsulating element queries
- Disable animations in test mode for faster, more reliable tests: `UIView.setAnimationsEnabled(false)`
