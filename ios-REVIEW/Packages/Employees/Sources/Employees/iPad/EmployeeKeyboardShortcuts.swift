// §22 — iPad Employees keyboard shortcuts: ⌘F, ⌘R, ⌘I, ⌘D

// MARK: - EmployeeShortcut metadata (no UIKit dependency — headless testable)

/// Static metadata for each Employees iPad keyboard shortcut.
/// This type has NO UIKit/SwiftUI dependency so tests run on macOS.
public enum EmployeeShortcut: CaseIterable, Sendable {
    case search
    case refresh
    case clockInOut
    case deactivate

    public var key: Character {
        switch self {
        case .search:     return "f"
        case .refresh:    return "r"
        case .clockInOut: return "i"
        case .deactivate: return "d"
        }
    }

    public var displayTitle: String {
        switch self {
        case .search:     return "Search Employees"
        case .refresh:    return "Refresh List"
        case .clockInOut: return "Clock In / Out"
        case .deactivate: return "Deactivate Employee"
        }
    }

    /// Used in accessibility hints and unit tests.
    /// Always includes the word "Command" so tests can verify modifier key.
    public var accessibilityHint: String {
        "Command \(key.uppercased())"
    }
}

#if canImport(UIKit)
import SwiftUI

public extension EmployeeShortcut {
    var modifiers: SwiftUI.EventModifiers { .command }
}

/// `ViewModifier` that attaches §22 keyboard shortcuts to
/// `EmployeesThreeColumnView`. Sits at the root so shortcuts fire
/// regardless of which column holds focus.
///
/// Shortcuts:
/// - ⌘F — Focus search (raises sidebar search / filter sheet)
/// - ⌘R — Refresh employee list
/// - ⌘I — Clock selected employee in or out
/// - ⌘D — Deactivate / reactivate selected employee
public struct EmployeeKeyboardShortcuts: ViewModifier {

    // MARK: - Callbacks

    private let onSearch: () -> Void
    private let onRefresh: () -> Void
    private let onClockInOut: () -> Void
    private let onDeactivate: () -> Void

    // MARK: - Init

    public init(
        onSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onClockInOut: @escaping () -> Void,
        onDeactivate: @escaping () -> Void
    ) {
        self.onSearch = onSearch
        self.onRefresh = onRefresh
        self.onClockInOut = onClockInOut
        self.onDeactivate = onDeactivate
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .background(shortcutButton("Search employees", key: "f", action: onSearch))
            .background(shortcutButton("Refresh employee list", key: "r", action: onRefresh))
            .background(shortcutButton("Clock in or out", key: "i", action: onClockInOut))
            .background(shortcutButton("Deactivate employee", key: "d", action: onDeactivate))
    }

    // MARK: - Private helpers

    @ViewBuilder
    private func shortcutButton(
        _ label: String,
        key: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button("") { action() }
            .keyboardShortcut(key, modifiers: .command)
            .accessibilityLabel(label)
            .hidden()
    }
}

// MARK: - View convenience

public extension View {
    /// Attach §22 Employee iPad keyboard shortcuts.
    func employeeKeyboardShortcuts(
        onSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onClockInOut: @escaping () -> Void,
        onDeactivate: @escaping () -> Void
    ) -> some View {
        modifier(EmployeeKeyboardShortcuts(
            onSearch: onSearch,
            onRefresh: onRefresh,
            onClockInOut: onClockInOut,
            onDeactivate: onDeactivate
        ))
    }
}

#endif
