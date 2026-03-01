import Testing
import Foundation
@testable import FastyDiscount

// MARK: - ExpiryNotificationServiceTests

@Suite("ExpiryNotificationService Tests")
struct ExpiryNotificationServiceTests {

    // MARK: - DVGSnapshot Tests

    @Test("test_dvgSnapshot_initFromDVG_copiesFields")
    @MainActor
    func test_dvgSnapshot_initFromDVG_copiesFields() {
        let dvg = DVG.testFixture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            title: "Snapshot Test",
            storeName: "My Store",
            expirationDate: Date(timeIntervalSince1970: 2000000),
            notificationLeadDays: 5
        )

        let snapshot = DVGSnapshot(dvg: dvg)

        #expect(snapshot.id == dvg.id)
        #expect(snapshot.title == "Snapshot Test")
        #expect(snapshot.storeName == "My Store")
        #expect(snapshot.expirationDate == dvg.expirationDate)
        #expect(snapshot.notificationLeadDays == 5)
        #expect(snapshot.statusEnum == .active)
        #expect(snapshot.isDeleted == false)
    }

    // MARK: - Mock Service Tests

    @Test("test_schedule_recordsSnapshot")
    func test_schedule_recordsSnapshot() async {
        let service = MockExpiryNotificationService()
        let snapshot = DVGSnapshot.testFixture(
            title: "Test",
            notificationLeadDays: 3
        )

        await service.schedule(for: snapshot)

        let scheduled = await service.scheduledSnapshots
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.title == "Test")
    }

    @Test("test_cancel_recordsDVGID")
    func test_cancel_recordsDVGID() async {
        let service = MockExpiryNotificationService()
        let id = UUID()

        await service.cancel(for: id)

        let cancelled = await service.cancelledDVGIDs
        #expect(cancelled.count == 1)
        #expect(cancelled.first == id)
    }

    @Test("test_rescheduleAll_recordsAllSnapshots")
    func test_rescheduleAll_recordsAllSnapshots() async {
        let service = MockExpiryNotificationService()
        let snapshots = [
            DVGSnapshot.testFixture(title: "A"),
            DVGSnapshot.testFixture(title: "B")
        ]

        await service.rescheduleAll(activeDVGs: snapshots)

        let count = await service.rescheduleAllCallCount
        #expect(count == 1)
        let lastDVGs = await service.lastRescheduleAllDVGs
        #expect(lastDVGs.count == 2)
    }

    // MARK: - Notification Identifier Format

    @Test("test_notificationIdentifier_prefix_isExpiry")
    func test_notificationIdentifier_prefix_isExpiry() {
        #expect(UNExpiryNotificationService.identifierPrefix == "expiry-")
    }

    @Test("test_categoryIdentifier_isDvgExpiry")
    func test_categoryIdentifier_isDvgExpiry() {
        #expect(UNExpiryNotificationService.categoryIdentifier == "dvg-expiry")
    }

    // MARK: - Constants

    @Test("test_maxPendingNotifications_is64")
    func test_maxPendingNotifications_is64() {
        #expect(UNExpiryNotificationService.maxPendingNotifications == 64)
    }

    @Test("test_defaultNotificationHour_is9")
    func test_defaultNotificationHour_is9() {
        #expect(UNExpiryNotificationService.defaultNotificationHour == 9)
    }

    // MARK: - Notification Action Identifiers

    @Test("test_notificationActions_haveCorrectIdentifiers")
    func test_notificationActions_haveCorrectIdentifiers() {
        #expect(NotificationActionIdentifier.viewCode == "view-code")
        #expect(NotificationActionIdentifier.markUsed == "mark-used")
        #expect(NotificationActionIdentifier.snooze == "snooze")
    }
}
