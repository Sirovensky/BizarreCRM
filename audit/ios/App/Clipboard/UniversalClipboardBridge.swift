import UIKit

// MARK: - PasteboardProtocol

/// Abstraction over `UIPasteboard` for testability.
///
/// The production implementation delegates to `UIPasteboard.general`.
/// Tests inject a `MockPasteboard` that stores values in memory.
public protocol PasteboardProtocol: AnyObject, Sendable {
    var string: String? { get set }
}

// MARK: UIPasteboard + PasteboardProtocol

extension UIPasteboard: @retroactive @unchecked Sendable {}
extension UIPasteboard: PasteboardProtocol {}

// MARK: - UniversalClipboardBridge

/// Thin wrapper around `UIPasteboard.general` that integrates with iOS's
/// transparent **Universal Clipboard** feature.
///
/// Universal Clipboard (Handoff-via-Clipboard) works automatically when:
/// - Both devices share the same Apple ID (Handoff enabled in Settings).
/// - The item is written with `UIPasteboard.general`.
///
/// No additional API surface is required; iOS transfers the pasteboard
/// item across nearby devices invisibly.
///
/// **Usage**
/// ```swift
/// // Copy a customer phone number
/// UniversalClipboardBridge.shared.writePlainText("+1 555 0100")
///
/// // Paste a POS SKU
/// let sku = await UniversalClipboardBridge.shared.readPlainText()
/// ```
///
/// **Thread safety** — all methods are `@MainActor`; `UIPasteboard` is
/// main-thread-only per Apple documentation.
@MainActor
public final class UniversalClipboardBridge {

    // MARK: Singleton

    public static let shared = UniversalClipboardBridge(
        pasteboard: UIPasteboard.general
    )

    // MARK: Internal

    private let pasteboard: any PasteboardProtocol

    /// Designated initialiser — exposed `internal` so tests can inject
    /// a mock pasteboard without touching the singleton.
    init(pasteboard: any PasteboardProtocol) {
        self.pasteboard = pasteboard
    }

    // MARK: - Public API

    /// Write a plain-text string to the system pasteboard.
    ///
    /// The value becomes available to Universal Clipboard on nearby devices
    /// automatically.
    ///
    /// - Parameter text: The string to place on the pasteboard.
    public func writePlainText(_ text: String) {
        pasteboard.string = text
    }

    /// Read the current plain-text value from the system pasteboard.
    ///
    /// Returns `nil` if the pasteboard is empty or holds a non-text item.
    ///
    /// - Returns: The pasteboard string, or `nil`.
    public func readPlainText() async -> String? {
        pasteboard.string
    }
}
