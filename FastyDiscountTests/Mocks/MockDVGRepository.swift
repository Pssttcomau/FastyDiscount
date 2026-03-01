import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - MockDVGRepository

/// In-memory mock of `DVGRepository` for unit testing.
///
/// Records method calls for verification and returns pre-configured values.
@MainActor
final class MockDVGRepository: DVGRepository {

    // MARK: - Recorded Calls

    var fetchActiveCalled = false
    var fetchExpiringSoonDays: Int?
    var fetchNearbyArgs: (lat: Double, lon: Double, radius: Double)?
    var fetchByStatusArgs: DVGStatus?
    var fetchByTagArgs: String?
    var searchArgs: (query: String, filters: DVGFilter, sort: DVGSortOrder)?
    var savedDVGs: [DVG] = []
    var softDeletedDVGs: [DVG] = []
    var markedUsedDVGs: [DVG] = []
    var updateBalanceArgs: [(dvg: DVG, balance: Double)] = []
    var fetchReviewQueueCalled = false

    // MARK: - Stubbed Return Values

    var stubbedActive: [DVG] = []
    var stubbedExpiringSoon: [DVG] = []
    var stubbedNearby: [DVG] = []
    var stubbedByStatus: [DVG] = []
    var stubbedByTag: [DVG] = []
    var stubbedSearch: [DVG] = []
    var stubbedSaveResult: SaveResult = .saved
    var stubbedReviewQueue: [DVG] = []

    // MARK: - Error Stubs

    var fetchActiveError: Error?
    var fetchExpiringSoonError: Error?
    var fetchNearbyError: Error?
    var fetchByStatusError: Error?
    var fetchByTagError: Error?
    var searchError: Error?
    var saveError: Error?
    var softDeleteError: Error?
    var markAsUsedError: Error?
    var updateBalanceError: Error?
    var fetchReviewQueueError: Error?

    // MARK: - DVGRepository

    func fetchActive() async throws -> [DVG] {
        fetchActiveCalled = true
        if let error = fetchActiveError { throw error }
        return stubbedActive
    }

    func fetchExpiringSoon(within days: Int) async throws -> [DVG] {
        fetchExpiringSoonDays = days
        if let error = fetchExpiringSoonError { throw error }
        return stubbedExpiringSoon
    }

    func fetchNearby(latitude: Double, longitude: Double, radius: Double) async throws -> [DVG] {
        fetchNearbyArgs = (latitude, longitude, radius)
        if let error = fetchNearbyError { throw error }
        return stubbedNearby
    }

    func fetchByStatus(_ status: DVGStatus) async throws -> [DVG] {
        fetchByStatusArgs = status
        if let error = fetchByStatusError { throw error }
        return stubbedByStatus
    }

    func fetchByTag(_ tagName: String) async throws -> [DVG] {
        fetchByTagArgs = tagName
        if let error = fetchByTagError { throw error }
        return stubbedByTag
    }

    func search(query: String, filters: DVGFilter, sort: DVGSortOrder) async throws -> [DVG] {
        searchArgs = (query, filters, sort)
        if let error = searchError { throw error }
        return stubbedSearch
    }

    @discardableResult
    func save(_ dvg: DVG) async throws -> SaveResult {
        if let error = saveError { throw error }
        savedDVGs.append(dvg)
        return stubbedSaveResult
    }

    func softDelete(_ dvg: DVG) async throws {
        if let error = softDeleteError { throw error }
        softDeletedDVGs.append(dvg)
    }

    func markAsUsed(_ dvg: DVG) async throws {
        if let error = markAsUsedError { throw error }
        markedUsedDVGs.append(dvg)
    }

    func updateBalance(_ dvg: DVG, newBalance: Double) async throws {
        if let error = updateBalanceError { throw error }
        updateBalanceArgs.append((dvg, newBalance))
    }

    func fetchReviewQueue() async throws -> [DVG] {
        fetchReviewQueueCalled = true
        if let error = fetchReviewQueueError { throw error }
        return stubbedReviewQueue
    }
}
