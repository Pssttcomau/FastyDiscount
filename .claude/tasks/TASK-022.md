# TASK-022: Implement notification action handlers (View Code, Mark Used, Snooze)

## Description
Register notification categories with actionable buttons and implement the handlers for each action. When a user interacts with a notification, the app should perform the requested action (navigate to DVG, mark as used, or snooze the reminder).

## Assigned Agent
code

## Priority & Complexity
- Priority: Medium
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-021 (expiry notification scheduling -- provides notification category)
- TASK-009 (DVGRepository for status updates)
- TASK-005 (navigation router for deep-linking to DVG detail)

## Acceptance Criteria
- [ ] `UNNotificationCategory` registered with identifier `dvg-expiry` and `dvg-location`
- [ ] Action: "View Code" (`view-code`) -- opens the app and navigates to DVG detail view
- [ ] Action: "Mark as Used" (`mark-used`) -- updates DVG status to `.used` without opening the app
- [ ] Action: "Snooze" (`snooze`) -- reschedules notification for +1 day
- [ ] `UNUserNotificationCenterDelegate` implemented in `AppDelegate` or app entry point
- [ ] `userNotificationCenter(_:didReceive:withCompletionHandler:)` handles action routing
- [ ] DVG ID passed in notification's `userInfo` dictionary for action handlers to retrieve the correct DVG
- [ ] "Mark as Used" works even when app is terminated (background handler)
- [ ] "View Code" uses deep link (`fastydiscount://dvg/{id}`) to navigate within the app
- [ ] Notification actions work for both expiry and location notification categories

## Technical Notes
- Register categories in `application(_:didFinishLaunchingWithOptions:)` or app's `init`
- `UNNotificationAction` options: `.foreground` for "View Code" (launches app), `.destructive` for "Mark Used" (no launch needed)
- "Snooze" action: cancel current notification, schedule new one with trigger date = now + 24 hours
- Store `dvg-id` in `UNMutableNotificationContent.userInfo["dvgID"]`
- For background actions ("Mark as Used"): must complete within the notification handling time limit (~30 seconds)
- Use same action identifiers for both expiry and location categories
