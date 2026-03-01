import Testing
import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - DVGRepositoryTests

@Suite("DVGRepository Tests")
@MainActor
struct DVGRepositoryTests {

    // MARK: - Helpers

    private func makeRepository() throws -> (SwiftDataDVGRepository, ModelContext) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = SwiftDataDVGRepository(modelContext: context, notificationService: nil)
        return (repo, context)
    }

    // MARK: - CRUD: Save

    @Test("test_save_newDVG_savedSuccessfully")
    func test_save_newDVG_savedSuccessfully() async throws {
        let (repo, context) = try makeRepository()
        let dvg = DVG.testFixture(title: "Saved Item", code: "CODE1", storeName: "Store A")

        let result = try await repo.save(dvg)

        #expect(result == .saved)

        let descriptor = FetchDescriptor<DVG>()
        let all = try context.fetch(descriptor)
        #expect(all.count == 1)
        #expect(all.first?.title == "Saved Item")
    }

    @Test("test_save_duplicateCodeAndStore_savedWithWarning")
    func test_save_duplicateCodeAndStore_savedWithWarning() async throws {
        let (repo, _) = try makeRepository()
        let dvg1 = DVG.testFixture(title: "First", code: "DUP", storeName: "Store")
        let dvg2 = DVG.testFixture(title: "Second", code: "DUP", storeName: "Store")

        _ = try await repo.save(dvg1)
        let result = try await repo.save(dvg2)

        if case .savedWithDuplicateWarning(let message) = result {
            #expect(message.contains("DUP"))
            #expect(message.contains("Store"))
        } else {
            Issue.record("Expected savedWithDuplicateWarning but got \(result)")
        }
    }

    @Test("test_save_emptyCode_noDuplicateWarning")
    func test_save_emptyCode_noDuplicateWarning() async throws {
        let (repo, _) = try makeRepository()
        let dvg1 = DVG.testFixture(title: "First", code: "", storeName: "Store")
        let dvg2 = DVG.testFixture(title: "Second", code: "", storeName: "Store")

        _ = try await repo.save(dvg1)
        let result = try await repo.save(dvg2)

        #expect(result == .saved)
    }

    @Test("test_save_setsLastModified")
    func test_save_setsLastModified() async throws {
        let (repo, _) = try makeRepository()
        let pastDate = Date.distantPast
        let dvg = DVG.testFixture(lastModified: pastDate)

        _ = try await repo.save(dvg)

        #expect(dvg.lastModified > pastDate)
    }

    // MARK: - CRUD: Soft Delete

    @Test("test_softDelete_setsIsDeletedAndArchived")
    func test_softDelete_setsIsDeletedAndArchived() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture()
        _ = try await repo.save(dvg)

        try await repo.softDelete(dvg)

        #expect(dvg.isDeleted == true)
        #expect(dvg.statusEnum == .archived)
    }

    @Test("test_softDelete_updatesLastModified")
    func test_softDelete_updatesLastModified() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture(lastModified: Date.distantPast)
        _ = try await repo.save(dvg)

        try await repo.softDelete(dvg)

        #expect(dvg.lastModified > Date.distantPast)
    }

    // MARK: - CRUD: Mark as Used

    @Test("test_markAsUsed_setsStatusToUsed")
    func test_markAsUsed_setsStatusToUsed() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture()
        _ = try await repo.save(dvg)

        try await repo.markAsUsed(dvg)

        #expect(dvg.statusEnum == .used)
    }

    // MARK: - CRUD: Update Balance

    @Test("test_updateBalance_giftCard_updatesRemainingBalance")
    func test_updateBalance_giftCard_updatesRemainingBalance() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture(dvgType: .giftCard, originalValue: 50.0, remainingBalance: 50.0)
        _ = try await repo.save(dvg)

        try await repo.updateBalance(dvg, newBalance: 25.0)

        #expect(dvg.remainingBalance == 25.0)
    }

    @Test("test_updateBalance_giftCardZero_autoMarksUsed")
    func test_updateBalance_giftCardZero_autoMarksUsed() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture(dvgType: .giftCard, originalValue: 50.0, remainingBalance: 50.0)
        _ = try await repo.save(dvg)

        try await repo.updateBalance(dvg, newBalance: 0.0)

        #expect(dvg.remainingBalance == 0.0)
        #expect(dvg.statusEnum == .used)
    }

    @Test("test_updateBalance_loyaltyPoints_updatesPointsBalance")
    func test_updateBalance_loyaltyPoints_updatesPointsBalance() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture(dvgType: .loyaltyPoints, pointsBalance: 100.0)
        _ = try await repo.save(dvg)

        try await repo.updateBalance(dvg, newBalance: 50.0)

        #expect(dvg.pointsBalance == 50.0)
    }

    @Test("test_updateBalance_negativeValue_throwsInvalidBalance")
    func test_updateBalance_negativeValue_throwsInvalidBalance() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture(dvgType: .giftCard)
        _ = try await repo.save(dvg)

        do {
            try await repo.updateBalance(dvg, newBalance: -10.0)
            Issue.record("Expected error to be thrown")
        } catch let error as DVGRepositoryError {
            if case .invalidBalance(let value) = error {
                #expect(value == -10.0)
            } else {
                Issue.record("Unexpected error case: \(error)")
            }
        }
    }

    // MARK: - Auto-Expiry

    @Test("test_fetchActive_expiredDVGs_autoTransitionsToExpiredStatus")
    func test_fetchActive_expiredDVGs_autoTransitionsToExpiredStatus() async throws {
        let (repo, _) = try makeRepository()
        let expiredDVG = DVG.testFixture(
            title: "Expired",
            expirationDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
        _ = try await repo.save(expiredDVG)

        let active = try await repo.fetchActive()

        #expect(active.isEmpty)
        #expect(expiredDVG.statusEnum == .expired)
    }

    @Test("test_fetchActive_excludesSoftDeleted")
    func test_fetchActive_excludesSoftDeleted() async throws {
        let (repo, _) = try makeRepository()
        let dvg = DVG.testFixture(title: "Active")
        let deletedDVG = DVG.testFixture(title: "Deleted", isDeleted: true)
        _ = try await repo.save(dvg)
        _ = try await repo.save(deletedDVG)

        let active = try await repo.fetchActive()

        #expect(active.count == 1)
        #expect(active.first?.title == "Active")
    }

    // MARK: - Fetch Expiring Soon

    @Test("test_fetchExpiringSoon_returnsWithinWindow")
    func test_fetchExpiringSoon_returnsWithinWindow() async throws {
        let (repo, _) = try makeRepository()
        let soonDVG = DVG.testFixture(
            title: "Soon",
            expirationDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
        )
        let farDVG = DVG.testFixture(
            title: "Far",
            expirationDate: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        _ = try await repo.save(soonDVG)
        _ = try await repo.save(farDVG)

        let results = try await repo.fetchExpiringSoon(within: 7)

        #expect(results.count == 1)
        #expect(results.first?.title == "Soon")
    }

    @Test("test_fetchExpiringSoon_excludesAlreadyExpired")
    func test_fetchExpiringSoon_excludesAlreadyExpired() async throws {
        let (repo, _) = try makeRepository()
        let pastDVG = DVG.testFixture(
            title: "Past",
            expirationDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
        _ = try await repo.save(pastDVG)

        let results = try await repo.fetchExpiringSoon(within: 7)

        // The auto-expiry in fetchActive may have transitioned it, but fetchExpiringSoon
        // only returns DVGs with expirationDate >= now and <= cutoff.
        #expect(results.isEmpty)
    }

    // MARK: - Search with Filters

    @Test("test_search_textQuery_matchesTitleAndCode")
    func test_search_textQuery_matchesTitleAndCode() async throws {
        let (repo, _) = try makeRepository()
        let dvg1 = DVG.testFixture(title: "Coffee Discount", code: "COFFEE10")
        let dvg2 = DVG.testFixture(title: "Tea Voucher", code: "TEA20")
        _ = try await repo.save(dvg1)
        _ = try await repo.save(dvg2)

        let results = try await repo.search(
            query: "coffee",
            filters: DVGFilter(),
            sort: .dateAddedNewest
        )

        #expect(results.count == 1)
        #expect(results.first?.title == "Coffee Discount")
    }

    @Test("test_search_emptyQuery_returnsAll")
    func test_search_emptyQuery_returnsAll() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "A"))
        _ = try await repo.save(DVG.testFixture(title: "B"))

        let results = try await repo.search(
            query: "",
            filters: DVGFilter(),
            sort: .dateAddedNewest
        )

        #expect(results.count == 2)
    }

    @Test("test_search_typeFilter_filtersCorrectly")
    func test_search_typeFilter_filtersCorrectly() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Discount", dvgType: .discountCode))
        _ = try await repo.save(DVG.testFixture(title: "Gift Card", dvgType: .giftCard))

        let filter = DVGFilter(type: .giftCard)
        let results = try await repo.search(query: "", filters: filter, sort: .dateAddedNewest)

        #expect(results.count == 1)
        #expect(results.first?.title == "Gift Card")
    }

    @Test("test_search_statusFilter_filtersCorrectly")
    func test_search_statusFilter_filtersCorrectly() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Active", status: .active))
        let usedDVG = DVG.testFixture(title: "Used", status: .used)
        _ = try await repo.save(usedDVG)

        let filter = DVGFilter(status: .used)
        let results = try await repo.search(query: "", filters: filter, sort: .dateAddedNewest)

        #expect(results.count == 1)
        #expect(results.first?.title == "Used")
    }

    @Test("test_search_favoriteFilter_returnsOnlyFavorites")
    func test_search_favoriteFilter_returnsOnlyFavorites() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Fav", isFavorite: true))
        _ = try await repo.save(DVG.testFixture(title: "NotFav", isFavorite: false))

        let filter = DVGFilter(isFavoriteOnly: true)
        let results = try await repo.search(query: "", filters: filter, sort: .dateAddedNewest)

        #expect(results.count == 1)
        #expect(results.first?.title == "Fav")
    }

    // MARK: - Sort Orders

    @Test("test_search_sortAlphabeticalAZ_correctOrder")
    func test_search_sortAlphabeticalAZ_correctOrder() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Banana"))
        _ = try await repo.save(DVG.testFixture(title: "Apple"))
        _ = try await repo.save(DVG.testFixture(title: "Cherry"))

        let results = try await repo.search(query: "", filters: DVGFilter(), sort: .alphabeticalAZ)

        #expect(results.map(\.title) == ["Apple", "Banana", "Cherry"])
    }

    @Test("test_search_sortAlphabeticalZA_correctOrder")
    func test_search_sortAlphabeticalZA_correctOrder() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Banana"))
        _ = try await repo.save(DVG.testFixture(title: "Apple"))
        _ = try await repo.save(DVG.testFixture(title: "Cherry"))

        let results = try await repo.search(query: "", filters: DVGFilter(), sort: .alphabeticalZA)

        #expect(results.map(\.title) == ["Cherry", "Banana", "Apple"])
    }

    @Test("test_search_sortValueDescending_correctOrder")
    func test_search_sortValueDescending_correctOrder() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Low", originalValue: 10))
        _ = try await repo.save(DVG.testFixture(title: "High", originalValue: 100))
        _ = try await repo.save(DVG.testFixture(title: "Mid", originalValue: 50))

        let results = try await repo.search(query: "", filters: DVGFilter(), sort: .valueDescending)

        #expect(results.map(\.title) == ["High", "Mid", "Low"])
    }

    // MARK: - Fetch by Status

    @Test("test_fetchByStatus_returnsMatchingStatus")
    func test_fetchByStatus_returnsMatchingStatus() async throws {
        let (repo, _) = try makeRepository()
        _ = try await repo.save(DVG.testFixture(title: "Active", status: .active))
        _ = try await repo.save(DVG.testFixture(title: "Used", status: .used))

        let results = try await repo.fetchByStatus(.used)

        #expect(results.count == 1)
        #expect(results.first?.title == "Used")
    }

    // MARK: - Fetch by Tag

    @Test("test_fetchByTag_returnsMatchingTag")
    func test_fetchByTag_returnsMatchingTag() async throws {
        let (repo, context) = try makeRepository()
        let tag = Tag(name: "Food", isSystemTag: true)
        context.insert(tag)

        let dvg = DVG.testFixture(title: "Food Deal")
        dvg.tags = [tag]
        _ = try await repo.save(dvg)

        let noTagDVG = DVG.testFixture(title: "No Tag")
        _ = try await repo.save(noTagDVG)

        let results = try await repo.fetchByTag("Food")

        #expect(results.count == 1)
        #expect(results.first?.title == "Food Deal")
    }

    @Test("test_fetchByTag_caseInsensitive")
    func test_fetchByTag_caseInsensitive() async throws {
        let (repo, context) = try makeRepository()
        let tag = Tag(name: "Electronics", isSystemTag: true)
        context.insert(tag)

        let dvg = DVG.testFixture(title: "Tech Deal")
        dvg.tags = [tag]
        _ = try await repo.save(dvg)

        let results = try await repo.fetchByTag("electronics")

        #expect(results.count == 1)
    }

    // MARK: - Nearby Query

    @Test("test_fetchNearby_returnsWithinRadius")
    func test_fetchNearby_returnsWithinRadius() async throws {
        let (repo, context) = try makeRepository()

        // Sydney CBD
        let location = StoreLocation(
            name: "Sydney Store",
            latitude: -33.8688,
            longitude: 151.2093
        )
        context.insert(location)

        let dvg = DVG.testFixture(title: "Nearby Deal")
        dvg.storeLocations = [location]
        _ = try await repo.save(dvg)

        // Search from very close (same location, 1km radius)
        let results = try await repo.fetchNearby(
            latitude: -33.8688,
            longitude: 151.2093,
            radius: 1000
        )

        #expect(results.count == 1)
        #expect(results.first?.title == "Nearby Deal")
    }

    @Test("test_fetchNearby_excludesFarAway")
    func test_fetchNearby_excludesFarAway() async throws {
        let (repo, context) = try makeRepository()

        // Melbourne
        let location = StoreLocation(
            name: "Melbourne Store",
            latitude: -37.8136,
            longitude: 144.9631
        )
        context.insert(location)

        let dvg = DVG.testFixture(title: "Far Deal")
        dvg.storeLocations = [location]
        _ = try await repo.save(dvg)

        // Search from Sydney (1km radius -- Melbourne is ~700km away)
        let results = try await repo.fetchNearby(
            latitude: -33.8688,
            longitude: 151.2093,
            radius: 1000
        )

        #expect(results.isEmpty)
    }

    // MARK: - Review Queue

    @Test("test_fetchReviewQueue_returnsDVGsNeedingReview")
    func test_fetchReviewQueue_returnsDVGsNeedingReview() async throws {
        let (repo, context) = try makeRepository()

        let scanResult = ScanResult(
            sourceType: .email,
            confidenceScore: 0.6,
            needsReview: true
        )
        context.insert(scanResult)

        let dvg = DVG.testFixture(title: "Needs Review")
        dvg.scanResult = scanResult
        _ = try await repo.save(dvg)

        let normalDVG = DVG.testFixture(title: "No Review")
        _ = try await repo.save(normalDVG)

        let queue = try await repo.fetchReviewQueue()

        #expect(queue.count == 1)
        #expect(queue.first?.title == "Needs Review")
    }

    // MARK: - Haversine Distance

    @Test("test_haversineDistance_samePoint_returnsZero")
    func test_haversineDistance_samePoint_returnsZero() {
        let distance = SwiftDataDVGRepository.haversineDistance(
            lat1: -33.8688, lon1: 151.2093,
            lat2: -33.8688, lon2: 151.2093
        )
        #expect(distance < 0.01)
    }

    @Test("test_haversineDistance_knownPoints_approximatelyCorrect")
    func test_haversineDistance_knownPoints_approximatelyCorrect() {
        // Sydney to Melbourne is approximately 713 km
        let distance = SwiftDataDVGRepository.haversineDistance(
            lat1: -33.8688, lon1: 151.2093,
            lat2: -37.8136, lon2: 144.9631
        )
        let km = distance / 1000.0
        #expect(km > 700 && km < 730)
    }
}

// MARK: - SaveResult Equatable (for testing)

extension SaveResult: @retroactive Equatable {
    public static func == (lhs: SaveResult, rhs: SaveResult) -> Bool {
        switch (lhs, rhs) {
        case (.saved, .saved):
            return true
        case (.savedWithDuplicateWarning, .savedWithDuplicateWarning):
            return true
        default:
            return false
        }
    }
}
