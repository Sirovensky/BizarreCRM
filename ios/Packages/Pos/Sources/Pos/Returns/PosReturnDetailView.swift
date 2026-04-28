#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.9 — Full invoice return detail: per-line checkboxes, qty steppers,
/// restock flags, tender picker, manager PIN gate above threshold.
///
/// Presented when a cashier taps an invoice row in `PosReturnsView`.
/// Replaces the simpler `PosRefundSheet` for the enhanced flow.
///
/// iPhone: `.large` sheet with scrollable form.
/// iPad: centred panel at 620 pt.
///
/// Manager PIN threshold: `PosTenantLimits.refundManagerPinThresholdCents`
/// (default $50.00 = 5,000 cents).
@MainActor
public struct PosReturnDetailView: View {

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var vm: PosReturnDetailViewModel
    @State private var showManagerPin: Bool = false

    // MARK: - Init

    public init(invoice: InvoiceSummary, api: APIClient?) {
        _vm = State(wrappedValue: PosReturnDetailViewModel(invoice: invoice, api: api))
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    phoneLayout
                } else {
                    padLayout
                }
            }
            .navigationTitle("Process Return")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 620)
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet(
                reason: "Refund of \(CartMath.formatCents(vm.totalRefundCents)) requires manager approval.",
                onApproved: { managerId in
                    vm.managerApprovedId = managerId
                    Task { await vm.submit() }
                },
                onCancelled: { }
            )
        }
        .task { await vm.loadLines() }
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        Form {
            invoiceHeaderSection
            linesSectionContent
            tenderSection
            reasonSection
            summarySection
            statusSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var padLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: line selector
            Form {
                linesSectionContent
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .frame(minWidth: 300, idealWidth: 380)

            Divider()

            // Right: header + controls + submit
            Form {
                invoiceHeaderSection
                tenderSection
                reasonSection
                summarySection
                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }

    // MARK: - Sections

    private var invoiceHeaderSection: some View {
        Section("Invoice") {
            LabeledContent("Order", value: vm.invoice.displayId)
                .accessibilityIdentifier("pos.returnDetail.orderId")
            LabeledContent("Customer", value: vm.invoice.customerName)
                .accessibilityIdentifier("pos.returnDetail.customer")
            LabeledContent("Total") {
                Text(CartMath.formatCents(Int(((vm.invoice.total ?? 0) * 100).rounded())))
                    .monospacedDigit()
                    .font(.brandTitleSmall())
            }
        }
    }

    @ViewBuilder
    private var linesSectionContent: some View {
        if vm.isLoadingLines {
            Section {
                HStack {
                    ProgressView()
                    Text("Loading invoice lines…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityIdentifier("pos.returnDetail.loadingLines")
            }
        } else {
            Section("Select lines to return") {
                Toggle("Full invoice refund", isOn: $vm.fullRefund)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("pos.returnDetail.fullRefund")

                if !vm.fullRefund {
                    PosReturnLineSelector(lines: $vm.lines)
                }
            }
        }
    }

    private var tenderSection: some View {
        Section("Refund via") {
            Picker("Tender", selection: $vm.tender) {
                ForEach(PosReturnDetailViewModel.Tender.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pos.returnDetail.tender")

            if vm.tender == .original {
                Text("Original payment method — available for card tenders via BlockChyp refund token.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private var reasonSection: some View {
        Section("Reason") {
            Picker("Category", selection: $vm.reasonCategory) {
                ForEach(PosReturnDetailViewModel.ReasonCategory.allCases) { cat in
                    Text(cat.label).tag(cat)
                }
            }
            .accessibilityIdentifier("pos.returnDetail.reasonCategory")
            TextField("Additional notes (optional)", text: $vm.notes, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("pos.returnDetail.notes")
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            PosReturnSummaryBar(
                selectedLines: vm.effectiveLines,
                managerPinThresholdCents: vm.managerPinThresholdCents
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch vm.status {
        case .idle, .sending:
            EmptyView()
        case .failed(let msg):
            Section {
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("pos.returnDetail.error")
            }
        case .sent(let msg):
            Section {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityIdentifier("pos.returnDetail.success")
            }
        case .unavailable(let msg):
            Section {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityIdentifier("pos.returnDetail.unavailable")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if case .sending = vm.status {
                ProgressView()
            } else {
                Button("Refund") {
                    if vm.requiresManagerPin && vm.managerApprovedId == nil {
                        showManagerPin = true
                    } else {
                        Task { await vm.submit() }
                    }
                }
                .disabled(!vm.canSubmit)
                .fontWeight(.semibold)
                .accessibilityIdentifier("pos.returnDetail.submit")
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class PosReturnDetailViewModel {

    // MARK: - Types

    enum Status: Equatable, Sendable {
        case idle
        case sending
        case sent(String)
        case failed(String)
        case unavailable(String)
    }

    enum Tender: String, CaseIterable, Identifiable, Sendable {
        case original, cash, credit
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: return "Original"
            case .cash:     return "Cash"
            case .credit:   return "Store credit"
            }
        }
        var wireValue: String {
            switch self {
            case .original: return "card"
            case .cash:     return "cash"
            case .credit:   return "credit"
            }
        }
    }

    enum ReasonCategory: String, CaseIterable, Identifiable, Sendable {
        case customerRequest = "customer_request"
        case defective = "defective"
        case wrongItem = "wrong_item"
        case damaged = "damaged"
        case other = "other"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .customerRequest: return "Customer request"
            case .defective:       return "Defective"
            case .wrongItem:       return "Wrong item"
            case .damaged:         return "Damaged"
            case .other:           return "Other"
            }
        }
    }

    // MARK: - Published state

    var lines: [ReturnableLine] = []
    var fullRefund: Bool = true
    var tender: Tender = .original
    var reasonCategory: ReasonCategory = .customerRequest
    var notes: String = ""
    var isLoadingLines: Bool = false
    var status: Status = .idle
    var managerApprovedId: Int64?

    // MARK: - Stored

    @ObservationIgnored let invoice: InvoiceSummary
    @ObservationIgnored let api: APIClient?

    /// Tenant-configurable PIN threshold. Default $50.00.
    let managerPinThresholdCents: Int = PosTenantLimits.shared.refundManagerPinThresholdCents

    init(invoice: InvoiceSummary, api: APIClient?) {
        self.invoice = invoice
        self.api = api
    }

    // MARK: - Derived

    var effectiveLines: [ReturnableLine] {
        if fullRefund {
            // When doing a full refund, synthesize a single line with the invoice total.
            let totalCents = Int(((invoice.total ?? 0) * 100).rounded())
            return [ReturnableLine(
                id: 0,
                description: "Full refund of \(invoice.displayId)",
                originalQty: 1,
                unitPriceCents: totalCents,
                isSelected: true,
                restock: false
            )]
        }
        return lines
    }

    var totalRefundCents: Int {
        effectiveLines.filter(\.isSelected).map(\.refundCents).reduce(0, +)
    }

    var requiresManagerPin: Bool {
        totalRefundCents > managerPinThresholdCents
    }

    var canSubmit: Bool {
        guard case .sending = status else {
            return totalRefundCents > 0
        }
        return false
    }

    // MARK: - Data

    func loadLines() async {
        guard let api else { return }
        isLoadingLines = true
        defer { isLoadingLines = false }

        do {
            let detail = try await api.getInvoiceDetail(id: invoice.id)
            lines = detail.lineItems.map { item in
                ReturnableLine(
                    id: item.id,
                    description: item.name ?? item.description ?? "Item",
                    originalQty: item.qty,
                    unitPriceCents: item.unitPriceCents
                )
            }
        } catch {
            // Non-fatal — fall back to full-refund mode if lines can't be fetched.
            AppLog.pos.warning("Could not load invoice lines: \(error.localizedDescription, privacy: .public)")
            lines = []
            fullRefund = true
        }
    }

    // MARK: - Submit

    func submit() async {
        guard canSubmit, let api else {
            if api == nil { status = .unavailable("Server not connected.") }
            return
        }
        status = .sending

        let selected = effectiveLines.filter(\.isSelected)
        let requestLines: [PosReturnLineRequest] = selected.map { line in
            PosReturnLineRequest(
                invoiceLineId: line.id == 0 ? nil : line.id,
                description: line.description,
                quantity: line.qtyToReturn,
                unitPriceCents: line.unitPriceCents
            )
        }

        let reason = "\(reasonCategory.label)\(notes.isEmpty ? "" : " · \(notes)")"
        let request = PosReturnRequest(
            invoiceId: invoice.id,
            reason: reason,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            tender: tender.wireValue,
            lines: requestLines
        )

        do {
            let resp = try await api.posReturn(request)
            let refunded = resp.refundedCents ?? totalRefundCents
            AppLog.pos.info("POS return: invoice=\(invoice.id) refunded=\(refunded)c tender=\(tender.wireValue)")
            BrandHaptics.success()
            status = .sent("Refunded \(CartMath.formatCents(refunded)).")
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            await fallbackToStoreCredit()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Fallback

    private func fallbackToStoreCredit() async {
        guard let api, let customerId = invoice.customerId else {
            status = .unavailable("Coming soon — contact admin to enable the returns module.")
            return
        }
        let req = CustomerCreditRefundRequest(
            amountCents: totalRefundCents,
            reason: "\(reasonCategory.label)\(notes.isEmpty ? "" : " · \(notes)")",
            sourceInvoiceId: invoice.id
        )
        do {
            _ = try await api.refundCustomerCredit(customerId: customerId, request: req)
            BrandHaptics.success()
            status = .sent("Issued \(CartMath.formatCents(totalRefundCents)) store credit.")
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            status = .unavailable("Coming soon — not yet enabled on your server.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

// MARK: - APIClient extension for invoice detail

private extension APIClient {
    /// `GET /api/v1/invoices/:id` — returns the invoice with nested line items.
    func getInvoiceDetail(id: Int64) async throws -> InvoiceDetailWithLines {
        try await get("/api/v1/invoices/\(id)", as: InvoiceDetailWithLines.self)
    }
}

// MARK: - Invoice detail DTO (minimal — only what returns needs)

struct InvoiceDetailWithLines: Decodable, Sendable {
    let lineItems: [InvoiceLineItem]

    enum CodingKeys: String, CodingKey {
        case lineItems = "line_items"
        case lines
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server may use either "line_items" or "lines"
        if let items = try? c.decodeIfPresent([InvoiceLineItem].self, forKey: .lineItems) {
            lineItems = items ?? []
        } else {
            lineItems = (try? c.decodeIfPresent([InvoiceLineItem].self, forKey: .lines)) ?? []
        }
    }
}

// MARK: - PosTenantLimits extension (refund threshold)

private extension PosTenantLimits {
    static let shared = PosTenantLimits(
        maxCashierDiscountPercent: 0,
        maxCashierDiscountCents: 0,
        priceOverrideThresholdCents: 0,
        voidRequiresManager: false,
        noSaleRequiresManager: false
    )
    /// Manager PIN required for refunds above this amount. Default $50 = 5,000 cents.
    var refundManagerPinThresholdCents: Int { 5_000 }
}

// MARK: - Preview

// Preview disabled — InvoiceSummary has no public memberwise init
// (Decodable-only). Restore via JSONDecoder + sample fixture if needed.
#endif
