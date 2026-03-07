# TASK-029: Build onboarding flow (3 screens + interactive first-DVG setup)

## Description
Create a 3-screen onboarding walkthrough for first-time users, followed by an interactive guided setup to add their first DVG. The onboarding should be visually engaging, clearly communicate the app's value, and request permissions contextually (not all upfront).

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-006 (theme system)
- TASK-011 (DVG form for guided first-DVG creation)

## Acceptance Criteria
- [ ] Screen 1: Value proposition -- "Never Waste a Discount Again" with hero illustration and key benefit bullets
- [ ] Screen 2: Feature overview -- Email scanning, camera scanning, location alerts with icons/illustrations
- [ ] Screen 3: Interactive -- "Add Your First Discount" with three options: Scan (camera), Import from Email, Add Manually
- [ ] Smooth horizontal paging with page indicator dots
- [ ] "Skip" button on all screens (goes directly to dashboard)
- [ ] "Next" and "Get Started" buttons with smooth transitions
- [ ] Choosing an option on Screen 3 navigates to the appropriate flow (camera scanner, email scan, or DVG form)
- [ ] Onboarding shown only on first launch; completion tracked in UserDefaults
- [ ] Permission requests NOT shown during onboarding (requested contextually when features are used)
- [ ] Animations: subtle fade-in for illustrations, slide for content
- [ ] `@Observable` `OnboardingViewModel` tracking current page and completion state
- [ ] Supports Dynamic Type and VoiceOver

## Technical Notes
- Use `TabView` with `.tabViewStyle(.page)` for horizontal paging
- Illustrations: use SF Symbols composed into simple graphics, or placeholder rectangles for custom art
- Store `hasCompletedOnboarding` in UserDefaults; check in `FastyDiscountApp.swift` to decide root view
- The "Add Your First Discount" screen should feel interactive, not like a tutorial
- After the first DVG is added (from any path), mark onboarding as complete
- Skip also marks onboarding as complete
- Onboarding should look great on both iPhone and iPad
