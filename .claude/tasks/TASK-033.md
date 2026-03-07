# TASK-033: Build WidgetKit expiring-soon widget (small + medium families)

## Description
Create WidgetKit widgets that display expiring DVGs on the home screen. Small widget shows the next expiring DVG; medium widget shows the top 3. Tapping a widget deep-links to the corresponding DVG in the app.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (WidgetKit extension target)
- TASK-002 (shared SwiftData container via App Group)
- TASK-007 (DVG model)
- TASK-006 (theme system colors)

## Acceptance Criteria
- [ ] `WidgetBundle` entry point in the widget extension target
- [ ] `ExpiringDVGWidget` with `.systemSmall` and `.systemMedium` support
- [ ] Small widget: DVG title, store name, days remaining with urgency color, type icon
- [ ] Medium widget: top 3 expiring DVGs in a compact list layout
- [ ] `TimelineProvider` that queries shared SwiftData container for active DVGs sorted by expirationDate
- [ ] Timeline entries refresh every 6 hours (`.atEnd` policy)
- [ ] Each widget entry contains a deep link URL: `fastydiscount://dvg/{id}`
- [ ] Placeholder and snapshot views for widget gallery preview
- [ ] Empty state: "No expiring discounts" with app icon
- [ ] Widget uses `containerBackground` for proper iOS 17+ widget styling
- [ ] Colors match app theme (urgency colors: red, yellow, green)
- [ ] VoiceOver labels on all text elements

## Technical Notes
- Widget extension reads from shared App Group SwiftData container -- same as TASK-002
- `TimelineProvider.getTimeline`: query DVGs where `status == .active && expirationDate != nil && isDeleted == false`, sorted by expirationDate ascending, limit to 3
- Use `Link(destination:)` or `.widgetURL()` for deep linking
- Widget views cannot use `@Query` -- must use `ModelContainer` directly in the provider
- Keep the data model lightweight in the widget: use a simple `DVGWidgetEntry` struct, not the full `@Model`
- Test with multiple widget sizes in the widget preview canvas
- Widget configuration: static (no user configuration needed for v1)
