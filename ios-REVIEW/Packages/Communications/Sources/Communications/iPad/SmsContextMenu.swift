import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - SmsContextMenu

/// Context menu actions for a single SMS conversation row on iPad.
///
/// Surfaces from `.contextMenu { SmsContextMenu(...) }` in SmsThreeColumnView.
/// All mutations delegate to `SmsListViewModel` for optimistic updates.
///
/// Actions:
///   Mark Read / Mark Unread  — toggles `unreadCount`
///   Flag / Unflag            — toggles `isFlagged`
///   Pin to Top / Unpin       — toggles `isPinned`
///   Archive / Unarchive      — toggles `isArchived`
///   ─────────────────────────
///   Call                     — tel: deep link
///   Copy Number              — writes `convPhone` to pasteboard
public struct SmsContextMenu: View {
    let conversation: SmsConversation
    let vm: SmsListViewModel

    public init(conversation: SmsConversation, vm: SmsListViewModel) {
        self.conversation = conversation
        self.vm = vm
    }

    public var body: some View {
        readToggleItem
        flagToggleItem
        pinToggleItem
        archiveToggleItem
        Divider()
        callItem
        copyNumberItem
    }

    // MARK: - Read / Unread

    @ViewBuilder
    private var readToggleItem: some View {
        if conversation.unreadCount > 0 {
            Button {
                Task { await vm.markRead(phone: conversation.convPhone) }
            } label: {
                Label("Mark Read", systemImage: "envelope.open")
            }
            .accessibilityLabel("Mark \(conversation.displayName) as read")
        } else {
            // Unread action is best-effort; uses existing flag optimistically.
            Button {
                Task { await vm.markUnread(phone: conversation.convPhone) }
            } label: {
                Label("Mark Unread", systemImage: "envelope.badge")
            }
            .accessibilityLabel("Mark \(conversation.displayName) as unread")
        }
    }

    // MARK: - Flag

    private var flagToggleItem: some View {
        Button {
            Task { await vm.toggleFlag(phone: conversation.convPhone) }
        } label: {
            Label(
                conversation.isFlagged ? "Remove Flag" : "Flag",
                systemImage: conversation.isFlagged ? "flag.slash" : "flag"
            )
        }
        .accessibilityLabel(
            conversation.isFlagged
                ? "Remove flag from \(conversation.displayName)"
                : "Flag \(conversation.displayName)"
        )
    }

    // MARK: - Pin

    private var pinToggleItem: some View {
        Button {
            Task { await vm.togglePin(phone: conversation.convPhone) }
        } label: {
            Label(
                conversation.isPinned ? "Unpin" : "Pin to Top",
                systemImage: conversation.isPinned ? "pin.slash" : "pin"
            )
        }
        .accessibilityLabel(
            conversation.isPinned
                ? "Unpin \(conversation.displayName)"
                : "Pin \(conversation.displayName) to top"
        )
    }

    // MARK: - Archive

    private var archiveToggleItem: some View {
        Button(role: conversation.isArchived ? nil : .destructive) {
            Task { await vm.toggleArchive(phone: conversation.convPhone) }
        } label: {
            Label(
                conversation.isArchived ? "Unarchive" : "Archive",
                systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .accessibilityLabel(
            conversation.isArchived
                ? "Unarchive \(conversation.displayName)"
                : "Archive \(conversation.displayName)"
        )
    }

    // MARK: - Call

    private var callItem: some View {
        Button {
            callPhone(conversation.convPhone)
        } label: {
            Label("Call", systemImage: "phone")
        }
        .accessibilityLabel("Call \(conversation.displayName)")
    }

    // MARK: - Copy Number

    private var copyNumberItem: some View {
        Button {
            copyToPasteboard(conversation.convPhone)
        } label: {
            Label("Copy Number", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy phone number \(conversation.convPhone)")
    }

    // MARK: - Helpers

    private func callPhone(_ phone: String) {
        let cleaned = phone.components(separatedBy: .whitespaces).joined()
        guard let url = URL(string: "tel:\(cleaned)") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - SmsListViewModel + markUnread

/// Adds `markUnread` to the list view-model to support the "Mark Unread" context-menu action.
/// Optimistically bumps unreadCount by 1 when the thread shows 0.
extension SmsListViewModel {
    public func markUnread(phone: String) async {
        conversations = conversations.map { c in
            guard c.convPhone == phone, c.unreadCount == 0 else { return c }
            return SmsConversation(
                convPhone: c.convPhone,
                lastMessageAt: c.lastMessageAt,
                lastMessage: c.lastMessage,
                lastDirection: c.lastDirection,
                messageCount: c.messageCount,
                unreadCount: 1,
                isFlagged: c.isFlagged,
                isPinned: c.isPinned,
                isArchived: c.isArchived,
                customer: c.customer,
                recentTicket: c.recentTicket
            )
        }
        // No dedicated server endpoint for mark-unread yet — local-only optimistic update.
        // When the server gains the endpoint, wire it here.
    }
}
