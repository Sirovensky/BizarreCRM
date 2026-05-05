// §22 — iPad invoice keyboard shortcuts: ⌘N, ⌘F, ⌘R, ⌘P

// MARK: - Key descriptions (for tests + UI)

/// Static metadata about each shortcut. Used in accessibility hints and tests.
/// This type has NO UIKit/SwiftUI dependency so it can be tested on macOS.
public enum InvoiceShortcut: CaseIterable, Sendable {
    case new, search, refresh, print_

    public var key: Character {
        switch self {
        case .new:     return "n"
        case .search:  return "f"
        case .refresh: return "r"
        case .print_:  return "p"
        }
    }

    public var displayTitle: String {
        switch self {
        case .new:     return "New Invoice"
        case .search:  return "Search"
        case .refresh: return "Refresh"
        case .print_:  return "Print"
        }
    }

    public var accessibilityHint: String {
        "Command \(key.uppercased())"
    }
}

#if canImport(UIKit)
import SwiftUI

public extension InvoiceShortcut {
    var modifiers: SwiftUI.EventModifiers { .command }
}

/// `ViewModifier` that attaches the four standard §22 keyboard shortcuts to the
/// Invoices three-column view. Designed to sit at the root of
/// `InvoicesThreeColumnView` so shortcuts fire regardless of focus column.
///
/// Shortcuts:
/// - ⌘N — New invoice (triggers create flow)
/// - ⌘F — Focus search (raises search bar in content column)
/// - ⌘R — Refresh list
/// - ⌘P — Print current invoice
public struct InvoiceKeyboardShortcuts: ViewModifier {

    // MARK: - Callbacks

    private let onNew: () -> Void
    private let onSearch: () -> Void
    private let onRefresh: () -> Void
    private let onPrint: () -> Void

    // MARK: - Init

    public init(
        onNew: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onPrint: @escaping () -> Void
    ) {
        self.onNew = onNew
        self.onSearch = onSearch
        self.onRefresh = onRefresh
        self.onPrint = onPrint
    }

    // MARK: - Body

    @ViewBuilder
    private func shortcutButton(_ label: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button("") { action() }
            .keyboardShortcut(key, modifiers: .command)
            .accessibilityLabel(label)
            .hidden()
    }

    public func body(content: Content) -> some View {
        content
            .background(shortcutButton("New invoice", key: "n", action: onNew))
            .background(shortcutButton("Search invoices", key: "f", action: onSearch))
            .background(shortcutButton("Refresh invoice list", key: "r", action: onRefresh))
            .background(shortcutButton("Print invoice", key: "p", action: onPrint))
    }
}

// MARK: - View convenience

public extension View {
    /// Attach §22 invoice keyboard shortcuts.
    func invoiceKeyboardShortcuts(
        onNew: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onPrint: @escaping () -> Void
    ) -> some View {
        modifier(InvoiceKeyboardShortcuts(
            onNew: onNew,
            onSearch: onSearch,
            onRefresh: onRefresh,
            onPrint: onPrint
        ))
    }
}

#endif
