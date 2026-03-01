import Foundation
@testable import FastyDiscount

// MARK: - MockEmailParsingService

/// Mock implementation of `EmailParsingService` for unit testing.
@MainActor
final class MockEmailParsingService: EmailParsingService {

    // MARK: - Recorded Calls

    var parseEmailsCallCount = 0
    var lastEmails: [RawEmail] = []
    var lastSinceDate: Date?

    // MARK: - Stubbed Responses

    /// The progress events to yield from the returned stream.
    var stubbedProgressEvents: [EmailParseProgress] = []

    // MARK: - EmailParsingService

    func parseEmails(
        _ emails: [RawEmail],
        sinceDate: Date?
    ) -> AsyncStream<EmailParseProgress> {
        parseEmailsCallCount += 1
        lastEmails = emails
        lastSinceDate = sinceDate

        let events = stubbedProgressEvents
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
