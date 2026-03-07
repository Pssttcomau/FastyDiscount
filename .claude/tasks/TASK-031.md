# TASK-031: Build history view for used/expired/archived DVGs

## Description
Build the history tab that shows DVGs that are no longer active (used, expired, archived). Users can browse, search, and reactivate DVGs from history. This replaces the "History" tab in the navigation.

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-009 (DVGRepository.fetchByStatus())
- TASK-007 (DVG model)
- TASK-006 (theme system)
- TASK-010 (DVG detail for navigation)

## Acceptance Criteria
- [ ] Segmented control or tab for filtering: All History, Used, Expired, Archived
- [ ] List of DVGs in selected status, sorted by date (newest status change first)
- [ ] Each row shows: title, store, type icon, status badge (color-coded), date used/expired
- [ ] Swipe actions: Reactivate (sets status back to .active), Permanently Delete (hard delete with confirmation)
- [ ] Search bar for searching within history
- [ ] Empty state per segment ("No used DVGs yet", "Nothing expired", etc.)
- [ ] Tapping a DVG navigates to detail view (read-only, shows historical info)
- [ ] "Clear All" button per segment with confirmation dialog
- [ ] Status badge colors: Used = blue, Expired = red, Archived = gray
- [ ] `@Observable` `HistoryViewModel` managing filter state and DVG list

## Technical Notes
- Reactivate: set `status = .active`, clear `isDeleted` if needed, reschedule notifications
- Permanent delete: actually remove from SwiftData (`modelContext.delete`) -- this is the only hard delete in the app
- "Clear All" for expired: permanently delete all expired DVGs (with confirmation)
- Consider adding a "Re-add as New" option that copies the DVG data into a new active DVG (useful for recurring discounts)
- History can grow large -- use `LazyVStack` or `.searchable` for performance
- Date displayed: for "Used" show date marked used, for "Expired" show expiration date
