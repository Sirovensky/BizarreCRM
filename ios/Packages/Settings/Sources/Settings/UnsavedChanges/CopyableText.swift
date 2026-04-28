import SwiftUI

// MARK: - CopyableText (§25.3 Universal Clipboard)
//
// Reusable view modifier that enables:
//   1. `.textSelection(.enabled)` so users can long-press → Copy / Look Up / etc.
//   2. An optional context-menu "Copy <label>" action for ID-like fields.
//
// Usage:
// ```swift
// Text(invoice.id).copyable(label: "invoice number", value: invoice.displayId)
// Text(customer.phone).copyable(label: "phone number")
// ```

public extension View {
    /// Enable text selection + an optional copy context-menu item.
    ///
    /// - Parameters:
    ///   - label: Human-readable label for the context-menu item ("invoice number").
    ///   - value: String to copy. If nil, copies the rendered text (relies on `.textSelection`).
    func copyable(label: String? = nil, value: String? = nil) -> some View {
        self
            .textSelection(.enabled)
            .conditionalContextMenuCopy(label: label, value: value)
    }
}

// MARK: - Private conditional modifier

private struct ConditionalContextMenuCopyModifier: ViewModifier {
    let label: String?
    let value: String?

    func body(content: Content) -> some View {
        if let label, let value {
            content.contextMenu {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = value
                    #endif
                } label: {
                    Label("Copy \(label)", systemImage: "doc.on.doc")
                }
            }
        } else {
            content
        }
    }
}

private extension View {
    func conditionalContextMenuCopy(label: String?, value: String?) -> some View {
        modifier(ConditionalContextMenuCopyModifier(label: label, value: value))
    }
}
