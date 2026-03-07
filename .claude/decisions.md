# Decisions Log - FastyDiscount

## [2026-02-23] - Project Initialization
**Decision**: Initialize as iOS native app project
**Rationale**: User specified iOS app for DVG management
**Made By**: Orchestrator

## [2026-03-01] - GitHub Remote Repository
**Decision**: Use https://github.com/Pssttcomau/FastyDiscount as the remote origin
**Rationale**: User provided this as the project repo (currently empty)
**Made By**: Orchestrator (from user input)

## [2026-03-02] - Plan Amendment: AppDestination naming
**Decision**: Task docs should use `.cameraScanner` (not `.scannerCapture`) and `.dvgCreate(.manual)` (not `.dvgForm(nil)`)
**Rationale**: Code-agent discovered actual enum cases differ from task spec references
**Original**: Task spec referenced `.scannerCapture` and `.dvgForm(nil)`
**Impact**: Documentation only; future task specs should use correct destination names
**Made By**: Orchestrator (from code-agent request)

## [2026-03-02] - Plan Amendment: DVGType.iconName
**Decision**: Added `DVGType.iconName` computed property extension in DVGCardView.swift
**Rationale**: Task spec referenced `DVGType.systemImageName` but no such property existed. Agent created `iconName` extension locally in DVGCardView.swift.
**Original**: Plan assumed `systemImageName` existed on DVGType
**Impact**: If more views need DVG type icons, consider moving extension to DVG.swift
**Made By**: Orchestrator (from code-opus-agent request)

## [2026-03-02] - Plan Amendment: PKBarcodeFormat unavailable on simulator
**Decision**: Use string-based `PassBarcodeFormat` enum for pass.json generation instead of `PKBarcodeFormat`
**Rationale**: `PKBarcodeFormat` is unavailable on iOS Simulator; string constants are functionally equivalent for pass.json
**Original**: Task spec referenced `PKBarcodeFormat.qr`, `.code128`, `.pdf417`, `.aztec` directly
**Impact**: PassKitService uses string-based format; works on simulator and device
**Made By**: Orchestrator (from code-opus-agent request, TASK-036)

## [2026-03-02] - Plan Amendment: CoreImage unavailable on watchOS
**Decision**: Use pure-Swift barcode rendering (QRCodeEncoder, Code128Encoder) instead of CIFilter on watchOS
**Rationale**: CoreImage module is not available on watchOS SDK — build fails with "Unable to find module dependency: 'CoreImage'"
**Original**: Task spec stated "CIFilter is available on watchOS; use CIQRCodeGenerator and CICode128BarcodeGenerator"
**Impact**: Watch barcode rendering uses SwiftUI Canvas with custom encoders; alternative is pre-rendered images synced from iPhone
**Made By**: Orchestrator (from code-opus-agent request, TASK-034)

## [2026-03-02] - Plan Amendment: DVGType.iconName moved to DVG.swift
**Decision**: Moved `DVGType.iconName` extension from DVGCardView.swift to DVG.swift
**Rationale**: Widget extension target includes Core/Models but not Features/Dashboard/Components. iconName needed in widget.
**Original**: iconName lived in DVGCardView.swift (main app target only)
**Impact**: iconName now available to all targets (widget, share extension, watch) that compile DVG.swift
**Made By**: Orchestrator (from code-opus-agent request, TASK-033)
