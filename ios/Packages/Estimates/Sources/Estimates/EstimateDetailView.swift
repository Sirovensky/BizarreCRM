import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateDetailView (§8.2)
//
// Detail view for a single estimate.
// §8.2: header (estimate # + status + valid-until), line items + totals,
//   Send (SMS/email), Approve (staff-assisted signature), Reject (reason required),
//   Convert to ticket, Convert to invoice, Versioning, Customer-facing PDF preview.
//
// iPhone: vertical scroll + action menu in toolbar.
// iPad: main scroll + actions sidebar (300pt).

/// Detail view for a single estimate.
/// §8.2: header, line items, totals, approve/reject actions, convert-to-ticket.
/// §8.4: manual expire action (marks estimate as expired via PUT /estimates/:id).
/// iPhone: vertical scroll + bottom-sheet actions.
/// iPad: multi-column layout with actions sidebar.
public struct EstimateDetailView: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void
    private let onInvoiceCreated: @MainActor (Int64) -> Void

    // §8.2 sheet states
    @State private var showConvertSheet: Bool = false
    @State private var showExpireConfirm: Bool = false
    @State private var isExpiring: Bool = false
    @State private var expireErrorMessage: String?
    // §8.2: Approve / Reject / Convert-to-invoice / Versioning
    @State private var showApproveSheet: Bool = false
    @State private var showRejectSheet: Bool = false
    @State private var showConvertToInvoiceSheet: Bool = false
    @State private var showVersioningView: Bool = false
    @State private var showPdfPreview: Bool = false
    #if canImport(UIKit)
    @State private var showSignSheet: Bool = false      // existing sign-url sheet
    @State private var showSendSheet: Bool = false      // §8.2 send
    #endif

    public init(
        estimate: Estimate,
        api: APIClient,
        onTicketCreated: @escaping @MainActor (Int64) -> Void = { _ in },
        onInvoiceCreated: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        self.estimate = estimate
        self.api = api
        self.onTicketCreated = onTicketCreated
        self.onInvoiceCreated = onInvoiceCreated
    }

    public var body: some View {
        if Platform.isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    versionWarningBanner
                    headerCard
                    lineItemsCard
                    totalsCard
                    if let reason = estimate.rejectionReason, !reason.isEmpty {
                        rejectionCard(reason)
                    }
                }
                .padding(BrandSpacing.lg)
            }
        }
        .navigationTitle(estimate.orderId ?? "Estimate")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { compactToolbar }
        .sheet(isPresented: $showConvertSheet) { convertSheet }
        .sheet(isPresented: $showApproveSheet) { approveSheet }
        .sheet(isPresented: $showRejectSheet) { rejectSheet }
        .sheet(isPresented: $showConvertToInvoiceSheet) { convertToInvoiceSheet }
        .navigationDestination(isPresented: $showVersioningView) {
            EstimateVersioningView(estimate: estimate, api: api)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showSignSheet) { signSheet }
        .sheet(isPresented: $showSendSheet) { sendSheet }
        .sheet(isPresented: $showApproveSheet) { approveSheet }
        .sheet(isPresented: $showRejectSheet) { rejectSheet }
        #endif
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Main scroll area
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        versionWarningBanner
                        headerCard
                        lineItemsCard
                        if let reason = estimate.rejectionReason, !reason.isEmpty {
                            rejectionCard(reason)
                        }
                    }
                    .padding(BrandSpacing.xl)
                }
            }

            Divider()

            // Actions sidebar (iPad exclusive)
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    totalsCard
                    actionsCard
                }
                .padding(BrandSpacing.xl)
            }
            .frame(width: 300)
            .background(Color.bizarreSurface1)
        }
        .navigationTitle(estimate.orderId ?? "Estimate")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ipadToolbar }
        .sheet(isPresented: $showConvertSheet) { convertSheet }
        .sheet(isPresented: $showApproveSheet) { approveSheet }
        .sheet(isPresented: $showRejectSheet) { rejectSheet }
        .sheet(isPresented: $showConvertToInvoiceSheet) { convertToInvoiceSheet }
        .navigationDestination(isPresented: $showVersioningView) {
            EstimateVersioningView(estimate: estimate, api: api)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showSignSheet) { signSheet }
        .sheet(isPresented: $showSendSheet) { sendSheet }
        .sheet(isPresented: $showApproveSheet) { approveSheet }
        .sheet(isPresented: $showRejectSheet) { rejectSheet }
        #endif
    }

    // MARK: - §8 Version warning banner

    /// Shows an amber warning when the customer approved an earlier version
    /// but staff has since edited to a newer draft.
    /// Example: customer approved v2, current version is v3 → "Customer approved v2; resend?"
    @ViewBuilder
    private var versionWarningBanner: some View {
        if let approved = estimate.approvedVersionNumber,
           let current = estimate.versionNumber,
           current > approved {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Customer approved v\(approved)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Estimate was edited to v\(current). Resend for re-approval?")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                #if canImport(UIKit)
                Button("Resend") { showSendSheet = true }
                    .font(.brandLabelMedium())
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .accessibilityLabel("Resend estimate to customer for re-approval")
                #endif
            }
            .padding(BrandSpacing.md)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Customer approved version \(approved). Estimate has been edited to version \(current). Consider resending.")
        }
    }

    // MARK: - Header card (§8.2)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(estimate.orderId ?? "EST-?")
                        .font(.brandMono(size: 18))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                        .accessibilityLabel("Order ID: \(estimate.orderId ?? "EST-?")")
                    if let vn = estimate.versionNumber {
                        Text("Version \(vn)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                statusBadge
            }

            Text(estimate.customerName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)

            if let total = estimate.total {
                Text(formatMoney(total))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel("Total: \(formatMoney(total))")
            }

            if let until = estimate.validUntil, !until.isEmpty {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Valid until \(String(until.prefix(10)))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Valid until \(String(until.prefix(10)))")
            }

            if let sentAt = estimate.sentAt, !sentAt.isEmpty {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "paperplane")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Sent \(String(sentAt.prefix(10)))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sent on \(String(sentAt.prefix(10)))")
            }

            if let notes = estimate.notes, !notes.isEmpty {
                Text(notes)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.top, BrandSpacing.xs)
            }
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        if let status = estimate.status, !status.isEmpty {
            Text(status.capitalized)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .foregroundStyle(statusForeground(status))
                .background(statusBackground(status), in: Capsule())
                .accessibilityLabel("Status: \(status.capitalized)")
        }
    }

    private func statusForeground(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved": return .green
        case "rejected", "expired": return .bizarreError
        case "converted": return .bizarreOrange
        case "sent": return .blue
        default: return .bizarreOnSurface
        }
    }

    private func statusBackground(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved": return Color.green.opacity(0.15)
        case "rejected", "expired": return Color.bizarreError.opacity(0.15)
        case "converted": return Color.bizarreOrange.opacity(0.15)
        case "sent": return Color.blue.opacity(0.15)
        default: return Color.bizarreSurface2
        }
    }

    // MARK: - Rejection card

    private func rejectionCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label("Rejected", systemImage: "xmark.circle.fill")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(reason)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rejected. Reason: \(reason)")
    }

    // MARK: - Line items card

    @ViewBuilder
    private var lineItemsCard: some View {
        if let items = estimate.lineItems, !items.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                Text("Line Items")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                Divider()

                ForEach(items) { item in
                    lineItemRow(item)
                    if item.id != items.last?.id { Divider() }
                }
            }
            .padding(BrandSpacing.lg)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    private func lineItemRow(_ item: EstimateLineItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.description ?? item.itemName ?? "Item")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let qty = item.quantity, let price = item.unitPrice {
                    Text("\(qty) × \(formatMoney(price))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let sku = item.itemSku, !sku.isEmpty {
                    Text("SKU: \(sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                if let total = item.total {
                    Text(formatMoney(total))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                if let tax = item.taxAmount, tax > 0 {
                    Text("+ \(formatMoney(tax)) tax")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lineItemA11y(item))
    }

    private func lineItemA11y(_ item: EstimateLineItem) -> String {
        var parts: [String] = []
        parts.append(item.description ?? item.itemName ?? "Item")
        if let qty = item.quantity, let price = item.unitPrice {
            parts.append("\(qty) at \(formatMoney(price)) each")
        }
        if let total = item.total { parts.append("Total: \(formatMoney(total))") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Totals card

    private var totalsCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let sub = estimate.subtotal {
                totalsRow("Subtotal", formatMoney(sub))
            }
            if let disc = estimate.discount, disc > 0 {
                totalsRow("Discount", "−\(formatMoney(disc))")
            }
            if let tax = estimate.totalTax, tax > 0 {
                totalsRow("Tax", formatMoney(tax))
            }
            if estimate.subtotal != nil || estimate.discount != nil {
                Divider()
            }
            HStack {
                Text("Total")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(estimate.total ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total: \(formatMoney(estimate.total ?? 0))")
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func totalsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - iPad actions sidebar card

    private var actionsCard: some View {
        let status = estimate.status ?? ""
        let isConverted = (status == "converted")
        let isSigned   = (status == "signed")
        let isApproved = (status == "approved")
        let isRejected = (status == "rejected")

        return VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Actions")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            let status = estimate.status ?? ""
            let isConverted = (status == "converted")
            let isSigned = (status == "signed")
            let isAlreadyExpired = (status == "expired")

            // §8.2: Approve action
            let isApproved = (status == "approved")
            let isRejected = (status == "rejected")
            Button {
                showApproveSheet = true
            } label: {
                Label(isApproved ? "Approved" : "Approve",
                      systemImage: isApproved ? "checkmark.seal.fill" : "checkmark.seal")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(isApproved ? .green : .bizarreOrange)
            .disabled(isApproved || isConverted || isAlreadyExpired)
            .accessibilityLabel(isApproved ? "Estimate already approved" : "Approve this estimate")
            .keyboardShortcut("a", modifiers: [.command, .shift])

            // §8.2: Reject action
            Button(role: .destructive) {
                showRejectSheet = true
            } label: {
                Label(isRejected ? "Rejected" : "Reject",
                      systemImage: isRejected ? "xmark.seal.fill" : "xmark.seal")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isRejected || isConverted || isAlreadyExpired)
            .accessibilityLabel(isRejected ? "Estimate already rejected" : "Reject this estimate")

            Divider()

            // §8.2 Approve
            Button { showApproveSheet = true } label: {
                Label("Approve (Signature)", systemImage: "signature")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isApproved || isConverted || isRejected)
            .accessibilityLabel(isApproved ? "Already approved" : "Approve with customer signature")
            .keyboardShortcut("a", modifiers: [.command, .option])

            // §8.2 Reject
            Button { showRejectSheet = true } label: {
                Label("Reject", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreError)
            .disabled(isRejected || isConverted || isApproved)
            .accessibilityLabel(isRejected ? "Already rejected" : "Reject this estimate with a reason")

            // Convert to ticket (existing)
            Button { showConvertSheet = true } label: {
                Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isConverted)
            .accessibilityLabel(isConverted ? "Already converted to ticket" : "Convert estimate to a service ticket")
            .keyboardShortcut("k", modifiers: [.command, .shift])

            // §8.2: Convert to invoice
            Button {
                showConvertToInvoiceSheet = true
            } label: {
                Label("Convert to Invoice", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isConverted)
            .accessibilityLabel(isConverted ? "Already converted" : "Convert estimate to an invoice")
            .keyboardShortcut("i", modifiers: [.command, .shift])

            // §8.2: Version history
            Button {
                showVersioningView = true
            } label: {
                Label("Version History", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("View estimate version history")

            #if canImport(UIKit)
            Button {
                Task { await convertToInvoice() }
            } label: {
                Label("Convert to Invoice", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isConverted)
            .accessibilityLabel(isConverted ? "Already converted" : "Convert estimate to an invoice")
            .keyboardShortcut("i", modifiers: [.command, .option])

            // §8.2 Versions
            Button { showVersioningView = true } label: {
                Label("Version History", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("View all versions of this estimate")
            .keyboardShortcut("v", modifiers: [.command, .option])

            // §8.2 PDF preview
            Button { showPdfPreview = true } label: {
                Label("Customer Preview", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Preview what the customer sees")

            // Existing sign-url sheet
            #if canImport(UIKit)
            Button { showSignSheet = true } label: {
                Label(isSigned ? "Already Signed" : "Send for E-Signature",
                      systemImage: isSigned ? "checkmark.seal.fill" : "pencil.and.signature")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isSigned)
            .accessibilityLabel(isSigned ? "Estimate already signed by customer" : "Generate and share signature link")
            .keyboardShortcut("g", modifiers: [.command, .shift])
            #endif

            // §8.4 Manual expire action
            if !isAlreadyExpired && !isConverted {
                Button(role: .destructive) {
                    showExpireConfirm = true
                } label: {
                    Label(isExpiring ? "Expiring…" : "Expire Estimate",
                          systemImage: "clock.badge.xmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(isExpiring)
                .accessibilityLabel("Mark this estimate as expired")
                .confirmationDialog("Expire this estimate?",
                                    isPresented: $showExpireConfirm,
                                    titleVisibility: .visible) {
                    Button("Expire", role: .destructive) {
                        Task { await manualExpire() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The estimate will be marked as expired and can no longer be approved.")
                }
            }

            if let errMsg = expireErrorMessage {
                Text(errMsg)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
            #endif
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - §8.4 Manual expire

    private func manualExpire() async {
        isExpiring = true
        expireErrorMessage = nil
        defer { isExpiring = false }
        do {
            // PUT /api/v1/estimates/:id with { status: "expired" }
            struct ExpireBody: Encodable { let status: String }
            _ = try await api.put(
                "/api/v1/estimates/\(estimate.id)",
                body: ExpireBody(status: "expired"),
                as: Estimate.self
            )
            AppLog.ui.info("Estimate \(estimate.id) manually expired.")
        } catch {
            expireErrorMessage = "Could not expire: \(error.localizedDescription)"
            AppLog.ui.error("Manual expire failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var compactToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let status = estimate.status ?? ""
            let isConverted = (status == "converted")
            let isSigned = (status == "signed")
            let isAlreadyExpired = (status == "expired")
            Menu {
                // §8.2: Approve / Reject
                let isApproved = (estimate.status == "approved")
                let isRejected = (estimate.status == "rejected")
                Button {
                    showApproveSheet = true
                } label: {
                    Label(isApproved ? "Approved" : "Approve",
                          systemImage: isApproved ? "checkmark.seal.fill" : "checkmark.seal")
                }
                .disabled(isApproved || isConverted || isAlreadyExpired)

                Button(role: .destructive) {
                    showRejectSheet = true
                } label: {
                    Label(isRejected ? "Rejected" : "Reject",
                          systemImage: isRejected ? "xmark.seal.fill" : "xmark.seal")
                }
                .disabled(isRejected || isConverted || isAlreadyExpired)

                Divider()

                Button {
                    showConvertSheet = true
                } label: {
                    Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
                }
                .disabled(isConverted)

                // §8.2: Convert to invoice
                Button {
                    showConvertToInvoiceSheet = true
                } label: {
                    Label("Convert to Invoice", systemImage: "doc.text")
                }
                .disabled(isConverted)

                // §8.2: Version history
                Button {
                    showVersioningView = true
                } label: {
                    Label("Version History", systemImage: "clock.arrow.circlepath")
                }

                #if canImport(UIKit)
                Divider()

                Button { showSignSheet = true } label: {
                    Label("Send for E-Signature", systemImage: "pencil.and.signature")
                }
                .disabled(isSigned)

                Divider()

                // §8.4 Manual expire
                Button(role: .destructive) {
                    showExpireConfirm = true
                } label: {
                    Label("Expire Now", systemImage: "clock.badge.xmark")
                }
                .disabled(isConverted || (status == "expired"))
                #endif

                // §8.4 Manual expire
                if !isAlreadyExpired && !isConverted {
                    Button(role: .destructive) {
                        showExpireConfirm = true
                    } label: {
                        Label("Expire Estimate", systemImage: "clock.badge.xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Estimate actions")
            .confirmationDialog("Expire this estimate?",
                                isPresented: $showExpireConfirm,
                                titleVisibility: .visible) {
                Button("Expire", role: .destructive) {
                    Task { await manualExpire() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The estimate will be marked as expired.")
            }
        }
    }

    @ToolbarContentBuilder
    private var ipadToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let status = estimate.status ?? ""
            let isConverted = (status == "converted")
            Button { showConvertSheet = true } label: {
                Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
            }
            .disabled(isConverted)
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .accessibilityLabel(isConverted ? "Already converted" : "Convert estimate to a service ticket")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showVersioningView = true } label: {
                Label("Versions", systemImage: "clock.arrow.circlepath")
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            .accessibilityLabel("View version history")
        }
        #if canImport(UIKit)
        ToolbarItem(placement: .primaryAction) {
            let status = estimate.status ?? ""
            let isSigned = (status == "signed")
            Button { showSignSheet = true } label: {
                Label("Send for E-Sig", systemImage: "pencil.and.signature")
            }
            .disabled(isSigned)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityLabel(isSigned ? "Estimate already signed" : "Generate and share signature link")
        }
        #endif
    }

    // MARK: - Sheets

    private var convertSheet: some View {
        EstimateConvertSheet(
            estimate: estimate,
            api: api,
            onSuccess: { ticketId in
                showConvertSheet = false
                onTicketCreated(ticketId)
            }
        )
    }

    // MARK: - §8.2 Approve sheet

    private var approveSheet: some View {
        EstimateApproveSheet(
            estimate: estimate,
            api: api,
            onApproved: { showApproveSheet = false }
        )
    }

    // MARK: - §8.2 Reject sheet

    private var rejectSheet: some View {
        EstimateRejectSheet(
            estimate: estimate,
            api: api,
            onRejected: { showRejectSheet = false }
        )
    }

    // MARK: - §8.2 Convert to invoice sheet

    private var convertToInvoiceSheet: some View {
        EstimateConvertToInvoiceSheet(
            estimate: estimate,
            api: api,
            onSuccess: { _ in showConvertToInvoiceSheet = false }
        )
    }

    // MARK: - Sign sheet

    #if canImport(UIKit)
    private var signSheet: some View {
        EstimateSignSheet(
            estimateId: estimate.id,
            orderId: estimate.orderId ?? "EST-?",
            api: api
        )
    }

    private var sendSheet: some View {
        EstimateSendSheet(
            estimateId: estimate.id,
            orderId: estimate.orderId ?? "EST-?",
            api: api
        )
        .presentationDetents([.medium])
    }

    #endif

    // MARK: - Convert to invoice action

    @MainActor
    private func convertToInvoice() async {
        do {
            let result = try await api.convertEstimateToInvoice(estimateId: estimate.id)
            if let invoiceId = result.invoiceId {
                onInvoiceCreated(invoiceId)
            }
        } catch {
            AppLog.ui.error("Estimate convert-to-invoice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - §8.4 Expire action

    @MainActor
    private func expireEstimate() async {
        isExpiring = true
        defer { isExpiring = false }
        do {
            _ = try await api.expireEstimate(estimateId: estimate.id)
        } catch {
            AppLog.ui.error("Estimate expire failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
