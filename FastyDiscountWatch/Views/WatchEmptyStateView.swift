import SwiftUI

// MARK: - WatchEmptyStateView

/// Displayed when no DVGs have been synced to the watch.
/// Instructs the user to open the iPhone app to sync.
struct WatchEmptyStateView: View {

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.and.arrow.right.inward")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Discounts")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Open FastyDiscount on iPhone to sync")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No discounts synced. Open FastyDiscount on iPhone to sync your discounts.")
    }
}

// MARK: - Preview

#Preview {
    WatchEmptyStateView()
}
