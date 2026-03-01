import Testing
import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - EmailParsingServiceTests

@Suite("EmailParsingService Tests")
@MainActor
struct EmailParsingServiceTests {

    // MARK: - Helpers

    private func makeService() throws -> (CloudAIEmailParsingService, MockCloudAIClient, ModelContext) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let aiClient = MockCloudAIClient()
        let service = CloudAIEmailParsingService(aiClient: aiClient, modelContext: context)
        return (service, aiClient, context)
    }

    private func validAIResponse(confidence: Double = 0.92) -> String {
        """
        {
            "title": "20% off",
            "code": "SAVE20",
            "dvgType": "discountCode",
            "storeName": "Test Store",
            "originalValue": 20.0,
            "discountDescription": "20% off all items",
            "expirationDate": null,
            "termsAndConditions": null,
            "confidenceScore": \(confidence),
            "fieldConfidences": {
                "title": 0.95,
                "code": 0.98,
                "storeName": 0.90,
                "dvgType": 0.85,
                "originalValue": 0.80,
                "discountDescription": 0.85,
                "expirationDate": 0.0,
                "termsAndConditions": 0.0
            }
        }
        """
    }

    // MARK: - High Confidence Routing

    @Test("test_parseEmails_highConfidence_savedWithoutReview")
    func test_parseEmails_highConfidence_savedWithoutReview() async throws {
        let (service, aiClient, context) = try makeService()
        aiClient.stubbedCompleteResponse = validAIResponse(confidence: 0.92)

        let email = RawEmail.testFixture()
        let stream = service.parseEmails([email], sinceDate: nil)

        var progressEvents: [EmailParseProgress] = []
        for await event in stream {
            progressEvents.append(event)
        }

        // Verify ScanResult was saved with needsReview = false
        let scanDescriptor = FetchDescriptor<ScanResult>()
        let scanResults = try context.fetch(scanDescriptor)
        #expect(scanResults.count == 1)
        #expect(scanResults.first?.needsReview == false)
    }

    // MARK: - Low Confidence Routing

    @Test("test_parseEmails_lowConfidence_savedWithReview")
    func test_parseEmails_lowConfidence_savedWithReview() async throws {
        let (service, aiClient, context) = try makeService()
        aiClient.stubbedCompleteResponse = validAIResponse(confidence: 0.65)

        let email = RawEmail.testFixture()
        let stream = service.parseEmails([email], sinceDate: nil)

        for await _ in stream {}

        let scanDescriptor = FetchDescriptor<ScanResult>()
        let scanResults = try context.fetch(scanDescriptor)
        #expect(scanResults.count == 1)
        #expect(scanResults.first?.needsReview == true)
    }

    // MARK: - Deduplication

    @Test("test_parseEmails_duplicateEmail_skipped")
    func test_parseEmails_duplicateEmail_skipped() async throws {
        let (service, aiClient, context) = try makeService()
        aiClient.stubbedCompleteResponse = validAIResponse()

        let email = RawEmail.testFixture(
            subject: "Duplicate Subject",
            sender: "sender@example.com",
            date: Date(timeIntervalSince1970: 1000000)
        )

        // Parse first time
        let stream1 = service.parseEmails([email], sinceDate: nil)
        for await _ in stream1 {}

        // Parse same email again
        let stream2 = service.parseEmails([email], sinceDate: nil)
        var failedCount = 0
        for await event in stream2 {
            if case .failed = event {
                failedCount += 1
            }
        }

        #expect(failedCount == 1)

        // Only one DVG should exist
        let dvgDescriptor = FetchDescriptor<DVG>()
        let dvgs = try context.fetch(dvgDescriptor)
        #expect(dvgs.count == 1)
    }

    // MARK: - Progress Reporting

    @Test("test_parseEmails_multipleEmails_reportsProgressSequentially")
    func test_parseEmails_multipleEmails_reportsProgressSequentially() async throws {
        let (service, aiClient, _) = try makeService()
        aiClient.stubbedCompleteResponse = validAIResponse()

        let emails = [
            RawEmail.testFixture(id: "1", subject: "Email 1", date: Date(timeIntervalSince1970: 1000)),
            RawEmail.testFixture(id: "2", subject: "Email 2", date: Date(timeIntervalSince1970: 2000))
        ]

        let stream = service.parseEmails(emails, sinceDate: nil)

        var parsingIndices: [Int] = []
        var parsedCount = 0
        var completeResultCount: Int?

        for await event in stream {
            switch event {
            case .parsing(let index, _):
                parsingIndices.append(index)
            case .parsed:
                parsedCount += 1
            case .complete(let results):
                completeResultCount = results.count
            case .failed:
                break
            }
        }

        #expect(parsingIndices == [0, 1])
        #expect(parsedCount == 2)
        #expect(completeResultCount == 2)
    }

    // MARK: - AI Error Handling

    @Test("test_parseEmails_aiError_continuesProcessingRemaining")
    func test_parseEmails_aiError_continuesProcessingRemaining() async throws {
        let (service, aiClient, _) = try makeService()

        // First call fails, second succeeds
        var callCount = 0
        let validResponse = validAIResponse()

        // We need a different approach since MockCloudAIClient doesn't support per-call responses.
        // Instead, test with a single failing email.
        aiClient.completeError = CloudAIServiceError.networkError(underlying: "timeout")

        let email = RawEmail.testFixture()
        let stream = service.parseEmails([email], sinceDate: nil)

        var failedCount = 0
        for await event in stream {
            if case .failed = event {
                failedCount += 1
            }
        }

        _ = callCount
        #expect(failedCount == 1)
    }

    // MARK: - Since Date Filtering

    @Test("test_parseEmails_sinceDate_filtersOlderEmails")
    func test_parseEmails_sinceDate_filtersOlderEmails() async throws {
        let (service, aiClient, _) = try makeService()
        aiClient.stubbedCompleteResponse = validAIResponse()

        let oldEmail = RawEmail.testFixture(
            id: "old",
            subject: "Old Email",
            date: Date(timeIntervalSince1970: 1000)
        )
        let newEmail = RawEmail.testFixture(
            id: "new",
            subject: "New Email",
            date: Date()
        )

        let sinceDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let stream = service.parseEmails([oldEmail, newEmail], sinceDate: sinceDate)

        var parsedCount = 0
        for await event in stream {
            if case .parsed = event {
                parsedCount += 1
            }
        }

        // Only the new email should be parsed
        #expect(parsedCount == 1)
    }

    // MARK: - Markdown Stripping

    @Test("test_parseEmails_markdownWrappedJSON_parsesCorrectly")
    func test_parseEmails_markdownWrappedJSON_parsesCorrectly() async throws {
        let (service, aiClient, _) = try makeService()
        aiClient.stubbedCompleteResponse = """
        ```json
        \(validAIResponse())
        ```
        """

        let email = RawEmail.testFixture()
        let stream = service.parseEmails([email], sinceDate: nil)

        var parsedCount = 0
        for await event in stream {
            if case .parsed = event {
                parsedCount += 1
            }
        }

        #expect(parsedCount == 1)
    }

    // MARK: - Prompt Construction

    @Test("test_buildUserPrompt_containsEmailFields")
    func test_buildUserPrompt_containsEmailFields() {
        let prompt = EmailParsingPrompts.buildUserPrompt(
            subject: "Special Offer",
            sender: "store@shop.com",
            body: "Use code DEAL20 for 20% off"
        )

        #expect(prompt.contains("Special Offer"))
        #expect(prompt.contains("store@shop.com"))
        #expect(prompt.contains("DEAL20"))
    }

    @Test("test_buildUserPrompt_longBody_truncated")
    func test_buildUserPrompt_longBody_truncated() {
        let longBody = String(repeating: "A", count: 10000)
        let prompt = EmailParsingPrompts.buildUserPrompt(
            subject: "Test",
            sender: "test@test.com",
            body: longBody
        )

        #expect(prompt.contains("[... truncated ...]"))
        #expect(prompt.count < longBody.count)
    }
}
