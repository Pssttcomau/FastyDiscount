import SwiftUI
import SwiftData

// MARK: - HistoryView

/// History tab view showing DVGs in used, expired, or archived status.
///
/// Features:
/// - Segmented control for filtering: All, Used, Expired, Archived
/// - Searchable list with per-segment empty states
/// - Each row shows title, store, type icon, status badge, and status-change date
/// - Swipe actions: Reactivate (back to active) and Permanently Delete (hard delete)
/// - "Clear All" button per segment with confirmation dialog
/// - Tapping a row navigates to DVGDetailView (read-only)
struct HistoryView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(MockAdMobService.self) private var adService

    // MARK: - State

    @State private var viewModel: HistoryViewModel?

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                historyContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .task {
            initializeViewModelIfNeeded()
            await viewModel?.load()
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func historyContent(viewModel: HistoryViewModel) -> some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Segmented control
            segmentedControl(viewModel: viewModel)

            // List with search
            listContent(viewModel: viewModel)
                .searchable(
                    text: $vm.searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search history"
                )

            // Banner ad at the bottom of the History view.
            // Hidden automatically when the user is ad-free.
            BannerAdView(
                adUnitID: AppConstants.AdMob.bannerAdUnitID,
                adService: adService
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.filteredDVGs.isEmpty {
                    Button(viewModel.selectedFilter.clearAllTitle) {
                        viewModel.showClearAllConfirmation = true
                    }
                    .foregroundStyle(Theme.Colors.error)
                }
            }
        }
        .confirmationDialog(
            viewModel.selectedFilter.clearAllTitle,
            isPresented: $vm.showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await viewModel.clearAll() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(viewModel.selectedFilter.clearAllMessage)
        }
        .confirmationDialog(
            "Permanently Delete?",
            isPresented: $vm.showPermanentDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task { await viewModel.confirmPermanentDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteDVG = nil
            }
        } message: {
            if let dvg = viewModel.pendingDeleteDVG {
                Text("Permanently delete \"\(dvg.title.isEmpty ? "this item" : dvg.title)\"? This cannot be undone.")
            } else {
                Text("This item will be permanently deleted. This cannot be undone.")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Segmented Control

    private func segmentedControl(viewModel: HistoryViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(HistoryFilter.allCases) { filter in
                    filterChip(
                        filter: filter,
                        isSelected: viewModel.selectedFilter == filter,
                        viewModel: viewModel
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Colors.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func filterChip(
        filter: HistoryFilter,
        isSelected: Bool,
        viewModel: HistoryViewModel
    ) -> some View {
        Button {
            viewModel.selectedFilter = filter
        } label: {
            Text(filter.displayName)
                .font(Theme.Typography.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs + 2)
                .background(
                    isSelected
                        ? Theme.Colors.primary
                        : Theme.Colors.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : Theme.Colors.border,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.displayName) filter")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - List Content

    @ViewBuilder
    private func listContent(viewModel: HistoryViewModel) -> some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isEmpty {
            emptyState(for: viewModel.selectedFilter)
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.filteredDVGs, id: \.id) { dvg in
                        historyRow(dvg: dvg, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    // MARK: - History Row

    private func historyRow(dvg: DVG, viewModel: HistoryViewModel) -> some View {
        Button {
            router.push(.dvgDetail(dvg.id))
        } label: {
            HistoryRowView(dvg: dvg)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await viewModel.reactivate(dvg) }
            } label: {
                Label("Reactivate", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(Theme.Colors.success)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.requestPermanentDelete(dvg)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityHint("Tap to view details. Swipe left to delete, swipe right to reactivate.")
    }

    // MARK: - Empty State

    private func emptyState(for filter: HistoryFilter) -> some View {
        ContentUnavailableView(
            filter.emptyStateMessage,
            systemImage: filter.emptyStateIcon,
            description: Text(filter.emptyStateDescription)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Private Helpers

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        let repository = SwiftDataDVGRepository(modelContext: modelContext)
        viewModel = HistoryViewModel(
            repository: repository,
            modelContext: modelContext
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showError ?? false },
            set: { viewModel?.showError = $0 }
        )
    }
}

// MARK: - HistoryRowView

/// A single row in the History list.
///
/// Shows: type icon circle, title, store name, status badge (color-coded),
/// and the relevant date (usedDate for used, expirationDate for expired,
/// lastModified for archived).
struct HistoryRowView: View {
    let dvg: DVG

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Type icon circle
            typeIconCircle

            // Main content
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(dvg.title.isEmpty ? "Untitled" : dvg.title)
                    .font(Theme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if !dvg.storeName.isEmpty {
                    Text(dvg.storeName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Right side: status badge + date
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                statusBadge

                Text(statusDateLabel)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.Colors.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var typeIconCircle: some View {
        Image(systemName: dvg.dvgTypeEnum.iconName)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.primary)
            .frame(width: 40, height: 40)
            .background(Theme.Colors.primary.opacity(0.12))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    /// Color-coded status badge.
    /// Used = blue, Expired = red, Archived = gray.
    @ViewBuilder
    private var statusBadge: some View {
        Text(dvg.statusEnum.displayName)
            .font(Theme.Typography.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusBadgeColor, in: Capsule())
            .accessibilityHidden(true)
    }

    private var statusBadgeColor: Color {
        switch dvg.statusEnum {
        case .used:     return .blue
        case .expired:  return Theme.Colors.error
        case .archived: return .gray
        case .active:   return Theme.Colors.success
        }
    }

    /// Returns the most appropriate date label for the DVG status.
    ///
    /// - Used: show `lastModified` (when it was marked used)
    /// - Expired: show `expirationDate` if available, otherwise `lastModified`
    /// - Archived: show `lastModified` (when it was archived)
    private var statusDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        switch dvg.statusEnum {
        case .used, .archived:
            return formatter.string(from: dvg.lastModified)
        case .expired:
            if let expiryDate = dvg.expirationDate {
                return "Expired \(formatter.string(from: expiryDate))"
            }
            return formatter.string(from: dvg.lastModified)
        case .active:
            return formatter.string(from: dvg.lastModified)
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []

        parts.append(dvg.title.isEmpty ? "Untitled item" : dvg.title)

        if !dvg.storeName.isEmpty {
            parts.append("at \(dvg.storeName)")
        }

        parts.append(dvg.dvgTypeEnum.displayName)
        parts.append("Status: \(dvg.statusEnum.displayName)")
        parts.append(statusDateLabel)

        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("HistoryView") {
    let schema = Schema([DVG.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    let context = container.mainContext

    // Insert sample history items
    let used = DVG(
        title: "20% Off Storewide",
        code: "SAVE20",
        dvgType: .discountCode,
        storeName: "TechStore",
        originalValue: 20.0,
        status: .used,
        lastModified: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
    )
    let expired = DVG(
        title: "Free Shipping Voucher",
        code: "SHIP2024",
        dvgType: .voucher,
        storeName: "FashionHub",
        originalValue: 15.0,
        expirationDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
        status: .expired,
        lastModified: Calendar.current.date(byAdding: .day, value: -5, to: Date())!
    )
    let archived = DVG(
        title: "Gift Card",
        dvgType: .giftCard,
        storeName: "BookWorld",
        originalValue: 50.0,
        status: .archived,
        isDeleted: true,
        lastModified: Calendar.current.date(byAdding: .day, value: -10, to: Date())!
    )

    context.insert(used)
    context.insert(expired)
    context.insert(archived)

    return NavigationStack {
        HistoryView()
    }
    .environment(NavigationRouter())
    .modelContainer(container)
}
#endif
