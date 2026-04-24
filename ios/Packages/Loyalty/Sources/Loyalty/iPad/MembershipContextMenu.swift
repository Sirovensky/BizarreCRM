import SwiftUI
import DesignSystem

// MARK: - MembershipContextMenuActions

/// §22 — Callbacks for the four required context-menu actions.
public struct MembershipContextMenuActions: Sendable {
    public let onEnroll:      @Sendable (String) -> Void
    public let onRedeemPoints: @Sendable (String) -> Void
    public let onViewHistory:  @Sendable (String) -> Void
    public let onTogglePause:  @Sendable (String) -> Void

    public init(
        onEnroll: @escaping @Sendable (String) -> Void,
        onRedeemPoints: @escaping @Sendable (String) -> Void,
        onViewHistory: @escaping @Sendable (String) -> Void,
        onTogglePause: @escaping @Sendable (String) -> Void
    ) {
        self.onEnroll = onEnroll
        self.onRedeemPoints = onRedeemPoints
        self.onViewHistory = onViewHistory
        self.onTogglePause = onTogglePause
    }
}

// MARK: - View+membershipContextMenu modifier

public extension View {
    /// Attaches the standard loyalty context menu to any view.
    ///
    /// Required actions (§22):
    ///  1. Enroll
    ///  2. Redeem Points
    ///  3. View History
    ///  4. Pause / Resume  (label toggles based on `isPaused`)
    ///
    /// `membershipId` is forwarded to each callback so the call site
    /// can route the action to the right record without extra closures.
    func membershipContextMenu(
        membershipId: String,
        isPaused: Bool,
        actions: MembershipContextMenuActions
    ) -> some View {
        modifier(MembershipContextMenuModifier(
            membershipId: membershipId,
            isPaused: isPaused,
            actions: actions
        ))
    }
}

// MARK: - MembershipContextMenuModifier

private struct MembershipContextMenuModifier: ViewModifier {
    let membershipId: String
    let isPaused: Bool
    let actions: MembershipContextMenuActions

    func body(content: Content) -> some View {
        content.contextMenu {
            // 1. Enroll
            Button {
                actions.onEnroll(membershipId)
            } label: {
                Label("Enroll", systemImage: "person.crop.circle.badge.plus")
            }
            .accessibilityLabel("Enroll customer in membership")

            // 2. Redeem Points
            Button {
                actions.onRedeemPoints(membershipId)
            } label: {
                Label("Redeem Points", systemImage: "wallet.pass")
            }
            .accessibilityLabel("Redeem loyalty points")

            // 3. View History
            Button {
                actions.onViewHistory(membershipId)
            } label: {
                Label("View History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityLabel("View points history")

            Divider()

            // 4. Pause / Resume
            Button {
                actions.onTogglePause(membershipId)
            } label: {
                if isPaused {
                    Label("Resume", systemImage: "play.circle")
                } else {
                    Label("Pause", systemImage: "pause.circle")
                }
            }
            .accessibilityLabel(isPaused ? "Resume membership" : "Pause membership")
        }
    }
}

// MARK: - MembershipContextMenu (standalone view)

/// §22 — Standalone context-menu view for use in Table's
/// `contextMenu(forSelectionType:)` callback.
///
/// Usage:
/// ```swift
/// .contextMenu(forSelectionType: Membership.ID.self) { ids in
///     if let id = ids.first, let m = memberships.first(where: { $0.id == id }) {
///         MembershipContextMenu(membership: m, actions: actions)
///     }
/// }
/// ```
public struct MembershipContextMenu: View {
    let membership: Membership
    let actions: MembershipContextMenuActions

    public init(membership: Membership, actions: MembershipContextMenuActions) {
        self.membership = membership
        self.actions = actions
    }

    public var body: some View {
        let id = membership.id
        let isPaused = membership.status == .paused

        Group {
            Button {
                actions.onEnroll(id)
            } label: {
                Label("Enroll", systemImage: "person.crop.circle.badge.plus")
            }
            .accessibilityLabel("Enroll in membership")

            Button {
                actions.onRedeemPoints(id)
            } label: {
                Label("Redeem Points", systemImage: "wallet.pass")
            }
            .accessibilityLabel("Redeem loyalty points")

            Button {
                actions.onViewHistory(id)
            } label: {
                Label("View History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityLabel("View points history")

            Divider()

            Button {
                actions.onTogglePause(id)
            } label: {
                Label(isPaused ? "Resume" : "Pause",
                      systemImage: isPaused ? "play.circle" : "pause.circle")
            }
            .accessibilityLabel(isPaused ? "Resume membership" : "Pause membership")
        }
    }
}
