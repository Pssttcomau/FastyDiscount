import SwiftUI

// MARK: - DVGCardView

/// A reusable card component for displaying a DVG item summary.
///
/// Supports two layout modes:
/// - **Compact**: Horizontal card for use in scrollable sections (Expiring Soon, Nearby).
/// - **Row**: Full-width row for vertical lists (Recently Added, search results, history).
///
/// The card displays the DVG title, store name, type icon, expiry countdown badge
/// (color-coded red or yellow), favourite star, and optional distance indicator.
///
/// Place in `Features/Dashboard/Components/` for reuse across Dashboard, Search,
/// History, and other feature modules.
struct DVGCardView: View {

    // MARK: - Layout Mode

    /// The visual layout of the card.
    enum LayoutMode {
        /// Compact horizontal card with fixed width.
        case compact
        /// Full-width row for vertical lists.
        case row
    }

    // MARK: - Properties

    let dvg: DVG
    let layoutMode: LayoutMode

    /// Optional distance string to display (e.g. "1.2 km").
    var distanceText: String?

    /// Called when the favourite star is tapped.
    var onToggleFavorite: (() -> Void)?

    // MARK: - Body

    var body: some View {
        switch layoutMode {
        case .compact:
            compactLayout
        case .row:
            rowLayout
        }
    }

    // MARK: - Compact Layout

    /// Horizontal card for use in `LazyHStack` scrollable sections.
    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Top: Type icon + favourite
            HStack {
                typeIcon
                Spacer()
                favoriteButton
            }

            Spacer(minLength: 0)

            // Title
            Text(dvg.title.isEmpty ? "Untitled" : dvg.title)
                .font(Theme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            // Store name
            if !dvg.storeName.isEmpty {
                Text(dvg.storeName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            // Bottom: Badges
            HStack(spacing: Theme.Spacing.xs) {
                if let badge = expiryBadge {
                    badge
                }

                if let distanceText {
                    distanceBadge(distanceText)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(minWidth: 160, maxWidth: 160, minHeight: 150)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Row Layout

    /// Full-width row for vertical list sections.
    private var rowLayout: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Type icon in a circle
            typeIconCircle

            // Text content
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

            // Right side: badges + favourite
            HStack(spacing: Theme.Spacing.sm) {
                if let badge = expiryBadge {
                    badge
                }

                if let distanceText {
                    distanceBadge(distanceText)
                }

                favoriteButton
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subviews

    /// SF Symbol icon representing the DVG type.
    private var typeIcon: some View {
        Image(systemName: dvg.dvgTypeEnum.iconName)
            .font(Theme.Typography.title3)
            .foregroundStyle(Theme.Colors.primary)
            .accessibilityHidden(true)
    }

    /// Type icon in a colored circle for row layout.
    private var typeIconCircle: some View {
        Image(systemName: dvg.dvgTypeEnum.iconName)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.primary)
            .frame(width: 40, height: 40)
            .background(Theme.Colors.primary.opacity(0.12))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    /// Favourite star toggle button.
    private var favoriteButton: some View {
        Button {
            onToggleFavorite?()
        } label: {
            Image(systemName: dvg.isFavorite ? "heart.fill" : "heart")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(dvg.isFavorite ? .red : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dvg.isFavorite ? "Remove from favourites" : "Add to favourites")
        .accessibilityAddTraits(.isButton)
    }

    /// Expiry countdown badge, color-coded by urgency.
    /// Red for < 3 days, yellow/warning for 3-7 days.
    @ViewBuilder
    private var expiryBadge: (some View)? {
        if let days = dvg.daysUntilExpiry, days >= 0, days <= 7 {
            let color: Color = days < 3 ? Theme.Colors.error : Theme.Colors.warning
            let text: String = {
                if days == 0 { return "Today" }
                if days == 1 { return "1 day" }
                return "\(days) days"
            }()

            Text(text)
                .font(Theme.Typography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color, in: Capsule())
                .accessibilityLabel("Expires in \(text)")
        }
    }

    /// Distance indicator badge.
    private func distanceBadge(_ text: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "location.fill")
                .font(Theme.Typography.caption2)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(Theme.Colors.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.Colors.primary.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(text) away")
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []

        parts.append(dvg.title.isEmpty ? "Untitled item" : dvg.title)

        if !dvg.storeName.isEmpty {
            parts.append("at \(dvg.storeName)")
        }

        parts.append(dvg.dvgTypeEnum.displayName)

        if let days = dvg.daysUntilExpiry, days >= 0, days <= 7 {
            if days == 0 {
                parts.append("expires today")
            } else if days == 1 {
                parts.append("expires tomorrow")
            } else {
                parts.append("expires in \(days) days")
            }
        }

        if let distanceText {
            parts.append("\(distanceText) away")
        }

        if dvg.isFavorite {
            parts.append("favourited")
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DVGCardView - Compact") {
    ScrollView(.horizontal) {
        LazyHStack(spacing: Theme.Spacing.md) {
            DVGCardView(dvg: .preview, layoutMode: .compact)
            DVGCardView(
                dvg: .preview,
                layoutMode: .compact,
                distanceText: "1.2 km"
            )
        }
        .padding(Theme.Spacing.md)
    }
}

#Preview("DVGCardView - Row") {
    VStack(spacing: Theme.Spacing.sm) {
        DVGCardView(dvg: .preview, layoutMode: .row)
        DVGCardView(
            dvg: .preview,
            layoutMode: .row,
            distanceText: "500 m"
        )
    }
    .padding(Theme.Spacing.md)
}
#endif
