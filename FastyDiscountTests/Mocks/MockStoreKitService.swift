import Foundation
import StoreKit
@testable import FastyDiscount

// MARK: - MockStoreKitService

/// Mock implementation of `StoreKitService` for unit testing.
@MainActor
final class MockStoreKitService: StoreKitService {

    // MARK: - State

    var products: [Product] = []
    var isAdFree: Bool = false
    var isPurchasing: Bool = false
    var purchaseError: StoreKitPurchaseError?

    // MARK: - Recorded Calls

    var loadProductsCallCount = 0
    var purchaseCallCount = 0
    var lastPurchaseProductID: String?
    var restorePurchasesCallCount = 0
    var isEntitledCallCount = 0
    var lastEntitlementProductID: String?

    // MARK: - Stubbed

    var stubbedIsEntitled: Bool = false

    // MARK: - StoreKitService

    func loadProducts() async {
        loadProductsCallCount += 1
    }

    func purchase(productID: String) async {
        purchaseCallCount += 1
        lastPurchaseProductID = productID
    }

    func restorePurchases() async {
        restorePurchasesCallCount += 1
    }

    func isEntitled(to productID: String) async -> Bool {
        isEntitledCallCount += 1
        lastEntitlementProductID = productID
        return stubbedIsEntitled
    }
}
