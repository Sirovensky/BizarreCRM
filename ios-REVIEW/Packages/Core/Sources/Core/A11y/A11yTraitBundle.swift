// Core/A11y/A11yTraitBundle.swift
//
// Value type bundling an accessibility label, hint, and SwiftUI AccessibilityTraits
// for reuse via a ViewModifier.
//
// Why: Many CRM list rows share identical a11y configurations.  Rather than
// scattering `.accessibilityLabel` / `.accessibilityHint` / `.accessibilityAddTraits`
// across every call site, callers compose an `A11yTraitBundle` once and apply it
// with `.accessibilityBundle(...)`.
//
// §26 A11y label catalog — trait bundle

import SwiftUI

// MARK: - A11yTraitBundle

/// An immutable bundle of accessibility label, hint, and traits.
///
/// Build a bundle once per row type and apply it with the `.accessibilityBundle(_:)`
/// ViewModifier:
///
/// ```swift
/// static let ticketRow = A11yTraitBundle(
///     label: A11yLabels.Tickets.listTitle,
///     hint:  A11yRoleHints.swipeLeftForActions,
///     traits: [.isButton]
/// )
///
/// var body: some View {
///     TicketRowView()
///         .accessibilityBundle(ticketRow)
/// }
/// ```
public struct A11yTraitBundle: Equatable, Sendable {

    // MARK: Properties

    /// The accessibility label read by VoiceOver (describes *what* the element is).
    public let label: String

    /// The accessibility hint read by VoiceOver (describes *how* to interact).
    /// Empty string means no hint is applied.
    public let hint: String

    /// SwiftUI accessibility traits combined into the element's trait set.
    public let traits: AccessibilityTraits

    // MARK: Init

    /// Creates a new bundle.
    ///
    /// - Parameters:
    ///   - label:  Accessibility label.  Must be non-empty.
    ///   - hint:   Accessibility hint.  Defaults to empty (no hint applied).
    ///   - traits: `AccessibilityTraits` to attach.  Defaults to `.isStaticText`.
    public init(
        label: String,
        hint: String = "",
        traits: AccessibilityTraits = .isStaticText
    ) {
        self.label  = label
        self.hint   = hint
        self.traits = traits
    }

    // MARK: Factory helpers

    /// A bundle suitable for a tappable list row that navigates to a detail screen.
    public static func listRow(label: String, hint: String = A11yRoleHints.doubleTapToOpen) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: hint, traits: [.isButton])
    }

    /// A bundle suitable for a standalone action button.
    public static func button(label: String, hint: String = "") -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: hint, traits: [.isButton])
    }

    /// A bundle suitable for a header / section title.
    public static func header(label: String) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: "", traits: [.isHeader])
    }

    /// A bundle suitable for a read-only link element.
    public static func link(label: String) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: A11yRoleHints.doubleTapToOpen, traits: [.isLink])
    }

    /// A bundle suitable for a status / badge element that is read-only.
    public static func badge(label: String) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: "", traits: [.isStaticText])
    }

    /// A bundle suitable for an image that conveys meaning.
    public static func image(label: String) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: "", traits: [.isImage])
    }

    // MARK: Functional combinators

    /// Returns a new bundle with the label replaced.
    public func withLabel(_ newLabel: String) -> A11yTraitBundle {
        A11yTraitBundle(label: newLabel, hint: hint, traits: traits)
    }

    /// Returns a new bundle with the hint replaced.
    public func withHint(_ newHint: String) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: newHint, traits: traits)
    }

    /// Returns a new bundle with additional traits merged in.
    public func addingTraits(_ additional: AccessibilityTraits) -> A11yTraitBundle {
        A11yTraitBundle(label: label, hint: hint, traits: traits.union(additional))
    }
}

// MARK: - ViewModifier

/// Applies an `A11yTraitBundle` to a SwiftUI view in a single call.
private struct A11yTraitBundleModifier: ViewModifier {

    let bundle: A11yTraitBundle

    func body(content: Content) -> some View {
        var modified = content
            .accessibilityLabel(bundle.label)
            .accessibilityAddTraits(bundle.traits)

        if !bundle.hint.isEmpty {
            modified = modified.accessibilityHint(bundle.hint)
        }

        return modified
    }
}

// MARK: - View extension

public extension View {

    /// Applies a pre-composed `A11yTraitBundle` (label + hint + traits) to this view.
    ///
    /// ```swift
    /// TicketRow()
    ///     .accessibilityBundle(
    ///         .listRow(label: "Ticket TKT-042, Open, due tomorrow")
    ///     )
    /// ```
    func accessibilityBundle(_ bundle: A11yTraitBundle) -> some View {
        modifier(A11yTraitBundleModifier(bundle: bundle))
    }
}

// MARK: - AccessibilityTraits set union helper

private extension AccessibilityTraits {
    /// Returns new `AccessibilityTraits` by merging `other` into the receiver.
    func union(_ other: AccessibilityTraits) -> AccessibilityTraits {
        var result = self
        result.formUnion(other)
        return result
    }
}
