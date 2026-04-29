#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct InvoiceDetailView: View {
    @State private var vm: InvoiceDetailViewModel
    /// §7 Customer card link — optional callback invoked when user taps the customer name.
    /// Caller (e.g. the host NavigationStack) should push `CustomerDetailView(customerId:)`.
    public var onNavigateToCustomer: ((Int64) -> Void)?
    @State private var showPaySheet = false
    @State private var showRefundSheet = false
    @State private var showVoidAlert = false
    @State private var showReceiptSheet = false
    @State private var showCreditNoteSheet = false
    // §7.2 Convert to credit note (overpaid)
    @State private var showConvertToCreditNote = false
    // §7.2 Editable line items
    @State private var showLineItemEditor = false
    // §7.2 Deposit invoice drill-through (tap deposit → push detail)
    @State private var depositDrillId: Int64?
    // §7.2 Clone invoice
    @State private var isCloning = false
    @State private var cloneError: String?
    @State private var clonedInvoiceId: Int64?
    // §7.2 SMS
    @State private var showSMSSheet = false
    // §7.7 Customer return flow
    @State private var showReturnSheet = false
    // §7.4 Post-payment receipt delivery sheet
    @State private var showReceiptDelivery = false
    @State private var lastPaymentCents: Int = 0
    // §7.2 Share PDF + AirPrint
    @State private var pdfURL: URL?
    @State private var isGeneratingPDF = false
    @State private var pdfError: String?
    @State private var showSharePDF = false
    @State private var showAirPrint = false
    @ObservationIgnored private let printService = InvoicePrintService()

    // §7.9 Installment plan
    @State private var installmentPlan: InstallmentPlan?
    @State private var showInstallmentEditor = false
    // §7.7 Late fee waiver
    @State private var showLateFeeWaiver = false
    // §7.13 Discount code input
    @State private var showDiscountInput = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let repo: InvoiceDetailRepository

    public init(
        repo: InvoiceDetailRepository,
        invoiceId: Int64,
        api: APIClient,
        onNavigateToCustomer: ((Int64) -> Void)? = nil
    ) {
        _vm = State(wrappedValue: InvoiceDetailViewModel(repo: repo, invoiceId: invoiceId))
        self.api = api
        self.repo = repo
        self.onNavigateToCustomer = onNavigateToCustomer
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
        .task {
            await vm.load()
            if case let .loaded(inv) = vm.state {
                await loadInstallmentPlan(invoiceId: inv.id)
            }
        }
        .refreshable {
            await vm.load()
            if case let .loaded(inv) = vm.state {
                await loadInstallmentPlan(invoiceId: inv.id)
            }
        }
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
                ) { result in
                    // §7.4 After successful payment, offer receipt delivery options.
                    let paid = Int(((result.amountPaid ?? 0) * 100).rounded())
                    lastPaymentCents = paid > 0 ? paid : balanceCents
                    Task {
                        await vm.load()
                        showPaySheet = false
                        showReceiptDelivery = true
                    }
                }
            }
        }
        // §7.4 Post-payment receipt delivery sheet (print / email / SMS / PDF).
        .sheet(isPresented: $showReceiptDelivery) {
            if case let .loaded(inv) = vm.state {
                InvoiceReceiptDeliverySheet(
                    vm: InvoiceReceiptDeliveryViewModel(
                        invoiceId: inv.id,
                        invoiceNumber: inv.orderId ?? "INV-\(inv.id)",
                        customerEmail: inv.customerEmail,
                        customerPhone: inv.customerPhone,
                        paymentCents: lastPaymentCents,
                        repository: InvoiceReceiptDeliveryRepositoryImpl(api: api)
                    ),
                    invoice: inv
                ) { Task { await vm.load() } }
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
        // §7.2 Editable line items
        .sheet(isPresented: $showLineItemEditor) {
            if case let .loaded(inv) = vm.state, let items = inv.lineItems {
                InvoiceLineItemEditorSheet(
                    api: api,
                    invoiceId: inv.id,
                    items: items
                ) { Task { await vm.load() } }
            }
        }
        // §7.2 Convert to credit note (overpaid) — reuses InvoiceCreditNoteSheet
        .sheet(isPresented: $showConvertToCreditNote) {
            if case let .loaded(inv) = vm.state {
                let overpaidCents = max(0, Int((((inv.amountPaid ?? 0) - (inv.total ?? 0)) * 100).rounded()))
                InvoiceCreditNoteSheet(
                    api: api,
                    invoiceId: inv.id,
                    maxCents: overpaidCents
                ) { showConvertToCreditNote = false; Task { await vm.load() } }
            }
        }
        // §7.2 Clone invoice — navigate to the cloned invoice detail sheet
        .sheet(
            isPresented: Binding(
                get: { clonedInvoiceId != nil },
                set: { if !$0 { clonedInvoiceId = nil } }
            )
        ) {
            if let newId = clonedInvoiceId {
                NavigationStack {
                    InvoiceDetailView(repo: repo, invoiceId: newId, api: api)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { clonedInvoiceId = nil }
                            }
                        }
                }
            }
        }
        // §7.2 Clone error alert
        .alert("Clone Failed", isPresented: Binding(
            get: { cloneError != nil },
            set: { if !$0 { cloneError = nil } }
        )) {
            Button("OK") { cloneError = nil }
        } message: {
            Text(cloneError ?? "Unknown error")
        }
        // §7.2 PDF error alert
        .alert("PDF Error", isPresented: Binding(
            get: { pdfError != nil },
            set: { if !$0 { pdfError = nil } }
        )) {
            Button("OK") { pdfError = nil }
        } message: {
            Text(pdfError ?? "Unknown error")
        }
        // §7.2 Send by SMS sheet
        .sheet(isPresented: $showSMSSheet) {
            if case let .loaded(inv) = vm.state {
                InvoiceSMSSheet(
                    vm: InvoiceSMSViewModel(
                        api: api,
                        invoiceId: inv.id,
                        orderId: inv.orderId,
                        customerPhone: inv.customerPhone,
                        paymentLinkURL: nil
                    )
                ) { showSMSSheet = false }
            }
        }
        // §7.2 Share PDF
        .sheet(isPresented: $showSharePDF) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
        // §7.9 Installment plan editor sheet
        .sheet(isPresented: $showInstallmentEditor) {
            if case let .loaded(inv) = vm.state {
                let totalCents = Int(((inv.total ?? 0) * 100).rounded())
                InstallmentPlanEditorSheet(
                    api: api,
                    invoiceId: inv.id,
                    totalCents: totalCents
                ) {
                    await loadInstallmentPlan(invoiceId: inv.id)
                    showInstallmentEditor = false
                }
            }
        }
        // §7.7 Late fee waiver sheet
        .sheet(isPresented: $showLateFeeWaiver) {
            if case let .loaded(inv) = vm.state {
                LateFeeWaiverSheet(
                    vm: LateFeeWaiverViewModel(api: api, invoiceId: inv.id, maxWaiverCents: 0)
                ) {
                    showLateFeeWaiver = false
                    Task { await vm.load() }
                }
            }
        }
        // §7.13 Discount code input sheet
        .sheet(isPresented: $showDiscountInput) {
            if case let .loaded(inv) = vm.state {
                InvoiceDiscountInputSheet(api: api, invoiceId: inv.id) { _ in
                    showDiscountInput = false
                    Task { await vm.load() }
                }
            }
        }
        // §7.7 Customer return flow sheet
        .sheet(isPresented: $showReturnSheet) {
            if case let .loaded(inv) = vm.state {
                let custId = inv.customerId ?? 0
                let returnLines: [InvoiceReturnLine] = (inv.lineItems ?? []).map { item in
                    InvoiceReturnLine(
                        id: item.id,
                        displayName: item.displayName,
                        sku: item.sku,
                        originalQty: Int((item.quantity ?? 1).rounded()),
                        unitPriceCents: Int(((item.unitPrice ?? 0) * 100).rounded())
                    )
                }
                InvoiceReturnSheet(
                    vm: InvoiceReturnViewModel(
                        api: api,
                        invoiceId: inv.id,
                        customerId: custId,
                        lines: returnLines
                    )
                ) { _ in
                    showReturnSheet = false
                    Task { await vm.load() }
                }
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
                        // §7.2 Send by SMS
                        if let phone = inv.customerPhone, !phone.isEmpty {
                            Button {
                                showSMSSheet = true
                            } label: {
                                Label("Send by SMS", systemImage: "message")
                            }
                            .accessibilityLabel("Send invoice by SMS")
                        }
                        // §7.2 Share PDF
                        Button {
                            Task { await generateAndSharePDF(inv) }
                        } label: {
                            if isGeneratingPDF {
                                Label("Generating…", systemImage: "doc.richtext")
                            } else {
                                Label("Share PDF", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isGeneratingPDF)
                        .accessibilityLabel("Share invoice as PDF")
                        // §7.2 AirPrint
                        Button {
                            Task { await generateAndPrint(inv) }
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        .accessibilityLabel("Print invoice via AirPrint")
                        // §7.2 Edit line items (if status allows)
                        if inv.canEditLines {
                            Button {
                                showLineItemEditor = true
                            } label: {
                                Label("Edit Line Items", systemImage: "pencil.line")
                            }
                            .accessibilityLabel("Edit invoice line items")
                        }
                        // §7.2 Credit note
                        if (inv.amountPaid ?? 0) > 0 {
                            Button {
                                showCreditNoteSheet = true
                            } label: {
                                Label("Issue Credit Note", systemImage: "minus.circle")
                            }
                            .accessibilityLabel("Issue credit note for this invoice")
                        }
                        // §7.2 Convert to credit note — if overpaid
                        if inv.isOverpaid {
                            Button {
                                showConvertToCreditNote = true
                            } label: {
                                Label("Convert Overpayment to Credit", systemImage: "arrow.left.arrow.right.circle")
                            }
                            .accessibilityLabel("Convert overpayment to credit note")
                        }
                        // §7.7 Return items (customer return flow)
                        if inv.canRefund {
                            Divider()
                            Button {
                                showReturnSheet = true
                            } label: {
                                Label("Return Items…", systemImage: "return")
                            }
                            .accessibilityLabel("Return items on this invoice")
                        }
                        // §7.2 Clone invoice
                        Button {
                            Task { await cloneInvoice(inv) }
                        } label: {
                            if isCloning {
                                Label("Cloning…", systemImage: "doc.on.doc")
                            } else {
                                Label("Clone Invoice", systemImage: "doc.on.doc")
                            }
                        }
                        .disabled(isCloning)
                        .accessibilityLabel("Clone this invoice")
                        Divider()
                        // §7.9 Installment plan editor
                        if inv.canPay || installmentPlan != nil {
                            Button {
                                showInstallmentEditor = true
                            } label: {
                                Label(
                                    installmentPlan == nil ? "Set Up Payment Plan" : "Edit Payment Plan",
                                    systemImage: "calendar.badge.clock"
                                )
                            }
                            .accessibilityLabel(installmentPlan == nil ? "Set up installment payment plan" : "Edit installment payment plan")
                        }
                        // §7.7 Waive late fee (always visible on non-void invoices)
                        if (inv.status ?? "").lowercased() != "void" {
                            Button {
                                showLateFeeWaiver = true
                            } label: {
                                Label("Waive Late Fee", systemImage: "minus.circle.fill")
                            }
                            .accessibilityLabel("Waive applied late fee")
                        }
                        // §7.13 Apply discount code
                        if inv.canEditLines {
                            Button {
                                showDiscountInput = true
                            } label: {
                                Label("Apply Discount Code", systemImage: "tag")
                            }
                            .accessibilityLabel("Apply a discount code to this invoice")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - §7.9 Installment plan load

    @MainActor
    private func loadInstallmentPlan(invoiceId: Int64) async {
        do {
            installmentPlan = try await api.invoiceInstallmentPlan(invoiceId: invoiceId)
        } catch {
            // No plan yet — leave nil; not an error condition
            installmentPlan = nil
        }
    }

    // MARK: - §7.2 Share PDF action

    @MainActor
    private func generateAndSharePDF(_ inv: InvoiceDetail) async {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        pdfError = nil
        defer { isGeneratingPDF = false }
        do {
            let url = try await printService.generatePDF(invoice: inv)
            pdfURL = url
            showSharePDF = true
        } catch {
            pdfError = error.localizedDescription
            AppLog.ui.error("Invoice PDF generation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - §7.2 AirPrint action

    @MainActor
    private func generateAndPrint(_ inv: InvoiceDetail) async {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        pdfError = nil
        defer { isGeneratingPDF = false }
        do {
            let url = try await printService.generatePDF(invoice: inv)
            await presentAirPrint(pdfURL: url)
        } catch {
            pdfError = error.localizedDescription
            AppLog.ui.error("Invoice AirPrint failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func presentAirPrint(pdfURL: URL) async {
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Invoice"
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdfURL
        controller.present(animated: true, completionHandler: nil)
    }

    // MARK: - §7.2 Clone invoice action

    @MainActor
    private func cloneInvoice(_ inv: InvoiceDetail) async {
        isCloning = true
        cloneError = nil
        defer { isCloning = false }
        do {
            let cloned = try await api.cloneInvoice(id: inv.id)
            clonedInvoiceId = cloned.id
        } catch {
            cloneError = error.localizedDescription
            AppLog.ui.error("Invoice clone failed: \(error.localizedDescription, privacy: .public)")
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
                    HeaderCard(invoice: inv, api: api, onNavigateToCustomer: onNavigateToCustomer)
                    if let items = inv.lineItems, !items.isEmpty {
                        LineItemsCard(items: items)
                    }
                    // §7.2 Totals panel — subtotal / discount / tax / total / paid / balance due
                    TotalsCard(invoice: inv)
                    if let notes = inv.notes, !notes.isEmpty {
                        NotesCard(text: notes)
                    }
                    // §7.2 Deposit invoices linked
                    DepositInvoicesCard(
                        api: api,
                        parentInvoiceId: inv.id,
                        onTapDeposit: { depositId in depositDrillId = depositId }
                    )
                    // §7.7 Payment history section
                    InvoicePaymentHistoryView(entries: buildPaymentHistory(from: inv))
                    // §7.2 Timeline — every status change, payment, note, send
                    let timelineEvents = buildInvoiceTimeline(from: inv)
                    if !timelineEvents.isEmpty {
                        InvoiceTimelineView(events: timelineEvents)
                    }
                    // §7.9 Installment schedule — shown when a payment plan exists
                    if let plan = installmentPlan {
                        InstallmentScheduleView(plan: plan)
                    }
                }
                .padding(BrandSpacing.base)
            }
            // §7.2 Deposit invoice detail drill-through
            .sheet(
                isPresented: Binding(
                    get: { depositDrillId != nil },
                    set: { if !$0 { depositDrillId = nil } }
                )
            ) {
                if let depId = depositDrillId {
                    NavigationStack {
                        InvoiceDetailView(repo: repo, invoiceId: depId, api: api)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { depositDrillId = nil }
                                }
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Sections

private struct HeaderCard: View {
    let invoice: InvoiceDetail
    /// §7.2+ Portal link copy — requires APIClient for GET /customers/:id/portal-link
    let api: APIClient
    /// §7 Customer card link callback — nil hides the chevron.
    var onNavigateToCustomer: ((Int64) -> Void)?

    @State private var didCopyLink = false
    // §7.2+ Customer portal link copy state
    @State private var didCopyPortalLink = false
    @State private var isFetchingPortalLink = false
    @State private var portalLinkError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // §7.2 Invoice # with textSelection + copy button
            HStack(alignment: .firstTextBaseline) {
                Text(invoice.orderId ?? "INV-?")
                    .font(.brandMono(size: 17))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .accessibilityLabel("Invoice number \(invoice.orderId ?? "unknown")")
                Button {
                    UIPasteboard.general.string = invoice.orderId ?? ""
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy invoice number \(invoice.orderId ?? "")")
                .accessibilityHint("Copies the invoice number to the clipboard")
                Spacer()
                StatusBadge(status: invoice.status)
            }

            // §7 Customer card link — tapping navigates to customer detail.
            if let custId = invoice.customerId, let navigate = onNavigateToCustomer {
                Button {
                    navigate(custId)
                } label: {
                    HStack(spacing: BrandSpacing.xs) {
                        Text(invoice.customerDisplayName)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customer: \(invoice.customerDisplayName)")
                .accessibilityHint("Opens customer detail")
            } else {
                Text(invoice.customerDisplayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }

            // §7.2 Balance-due chip
            if let due = invoice.amountDue, due > 0 {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.bizarreError)
                        .accessibilityHidden(true)
                    Text("Balance due \(formatMoney(due))")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreError.opacity(0.12), in: Capsule())
                .accessibilityLabel("Balance due \(formatMoney(due))")
            }

            // §7.2 Customer card — phone + email with quick-actions
            if let phone = invoice.customerPhone, !phone.isEmpty {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "phone").foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(PhoneFormatter.format(phone))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    Spacer()
                    // Quick-action: dial
                    if let url = URL(string: "tel:\(phone.filter { $0.isNumber })") {
                        Link(destination: url) {
                            Image(systemName: "phone.circle.fill")
                                .foregroundStyle(.bizarreOrange)
                                .font(.system(size: 22))
                        }
                        .accessibilityLabel("Call \(PhoneFormatter.format(phone))")
                    }
                }
            }
            if let email = invoice.customerEmail, !email.isEmpty {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "envelope").foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(email)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    Spacer()
                    // Quick-action: compose email
                    if let url = URL(string: "mailto:\(email)") {
                        Link(destination: url) {
                            Image(systemName: "envelope.circle.fill")
                                .foregroundStyle(.bizarreOrange)
                                .font(.system(size: 22))
                        }
                        .accessibilityLabel("Email \(email)")
                    }
                }
            }

            HStack(alignment: .top) {
                if let created = invoice.createdAt {
                    DateTile(label: "Issued", value: String(created.prefix(10)))
                }
                // §7 Due-date badge with color states: overdue=red, ≤3d=amber, ok=muted.
                if let due = invoice.dueOn, !due.isEmpty {
                    DueDateBadge(dueOn: String(due.prefix(10)), status: invoice.status)
                }
            }
            .padding(.top, BrandSpacing.xs)

            // §7 Share-link button — copies the customer-facing payment URL to the clipboard.
            if let orderId = invoice.orderId, !orderId.isEmpty {
                let payURL = "https://pay.bizarrecrm.com/\(orderId)"
                Button {
                    UIPasteboard.general.string = payURL
                    didCopyLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopyLink = false }
                } label: {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: didCopyLink ? "checkmark.circle.fill" : "link")
                            .foregroundStyle(didCopyLink ? .bizarreSuccess : .bizarreOrange)
                            .font(.system(size: 15))
                        Text(didCopyLink ? "Link copied!" : "Copy payment link")
                            .font(.brandLabelSmall())
                            .foregroundStyle(didCopyLink ? .bizarreSuccess : .bizarreOrange)
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: didCopyLink)
                .accessibilityLabel(didCopyLink ? "Payment link copied to clipboard" : "Copy payment link")
                .accessibilityHint("Copies the customer payment URL to the clipboard")
            }

            // §7.2+ Customer portal magic-link copy — generates a single-use login URL
            // for the customer self-service portal via GET /customers/:id/portal-link.
            if let custId = invoice.customerId {
                Button {
                    guard !isFetchingPortalLink else { return }
                    Task {
                        isFetchingPortalLink = true
                        defer { isFetchingPortalLink = false }
                        do {
                            let resp = try await api.customerPortalLink(customerId: custId)
                            UIPasteboard.general.string = resp.url
                            withAnimation(.easeInOut(duration: 0.2)) { didCopyPortalLink = true }
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeInOut(duration: 0.2)) { didCopyPortalLink = false }
                        } catch {
                            portalLinkError = error.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: BrandSpacing.xs) {
                        if isFetchingPortalLink {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: didCopyPortalLink ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                                .foregroundStyle(didCopyPortalLink ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                                .font(.system(size: 15))
                        }
                        Text(didCopyPortalLink ? "Portal link copied!" : "Copy portal link")
                            .font(.brandLabelSmall())
                            .foregroundStyle(didCopyPortalLink ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: didCopyPortalLink)
                .accessibilityLabel(didCopyPortalLink ? "Customer portal link copied" : "Copy customer portal link")
                .accessibilityHint("Generates a one-time login link for the customer self-service portal")
                .alert("Couldn't generate portal link", isPresented: Binding(
                    get: { portalLinkError != nil },
                    set: { if !$0 { portalLinkError = nil } }
                )) {
                    Button("OK") { portalLinkError = nil }
                } message: {
                    if let e = portalLinkError { Text(e) }
                }
            }
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

// §7 Due-date badge — color-coded by urgency.
// overdue (past due date and not fully paid) → red
// due within 3 days → amber
// otherwise → muted (normal)
private struct DueDateBadge: View {
    let dueOn: String   // "YYYY-MM-DD"
    let status: String?

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var urgency: Urgency {
        let s = (status ?? "").lowercased()
        // Void / paid invoices never show urgency coloring.
        guard s != "paid" && s != "void" else { return .normal }
        guard let date = Self.isoDay.date(from: dueOn) else { return .normal }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return .overdue }
        if days <= 3 { return .soon }
        return .normal
    }

    enum Urgency { case overdue, soon, normal }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Due")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.xxs) {
                if urgency != .normal {
                    Image(systemName: urgency == .overdue ? "exclamationmark.circle.fill" : "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(badgeColor)
                        .accessibilityHidden(true)
                }
                Text(dueOn)
                    .font(.brandBodyMedium())
                    .foregroundStyle(badgeColor)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(a11yLabel)
    }

    private var badgeColor: Color {
        switch urgency {
        case .overdue: return .bizarreError
        case .soon:    return .bizarreWarning
        case .normal:  return .bizarreOnSurface
        }
    }

    private var a11yLabel: String {
        switch urgency {
        case .overdue: return "Due \(dueOn), overdue"
        case .soon:    return "Due \(dueOn), due soon"
        case .normal:  return "Due \(dueOn)"
        }
    }
}

private struct StatusBadge: View {
    let status: String?

    var body: some View {
        let kind = (status ?? "").lowercased()
        let colors = colors(for: kind)
        return Text(status?.capitalized ?? "—")
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(colors.fg)
            .background(colors.bg, in: Capsule())
            .accessibilityLabel("Status: \(status?.capitalized ?? "Unknown")")
    }

    private func colors(for kind: String) -> (bg: Color, fg: Color) {
        switch kind {
        case "paid":    return (.bizarreSuccess, .black)
        case "partial": return (.bizarreWarning, .black)
        case "unpaid":  return (.bizarreError, .white)
        case "overdue": return (.bizarreError, .white)
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
                    // §7.2 Tax per line
                    if let tax = item.taxAmount, tax > 0 {
                        HStack {
                            Text("Tax")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(formatMoney(tax))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tax: \(formatMoney(tax))")
                    }
                }
                .padding(.vertical, BrandSpacing.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(lineItemA11yLabel(item))
            }
        }
        .cardBackground()
    }

    private func formatQty(_ v: Double) -> String {
        if v.rounded() == v { return String(Int(v)) }
        return String(format: "%.2f", v)
    }

    private func lineItemA11yLabel(_ item: InvoiceDetail.LineItem) -> String {
        var parts: [String] = [item.displayName]
        if let qty = item.quantity {
            parts.append("quantity \(formatQty(qty))")
        }
        if let price = item.unitPrice {
            parts.append("at \(formatMoney(price)) each")
        }
        parts.append("total \(formatMoney(item.total ?? 0))")
        if let tax = item.taxAmount, tax > 0 {
            parts.append("tax \(formatMoney(tax))")
        }
        return parts.joined(separator: ", ")
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

// MARK: - §7.2 ShareSheet shim

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
