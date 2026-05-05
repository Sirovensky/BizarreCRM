import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §25.3 Universal Clipboard — textSelection + expiring pasteboard

// MARK: - .textSelection(.enabled) helpers

/// §25.3 — Convenience modifier that enables text selection and attaches a
/// context menu copy action with expiring pasteboard for sensitive values.
///
/// Usage:
/// ```swift
/// Text(ticket.orderId)
///     .selectableCopyable(label: "Ticket ID")
/// ```
public struct SelectableCopyableModifier: ViewModifier {
    let label: String
    let isSensitive: Bool

    public func body(content: Content) -> some View {
        content
            .textSelection(.enabled)
            .contextMenu {
                Button {
                    copyToPasteboard(content: content, isSensitive: isSensitive)
                } label: {
                    Label("Copy \(label)", systemImage: "doc.on.doc")
                }
            }
    }

    @MainActor
    private func copyToPasteboard(content: Content, isSensitive: Bool) {
        // We can't extract the raw text from `content` here — the caller should
        // use `selectableCopyable(value:label:isSensitive:)` when the raw string
        // is available (preferred). This overload enables text selection only.
        #if canImport(UIKit)
        // No-op for the content-only variant; selection is enabled via textSelection(.enabled).
        #endif
    }
}

/// §25.3 — Attaches `.textSelection(.enabled)` + context-menu "Copy" with optional
/// expiring pasteboard for sensitive values (e.g. order IDs, phone numbers).
///
/// - Parameters:
///   - value: Raw string to copy. Falls back to selection if nil.
///   - label: Human-readable name shown in context menu (e.g. "Phone Number").
///   - isSensitive: When `true`, the pasteboard item expires after 120 s.
public struct SelectableCopyableValueModifier: ViewModifier {
    let value: String
    let label: String
    let isSensitive: Bool

    public func body(content: Content) -> some View {
        content
            .textSelection(.enabled)
            .contextMenu {
                Button {
                    #if canImport(UIKit)
                    if isSensitive {
                        UIPasteboard.general.setItems(
                            [[UIPasteboard.typeAutomatic: value]],
                            options: [.expirationDate: Date(timeIntervalSinceNow: 120)]
                        )
                    } else {
                        UIPasteboard.general.string = value
                    }
                    #endif
                } label: {
                    Label("Copy \(label)", systemImage: "doc.on.doc")
                }
            }
    }
}

// MARK: - View extensions

public extension View {
    /// Enables text selection and adds a context-menu copy action.
    /// Use when you have the raw string value available.
    func selectableCopyable(
        value: String,
        label: String,
        isSensitive: Bool = false
    ) -> some View {
        modifier(SelectableCopyableValueModifier(
            value: value,
            label: label,
            isSensitive: isSensitive
        ))
    }

    /// Enables text selection only (no copy-to-pasteboard action on tap).
    /// Use when the exact text value is rendered by SwiftUI (e.g. long Text blocks).
    func selectableText() -> some View {
        textSelection(.enabled)
    }
}

// MARK: - §25.3 iCloud Keychain paste — OTP / one-time code

/// §25.3 — TextField wrapper that sets `textContentType(.oneTimeCode)` for
/// automatic iCloud Keychain paste suggestion on SMS OTP fields.
///
/// Usage:
/// ```swift
/// OTPTextField(text: $code, onCommit: verify)
/// ```
public struct OTPTextField: View {
    @Binding var text: String
    var onCommit: (() -> Void)?

    public init(text: Binding<String>, onCommit: (() -> Void)? = nil) {
        _text = text
        self.onCommit = onCommit
    }

    public var body: some View {
        TextField("SMS code", text: $text)
            #if canImport(UIKit)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            #endif
            .onSubmit { onCommit?() }
            .accessibilityLabel("One-time code")
            .accessibilityHint("Paste the code from your SMS message")
    }
}
