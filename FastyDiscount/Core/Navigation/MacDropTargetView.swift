import SwiftUI
import UniformTypeIdentifiers

// MARK: - MacDropTargetModifier

/// A view modifier that accepts image and PDF file drops on Mac Catalyst.
///
/// When a file is dropped, it triggers the `onImageDrop` or `onPDFDrop`
/// callback with the file URL so the import flow can be started.
///
/// Only activates on Mac Catalyst; on iOS the modifier is a no-op.
///
/// Usage:
/// ```swift
/// ContentView()
///     .macDropTarget(onImageDrop: { url in ... }, onPDFDrop: { url in ... })
/// ```
struct MacDropTargetModifier: ViewModifier {

    let onImageDrop: (URL) -> Void
    let onPDFDrop: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.image, .pdf, .fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            // Try PDF first (more specific)
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                    guard let url, error == nil else { return }
                    // Copy to a temp location we can access after the callback returns
                    let tempURL = copyToTemporary(url: url, extension: "pdf")
                    DispatchQueue.main.async {
                        if let tempURL {
                            onPDFDrop(tempURL)
                        }
                    }
                }
                handled = true
                continue
            }

            // Try image types
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    guard let url, error == nil else { return }
                    let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                    let tempURL = copyToTemporary(url: url, extension: ext)
                    DispatchQueue.main.async {
                        if let tempURL {
                            onImageDrop(tempURL)
                        }
                    }
                }
                handled = true
                continue
            }

            // Try generic file URL (drag from Finder)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          error == nil else { return }

                    let pathExt = url.pathExtension.lowercased()
                    let tempURL = copyToTemporary(url: url, extension: pathExt)

                    DispatchQueue.main.async {
                        guard let tempURL else { return }
                        if pathExt == "pdf" {
                            onPDFDrop(tempURL)
                        } else {
                            // Treat unknown types as images; ImportViewModel handles errors
                            onImageDrop(tempURL)
                        }
                    }
                }
                handled = true
            }
        }

        return handled
    }

    // MARK: - Helpers

    /// Copies a sandbox-scoped URL to a temporary directory so it remains
    /// accessible after the drop provider callback completes.
    private func copyToTemporary(url: URL, extension fileExtension: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + "." + fileExtension
        let destURL = tempDir.appending(path: fileName)

        do {
            try FileManager.default.copyItem(at: url, to: destURL)
            return destURL
        } catch {
            return nil
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds image and PDF file drop support (primarily for Mac Catalyst).
    ///
    /// On Mac, users can drag image or PDF files from Finder directly onto the
    /// app window to trigger the import flow.
    func macDropTarget(
        onImageDrop: @escaping (URL) -> Void,
        onPDFDrop: @escaping (URL) -> Void
    ) -> some View {
        modifier(MacDropTargetModifier(onImageDrop: onImageDrop, onPDFDrop: onPDFDrop))
    }
}
