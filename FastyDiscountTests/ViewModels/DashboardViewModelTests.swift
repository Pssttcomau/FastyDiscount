import Testing
import Foundation
@testable import FastyDiscount

// MARK: - DashboardViewModelTests

@Suite("DashboardViewModel Tests")
@MainActor
struct DashboardViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(
        stubbedActive: [DVG] = [],
        stubbedExpiring: [DVG] = [],
        stubbedNearby: [DVG] = []
    ) -> (DashboardViewModel, MockDVGRepository) {
        let repo = MockDVGRepository()
        repo.stubbedActive = stubbedActive
        repo.stubbedExpiringSoon = stubbedExpiring
        repo.stubbedNearby = stubbedNearby
        let vm = DashboardViewModel(repository: repo, locationManager: nil)
        return (vm, repo)
    }

    // MARK: - Section Loading

    @Test("test_loadAll_populatesAllSections")
    func test_loadAll_populatesAllSections() async {
        let dvg1 = DVG.testFixture(title: "Expiring")
        let dvg2 = DVG.testFixture(title: "Recent")

        let (vm, repo) = makeViewModel(
            stubbedActive: [dvg2],
            stubbedExpiring: [dvg1]
        )

        await vm.loadAll()

        #expect(vm.expiringSoon.count == 1)
        #expect(vm.recentlyAdded.count == 1)
        #expect(vm.hasLoaded == true)
        #expect(vm.isLoading == false)
    }

    @Test("test_loadAll_setsHasLoadedTrue")
    func test_loadAll_setsHasLoadedTrue() async {
        let (vm, _) = makeViewModel()

        #expect(vm.hasLoaded == false)
        await vm.loadAll()
        #expect(vm.hasLoaded == true)
    }

    @Test("test_loadRecentlyAdded_limitsTo5")
    func test_loadRecentlyAdded_limitsTo5() async {
        let dvgs = (0..<10).map { DVG.testFixture(title: "DVG \($0)") }
        let (vm, _) = makeViewModel(stubbedActive: dvgs)

        await vm.loadRecentlyAdded()

        #expect(vm.recentlyAdded.count == 5)
    }

    // MARK: - Empty States

    @Test("test_hasNoDVGs_whenAllEmpty_returnsTrue")
    func test_hasNoDVGs_whenAllEmpty_returnsTrue() async {
        let (vm, _) = makeViewModel()

        await vm.loadAll()

        #expect(vm.hasNoDVGs == true)
    }

    @Test("test_hasNoDVGs_withActiveDVGs_returnsFalse")
    func test_hasNoDVGs_withActiveDVGs_returnsFalse() async {
        let dvg = DVG.testFixture(title: "Active")
        let (vm, _) = makeViewModel(stubbedActive: [dvg])

        await vm.loadAll()

        #expect(vm.hasNoDVGs == false)
    }

    @Test("test_hasNoDVGs_notLoaded_returnsFalse")
    func test_hasNoDVGs_notLoaded_returnsFalse() {
        let (vm, _) = makeViewModel()
        // Not loaded yet
        #expect(vm.hasNoDVGs == false)
    }

    // MARK: - Nearby Section Visibility

    @Test("test_showNearbySection_noLocation_returnsFalse")
    func test_showNearbySection_noLocation_returnsFalse() async {
        let (vm, _) = makeViewModel()
        await vm.loadAll()
        #expect(vm.showNearbySection == false)
    }

    // MARK: - Error Handling

    @Test("test_loadExpiringSoon_error_setsErrorMessage")
    func test_loadExpiringSoon_error_setsErrorMessage() async {
        let (vm, repo) = makeViewModel()
        repo.fetchExpiringSoonError = DVGRepositoryError.fetchFailed("test error")

        await vm.loadExpiringSoon()

        #expect(vm.showError == true)
        #expect(vm.errorMessage?.contains("Expiring Soon") == true)
    }

    @Test("test_loadRecentlyAdded_error_setsErrorMessage")
    func test_loadRecentlyAdded_error_setsErrorMessage() async {
        let (vm, repo) = makeViewModel()
        repo.fetchActiveError = DVGRepositoryError.fetchFailed("db error")

        await vm.loadRecentlyAdded()

        #expect(vm.showError == true)
        #expect(vm.errorMessage?.contains("Recently Added") == true)
    }

    // MARK: - Favourite Toggle

    @Test("test_toggleFavorite_togglesValue")
    func test_toggleFavorite_togglesValue() {
        let dvg = DVG.testFixture(isFavorite: false)
        let (vm, _) = makeViewModel()

        vm.toggleFavorite(dvg)

        #expect(dvg.isFavorite == true)
    }

    @Test("test_toggleFavorite_updatesLastModified")
    func test_toggleFavorite_updatesLastModified() {
        let dvg = DVG.testFixture(isFavorite: false, lastModified: Date.distantPast)
        let (vm, _) = makeViewModel()

        vm.toggleFavorite(dvg)

        #expect(dvg.lastModified > Date.distantPast)
    }

    // MARK: - Refresh

    @Test("test_refresh_reloadsAllSections")
    func test_refresh_reloadsAllSections() async {
        let (vm, repo) = makeViewModel()

        await vm.refresh()

        #expect(repo.fetchExpiringSoonDays == 7)
        #expect(repo.fetchActiveCalled == true)
    }
}
