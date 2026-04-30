// Core/Mac/MacListKeyboardNav.swift
//
// `.macListKeyboardNav(…)` SwiftUI ViewModifier — wires up ↑/↓ arrow keys to
// move the selection cursor through a list and ↵ Return to open the
// highlighted row.  Built on `.focusable()` + `.onMoveCommand` + `.onCommand`
// (Mac/iPad with hardware keyboard).  No-op on iPhone without a hardware
// keyboard.
//
// §23.3 Mac polish — Keyboard arrows nav through lists (↑↓) with ↵ to open.
//
// Usage:
// ```swift
// List(tickets) { ticket in TicketRow(ticket: ticket) }
//     .macListKeyboardNav(
//         count: tickets.count,
//         selection: $selectedIndex,
//         onOpen: { idx in coordinator.openTicket(tickets[idx]) }
//     )
// ```
//
// The caller owns the `selection` binding so it can drive row highlight
// styling itself (`.background` colour, etc.).  This modifier is purely
// keyboard plumbing.

import SwiftUI

// MARK: - MacListKeyboardNavModifier

/// Backing modifier for `.macListKeyboardNav(…)`.
///
/// Marks the wrapped view `.focusable()` so it can receive key events, then
/// translates ↑/↓ `.onMoveCommand` into `selection` mutations, clamped to
/// `[0, count - 1]`, and ↵ Return into `onOpen(selection)`.
public struct MacListKeyboardNavModifier: ViewModifier {

    /// Total number of rows.  When the list grows the modifier rewires its
    /// clamping logic on the next render, so callers should pass the live
    /// count.
    public let count: Int

    /// External selection binding — caller keeps the source of truth.
    @Binding public var selection: Int

    /// Triggered on ↵ Return with the **clamped** current selection.
    public let onOpen: (Int) -> Void

    /// When `false`, the wrapped view never receives key focus and key events
    /// fall through to the next responder.  Useful when a sheet / modal
    /// covers the list.
    public let isEnabled: Bool

    public init(
        count: Int,
        selection: Binding<Int>,
        isEnabled: Bool = true,
        onOpen: @escaping (Int) -> Void
    ) {
        self.count = max(0, count)
        self._selection = selection
        self.isEnabled = isEnabled
        self.onOpen = onOpen
    }

    public func body(content: Content) -> some View {
        content
            .focusable(isEnabled)
            .onMoveCommand { direction in
                guard isEnabled, count > 0 else { return }
                switch direction {
                case .up:
                    selection = Self.clamp(selection - 1, count: count)
                case .down:
                    selection = Self.clamp(selection + 1, count: count)
                default:
                    break
                }
            }
            // ↵ Return — open the highlighted row.
            .onSubmit {
                guard isEnabled, count > 0 else { return }
                onOpen(Self.clamp(selection, count: count))
            }
    }

    /// Public for tests — clamps `index` to `[0, count - 1]`, returning 0 when
    /// the list is empty.
    public static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        if index < 0 { return 0 }
        if index >= count { return count - 1 }
        return index
    }
}

// MARK: - View extension

public extension View {
    /// Wires ↑/↓ + ↵ keyboard navigation to a row-based list.
    ///
    /// - Parameters:
    ///   - count: Number of rows in the list.
    ///   - selection: Binding to the current highlighted-row index.
    ///   - isEnabled: When `false` the modifier is dormant (default `true`).
    ///   - onOpen: Closure invoked with the current index on ↵ Return.
    func macListKeyboardNav(
        count: Int,
        selection: Binding<Int>,
        isEnabled: Bool = true,
        onOpen: @escaping (Int) -> Void
    ) -> some View {
        modifier(
            MacListKeyboardNavModifier(
                count: count,
                selection: selection,
                isEnabled: isEnabled,
                onOpen: onOpen
            )
        )
    }
}
