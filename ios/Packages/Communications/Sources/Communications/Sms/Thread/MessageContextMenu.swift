import SwiftUI
import Core
import DesignSystem

// MARK: - MessageContextMenu
//
// §12.2 Long-press message → context menu:
//   Copy · Reply · Forward · Create ticket from this · Flag · Delete
//
// Usage: attach `.messageContextMenu(message:, onReply:, onForward:, onCreate:, onFlag:, onDelete:)`
// to any message bubble.

public struct MessageContextMenuModifier: ViewModifier {
    let message: SmsMessage
    let onCopy: (() -> Void)?
    let onReply: ((SmsMessage) -> Void)?
    let onForward: ((SmsMessage) -> Void)?
    let onCreateTicket: ((SmsMessage) -> Void)?
    let onFlag: ((SmsMessage) -> Void)?
    let onDelete: ((SmsMessage) -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            // Copy
            Button {
                copyToClipboard(message.message ?? "")
                onCopy?()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("msg.ctx.copy")

            // Reply
            if let onReply {
                Button { onReply(message) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .accessibilityIdentifier("msg.ctx.reply")
            }

            // Forward
            if let onForward {
                Button { onForward(message) } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                .accessibilityIdentifier("msg.ctx.forward")
            }

            Divider()

            // Create ticket from this
            if let onCreateTicket {
                Button { onCreateTicket(message) } label: {
                    Label("Create Ticket", systemImage: "ticket")
                }
                .accessibilityIdentifier("msg.ctx.createTicket")
            }

            // Flag
            if let onFlag {
                Button { onFlag(message) } label: {
                    Label("Flag", systemImage: "flag")
                }
                .accessibilityIdentifier("msg.ctx.flag")
            }

            Divider()

            // Delete (destructive)
            if let onDelete {
                Button(role: .destructive) { onDelete(message) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("msg.ctx.delete")
            }
        }
    }

    private func copyToClipboard(_ text: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
#endif
        BrandHaptics.tap()
    }
}

public extension View {
    func messageContextMenu(
        message: SmsMessage,
        onCopy: (() -> Void)? = nil,
        onReply: ((SmsMessage) -> Void)? = nil,
        onForward: ((SmsMessage) -> Void)? = nil,
        onCreateTicket: ((SmsMessage) -> Void)? = nil,
        onFlag: ((SmsMessage) -> Void)? = nil,
        onDelete: ((SmsMessage) -> Void)? = nil
    ) -> some View {
        modifier(MessageContextMenuModifier(
            message: message,
            onCopy: onCopy,
            onReply: onReply,
            onForward: onForward,
            onCreateTicket: onCreateTicket,
            onFlag: onFlag,
            onDelete: onDelete
        ))
    }
}
