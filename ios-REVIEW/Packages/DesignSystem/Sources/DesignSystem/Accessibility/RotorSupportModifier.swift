import SwiftUI

// MARK: - RotorSupportModifier
// §26.1 — Rotor support helpers.
//
// VoiceOver's rotor (two-finger rotate gesture) lets users jump between
// headings, links, form controls, etc.  These helpers wire SwiftUI
// `accessibilityRotor` calls so each long list gains the standard rotors
// without every call-site having to know the API details.
//
// **Usage:**
// ```swift
// ScrollView {
//     ForEach(tickets) { ticket in
//         TicketRow(ticket: ticket)
//             .rotorHeading(ticket.title)
//     }
// }
// .rotorNavigation(headings: tickets.map(\.title))
// ```

// MARK: - View extension

public extension View {

    /// Marks this view as a VoiceOver rotor **heading** entry.
    ///
    /// When the VoiceOver user sets the rotor to "Headings" they can
    /// flick up/down to jump between rows that carry this modifier.
    ///
    /// - Parameter label: The spoken label for the rotor entry.
    ///   Typically the same string as `accessibilityLabel`.
    func rotorHeading(_ label: String) -> some View {
        accessibilityAddTraits(.isHeader)
            .accessibilityLabel(label)
    }

    /// Attaches a custom **Headings** rotor to a container (e.g. `ScrollView`
    /// or `List`) so VoiceOver can jump between named items.
    ///
    /// - Parameter labels: Ordered list of entry labels matching the children.
    ///   The rotor entries are synthesised from these strings; each one must
    ///   correspond to a child that has `.accessibilityLabel` set to the same
    ///   string so VoiceOver can focus the right element.
    ///
    /// - Note: This modifier is unconditional; the rotor only surfaces when
    ///   VoiceOver is active — iOS controls that, not us.
    func rotorNavigation(headings labels: [String]) -> some View {
        accessibilityRotor("Headings") {
            ForEach(labels, id: \.self) { label in
                AccessibilityRotorEntry(label, id: label)
            }
        }
    }

    /// Attaches a custom **Links** rotor entry to a tappable element.
    ///
    /// Use on rows that navigate to an external URL or a deep-link destination.
    /// VoiceOver users can set the rotor to "Links" and flick between them.
    ///
    /// - Parameter label: Spoken label for this link entry.
    func rotorLink(_ label: String) -> some View {
        accessibilityAddTraits(.isLink)
            .accessibilityLabel(label)
    }

    /// Attaches a **Links** rotor to a container listing link-type children.
    ///
    /// - Parameter labels: Ordered list of link labels matching `.rotorLink(_:)` children.
    func rotorLinksNavigation(labels: [String]) -> some View {
        accessibilityRotor("Links") {
            ForEach(labels, id: \.self) { label in
                AccessibilityRotorEntry(label, id: label)
            }
        }
    }
}
