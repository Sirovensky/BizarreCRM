#if canImport(UIKit)
import SwiftUI

// MARK: - CustomerKeyboardShortcuts

/// Registers iPad keyboard shortcuts for the Customers section.
///
/// | Shortcut | Action         |
/// |----------|----------------|
/// | ⌘N       | New customer   |
/// | ⌘F       | Focus search   |
/// | ⌘R       | Refresh list   |
///
/// Embed as a `.background` on the root view so shortcuts are active
/// regardless of which column has keyboard focus:
/// ```swift
/// .background(CustomerKeyboardShortcuts(
///     onNewCustomer: { showingCreate = true },
///     onFocusSearch: { showingSearch = true },
///     onRefresh:     { Task { await vm.refresh() } }
/// ))
/// ```
public struct CustomerKeyboardShortcuts: View {
    let onNewCustomer: () -> Void
    let onFocusSearch: () -> Void
    let onRefresh: () -> Void

    public init(
        onNewCustomer: @escaping () -> Void,
        onFocusSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.onNewCustomer = onNewCustomer
        self.onFocusSearch = onFocusSearch
        self.onRefresh = onRefresh
    }

    public var body: some View {
        // Zero-size view; only here to host keyboard shortcut commands.
        ZStack {
            newCustomerCommand
            focusSearchCommand
            refreshCommand
        }
        .frame(width: 0, height: 0)
        .hidden()
    }

    // MARK: - Command buttons

    /// ⌘N — New customer
    private var newCustomerCommand: some View {
        Button(action: onNewCustomer) {
            EmptyView()
        }
        .keyboardShortcut("N", modifiers: .command)
        .accessibilityLabel("New customer")
        .accessibilityHint("Creates a new customer record")
    }

    /// ⌘F — Focus search field
    private var focusSearchCommand: some View {
        Button(action: onFocusSearch) {
            EmptyView()
        }
        .keyboardShortcut("F", modifiers: .command)
        .accessibilityLabel("Search customers")
        .accessibilityHint("Moves focus to the search field")
    }

    /// ⌘R — Refresh list
    private var refreshCommand: some View {
        Button(action: onRefresh) {
            EmptyView()
        }
        .keyboardShortcut("R", modifiers: .command)
        .accessibilityLabel("Refresh")
        .accessibilityHint("Refreshes the customer list")
    }
}
#endif
