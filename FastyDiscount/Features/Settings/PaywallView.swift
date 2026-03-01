import SwiftUI
import StoreKit

// MARK: - PaywallView

/// A self-contained "Remove Ads" section designed to be embedded inside a SwiftUI `Form`.
///
/// States:
///  - **Loading**: spinner while the product loads from the App Store.
///  - **Available**: displays the product description, localized price, a Buy button, and a Restore button.
///  - **Purchasing**: spinner with "Processing…" text while the transaction is in flight.
///  - **Purchased**: green checkmark with "Ad-Free — Thank You!" message.
///  - **Unavailable**: graceful fallback when the product cannot be fetched.
///  - **Error**: shows the error message with a Retry action.
struct PaywallView: View {

    // MARK: - Dependencies

    @State private var viewModel: PaywallViewModel

    // MARK: - Init

    init(storeKitService: any StoreKitService) {
        _viewModel = State(initialValue: PaywallViewModel(storeKitService: storeKitService))
    }

    // MARK: - Body

    var body: some View {
        Section {
            paywallContent
        } header: {
            Text("Purchases")
        } footer: {
            if case .purchased = viewModel.state {
                Text("You've removed all ads. Thank you for supporting FastyDiscount!")
            } else {
                Text("Remove Ads is a one-time purchase. Restore Purchases recovers any previous purchases on this Apple ID.")
            }
        }
        .task {
            await viewModel.onAppear()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var paywallContent: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingRow

            case .available:
                availableRows

            case .purchasing:
                purchasingRow

            case .purchased:
                purchasedRow

            case .unavailable:
                unavailableRow

            case .error(let message):
                errorRow(message: message)
            }
        }
        .animation(.easeInOut, value: viewModel.state)
    }

    // MARK: - State Rows

    private var loadingRow: some View {
        HStack {
            Label("Remove Ads", systemImage: "sparkles")
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var availableRows: some View {
        // Product row: icon, title, price badge
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Remove Ads")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Enjoy FastyDiscount ad-free. One-time purchase, no subscription.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            if let product = viewModel.removeAdsProduct {
                Text(product.displayPrice)
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.primary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Theme.Spacing.xs)

        // Buy button
        Button {
            Task { await viewModel.purchase() }
        } label: {
            HStack {
                Spacer()
                Text("Buy Now")
                    .fontWeight(.semibold)
                Spacer()
            }
        }
        .foregroundStyle(Theme.Colors.primary)

        // Restore button
        Button {
            Task { await viewModel.restorePurchases() }
        } label: {
            Label("Restore Purchases", systemImage: "arrow.counterclockwise")
        }
        .foregroundStyle(Theme.Colors.primary)
    }

    private var purchasingRow: some View {
        HStack {
            Label("Processing…", systemImage: "sparkles")
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
    }

    private var purchasedRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Theme.Colors.success)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Ad-Free")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Thank You!")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.success)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var unavailableRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Remove Ads", systemImage: "sparkles")
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Product temporarily unavailable. Please check your internet connection and try again.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                Task { await viewModel.onAppear() }
            } label: {
                Label("Retry", systemImage: "arrow.counterclockwise")
                    .font(Theme.Typography.footnote)
            }
            .foregroundStyle(Theme.Colors.primary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Purchase Error", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.Colors.error)
                .font(Theme.Typography.subheadline)
                .fontWeight(.semibold)

            Text(message)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                Task { await viewModel.onAppear() }
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(Theme.Typography.footnote)
            }
            .foregroundStyle(Theme.Colors.primary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("PaywallView - Loading") {
    NavigationStack {
        Form {
            PaywallView(storeKitService: MockStoreKitService())
        }
        .navigationTitle("Settings")
    }
}

#Preview("PaywallView - Available") {
    NavigationStack {
        Form {
            PaywallView(storeKitService: MockStoreKitService())
        }
        .navigationTitle("Settings")
    }
}

#Preview("PaywallView - Purchased") {
    let service = MockStoreKitService()
    service.isAdFree = true
    return NavigationStack {
        Form {
            PaywallView(storeKitService: service)
        }
        .navigationTitle("Settings")
    }
}

// MARK: - MockStoreKitService (Preview Only)

@Observable
@MainActor
private final class MockStoreKitService: StoreKitService {
    var products: [Product] = []
    var isAdFree: Bool = false
    var isPurchasing: Bool = false
    var purchaseError: StoreKitPurchaseError?

    func loadProducts() async {}

    func purchase(productID: String) async {
        isPurchasing = true
        try? await Task.sleep(for: .seconds(1))
        isAdFree = true
        isPurchasing = false
    }

    func restorePurchases() async {
        isPurchasing = true
        try? await Task.sleep(for: .seconds(1))
        isPurchasing = false
    }

    func isEntitled(to productID: String) async -> Bool {
        return isAdFree
    }
}
#endif
