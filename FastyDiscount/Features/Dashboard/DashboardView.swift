import SwiftUI
import SwiftData

// MARK: - DashboardView

/// The main dashboard home screen displaying three sections:
/// - **Expiring Soon**: Horizontal scroll of DVGs expiring within 7 days.
/// - **Nearby**: Horizontal scroll of DVGs near the user's current location.
/// - **Recently Added**: Vertical list of the last 5 DVGs.
///
/// Features pull-to-refresh, quick action toolbar, adaptive layout for
/// iPhone (single column) and iPad (two-column grid), and per-section
/// empty states with a global empty state when no DVGs exist.
struct DashboardView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NavigationRouter.self) private var router
    @Environment(LocationPermissionManager.self) private var locationManager
    @Environment(MockAdMobService.self) private var adService

    // MARK: - State

    @State private var viewModel: DashboardViewModel?

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                dashboardContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            quickActionToolbar
        }
        .task {
            initializeViewModelIfNeeded()
            await viewModel?.loadAll()
        }
        .alert("Error", isPresented: alertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(viewModel: DashboardViewModel) -> some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            // First load: show centered progress
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading your discounts...")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasNoDVGs {
            overallEmptyState
        } else {
            scrollableContent(viewModel: viewModel)
        }
    }

    // MARK: - Scrollable Content

    @ViewBuilder
    private func scrollableContent(viewModel: DashboardViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                if horizontalSizeClass == .regular {
                    iPadLayout(viewModel: viewModel)
                } else {
                    iPhoneLayout(viewModel: viewModel)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .background(Theme.Colors.background)

            // Banner ad at the bottom of the Dashboard.
            // Hidden automatically when the user is ad-free.
            BannerAdView(
                adUnitID: AppConstants.AdMob.bannerAdUnitID,
                adService: adService
            )
        }
    }

    // MARK: - iPhone Layout (Single Column)

    @ViewBuilder
    private func iPhoneLayout(viewModel: DashboardViewModel) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Expiring Soon Section
            expiringSoonSection(viewModel: viewModel)

            // Nearby Section (hidden if location not authorized or no results)
            if viewModel.showNearbySection {
                nearbySection(viewModel: viewModel)
            }

            // Recently Added Section
            recentlyAddedSection(viewModel: viewModel)
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - iPad Layout (Two-Column Grid)

    @ViewBuilder
    private func iPadLayout(viewModel: DashboardViewModel) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Expiring Soon: full width horizontal scroll
            expiringSoonSection(viewModel: viewModel)

            // Two-column grid for Nearby and Recently Added
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                // Left column: Nearby (or empty spacer if hidden)
                if viewModel.showNearbySection {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        nearbySection(viewModel: viewModel)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Right column: Recently Added
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    recentlyAddedSection(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Expiring Soon Section

    @ViewBuilder
    private func expiringSoonSection(viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title: "Expiring Soon", systemImage: "clock.badge.exclamationmark") {
                // Navigate to search with an expiry range pre-set to the next 7 days.
                let now = Date()
                let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
                let filter = DVGFilter(
                    status: .active,
                    expiryDateFrom: now,
                    expiryDateTo: sevenDays
                )
                router.push(.search(filter))
            }

            if viewModel.expiringSoon.isEmpty {
                sectionEmptyState(
                    icon: "clock.badge.checkmark",
                    message: "No items expiring soon",
                    detail: "You're all caught up!"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.md) {
                        ForEach(viewModel.expiringSoon, id: \.id) { dvg in
                            Button {
                                router.push(.dvgDetail(dvg.id))
                            } label: {
                                DVGCardView(
                                    dvg: dvg,
                                    layoutMode: .compact,
                                    onToggleFavorite: { viewModel.toggleFavorite(dvg) }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
        }
    }

    // MARK: - Nearby Section

    @ViewBuilder
    private func nearbySection(viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title: "Nearby", systemImage: "location") {
                // Navigate to Nearby tab
                router.selectedTab = .nearby
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(viewModel.nearbyDVGs, id: \.id) { dvg in
                        Button {
                            router.push(.dvgDetail(dvg.id))
                        } label: {
                            DVGCardView(
                                dvg: dvg,
                                layoutMode: .compact,
                                distanceText: viewModel.nearbyDistances[dvg.id],
                                onToggleFavorite: { viewModel.toggleFavorite(dvg) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Recently Added Section

    @ViewBuilder
    private func recentlyAddedSection(viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title: "Recently Added", systemImage: "plus.circle") {
                router.push(.search(nil))
            }

            if viewModel.recentlyAdded.isEmpty {
                sectionEmptyState(
                    icon: "tray",
                    message: "No items yet",
                    detail: "Add your first discount to get started."
                )
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.recentlyAdded, id: \.id) { dvg in
                        Button {
                            router.push(.dvgDetail(dvg.id))
                        } label: {
                            DVGCardView(
                                dvg: dvg,
                                layoutMode: .row,
                                onToggleFavorite: { viewModel.toggleFavorite(dvg) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(
        title: String,
        systemImage: String,
        seeAllAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            Button {
                seeAllAction()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("See All")
                        .font(Theme.Typography.subheadline)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.Colors.primary)
            }
            .accessibilityLabel("See all \(title)")
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Section Empty State

    @ViewBuilder
    private func sectionEmptyState(icon: String, message: String, detail: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
                .accessibilityHidden(true)

            Text(message)
                .font(Theme.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .padding(.horizontal, Theme.Spacing.md)
        .cardStyle()
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). \(detail)")
    }

    // MARK: - Overall Empty State

    private var overallEmptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "tag.slash")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.primary.opacity(0.4))
                .accessibilityHidden(true)

            Text("Add your first discount!")
                .font(Theme.Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Scan a barcode, import from email, or add manually to keep all your discounts, vouchers, and gift cards in one place.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    router.push(.cameraScanner)
                } label: {
                    Label("Scan Barcode", systemImage: "camera.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .accessibilityLabel("Scan a barcode with the camera")

                Button {
                    router.push(.dvgCreate(.manual))
                } label: {
                    Label("Add Manually", systemImage: "plus.circle")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            Theme.Colors.primary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .stroke(Theme.Colors.primary.opacity(0.4), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Add a discount manually")
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    // MARK: - Quick Action Toolbar

    @ToolbarContentBuilder
    private var quickActionToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button {
                    router.push(.cameraScanner)
                } label: {
                    Label("Scan Barcode", systemImage: "camera.fill")
                }

                Button {
                    router.push(.dvgCreate(.manual))
                } label: {
                    Label("Add Manually", systemImage: "plus.circle")
                }

                Button {
                    router.push(.emailScan)
                } label: {
                    Label("Email Scan", systemImage: "envelope.open")
                }

                Button {
                    router.push(.importScan)
                } label: {
                    Label("Import Photo/PDF", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
                    .font(Theme.Typography.body)
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Add new discount")
            .accessibilityHint("Opens a menu with options to add a discount")
        }
    }

    // MARK: - Private Helpers

    /// Lazily creates the ViewModel on first access.
    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        let repository = SwiftDataDVGRepository(modelContext: modelContext)
        viewModel = DashboardViewModel(
            repository: repository,
            locationManager: locationManager
        )
    }

    /// Creates a binding for the error alert.
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showError ?? false },
            set: { newValue in viewModel?.showError = newValue }
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Dashboard") {
    NavigationStack {
        DashboardView()
    }
    .environment(NavigationRouter())
    .environment(LocationPermissionManager())
    .modelContainer(for: DVG.self, inMemory: true)
}
#endif
