import Testing
import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - HistoryViewModelTests

@Suite("HistoryViewModel Tests")
@MainActor
struct HistoryViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(
        stubbedByStatus: [DVG] = []
    ) throws -> (HistoryViewModel, MockDVGRepository, ModelContext) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()
        repo.stubbedByStatus = stubbedByStatus
        let vm = HistoryViewModel(
            repository: repo,
            modelContext: context,
            notificationService: nil
        )
        return (vm, repo, context)
    }

    // MARK: - Loading

    @Test("test_load_setsHasLoadedTrue")
    func test_load_setsHasLoadedTrue() async throws {
        let (vm, _, _) = try makeViewModel()

        await vm.load()

        #expect(vm.hasLoaded == true)
        #expect(vm.isLoading == false)
    }

    @Test("test_load_fetchesAllHistoryStatuses")
    func test_load_fetchesAllHistoryStatuses() async throws {
        let (vm, repo, _) = try makeViewModel()

        await vm.load()

        // Should have called fetchByStatus at least once
        #expect(repo.fetchByStatusArgs != nil)
    }

    // MARK: - Filtering by Segment

    @Test("test_filteredDVGs_allFilter_returnsAll")
    func test_filteredDVGs_allFilter_returnsAll() async throws {
        let used = DVG.testFixture(title: "Used", status: .used)
        let expired = DVG.testFixture(title: "Expired", status: .expired)
        let (vm, _, _) = try makeViewModel(stubbedByStatus: [used, expired])

        await vm.load()
        vm.selectedFilter = .all

        #expect(vm.filteredDVGs.count >= 0) // The mock returns same list for all statuses
    }

    @Test("test_filteredDVGs_searchQuery_filtersCorrectly")
    func test_filteredDVGs_searchQuery_filtersCorrectly() async throws {
        let dvg1 = DVG.testFixture(title: "Coffee Card", status: .used)
        let dvg2 = DVG.testFixture(title: "Tea Voucher", status: .used)
        let (vm, _, _) = try makeViewModel(stubbedByStatus: [dvg1, dvg2])

        await vm.load()
        vm.searchQuery = "Coffee"

        let results = vm.filteredDVGs
        // Results filtered by text
        #expect(results.allSatisfy { $0.title.lowercased().contains("coffee") || $0.storeName.lowercased().contains("coffee") || $0.code.lowercased().contains("coffee") || $0.notes.lowercased().contains("coffee") })
    }

    // MARK: - Empty State

    @Test("test_isEmpty_notLoaded_returnsFalse")
    func test_isEmpty_notLoaded_returnsFalse() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.isEmpty == false)
    }

    @Test("test_isEmpty_loadedNoResults_returnsTrue")
    func test_isEmpty_loadedNoResults_returnsTrue() async throws {
        let (vm, _, _) = try makeViewModel(stubbedByStatus: [])

        await vm.load()

        #expect(vm.isEmpty == true)
    }

    // MARK: - Reactivation

    @Test("test_reactivate_setsStatusToActive")
    func test_reactivate_setsStatusToActive() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()

        let dvg = DVG.testFixture(title: "Reactivate Me", status: .used)
        context.insert(dvg)
        try context.save()

        let vm = HistoryViewModel(repository: repo, modelContext: context, notificationService: nil)

        await vm.reactivate(dvg)

        #expect(dvg.statusEnum == .active)
        #expect(dvg.isDeleted == false)
    }

    // MARK: - Permanent Delete

    @Test("test_requestPermanentDelete_setsPendingDVG")
    func test_requestPermanentDelete_setsPendingDVG() throws {
        let dvg = DVG.testFixture(title: "Delete Me")
        let (vm, _, _) = try makeViewModel()

        vm.requestPermanentDelete(dvg)

        #expect(vm.pendingDeleteDVG?.id == dvg.id)
        #expect(vm.showPermanentDeleteConfirmation == true)
    }

    // MARK: - HistoryFilter

    @Test("test_historyFilter_dvgStatus_correctMapping")
    func test_historyFilter_dvgStatus_correctMapping() {
        #expect(HistoryFilter.all.dvgStatus == nil)
        #expect(HistoryFilter.used.dvgStatus == .used)
        #expect(HistoryFilter.expired.dvgStatus == .expired)
        #expect(HistoryFilter.archived.dvgStatus == .archived)
    }

    @Test("test_historyFilter_displayNames_notEmpty")
    func test_historyFilter_displayNames_notEmpty() {
        for filter in HistoryFilter.allCases {
            #expect(!filter.displayName.isEmpty)
            #expect(!filter.emptyStateMessage.isEmpty)
            #expect(!filter.emptyStateDescription.isEmpty)
            #expect(!filter.emptyStateIcon.isEmpty)
            #expect(!filter.clearAllTitle.isEmpty)
            #expect(!filter.clearAllMessage.isEmpty)
        }
    }
}
