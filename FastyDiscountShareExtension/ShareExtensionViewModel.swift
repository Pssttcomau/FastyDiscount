import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ShareExtensionState

/// The processing state of the share extension.
enum ShareExtensionState: Sendable {
    /// Currently loading and processing the shared content.
    case processing
    /// Processing complete; the form is ready for user input.
    case ready
    /// An error occurred during processing.
    case error(String)
    /// The DVG was saved successfully.
    case saved
}

// MARK: - ShareExtensionViewModel

/// ViewModel for the share extension DVG creation form.
///
/// Manages content extraction from `NSItemProvider`, pre-populates form fields
/// from extraction results, and saves the new DVG to the shared SwiftData
/// container via App Group.
///
/// All state is `@MainActor` to safely drive the SwiftUI form.
@Observable
@MainActor
final class ShareExtensionViewModel {

    // MARK: - Form Fields

    var title: String = ""
    var code: String = ""
    var storeName: String = ""
    var selectedDVGType: DVGType = .discountCode
    var notes: String = ""
    var discountDescription: String = ""

    // MARK: - State

    var state: ShareExtensionState = .processing
    var extractionResult: ShareExtractionResult?

    // MARK: - Private Properties

    private let contentProcessor = ShareExtensionContentProcessor()
    private var modelContainer: ModelContainer?

    // MARK: - Init

    init() {}

    // MARK: - Content Processing

    /// Loads and processes the shared item from the extension context.
    ///
    /// Determines the content type (text, URL, image, PDF) and delegates
    /// to the appropriate processor method. Updates form fields with
    /// extraction results.
    func processSharedItems(from extensionContext: NSExtensionContext?) async {
        state = .processing

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            state = .error("No content received.")
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                if let result = await processAttachment(attachment) {
                    extractionResult = result
                    populateForm(from: result)
                    state = .ready
                    return
                }
            }
        }

        // No processable attachment found
        state = .ready
    }

    /// Processes a single NSItemProvider attachment.
    private func processAttachment(_ provider: NSItemProvider) async -> ShareExtractionResult? {
        // Try each type in order of specificity

        // 1. PDF
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await processPDFAttachment(provider)
        }

        // 2. Image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await processImageAttachment(provider)
        }

        // 3. URL
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await processURLAttachment(provider)
        }

        // 4. Plain text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await processTextAttachment(provider)
        }

        return nil
    }

    // MARK: - Attachment Type Processors

    private func processTextAttachment(_ provider: NSItemProvider) async -> ShareExtractionResult? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)

            if let text = item as? String {
                return await contentProcessor.processText(text)
            }

            if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                return await contentProcessor.processText(text)
            }
        } catch {
            // Fall through
        }
        return nil
    }

    private func processURLAttachment(_ provider: NSItemProvider) async -> ShareExtractionResult? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)

            if let url = item as? URL {
                return await contentProcessor.processURL(url)
            }

            if let data = item as? Data, let urlString = String(data: data, encoding: .utf8),
               let url = URL(string: urlString) {
                return await contentProcessor.processURL(url)
            }
        } catch {
            // Fall through
        }
        return nil
    }

    private func processImageAttachment(_ provider: NSItemProvider) async -> ShareExtractionResult? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)

            if let image = item as? UIImage {
                return await contentProcessor.processImage(image)
            }

            if let url = item as? URL, let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return await contentProcessor.processImage(image)
            }

            if let data = item as? Data, let image = UIImage(data: data) {
                return await contentProcessor.processImage(image)
            }
        } catch {
            // Fall through
        }
        return nil
    }

    private func processPDFAttachment(_ provider: NSItemProvider) async -> ShareExtractionResult? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier)

            if let url = item as? URL {
                return await contentProcessor.processPDF(at: url)
            }

            // If we got Data, write to temp file for PDFKit
            if let data = item as? Data {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                try data.write(to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                return await contentProcessor.processPDF(at: tempURL)
            }
        } catch {
            // Fall through
        }
        return nil
    }

    // MARK: - Form Population

    /// Populates form fields from extraction results.
    private func populateForm(from result: ShareExtractionResult) {
        title = result.suggestedTitle
        code = result.extractedCode
        storeName = result.suggestedStoreName
        selectedDVGType = result.suggestedDVGType
        notes = result.notes
        discountDescription = result.discountDescription
    }

    // MARK: - Save

    /// Saves the DVG to the shared SwiftData container and returns success status.
    func save() -> Bool {
        do {
            let container = try getOrCreateContainer()
            let context = ModelContext(container)

            let dvg = DVG(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                barcodeImageData: extractionResult?.barcodeImageData,
                barcodeType: extractionResult?.suggestedBarcodeType ?? .text,
                decodedBarcodeValue: code.trimmingCharacters(in: .whitespacesAndNewlines),
                dvgType: selectedDVGType,
                storeName: storeName.trimmingCharacters(in: .whitespacesAndNewlines),
                discountDescription: discountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                source: .shareExtension,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // Attach a ScanResult to mark it as needing review if AI parsing would help
            let scanResult = ScanResult(
                sourceType: .import_,
                rawText: extractionResult?.rawText ?? "",
                confidenceScore: 0.5,
                needsReview: true
            )
            dvg.scanResult = scanResult

            context.insert(scanResult)
            context.insert(dvg)
            try context.save()

            state = .saved
            return true

        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Container Management

    /// Returns the cached model container, creating it on first access.
    private func getOrCreateContainer() throws -> ModelContainer {
        if let container = modelContainer {
            return container
        }

        let container = try ModelContainerFactory.makeExtensionContainer()
        modelContainer = container
        return container
    }
}
