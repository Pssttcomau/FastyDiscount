import Testing
import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - DVGFormViewModelTests

@Suite("DVGFormViewModel Tests")
@MainActor
struct DVGFormViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(
        mode: DVGFormMode = .create(.manual)
    ) throws -> (DVGFormViewModel, MockDVGRepository, ModelContext) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()
        let vm = DVGFormViewModel(mode: mode, repository: repo, modelContext: context)
        return (vm, repo, context)
    }

    // MARK: - Validation

    @Test("test_validate_emptyTitle_returnsFalseWithError")
    func test_validate_emptyTitle_returnsFalseWithError() throws {
        let (vm, _, _) = try makeViewModel()
        vm.title = ""
        vm.storeName = "Store"

        let result = vm.validate()

        #expect(result == false)
        #expect(vm.titleError != nil)
        #expect(vm.titleError?.contains("required") == true)
    }

    @Test("test_validate_emptyStoreName_returnsFalseWithError")
    func test_validate_emptyStoreName_returnsFalseWithError() throws {
        let (vm, _, _) = try makeViewModel()
        vm.title = "Title"
        vm.storeName = ""

        let result = vm.validate()

        #expect(result == false)
        #expect(vm.storeNameError != nil)
        #expect(vm.storeNameError?.contains("required") == true)
    }

    @Test("test_validate_validFields_returnsTrue")
    func test_validate_validFields_returnsTrue() throws {
        let (vm, _, _) = try makeViewModel()
        vm.title = "My Discount"
        vm.storeName = "My Store"

        let result = vm.validate()

        #expect(result == true)
        #expect(vm.titleError == nil)
        #expect(vm.storeNameError == nil)
    }

    @Test("test_validate_whitespaceOnlyTitle_returnsFalse")
    func test_validate_whitespaceOnlyTitle_returnsFalse() throws {
        let (vm, _, _) = try makeViewModel()
        vm.title = "   "
        vm.storeName = "Store"

        let result = vm.validate()

        #expect(result == false)
    }

    // MARK: - isValid Computed Property

    @Test("test_isValid_bothFieldsPopulated_returnsTrue")
    func test_isValid_bothFieldsPopulated_returnsTrue() throws {
        let (vm, _, _) = try makeViewModel()
        vm.title = "Title"
        vm.storeName = "Store"

        #expect(vm.isValid == true)
    }

    @Test("test_isValid_missingTitle_returnsFalse")
    func test_isValid_missingTitle_returnsFalse() throws {
        let (vm, _, _) = try makeViewModel()
        vm.title = ""
        vm.storeName = "Store"

        #expect(vm.isValid == false)
    }

    // MARK: - Save (Create Mode)

    @Test("test_save_validData_callsRepositorySave")
    func test_save_validData_callsRepositorySave() async throws {
        let (vm, repo, _) = try makeViewModel()
        vm.title = "New Item"
        vm.storeName = "New Store"
        vm.code = "CODE123"

        await vm.save()

        #expect(repo.savedDVGs.count == 1)
        #expect(repo.savedDVGs.first?.title == "New Item")
        #expect(repo.savedDVGs.first?.storeName == "New Store")
    }

    @Test("test_save_invalidData_doesNotCallRepository")
    func test_save_invalidData_doesNotCallRepository() async throws {
        let (vm, repo, _) = try makeViewModel()
        vm.title = ""
        vm.storeName = ""

        await vm.save()

        #expect(repo.savedDVGs.isEmpty)
    }

    @Test("test_save_withExpirationDate_setsExpirationOnDVG")
    func test_save_withExpirationDate_setsExpirationOnDVG() async throws {
        let (vm, repo, _) = try makeViewModel()
        vm.title = "Expiring Item"
        vm.storeName = "Store"
        vm.hasExpirationDate = true
        let futureDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        vm.expirationDate = futureDate

        await vm.save()

        #expect(repo.savedDVGs.first?.expirationDate != nil)
    }

    @Test("test_save_withoutExpirationDate_nilExpiration")
    func test_save_withoutExpirationDate_nilExpiration() async throws {
        let (vm, repo, _) = try makeViewModel()
        vm.title = "No Expiry"
        vm.storeName = "Store"
        vm.hasExpirationDate = false

        await vm.save()

        #expect(repo.savedDVGs.first?.expirationDate == nil)
    }

    @Test("test_save_error_setsErrorMessage")
    func test_save_error_setsErrorMessage() async throws {
        let (vm, repo, _) = try makeViewModel()
        vm.title = "Title"
        vm.storeName = "Store"
        repo.saveError = DVGRepositoryError.saveFailed("disk full")

        await vm.save()

        #expect(vm.showError == true)
        #expect(vm.errorMessage != nil)
    }

    @Test("test_save_duplicateWarning_showsWarning")
    func test_save_duplicateWarning_showsWarning() async throws {
        let (vm, repo, _) = try makeViewModel()
        vm.title = "Title"
        vm.storeName = "Store"
        repo.stubbedSaveResult = .savedWithDuplicateWarning("Existing item found")

        await vm.save()

        #expect(vm.showDuplicateWarning == true)
        #expect(vm.duplicateWarningMessage.contains("Existing"))
    }

    // MARK: - Edit Mode Population

    @Test("test_editMode_populatesFieldsFromDVG")
    func test_editMode_populatesFieldsFromDVG() throws {
        let dvg = DVG.testFixture(
            title: "Edit Me",
            code: "EDITCODE",
            storeName: "Edit Store",
            dvgType: .giftCard,
            originalValue: 50.0,
            remainingBalance: 25.0,
            discountDescription: "Half off",
            isFavorite: true,
            notificationLeadDays: 3
        )
        dvg.expirationDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())

        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()
        let vm = DVGFormViewModel(mode: .edit(dvg), repository: repo, modelContext: context)

        #expect(vm.title == "Edit Me")
        #expect(vm.code == "EDITCODE")
        #expect(vm.storeName == "Edit Store")
        #expect(vm.dvgType == .giftCard)
        #expect(vm.originalValue == "50.0")
        #expect(vm.remainingBalance == "25.0")
        #expect(vm.discountDescription == "Half off")
        #expect(vm.isFavorite == true)
        #expect(vm.hasExpirationDate == true)
        #expect(vm.notificationLeadDays == 3)
    }

    @Test("test_isEditMode_createMode_returnsFalse")
    func test_isEditMode_createMode_returnsFalse() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.isEditMode == false)
    }

    @Test("test_isEditMode_editMode_returnsTrue")
    func test_isEditMode_editMode_returnsTrue() throws {
        let dvg = DVG.testFixture()
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()
        let vm = DVGFormViewModel(mode: .edit(dvg), repository: repo, modelContext: context)

        #expect(vm.isEditMode == true)
    }

    // MARK: - Navigation Title

    @Test("test_navigationTitle_createMode_isNewItem")
    func test_navigationTitle_createMode_isNewItem() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.navigationTitle == "New Item")
    }

    @Test("test_navigationTitle_editMode_isEditItem")
    func test_navigationTitle_editMode_isEditItem() throws {
        let dvg = DVG.testFixture()
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let repo = MockDVGRepository()
        let vm = DVGFormViewModel(mode: .edit(dvg), repository: repo, modelContext: context)

        #expect(vm.navigationTitle == "Edit Item")
    }

    // MARK: - DVG Type Dependent Fields

    @Test("test_showBalanceField_giftCard_returnsTrue")
    func test_showBalanceField_giftCard_returnsTrue() throws {
        let (vm, _, _) = try makeViewModel()
        vm.dvgType = .giftCard
        #expect(vm.showBalanceField == true)
    }

    @Test("test_showBalanceField_discountCode_returnsFalse")
    func test_showBalanceField_discountCode_returnsFalse() throws {
        let (vm, _, _) = try makeViewModel()
        vm.dvgType = .discountCode
        #expect(vm.showBalanceField == false)
    }

    @Test("test_showPointsField_loyaltyPoints_returnsTrue")
    func test_showPointsField_loyaltyPoints_returnsTrue() throws {
        let (vm, _, _) = try makeViewModel()
        vm.dvgType = .loyaltyPoints
        #expect(vm.showPointsField == true)
    }

    // MARK: - Clear Validation Errors

    @Test("test_clearTitleError_clearsError")
    func test_clearTitleError_clearsError() throws {
        let (vm, _, _) = try makeViewModel()
        vm.titleError = "Title is required"

        vm.clearTitleError()

        #expect(vm.titleError == nil)
    }

    @Test("test_clearStoreNameError_clearsError")
    func test_clearStoreNameError_clearsError() throws {
        let (vm, _, _) = try makeViewModel()
        vm.storeNameError = "Store name is required"

        vm.clearStoreNameError()

        #expect(vm.storeNameError == nil)
    }

    // MARK: - Focus Management

    @Test("test_nextField_afterTitle_returnsCode")
    func test_nextField_afterTitle_returnsCode() throws {
        let (vm, _, _) = try makeViewModel()
        let next = vm.nextField(after: .title)
        #expect(next == .code)
    }

    @Test("test_nextField_afterLastQuickField_returnsNil")
    func test_nextField_afterLastQuickField_returnsNil() throws {
        let (vm, _, _) = try makeViewModel()
        vm.showAllFields = false
        let next = vm.nextField(after: .storeName)
        #expect(next == nil)
    }

    // MARK: - Notification Options

    @Test("test_notificationLeadDayOptions_containsExpectedValues")
    func test_notificationLeadDayOptions_containsExpectedValues() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.notificationLeadDayOptions.contains(0))
        #expect(vm.notificationLeadDayOptions.contains(1))
        #expect(vm.notificationLeadDayOptions.contains(7))
        #expect(vm.notificationLeadDayOptions.contains(30))
    }

    @Test("test_notificationLeadDayLabel_zero_returnsNone")
    func test_notificationLeadDayLabel_zero_returnsNone() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.notificationLeadDayLabel(for: 0) == "None")
    }

    @Test("test_notificationLeadDayLabel_one_returnsSingular")
    func test_notificationLeadDayLabel_one_returnsSingular() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.notificationLeadDayLabel(for: 1) == "1 day before")
    }

    @Test("test_notificationLeadDayLabel_multiple_returnsPlural")
    func test_notificationLeadDayLabel_multiple_returnsPlural() throws {
        let (vm, _, _) = try makeViewModel()
        #expect(vm.notificationLeadDayLabel(for: 7) == "7 days before")
    }
}
