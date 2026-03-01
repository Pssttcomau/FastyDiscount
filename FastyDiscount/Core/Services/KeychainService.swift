import Foundation
import Security

// MARK: - KeychainService

/// A thread-safe wrapper around the Security framework's Keychain APIs.
/// All reads and writes are scoped to this app using `kSecAttrService`.
///
/// Conforms to `Sendable` so it can be safely used across concurrency domains.
struct KeychainService: Sendable {

    // MARK: - Types

    enum KeychainError: LocalizedError, Sendable {
        case encodingFailed
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case itemNotFound

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode value for Keychain storage."
            case .saveFailed(let status):
                return "Keychain save failed with status \(status)."
            case .readFailed(let status):
                return "Keychain read failed with status \(status)."
            case .deleteFailed(let status):
                return "Keychain delete failed with status \(status)."
            case .itemNotFound:
                return "Keychain item not found."
            }
        }
    }

    // MARK: - Properties

    private let service: String

    // MARK: - Init

    init(service: String = AppConstants.bundleIdentifier) {
        self.service = service
    }

    // MARK: - Public API

    /// Saves a string value for the given key.
    /// If an item already exists, it is updated.
    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Attempt to delete any existing item first for a clean update.
        let deleteQuery = baseQuery(forKey: key)
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = baseQuery(forKey: key)
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Reads the string value for the given key.
    /// Returns `nil` if the item does not exist.
    func read(forKey key: String) throws -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Deletes the item for the given key.
    func delete(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Private Helpers

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Restrict access to this device only while the device is unlocked.
            // Prevents iCloud Keychain sync and ensures credentials are not
            // accessible from backup restores on other devices.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
