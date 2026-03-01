import StoreKit
import SwiftUI

// MARK: - PaywallViewState

/// Represents the loading / purchase states for the paywall UI.
enum PaywallViewState: Equatable {
    /// Products have not been loaded yet; a spinner should be shown.
    case loading
    /// The Remove Ads product is available and ready to purchase.
    case available
    /// The purchase is in progress (or restore is running).
    case purchasing
    /// The user already owns the Remove Ads entitlement.
    case purchased
    /// No product could be loaded from the App Store.
    case unavailable
    /// A purchase error occurred.
    case error(String)
}

// MARK: - PaywallViewModel

/// `@Observable` view model managing Remove Ads product loading, purchase state,
/// and entitlement status. Injected as a `@State` in `PaywallView`.
@Observable
@MainActor
final class PaywallViewModel {

    // MARK: - Observable State

    /// The current UI state for the paywall section.
    var state: PaywallViewState = .loading

    /// The product to display (Remove Ads non-consumable).
    var removeAdsProduct: Product?

    // MARK: - Dependencies

    private let storeKitService: any StoreKitService

    // MARK: - Init

    init(storeKitService: any StoreKitService) {
        self.storeKitService = storeKitService
    }

    // MARK: - Lifecycle

    /// Called when the paywall section appears.
    /// Loads the product and evaluates the current entitlement.
    func onAppear() async {
        await refreshState()
    }

    // MARK: - Actions

    /// Initiates the Remove Ads purchase.
    func purchase() async {
        guard let product = removeAdsProduct else {
            state = .error("Product not available. Please try again later.")
            return
        }
        state = .purchasing
        await storeKitService.purchase(productID: product.id)
        await refreshState()
    }

    /// Restores previously completed purchases on this Apple ID.
    func restorePurchases() async {
        state = .purchasing
        await storeKitService.restorePurchases()
        await refreshState()
    }

    // MARK: - Private Helpers

    /// Re-evaluates state from the StoreKit service.
    private func refreshState() async {
        // If already entitled, show the purchased state immediately.
        if storeKitService.isAdFree {
            state = .purchased
            return
        }

        // Find the Remove Ads product in the fetched product list.
        let product = storeKitService.products.first(where: {
            $0.id == AppConstants.IAP.removeAdsProductID
        })

        removeAdsProduct = product

        // Map the service's purchase error to a user-facing state.
        if let error = storeKitService.purchaseError {
            switch error {
            case .cancelled:
                // User cancelled — return to available state without an error message.
                state = product != nil ? .available : .unavailable
            case .pending:
                state = .error("Purchase pending approval. It will activate once approved.")
            default:
                state = .error(error.errorDescription ?? "An error occurred. Please try again.")
            }
            return
        }

        if product != nil {
            state = .available
        } else {
            // Products may still be loading on first appearance; stay in loading state.
            state = storeKitService.products.isEmpty ? .loading : .unavailable
        }
    }
}
