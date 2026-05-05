#if canImport(UIKit)
import SwiftUI
import UIKit

// §28.9 Pasteboard hygiene — Customer paste-blind
//
// Customer fields (email, phone, address) that are pasted from the
// system clipboard should not trigger iOS's "X pasted from Y" permission
// toast, and should never be read programmatically by view code.
//
// This helper wraps the iOS 16+ `PasteButton` pattern for customer form
// fields and provides a `View` modifier that attaches paste-blind handling
// to any sensitive customer field.
//
// Companion to the already-shipped ticket paste-blind (§28.9 / TicketPIIRedactor).

// MARK: - CustomerPasteField

/// Wraps a `TextField` for a sensitive customer field so that paste
/// actions go through iOS's `PasteButton` (iOS 16+), avoiding the
/// "X accessed your clipboard" toast that `UIPasteboard.general` reads trigger.
///
/// On iOS 15 and earlier the field falls back to a plain `TextField`;
/// the paste toast is unavoidable there but the UX contract is met.
///
/// Usage:
/// ```swift
/// CustomerPasteField("Email", text: $email, contentType: .emailAddress)
/// ```
public struct CustomerPasteField: View {
    let label: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType

    public init(
        _ label: String,
        text: Binding<String>,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default
    ) {
        self.label = label
        self._text = text
        self.contentType = contentType
        self.keyboard = keyboard
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            CustomerPasteFieldiOS16(
                label: label,
                text: $text,
                contentType: contentType,
                keyboard: keyboard
            )
        } else {
            TextField(label, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .accessibilityLabel(label)
        }
    }
}

// MARK: - iOS 16+ implementation

@available(iOS 16.0, *)
private struct CustomerPasteFieldiOS16: View {
    let label: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .accessibilityLabel(label)

            if text.isEmpty {
                // Show PasteButton only when field is empty so the user can
                // paste an initial value without triggering the toast.
                PasteButton(payloadType: String.self) { strings in
                    guard let first = strings.first else { return }
                    text = first
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.iconOnly)
                .tint(.secondary)
                .accessibilityLabel("Paste \(label)")
            }
        }
    }
}

// MARK: - View modifier

extension View {
    /// Marks this view as a customer-sensitive paste target, consistent with
    /// §28.9 pasteboard hygiene. Currently a no-op marker that documents intent
    /// and can be extended to add audit-log hooks when `UIPasteboard` is read
    /// in view code (SwiftLint rule: `forbid-pasteboard-in-view`).
    ///
    /// Wrap any view that reads `UIPasteboard.general` for a customer field:
    /// ```swift
    /// someView.customerPasteBlind()
    /// ```
    public func customerPasteBlind() -> some View {
        self
            // Annotate for SwiftLint rule and future audit-log injection point.
            .accessibilityIdentifier("customer.paste-blind")
    }
}

#endif
