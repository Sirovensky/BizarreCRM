import UIKit
import Social
import UniformTypeIdentifiers
import SwiftUI

// MARK: - §25.5 Share Extension (receive sheet)
//
// Targets: image attachments, PDFs, and URLs from any app.
//
// Accepted types:
//   - Images (kUTTypeImage / UTType.image)  → "Attach to ticket" picker flow
//   - PDFs (kUTTypePDF / UTType.pdf)        → "Attach to invoice" or "Attach to expense"
//   - URLs (kUTTypeURL / UTType.url)        → "Add to note on ticket"
//
// Hand-off: stores the shared item in the App Group temp directory
// (`group.com.bizarrecrm`) and opens the main app via URL scheme
// `bizarrecrm://sharehandoff?type=<image|pdf|url>&path=<filename>`.
// The main app reads from the temp file on launch and shows the appropriate picker.
//
// Bundle: BizarreCRMShareExtension target; App Group `group.com.bizarrecrm`.

@objc(ShareViewController)
class ShareViewController: UIViewController {

    private let appGroup = "group.com.bizarrecrm"
    private let handoffScheme = "bizarrecrm"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        processSharedItems()
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            finishWithError("No items to share.")
            return
        }

        let group = DispatchGroup()
        var handoffType: String = "unknown"
        var handoffPath: String = ""

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, error in
                    defer { group.leave() }
                    guard let self, error == nil else { return }
                    if let url = item as? URL,
                       let filename = self.copyToAppGroup(url: url, prefix: "shared_image") {
                        handoffType = "image"
                        handoffPath = filename
                    } else if let image = item as? UIImage,
                              let data = image.jpegData(compressionQuality: 0.85),
                              let filename = self.writeToAppGroup(data: data, filename: "shared_image.jpg") {
                        handoffType = "image"
                        handoffPath = filename
                    }
                }
                break   // one item at a time for MVP

            } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) { [weak self] item, error in
                    defer { group.leave() }
                    guard let self, error == nil else { return }
                    if let url = item as? URL,
                       let filename = self.copyToAppGroup(url: url, prefix: "shared_pdf") {
                        handoffType = "pdf"
                        handoffPath = filename
                    }
                }
                break

            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
                    defer { group.leave() }
                    guard let self, error == nil else { return }
                    if let url = item as? URL {
                        let filename = "shared_url.txt"
                        _ = self.writeToAppGroup(
                            data: url.absoluteString.data(using: .utf8) ?? Data(),
                            filename: filename
                        )
                        handoffType = "url"
                        handoffPath = filename
                    }
                }
                break
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if handoffType == "unknown" || handoffPath.isEmpty {
                self.finishWithError("Could not process the shared item.")
                return
            }
            self.openMainApp(type: handoffType, path: handoffPath)
        }
    }

    // MARK: - App Group helpers

    private func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("ShareHandoff", isDirectory: true)
    }

    private func copyToAppGroup(url: URL, prefix: String) -> String? {
        guard let container = appGroupContainerURL() else { return nil }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let ext = url.pathExtension
        let filename = "\(prefix)_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let dest = container.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return filename
        } catch {
            return nil
        }
    }

    private func writeToAppGroup(data: Data, filename: String) -> String? {
        guard let container = appGroupContainerURL() else { return nil }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let timestamped = "\(Int(Date().timeIntervalSince1970))_\(filename)"
        let dest = container.appendingPathComponent(timestamped)
        do {
            try data.write(to: dest, options: .atomic)
            return timestamped
        } catch {
            return nil
        }
    }

    // MARK: - Handoff to main app

    private func openMainApp(type: String, path: String) {
        // Encode the handoff info into a bizarrecrm:// URL.
        // The main app picks this up in `onOpenURL` → `DeepLinkRouter.handle`.
        var components = URLComponents()
        components.scheme = handoffScheme
        components.host = "sharehandoff"
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "path", value: path)
        ]
        guard let url = components.url else {
            finishWithError("Could not build handoff URL.")
            return
        }

        // Open the main app
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url)
                break
            }
            responder = responder?.next
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Error handling

    private func finishWithError(_ message: String) {
        let alert = UIAlertController(
            title: "Couldn't Share",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: ShareExtensionError.failed(message))
        })
        present(alert, animated: true)
    }
}

// MARK: - Error type

enum ShareExtensionError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let msg) = self { return msg }
        return nil
    }
}
