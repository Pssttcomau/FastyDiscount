import Foundation
@testable import FastyDiscount

// MARK: - MockNotificationPermissionManager

/// Mock implementation of `NotificationPermissionManager` for unit testing.
struct MockNotificationPermissionManager: NotificationPermissionManager {

    var stubbedResult: Bool = true

    func requestIfNeeded() async -> Bool {
        return stubbedResult
    }
}
