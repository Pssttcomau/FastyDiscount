# TASK-019: Implement Cloud AI vision parsing for text coupons and flyers

## Description
When a scanned or imported image contains text (not just a barcode), send the image and extracted OCR text to the Cloud AI service for intelligent DVG field extraction. This handles complex coupon layouts, promotional flyers, and screenshots that need AI interpretation.

## Assigned Agent
code

## Priority & Complexity
- Priority: High
- Complexity: M (1-4 hours)
- Routing: code-agent

## Dependencies
- TASK-004 (Cloud AI client with vision support)
- TASK-017 or TASK-018 (provides images and extracted text)

## Acceptance Criteria
- [ ] `VisionParsingService` that accepts image data and optional pre-extracted OCR text
- [ ] Calls `CloudAIClient.completeWithVision()` with image and structured extraction prompt
- [ ] System prompt optimized for visual coupon/flyer parsing (extracts store, code, value, expiry, terms)
- [ ] Returns `DVGExtractionResult` with confidence scores
- [ ] Image compressed/resized before sending to API (max 1024px longest edge, JPEG quality 0.7)
- [ ] Fallback: if no network, return just the raw OCR text for manual DVG creation
- [ ] Cost awareness: log approximate token usage per request (for user's API cost tracking)
- [ ] Results integrate with scan results UI (TASK-020) for DVG creation

## Technical Notes
- For OpenAI: send image as base64 data URI in the `image_url` content part
- For Anthropic: send image as base64 in `image` content block with `media_type: "image/jpeg"`
- Resize using `UIGraphicsImageRenderer` to keep under API size limits and reduce cost
- The system prompt should be distinct from the email parsing prompt -- it should emphasize visual layout interpretation
- Consider including the OCR text in the prompt alongside the image for better extraction accuracy
- Token logging: OpenAI returns `usage.total_tokens`; Anthropic returns `usage.input_tokens + output_tokens`
