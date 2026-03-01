import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ShareViewController

/// Entry point for the FastyDiscount share extension.
///
/// Hosts a compact SwiftUI form (`ShareExtensionView`) inside a
/// `UIHostingController`. The extension accepts shared content
/// (text, URL, image, PDF) from other apps and creates DVG items
/// in the shared SwiftData container.
///
/// The view controller coordinates between the `NSExtensionContext`
/// (for receiving items and completing the request) and the SwiftUI
/// view layer.
@objc(ShareViewController)
@MainActor
class ShareViewController: UIViewController {

    // MARK: - Properties

    private let viewModel = ShareExtensionViewModel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHostingController()
        startProcessing()
    }

    // MARK: - Setup

    /// Embeds the SwiftUI `ShareExtensionView` as a child view controller.
    private func setupHostingController() {
        let shareView = ShareExtensionView(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.cancelRequest()
            },
            onSave: { [weak self] in
                self?.completeRequest()
            }
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    // MARK: - Processing

    /// Starts asynchronous processing of shared items from the extension context.
    private func startProcessing() {
        Task { @MainActor in
            await viewModel.processSharedItems(from: extensionContext)
        }
    }

    // MARK: - Extension Lifecycle

    /// Completes the extension request after a successful save.
    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Cancels the extension request without saving.
    private func cancelRequest() {
        let cancelError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError
        )
        extensionContext?.cancelRequest(withError: cancelError)
    }
}
