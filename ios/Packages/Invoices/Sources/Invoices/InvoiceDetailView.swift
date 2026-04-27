#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct InvoiceDetailView: View {
    @State private var vm: InvoiceDetailViewModel
    @State private var showPaySheet = false
    @State private var showRefundSheet = false
    @State private var showVoidAlert = false
    @State private var showReceiptSheet = false
    @State private var showCreditNoteSheet = false

    @ObservationIgnored private let api: APIClient

    public init(repo: InvoiceDetailRepository, invoiceId: Int64, api: APIClient) {
        _vm = State(wrappedValue: InvoiceDetailViewModel(repo: repo, invoiceId: invoiceId))
        self.api = api
    }

    public var body: some View {
        let voidVM: InvoiceVoidViewModel? = {
            if case let .loaded(inv) = vm.state {
                return InvoiceVoidViewModel(api: api, invoiceId: inv.id, canVoid: inv.canVoid)
            }
            return nil
        }()
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar { toolbarItems }
        .sheet(isPresented: $showPaySheet) {
            if case let .loaded(inv) = vm.state {
                let balanceCents = Int(((inv.amountDue ?? 0) * 100).rounded())
                InvoicePaymentSheet(
                    vm: InvoicePaymentViewModel(
                        api: api,
                        invoiceId: inv.id,
                        balanceCents: balanceCents,
                        customerId: inv.customerId
                    )
                ) { _ in Task { await vm.load() } }
            }
        }
        .sheet(isPresented: $showRefundSheet) {
            if case let .loaded(inv) = vm.state {
                let paidCents = Int(((inv.amountPaid ?? 0) * 100).rounded())
                let custId = inv.customerId ?? 0
                let lineItems = (inv.lineItems ?? []).map { item in
                    RefundLineItem(
                        id: item.id,
                        displayName: item.displayName,
                        totalCents: Int(((item.total ?? 0) * 100).rounded())
                    )
                }
                InvoiceRefundSheet(
                    vm: InvoiceRefundViewModel(
                        api: api,
                        invoiceId: inv.id,
                        customerId: custId,
                        totalPaidCents: paidCents,
                        lineItems: lineItems
                    )
                ) { _ in Task { await vm.load() } }
            }
        }
        .sheet(isPresented: $showReceiptSheet) {
            if case let .loaded(inv) = vm.state {
                InvoiceEmailReceiptSheet(
                    vm: InvoiceEmailReceiptViewModel(
                        api: api,
                        invoiceId: inv.id,
                        customerEmail: inv.customerEmail,
                        customerPhone: inv.customerPhone
                    )
                ) { Task { await vm.load() } }
            }
        }
        .invoiceVoidAlert(
            isPresented: $showVoidAlert,
            vm: voidVM ?? InvoiceVoidViewModel(api: api, invoiceId: 0, canVoid: false)
        ) { _ in Task { await vm.load() } }
        // §7.2 Credit note sheet
        .sheet(isPresented: $showCreditNoteSheet) {
            if case let .loaded(inv) = vm.state {
                let paidCents = Int(((inv.amountPaid ?? 0) * 100).rounded())
                InvoiceCreditNoteSheet(
                    api: api,
                    invoiceId: inv.id,
                    maxCents: paidCents
                ) { showCreditNoteSheet = false; Task { await vm.load() } }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if case let .loaded(inv) = vm.state {
            ToolbarItemGroup(placement: .topBarTrailing) {
                BrandGlassContainer {
                    if inv.canPay {
                        Button {
                            showPaySheet = true
                        } label: {
                            Label("Pay", systemImage: "creditcard")
                        }
                        .accessibilityLabel("Record payment")
                    }

                    if inv.canRefund {
                        Button {
                            showRefundSheet = true
                        } label: {
                            Label("Refund", systemImage: "arrow.uturn.left")
                        }
                        .accessibilityLabel("Issue refund")
                    }

                    Menu {
                        if inv.canVoid {
                            Button(role: .destructive) {
                                showVoidAlert = true
                            } label: {
                                Label("Void Invoice", systemImage: "xmark.circle")
                            }
                            .accessibilityLabel("Void this invoice")
                        }
                        Button {
                            showReceiptSheet = true
                        } label: {
                            Label("Email Receipt", systemImage: "envelope")
                        }
                        .accessibilityLabel("Email receipt to customer")
                        // §7.2 Credit note
                        if (inv.amountPaid ?? 0) > 0 {
                            Button {
                                showCreditNoteSheet = true
                            } label: {
                                Label("Issue Credit Note", systemImage: "minus.circle")
                            }
                            .accessibilityLabel("Issue credit note for this invoice")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var navTitle: String {
        if case let .loaded(inv) = vm.state { return inv.orderId ?? "Invoice" }
        return "Invoice"
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load invoice")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let inv):
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    HeaderCard(invoice: inv)
                    if let items = inv.lineItems, !items.isEmpty {
                        LineItemsCard(items: items)
                    }
                    TotalsCard(invoice: inv)
                    if let notes = inv.notes, !notes.isEmpty {
                        NotesCard(text: notes)
                    }
                    // §7.7 Payment history section
                    InvoicePaymentHistoryView(entries: buildPaymentHistory(from: inv))
                }
                .padding(BrandSpacing.base)
            }
        }
    }
}

// MARK: - Sections

private struct HeaderCard: View {
    let invoice: InvoiceDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(invoice.orderId ?? "INV-?")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                Text(invoice.customerDisplayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                StatusBadge(status: invoice.status)
            }

            if let phone = invoice.customerPhone, !phone.isEmpty {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "phone").foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(PhoneFormatter.format(phone))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }
            }
            if let email = invoice.customerEmail, !email.isEmpty {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "envelope").foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(email)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }
            }

            HStack {
                if let created = invoice.createdAt {
                    DateTile(label: "Issued", value: String(created.prefix(10)))
                }
                if let due = invoice.dueOn, !due.isEmpty {
                    DateTile(label: "Due", value: String(due.prefix(10)))
                }
            }
            .padding(.top, BrandSpacing.xs)
        }
        .cardBackground()
    }
}

