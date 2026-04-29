import SwiftUI

// MARK: - ArrowKeyRowSelection
//
// §22.3 — Hardware keyboard: ↑/↓ arrow keys navigate focusable list rows.
// The modifier wraps a list that manages a generic `Identifiable` collection
// and a `selectedId` binding.  When the user presses ↑ or ↓ the selection
// moves one step; wrapping is intentionally suppressed (at-boundary presses
// are no-ops matching native List behaviour).
//
// Usage:
// ```swift
// List(tickets, selection: $selectedId) { … }
//     .arrowKeyRowSelection(items: tickets, selectedId: $selectedId)
// ```

/// Attaches ↑/↓ arrow-key row navigation to any `List` or `ForEach`-backed
/// scroll view.
///
/// - Requirements: items must conform to `Identifiable`; `ID` must be `Hashable`.
/// - Platform: iPadOS 17+ (keyboard shortcuts compile on all platforms;
///   the hidden buttons are no-ops on iPhone because arrow keys have no effect).
public struct ArrowKeyRowSelectionModifier<Item: Identifiable>: ViewModifier where Item.ID: Hashable {

    private let items: [Item]
    @Binding private var selectedId: Item.ID?

    public init(items: [Item], selectedId: Binding<Item.ID?>) {
        self.items = items
        self._selectedId = selectedId
    }

    // MARK: Computed helpers

    private var selectedIndex: Int? {
        guard let id = selectedId else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            .background {
                Group {
                    Button("Previous row") { movePrevious() }
                        .keyboardShortcut(.upArrow, modifiers: [])
                        .hidden()
                        .accessibilityHidden(true)

                    Button("Next row") { moveNext() }
                        .keyboardShortcut(.downArrow, modifiers: [])
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
    }

    // MARK: Navigation

    private func moveNext() {
        guard !items.isEmpty else { return }
        if let idx = selectedIndex {
            let nextIdx = idx + 1
            if nextIdx < items.count {
                selectedId = items[nextIdx].id
            }
            // At last item — no wrap; matches native List behaviour.
        } else {
            selectedId = items.first?.id
        }
    }

    private func movePrevious() {
        guard !items.isEmpty else { return }
        if let idx = selectedIndex {
            let prevIdx = idx - 1
            if prevIdx >= 0 {
                selectedId = items[prevIdx].id
            }
            // At first item — no wrap.
        } else {
            selectedId = items.last?.id
        }
    }
}

// MARK: - View extension

public extension View {
    /// Attaches ↑/↓ arrow-key row selection to this view.
    ///
    /// Wire the same `selectedId` binding to the enclosing `List(selection:)`.
    /// Pressing ↓ advances the selection by one; ↑ retreats it.
    /// At the boundaries the selection stays on the current item (no wrap).
    ///
    /// - Parameters:
    ///   - items:      The same ordered array rendered by the list.
    ///   - selectedId: Binding to the currently-selected item's ID.
    func arrowKeyRowSelection<Item: Identifiable>(
        items: [Item],
        selectedId: Binding<Item.ID?>
    ) -> some View where Item.ID: Hashable {
        modifier(ArrowKeyRowSelectionModifier(items: items, selectedId: selectedId))
    }
}
