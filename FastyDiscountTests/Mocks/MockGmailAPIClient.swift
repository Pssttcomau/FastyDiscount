import Foundation
@testable import FastyDiscount

// MARK: - MockGmailAPIClient

/// Mock implementation of `GmailAPIClient` for unit testing.
final class MockGmailAPIClient: GmailAPIClient {

    // MARK: - Recorded Calls

    var fetchEmailsCallCount = 0
    var lastScope: EmailScanScope?
    var lastMaxResults: Int?
    var lastPageToken: String?

    // MARK: - Stubbed Responses

    var stubbedEmailPages: [EmailFetchPage] = []
    var fetchEmailsError: Error?

    /// Index into `stubbedEmailPages` for sequential calls.
    private var pageIndex = 0

    // MARK: - GmailAPIClient

    func fetchEmails(
        scope: EmailScanScope,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailFetchPage {
        fetchEmailsCallCount += 1
        lastScope = scope
        lastMaxResults = maxResults
        lastPageToken = pageToken
        if let error = fetchEmailsError { throw error }

        guard pageIndex < stubbedEmailPages.count else {
            return EmailFetchPage(emails: [], nextPageToken: nil)
        }

        let page = stubbedEmailPages[pageIndex]
        pageIndex += 1
        return page
    }

    /// Resets the page counter for a fresh sequence of calls.
    func resetPageIndex() {
        pageIndex = 0
    }
}
