#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Persistence

/// §16.9 — refund sheet presented from `PosReturnsView`. Staff pick lines
/// (or request a full refund), choose a tender + reason, and submit. The
/// sheet tries `POST /pos/returns` first, falls back to
/// `POST /refunds/credits/:customerId` when the primary endpoint is
/// missing, and surfaces a "Coming soon" banner if both 404.
struct PosRefundSheet: View {
    @Environment(\.dismiss) private var dismiss
    let invoice: InvoiceSummary
    let api: APIClient?

    @State private var vm: PosRefundViewModel
    @State private var showingManagerPin: Bool = false

    init(invoice: InvoiceSummary, api: APIClient?) {
        self.invoice = invoice
        self.api = api
        _vm = State(wrappedValue: PosRefundViewModel(invoice: invoice, api: api))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invoice") {
                    LabeledContent("Order", value: invoice.displayId)
                    LabeledContent("Customer", value: invoice.customerName)
                    LabeledContent("Total") {
                        Text(CartMath.formatCents(Int(((invoice.total ?? 0) * 100).rounded())))
                            .monospacedDigit()
                    }
                }

                Section("Scope") {
                    Toggle("Full refund", isOn: $vm.fullRefund)
                        .accessibilityIdentifier("pos.refund.fullToggle")
                    if !vm.fullRefund {
                        Text("Partial-line refunds ship with §16.9.1.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                // §16.9 — restock flag: per-return disposition toggle.
                // "Return to stock" increments inventory; "Scrap" does not.
                Section {
                    Toggle(isOn: $vm.restockItem) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Return to stock")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Text(vm.restockItem
                                     ? "Item will be re-added to inventory"
                                     : "Item will be scrapped — inventory unchanged")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        } icon: {
                            Image(systemName: vm.restockItem ? "arrow.uturn.up.circle.fill" : "trash.circle")
                                .foregroundStyle(vm.restockItem ? Color.bizarreSuccess : Color.bizarreError)
                        }
                    }
                    .accessibilityIdentifier("pos.refund.restockToggle")
                } header: {
                    Text("Inventory disposition")
                } footer: {
                    Text("Sent to server as the \u{201C}restock\u{201D} field on the return request.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Section("Tender") {
                    Picker("Tender", selection: $vm.tender) {
                        ForEach(PosRefundViewModel.Tender.allCases) { tender in
                            Text(tender.label).tag(tender)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pos.refund.tender")
                }

                Section("Reason") {
                    // §16.9 — reason presets. Picker drives the structured
                    // wire value (see `PosRefundReason`). Selecting `.other`
                    // unlocks the free-text field for staff to elaborate.
                    Picker("Reason", selection: $vm.reasonPreset) {
                        ForEach(PosRefundReason.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("pos.refund.reasonPreset")

                    if vm.reasonPreset == .other {
                        TextField("Reason (required)", text: $vm.reason)
                            .accessibilityIdentifier("pos.refund.reason")
                    }
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("pos.refund.notes")
                }

                if vm.requiresManagerPin {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.bizarreWarning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manager approval required")
                                    .font(.brandLabelLarge())
                                    .foregroundStyle(.bizarreOnSurface)
                                Text(vm.managerPinReason)
                                    .font(.brandBodySmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .accessibilityIdentifier("pos.refund.managerNotice")
                    }
                }

                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .sending = vm.status {
                        ProgressView()
                    } else {
                        Button("Refund") {
                            // §16.9 — gate above-threshold refunds behind a
                            // manager PIN before posting. Below threshold or
                            // when staff already has approval flagged, fall
                            // through to the normal submit path.
                            if vm.requiresManagerPin {
                                showingManagerPin = true
                            } else {
                                Task { await vm.submit() }
                            }
                        }
                        .disabled(!vm.canSubmit)
                        .accessibilityIdentifier("pos.refund.submit")
                    }
                }
            }
            .onChange(of: vm.status) { _, new in
                if case .sent = new {
                    Task {
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingManagerPin) {
                ManagerPinSheet(
                    reason: vm.managerPinReason,
                    onApproved: { managerId in
                        vm.note(managerApproval: managerId)
                        Task { await vm.submit() }
                    },
                    onCancelled: {}
                )
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var statusSection: some View {
        switch vm.status {
        case .idle, .sending:
            EmptyView()
        case .failed(let message):
            Section {
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("pos.refund.error")
            }
        case .sent(let message):
            Section {
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityIdentifier("pos.refund.success")
            }
        case .unavailable(let message):
            Section {
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityIdentifier("pos.refund.unavailable")
            }
        }
    }
}

/// Refund view model. Keeps the endpoint-fallback logic out of the view
/// layer so the SwiftUI surface stays a thin shell over decisions.
@MainActor
@Observable
final class PosRefundViewModel {
    enum Status: Equatable, Sendable {
        case idle
        case sending
        case sent(String)
        case failed(String)
        case unavailable(String)
    }

    enum Tender: String, CaseIterable, Identifiable, Sendable {
        case card, cash, credit
        var id: String { rawValue }
        var label: String {
            switch self {
            case .card:   return "Card"
            case .cash:   return "Cash"
            case .credit: return "Store credit"
            }
        }
        var wireValue: String { rawValue }
    }

    var fullRefund: Bool = true
    var tender: Tender = .card
    /// §16.9 — preset picker; selecting `.other` reveals the free-text field.
    /// The wire-side `reason` string is the merged (preset + text) value
    /// computed at submit time.
    var reasonPreset: PosRefundReason = .none
    var reason: String = ""
    var notes: String = ""
    /// §16.9 — `true` = return item to inventory; `false` = scrap (no stock increment).
    /// Defaults to `true` (most returns go back to stock).
    var restockItem: Bool = true
    private(set) var status: Status = .idle
    /// §16.9 — manager id captured from `ManagerPinSheet` when the refund
    /// crosses the tenant's PIN threshold. Logged with the refund audit
    /// entry; cleared once the request lands.
    private(set) var managerApprovalId: Int64?

    @ObservationIgnored let invoice: InvoiceSummary
    @ObservationIgnored let api: APIClient?

    init(invoice: InvoiceSummary, api: APIClient?) {
        self.invoice = invoice
        self.api = api
    }

    var canSubmit: Bool {
        if case .sending = status { return false }
        // §16.9 — when the picker says `.other`, require explicit text so
        // we never submit an unstructured-but-empty reason.
        if reasonPreset == .other,
           reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    /// §16.9 — total refund amount in cents. Lifted from `invoice.total`
    /// (dollars) and rounded to cents.
    var refundCents: Int {
        Int(((invoice.total ?? 0) * 100).rounded())
    }

    /// §16.9 — true when the refund crosses the tenant-configured PIN
    /// threshold. Skipped once a manager has already approved this round.
    var requiresManagerPin: Bool {
        guard managerApprovalId == nil else { return false }
        let limits = PosTenantLimits.current()
        return refundCents > limits.refundManagerPinThresholdCents
    }

    /// User-facing copy passed to `ManagerPinSheet` so the manager sees
    /// what they're approving before tapping their PIN.
    var managerPinReason: String {
        let amount = CartMath.formatCents(refundCents)
        let threshold = CartMath.formatCents(PosTenantLimits.current().refundManagerPinThresholdCents)
        return "Refund \(amount) exceeds threshold of \(threshold)"
    }

    /// Capture the manager id from `ManagerPinSheet`. Persisted on the
    /// view model so it survives the brief gap between the PIN sheet
    /// dismissing and `submit()` resuming.
    func note(managerApproval id: Int64) {
        managerApprovalId = id
    }

    /// §16.9 — merged structured + free-text refund reason. Empty string
    /// when the cashier left both blank.
    func mergedReason() -> String {
        let trimmedFree = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reasonPreset {
        case .none:
            return trimmedFree
        case .other:
            return trimmedFree
        default:
            return trimmedFree.isEmpty
                ? reasonPreset.label
                : "\(reasonPreset.label) — \(trimmedFree)"
        }
    }

    func submit() async {
        guard let api else {
            status = .unavailable("Coming soon — not yet enabled on your server.")
            return
        }
        status = .sending

        let totalCents = Int(((invoice.total ?? 0) * 100).rounded())
        // §16.9 — merge the preset label with any free-text the staff
        // entered so the server gets a structured + descriptive reason.
        let trimmedReason = mergedReason()
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // §16.9 — record manager-approved refund to the audit log before
        // the network round-trip; matches the `delete_line` / `no_sale`
        // pattern in `Cart.removeLine` and `PosView.handleNoSale`.
        if let managerId = managerApprovalId {
            try? await PosAuditLogStore.shared.record(
                event: PosAuditEntry.EventType.managerApprovedRefund,
                cashierId: 0,
                managerId: managerId,
                amountCents: totalCents,
                context: [
                    "invoiceId": invoice.id,
                    "reason": trimmedReason
                ]
            )
        }

        let request = PosReturnRequest(
            invoiceId: invoice.id,
            reason: trimmedReason.isEmpty ? nil : trimmedReason,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            tender: tender.wireValue,
            lines: [],
            restock: restockItem
        )
        do {
            let resp = try await api.posReturn(request)
            let amount = resp.refundedCents ?? totalCents
            status = .sent("Refunded \(CartMath.formatCents(amount)).")
            return
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            // Primary returns endpoint not deployed — try the store-credit
            // fallback if we have a customer id.
            await fallbackToStoreCredit(totalCents: totalCents, trimmedReason: trimmedReason)
            return
        } catch {
            self.status = .failed(error.localizedDescription)
            return
        }
    }

    private func fallbackToStoreCredit(totalCents: Int, trimmedReason: String) async {
        guard let api, let customerId = invoice.customerId else {
            status = .unavailable("Coming soon — not yet enabled on your server.")
            return
        }
        let request = CustomerCreditRefundRequest(
            amountCents: totalCents,
            reason: trimmedReason.isEmpty ? nil : trimmedReason,
            sourceInvoiceId: invoice.id
        )
        do {
            _ = try await api.refundCustomerCredit(customerId: customerId, request: request)
            status = .sent("Issued \(CartMath.formatCents(totalCents)) store credit.")
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            status = .unavailable("Coming soon — not yet enabled on your server.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
#endif
