import SwiftUI

/// §22.4 — Keyboard shortcut overlay for the iPad 3-column search layout.
///
/// Supported shortcuts:
///   ⌘F        — Focus the search field (focusedField binding must be wired)
///   ⌘1…⌘5    — Activate scope 1-5 (Customers / Tickets / Inventory / Invoices / Notes)
///   ↑          — Select previous result
///   ↓          — Select next result
///   Return      — Open selected result (preview pane "Open" CTA)
///
/// Usage: add `.searchKeyboardShortcuts(...)` to the root view.
public extension View {

    /// Attach all §22 iPad keyboard shortcuts to the view hierarchy.
    ///
    /// - Parameters:
    ///   - selectedScope: Binding to the currently active `SearchScope`.
    ///   - focusedField: Binding controlling which field has focus (uses `SearchFocusField`).
    ///   - hitCount: Total number of results in the current result list.
    ///   - selectedIndex: Binding to the zero-based index of the selected result (nil = none).
    ///   - onOpen: Called when the user presses Return to open the selected result.
    func searchKeyboardShortcuts(
        selectedScope: Binding<SearchScope>,
        focusedField: Binding<SearchFocusField?>,
        hitCount: Int,
        selectedIndex: Binding<Int?>,
        onOpen: @escaping () -> Void
    ) -> some View {
        modifier(SearchKeyboardShortcutsModifier(
            selectedScope: selectedScope,
            focusedField: focusedField,
            hitCount: hitCount,
            selectedIndex: selectedIndex,
            onOpen: onOpen
        ))
    }
}

// MARK: - Focus field token

/// Focus state token for the search field in the 3-column layout.
public enum SearchFocusField: Hashable {
    case searchBar
}

// MARK: - Modifier

private struct SearchKeyboardShortcutsModifier: ViewModifier {

    @Binding var selectedScope: SearchScope
    @Binding var focusedField: SearchFocusField?
    let hitCount: Int
    @Binding var selectedIndex: Int?
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        // All shortcuts are registered via the hidden background command group.
        // Using `.background` keeps the modifier composable and avoids
        // double-registering shortcuts at different levels of the view tree.
        content
            .background(
                SearchShortcutCommands(
                    selectedScope: $selectedScope,
                    focusedField: $focusedField,
                    hitCount: hitCount,
                    selectedIndex: $selectedIndex,
                    onOpen: onOpen
                )
            )
    }
}

// MARK: - Command group view

/// Hidden zero-size view that registers all keyboard shortcuts as SwiftUI commands.
/// Using a background ZStack-invisible view avoids polluting the visible layout.
private struct SearchShortcutCommands: View {

    @Binding var selectedScope: SearchScope
    @Binding var focusedField: SearchFocusField?
    let hitCount: Int
    @Binding var selectedIndex: Int?
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            // ⌘F — focus search bar
            Button("Focus Search") {
                focusedField = .searchBar
            }
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Focus search field")
            .hidden()

            // ⌘1-5 — scope picker
            scopeShortcuts

            // ↑ — navigate up
            Button("Previous Result") {
                moveToPrevious()
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .accessibilityLabel("Select previous result")
            .hidden()

            // ↓ — navigate down
            Button("Next Result") {
                moveToNext()
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .accessibilityLabel("Select next result")
            .hidden()

            // Return — open selected
            Button("Open Selected Result") {
                if selectedIndex != nil {
                    onOpen()
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Open selected result")
            .hidden()
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Scope shortcuts (⌘1–⌘5)

    @ViewBuilder
    private var scopeShortcuts: some View {
        ForEach(SearchScope.allCases.filter { $0.shortcutDigit != nil }, id: \.self) { scope in
            if let digit = scope.shortcutDigit, let key = KeyEquivalent(digit) {
                Button("Scope: \(scope.displayName)") {
                    selectedScope = scope
                }
                .keyboardShortcut(key, modifiers: .command)
                .accessibilityLabel("Switch to \(scope.displayName) scope")
                .hidden()
            }
        }
    }

    // MARK: - Navigation helpers

    private func moveToPrevious() {
        guard hitCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, current - 1)
        } else {
            selectedIndex = hitCount - 1
        }
    }

    private func moveToNext() {
        guard hitCount > 0 else { return }
        if let current = selectedIndex {
            selectedIndex = min(hitCount - 1, current + 1)
        } else {
            selectedIndex = 0
        }
    }
}

// MARK: - KeyEquivalent helper

private extension KeyEquivalent {
    /// Convert an Int digit (1-9) to a `KeyEquivalent`.
    init?(_ digit: Int) {
        let chars: [Int: Character] = [
            1: "1", 2: "2", 3: "3", 4: "4", 5: "5",
            6: "6", 7: "7", 8: "8", 9: "9"
        ]
        guard let char = chars[digit] else { return nil }
        self = KeyEquivalent(char)
    }
}
