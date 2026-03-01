import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - DVG Test Fixtures

extension DVG {

    /// Factory method for creating test DVGs with sensible defaults.
    static func testFixture(
        id: UUID = UUID(),
        title: String = "Test Discount",
        code: String = "TEST20",
        storeName: String = "Test Store",
        dvgType: DVGType = .discountCode,
        originalValue: Double = 20.0,
        remainingBalance: Double = 0.0,
        pointsBalance: Double = 0.0,
        discountDescription: String = "Test discount description",
        minimumSpend: Double = 0.0,
        expirationDate: Date? = Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        dateAdded: Date = Date(),
        source: DVGSource = .manual,
        status: DVGStatus = .active,
        notes: String = "",
        isFavorite: Bool = false,
        notificationLeadDays: Int = 0,
        geofenceRadius: Double = 0.0,
        isDeleted: Bool = false,
        lastModified: Date = Date()
    ) -> DVG {
        DVG(
            id: id,
            title: title,
            code: code,
            dvgType: dvgType,
            storeName: storeName,
            originalValue: originalValue,
            remainingBalance: remainingBalance,
            pointsBalance: pointsBalance,
            discountDescription: discountDescription,
            minimumSpend: minimumSpend,
            expirationDate: expirationDate,
            dateAdded: dateAdded,
            source: source,
            status: status,
            notes: notes,
            isFavorite: isFavorite,
            notificationLeadDays: notificationLeadDays,
            geofenceRadius: geofenceRadius,
            isDeleted: isDeleted,
            lastModified: lastModified
        )
    }
}

// MARK: - RawEmail Test Fixtures

extension RawEmail {

    static func testFixture(
        id: String = "msg-001",
        subject: String = "20% off your next order!",
        sender: String = "store@example.com",
        date: Date = Date(),
        bodyText: String = "Use code SAVE20 for 20% off. Valid until Dec 31.",
        bodyHTML: String? = nil,
        snippet: String = "Use code SAVE20 for 20% off"
    ) -> RawEmail {
        RawEmail(
            id: id,
            subject: subject,
            sender: sender,
            date: date,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            snippet: snippet
        )
    }
}

// MARK: - DVGExtractionResult Test Fixtures

extension DVGExtractionResult {

    static func testFixture(
        title: String? = "20% off",
        code: String? = "SAVE20",
        dvgType: DVGType? = .discountCode,
        storeName: String? = "Test Store",
        originalValue: Double? = 20.0,
        discountDescription: String? = "20% off all items",
        expirationDate: Date? = nil,
        termsAndConditions: String? = nil,
        confidenceScore: Double = 0.92,
        fieldConfidences: [String: Double] = [
            "title": 0.95,
            "code": 0.98,
            "storeName": 0.90,
            "dvgType": 0.85
        ]
    ) -> DVGExtractionResult {
        DVGExtractionResult(
            title: title,
            code: code,
            dvgType: dvgType,
            storeName: storeName,
            originalValue: originalValue,
            discountDescription: discountDescription,
            expirationDate: expirationDate,
            termsAndConditions: termsAndConditions,
            confidenceScore: confidenceScore,
            fieldConfidences: fieldConfidences
        )
    }
}

// MARK: - DVGSnapshot Test Fixtures

extension DVGSnapshot {

    /// Creates a test snapshot without requiring an actual DVG model object.
    static func testFixture(
        id: UUID = UUID(),
        title: String = "Test DVG",
        storeName: String = "Test Store",
        expirationDate: Date? = Calendar.current.date(byAdding: .day, value: 10, to: Date()),
        notificationLeadDays: Int = 3,
        statusEnum: DVGStatus = .active,
        isDeleted: Bool = false
    ) -> DVGSnapshot {
        // We need to create a DVG to init DVGSnapshot because its init requires @MainActor DVG.
        // Instead, use a direct memberwise approach via a helper.
        _DVGSnapshotTestHelper(
            id: id,
            title: title,
            storeName: storeName,
            expirationDate: expirationDate,
            notificationLeadDays: notificationLeadDays,
            statusEnum: statusEnum,
            isDeleted: isDeleted
        )
    }
}

/// Helper to create DVGSnapshot values for testing without needing a live DVG model.
@MainActor
private func _DVGSnapshotTestHelper(
    id: UUID,
    title: String,
    storeName: String,
    expirationDate: Date?,
    notificationLeadDays: Int,
    statusEnum: DVGStatus,
    isDeleted: Bool
) -> DVGSnapshot {
    let dvg = DVG(
        id: id,
        title: title,
        storeName: storeName,
        expirationDate: expirationDate,
        notificationLeadDays: notificationLeadDays,
        isDeleted: isDeleted
    )
    dvg.status = statusEnum.rawValue
    return DVGSnapshot(dvg: dvg)
}

// MARK: - GeofenceSnapshot Test Fixtures

extension GeofenceSnapshot {

    static func testFixture(
        dvgID: UUID = UUID(),
        storeName: String = "Test Store",
        title: String = "Test DVG",
        discountDescription: String = "Test discount",
        isFavorite: Bool = false,
        expirationDate: Date? = Calendar.current.date(byAdding: .day, value: 10, to: Date()),
        geofenceRadius: Double = 300.0,
        locationID: UUID = UUID(),
        latitude: Double = -33.8688,
        longitude: Double = 151.2093
    ) -> GeofenceSnapshot {
        GeofenceSnapshot(
            dvgID: dvgID,
            storeName: storeName,
            title: title,
            discountDescription: discountDescription,
            isFavorite: isFavorite,
            expirationDate: expirationDate,
            geofenceRadius: geofenceRadius,
            locationID: locationID,
            latitude: latitude,
            longitude: longitude
        )
    }
}

// MARK: - In-Memory ModelContainer

/// Creates an in-memory `ModelContainer` suitable for testing.
///
/// Uses `ModelConfiguration(isStoredInMemoryOnly: true)` so tests
/// do not touch the filesystem and run in isolation.
@MainActor
func makeTestModelContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: DVG.self, StoreLocation.self, Tag.self, ScanResult.self,
        configurations: config
    )
}
