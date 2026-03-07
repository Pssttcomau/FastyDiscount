# TASK-016: Build review queue UI for low-confidence email extractions

## Description
Build the review queue interface where users can approve, edit, or discard DVG extractions that the AI marked as low-confidence. Each item shows the extracted fields with confidence indicators, the original email snippet, and editable fields.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-014 (parsing pipeline creates review queue items)
- TASK-009 (DVGRepository.fetchReviewQueue())
- TASK-011 (DVG form view for editing)
- TASK-006 (theme system)

## Acceptance Criteria
- [ ] List of DVGs with `ScanResult.needsReview == true`, sorted by date (newest first)
- [ ] Each item shows: extracted title, store, code, type, expiry, confidence score (color-coded)
- [ ] Per-field confidence indicators (green/yellow/red dots or bars)
- [ ] Original email snippet displayed in expandable section
- [ ] Action buttons per item: Approve (accept as-is), Edit (opens DVG form pre-populated), Discard (soft-delete)
- [ ] Approve action sets `needsReview = false` and `reviewedAt = Date()`
- [ ] Batch actions: "Approve All" and "Discard All" with confirmation
- [ ] Empty state when no items need review
- [ ] Badge count on the review queue navigation element showing pending count
- [ ] `@Observable` `ReviewQueueViewModel` managing the list and actions

## Technical Notes
- Confidence color coding: >= 0.8 green, 0.5-0.8 yellow, < 0.5 red
- "Edit" action should navigate to the DVG form (TASK-011) in edit mode with all fields pre-populated
- Discard sets `DVG.isDeleted = true` and `ScanResult.needsReview = false`
- Consider swipe actions on list items for quick approve/discard
- The badge count can be computed from `DVGRepository.fetchReviewQueue().count`
