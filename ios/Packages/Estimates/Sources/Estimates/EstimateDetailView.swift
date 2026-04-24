import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateDetailView

/// Detail view for a single estimate.
/// §8.2: header, line items, totals, approve/reject actions, convert-to-ticket.
/// iPhone: vertical scroll + bottom-sheet actions.
/// iPad: multi-column layout with actions sidebar.
public struct EstimateDetailView: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void

    @State private var showConvertSheet: Bool = false
    #if canImport(UIKit)
    @State private var showSignSheet: Bool = false
    #endif

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
                    headerCard
                    lineItemsCard
                    totalsCard
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
        #if canImport(UIKit)
        .sheet(isPresented: $showSignSheet) { signSheet }
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
                        headerCard
                        lineItemsCard
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
        #if canImport(UIKit)
        .sheet(isPresented: $showSignSheet) { signSheet }
        #endif
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text(estimate.orderId ?? "EST-?")
                    .font(.brandMono(size: 18))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
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
        default: return .bizarreOnSurface
        }
    }

    private func statusBackground(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved": return Color.green.opacity(0.15)
        case "rejected", "expired": return Color.bizarreError.opacity(0.15)
        case "converted": return Color.bizarreOrange.opacity(0.15)
        default: return Color.bizarreSurface2
        }
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
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Actions")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            let status = estimate.status ?? ""
            let isConverted = (status == "converted")
            let isSigned = (status == "signed")

            Button {
                showConvertSheet = true
            } label: {
                Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isConverted)
            .accessibilityLabel(isConverted ? "Already converted to ticket" : "Convert estimate to a service ticket")
            .keyboardShortcut("k", modifiers: [.command, .shift])

            #if canImport(UIKit)
            Button {
                showSignSheet = true
            } label: {
                Label(isSigned ? "Already Signed" : "Send for Signature",
                      systemImage: isSigned ? "checkmark.seal.fill" : "pencil.and.signature")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isSigned)
            .accessibilityLabel(isSigned ? "Estimate already signed by customer" : "Generate a signature link to send to customer")
            .keyboardShortcut("g", modifiers: [.command, .shift])
            #endif
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var compactToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let status = estimate.status ?? ""
            let isConverted = (status == "converted")
            let isSigned = (status == "signed")
            Menu {
                Button {
                    showConvertSheet = true
                } label: {
                    Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
                }
                .disabled(isConverted)

                #if canImport(UIKit)
                Button {
                    showSignSheet = true
                } label: {
                    Label("Send for Signature", systemImage: "pencil.and.signature")
                }
                .disabled(isSigned)
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Estimate actions")
        }
    }

    @ToolbarContentBuilder
    private var ipadToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let status = estimate.status ?? ""
            let isConverted = (status == "converted")
            Button {
                showConvertSheet = true
            } label: {
                Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
            }
            .disabled(isConverted)
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .accessibilityLabel(isConverted ? "Already converted" : "Convert estimate to a service ticket")
        }
        #if canImport(UIKit)
        ToolbarItem(placement: .primaryAction) {
            let status = estimate.status ?? ""
            let isSigned = (status == "signed")
            Button {
                showSignSheet = true
            } label: {
                Label("Send for Signature", systemImage: "pencil.and.signature")
            }
            .disabled(isSigned)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityLabel(isSigned ? "Estimate already signed" : "Generate and share signature link")
        }
        #endif
    }

    // MARK: - Convert sheet

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

    // MARK: - Sign sheet

    #if canImport(UIKit)
    private var signSheet: some View {
        EstimateSignSheet(
            estimateId: estimate.id,
            orderId: estimate.orderId ?? "EST-?",
            api: api
        )
    }
    #endif

    // MARK: - Helpers

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
