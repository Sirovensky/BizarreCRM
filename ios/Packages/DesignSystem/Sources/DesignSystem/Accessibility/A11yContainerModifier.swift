import SwiftUI

// MARK: - §26.1 Container — `.accessibilityElement(children: .contain)`
//
// Wraps a list / collection so VoiceOver treats it as a navigable container.
// `.contain` (vs `.combine`) keeps each child individually focusable while
// signalling to VoiceOver that they belong to the same logical group, which
// improves rotor + escape-gesture (two-finger Z) behavior on long lists.
//
// Usage:
// ```swift
// ScrollView {
//     LazyVStack {
//         ForEach(tickets) { TicketRow(ticket: $0) }
//     }
// }
// .a11yContainer(label: "Tickets")
// ```

extension View {
    /// Marks the view as an accessibility container that **contains** its
    /// children (rather than combining them). Optional `label` is read by
    /// VoiceOver when the user enters the container.
    ///
    /// - Parameter label: optional spoken label for the container.
    public func a11yContainer(label: String? = nil) -> some View {
        self.modifier(A11yContainerModifier(label: label))
    }
}

private struct A11yContainerModifier: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label, !label.isEmpty {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(label))
        } else {
            content
                .accessibilityElement(children: .contain)
        }
    }
}
