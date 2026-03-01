import Testing
import Foundation
@testable import FastyDiscount

// MARK: - CloudAIClientTests

@Suite("CloudAIClient Tests")
struct CloudAIClientTests {

    // MARK: - Mock CloudAIClient Protocol Tests

    @Test("test_complete_validResponse_returnsText")
    func test_complete_validResponse_returnsText() async throws {
        let mock = MockCloudAIClient()
        mock.stubbedCompleteResponse = "Hello from AI"

        let result = try await mock.complete(prompt: "test", systemPrompt: "system")

        #expect(result == "Hello from AI")
        #expect(mock.completeCallCount == 1)
        #expect(mock.lastPrompt == "test")
        #expect(mock.lastSystemPrompt == "system")
    }

    @Test("test_complete_error_throwsCorrectly")
    func test_complete_error_throwsCorrectly() async {
        let mock = MockCloudAIClient()
        mock.completeError = CloudAIServiceError.noAPIKey

        do {
            _ = try await mock.complete(prompt: "test", systemPrompt: "system")
            Issue.record("Expected error")
        } catch let error as CloudAIServiceError {
            if case .noAPIKey = error {
                // expected
            } else {
                Issue.record("Unexpected error variant: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("test_completeWithVision_validResponse_returnsText")
    func test_completeWithVision_validResponse_returnsText() async throws {
        let mock = MockCloudAIClient()
        mock.stubbedVisionResponse = "Vision result"
        let imageData = Data([0xFF, 0xD8]) // JPEG header

        let result = try await mock.completeWithVision(
            prompt: "describe",
            imageData: imageData,
            systemPrompt: "system"
        )

        #expect(result == "Vision result")
        #expect(mock.completeWithVisionCallCount == 1)
        #expect(mock.lastImageData == imageData)
    }

    @Test("test_completeWithVision_error_throwsCorrectly")
    func test_completeWithVision_error_throwsCorrectly() async {
        let mock = MockCloudAIClient()
        mock.visionError = CloudAIServiceError.networkError(underlying: "timeout")

        do {
            _ = try await mock.completeWithVision(
                prompt: "describe",
                imageData: Data(),
                systemPrompt: "system"
            )
            Issue.record("Expected error")
        } catch let error as CloudAIServiceError {
            if case .networkError(let underlying) = error {
                #expect(underlying == "timeout")
            } else {
                Issue.record("Unexpected error variant: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - CloudAIServiceError Tests

    @Test("test_cloudAIServiceError_descriptions_notEmpty")
    func test_cloudAIServiceError_descriptions_notEmpty() {
        let errors: [CloudAIServiceError] = [
            .noAPIKey,
            .networkError(underlying: "test"),
            .rateLimited,
            .invalidResponse(detail: "bad json"),
            .serverError(statusCode: 500)
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("test_cloudAIServiceError_noAPIKey_containsMessage")
    func test_cloudAIServiceError_noAPIKey_containsMessage() {
        let error = CloudAIServiceError.noAPIKey
        #expect(error.errorDescription?.contains("API key") == true)
    }

    @Test("test_cloudAIServiceError_serverError_containsStatusCode")
    func test_cloudAIServiceError_serverError_containsStatusCode() {
        let error = CloudAIServiceError.serverError(statusCode: 503)
        #expect(error.errorDescription?.contains("503") == true)
    }

    @Test("test_cloudAIServiceError_rateLimited_containsRateLimit")
    func test_cloudAIServiceError_rateLimited_containsRateLimit() {
        let error = CloudAIServiceError.rateLimited
        #expect(error.errorDescription?.contains("Rate limit") == true)
    }
}
