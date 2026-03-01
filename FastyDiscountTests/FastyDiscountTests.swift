import Testing
@testable import FastyDiscount

@Suite("FastyDiscount Tests")
struct FastyDiscountTests {
    @Test("App constants are configured correctly")
    func appConstants() {
        #expect(AppConstants.appGroupIdentifier == "group.com.fastydiscount.shared")
        #expect(AppConstants.iCloudContainerIdentifier == "iCloud.com.fastydiscount.app")
        #expect(AppConstants.bundleIdentifier == "com.fastydiscount.app")
    }
}
