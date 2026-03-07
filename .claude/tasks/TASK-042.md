# TASK-042: Accessibility audit and remediation (VoiceOver, Dynamic Type, contrast)

## Description
Perform a comprehensive accessibility audit across all views and fix any issues. Ensure full VoiceOver support, Dynamic Type scaling, high contrast mode, and minimum touch target sizes throughout the app.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- All Phase 6 UI tasks (TASK-026 through TASK-032)

## Acceptance Criteria
- [ ] All interactive elements have meaningful `.accessibilityLabel` values
- [ ] All images have `.accessibilityLabel` or are marked `.accessibilityHidden(true)` if decorative
- [ ] VoiceOver navigation order is logical on every screen (top-to-bottom, left-to-right)
- [ ] Custom components (DVG cards, barcode display, map pins) have custom VoiceOver descriptions
- [ ] All text uses Dynamic Type (`.font(.body)`, `.font(.headline)`, etc.) -- no hardcoded sizes
- [ ] Layout does not break at accessibility text sizes (xxxLarge) -- verified visually
- [ ] All colors pass WCAG AA contrast ratio (4.5:1 body text, 3:1 large text) in both light and dark modes
- [ ] Minimum touch target size: 44x44 points for all interactive elements
- [ ] `.accessibilityAction` added for complex gestures (swipe actions have button alternatives)
- [ ] Barcode display screen has VoiceOver announcement: "Barcode displayed for {store}. Show to cashier."
- [ ] Map view has accessible annotation descriptions
- [ ] Form fields have `.accessibilityHint` explaining expected input
- [ ] Status badges (Used, Expired, Active) have semantic accessibility traits

## Technical Notes
- Use Xcode Accessibility Inspector for automated testing
- Test with VoiceOver enabled on a real device (not just simulator)
- Dynamic Type: test at all text sizes, especially xxxLarge
- High contrast: test with Settings > Accessibility > Increase Contrast enabled
- For custom drawn views (barcode): provide `accessibilityLabel` with the code value
- Map accessibility: `MKAnnotationView.accessibilityLabel` with store name and DVG info
- Consider `.accessibilityElement(children:)` for compound views like DVG cards
