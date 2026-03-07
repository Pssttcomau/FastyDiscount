# TASK-032: Build tag management view (create, edit, delete custom tags; view system tags)

## Description
Build a tag management interface accessible from Settings or the DVG form. Users can create custom tags with optional colors, edit tag names, and delete custom tags. System tags are displayed but not editable.

## Assigned Agent
code

## Priority & Complexity
- Priority: Low
- Complexity: S (< 1 hour)
- Routing: code-agent

## Dependencies
- TASK-008 (Tag model)
- TASK-009 (DVGRepository or a dedicated TagRepository)

## Acceptance Criteria
- [ ] List of all tags grouped: System Tags (non-editable) and Custom Tags (editable)
- [ ] System tags displayed with lock icon indicating they cannot be modified
- [ ] "Add Tag" button opens form with name field and optional color picker
- [ ] Custom tag edit: tap to rename, long-press or swipe for delete
- [ ] Delete confirmation: warns if tag is used by existing DVGs ("This tag is used by X DVGs. Remove tag from all?")
- [ ] Color picker: grid of predefined colors (8-12 options) for tag display color
- [ ] Tags searchable if list grows long
- [ ] `@Observable` `TagManagerViewModel` managing CRUD operations

## Technical Notes
- Color picker: use a simple grid of colored circles; store selected color as hex string
- Delete: soft-delete the tag and remove it from all associated DVGs (update relationships)
- Prevent duplicate tag names (case-insensitive check)
- This view is also used as a sheet from the DVG form's tag picker (TASK-011)
