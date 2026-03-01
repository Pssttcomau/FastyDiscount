import Testing
import Foundation
@testable import FastyDiscount

// MARK: - EmailScanViewModelTests

@Suite("EmailScanViewModel Tests")
@MainActor
struct EmailScanViewModelTests {

    // MARK: - Helpers

    private func makeViewModel() -> (
        EmailScanViewModel,
        MockGmailAuthService,
        MockGmailAPIClient,
        MockEmailParsingService
    ) {
        let authService = MockGmailAuthService()
        let apiClient = MockGmailAPIClient()
        let parsingService = MockEmailParsingService()
        let vm = EmailScanViewModel(
            authService: authService,
            apiClient: apiClient,
            parsingService: parsingService
        )
        return (vm, authService, apiClient, parsingService)
    }

    // MARK: - Gmail Connection

    @Test("test_connectGmail_success_setsConnected")
    func test_connectGmail_success_setsConnected() async {
        let (vm, _, _, _) = makeViewModel()

        await vm.connectGmail()

        #expect(vm.isGmailConnected == true)
        #expect(vm.isConnecting == false)
    }

    @Test("test_connectGmail_userCancelled_noError")
    func test_connectGmail_userCancelled_noError() async {
        let (vm, auth, _, _) = makeViewModel()
        auth.authenticateError = GmailAuthError.userCancelled

        await vm.connectGmail()

        #expect(vm.isGmailConnected == false)
        #expect(vm.showError == false)
    }

    @Test("test_connectGmail_error_showsError")
    func test_connectGmail_error_showsError() async {
        let (vm, auth, _, _) = makeViewModel()
        auth.authenticateError = GmailAuthError.networkError(underlying: "timeout")

        await vm.connectGmail()

        #expect(vm.showError == true)
        #expect(!vm.errorMessage.isEmpty)
    }

    @Test("test_disconnectGmail_clearsConnection")
    func test_disconnectGmail_clearsConnection() async {
        let (vm, auth, _, _) = makeViewModel()
        auth.isAuthenticated = true
        vm.isGmailConnected = true

        await vm.disconnectGmail()

        #expect(vm.isGmailConnected == false)
    }

    // MARK: - Scan State

    @Test("test_startScan_notConnected_failsWithMessage")
    func test_startScan_notConnected_failsWithMessage() async throws {
        let (vm, _, _, _) = makeViewModel()
        vm.isGmailConnected = false

        vm.startScan()

        // Allow the pipeline task to execute
        try await Task.sleep(for: .milliseconds(100))

        if case .failed(let message) = vm.scanState {
            #expect(message.contains("not connected"))
        } else {
            Issue.record("Expected failed state but got \(vm.scanState)")
        }
    }

    @Test("test_startScan_noEmails_completesWithZeroResults")
    func test_startScan_noEmails_completesWithZeroResults() async throws {
        let (vm, auth, api, _) = makeViewModel()
        auth.isAuthenticated = true
        vm.isGmailConnected = true
        api.stubbedEmailPages = [EmailFetchPage(emails: [], nextPageToken: nil)]

        vm.startScan()
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.scanState == .complete)
        #expect(vm.scanSummary?.totalDVGsFound == 0)
    }

    @Test("test_cancelScan_resetsState")
    func test_cancelScan_resetsState() {
        let (vm, _, _, _) = makeViewModel()
        vm.scanState = .parsing(current: 3, total: 10)

        vm.cancelScan()

        #expect(vm.scanState == .idle)
        #expect(vm.emailStatuses.isEmpty)
        #expect(vm.progressFraction == 0.0)
        #expect(vm.scanSummary == nil)
    }

    // MARK: - Scope Settings

    @Test("test_currentScope_respectsSettings")
    func test_currentScope_respectsSettings() {
        let (vm, _, _, _) = makeViewModel()
        vm.selectedLabels = ["CATEGORY_PROMOTIONS", "CATEGORY_UPDATES"]
        vm.senderWhitelist = ["store@example.com"]
        vm.scanFullInbox = false

        let scope = vm.currentScope

        #expect(scope.selectedLabels.count == 2)
        #expect(scope.senderWhitelist.count == 1)
        #expect(scope.scanFullInbox == false)
    }

    @Test("test_currentScope_fullInbox_emptiesLabels")
    func test_currentScope_fullInbox_emptiesLabels() {
        let (vm, _, _, _) = makeViewModel()
        vm.scanFullInbox = true
        vm.selectedLabels = ["CATEGORY_PROMOTIONS"]

        let scope = vm.currentScope

        #expect(scope.selectedLabels.isEmpty)
        #expect(scope.scanFullInbox == true)
    }

    // MARK: - Sender Whitelist

    @Test("test_addSenderToWhitelist_addsAndClearsInput")
    func test_addSenderToWhitelist_addsAndClearsInput() {
        let (vm, _, _, _) = makeViewModel()
        vm.senderWhitelist = []
        vm.newSenderText = "store@example.com"

        vm.addSenderToWhitelist()

        #expect(vm.senderWhitelist.contains("store@example.com"))
        #expect(vm.newSenderText.isEmpty)
    }

    @Test("test_addSenderToWhitelist_emptyText_doesNotAdd")
    func test_addSenderToWhitelist_emptyText_doesNotAdd() {
        let (vm, _, _, _) = makeViewModel()
        vm.senderWhitelist = []
        vm.newSenderText = "   "

        vm.addSenderToWhitelist()

        #expect(vm.senderWhitelist.isEmpty)
    }

    @Test("test_addSenderToWhitelist_duplicate_doesNotAdd")
    func test_addSenderToWhitelist_duplicate_doesNotAdd() {
        let (vm, _, _, _) = makeViewModel()
        vm.senderWhitelist = ["store@example.com"]
        vm.newSenderText = "store@example.com"

        vm.addSenderToWhitelist()

        #expect(vm.senderWhitelist.count == 1)
    }

    @Test("test_removeSenders_removesCorrectIndices")
    func test_removeSenders_removesCorrectIndices() {
        let (vm, _, _, _) = makeViewModel()
        vm.senderWhitelist = ["a@test.com", "b@test.com", "c@test.com"]

        vm.removeSenders(at: IndexSet(integer: 1))

        #expect(vm.senderWhitelist == ["a@test.com", "c@test.com"])
    }

    // MARK: - Full Inbox Toggle

    @Test("test_toggleFullInbox_enable_showsWarning")
    func test_toggleFullInbox_enable_showsWarning() {
        let (vm, _, _, _) = makeViewModel()

        vm.toggleFullInbox(true)

        #expect(vm.showFullInboxWarning == true)
        #expect(vm.scanFullInbox == false) // Not yet confirmed
    }

    @Test("test_confirmFullInboxScan_enablesFullInbox")
    func test_confirmFullInboxScan_enablesFullInbox() {
        let (vm, _, _, _) = makeViewModel()
        vm.showFullInboxWarning = true

        vm.confirmFullInboxScan()

        #expect(vm.scanFullInbox == true)
        #expect(vm.showFullInboxWarning == false)
    }

    @Test("test_toggleFullInbox_disable_noWarning")
    func test_toggleFullInbox_disable_noWarning() {
        let (vm, _, _, _) = makeViewModel()
        vm.scanFullInbox = true

        vm.toggleFullInbox(false)

        #expect(vm.scanFullInbox == false)
        #expect(vm.showFullInboxWarning == false)
    }
}
