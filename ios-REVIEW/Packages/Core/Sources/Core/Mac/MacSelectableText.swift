// Core/Mac/MacSelectableText.swift
//
// `.macSelectableID()` SwiftUI ViewModifier that applies
// `.textSelection(.enabled)` so users on Mac (and iPad with hardware keyboard)
// can drag-select and ⌘C copy IDs / phone numbers / emails / invoice numbers
// / SKUs / tags from any list row or detail header.
//
// On iPhone the modifier is a no-op (saves the gesture-conflict surface area
// where long-press already opens a context menu).
//
// §23.3 Mac (Designed for iPad) polish — `.textSelection(.enabled)` on every
// ID, phone, email, invoice number, tag.
//
// Usage:
// ```swift
// Text(ticket.publicID).macSelectableID()
// Text(customer.email).macSelectableID()
// Text(invoice.number).macSelectableID()
// ```

import SwiftUI
import Foundation

// MARK: - MacSelectableIDModifier

/// Backing modifier for the public `.macSelectableID()` extension.
///
/// Applies `.textSelection(.enabled)` whenever the runtime is Mac
/// ("Designed for iPad" via `ProcessInfo.processInfo.isiOSAppOnMac`) or iPad
/// (where pointer + hardware keyboard make text selection useful).  On iPhone
/// it falls through to the standard non-selectable behaviour to avoid clashing
/// with the long-press context menu gesture.
public struct MacSelectableIDModifier: ViewModifier {

    /// Whether to force selection on every platform regardless of idiom.
    /// Pass `true` for fields where copy/paste is the primary action (e.g.
    /// public-tracking link displayed on a customer-facing receipt page).
    public let alwaysSelectable: Bool

    public init(alwaysSelectable: Bool = false) {
        self.alwaysSelectable = alwaysSelectable
    }

    public func body(content: Content) -> some View {
        if alwaysSelectable || Self.shouldEnableSelection {
            content.textSelection(.enabled)
        } else {
            content
        }
    }

    /// Whether selection should be enabled by default on this platform.
    /// Internal so tests can assert behaviour deterministically.
    static var shouldEnableSelection: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac { return true }
        #if canImport(UIKit)
        // Enable on iPad too — pointer + magic keyboard are common.
        return UITraitCollection.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
        #endif
    }
}

// MARK: - View extension

public extension View {
    /// Marks this view's text content as a copyable identifier.
    ///
    /// On Mac (Designed for iPad) and iPad the underlying `Text` is rendered
    /// with `.textSelection(.enabled)` so the user can drag-select and ⌘C copy
    /// the value.  On iPhone the modifier is a no-op.
    ///
    /// Use on every visible **ID, phone, email, invoice number, SKU, tag**
    /// per §23.3.  Pair with `.contextMenu` for an explicit Copy action where
    /// the value is a single-line glyph.
    ///
    /// - Parameter alwaysSelectable: When `true`, enables selection on every
    ///   platform (default `false`).
    func macSelectableID(alwaysSelectable: Bool = false) -> some View {
        modifier(MacSelectableIDModifier(alwaysSelectable: alwaysSelectable))
    }
}
