import SwiftUI

// MARK: - §26.1 Custom actions — swipe actions exposed as a11y custom actions
//
// `.swipeActions` is invisible to VoiceOver (the gesture itself isn't
// discoverable without sight). To make the same operations reachable, every
// swipe-action group should be mirrored as `.accessibilityAction(named:)`
// so VoiceOver users hit them via the rotor's "Actions" entry.
//
// This helper takes a small descriptor list and emits both `.swipeActions`
// and the matching `.accessibilityAction(named:)` calls in one go, so call
// sites can't accidentally provide one without the other.
//
// Usage:
// ```swift
// TicketRow(ticket: ticket)
//     .a11ySwipeActions([
//         .init(label: "Archive",  systemImage: "archivebox", tint: .gray) { archive() },
//         .init(label: "Delete",   systemImage: "trash",      tint: .red,
//               role: .destructive) { delete() },
//     ])
// ```

public struct A11ySwipeAction: Identifiable {
    public let id: UUID
    public let label: String
    public let systemImage: String?
    public let tint: Color?
    public let role: ButtonRole?
    public let action: () -> Void

    public init(
        label: String,
        systemImage: String? = nil,
        tint: Color? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.id = UUID()
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.role = role
        self.action = action
    }
}

extension View {
    /// Attaches the supplied actions both as a `.swipeActions(edge: .trailing)`
    /// group **and** as VoiceOver `.accessibilityAction(named:)` entries, so
    /// keyboard / Switch Control / VoiceOver users reach them via the rotor
    /// while touch users still get the swipe gesture.
    ///
    /// - Parameters:
    ///   - actions: ordered list (leading-most action first; iOS reverses the
    ///     visual order on trailing-edge swipe automatically).
    ///   - edge:    swipe edge; defaults to `.trailing`.
    ///   - allowsFullSwipe: forwarded to `.swipeActions`. Defaults to `true`.
    public func a11ySwipeActions(
        _ actions: [A11ySwipeAction],
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true
    ) -> some View {
        self.modifier(
            A11ySwipeActionsModifier(
                actions: actions,
                edge: edge,
                allowsFullSwipe: allowsFullSwipe
            )
        )
    }
}

private struct A11ySwipeActionsModifier: ViewModifier {
    let actions: [A11ySwipeAction]
    let edge: HorizontalEdge
    let allowsFullSwipe: Bool

    func body(content: Content) -> some View {
        var view = AnyView(
            content.swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe) {
                ForEach(actions) { action in
                    Button(role: action.role, action: action.action) {
                        if let symbol = action.systemImage {
                            Label(action.label, systemImage: symbol)
                        } else {
                            Text(action.label)
                        }
                    }
                    .tint(action.tint)
                }
            }
        )
        // Mirror each swipe action as a VoiceOver custom action so they show
        // up under the rotor's "Actions" entry. Order is preserved.
        for action in actions {
            view = AnyView(view.accessibilityAction(named: Text(action.label), action.action))
        }
        return view
    }
}
