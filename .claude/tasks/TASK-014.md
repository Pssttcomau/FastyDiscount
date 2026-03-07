# TASK-014: Implement email parsing pipeline using Cloud AI service

## Description
Build the pipeline that takes raw emails from the Gmail client and sends them to the Cloud AI service for structured DVG extraction. The pipeline handles batch processing, confidence scoring, and routing results to either auto-save or the review queue.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: L (> 4 hours)
- Routing: code-opus-agent

## Dependencies
- TASK-004 (Cloud AI client)
- TASK-013 (Gmail API client for raw emails)
- TASK-009 (DVGRepository for saving results)

## Acceptance Criteria
- [ ] `EmailParsingService` protocol with `parseEmails(_ emails: [RawEmail]) -> AsyncStream<EmailParseProgress>`
- [ ] Each email sent to `CloudAIClient.complete()` with structured extraction system prompt
- [ ] System prompt instructs AI to extract: title, code, dvgType, storeName, originalValue, discountDescription, expirationDate, termsAndConditions; return as JSON
- [ ] System prompt includes confidence score instruction (0.0-1.0 per field and overall)
- [ ] `EmailParseProgress` enum: `.parsing(index:total:)`, `.parsed(DVGExtractionResult)`, `.failed(index:error:)`, `.complete(results:)`
- [ ] High-confidence results (overall >= 0.8) auto-saved with `ScanResult.needsReview = false`
- [ ] Low-confidence results saved with `ScanResult.needsReview = true` (routed to review queue)
- [ ] `ScanResult` created for each parsed email with `sourceType = "email"`, `emailSubject`, `emailSender`, `emailDate`
- [ ] Dedup check: skip emails that match an existing `ScanResult.emailSubject + emailSender + emailDate`
- [ ] Error handling: continue processing remaining emails if one fails

## Technical Notes
- Use `AsyncStream` to report per-email progress for UI updates
- The system prompt should be a carefully crafted template; consider storing it as a string constant in a dedicated `Prompts` enum/struct
- Example system prompt structure: "You are a discount/voucher extraction assistant. Given the following email, extract any discount codes, vouchers, gift cards, or coupons. Return a JSON object with these fields: ..."
- Batch processing: process sequentially (not parallel) to respect AI API rate limits
- Date parsing: instruct the AI to return dates in ISO 8601 format; parse with `ISO8601DateFormatter`
- Consider a `sinceDate` parameter to only parse emails newer than the last scan
