import Foundation
import Networking

/// §22 — Context-menu modifier for voice-screen list rows on iPad.
///
/// Provides four actions per spec:
///   1. **Callback** — dials the entry's phone number via `tel:` URL.
///   2. **Copy Number** — writes the raw phone number to the pasteboard.
///   3. **Add to Customer** — fires a closure so the host can navigate to the
///      customer-linkage sheet (the sheet itself lives in the Customers package).
///   4. **Archive** — fires an optional closure; the action is hidden when the
///      closure is `nil` so callers can omit it for routes that don't support
///      archiving.
///
/// Apply with `.voiceContextMenu(entry:onAddToCustomer:onArchive:)`.

// MARK: - Data carrier (platform-agnostic, testable on macOS)

/// Internal data carrier backing both `.voiceContextMenu` overloads.
/// Declared outside the UIKit guard so tests on macOS can exercise the
/// stored properties and optional-action logic without a UIKit host.
public struct VoiceCallContextMenuModifier {

    public let phoneNumber: String
    public let displayName: String
    public let onAddToCustomer: (() -> Void)?
    public let onArchive: (() -> Void)?

    public init(
        phoneNumber: String,
        displayName: String,
        onAddToCustomer: (() -> Void)? = nil,
        onArchive: (() -> Void)? = nil
    ) {
        self.phoneNumber = phoneNumber
        self.displayName = displayName
        self.onAddToCustomer = onAddToCustomer
        self.onArchive = onArchive
    }
}

// MARK: - SwiftUI ViewModifier + View extension (UIKit platforms only)

#if canImport(UIKit)
import SwiftUI
import UIKit

extension VoiceCallContextMenuModifier: ViewModifier {

    public func body(content: Content) -> some View {
        content.contextMenu {
            // 1. Callback
            Button {
                CallQuickAction.placeCall(to: phoneNumber)
            } label: {
                Label("Call \(displayName)", systemImage: "phone.fill")
            }

            // 2. Copy Number
            Button {
                UIPasteboard.general.string = phoneNumber
            } label: {
                Label("Copy Number", systemImage: "doc.on.doc")
            }

            // 3. Add to Customer (optional)
            if let onAddToCustomer {
                Button {
                    onAddToCustomer()
                } label: {
                    Label("Add to Customer", systemImage: "person.badge.plus")
                }
            }

            // 4. Archive (optional, destructive — shown below a Divider)
            if let onArchive {
                Divider()
                Button(role: .destructive) {
                    onArchive()
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
    }
}

public extension View {

    /// Attaches the standardised Voice context menu to a call-log list row.
    func voiceContextMenu(
        entry: CallLogEntry,
        onAddToCustomer: (() -> Void)? = nil,
        onArchive: (() -> Void)? = nil
    ) -> some View {
        modifier(
            VoiceCallContextMenuModifier(
                phoneNumber: entry.phoneNumber,
                displayName: entry.customerName ?? entry.phoneNumber,
                onAddToCustomer: onAddToCustomer,
                onArchive: onArchive
            )
        )
    }

    /// Voicemail-flavoured overload (same actions, different entry type).
    func voiceContextMenu(
        entry: VoicemailEntry,
        onAddToCustomer: (() -> Void)? = nil,
        onArchive: (() -> Void)? = nil
    ) -> some View {
        modifier(
            VoiceCallContextMenuModifier(
                phoneNumber: entry.phoneNumber,
                displayName: entry.customerName ?? entry.phoneNumber,
                onAddToCustomer: onAddToCustomer,
                onArchive: onArchive
            )
        )
    }
}
#endif
