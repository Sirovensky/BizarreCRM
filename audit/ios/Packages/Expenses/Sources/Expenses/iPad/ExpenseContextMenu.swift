import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ExpenseContextMenu
//
// Context-menu content for an expense row on iPad (3-col and 2-col list).
// Used via .contextMenu { ExpenseContextMenu(...) } at the call site.
//
// Actions and their route grounding:
//   Open      — navigates to ExpenseDetailView (no network call)
//   Duplicate — POST /api/v1/expenses  (server: insert a copy with same fields)
//   Delete    — DELETE /api/v1/expenses/:id  (confirmed: route exists in expenses.routes.ts,
//               guard: owner OR admin, audited)
//   Export    — client-side CSV export via ExpenseCSVExporter, no server call required
//
// All destructive actions require confirmation via an alert owned by the parent.
// This view only emits callbacks; state management stays in the parent.

public struct ExpenseContextMenu: View {

    // MARK: Dependencies

    let expense: Expense
    let api: APIClient

    // MARK: Callbacks

    /// Called after a successful duplicate (parent should refresh list).
    var onDuplicated: ((Int64) -> Void)?
    /// Called after a successful delete (parent should remove item).
    var onDeleted: (() -> Void)?

    // MARK: Local state

    @State private var isDuplicating: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    // MARK: Body

    public var body: some View {
        // Open
        NavigationLink(value: expense.id) {
            Label("Open", systemImage: "arrow.up.forward.square")
        }
        .accessibilityLabel("Open expense detail")
        .accessibilityIdentifier("expenses.context.open")

        Divider()

        // Duplicate
        Button {
            Task { await duplicate() }
        } label: {
            Label(
                isDuplicating ? "Duplicating…" : "Duplicate",
                systemImage: isDuplicating ? "clock" : "doc.on.doc"
            )
        }
        .disabled(isDuplicating || isDeleting)
        .accessibilityLabel("Duplicate expense")
        .accessibilityIdentifier("expenses.context.duplicate")

        // Export
        Button {
            exportExpense()
        } label: {
            Label("Export CSV", systemImage: "arrow.down.doc")
        }
        .accessibilityLabel("Export expense as CSV")
        .accessibilityIdentifier("expenses.context.export")

        Divider()

        // Delete (destructive)
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(isDuplicating || isDeleting)
        .accessibilityLabel("Delete expense")
        .accessibilityIdentifier("expenses.context.delete")
        // Confirmation alert — presented on the containing view tree via alert(isPresented:)
        // SwiftUI surfaces confirmationDialog/alert attached to .contextMenu buttons
        // on iOS 16+ when the button's role is .destructive.
        .confirmationDialog(
            "Delete this expense?",
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteExpense() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Action failed", isPresented: $showErrorAlert) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Duplicate

    private func duplicate() async {
        guard !isDuplicating else { return }
        isDuplicating = true
        defer { isDuplicating = false }

        let body = CreateExpenseRequest(
            category: expense.category ?? "Other",
            amount: expense.amount ?? 0,
            description: expense.description,
            date: expense.date,
            vendor: expense.vendor,
            taxAmount: expense.taxAmount,
            paymentMethod: expense.paymentMethod,
            notes: expense.notes,
            isReimbursable: expense.isReimbursable
        )

        do {
            let resp = try await api.createExpense(body)
            onDuplicated?(resp.id)
        } catch {
            AppLog.ui.error(
                "Expense duplicate failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    // MARK: - Delete

    private func deleteExpense() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await api.deleteExpense(id: expense.id)
            onDeleted?()
        } catch {
            AppLog.ui.error(
                "Expense delete failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    // MARK: - Export

    private func exportExpense() {
        let csv = ExpenseCSVExporter.csvLine(for: expense)
        let filename = "expense-\(expense.id).csv"
        ExpenseCSVExporter.share(csv: csv, filename: filename)
    }
}

// MARK: - ExpenseCSVExporter

/// Lightweight client-side CSV export for a single expense.
/// No server call required — all data already present in the `Expense` model.
public enum ExpenseCSVExporter {

    private static let header = "id,category,amount,date,description,vendor,status,payment_method,notes"

    /// Produces a two-line CSV string (header + data row).
    public static func csvLine(for expense: Expense) -> String {
        let row = [
            "\(expense.id)",
            escape(expense.category),
            expense.amount.map { String($0) } ?? "",
            escape(expense.date),
            escape(expense.description),
            escape(expense.vendor),
            escape(expense.status),
            escape(expense.paymentMethod),
            escape(expense.notes),
        ].joined(separator: ",")
        return "\(header)\n\(row)"
    }

    /// Writes the CSV string to a temp file and presents a share sheet.
    public static func share(csv: String, filename: String) {
        #if canImport(UIKit)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                let controller = UIActivityViewController(
                    activityItems: [tempURL],
                    applicationActivities: nil
                )
                if let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                   let root = scene.windows.first?.rootViewController {
                    root.present(controller, animated: true)
                }
            }
        } catch {
            AppLog.ui.error(
                "CSV export failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        #endif
    }

    // MARK: Helpers

    private static func escape(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "" }
        let escaped = v.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n")
            ? "\"\(escaped)\""
            : escaped
    }
}
