# TASK-027: Build search view with text search, type/status/tag filters, and smart sorting

## Description
Build a comprehensive search and filter view that allows users to find DVGs by text query and narrow results using filters (type, status, tag, expiry range). Supports multiple sort orders and displays results in a list with real-time updating.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-009 (DVGRepository.search())
- TASK-007 (DVG model)
- TASK-008 (Tag model for tag filter)
- TASK-006 (theme system)
- TASK-010 (DVG detail for navigation)

## Acceptance Criteria
- [ ] Search bar with real-time text filtering (searches title, storeName, code, notes)
- [ ] Filter chips/pills below search bar: type (multi-select), status, tag, expiry range
- [ ] Type filter: checkboxes for each DVGType (discountCode, voucher, giftCard, loyaltyPoints, barcodeCoupon)
- [ ] Status filter: Active, Used, Expired, Archived
- [ ] Tag filter: show all tags (system + custom), multi-select
- [ ] Expiry range filter: date range picker (from date - to date)
- [ ] Sort picker: by expiry date (soonest), by value (highest), by date added (newest), alphabetical
- [ ] Results displayed in scrollable list with DVG row component (title, store, type icon, expiry, favorite)
- [ ] Active filter indicators: show count of active filters, "Clear All" button
- [ ] Empty search state: "No results found" with suggestion to adjust filters
- [ ] Debounced search input (300ms delay before querying)
- [ ] `@Observable` `SearchViewModel` managing query, filters, sort, and results

## Technical Notes
- Use `.searchable` modifier for the search bar
- Filter UI: use a collapsible filter bar or a filter sheet accessible via filter icon
- Debounce: use `Task.sleep(for: .milliseconds(300))` with cancellation on new input
- The `DVGRepository.search(query:filters:sort:)` handles the actual querying
- Consider a `DVGFilter` struct: `types: Set<DVGType>`, `statuses: Set<DVGStatus>`, `tagIDs: Set<UUID>`, `expiryFrom: Date?`, `expiryTo: Date?`
- Sort enum: `DVGSortOrder` with cases `expiryAsc`, `valueDesc`, `dateAddedDesc`, `alphabetical`
- Swipe actions on list rows: favorite, mark used, delete
