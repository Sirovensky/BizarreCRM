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

public extension View where Self: Equatable {
    /// Wraps this view in `EquatableView` so SwiftUI skips re-rendering the
    /// body when the bound value compares equal.
    ///
    /// The view **must** conform to `Equatable` for this modifier to be
    /// available. SwiftUI's `EquatableView` compares the previous and next
    /// view values and suppresses `body` evaluation when they are equal.
    ///
    /// Usage:
    /// ```swift
    /// struct TicketRowView: View, Equatable {
    ///     let ticket: Ticket
    ///     var body: some View { … }
    /// }
    ///
    /// // In the list:
    /// TicketRowView(ticket: ticket)
    ///     .equatableRow()
    /// ```
    func equatableRow() -> EquatableView<Self> {
        EquatableView(content: self)
    }
}
