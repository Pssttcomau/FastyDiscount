# TASK-043: Localization infrastructure (Localizable.xcstrings, locale-aware formatters)

## Description
Set up the localization infrastructure so the app is ready for future translation. Extract all user-facing strings into Localizable.xcstrings, use locale-aware formatters for dates, currencies, and numbers, and verify no hardcoded strings remain in views.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- All UI tasks (Phases 2-7)

## Acceptance Criteria
- [ ] `Localizable.xcstrings` file created with all user-facing strings extracted
- [ ] All strings in SwiftUI views use `String(localized:)` or `LocalizedStringKey`
- [ ] Date formatting uses `Date.FormatStyle` or `DateFormatter` with current locale (not hardcoded formats)
- [ ] Currency formatting uses `Decimal.FormatStyle.Currency` with user's locale
- [ ] Number formatting uses `IntegerFormatStyle` / `FloatingPointFormatStyle` with locale
- [ ] Pluralization rules defined for countable strings (e.g., "1 day remaining" vs "3 days remaining")
- [ ] String keys use dot notation namespacing (e.g., `dashboard.expiringSoon.title`, `dvgForm.title.label`)
- [ ] No hardcoded strings found in any SwiftUI view (verified via grep)
- [ ] Export/import localization workflow verified (Xcode Export Localizations)
- [ ] Comments added to string catalog entries for translator context

## Technical Notes
- Use Xcode's String Catalog (.xcstrings) format (Xcode 15+) instead of .strings files
- `String(localized: "dvgForm.save.button")` is the preferred API
- For interpolated strings: `String(localized: "dashboard.expiring.subtitle \(count) days")` with automatic pluralization
- Date formatting: `dvg.expirationDate?.formatted(date: .abbreviated, time: .omitted)`
- Currency: `dvg.originalValue?.formatted(.currency(code: "USD"))` -- consider detecting user's currency
- Grep for hardcoded strings: search for `Text("` patterns that are not using localized keys
- Do NOT translate yet -- just set up the infrastructure. English strings only for v1.
