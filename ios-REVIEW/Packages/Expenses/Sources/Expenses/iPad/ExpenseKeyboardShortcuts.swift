import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ExpenseKeyboardShortcuts
//
// View modifier that wires keyboard shortcuts to expense list / detail actions.
// Apply to the root view of ExpensesThreeColumnView or any iPad Expenses screen.
//
// Shortcuts:
//   ⌘N        — create new expense
//   ⌘F        — focus filter
//   ⌘R        — refresh list
//   ⌘⌫        — delete selected expense (with confirmation)
//   ⌘D        — duplicate selected expense
//   ⌘⇧E       — export selected expense
//   Esc       — clear selection / dismiss

public struct ExpenseKeyboardShortcutModifier: ViewModifier {

    // MARK: Bindings from parent

    @Binding var showingCreate: Bool
    @Binding var showingFilter: Bool
    @Binding var showDeleteConfirm: Bool
    @Binding var selectedExpenseId: Int64?

    let onRefresh: () async -> Void
    let onDuplicate: ((Int64) async -> Void)?
    let onExport: ((Int64) -> Void)?

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            // ⌘N — new expense
            .keyboardShortcut("N", modifiers: .command)
            // Overlay invisible buttons to capture additional shortcuts
            // (SwiftUI routes keyboard shortcuts to whichever button is in the hierarchy)
            .background(shortcutButtons)
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        // ⌘F — filter
        Button("", action: { showingFilter = true })
            .keyboardShortcut("F", modifiers: .command)
            .accessibilityHidden(true)
            .frame(width: 0, height: 0)
            .hidden()

        // ⌘R — refresh
        Button("", action: { Task { await onRefresh() } })
            .keyboardShortcut("R", modifiers: .command)
            .accessibilityHidden(true)
            .frame(width: 0, height: 0)
            .hidden()

        // ⌘⌫ — delete selected
        Button("", action: {
            guard selectedExpenseId != nil else { return }
            showDeleteConfirm = true
        })
        .keyboardShortcut(.delete, modifiers: .command)
        .accessibilityHidden(true)
        .frame(width: 0, height: 0)
        .hidden()

        // ⌘D — duplicate selected
        if let duplicate = onDuplicate {
            Button("", action: {
                guard let id = selectedExpenseId else { return }
                Task { await duplicate(id) }
            })
            .keyboardShortcut("D", modifiers: .command)
            .accessibilityHidden(true)
            .frame(width: 0, height: 0)
            .hidden()
        }

        // ⌘⇧E — export selected
        if let export = onExport {
            Button("", action: {
                guard let id = selectedExpenseId else { return }
                export(id)
            })
            .keyboardShortcut("E", modifiers: [.command, .shift])
            .accessibilityHidden(true)
            .frame(width: 0, height: 0)
            .hidden()
        }
    }
}

// MARK: - View extension for ergonomic usage

public extension View {
    /// Attach expense-screen keyboard shortcuts.
    ///
    /// - Parameters:
    ///   - showingCreate: Binding that triggers the create sheet.
    ///   - showingFilter: Binding that triggers the filter sheet.
    ///   - showDeleteConfirm: Binding that triggers the delete confirmation dialog.
    ///   - selectedExpenseId: Currently selected expense (for single-item actions).
    ///   - onRefresh: Async closure invoked by ⌘R.
    ///   - onDuplicate: Optional closure invoked by ⌘D with the selected expense id.
    ///   - onExport: Optional closure invoked by ⌘⇧E with the selected expense id.
    func expenseKeyboardShortcuts(
        showingCreate: Binding<Bool>,
        showingFilter: Binding<Bool>,
        showDeleteConfirm: Binding<Bool>,
        selectedExpenseId: Binding<Int64?>,
        onRefresh: @escaping () async -> Void,
        onDuplicate: ((Int64) async -> Void)? = nil,
        onExport: ((Int64) -> Void)? = nil
    ) -> some View {
        modifier(
            ExpenseKeyboardShortcutModifier(
                showingCreate: showingCreate,
                showingFilter: showingFilter,
                showDeleteConfirm: showDeleteConfirm,
                selectedExpenseId: selectedExpenseId,
                onRefresh: onRefresh,
                onDuplicate: onDuplicate,
                onExport: onExport
            )
        )
    }
}

// MARK: - ExpenseKeyboardShortcutsHelpView

/// Popover / sheet that shows all available keyboard shortcuts.
/// Present via a ⌘/ handler or a "?" button in the toolbar.
public struct ExpenseKeyboardShortcutsHelpView: View {

    private struct ShortcutRow: Identifiable {
        let id = UUID()
        let keys: String
        let label: String
    }

    private static let rows: [ShortcutRow] = [
        .init(keys: "⌘ N",   label: "New expense"),
        .init(keys: "⌘ F",   label: "Filter expenses"),
        .init(keys: "⌘ R",   label: "Refresh list"),
        .init(keys: "⌘ ⌫",   label: "Delete selected expense"),
        .init(keys: "⌘ D",   label: "Duplicate selected expense"),
        .init(keys: "⌘ ⇧ E", label: "Export selected expense"),
        .init(keys: "⌘ E",   label: "Edit expense (in detail view)"),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Keyboard Shortcuts")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.bottom, BrandSpacing.xs)

            ForEach(Self.rows) { row in
                HStack {
                    Text(row.label)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(row.keys)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, BrandSpacing.xxs)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.vertical, BrandSpacing.xxs)

                if row.id != Self.rows.last?.id {
                    Divider()
                }
            }
        }
        .padding(BrandSpacing.lg)
        .frame(minWidth: 340)
    }
}
