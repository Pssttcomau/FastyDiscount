import SwiftUI
import SwiftData

// MARK: - AdaptiveNavigationView

/// The root navigation container that adapts its layout to the current
/// device form factor:
///
/// - **iPhone (compact width):** `TabView` with a `NavigationStack` per tab.
/// - **iPad / Mac (regular width):** `NavigationSplitView` with a sidebar
///   listing tab items, and a detail area showing the selected tab's content.
///
/// Both layouts share the same `NavigationRouter` for programmatic navigation
/// and deep link handling.
struct AdaptiveNavigationView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        if horizontalSizeClass == .compact {
            CompactNavigationView()
        } else {
            RegularNavigationView()
        }
    }
}

// MARK: - CompactNavigationView (iPhone)

/// iPhone layout: standard `TabView` with a `NavigationStack` per tab.
/// Each tab's navigation stack is bound to the router's per-tab path
/// so programmatic navigation and deep links work correctly.
private struct CompactNavigationView: View {
    @Environment(NavigationRouter.self) private var router

    /// Count of `ScanResult` items that still need human review,
    /// displayed as a badge on the Scan tab.
    @Query(filter: #Predicate<ScanResult> { $0.needsReview == true && $0.isDeleted == false })
    private var pendingReviewItems: [ScanResult]

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ForEach(AppState.AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack(path: navigationPathBinding(for: tab)) {
                        TabRootView(tab: tab)
                            .navigationDestination(for: AppDestination.self) { destination in
                                DestinationView(destination: destination)
                            }
                    }
                }
                .badge(tab == .scan ? pendingReviewItems.count : 0)
            }
        }
    }

    private func navigationPathBinding(for tab: AppState.AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { router.path(for: tab) },
            set: { router.setPath($0, for: tab) }
        )
    }
}

// MARK: - RegularNavigationView (iPad / Mac)

/// iPad and Mac layout: `NavigationSplitView` with a sidebar of tab items,
/// and a detail area that shows the selected tab's content in a
/// `NavigationStack`.
private struct RegularNavigationView: View {
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            SidebarView(selection: $router.selectedTab)
        } detail: {
            NavigationStack(path: detailPathBinding) {
                TabRootView(tab: router.selectedTab)
                    .navigationDestination(for: AppDestination.self) { destination in
                        DestinationView(destination: destination)
                    }
            }
        }
    }

    private var detailPathBinding: Binding<NavigationPath> {
        Binding(
            get: { router.path(for: router.selectedTab) },
            set: { router.setPath($0, for: router.selectedTab) }
        )
    }
}

// MARK: - SidebarView

/// The sidebar for iPad/Mac showing all tabs as selectable list items.
/// Uses manual selection handling since `List(selection:)` is unavailable
/// on iOS 26.
private struct SidebarView: View {
    @Binding var selection: AppState.AppTab

    var body: some View {
        List {
            ForEach(AppState.AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .listRowBackground(
                    tab == selection
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .foregroundStyle(tab == selection ? Color.accentColor : .primary)
            }
        }
        .navigationTitle("FastyDiscount")
        .listStyle(.sidebar)
    }
}

// MARK: - TabRootView

/// Placeholder root view for each tab. These will be replaced with real
/// feature views in later tasks (Phase 6).
struct TabRootView: View {
    let tab: AppState.AppTab

    var body: some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .nearby:
            NearbyPlaceholderView()
        case .scan:
            ScanPlaceholderView()
        case .history:
            HistoryPlaceholderView()
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

// MARK: - DestinationView

/// Routes an `AppDestination` to its corresponding view.
/// Placeholder implementations are provided for now; real views will
/// be implemented in later tasks.
struct DestinationView: View {
    let destination: AppDestination

    var body: some View {
        switch destination {
        case .dvgDetail(let id):
            DVGDetailView(dvgID: id)
        case .dvgEdit(let id):
            DVGEditDestinationView(dvgID: id)
        case .dvgCreate(let source):
            DVGFormView(mode: .create(source), isEmbedded: true)
        case .emailScan:
            EmailScanView()
        case .emailScanResults:
            EmailScanView()
        case .reviewQueue:
            ReviewQueueView()
        case .tagManager:
            Text("Tag Manager")
                .navigationTitle("Tags")
        case .storeLocationPicker(let id):
            Text("Store Location Picker: \(id.uuidString)")
                .navigationTitle("Pick Location")
        case .cameraScanner:
            CameraScannerView()
        case .textOCR:
            Text("Text OCR Scanner")
                .navigationTitle("Text OCR")
        case .importScan:
            ImportView()
        case .scanResults(let inputData):
            ScanResultsView(inputData: inputData)
        case .search(let initialFilter):
            SearchView(initialFilter: initialFilter)
        }
    }
}

// MARK: - DVGEditDestinationView

/// A helper view that fetches a DVG by UUID from SwiftData and presents
/// the `DVGFormView` in edit mode. Shows "Item Not Found" if the DVG
/// cannot be located (e.g., it was deleted).
private struct DVGEditDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    let dvgID: UUID

    @State private var dvg: DVG?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let dvg {
                DVGFormView(mode: .edit(dvg), isEmbedded: true)
            } else if didLoad {
                ContentUnavailableView(
                    "Item Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This item could not be found for editing.")
                )
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            loadDVG()
        }
    }

    private func loadDVG() {
        guard !didLoad else { return }

        let id = dvgID
        let descriptor = FetchDescriptor<DVG>(
            predicate: #Predicate<DVG> { $0.id == id && $0.isDeleted == false }
        )

        dvg = try? modelContext.fetch(descriptor).first
        didLoad = true
    }
}

// MARK: - Placeholder Tab Views

/// Placeholder views for each tab. These are simple text views that will
/// be replaced with full feature implementations in Phase 6.

private struct NearbyPlaceholderView: View {
    var body: some View {
        Text("Nearby")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .navigationTitle("Nearby")
    }
}

private struct ScanPlaceholderView: View {
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.primary)

            Text("Scan Barcodes & QR Codes")
                .font(Theme.Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Use your camera to scan discount barcodes, QR codes, and coupons — or import from a photo or PDF.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            // Camera scanner button
            Button {
                router.push(.cameraScanner)
            } label: {
                Label("Open Camera Scanner", systemImage: "camera.fill")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .accessibilityLabel("Open barcode scanner")
            .accessibilityHint("Opens the camera to scan barcodes and QR codes")
            .padding(.horizontal, Theme.Spacing.lg)

            // Import from photo or PDF button
            Button {
                router.push(.importScan)
            } label: {
                Label("Import Photo or PDF", systemImage: "square.and.arrow.down")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .stroke(Theme.Colors.primary.opacity(0.4), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Import from photo or PDF")
            .accessibilityHint("Opens the import screen to extract barcodes from a photo or PDF document")
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .navigationTitle("Scan")
    }
}

private struct HistoryPlaceholderView: View {
    var body: some View {
        Text("History")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .navigationTitle("History")
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Settings")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .navigationTitle("Settings")
    }
}
