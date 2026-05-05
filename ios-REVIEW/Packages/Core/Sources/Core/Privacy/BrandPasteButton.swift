#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// §28.9 Pasteboard hygiene — PasteButton wrapper
//
// Per §28.9 we use Apple's `PasteButton` (iOS 16+) for all user-initiated
// paste affordances so iOS does NOT show the "Allowed BizarreCRM to access
// your pasteboard" toast. The toast appears only when an app reads
// `UIPasteboard.general` programmatically; `PasteButton` skips it because
// the system trusts the explicit user action.
//
// `BrandPasteButton` is the one place to:
//   - normalize the supported types (string + URL today),
//   - apply our brand styling so it matches surrounding controls,
//   - audit the paste action via `PasteboardAudit.logRead(...)` when the
//     paste happens on a sensitive screen.
//
// Usage:
//
// ```swift
// BrandPasteButton(label: "Paste server URL") { strings in
//     vm.acceptPastedHost(strings.first ?? "")
// }
// ```
//
// Or with the audit hook for sensitive screens:
//
// ```swift
// BrandPasteButton(label: "Paste backup code", auditScreen: "twoFactor.recovery") { strings in
//     vm.acceptBackupCode(strings.first ?? "")
// }
// ```

// MARK: - BrandPasteButton

public struct BrandPasteButton: View {

    // MARK: - Inputs

    private let label: String
    private let auditScreen: String?
    private let auditActor: String?
    private let onPaste: ([String]) -> Void

    // MARK: - Init

    /// - Parameters:
    ///   - label:       Visible label (defaults to "Paste").
    ///   - auditScreen: Stable screen identifier when the paste lands on a
    ///                  sensitive screen; `nil` skips the audit log.
    ///   - auditActor:  Current user / actor for the audit entry; ignored
    ///                  when `auditScreen == nil`.
    ///   - onPaste:     Called on the main queue with the pasted strings.
    ///                  Empty array is filtered out before the call.
    public init(
        label: String = "Paste",
        auditScreen: String? = nil,
        auditActor: String? = nil,
        onPaste: @escaping ([String]) -> Void
    ) {
        self.label       = label
        self.auditScreen = auditScreen
        self.auditActor  = auditActor
        self.onPaste     = onPaste
    }

    // MARK: - Body

    public var body: some View {
        // `PasteButton` accepts `String` (and arrays of) directly via the
        // initializer that takes a payload type list. We accept text/URL by
        // taking [String]; URL paste lands as a string we parse downstream.
        PasteButton(supportedContentTypes: [UTType.plainText, UTType.url]) { itemProviders in
            loadStrings(from: itemProviders) { strings in
                guard !strings.isEmpty else { return }
                if let screen = auditScreen {
                    PasteboardAudit.logRead(
                        screen: screen,
                        actor:  auditActor ?? "<unknown>"
                    )
                }
                onPaste(strings)
            }
        }
        .labelsHidden()
        .accessibilityLabel(label)
    }

    // MARK: - NSItemProvider plumbing

    /// Extract all `String` representations from the paste's item providers
    /// and call `completion` on the main queue once every load finishes.
    private func loadStrings(
        from providers: [NSItemProvider],
        completion: @escaping ([String]) -> Void
    ) {
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "BrandPasteButton.collect")
        // Use a class box so Swift 6 capture analysis doesn't flag concurrent mutation
        // (queue.sync already serializes all writes).
        final class Box: @unchecked Sendable { var values: [String] = [] }
        let box = Box()

        for provider in providers {
            group.enter()
            let textType = UTType.plainText.identifier
            let urlType  = UTType.url.identifier

            if provider.hasItemConformingToTypeIdentifier(textType) {
                provider.loadItem(forTypeIdentifier: textType, options: nil) { item, _ in
                    queue.sync {
                        if let s = item as? String {
                            box.values.append(s)
                        } else if let d = item as? Data, let s = String(data: d, encoding: .utf8) {
                            box.values.append(s)
                        }
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(urlType) {
                provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
                    queue.sync {
                        if let url = item as? URL {
                            box.values.append(url.absoluteString)
                        }
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(box.values)
        }
    }
}
#endif
