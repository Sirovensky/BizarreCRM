import SwiftUI
import DesignSystem

// MARK: - ReportKeyboardShortcuts

/// Keyboard-shortcut bindings for the iPad Reports 3-column layout.
///
/// Shortcuts registered:
///   ⌘1  — switch to Revenue report
///   ⌘2  — switch to Expenses report
///   ⌘3  — switch to Inventory report
///   ⌘4  — switch to Owner P&L report
///   ⌘E  — export current report as PDF (triggers `onExport`)
///   ⌘R  — refresh all report data (triggers `onRefresh`)
///
/// These are additive — attach via `.reportKeyboardShortcuts(...)` on the
/// `ReportsThreeColumnView` container.
public struct ReportKeyboardShortcuts: ViewModifier {

    // MARK: - Dependencies

    @Binding public var selectedCategory: ReportCategory

    /// Called when ⌘E is pressed.
    public let onExport: () -> Void

    /// Called when ⌘R is pressed.
    public let onRefresh: () -> Void

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            // ⌘1 — Revenue
            .background(
                Button("") { selectedCategory = .revenue }
                    .keyboardShortcut("1", modifiers: .command)
                    .accessibilityHidden(true)
            )
            // ⌘2 — Expenses
            .background(
                Button("") { selectedCategory = .expenses }
                    .keyboardShortcut("2", modifiers: .command)
                    .accessibilityHidden(true)
            )
            // ⌘3 — Inventory
            .background(
                Button("") { selectedCategory = .inventory }
                    .keyboardShortcut("3", modifiers: .command)
                    .accessibilityHidden(true)
            )
            // ⌘4 — Owner P&L
            .background(
                Button("") { selectedCategory = .ownerPL }
                    .keyboardShortcut("4", modifiers: .command)
                    .accessibilityHidden(true)
            )
            // ⌘E — Export
            .background(
                Button("") { onExport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .accessibilityHidden(true)
            )
            // ⌘R — Refresh
            .background(
                Button("") { onRefresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityHidden(true)
            )
    }
}

// MARK: - View extension

public extension View {
    /// Attaches all Reports iPad keyboard shortcuts to this view.
    ///
    /// Example:
    /// ```swift
    /// ReportsThreeColumnView(repository: repo)
    ///     .reportKeyboardShortcuts(
    ///         selectedCategory: $category,
    ///         onExport: { Task { await export() } },
    ///         onRefresh: { Task { await refresh() } }
    ///     )
    /// ```
    func reportKeyboardShortcuts(
        selectedCategory: Binding<ReportCategory>,
        onExport: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        modifier(
            ReportKeyboardShortcuts(
                selectedCategory: selectedCategory,
                onExport: onExport,
                onRefresh: onRefresh
            )
        )
    }
}

// MARK: - ShortcutBinding (pure data type for tests)

/// Describes a single keyboard shortcut binding.
/// Useful for unit-testing that the correct key+modifier combos are declared.
public struct ReportShortcutBinding: Equatable, Sendable {
    public let key: Character
    public let modifiers: EventModifiers
    public let category: ReportCategory?
    public let action: ReportShortcutAction

    public init(
        key: Character,
        modifiers: EventModifiers,
        category: ReportCategory?,
        action: ReportShortcutAction
    ) {
        self.key = key
        self.modifiers = modifiers
        self.category = category
        self.action = action
    }
}

public enum ReportShortcutAction: String, Sendable, CaseIterable {
    case selectCategory
    case export
    case refresh
}

/// Returns all expected shortcut bindings for the iPad Reports layout.
/// Call from unit tests to verify shortcut registration is complete.
public func allReportShortcutBindings() -> [ReportShortcutBinding] {
    [
        ReportShortcutBinding(key: "1", modifiers: .command, category: .revenue,   action: .selectCategory),
        ReportShortcutBinding(key: "2", modifiers: .command, category: .expenses,  action: .selectCategory),
        ReportShortcutBinding(key: "3", modifiers: .command, category: .inventory, action: .selectCategory),
        ReportShortcutBinding(key: "4", modifiers: .command, category: .ownerPL,   action: .selectCategory),
        ReportShortcutBinding(key: "e", modifiers: .command, category: nil,        action: .export),
        ReportShortcutBinding(key: "r", modifiers: .command, category: nil,        action: .refresh),
    ]
}
