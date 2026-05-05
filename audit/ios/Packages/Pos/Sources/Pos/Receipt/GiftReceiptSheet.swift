#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16 Gift Receipt — post-checkout sheet asking "Print gift receipt too?"
///
/// Presented from `PosPostSaleView` after a successful sale. The customer
/// can ask for a price-hidden gift receipt. On confirmation the view
/// dispatches a `.giftReceipt` print job (placeholder until §17.4 wires
/// the receipt printer).
///
/// Wiring from `PosPostSaleView`:
/// ```swift
/// .sheet(item: $giftReceiptSale) { sale in
///     GiftReceiptSheet(sale: sale) { vm.printGiftReceipt(for: sale) }
/// }
/// ```
public struct GiftReceiptSheet: View {
    public let sale: SaleRecord
    public let onPrint: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(sale: SaleRecord, onPrint: @escaping () -> Void) {
        self.sale    = sale
        self.onPrint = onPrint
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            // Header
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Print Gift Receipt?")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text("The gift receipt hides prices and totals so the recipient doesn't see what was paid.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }

            // Item preview (names + SKUs only)
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                ForEach(sale.lines) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            if let sku = line.sku {
                                Text("SKU: \(sku)")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        Spacer()
                        Text("×\(line.quantity)")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .padding(.vertical, BrandSpacing.xxs)
                }
            }
            .padding(.horizontal, BrandSpacing.xl)

            Spacer()

            // CTAs
            VStack(spacing: BrandSpacing.sm) {
                Button {
                    BrandHaptics.success()
                    onPrint()
                    dismiss()
                } label: {
                    Label("Print Gift Receipt", systemImage: "printer.fill")
                        .font(.brandTitleMedium())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .controlSize(.large)
                .accessibilityIdentifier("giftReceipt.print")

                Button {
                    dismiss()
                } label: {
                    Text("No Thanks")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityIdentifier("giftReceipt.skip")
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.bottom, BrandSpacing.xl)
        }
        .padding(.top, BrandSpacing.xl)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
