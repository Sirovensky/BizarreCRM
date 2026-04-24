import Foundation
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - ClipboardBridge

/// Helper for Universal Clipboard — copies record identifiers in a format
/// that survives cross-device paste (iPhone → iPad → Mac).
///
/// ## What it copies
/// The bridge puts two representations on the pasteboard simultaneously:
/// 1. A **plain-text ID** (`"T-001"`) — usable in any app.
/// 2. A **universal-link URL** (`"https://app.bizarrecrm.com/acme/tickets/T-001"`)
///    as a URL item — tapping it on another device opens BizarreCRM directly.
///
/// ## Privacy
/// Universal Clipboard syncs via iCloud only between devices signed in to
/// the same Apple ID.  No server-side transfer occurs.  The copied data
/// contains only the record type and ID — no PII from the record body.
///
/// Thread-safe: stateless enum.  `UIPasteboard.general` / `NSPasteboard.general`
/// calls must happen on the main thread; callers are responsible for
/// dispatching appropriately.
public enum ClipboardBridge {

    // MARK: - CopyResult

    /// Outcome of a clipboard copy operation.
    public enum CopyResult: Sendable, Equatable {
        /// Data was written to the pasteboard successfully.
        case copied(plainText: String)
        /// The destination does not carry a copyable identifier.
        case notApplicable
    }

    // MARK: - Public API

    /// Copies the record identifier for `destination` to the system
    /// Universal Clipboard.
    ///
    /// - Parameter destination: The currently displayed destination.
    /// - Returns: `.copied` with the plain-text value that was placed on
    ///   the clipboard, or `.notApplicable` when `destination` has no
    ///   meaningful identifier to copy.
    @MainActor
    @discardableResult
    public static func copy(_ destination: DeepLinkDestination) -> CopyResult {
        guard let payload = clipboardPayload(for: destination) else {
            return .notApplicable
        }

        writeToClipboard(plainText: payload.plainText, url: payload.url)
        return .copied(plainText: payload.plainText)
    }

    // MARK: - Payload extraction

    private struct Payload {
        let plainText: String
        let url: URL?
    }

    private static func clipboardPayload(
        for destination: DeepLinkDestination
    ) -> Payload? {
        let url = DeepLinkBuilder.build(destination, form: .universalLink)

        switch destination {
        case .ticket(_, let id):
            return Payload(plainText: id, url: url)
        case .customer(_, let id):
            return Payload(plainText: id, url: url)
        case .invoice(_, let id):
            return Payload(plainText: id, url: url)
        case .estimate(_, let id):
            return Payload(plainText: id, url: url)
        case .lead(_, let id):
            return Payload(plainText: id, url: url)
        case .appointment(_, let id):
            return Payload(plainText: id, url: url)
        case .inventory(_, let sku):
            return Payload(plainText: sku, url: url)
        case .smsThread(_, let phone):
            return Payload(plainText: phone, url: url)
        case .reports(_, let name):
            return Payload(plainText: name, url: url)
        case .dashboard, .posRoot, .posNewCart, .posReturn,
             .settings, .auditLogs, .search, .notifications,
             .timeclock, .magicLink:
            // These destinations carry no stable, copy-worthy record ID.
            return nil
        }
    }

    // MARK: - Platform clipboard write

    @MainActor
    private static func writeToClipboard(plainText: String, url: URL?) {
        #if canImport(UIKit)
        UIPasteboardBridge.write(plainText: plainText, url: url)
        #elseif canImport(AppKit)
        NSPasteboardBridge.write(plainText: plainText, url: url)
        #endif
    }
}

// MARK: - UIPasteboardBridge (iOS / iPadOS)

#if canImport(UIKit)
private enum UIPasteboardBridge {
    @MainActor
    static func write(plainText: String, url: URL?) {
        var items: [[String: Any]] = [
            [UTType.plainText.identifier: plainText]
        ]
        if let url {
            items.append([UTType.url.identifier: url as NSURL])
        }
        // Allow Universal Clipboard to sync across iCloud-signed devices.
        // `.localOnly = false` is the default; we set it explicitly for clarity.
        UIPasteboard.general.setItems(
            items,
            options: [UIPasteboard.OptionsKey.localOnly: false]
        )
    }
}
#endif

// MARK: - NSPasteboardBridge (macOS)

#if canImport(AppKit)
private enum NSPasteboardBridge {
    @MainActor
    static func write(plainText: String, url: URL?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(plainText, forType: .string)
        if let url {
            pb.setString(url.absoluteString, forType: .URL)
        }
    }
}
#endif
