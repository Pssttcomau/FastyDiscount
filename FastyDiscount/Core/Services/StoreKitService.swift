import StoreKit
import Foundation

// MARK: - StoreKitService Protocol

/// Protocol describing the StoreKit 2 in-app purchase service used throughout the app.
/// Abstracted so that tests and previews can use a mock implementation without StoreKit infrastructure.
@MainActor
protocol StoreKitService: AnyObject {

    /// The list of available products fetched from the App Store.
    var products: [Product] { get }

    /// Whether the user has an active, verified ad-free entitlement.
    /// Published via `@Observable` so SwiftUI views update reactively.
    var isAdFree: Bool { get }

    /// Whether a purchase or restore is currently in progress.
    var isPurchasing: Bool { get }

    /// The most recent purchase error, if any. Cleared before each new purchase attempt.
    var purchaseError: StoreKitPurchaseError? { get }

    /// Fetches available products from the App Store.
    func loadProducts() async

    /// Initiates a purchase for the given product ID.
    /// - Parameter productID: The product identifier to purchase.
    func purchase(productID: String) async

    /// Restores previously completed purchases by re-verifying current entitlements.
    func restorePurchases() async

    /// Returns whether the user is entitled to the given product ID.
    /// - Parameter productID: The product identifier to check.
    func isEntitled(to productID: String) async -> Bool
}

// MARK: - StoreKitPurchaseError

/// Errors that can occur during a StoreKit 2 purchase flow.
enum StoreKitPurchaseError: Error, LocalizedError, Sendable {
    /// The user cancelled the purchase dialog.
    case cancelled
    /// The purchase is pending (e.g. Ask to Buy approval from a family organiser).
    case pending
    /// The purchase failed for an unspecified reason.
    case failed(Error)
    /// The product could not be found in the available products list.
    case productNotFound
    /// The transaction verification failed (JWS signature invalid or revoked).
    case verificationFailed
    /// A network error prevented the purchase from completing.
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Purchase cancelled."
        case .pending:
            return "Purchase is pending approval. It will be activated once approved."
        case .failed(let error):
            return "Purchase failed: \(error.localizedDescription)"
        case .productNotFound:
            return "The selected product could not be found. Please try again later."
        case .verificationFailed:
            return "Purchase verification failed. Please contact support."
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - UserDefaults Key

private extension String {
    static let adFreeStoreKitKey = "com.fastydiscount.adFree"
}

// MARK: - AppStoreKitService

/// Production implementation of `StoreKitService` using StoreKit 2.
///
/// - Loads products from the App Store using `Product.products(for:)`.
/// - Handles the purchase flow via `product.purchase()` with JWS transaction verification.
/// - Observes `Transaction.updates` in a long-lived `Task` for real-time entitlement changes.
/// - Checks `Transaction.currentEntitlements` on launch to restore entitlement state.
/// - Caches the ad-free entitlement in `UserDefaults` for fast startup reads.
@Observable
@MainActor
final class AppStoreKitService: StoreKitService {

    // MARK: - Observable Properties

    /// Available products fetched from the App Store.
    private(set) var products: [Product] = []

    /// Whether the user has a verified ad-free entitlement.
    /// Backed by a UserDefaults cache for fast startup; re-verified from StoreKit on launch.
    var isAdFree: Bool = UserDefaults.standard.bool(forKey: .adFreeStoreKitKey) {
        didSet {
            UserDefaults.standard.set(isAdFree, forKey: .adFreeStoreKitKey)
        }
    }

    /// Whether a purchase or restore is currently in progress.
    private(set) var isPurchasing: Bool = false

    /// The most recent purchase error. Cleared before each new purchase attempt.
    var purchaseError: StoreKitPurchaseError?

    // MARK: - Private

    /// The ad service to synchronise `isAdFree` with for SwiftUI reactivity.
    private weak var adService: MockAdMobService?

    /// Long-running task observing `Transaction.updates` for the app's lifetime.
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    /// Creates the service and optionally takes a reference to the ad service for synchronisation.
    /// - Parameter adService: The `MockAdMobService` whose `isAdFree` will be kept in sync.
    init(adService: MockAdMobService? = nil) {
        self.adService = adService
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - StoreKitService

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: [AppConstants.IAP.removeAdsProductID])
            products = fetched
        } catch {
            // Product loading failure is non-fatal; products will remain empty.
            // Views should handle the empty state gracefully.
        }
    }

    func purchase(productID: String) async {
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        guard let product = products.first(where: { $0.id == productID }) else {
            purchaseError = .productNotFound
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                await handleVerificationResult(verification)

            case .userCancelled:
                purchaseError = .cancelled

            case .pending:
                // Ask to Buy: the transaction is pending parental approval.
                // We do NOT grant entitlement here; `Transaction.updates` will
                // deliver a `.success` result when the organiser approves.
                purchaseError = .pending

            @unknown default:
                break
            }
        } catch {
            // Differentiate network errors from general failures.
            if (error as NSError).domain == NSURLErrorDomain {
                purchaseError = .networkError(error)
            } else {
                purchaseError = .failed(error)
            }
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }

        // StoreKit 2 restore: iterate current entitlements and re-verify each one.
        var foundEntitlement = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AppConstants.IAP.removeAdsProductID,
               transaction.revocationDate == nil {
                await transaction.finish()
                foundEntitlement = true
            }
        }

        if foundEntitlement {
            grantAdFreeEntitlement()
        }
        // If no entitlement found, we leave isAdFree as-is; views can show a "not found" message.
    }

    func isEntitled(to productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    // MARK: - Transaction Listener

    /// Starts observing `Transaction.updates` for the lifetime of the service.
    /// Call this once at app launch (e.g. from `FastyDiscountApp.init()` or `body`).
    /// The task is automatically cancelled when this object is deallocated.
    func startTransactionListener() {
        transactionListenerTask?.cancel()
        // Inherits @MainActor from the enclosing scope (Swift 6).
        // handleVerificationResult must remain on @MainActor to safely mutate
        // @Observable properties; do not move this to a detached task.
        transactionListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleVerificationResult(result)
            }
        }
    }

    // MARK: - Launch Entitlement Check

    /// Checks `Transaction.currentEntitlements` to restore entitlement state on app launch.
    /// This re-verifies the cached UserDefaults value against live StoreKit data.
    func checkEntitlementsOnLaunch() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AppConstants.IAP.removeAdsProductID,
               transaction.revocationDate == nil {
                entitled = true
                break
            }
        }

        if entitled {
            grantAdFreeEntitlement()
        } else {
            // Only revoke if we had a cached entitlement — this handles refunds / revocations.
            if isAdFree {
                revokeAdFreeEntitlement()
            }
        }
    }

    // MARK: - Private Helpers

    /// Handles a JWS verification result from StoreKit 2.
    private func handleVerificationResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            if transaction.productID == AppConstants.IAP.removeAdsProductID {
                if transaction.revocationDate == nil {
                    grantAdFreeEntitlement()
                } else {
                    // Purchase was refunded or revoked.
                    revokeAdFreeEntitlement()
                }
            }
            // Always finish the transaction to remove it from the queue.
            await transaction.finish()

        case .unverified:
            // JWS verification failed — do not grant entitlement.
            purchaseError = .verificationFailed
        }
    }

    /// Grants the ad-free entitlement and synchronises state.
    private func grantAdFreeEntitlement() {
        isAdFree = true
        adService?.isAdFree = true
    }

    /// Revokes the ad-free entitlement and synchronises state.
    private func revokeAdFreeEntitlement() {
        isAdFree = false
        adService?.isAdFree = false
    }
}
