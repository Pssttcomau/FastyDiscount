import SwiftUI

// MARK: - LocationPermissionStep

/// The step in the two-phase location permission flow being explained.
enum LocationPermissionStep {
    /// Explain "When In Use" before triggering the first system dialog.
    case whenInUse
    /// Explain "Always" (background) before triggering the upgrade dialog.
    case always
}

// MARK: - LocationPermissionView

/// Custom explanation sheet shown BEFORE the system location permission dialog.
///
/// Presenting a benefit-focused explanation in the app's own UI — before
/// triggering the system prompt — dramatically improves the permission grant
/// rate because the user understands the value before being asked.
///
/// ### Usage
/// Present this as a `.sheet` or `.fullScreenCover` using the booleans on
/// `LocationPermissionManager`:
///
/// ```swift
/// .sheet(isPresented: $permissionManager.showWhenInUseExplanation) {
///     LocationPermissionView(step: .whenInUse, permissionManager: permissionManager)
/// }
/// .sheet(isPresented: $permissionManager.showAlwaysExplanation) {
///     LocationPermissionView(step: .always, permissionManager: permissionManager)
/// }
/// ```
struct LocationPermissionView: View {

    // MARK: - Properties

    let step: LocationPermissionStep

    @Bindable var permissionManager: LocationPermissionManager

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero illustration
                    heroSection

                    // Content
                    contentSection

                    Spacer(minLength: 24)

                    // Action buttons
                    actionSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 140, height: 140)

            Image(systemName: heroSystemImage)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)
        }
        .padding(.top, 32)
        .padding(.bottom, 28)
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title + subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text(titleText)
                    .font(Theme.Typography.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleText)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Benefit list
            VStack(alignment: .leading, spacing: 16) {
                ForEach(benefits, id: \.icon) { benefit in
                    BenefitRow(icon: benefit.icon, text: benefit.text, accentColor: accentColor)
                }
            }

            // Privacy note
            privacyNote
        }
    }

    // MARK: - Privacy Note

    @ViewBuilder
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(Theme.Typography.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(privacyText)
                .font(Theme.Typography.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy: \(privacyText)")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        VStack(spacing: 12) {
            // Primary CTA
            Button(action: primaryAction) {
                Text(primaryButtonTitle)
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(primaryButtonTitle)
            .accessibilityHint(step == .whenInUse
                ? "Presents the system location permission dialog"
                : "Requests background location access for store alerts")

            // Secondary / dismiss
            Button("Maybe Later") {
                dismiss()
            }
            .font(Theme.Typography.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Maybe later")
            .accessibilityHint("Dismiss without granting location permission")
        }
    }

    // MARK: - Step-Specific Content

    private var navigationTitle: String {
        switch step {
        case .whenInUse: return "Location Access"
        case .always:    return "Background Location"
        }
    }

    private var heroSystemImage: String {
        switch step {
        case .whenInUse: return "location.circle.fill"
        case .always:    return "location.fill.viewfinder"
        }
    }

    private var accentColor: Color {
        switch step {
        case .whenInUse: return .blue
        case .always:    return .green
        }
    }

    private var titleText: String {
        switch step {
        case .whenInUse:
            return "Find Discounts Near You"
        case .always:
            return "Never Miss a Nearby Deal"
        }
    }

    private var subtitleText: String {
        switch step {
        case .whenInUse:
            return "Allow FastyDiscount to use your location while using the app to see discounts on the map."
        case .always:
            return "Get notified the moment you walk past a store with one of your saved discounts — even when the app is closed."
        }
    }

    private struct Benefit {
        let icon: String
        let text: String
    }

    private var benefits: [Benefit] {
        switch step {
        case .whenInUse:
            return [
                Benefit(icon: "map.fill",         text: "See your saved discounts on a live map centred on your position."),
                Benefit(icon: "storefront.fill",   text: "Discover which of your vouchers are redeemable at stores nearby."),
                Benefit(icon: "arrow.triangle.turn.up.right.circle.fill",
                                                   text: "Get walking and driving directions to the best deal near you.")
            ]
        case .always:
            return [
                Benefit(icon: "bell.badge.fill",   text: "Receive a notification the moment you're near a store with a valid voucher."),
                Benefit(icon: "moon.stars.fill",   text: "Alerts work even when your phone is locked or the app is in the background."),
                Benefit(icon: "clock.badge.checkmark.fill",
                                                   text: "Never let an expiring discount go to waste — you'll always be reminded at the right time and place.")
            ]
        }
    }

    private var privacyText: String {
        switch step {
        case .whenInUse:
            return "Your location is only read while you have the app open. It is never stored on our servers or shared with third parties."
        case .always:
            return "Background location is used exclusively to trigger discount alerts. Your precise location is never logged, stored, or shared with anyone."
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .whenInUse: return "Continue"
        case .always:    return "Enable Background Alerts"
        }
    }

    private func primaryAction() {
        switch step {
        case .whenInUse:
            permissionManager.confirmWhenInUseRequest()
            dismiss()
        case .always:
            permissionManager.confirmAlwaysRequest()
            dismiss()
        }
    }
}

// MARK: - BenefitRow

/// A single row in the benefit list: icon + descriptive text.
private struct BenefitRow: View {
    let icon: String
    let text: String
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(Theme.Typography.title3)
                .foregroundStyle(accentColor)
                .frame(width: 28)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(Theme.Typography.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - DeniedLocationView

/// Full-screen view shown when location permission has been permanently denied.
///
/// Provides a prominent deep-link button to open the app's Settings page so
/// the user can manually grant the permission.
struct DeniedLocationView: View {

    @Bindable var permissionManager: LocationPermissionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "location.slash.fill")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(.red.opacity(0.8))
                .accessibilityHidden(true)

            // Message
            VStack(spacing: 10) {
                Text("Location Access Denied")
                    .font(Theme.Typography.title2)
                    .fontWeight(.bold)

                Text("To see nearby discounts and receive geofence alerts, please allow FastyDiscount to use your location in Settings.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Open Settings CTA
            Button(action: { permissionManager.openLocationSettings() }) {
                Label("Open Settings", systemImage: "gear")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
            }
            .accessibilityLabel("Open Settings")
            .accessibilityHint("Opens iOS Settings to change location permission")

            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("When In Use") {
    LocationPermissionView(
        step: .whenInUse,
        permissionManager: LocationPermissionManager()
    )
}

#Preview("Always") {
    LocationPermissionView(
        step: .always,
        permissionManager: LocationPermissionManager()
    )
}

#Preview("Denied") {
    DeniedLocationView(permissionManager: LocationPermissionManager())
}
#endif
