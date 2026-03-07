# TASK-038: Configure Mac Catalyst with menu bar, keyboard shortcuts, and drag-and-drop

## Description
Configure the Mac Catalyst build with native Mac affordances: menu bar items, keyboard shortcuts, window management, and drag-and-drop file import. Disable Mac-incompatible features (camera scanning, geofencing).

## Assigned Agent
code

## Priority & Complexity
- Priority: Low
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-005 (navigation architecture with adaptive layout)
- TASK-026 (dashboard view)
- TASK-027 (search view)

## Acceptance Criteria
- [ ] Mac Catalyst target enabled on the iOS app target
- [ ] `UIBehavioralStyle.mac` set for native Mac appearance
- [ ] Menu bar: File (New DVG, Import from Photo, Import PDF), Edit (standard), View (Show Dashboard, Show History, Show Settings)
- [ ] Keyboard shortcuts: Cmd+N (new DVG), Cmd+F (search), Cmd+, (settings), Cmd+I (import), Delete (delete DVG)
- [ ] Window minimum size: 800x600, default size: 1024x768
- [ ] Drag-and-drop: accept image and PDF files dropped onto the window (triggers import flow from TASK-018)
- [ ] Camera scanner tab replaced with "Import" view on Mac (photo picker + PDF picker)
- [ ] Geofencing/location features hidden on Mac (check `CLLocationManager.isMonitoringAvailable`)
- [ ] Sidebar navigation (NavigationSplitView) is the default layout on Mac
- [ ] Touch Bar support: show quick actions (New DVG, Search) if hardware supports it
- [ ] Mac icon configured in Assets.xcassets (macOS app icon set)

## Technical Notes
- Menu bar: use `.commands` modifier on `WindowGroup` with `CommandMenu` and `CommandGroup`
- Keyboard shortcuts: `.keyboardShortcut("n", modifiers: .command)` on buttons/menu items
- Drag-and-drop: use `.onDrop(of:)` modifier with `UTType.image` and `UTType.pdf`
- Window size: use `WindowGroup { }.defaultSize(width:height:)` (iOS 17+)
- Check `ProcessInfo.processInfo.isiOSAppOnMac` for Mac-specific code paths
- Camera: `AVCaptureDevice.default(for: .video) == nil` on Mac -- hide camera scanner
- Consider `#if targetEnvironment(macCatalyst)` for Mac-specific conditional compilation
