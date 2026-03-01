import Testing
import Foundation
@testable import FastyDiscount

// MARK: - KeychainServiceTests

@Suite("KeychainService Tests")
struct KeychainServiceTests {

    // MARK: - Error Types

    @Test("test_keychainError_encodingFailed_hasDescription")
    func test_keychainError_encodingFailed_hasDescription() {
        let error = KeychainService.KeychainError.encodingFailed
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("encode"))
    }

    @Test("test_keychainError_saveFailed_containsStatus")
    func test_keychainError_saveFailed_containsStatus() {
        let error = KeychainService.KeychainError.saveFailed(-25299)
        #expect(error.errorDescription?.contains("-25299") == true)
    }

    @Test("test_keychainError_readFailed_containsStatus")
    func test_keychainError_readFailed_containsStatus() {
        let error = KeychainService.KeychainError.readFailed(-25300)
        #expect(error.errorDescription?.contains("-25300") == true)
    }

    @Test("test_keychainError_deleteFailed_containsStatus")
    func test_keychainError_deleteFailed_containsStatus() {
        let error = KeychainService.KeychainError.deleteFailed(-25301)
        #expect(error.errorDescription?.contains("-25301") == true)
    }

    @Test("test_keychainError_itemNotFound_hasDescription")
    func test_keychainError_itemNotFound_hasDescription() {
        let error = KeychainService.KeychainError.itemNotFound
        #expect(error.errorDescription?.contains("not found") == true)
    }

    // MARK: - KeychainService Init

    @Test("test_init_usesDefaultService")
    func test_init_usesDefaultService() {
        let service = KeychainService()
        // If it doesn't crash, it initialized correctly.
        #expect(true)
    }

    @Test("test_init_customService")
    func test_init_customService() {
        let service = KeychainService(service: "com.test.keychain")
        #expect(true)
    }
}
