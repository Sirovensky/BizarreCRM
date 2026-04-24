import SwiftUI

/// §22 — Keyboard shortcut registrar for iPad audit-log views.
///
/// Registers three shortcuts as invisible `Button`s embedded in the view tree:
///   - ⌘F  — focus / show filter UI
///   - ⌘R  — refresh the log list
///   - ⌘E  — export current list as CSV
///
/// Embed in any container view using `.background(AuditKeyboardShortcuts(...))`.
/// The buttons have zero size so they never affect layout; they only provide
/// the `.keyboardShortcut` responder chain entries.
///
/// Example:
/// ```swift
/// .background(
///     AuditKeyboardShortcuts(
///         onFilter:  { vm.showFilterSheet = true },
///         onRefresh: { Task { await vm.load() } },
///         onExport:  { exportCSV() }
///     )
/// )
/// ```
public struct AuditKeyboardShortcuts: View {

    private let onFilter: () -> Void
    private let onRefresh: () -> Void
    private let onExport: () -> Void

    public init(
        onFilter: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) {
        self.onFilter = onFilter
        self.onRefresh = onRefresh
        self.onExport = onExport
    }

    public var body: some View {
        // Zero-size container; exists solely for keyboard shortcut registration.
        ZStack {
            // ⌘F — Filter
            Button(action: onFilter) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Filter audit logs")
            .accessibilityIdentifier("kbd.audit.filter")
            .frame(width: 0, height: 0)

            // ⌘R — Refresh
            Button(action: onRefresh) {
                EmptyView()
            }
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh audit logs")
            .accessibilityIdentifier("kbd.audit.refresh")
            .frame(width: 0, height: 0)

            // ⌘E — Export CSV
            Button(action: onExport) {
                EmptyView()
            }
            .keyboardShortcut("e", modifiers: .command)
            .accessibilityLabel("Export audit logs as CSV")
            .accessibilityIdentifier("kbd.audit.export")
            .frame(width: 0, height: 0)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shortcut descriptor (for documentation / tests)

/// Describes a single keyboard shortcut registered by AuditKeyboardShortcuts.
public struct AuditShortcutDescriptor: Sendable, Equatable {
    public let key: Character
    public let modifiers: EventModifiers
    public let description: String

    public init(key: Character, modifiers: EventModifiers, description: String) {
        self.key = key
        self.modifiers = modifiers
        self.description = description
    }
}

public extension AuditKeyboardShortcuts {
    /// All shortcuts registered by this view, in canonical order.
    static let shortcuts: [AuditShortcutDescriptor] = [
        .init(key: "f", modifiers: .command, description: "Filter audit logs"),
        .init(key: "r", modifiers: .command, description: "Refresh audit logs"),
        .init(key: "e", modifiers: .command, description: "Export audit logs as CSV"),
    ]
}
