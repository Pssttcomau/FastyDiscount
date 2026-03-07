# TASK-021: Implement expiry notification scheduling with UNUserNotificationCenter

## Description
Build the notification scheduling system that creates local notifications for DVGs based on their expiration date and user-configured lead time. Notifications are scheduled when DVGs are created/updated and cancelled when DVGs are used/deleted.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-007 (DVG model with expirationDate and notificationLeadDays)
- TASK-009 (DVGRepository)

## Acceptance Criteria
- [ ] `ExpiryNotificationService` protocol with `schedule(for:)`, `cancel(for:)`, `rescheduleAll()` methods
- [ ] Notification scheduled using `UNCalendarNotificationTrigger` based on `expirationDate - notificationLeadDays`
- [ ] Notification content: title = "DVG Expiring Soon", body = "{title} at {store} expires in {days} days"
- [ ] Notification identifier format: `expiry-{dvg.id}` for easy lookup and cancellation
- [ ] Notification category registered with action buttons (handled in TASK-022)
- [ ] `schedule(for:)` called automatically by repository after DVG save/update (if expiration date exists)
- [ ] `cancel(for:)` called when DVG is used, deleted, or archived
- [ ] `rescheduleAll()` recalculates all notifications (for app launch recovery or settings change)
- [ ] Skip scheduling if notification date is in the past
- [ ] Skip scheduling if global notifications are disabled (check UserDefaults)
- [ ] Permission request handled: request on first DVG with expiration date, not upfront

## Technical Notes
- `UNCalendarNotificationTrigger` uses `DateComponents` -- extract year, month, day, hour from the target date
- Default notification time: 9:00 AM on the notification day (configurable in future)
- iOS limits pending notifications to 64; if exceeding, prioritize by soonest expiry
- Notification identifier must be deterministic from DVG ID so we can cancel without tracking
- `rescheduleAll()` should: remove all `expiry-*` notifications, then schedule for all active DVGs with expiration dates
- Consider a `NotificationPermissionManager` that handles the first-time permission request flow
