import SwiftUI
import SwiftData
import MapKit

// MARK: - NearbyMapView

/// Full-screen map view showing store pins for all active DVGs with store locations.
///
/// Features:
/// - Custom annotation pins colored by DVG type with SF Symbol icons
/// - Search bar overlay to filter stores by name
/// - User location re-center button
/// - Summary card sheet when a pin is tapped (store name, address, distance, DVG list)
/// - Location permission handling (shows `LocationPermissionView` if not authorized)
/// - Empty state when no DVGs have store locations
///
/// On iPad, the summary card appears as a sidebar panel via `.presentationDetents`.
struct NearbyMapView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NavigationRouter.self) private var router
    @Environment(LocationPermissionManager.self) private var locationManager

    // MARK: - State

    @State private var viewModel: NearbyMapViewModel?

    /// Controls presentation of the summary card sheet.
    @State private var showSummaryCard: Bool = false

    // MARK: - Body

    var body: some View {
        Group {
            if !isLocationAuthorized {
                locationPermissionContent
            } else if let viewModel {
                mapContent(viewModel: viewModel)
            } else {
                ProgressView("Loading map...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Nearby")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            initializeViewModelIfNeeded()
            await viewModel?.loadAnnotations()
        }
    }

    // MARK: - Location Authorization Check

    private var isLocationAuthorized: Bool {
        let state = locationManager.authorizationState
        return state == .whenInUse || state == .always
    }

    // MARK: - Location Permission Content

    @ViewBuilder
    private var locationPermissionContent: some View {
        @Bindable var permManager = locationManager

        switch locationManager.authorizationState {
        case .notDetermined:
            // Show explanation and prompt
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                Image(systemName: "location.circle.fill")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.primary.opacity(0.6))
                    .accessibilityHidden(true)

                Text("Enable Location to See Nearby Stores")
                    .font(Theme.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Allow location access to discover discounts, vouchers, and gift cards available at stores near you.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)

                Button {
                    locationManager.requestWhenInUsePermission()
                } label: {
                    Label("Enable Location", systemImage: "location.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
            .sheet(isPresented: $permManager.showWhenInUseExplanation) {
                LocationPermissionView(step: .whenInUse, permissionManager: locationManager)
            }

        case .denied, .restricted:
            DeniedLocationView(permissionManager: locationManager)

        default:
            // Should not reach here since isLocationAuthorized handles whenInUse/always
            EmptyView()
        }
    }

    // MARK: - Map Content

    @ViewBuilder
    private func mapContent(viewModel: NearbyMapViewModel) -> some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Finding nearby stores...")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.showEmptyState {
            emptyState
        } else {
            mapWithOverlays(viewModel: viewModel)
        }
    }

    // MARK: - Map with Overlays

    @ViewBuilder
    private func mapWithOverlays(viewModel: NearbyMapViewModel) -> some View {
        @Bindable var vm = viewModel

        ZStack(alignment: .top) {
            // Full-screen map
            Map(position: $vm.cameraPosition) {
                // User location
                UserAnnotation()

                // Store annotations
                ForEach(viewModel.filteredAnnotations) { annotation in
                    Annotation(
                        annotation.name,
                        coordinate: annotation.coordinate,
                        anchor: .bottom
                    ) {
                        storePin(for: annotation, viewModel: viewModel)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)

            // Search bar overlay
            searchBarOverlay(viewModel: viewModel)

            // Bottom-trailing controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    userLocationButton(viewModel: viewModel)
                }
                .padding(.trailing, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .sheet(isPresented: $showSummaryCard, onDismiss: {
            viewModel.deselectAnnotation()
        }) {
            if let selected = viewModel.selectedAnnotation {
                StoreSummaryCard(annotation: selected) { dvgID in
                    showSummaryCard = false
                    viewModel.deselectAnnotation()
                    router.push(.dvgDetail(dvgID))
                } onDirections: {
                    viewModel.openDirections(to: selected)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .alert("Error", isPresented: alertBinding(viewModel: viewModel)) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Store Pin

    @ViewBuilder
    private func storePin(for annotation: StoreAnnotation, viewModel: NearbyMapViewModel) -> some View {
        let isSelected = viewModel.selectedAnnotation?.id == annotation.id

        Button {
            viewModel.selectAnnotation(annotation)
            showSummaryCard = true
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(pinColor(for: annotation.primaryDVGType))
                        .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                    Image(systemName: annotation.primaryDVGType.iconName)
                        .font(.system(size: isSelected ? 18 : 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Pin tail
                Image(systemName: "triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(pinColor(for: annotation.primaryDVGType))
                    .rotationEffect(.degrees(180))
                    .offset(y: -3)
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("\(annotation.name), \(annotation.dvgs.count) discount\(annotation.dvgs.count == 1 ? "" : "s"), \(annotation.distanceText) away")
        .accessibilityHint("Double-tap to view store details and available discounts")
        .accessibilityAddTraits(.isButton)
    }

    /// Returns a color for the pin based on the DVG type.
    private func pinColor(for type: DVGType) -> Color {
        switch type {
        case .discountCode:  return .blue
        case .voucher:       return .purple
        case .giftCard:      return .orange
        case .loyaltyPoints: return .green
        case .barcodeCoupon: return .red
        }
    }

    // MARK: - Search Bar Overlay

    @ViewBuilder
    private func searchBarOverlay(viewModel: NearbyMapViewModel) -> some View {
        @Bindable var vm = viewModel

        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField("Search stores...", text: $vm.searchText)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search stores")
                .accessibilityHint("Filter map pins by store name")

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - User Location Button

    @ViewBuilder
    private func userLocationButton(viewModel: NearbyMapViewModel) -> some View {
        Button {
            viewModel.centerOnUserLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(Theme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel("Center on my location")
        .accessibilityHint("Moves the map to show your current location")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "map")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                .accessibilityHidden(true)

            Text("No Nearby Stores")
                .font(Theme.Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("None of your saved discounts have store locations yet. Add a store location to a discount to see it on the map.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    // MARK: - Private Helpers

    /// Lazily creates the ViewModel on first access.
    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        let repository = SwiftDataDVGRepository(modelContext: modelContext)
        viewModel = NearbyMapViewModel(
            repository: repository,
            locationManager: locationManager
        )
    }

    /// Creates a binding for the error alert.
    private func alertBinding(viewModel: NearbyMapViewModel) -> Binding<Bool> {
        Binding(
            get: { viewModel.showError },
            set: { newValue in viewModel.showError = newValue }
        )
    }
}

// MARK: - StoreSummaryCard

/// Bottom sheet card showing store details and its DVGs when a map pin is tapped.
///
/// Displays the store name, address, distance, and a scrollable list of DVGs.
/// Each DVG row shows its title, type icon, expiry badge, and a "View" button.
/// A "Directions" button opens Apple Maps with driving directions.
private struct StoreSummaryCard: View {

    let annotation: StoreAnnotation
    let onViewDVG: (UUID) -> Void
    let onDirections: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Store header
                    storeHeader

                    Divider()

                    // DVG list
                    dvgList

                    // Directions button
                    directionsButton
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle(annotation.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Store Header

    @ViewBuilder
    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Address
            if !annotation.address.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.Colors.primary)
                        .font(Theme.Typography.subheadline)

                    Text(annotation.address)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            // Distance
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(Theme.Colors.primary)
                    .font(Theme.Typography.subheadline)

                Text(annotation.distanceText)
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("away")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            // DVG count
            Text("\(annotation.dvgs.count) discount\(annotation.dvgs.count == 1 ? "" : "s") available")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(annotation.name), \(annotation.address.isEmpty ? "" : annotation.address + ", ")\(annotation.distanceText) away, \(annotation.dvgs.count) discount\(annotation.dvgs.count == 1 ? "" : "s") available")
    }

    // MARK: - DVG List

    @ViewBuilder
    private var dvgList: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(annotation.dvgs) { dvg in
                dvgRow(dvg)
            }
        }
    }

    @ViewBuilder
    private func dvgRow(_ dvg: DVGSummary) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Type icon
            Image(systemName: dvg.dvgType.iconName)
                .font(Theme.Typography.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(dvgTypeColor(dvg.dvgType), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            // Title and expiry
            VStack(alignment: .leading, spacing: 2) {
                Text(dvg.title.isEmpty ? dvg.dvgType.displayName : dvg.title)
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.xs) {
                    Text(dvg.dvgType.displayName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let expiryBadge = expiryBadgeText(dvg) {
                        Text(expiryBadge)
                            .font(Theme.Typography.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(expiryBadgeColor(dvg))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                expiryBadgeColor(dvg).opacity(0.12),
                                in: Capsule()
                            )
                    }
                }
            }

            Spacer()

            // View button
            Button {
                onViewDVG(dvg.id)
            } label: {
                Text("View")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .background(
                        Theme.Colors.primary.opacity(0.1),
                        in: Capsule()
                    )
            }
            .accessibilityLabel("View \(dvg.title.isEmpty ? dvg.dvgType.displayName : dvg.title)")
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dvgRowAccessibilityLabel(dvg))
    }

    private func dvgRowAccessibilityLabel(_ dvg: DVGSummary) -> String {
        var parts: [String] = []
        parts.append(dvg.title.isEmpty ? dvg.dvgType.displayName : dvg.title)
        parts.append(dvg.dvgType.displayName)
        if let badge = expiryBadgeText(dvg) {
            parts.append(badge)
        }
        return parts.joined(separator: ", ")
    }

    /// Returns a color for a DVG type (used in the icon background).
    private func dvgTypeColor(_ type: DVGType) -> Color {
        switch type {
        case .discountCode:  return .blue
        case .voucher:       return .purple
        case .giftCard:      return .orange
        case .loyaltyPoints: return .green
        case .barcodeCoupon: return .red
        }
    }

    /// Returns the expiry badge text for a DVG, or `nil` if no badge should be shown.
    private func expiryBadgeText(_ dvg: DVGSummary) -> String? {
        guard let days = dvg.daysUntilExpiry else { return nil }
        if days < 0 {
            return "Expired"
        } else if days == 0 {
            return "Expires today"
        } else if days == 1 {
            return "1 day left"
        } else if days <= 7 {
            return "\(days) days left"
        } else if days <= 30 {
            return "\(days) days"
        }
        return nil
    }

    /// Returns the color for the expiry badge.
    private func expiryBadgeColor(_ dvg: DVGSummary) -> Color {
        guard let days = dvg.daysUntilExpiry else { return .clear }
        if days < 0 {
            return Theme.Colors.error
        } else if days <= 3 {
            return Theme.Colors.error
        } else if days <= 7 {
            return Theme.Colors.warning
        }
        return Theme.Colors.textSecondary
    }

    // MARK: - Directions Button

    @ViewBuilder
    private var directionsButton: some View {
        Button(action: onDirections) {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .accessibilityLabel("Get directions to \(annotation.name)")
        .accessibilityHint("Opens Apple Maps with driving directions")
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Nearby Map") {
    NavigationStack {
        NearbyMapView()
    }
    .environment(NavigationRouter())
    .environment(LocationPermissionManager())
    .modelContainer(for: DVG.self, inMemory: true)
}
#endif
