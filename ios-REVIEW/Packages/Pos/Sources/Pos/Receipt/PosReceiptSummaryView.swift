#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.7 — Receipt summary screen shown after a cash (or any completed)
/// sale. Renders a breakdown of all line items, subtotal, tax, tip, fees,
/// discount, total, and tender method.
///
/// This is a read-only summary — printing, email, and SMS are deferred to
/// `PosPostSaleView`. The screen is presented modally from `PosPostSaleView`
/// via the "View receipt" button (added when a `PosReceiptRenderer.Payload`
/// is available).
///
/// Layout:
/// - Glass toolbar (navigation chrome, per CLAUDE.md).
/// - Scrollable list of content rows (no glass).
/// - Footer: totals block + tender row.
public struct PosReceiptSummaryView: View {
    public let payload: PosReceiptRenderer.Payload
    @Environment(\.dismiss) private var dismiss

    public init(payload: PosReceiptRenderer.Payload) {
        self.payload = payload
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                scrollContent
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                merchantHeader
                    .padding(.vertical, BrandSpacing.lg)
                    .padding(.horizontal, BrandSpacing.base)

                Divider().background(.bizarreOutline)

                lineItemsSection

                Divider().background(.bizarreOutline)

                totalsSection
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.md)

                if !payload.tenders.isEmpty {
                    Divider().background(.bizarreOutline)
                    tendersSection
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.md)
                }

                footerNote
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.lg)
            }
        }
    }

    // MARK: - Merchant header

    private var merchantHeader: some View {
        VStack(spacing: BrandSpacing.xs) {
            Text(payload.merchant.name)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            if let addr = payload.merchant.address {
                Text(addr)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            if let phone = payload.merchant.phone {
                Text(phone)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(dateString)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let customer = payload.customerName {
                Text("Customer: \(customer)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let order = payload.orderNumber {
                Text("Order # \(order)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pos.receipt.header")
    }

    // MARK: - Line items

    private var lineItemsSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(payload.lines.enumerated()), id: \.offset) { _, line in
                receiptLineRow(line: line)
            }
        }
    }

    private func receiptLineRow(line: PosReceiptRenderer.Payload.Line) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    if let sku = line.sku, !sku.isEmpty {
                        Text("SKU \(sku)")
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Text("\(line.quantity) × \(CartMath.formatCents(line.unitPriceCents))")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
                Spacer(minLength: BrandSpacing.sm)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CartMath.formatCents(line.lineTotalCents))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    if line.discountCents > 0 {
                        Text("-\(CartMath.formatCents(line.discountCents))")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOrange)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lineAccessibilityLabel(line))
    }

    private func lineAccessibilityLabel(_ line: PosReceiptRenderer.Payload.Line) -> String {
        "\(line.name), \(line.quantity) at \(CartMath.formatCents(line.unitPriceCents)) each, total \(CartMath.formatCents(line.lineTotalCents))"
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(spacing: BrandSpacing.xs) {
            if payload.subtotalCents != payload.totalCents {
                totalsRow(label: "Subtotal", cents: payload.subtotalCents)
            }
            if payload.discountCents > 0 {
                totalsRow(label: "Discount", cents: -payload.discountCents, isHighlighted: true)
            }
            if payload.taxCents > 0 {
                totalsRow(label: "Tax", cents: payload.taxCents)
            }
            if payload.tipCents > 0 {
                totalsRow(label: "Tip", cents: payload.tipCents)
            }
            if payload.feesCents > 0 {
                totalsRow(label: "Fees", cents: payload.feesCents)
            }
            Divider().background(.bizarreOutline)
            totalsRow(label: "Total", cents: payload.totalCents, isEmphatic: true)
        }
        .accessibilityIdentifier("pos.receipt.totals")
    }

    @ViewBuilder
    private func totalsRow(label: String, cents: Int, isEmphatic: Bool = false, isHighlighted: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isEmphatic ? .brandTitleMedium() : .brandBodyMedium())
                .foregroundStyle(isEmphatic ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            Spacer()
            let display = cents < 0 ? "-\(CartMath.formatCents(-cents))" : CartMath.formatCents(cents)
            Text(display)
                .font(isEmphatic ? .brandHeadlineMedium() : .brandBodyLarge())
                .foregroundStyle(isHighlighted ? .bizarreOrange : .bizarreOnSurface)
                .monospacedDigit()
        }
    }

    // MARK: - Tenders

    private var tendersSection: some View {
        VStack(spacing: BrandSpacing.xs) {
            Text("Payment")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(payload.tenders.enumerated()), id: \.offset) { _, tender in
                HStack {
                    HStack(spacing: BrandSpacing.xs) {
                        Text(tender.method)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        if let last4 = tender.last4 {
                            Text("••••\(last4)")
                                .font(.brandMono(size: 12))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    Spacer()
                    Text(CartMath.formatCents(tender.amountCents))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityIdentifier("pos.receipt.tenders")
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerNote: some View {
        if let footer = payload.footer, !footer.isEmpty {
            Text(footer)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pos.receipt.footer")
        }
    }

    // MARK: - Helpers

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: payload.date)
    }
}

#Preview {
    PosReceiptSummaryView(
        payload: PosReceiptRenderer.Payload(
            merchant: .init(name: "BizarreCRM Demo", address: "123 Main St", phone: "(555) 867-5309"),
            date: Date(),
            customerName: "Jane Smith",
            orderNumber: "INV-0042",
            lines: [
                .init(name: "iPhone Screen Replacement", sku: "SVC-001", quantity: 1, unitPriceCents: 8999, lineTotalCents: 8999),
                .init(name: "Tempered Glass", sku: "ACC-112", quantity: 2, unitPriceCents: 1299, discountCents: 200, lineTotalCents: 2398),
            ],
            subtotalCents: 11397,
            discountCents: 200,
            feesCents: 0,
            taxCents: 912,
            tipCents: 0,
            totalCents: 12109,
            tenders: [.init(method: "Cash", amountCents: 13000)],
            currencyCode: "USD",
            footer: "Thank you for your business!"
        )
    )
    .preferredColorScheme(.dark)
}
#endif
