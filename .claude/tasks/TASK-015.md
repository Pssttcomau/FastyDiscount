# TASK-015: Build email scan UI with progress tracking and scope settings

## Description
Create the email scan feature UI including: Gmail connection status, scan scope configuration (labels, senders), the "Scan Inbox" action with real-time progress, and results summary. This is the primary user-facing interface for the email integration feature.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-012 (Gmail auth)
- TASK-013 (Gmail API client)
- TASK-014 (email parsing pipeline)
- TASK-006 (theme system)

## Acceptance Criteria
- [ ] Email connection section showing Gmail account status (connected/disconnected) with connect/disconnect buttons
- [ ] Scan scope settings: label picker, sender whitelist editor, full inbox toggle
- [ ] "Scan Inbox" button triggers the full pipeline (fetch emails -> parse -> save)
- [ ] Progress view showing: current email index / total, per-email status (parsing/done/failed), overall progress bar
- [ ] Results summary after scan: X DVGs found, Y auto-saved, Z need review
- [ ] "View Review Queue" button navigates to review queue (TASK-016)
- [ ] Error states: no API key configured, no Gmail connected, network error, AI API error
- [ ] `@Observable` `EmailScanViewModel` managing the full flow state
- [ ] Cancel button to abort in-progress scan

## Technical Notes
- The scan is a multi-step async operation; use the `AsyncStream<EmailParseProgress>` from TASK-014
- Scope settings can be a separate section or sheet; persist in UserDefaults
- Gmail label list can be fetched from Gmail API `labels.list` endpoint to populate picker
- Show a gentle warning when selecting "Full Inbox" (privacy/speed concern)
- The progress view should not block the entire app -- consider running in a sheet or dedicated view
