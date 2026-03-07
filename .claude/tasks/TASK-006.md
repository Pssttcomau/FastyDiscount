# TASK-006: Create app theme system (colors, typography, dark mode, Dynamic Type)

## Description
Create a centralized theme system with named colors (light/dark variants), typography scale, and spacing constants. All colors defined in Asset Catalog. Typography supports Dynamic Type. Dark mode follows system setting with manual override stored in UserDefaults.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (project structure, Assets.xcassets)

## Acceptance Criteria
- [ ] Color set defined in Assets.xcassets with light and dark variants: primary, secondary, accent, background, surface, textPrimary, textSecondary, border, error, success, warning
- [ ] `Theme` enum or struct with static color accessors (`Theme.primary`, `Theme.secondary`, etc.)
- [ ] Typography scale using `Font.TextStyle` with custom font support: largeTitle, title, headline, body, callout, caption
- [ ] Spacing constants: `Theme.Spacing` (xs: 4, sm: 8, md: 16, lg: 24, xl: 32)
- [ ] Corner radius constants: `Theme.CornerRadius` (small: 8, medium: 12, large: 16)
- [ ] `AppearanceManager` observable class that manages dark mode preference (system/light/dark)
- [ ] Dark mode override applied via `.preferredColorScheme()` modifier at root view
- [ ] All text uses Dynamic Type via `.font(.body)` etc. (no hardcoded point sizes)

## Technical Notes
- Use Color asset catalog entries so they automatically switch in dark mode
- `AppearanceManager` stores preference in UserDefaults: `.system`, `.light`, `.dark`
- Inject `AppearanceManager` via `@Environment` at root level
- Consider a `ViewModifier` for common card styling (background, corner radius, shadow)
- Recommended palette: Use a fresh, modern palette -- e.g. teal/blue primary, coral accent
- High contrast mode: ensure all text passes WCAG AA contrast ratio (4.5:1 for body, 3:1 for large text)
