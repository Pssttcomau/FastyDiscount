import Testing
import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - SearchViewModelTests

@Suite("SearchViewModel Tests")
@MainActor
struct SearchViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(
        stubbedSearch: [DVG] = [],
        initialFilter: DVGFilter? = nil
    ) throws -> (SearchViewModel, MockDVGRepository) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()
        repo.stubbedSearch = stubbedSearch
        let vm = SearchViewModel(
            repository: repo,
            modelContext: context,
            initialFilter: initialFilter
        )
        return (vm, repo)
    }

    // MARK: - Filter Application

    @Test("test_onAppear_runsSearchWithEmptyQuery")
    func test_onAppear_runsSearchWithEmptyQuery() async throws {
        let (vm, repo) = try makeViewModel()

        await vm.onAppear()

        #expect(repo.searchArgs != nil)
        #expect(repo.searchArgs?.query == "")
    }

    @Test("test_selectedTypes_filterAppliedInMemory")
    func test_selectedTypes_filterAppliedInMemory() async throws {
        let dvg1 = DVG.testFixture(title: "Code", dvgType: .discountCode)
        let dvg2 = DVG.testFixture(title: "Card", dvgType: .giftCard)
        let (vm, _) = try makeViewModel(stubbedSearch: [dvg1, dvg2])

        // Load results first
        await vm.onAppear()

        // Apply type filter
        vm.selectedTypes = [.giftCard]

        // Allow the async filter task to complete
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.results.count == 1)
        #expect(vm.results.first?.title == "Card")
    }

    @Test("test_selectedStatuses_filterAppliedInMemory")
    func test_selectedStatuses_filterAppliedInMemory() async throws {
        let dvg1 = DVG.testFixture(title: "Active", status: .active)
        let dvg2 = DVG.testFixture(title: "Used", status: .used)
        let (vm, _) = try makeViewModel(stubbedSearch: [dvg1, dvg2])

        await vm.onAppear()
        vm.selectedStatuses = [.used]

        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.results.count == 1)
        #expect(vm.results.first?.title == "Used")
    }

    // MARK: - Sort Ordering

    @Test("test_sortOrder_passedToRepository")
    func test_sortOrder_passedToRepository() async throws {
        let (vm, repo) = try makeViewModel()
        vm.sortOrder = .valueDescending

        await vm.onAppear()

        #expect(repo.searchArgs?.sort == .valueDescending)
    }

    // MARK: - Active Filter Count

    @Test("test_activeFilterCount_noFilters_isZero")
    func test_activeFilterCount_noFilters_isZero() throws {
        let (vm, _) = try makeViewModel()
        #expect(vm.activeFilterCount == 0)
        #expect(vm.hasActiveFilters == false)
    }

    @Test("test_activeFilterCount_typeAndStatus_isTwo")
    func test_activeFilterCount_typeAndStatus_isTwo() throws {
        let (vm, _) = try makeViewModel()
        vm.selectedTypes = [.giftCard]
        vm.selectedStatuses = [.active]
        #expect(vm.activeFilterCount == 2)
        #expect(vm.hasActiveFilters == true)
    }

    @Test("test_activeFilterCount_withTagFilter_isOne")
    func test_activeFilterCount_withTagFilter_isOne() throws {
        let (vm, _) = try makeViewModel()
        vm.selectedTagName = "Food"
        #expect(vm.activeFilterCount == 1)
    }

    @Test("test_activeFilterCount_withDateRange_isOne")
    func test_activeFilterCount_withDateRange_isOne() throws {
        let (vm, _) = try makeViewModel()
        vm.expiryDateFrom = Date()
        #expect(vm.activeFilterCount == 1)
    }

    // MARK: - Clear Filters

    @Test("test_clearAllFilters_resetsAllFilters")
    func test_clearAllFilters_resetsAllFilters() throws {
        let (vm, _) = try makeViewModel()
        vm.selectedTypes = [.giftCard]
        vm.selectedStatuses = [.active]
        vm.selectedTagName = "Food"
        vm.expiryDateFrom = Date()
        vm.expiryDateTo = Date()

        vm.clearAllFilters()

        #expect(vm.selectedTypes.isEmpty)
        #expect(vm.selectedStatuses.isEmpty)
        #expect(vm.selectedTagName == nil)
        #expect(vm.expiryDateFrom == nil)
        #expect(vm.expiryDateTo == nil)
        #expect(vm.activeFilterCount == 0)
    }

    // MARK: - Initial Filter

    @Test("test_initialFilter_appliesOnAppear")
    func test_initialFilter_appliesOnAppear() async throws {
        let filter = DVGFilter(type: .voucher, status: .active)
        let (vm, _) = try makeViewModel(initialFilter: filter)

        await vm.onAppear()

        #expect(vm.selectedTypes == [.voucher])
        #expect(vm.selectedStatuses == [.active])
    }

    // MARK: - Empty State

    @Test("test_isEmptyState_noResultsAndNotLoading_returnsTrue")
    func test_isEmptyState_noResultsAndNotLoading_returnsTrue() throws {
        let (vm, _) = try makeViewModel()
        #expect(vm.isEmptyState == true)
    }

    // MARK: - Debounce (Behavioural)

    @Test("test_searchQuery_change_schedulesSearch")
    func test_searchQuery_change_schedulesSearch() async throws {
        let (vm, repo) = try makeViewModel()

        // Set a search query -- this triggers the debounced search
        vm.searchQuery = "test"

        // Wait for debounce (300ms) + margin
        try await Task.sleep(for: .milliseconds(450))

        #expect(repo.searchArgs?.query == "test")
    }

    // MARK: - Swipe Actions

    @Test("test_markAsUsed_callsRepository")
    func test_markAsUsed_callsRepository() async throws {
        let dvg = DVG.testFixture(title: "To Use")
        let (vm, repo) = try makeViewModel(stubbedSearch: [dvg])

        vm.markAsUsed(dvg)

        // Allow the background task to complete
        try await Task.sleep(for: .milliseconds(50))

        #expect(repo.markedUsedDVGs.count == 1)
    }

    @Test("test_delete_callsRepository")
    func test_delete_callsRepository() async throws {
        let dvg = DVG.testFixture(title: "To Delete")
        let (vm, repo) = try makeViewModel(stubbedSearch: [dvg])

        vm.delete(dvg)

        try await Task.sleep(for: .milliseconds(50))

        #expect(repo.softDeletedDVGs.count == 1)
    }
}
