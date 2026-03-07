# TASK-013: Build Gmail API client for fetching emails by label/sender scope

## Description
Implement the Gmail REST API client that fetches emails based on user-configured scope (specific labels, sender whitelist, or full inbox). The client handles pagination, email content decoding (base64), and returns structured raw email data ready for AI parsing.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-012 (Gmail OAuth authentication and token management)

## Acceptance Criteria
- [ ] `GmailAPIClient` that uses authenticated access token from `GmailAuthService`
- [ ] `fetchEmails(scope:maxResults:pageToken:)` method supporting label filter, sender whitelist, date range
- [ ] Email content decoded from Gmail's base64url encoding to plain text
- [ ] Both `text/plain` and `text/html` parts extracted; HTML stripped to plain text for AI parsing
- [ ] Pagination support via `nextPageToken` for large result sets
- [ ] `RawEmail` struct returned: id, subject, sender, date, bodyText, bodyHTML, snippet
- [ ] `EmailScanScope` model: selectedLabels, senderWhitelist, scanFullInbox, sinceDate
- [ ] Rate limiting respected (Gmail API quota: 250 quota units per user per second)
- [ ] Automatic access token refresh on 401 response (delegate to `GmailAuthService`)
- [ ] Errors: `GmailAPIError` with cases for auth failure, quota exceeded, not found, server error

## Technical Notes
- Gmail API list endpoint: `GET https://gmail.googleapis.com/gmail/v1/users/me/messages?q={query}&labelIds={labels}`
- Gmail API get endpoint: `GET https://gmail.googleapis.com/gmail/v1/users/me/messages/{id}?format=full`
- Query syntax for labels: `label:CATEGORY_PROMOTIONS` or `label:{custom_label}`
- Query syntax for senders: `from:store@example.com`
- Email body is in `payload.parts[].body.data` (base64url encoded)
- Strip HTML using a simple regex or `NSAttributedString(data:options:documentAttributes:)` with `.html` option
- Default label for promotions tab: `CATEGORY_PROMOTIONS`
- Consider fetching in batches of 20 to provide progress updates
