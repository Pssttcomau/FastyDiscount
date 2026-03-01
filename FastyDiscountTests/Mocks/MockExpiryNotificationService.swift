import Foundation
@testable import FastyDiscount

// MARK: - MockExpiryNotificationService

/// Mock implementation of `ExpiryNotificationService` for unit testing.
///
/// Records all schedule/cancel/reschedule calls for verification.
actor MockExpiryNotificationService: ExpiryNotificationService {

    // MARK: - Recorded Calls

    private(set) var scheduledSnapshots: [DVGSnapshot] = []
    private(set) var cancelledDVGIDs: [UUID] = []
    private(set) var rescheduleAllCallCount = 0
    private(set) var lastRescheduleAllDVGs: [DVGSnapshot] = []

    // MARK: - ExpiryNotificationService

    func schedule(for dvg: DVGSnapshot) async {
        scheduledSnapshots.append(dvg)
    }

    func cancel(for dvgID: UUID) async {
        cancelledDVGIDs.append(dvgID)
    }

    func rescheduleAll(activeDVGs: [DVGSnapshot]) async {
        rescheduleAllCallCount += 1
        lastRescheduleAllDVGs = activeDVGs
    }
}
