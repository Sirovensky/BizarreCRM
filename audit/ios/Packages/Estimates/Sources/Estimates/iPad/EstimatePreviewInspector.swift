import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimatePreviewInspector
//
// §22 — Column 3 of the three-column layout.
// Shows a rich preview of the selected estimate with:
//   • Header (order ID, customer, status badge, validity)
//   • Inline line-items table with per-item totals
//   • Totals summary (subtotal → discount → tax → total)
//   • Signature status (signed / pending / not sent)
//   • Quick action buttons (Sign, Convert) reusing existing sheets
//
// Liquid Glass only on the inspector toolbar (CLAUDE.md rule).

#if canImport(UIKit)

public struct EstimatePreviewInspector: View {

    public let estimate: Estimate
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void

    @State private var showSignSheet = false
    @State private var showConvertSheet = false

    public init(
        estimate: Estimate,
        api: APIClient,
        onTicketCreated: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        self.estimate = estimate
        self.api = api
        self.onTicketCreated = onTicketCreated
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    headerSection
                    signatureStatusSection
                    lineItemsSection
                    totalsSection
                    actionsSection
                }
                .padding(BrandSpacing.lg)
            }
        }
        .navigationTitle(estimate.orderId ?? "Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { inspectorToolbar }
        .sheet(isPresented: $showSignSheet) {
            EstimateSignSheet(
                estimateId: estimate.id,
                orderId: estimate.orderId ?? "EST-?",
                api: api
            )
        }
        .sheet(isPresented: $showConvertSheet) {
            EstimateConvertSheet(
                estimate: estimate,
                api: api,
                onSuccess: { ticketId in
                    showConvertSheet = false
                    onTicketCreated(ticketId)
                }
            )
        }
    }

    // MARK: - Inspector Toolbar (glass chrome)

    @ToolbarContentBuilder
    private var inspectorToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                signButton
                convertButton
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Estimate actions")
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(estimate.orderId ?? "EST-?")
                        .font(.brandMono(size: 18))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    Text(estimate.customerName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
                Spacer()
                statusBadge
            }

            if let total = estimate.total {
                Text(formatMoney(total))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
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
            }

            if estimate.isExpiring == true, let days = estimate.daysUntilExpiry {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                    Text("Expires in \(days) days")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                }
            }

            if let notes = estimate.notes, !notes.isEmpty {
                Text(notes)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.top, BrandSpacing.xxs)
            }
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Signature Status Section

    private var signatureStatusSection: some View {
        let status = estimate.status?.lowercased() ?? ""
        let isSigned = status == "signed"

        return HStack(spacing: BrandSpacing.md) {
            Image(systemName: isSigned ? "checkmark.seal.fill" : "pencil.and.signature")
                .font(.system(size: 22))
                .foregroundStyle(isSigned ? .green : .bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Signature")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(isSigned ? "Signed by customer" : "Awaiting signature")
                    .font(.brandBodyMedium())
                    .foregroundStyle(isSigned ? .green : .bizarreOnSurface)
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(
            isSigned ? Color.green.opacity(0.08) : Color.bizarreSurface1,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSigned ? "Signature: signed by customer" : "Signature: awaiting customer signature")
    }

    // MARK: - Line Items Section

    @ViewBuilder
    private var lineItemsSection: some View {
        if let items = estimate.lineItems, !items.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                Text("Line Items")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                Divider()

                ForEach(items) { item in
                    lineItemRow(item)
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(BrandSpacing.lg)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    private func lineItemRow(_ item: EstimateLineItem) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.description ?? item.itemName ?? "Item")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                HStack(spacing: BrandSpacing.sm) {
                    if let qty = item.quantity, let price = item.unitPrice {
                        Text("\(qty) × \(formatMoney(price))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let sku = item.itemSku, !sku.isEmpty {
                        Text("SKU: \(sku)")
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
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
        var parts: [String] = [item.description ?? item.itemName ?? "Item"]
        if let qty = item.quantity, let price = item.unitPrice {
            parts.append("\(qty) at \(formatMoney(price)) each")
        }
        if let total = item.total { parts.append("Total \(formatMoney(total))") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Totals Section

    private var totalsSection: some View {
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
            if estimate.subtotal != nil || estimate.discount != nil || estimate.totalTax != nil {
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

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            signButton
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .frame(maxWidth: .infinity)

            convertButton
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Reusable action buttons

    @ViewBuilder
    private var signButton: some View {
        let isSigned = estimate.status?.lowercased() == "signed"
        Button {
            showSignSheet = true
        } label: {
            Label(
                isSigned ? "Already Signed" : "Send for Signature",
                systemImage: isSigned ? "checkmark.seal.fill" : "pencil.and.signature"
            )
        }
        .disabled(isSigned)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .accessibilityLabel(isSigned ? "Estimate already signed" : "Send for customer signature")
    }

    @ViewBuilder
    private var convertButton: some View {
        let isConverted = estimate.status?.lowercased() == "converted"
        Button {
            showConvertSheet = true
        } label: {
            Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
        }
        .disabled(isConverted)
        .accessibilityLabel(isConverted ? "Already converted to ticket" : "Convert estimate to a service ticket")
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
        case "approved":            return .green
        case "rejected", "expired": return .bizarreError
        case "converted":           return .bizarreOrange
        default:                    return .bizarreOnSurface
        }
    }

    private func statusBackground(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved":            return Color.green.opacity(0.15)
        case "rejected", "expired": return Color.bizarreError.opacity(0.15)
        case "converted":           return Color.bizarreOrange.opacity(0.15)
        default:                    return Color.bizarreSurface2
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

#endif
