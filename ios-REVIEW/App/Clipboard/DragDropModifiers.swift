import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §25.6 Drag-and-drop modifiers
//
// SwiftUI/UIKit-bridging modifiers for:
//   • Drag-out: ticket cards become draggable items carrying a plain-text
//     summary + tracking URL so they can be dropped into Notes, Mail,
//     Messages, etc.
//   • Drop text: any field can accept dropped text (from another app
//     or another window) directly into a `Binding<String>`.

// MARK: - Ticket drag-out (§25.6)

/// Transferable carried when the user drags a ticket card out of
/// BizarreCRM. Exports both a plain-text summary (for Notes, Mail) and
/// a URL (for the public tracking page) so the destination app picks
/// the best representation.
public struct TicketDragPayload: Transferable, Sendable {
    public let summaryText: String
    public let trackingURL: URL?

    public init(summaryText: String, trackingURL: URL?) {
        self.summaryText = summaryText
        self.trackingURL = trackingURL
    }

    public static var transferRepresentation: some TransferRepresentation {
        // Plain text representation — works in any text-accepting app.
        ProxyRepresentation(exporting: \.summaryText)

        // URL representation — drop into Safari / Notes link, etc.
        ProxyRepresentation { (payload: TicketDragPayload) -> URL in
            payload.trackingURL ?? URL(string: "about:blank")!
        }
    }
}

public extension View {
    /// §25.6 — Makes the receiver draggable, carrying a ticket payload.
    /// Drop targets in other apps see both a plain-text summary and a URL.
    func ticketDraggable(_ payload: TicketDragPayload) -> some View {
        self.draggable(payload)
    }
}

// MARK: - Text drop into note fields (§25.6)

#if canImport(UIKit)
/// View modifier accepting plain-text drops into a `Binding<String>`.
/// Appends the dropped text on a new line if the field already has content,
/// otherwise replaces it. Works for ticket notes, customer notes, etc.
public struct DroppableTextModifier: ViewModifier {
    @Binding var text: String

    public func body(content: Content) -> some View {
        content.dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first, !dropped.isEmpty else { return false }
            if text.isEmpty {
                text = dropped
            } else {
                // Avoid duplicate trailing newline.
                let separator = text.hasSuffix("\n") ? "" : "\n"
                text += separator + dropped
            }
            return true
        }
    }
}

public extension View {
    /// §25.6 — Accept dropped plain-text into the supplied binding.
    /// Use on note / comment fields:
    ///
    /// ```swift
    /// TextEditor(text: $note).droppableText($note)
    /// ```
    func droppableText(_ binding: Binding<String>) -> some View {
        modifier(DroppableTextModifier(text: binding))
    }
}
#endif
