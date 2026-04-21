#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

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
                    TextField("Reason (optional)", text: $vm.reason)
                        .accessibilityIdentifier("pos.refund.reason")
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("pos.refund.notes")
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
                            Task { await vm.submit() }
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
    var reason: String = ""
    var notes: String = ""
    private(set) var status: Status = .idle

    @ObservationIgnored let invoice: InvoiceSummary
    @ObservationIgnored let api: APIClient?

    init(invoice: InvoiceSummary, api: APIClient?) {
        self.invoice = invoice
        self.api = api
    }

    var canSubmit: Bool {
        if case .sending = status { return false }
        return true
    }

    func submit() async {
        guard let api else {
            status = .unavailable("Coming soon — not yet enabled on your server.")
            return
        }
        status = .sending

        let totalCents = Int(((invoice.total ?? 0) * 100).rounded())
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = PosReturnRequest(
            invoiceId: invoice.id,
            reason: trimmedReason.isEmpty ? nil : trimmedReason,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            tender: tender.wireValue,
            lines: []
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
