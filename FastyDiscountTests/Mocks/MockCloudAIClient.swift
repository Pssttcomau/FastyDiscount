import Foundation
@testable import FastyDiscount

// MARK: - MockCloudAIClient

/// Mock implementation of `CloudAIClient` for unit testing.
///
/// Returns pre-configured responses or throws pre-configured errors.
/// Records all calls for verification.
final class MockCloudAIClient: CloudAIClient {

    // MARK: - Recorded Calls

    var completeCallCount = 0
    var lastPrompt: String?
    var lastSystemPrompt: String?
    var completeWithVisionCallCount = 0
    var lastImageData: Data?

    // MARK: - Stubbed Responses

    var stubbedCompleteResponse: String = "{}"
    var stubbedVisionResponse: String = "{}"
    var completeError: Error?
    var visionError: Error?

    // MARK: - CloudAIClient

    func complete(prompt: String, systemPrompt: String) async throws -> String {
        completeCallCount += 1
        lastPrompt = prompt
        lastSystemPrompt = systemPrompt
        if let error = completeError { throw error }
        return stubbedCompleteResponse
    }

    func completeWithVision(prompt: String, imageData: Data, systemPrompt: String) async throws -> String {
        completeWithVisionCallCount += 1
        lastPrompt = prompt
        lastSystemPrompt = systemPrompt
        lastImageData = imageData
        if let error = visionError { throw error }
        return stubbedVisionResponse
    }
}
