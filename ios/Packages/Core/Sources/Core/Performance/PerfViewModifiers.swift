import SwiftUI

// §29.2 Scroll & render — debug redraw tracing + EquatableView convenience.
//
// `printChangesModifier()` — wraps `_printChanges()` in a DEBUG-only View
// modifier so call sites compile in both DEBUG and RELEASE without `#if DEBUG`
// scattered around feature code.
//
// `equatableRow()` — convenience shortcut for wrapping complex list-row
// content in `EquatableView` to prevent unnecessary re-renders when the model
// value hasn't changed.

// MARK: - PrintChanges modifier (§29.2 redraw traces)

private struct PrintChangesModifier: ViewModifier {
    func body(content: Content) -> some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        return content
    }
}

public extension View {
    /// Emits SwiftUI `_printChanges()` output in DEBUG builds whenever this
    /// view's body is re-evaluated. No-op in RELEASE builds.
    ///
    /// Apply to critical views you want to audit for spurious redraws:
    /// ```swift
    /// TicketRowView(ticket: ticket)
    ///     .printChangesDebug()
    /// ```
    func printChangesDebug() -> some View {
        modifier(PrintChangesModifier())
    }
}

// MARK: - EquatableView wrapper (§29.2 stable IDs / EquatableView)

public extension View {
    /// Wraps this view in `EquatableView` so SwiftUI skips re-rendering the
    /// body when the bound value compares equal.
    ///
    /// Use on complex row content where the parent container may rebuild but
    /// the underlying model hasn't changed:
    /// ```swift
    /// TicketRowView(ticket: ticket)
    ///     .equatableRow()
    /// ```
    ///
    /// The view must itself conform to `Equatable` for the optimisation to
    /// take effect. This modifier is a no-op otherwise (SwiftUI falls through
    /// to normal diffing).
    func equatableRow() -> EquatableView<Self> {
        EquatableView(content: self)
    }
}
