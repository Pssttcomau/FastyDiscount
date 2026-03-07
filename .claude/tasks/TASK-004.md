# TASK-004: Build Cloud AI API client abstraction (OpenAI + Anthropic)

## Description
Create a protocol-based Cloud AI client that supports both OpenAI and Anthropic APIs. This client is used by both email parsing (TASK-014) and vision OCR parsing (TASK-019). The user selects their provider and enters their API key in Settings. The abstraction must support text completion and vision (image + text) completion.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-001 (project structure)

## Acceptance Criteria
- [ ] `CloudAIClient` protocol defined with `complete(prompt:systemPrompt:)` and `completeWithVision(prompt:imageData:systemPrompt:)` methods
- [ ] `OpenAIClient` implementation using OpenAI Chat Completions API (`gpt-4o` model)
- [ ] `AnthropicClient` implementation using Anthropic Messages API (`claude-sonnet-4-20250514` model)
- [ ] Both clients support structured JSON output (system prompt enforces JSON schema)
- [ ] API key stored securely in Keychain via `KeychainService`
- [ ] `KeychainService` utility created for secure storage (API keys, OAuth tokens)
- [ ] `CloudAIServiceError` enum with cases: `noAPIKey`, `networkError`, `rateLimited`, `invalidResponse`, `serverError`
- [ ] Retry logic with exponential backoff for transient failures (429, 500, 503)
- [ ] Request timeout of 30 seconds
- [ ] `DVGExtractionResult` Codable struct defined (shared output format for both email and vision parsing)
- [ ] All types conform to `Sendable` for Swift 6 strict concurrency

## Technical Notes
- OpenAI endpoint: `https://api.openai.com/v1/chat/completions`
- Anthropic endpoint: `https://api.anthropic.com/v1/messages`
- For vision: OpenAI uses `image_url` content part with base64 data URI; Anthropic uses `image` content block with base64 `source`
- JSON mode: OpenAI uses `response_format: { type: "json_object" }`; Anthropic relies on system prompt instruction
- Use `URLSession` async/await -- no third-party HTTP libraries
- The `DVGExtractionResult` struct should match the fields in the architecture doc (title, code, dvgType, storeName, originalValue, discountDescription, expirationDate, termsAndConditions, confidenceScore, fieldConfidences)
- Consider a `CloudAIClientFactory` that creates the right client based on user's provider preference
