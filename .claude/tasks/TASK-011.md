# TASK-011: Create DVG form view (quick-add and full edit modes)

## Description
Build the DVG creation and editing form with two modes: quick-add (4 essential fields) and full edit (all fields). The form supports store name auto-complete, tag selection, date picking, barcode type selection, and location assignment. Used for both manual creation and editing existing DVGs.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-007 (DVG model)
- TASK-008 (Tag and StoreLocation models)
- TASK-009 (DVGRepository for saving)
- TASK-006 (theme system)

## Acceptance Criteria
- [ ] Quick-add mode shows: title, code, store name, expiration date
- [ ] "Show More Fields" button expands to full form with all DVG fields
- [ ] Store name auto-complete from previously used store names (query existing DVGs)
- [ ] DVG type picker (segmented control or picker wheel)
- [ ] Tag picker: multi-select from system tags + custom tags, with "Create New Tag" option
- [ ] Expiration date picker (optional, calendar-style)
- [ ] Notification lead days picker (1, 2, 3, 5, 7, 14, 30 days)
- [ ] Balance/points fields shown conditionally based on DVG type (gift card -> balance, loyalty -> points)
- [ ] Form validation: title required, store name required; show inline errors
- [ ] Save action calls `DVGRepository.save()` and dismisses the form
- [ ] Edit mode: pre-populates all fields from existing DVG
- [ ] `@Observable` `DVGFormViewModel` manages form state, validation, and save logic
- [ ] Keyboard management: auto-advance to next field, dismiss on save

## Technical Notes
- Use `@FocusState` for keyboard management
- Store name auto-complete: query distinct `storeName` values from DVGRepository
- Tag picker can be a separate sheet/popover with a list of toggleable tags
- For edit mode: pass the existing DVG to the ViewModel and populate all fields
- Validate before save; do not dismiss if validation fails
- Consider using `Form` with `Section` for grouping related fields
- The form should work well on both iPhone (full-screen sheet) and iPad (popover or sheet)
