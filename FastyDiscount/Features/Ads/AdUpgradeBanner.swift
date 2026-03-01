import SwiftUI

// MARK: - AdUpgradeBanner

/// A small, non-intrusive inline banner that suggests removing ads.
///
/// Shown after every 10th banner ad impression. Appears inline — NOT as a modal.
/// Dismissed by tapping the close button or by navigating to the paywall.
///
/// Design principles:
/// - Unobtrusive: small, dismissible, appears once per 10 impressions
/// - Contextual: appears near the ad banner, not as a disruptive overlay
/// - Action-oriented: taps navigate to the "Purchases" section in Settings
struct AdUpgradeBanner: View {

    // MARK: - Bindings

    /// Whether the banner is currently visible. The parent dismisses it by setting this to `false`.
    @Binding var isVisible: Bool

    /// Optional closure called when the user taps "Remove Ads". Use to navigate to paywall.
    var onUpgradeTapped: (() -> Void)?

    // MARK: - Body

    var body: some View {
        if isVisible {
            bannerContent
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Banner Content

    private var bannerContent: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Enjoying FastyDiscount?")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Remove ads with a one-time purchase.")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = false
                }
                onUpgradeTapped?()
            } label: {
                Text("Remove Ads")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(Theme.Colors.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Theme.Colors.border),
            alignment: .top
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AdUpgradeBanner - Visible") {
    VStack(spacing: 0) {
        Spacer()
        Text("Content area")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))

        AdUpgradeBanner(isVisible: .constant(true)) {
            print("Navigate to paywall")
        }

        // Simulate the banner ad below
        HStack {
            Spacer()
            Text("Advertisement (Test)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 50)
        .background(Color(.systemGray5))
    }
    .ignoresSafeArea(edges: .bottom)
}

#Preview("AdUpgradeBanner - Hidden") {
    VStack(spacing: 0) {
        Spacer()
        Text("Content area")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))

        AdUpgradeBanner(isVisible: .constant(false))

        HStack {
            Spacer()
            Text("Advertisement (Test)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 50)
        .background(Color(.systemGray5))
    }
    .ignoresSafeArea(edges: .bottom)
}
#endif
