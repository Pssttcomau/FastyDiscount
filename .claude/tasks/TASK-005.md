# TASK-005: Set up navigation architecture with adaptive layout (iPhone/iPad/Mac)

## Description
Implement the root navigation structure that adapts between iPhone (TabView + NavigationStack), iPad (NavigationSplitView with sidebar), and Mac Catalyst. Define the tab enum, destination enum, deep link handling, and the adaptive layout switching logic.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (project structure)

## Acceptance Criteria
- [ ] `AppTab` enum defined (dashboard, nearby, scan, history, settings)
- [ ] `AppDestination` enum defined with all navigation destinations (Hashable)
- [ ] iPhone: `TabView` with `NavigationStack` per tab, each with `.navigationDestination(for:)`
- [ ] iPad/Mac: `NavigationSplitView` with sidebar (tabs as sidebar items), list column, detail column
- [ ] Adaptive switching based on `@Environment(\.horizontalSizeClass)`
- [ ] Deep link handling via `onOpenURL` for `fastydiscount://dvg/{id}` scheme
- [ ] `NavigationRouter` observable class that manages `NavigationPath` and selected tab
- [ ] Placeholder views for each tab (replaced by real views in later tasks)
- [ ] Tab icons using SF Symbols

## Technical Notes
- `NavigationRouter` should be `@Observable @MainActor` and injected via `@Environment`
- For iPad sidebar: use `List(selection:)` bound to selected tab
- Deep link URL parsing: extract DVG UUID from URL path, set active tab to dashboard, push DVG detail
- Mac Catalyst: sidebar is automatic with `NavigationSplitView`; add `.commands` modifier for menu bar items
- Consider using `@SceneStorage` for persisting selected tab across app restarts
- Keep placeholder views as simple `Text("Dashboard")` etc. -- real views come in Phase 6
