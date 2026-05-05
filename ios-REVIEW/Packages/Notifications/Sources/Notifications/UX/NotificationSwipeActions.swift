import SwiftUI
import DesignSystem
import Networking

// MARK: - NotificationSwipeActionHandler

/// Callbacks supplied by the parent view or view-model.
///
/// Each action receives the notification `id` and the expected optimistic
/// state so the call site can apply an immediate UI update before awaiting
/// the network round-trip.
public struct NotificationSwipeActionHandler: Sendable {
    /// Mark a notification read (trailing swipe, leading edge).
    public let markRead: @Sendable (Int64) async -> Void
    /// Mark a notification unread (trailing swipe when already read).
    public let markUnread: @Sendable (Int64) async -> Void
    /// Archive a notification (leading swipe, trailing edge).
    public let archive: @Sendable (Int64) async -> Void
    /// Flag / unflag a notification (leading swipe, leading edge).
    public let toggleFlag: @Sendable (Int64, Bool) async -> Void

    public init(
        markRead: @escaping @Sendable (Int64) async -> Void,
        markUnread: @escaping @Sendable (Int64) async -> Void,
        archive: @escaping @Sendable (Int64) async -> Void,
        toggleFlag: @escaping @Sendable (Int64, Bool) async -> Void
    ) {
        self.markRead = markRead
        self.markUnread = markUnread
        self.archive = archive
        self.toggleFlag = toggleFlag
    }
}

// MARK: - notificationSwipeActions modifier

public extension View {
    /// Attaches the standard BizarreCRM swipe actions to a notification list row.
    ///
    /// Trailing edge (swipe left):
    ///   - Read / Unread toggle (full-swipe supported)
    ///
    /// Leading edge (swipe right):
    ///   - Flag / Unflag
    ///   - Archive (destructive)
    func notificationSwipeActions(
        item: NotificationItem,
        isFlagged: Bool = false,
        handler: NotificationSwipeActionHandler
    ) -> some View {
        modifier(
            NotificationSwipeActionsModifier(
                item: item,
                isFlagged: isFlagged,
                handler: handler
            )
        )
    }
}

// MARK: - NotificationSwipeActionsModifier

private struct NotificationSwipeActionsModifier: ViewModifier {

    let item: NotificationItem
    let isFlagged: Bool
    let handler: NotificationSwipeActionHandler

    func body(content: Content) -> some View {
        content
            // TRAILING edge — swipe LEFT → read/unread
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                trailingActions
            }
            // LEADING edge — swipe RIGHT → flag + archive
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                leadingActions
            }
    }

    // MARK: Trailing: read / unread toggle

    @ViewBuilder
    private var trailingActions: some View {
        if item.read {
            Button {
                Task { await handler.markUnread(item.id) }
            } label: {
                Label("Mark unread", systemImage: "envelope.badge")
            }
            .tint(.bizarreTeal)
            .accessibilityIdentifier("notif.swipe.unread.\(item.id)")
        } else {
            Button {
                Task { await handler.markRead(item.id) }
            } label: {
                Label("Mark read", systemImage: "envelope.open")
            }
            .tint(.bizarreTeal)
            .accessibilityIdentifier("notif.swipe.read.\(item.id)")
        }
    }

    // MARK: Leading: flag + archive

    @ViewBuilder
    private var leadingActions: some View {
        // Archive — destructive, rightmost on leading side
        Button(role: .destructive) {
            Task { await handler.archive(item.id) }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .accessibilityIdentifier("notif.swipe.archive.\(item.id)")

        // Flag / Unflag
        Button {
            Task { await handler.toggleFlag(item.id, !isFlagged) }
        } label: {
            Label(
                isFlagged ? "Unflag" : "Flag",
                systemImage: isFlagged ? "flag.slash" : "flag"
            )
        }
        .tint(isFlagged ? .bizarreOnSurfaceMuted : .bizarreWarning)
        .accessibilityIdentifier("notif.swipe.flag.\(item.id)")
    }
}

// MARK: - NotificationSwipeActionState

/// Tracks per-item ephemeral state (flagged, archived) that doesn't live in
/// the server model yet. Owned by the parent list view or view-model.
@MainActor
@Observable
public final class NotificationSwipeActionState {

    private var flagged: Set<Int64> = []
    private var archived: Set<Int64> = []

    public init() {}

    public func isFlagged(_ id: Int64) -> Bool { flagged.contains(id) }
    public func isArchived(_ id: Int64) -> Bool { archived.contains(id) }

    /// Toggle flag optimistically. Returns the new state.
    @discardableResult
    public func toggleFlag(id: Int64, flagged newValue: Bool) -> Bool {
        if newValue { flagged.insert(id) } else { flagged.remove(id) }
        return newValue
    }

    public func markArchived(_ id: Int64) {
        archived.insert(id)
    }

    public func removeArchived(_ id: Int64) {
        archived.remove(id)
    }

    /// Items not yet archived (use to filter the list).
    public func visibleItems(from items: [NotificationItem]) -> [NotificationItem] {
        items.filter { !archived.contains($0.id) }
    }
}