private struct DateTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBadge: View {
    let status: String?

    var body: some View {
        let colors = colors(for: (status ?? "").lowercased())
        return Text(status?.capitalized ?? "—")
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(colors.fg)
            .background(colors.bg, in: Capsule())
    }

    private func colors(for kind: String) -> (bg: Color, fg: Color) {
        switch kind {
        case "paid":    return (.bizarreSuccess, .black)
        case "partial": return (.bizarreWarning, .black)
        case "unpaid":  return (.bizarreError, .black)
        case "void":    return (.bizarreOnSurfaceMuted, .bizarreSurfaceBase)
        default:        return (.bizarreSurface2, .bizarreOnSurface)
        }
    }
}

private struct LineItemsCard: View {
    let items: [InvoiceDetail.LineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Line items").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    HStack {
                        Text(item.displayName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(formatMoney(item.total ?? 0))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    HStack(spacing: BrandSpacing.sm) {
                        if let sku = item.sku, !sku.isEmpty {
                            Text(sku).font(.brandMono(size: 12)).foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        if let qty = item.quantity {
                            Text("×\(formatQty(qty))").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        if let price = item.unitPrice {
                            Text("@ \(formatMoney(price))")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, BrandSpacing.xxs)
            }
        }
        .cardBackground()
    }

    private func formatQty(_ v: Double) -> String {
        if v.rounded() == v { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}

private struct TotalsCard: View {
    let invoice: InvoiceDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Totals").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            if let sub = invoice.subtotal, sub != (invoice.total ?? 0) {
                row("Subtotal", value: sub)
            }
            if let disc = invoice.discount, disc > 0 {
                row("Discount", value: -disc, tint: .bizarreSuccess)
            }
            if let tax = invoice.totalTax, tax > 0 {
                row("Tax", value: tax)
            }
            Divider().overlay(Color.bizarreOutline.opacity(0.4))
            HStack {
                Text("Total").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(invoice.total ?? 0))
                    .font(.brandTitleLarge()).bold()
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            if let paid = invoice.amountPaid, paid > 0 {
                row("Paid", value: -paid, tint: .bizarreSuccess)
            }
            if let due = invoice.amountDue, due > 0 {
                HStack {
                    Text("Due")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreError)
                    Spacer()
                    Text(formatMoney(due))
                        .font(.brandTitleMedium()).bold()
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
            }
        }
        .cardBackground()
    }

    private func row(_ label: String, value: Double, tint: Color = .bizarreOnSurface) -> some View {
        HStack {
            Text(label).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(value)).font(.brandBodyMedium()).foregroundStyle(tint).monospacedDigit()
        }
    }
}

private struct NotesCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(text).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .cardBackground()
    }
}

// MARK: - Card helper

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
#endif
