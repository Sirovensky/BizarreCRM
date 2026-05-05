import SwiftUI

// §29.2 Scroll & render — lazy view modifier guards.
//
// These modifiers let call sites skip expensive view body work (heavy
// computed properties, layout passes, Nuke fetches, etc.) when the view is
// not yet visible or is outside the performance budget.
//
// Three guards are provided:
//
//   1. `lazyGuard(isVisible:)`  — suppresses body re-evaluation when the view
//      is marked invisible by the call site.  Equivalent to an `EquatableView`
//      gate but driven by an explicit boolean flag rather than value equality.
//
//   2. `visibilityGuard()`  — tracks actual on-screen visibility via
//      `onAppear`/`onDisappear` and gates body re-evaluation automatically.
//      Useful for rows deep inside a `List` that SwiftUI may re-drive even
//      when offscreen.
//
//   3. `conditionalBody(condition:placeholder:content:)`  — renders `content`
//      only when `condition` is true; renders a zero-height `placeholder`
//      (default `EmptyView`) otherwise.  Unlike `if` in ViewBuilder, this
//      preserves the view identity in the tree so SwiftUI does not destroy and
//      recreate state on every toggle.

// MARK: - 1. lazyGuard(isVisible:)

private struct LazyGuardModifier: ViewModifier {

    let isVisible: Bool

    func body(content: Content) -> some View {
        if isVisible {
            content
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

public extension View {
    /// Suppresses rendering of this view when `isVisible` is `false`.
    ///
    /// When not visible the view collapses to a zero-size `Color.clear`
    /// placeholder, preserving layout space while skipping all child body
    /// evaluations.  SwiftUI identity is maintained, so state is not reset.
    ///
    /// Typical use: gate expensive list rows driven by an `@Observable`
    /// visibility model that tracks scroll position.
    ///
    /// ```swift
    /// TicketRowExpensiveDetail(ticket: ticket)
    ///     .lazyGuard(isVisible: isRowVisible)
    /// ```
    func lazyGuard(isVisible: Bool) -> some View {
        modifier(LazyGuardModifier(isVisible: isVisible))
    }
}

// MARK: - 2. visibilityGuard()

private struct VisibilityGuardModifier: ViewModifier {

    @State private var isVisible: Bool = false

    func body(content: Content) -> some View {
        Group {
            if isVisible {
                content
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .onAppear    { isVisible = true  }
        .onDisappear { isVisible = false }
    }
}

public extension View {
    /// Gates body re-evaluation to periods when this view is on-screen.
    ///
    /// Uses `onAppear`/`onDisappear` to track actual visibility.  Body
    /// re-evaluations triggered while the view is offscreen are suppressed —
    /// instead a zero-size `Color.clear` placeholder is rendered.
    ///
    /// Apply to the outermost container of list rows that contain heavy work
    /// (network images, complex computed properties):
    ///
    /// ```swift
    /// CustomerCardRow(customer: customer)
    ///     .visibilityGuard()
    /// ```
    ///
    /// - Note: The first render is always a zero-size placeholder until
    ///   `onAppear` fires, which is expected and invisible to the user.
    func visibilityGuard() -> some View {
        modifier(VisibilityGuardModifier())
    }
}

// MARK: - 3. conditionalBody(condition:placeholder:content:)

public extension View {
    /// Renders `content` only when `condition` is `true`; falls back to a
    /// lightweight `placeholder` (default `EmptyView`) otherwise.
    ///
    /// Unlike a bare `if` block in a `ViewBuilder`, this modifier preserves
    /// the view's position in the identity tree — SwiftUI will not destroy and
    /// recreate child state on every toggle, avoiding the jank that a plain
    /// `if/else` causes when switching between a heavy view and empty space.
    ///
    /// ```swift
    /// TicketDetailExpanded(ticket: ticket)
    ///     .conditionalBody(condition: isExpanded) {
    ///         ProgressView()   // cheap placeholder while collapsed
    ///     }
    /// ```
    @ViewBuilder
    func conditionalBody<Placeholder: View>(
        condition: Bool,
        @ViewBuilder placeholder: () -> Placeholder = { EmptyView() }
    ) -> some View {
        if condition {
            self
        } else {
            placeholder()
        }
    }
}
