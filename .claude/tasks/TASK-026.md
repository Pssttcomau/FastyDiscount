# TASK-026: Build dashboard home screen with Expiring Soon, Nearby, and Recently Added sections

## Description
Build the main dashboard view that serves as the app's home screen. It displays three card-based sections: Expiring Soon (DVGs expiring within 7 days), Nearby (DVGs with store locations near current position), and Recently Added (last 5 DVGs). Includes quick-action buttons for scanning and manual add.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-009 (DVGRepository for queries)
- TASK-007 (DVG model)
- TASK-005 (navigation for DVG detail routing)
- TASK-006 (theme system)
- TASK-010 (DVG detail view as navigation destination)

## Acceptance Criteria
- [ ] Dashboard view with scrollable vertical layout containing three sections
- [ ] **Expiring Soon** section: horizontal scroll of DVG cards, expiring within 7 days, sorted by date; shows expiry countdown badge (red for < 3 days, yellow for 3-7 days)
- [ ] **Nearby** section: horizontal scroll of DVG cards near current location; shows distance; hidden if location not authorized or no nearby DVGs
- [ ] **Recently Added** section: vertical list of last 5 DVGs with compact row layout
- [ ] Each DVG card shows: title, store name, type icon, expiry badge (if applicable), favorite star
- [ ] Tapping a card navigates to DVG detail view (TASK-010)
- [ ] Quick action toolbar or FAB: "Scan" (camera), "Add" (manual form), "Email Scan"
- [ ] Empty state for each section when no data (friendly illustration + message)
- [ ] Overall empty state when no DVGs exist ("Add your first discount!")
- [ ] Pull-to-refresh reloads all sections
- [ ] `@Observable` `DashboardViewModel` with methods to load each section independently
- [ ] Adaptive: single column on iPhone, two-column grid on iPad
- [ ] Section headers with "See All" button linking to filtered list

## Technical Notes
- Use `ScrollView(.horizontal)` for Expiring Soon and Nearby sections with `LazyHStack`
- "Nearby" section uses `CLLocationManager.location` for current position and `DVGRepository.fetchNearby()`
- If location not authorized: hide Nearby section entirely (not just empty state)
- Quick actions: use a `Menu` with SF Symbol icons or a floating toolbar at bottom
- Pull-to-refresh: `.refreshable` modifier on the main `ScrollView`
- DVG cards should be a reusable `DVGCardView` component used across the app
- "See All" for Expiring Soon navigates to search view with expiry filter pre-set
- Optimize: load sections in parallel using `async let`
