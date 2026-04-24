#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

private struct InvoiceVoidBody: Encodable, Sendable { let reason: String? }
private struct InvoiceVoidResponse: Decodable, Sendable { let id: Int64? }

// §22 — iPad invoice context menu: Open, Copy ID, Mark Paid, Void
//
// Archive + Delete intentionally NOT exposed — server has no PATCH or DELETE
// route for invoices (invoices.routes.ts lines 232-1066). Void is the only
// server-supported destructive op: POST /api/v1/invoices/:id/void.

/// Wraps any row content in a `.contextMenu` providing the standard §22
/// iPad invoice actions. Handles its own sheet/alert presentation so callers
/// only supply callbacks.
///
/// Usage:
/// ```swift
/// InvoiceContextMenu(invoice: inv, api: api, onRefresh: { ... }) {
///     InvoiceRow(invoice: inv)
/// }
/// ```
public struct InvoiceContextMenu<Content: View>: View {

    // MARK: - Inputs

    private let invoice: InvoiceSummary
    private let api: APIClient
    private let onRefresh: () -> Void
    private let content: () -> Content

    // MARK: - Internal sheet / alert state

    @State private var showMarkPaidConfirm: Bool = false
    @State private var showVoidConfirm: Bool = false
    @State private var isMarkingPaid: Bool = false
    @State private var isVoiding: Bool = false
    @State private var errorMessage: String?

    // MARK: - Init

    public init(
        invoice: InvoiceSummary,
        api: APIClient,
        onRefresh: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.invoice = invoice
        self.api = api
        self.onRefresh = onRefresh
        self.content = content
    }

    // MARK: - Body

    public var body: some View {
        content()
            .contextMenu {
                menuItems
            }
            .confirmationDialog(
                "Mark as Paid?",
                isPresented: $showMarkPaidConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark Paid") {
                    Task { await performMarkPaid() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will record a full payment against invoice \(invoice.displayId).")
            }
            .confirmationDialog(
                "Void Invoice?",
                isPresented: $showVoidConfirm,
                titleVisibility: .visible
            ) {
                Button("Void", role: .destructive) {
                    Task { await performVoid() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Invoice \(invoice.displayId) will be voided. This action is permanent.")
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                if let msg = errorMessage {
                    Text(msg)
                }
            }
    }

    // MARK: - Menu items

    @ViewBuilder
    private var menuItems: some View {
        // Open (primary — navigates to detail; caller handles via selection binding)
        Button {
            // Selection is handled by the parent List binding; no action needed here.
            // This button exists for keyboard-accessible context menu completeness.
        } label: {
            Label("Open", systemImage: "doc.text")
        }
        .accessibilityLabel("Open invoice \(invoice.displayId)")

        // Copy ID
        Button {
            UIPasteboard.general.string = invoice.displayId
        } label: {
            Label("Copy ID", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy invoice ID \(invoice.displayId)")

        Divider()

        // Mark Paid — only available when the invoice can accept a payment
        if canMarkPaid {
            Button {
                showMarkPaidConfirm = true
            } label: {
                Label(isMarkingPaid ? "Marking Paid…" : "Mark Paid", systemImage: "checkmark.circle")
            }
            .disabled(isMarkingPaid)
            .accessibilityLabel("Mark invoice \(invoice.displayId) as paid")
        }

        Divider()

        // Void (destructive; only server-supported destructive op)
        Button(role: .destructive) {
            showVoidConfirm = true
        } label: {
            Label(isVoiding ? "Voiding…" : "Void", systemImage: "xmark.octagon")
        }
        .disabled(isVoiding || (invoice.status ?? "").lowercased() == "void")
        .accessibilityLabel("Void invoice \(invoice.displayId)")
    }

    // MARK: - Computed helpers

    /// Invoice can be marked paid when it is unpaid or partial and has an amount due.
    private var canMarkPaid: Bool {
        let s = (invoice.status ?? "").lowercased()
        guard s != "paid" && s != "void" else { return false }
        return (invoice.amountDue ?? 0) > 0
    }

    // MARK: - Actions

    /// POST /api/v1/invoices/:id/payments (full amount due)
    private func performMarkPaid() async {
        guard let due = invoice.amountDue, due > 0 else { return }
        isMarkingPaid = true
        defer { isMarkingPaid = false }
        do {
            let body = RecordInvoicePaymentRequest(
                amount: due,
                method: "cash",
                notes: "Marked paid via context menu"
            )
            _ = try await api.recordPayment(invoiceId: invoice.id, body: body)
            onRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Void: POST /api/v1/invoices/:id/void (the only server-supported
    /// destructive op; see invoices.routes.ts line 803).
    private func performVoid() async {
        isVoiding = true
        defer { isVoiding = false }
        do {
            _ = try await api.post(
                "/api/v1/invoices/\(invoice.id)/void",
                body: InvoiceVoidBody(reason: "Voided from iPad context menu"),
                as: InvoiceVoidResponse.self
            )
            onRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
