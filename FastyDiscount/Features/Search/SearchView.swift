import SwiftUI
import SwiftData

// MARK: - SearchView

/// Full-screen search view with real-time text filtering, multi-select type/status
/// filters, tag filter, expiry date range, and configurable sort order.
///
/// Results are displayed using the existing `DVGCardView(.row)` layout.
/// Swipe actions on rows allow marking as used, toggling favourite, and deleting.
///
/// The view is presented as a pushed `AppDestination.search` navigation destination
/// from anywhere in the app (e.g. the dashboard "See All" buttons).
struct SearchView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(MockAdMobService.self) private var adService

    // MARK: - State

    @State private var viewModel: SearchViewModel?
    @State private var isFilterSheetPresented: Bool = false

    // MARK: - Properties

    /// Optional initial filter to pre-populate from a "See All" entry point.
    let initialFilter: DVGFilter?

    // MARK: - Init

    init(initialFilter: DVGFilter? = nil) {
        self.initialFilter = initialFilter
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                searchContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .task {
            initializeViewModelIfNeeded()
            await viewModel?.onAppear()
        }
        .alert("Error", isPresented: alertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func searchContent(viewModel: SearchViewModel) -> some View {
        VStack(spacing: 0) {
            // Active filter summary bar
            if viewModel.hasActiveFilters {
                activeFiltersBar(viewModel: viewModel)
            }

            // Results list
            resultsList(viewModel: viewModel)

            // Banner ad at the bottom of the Search view.
            // Hidden automatically when the user is ad-free.
            BannerAdView(
                adUnitID: AppConstants.AdMob.bannerAdUnitID,
                adService: adService
            )
        }
        .searchable(
            text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.searchQuery = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search by title, store, code, or notes"
        )
        .toolbar {
            searchToolbar(viewModel: viewModel)
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            FilterSheet(viewModel: viewModel)
        }
    }

    // MARK: - Active Filters Bar

    @ViewBuilder
    private func activeFiltersBar(viewModel: SearchViewModel) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Theme.Colors.primary)
                .font(Theme.Typography.subheadline)

            Text("\(viewModel.activeFilterCount) filter\(viewModel.activeFilterCount == 1 ? "" : "s") active")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Button("Clear All") {
                viewModel.clearAllFilters()
            }
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.primary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Results List

    @ViewBuilder
    private func resultsList(viewModel: SearchViewModel) -> some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.results.isEmpty {
            emptyState(viewModel: viewModel)
        } else {
            List {
                ForEach(viewModel.results, id: \.id) { dvg in
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
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xs,
                        leading: Theme.Spacing.md,
                        bottom: Theme.Spacing.xs,
                        trailing: Theme.Spacing.md
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.delete(dvg)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            viewModel.markAsUsed(dvg)
                        } label: {
                            Label("Mark Used", systemImage: "checkmark.circle")
                        }
                        .tint(Theme.Colors.success)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            viewModel.toggleFavorite(dvg)
                        } label: {
                            Label(
                                dvg.isFavorite ? "Unfavourite" : "Favourite",
                                systemImage: dvg.isFavorite ? "heart.slash" : "heart.fill"
                            )
                        }
                        .tint(.pink)
                    }
                }
            }
            .listStyle(.plain)
            .background(Theme.Colors.background)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(viewModel: SearchViewModel) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))

            VStack(spacing: Theme.Spacing.sm) {
                Text("No Results Found")
                    .font(Theme.Typography.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if viewModel.searchQuery.isEmpty && !viewModel.hasActiveFilters {
                    Text("Search for discounts, vouchers, gift cards, and more.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                } else {
                    Text("Try adjusting your search query or filters.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)

                    if viewModel.hasActiveFilters {
                        Button("Clear Filters") {
                            viewModel.clearAllFilters()
                        }
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.primary)
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func searchToolbar(viewModel: SearchViewModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Sort picker
            Menu {
                ForEach(DVGSortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.displayName)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .accessibilityLabel("Sort options")
            }

            // Filter button with badge
            Button {
                isFilterSheetPresented = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .accessibilityLabel("Filters")

                    if viewModel.activeFilterCount > 0 {
                        Text("\(viewModel.activeFilterCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Theme.Colors.primary, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .accessibilityLabel(viewModel.activeFilterCount > 0
                ? "Filters (\(viewModel.activeFilterCount) active)"
                : "Filters"
            )
        }
    }

    // MARK: - Private Helpers

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        let repository = SwiftDataDVGRepository(modelContext: modelContext)
        viewModel = SearchViewModel(
            repository: repository,
            modelContext: modelContext,
            initialFilter: initialFilter
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showError ?? false },
            set: { newValue in viewModel?.showError = newValue }
        )
    }
}

// MARK: - FilterSheet

/// Bottom sheet for configuring type, status, tag, and expiry date range filters.
private struct FilterSheet: View {

    @Environment(\.dismiss) private var dismiss
    var viewModel: SearchViewModel

    var body: some View {
        NavigationStack {
            Form {
                // Type multi-select
                Section {
                    ForEach(DVGType.allCases, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedTypes.contains(type) },
                            set: { isOn in
                                if isOn {
                                    viewModel.selectedTypes.insert(type)
                                } else {
                                    viewModel.selectedTypes.remove(type)
                                }
                            }
                        )) {
                            Label(type.displayName, systemImage: type.iconName)
                        }
                        .tint(Theme.Colors.primary)
                    }
                } header: {
                    Text("Type")
                }

                // Status multi-select
                Section {
                    ForEach(DVGStatus.allCases, id: \.self) { status in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedStatuses.contains(status) },
                            set: { isOn in
                                if isOn {
                                    viewModel.selectedStatuses.insert(status)
                                } else {
                                    viewModel.selectedStatuses.remove(status)
                                }
                            }
                        )) {
                            Text(status.displayName)
                        }
                        .tint(Theme.Colors.primary)
                    }
                } header: {
                    Text("Status")
                }

                // Tag filter
                if !viewModel.availableTags.isEmpty {
                    Section {
                        // "All tags" option
                        Button {
                            viewModel.selectedTagName = nil
                        } label: {
                            HStack {
                                Text("All Tags")
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                if viewModel.selectedTagName == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.primary)
                                }
                            }
                        }

                        ForEach(viewModel.availableTags, id: \.id) { tag in
                            Button {
                                viewModel.selectedTagName = tag.name
                            } label: {
                                HStack {
                                    if let hex = tag.colorHex {
                                        Circle()
                                            .fill(Color(hex: hex) ?? Theme.Colors.primary)
                                            .frame(width: 10, height: 10)
                                    }

                                    Text(tag.name)
                                        .foregroundStyle(Theme.Colors.textPrimary)

                                    Spacer()

                                    if viewModel.selectedTagName == tag.name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.Colors.primary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Tag")
                    }
                }

                // Expiry date range
                Section {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { viewModel.expiryDateFrom ?? Date() },
                            set: { viewModel.expiryDateFrom = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .disabled(false)

                    if viewModel.expiryDateFrom != nil {
                        Button("Clear From Date") {
                            viewModel.expiryDateFrom = nil
                        }
                        .foregroundStyle(Theme.Colors.error)
                    }

                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { viewModel.expiryDateTo ?? Date() },
                            set: { viewModel.expiryDateTo = $0 }
                        ),
                        displayedComponents: .date
                    )

                    if viewModel.expiryDateTo != nil {
                        Button("Clear To Date") {
                            viewModel.expiryDateTo = nil
                        }
                        .foregroundStyle(Theme.Colors.error)
                    }
                } header: {
                    Text("Expiry Date Range")
                } footer: {
                    Text("Filter items expiring within the selected date range.")
                        .font(Theme.Typography.caption)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        viewModel.clearAllFilters()
                    }
                    .foregroundStyle(Theme.Colors.error)
                    .disabled(!viewModel.hasActiveFilters)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Color from Hex

private extension Color {
    /// Creates a `Color` from a hex string such as `"#FF6B35"` or `"FF6B35"`.
    /// Returns `nil` if the string cannot be parsed.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SearchView") {
    NavigationStack {
        SearchView()
    }
    .environment(NavigationRouter())
    .modelContainer(for: [DVG.self, Tag.self], inMemory: true)
}

#Preview("SearchView - With Initial Filter") {
    NavigationStack {
        SearchView(initialFilter: DVGFilter(status: .active))
    }
    .environment(NavigationRouter())
    .modelContainer(for: [DVG.self, Tag.self], inMemory: true)
}
#endif
