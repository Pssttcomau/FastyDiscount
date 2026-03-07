# TASK-002: Configure SwiftData models with CloudKit sync and App Group shared container

## Description
Set up the SwiftData ModelContainer with CloudKit sync enabled, shared across main app, widget, share extension, and watch extension via App Group. Establish the CloudKit-compatible model schema configuration and merge policy. This task creates the container infrastructure only -- model definitions are in TASK-007 and TASK-008.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-001 (project structure and App Group entitlements)

## Acceptance Criteria
- [ ] `ModelContainer` configured with `ModelConfiguration` pointing to App Group shared directory
- [ ] CloudKit sync enabled via `.cloudKitDatabase(.automatic)` on the configuration
- [ ] `ModelContainer` instantiated in `FastyDiscountApp.swift` and injected via `.modelContainer()`
- [ ] Shared `ModelContainer` factory method accessible to widget and share extension targets
- [ ] Server-wins merge policy configured for conflict resolution
- [ ] CloudKit schema initialization handled (first-launch schema push)
- [ ] Container creation errors handled gracefully with user-facing error state

## Technical Notes
- The shared container path: `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.fastydiscount.shared")`
- Use a static factory: `ModelContainerFactory.shared` that returns the same configuration across targets
- For widget/share extension: use a lightweight read-only container if needed to reduce memory
- CloudKit sync requires the user to be signed into iCloud; handle the not-signed-in case
- The actual `@Model` classes are defined in TASK-007 and TASK-008; this task uses placeholder models to verify container setup
