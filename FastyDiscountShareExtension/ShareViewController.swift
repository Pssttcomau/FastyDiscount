import UIKit
import Social
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                processAttachment(attachment)
            }
        }
    }

    private func processAttachment(_ attachment: NSItemProvider) {
        let supportedTypes: [UTType] = [.url, .text, .image, .pdf]

        for type in supportedTypes {
            if attachment.hasItemConformingToTypeIdentifier(type.identifier) {
                attachment.loadItem(forTypeIdentifier: type.identifier) { [weak self] item, error in
                    if let error {
                        print("Error loading shared item: \(error.localizedDescription)")
                    }
                    // Item processing will be implemented in future tasks
                    self?.completeRequest()
                }
                return
            }
        }

        completeRequest()
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
