import SwiftUI

// MARK: - DVGRowView

/// A single row in the DVG list, displaying the DVG type icon, title,
/// store name, and an expiry badge.
struct DVGRowView: View {

    let dvg: WatchDVG

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: dvg.dvgTypeEnum.iconName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("\(dvg.dvgTypeEnum.displayName) icon")

            // Title and store
            VStack(alignment: .leading, spacing: 2) {
                Text(dvg.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityLabel("Discount: \(dvg.title)")

                Text(dvg.storeName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Store: \(dvg.storeName)")
            }

            Spacer(minLength: 0)

            // Expiry badge
            if dvg.expirationDate != nil {
                expiryBadge
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    private var expiryBadge: some View {
        Text(dvg.expiryText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(dvg.expiryColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(dvg.expiryColor.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel("Expires: \(dvg.expiryText)")
    }

    private var iconBackgroundColor: Color {
        switch dvg.dvgTypeEnum {
        case .discountCode:  return .blue
        case .voucher:       return .purple
        case .giftCard:      return .green
        case .loyaltyPoints: return .orange
        case .barcodeCoupon: return .teal
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        ForEach(WatchDVG.previews) { dvg in
            DVGRowView(dvg: dvg)
        }
    }
}
