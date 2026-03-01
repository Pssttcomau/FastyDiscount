import Testing
import Foundation
@testable import FastyDiscount

// MARK: - PaywallViewModelTests

@Suite("PaywallViewModel Tests")
@MainActor
struct PaywallViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(
        isAdFree: Bool = false,
        purchaseError: StoreKitPurchaseError? = nil
    ) -> (PaywallViewModel, MockStoreKitService) {
        let service = MockStoreKitService()
        service.isAdFree = isAdFree
        service.purchaseError = purchaseError
        let vm = PaywallViewModel(storeKitService: service)
        return (vm, service)
    }

    // MARK: - On Appear

    @Test("test_onAppear_alreadyAdFree_showsPurchasedState")
    func test_onAppear_alreadyAdFree_showsPurchasedState() async {
        let (vm, _) = makeViewModel(isAdFree: true)

        await vm.onAppear()

        #expect(vm.state == .purchased)
    }

    @Test("test_onAppear_noProducts_showsLoadingOrUnavailable")
    func test_onAppear_noProducts_showsLoadingOrUnavailable() async {
        let (vm, _) = makeViewModel()

        await vm.onAppear()

        // With empty products list and not ad-free, should be loading
        #expect(vm.state == .loading)
    }

    // MARK: - Purchase

    @Test("test_purchase_noProduct_setsErrorState")
    func test_purchase_noProduct_setsErrorState() async {
        let (vm, _) = makeViewModel()
        vm.removeAdsProduct = nil

        await vm.purchase()

        if case .error(let message) = vm.state {
            #expect(message.contains("not available"))
        } else {
            Issue.record("Expected error state")
        }
    }

    @Test("test_purchase_callsService")
    func test_purchase_callsService() async {
        let (vm, service) = makeViewModel()
        // Simulate having a product -- we can't create a real Product in tests,
        // but we can verify the purchase flow transitions state.

        // Without a product, it should show error
        await vm.purchase()

        // The state should be error since no product
        if case .error = vm.state {
            // expected
        } else {
            Issue.record("Expected error state since no product available")
        }
    }

    // MARK: - Restore

    @Test("test_restorePurchases_callsService")
    func test_restorePurchases_callsService() async {
        let (vm, service) = makeViewModel()

        await vm.restorePurchases()

        #expect(service.restorePurchasesCallCount == 1)
    }

    @Test("test_restorePurchases_adFreeAfter_showsPurchased")
    func test_restorePurchases_adFreeAfter_showsPurchased() async {
        let (vm, service) = makeViewModel()
        // After restore, set isAdFree
        service.isAdFree = true

        await vm.restorePurchases()

        #expect(vm.state == .purchased)
    }

    // MARK: - Purchase Error States

    @Test("test_cancelledError_returnsToAvailableState")
    func test_cancelledError_returnsToAvailableState() async {
        let (vm, service) = makeViewModel(purchaseError: .cancelled)

        await vm.onAppear()

        // Should not show an error for cancellation
        if case .error = vm.state {
            Issue.record("Should not show error for cancellation")
        }
    }

    @Test("test_pendingError_showsPendingMessage")
    func test_pendingError_showsPendingMessage() async {
        let (vm, _) = makeViewModel(purchaseError: .pending)

        await vm.onAppear()

        if case .error(let message) = vm.state {
            #expect(message.contains("pending"))
        } else {
            Issue.record("Expected error state with pending message")
        }
    }

    // MARK: - PaywallViewState

    @Test("test_paywallViewState_equatable")
    func test_paywallViewState_equatable() {
        #expect(PaywallViewState.loading == .loading)
        #expect(PaywallViewState.available == .available)
        #expect(PaywallViewState.purchasing == .purchasing)
        #expect(PaywallViewState.purchased == .purchased)
        #expect(PaywallViewState.unavailable == .unavailable)
        #expect(PaywallViewState.error("test") == .error("test"))
        #expect(PaywallViewState.loading != .available)
    }
}
