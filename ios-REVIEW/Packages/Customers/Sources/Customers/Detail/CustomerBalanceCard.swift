#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.2 Balance / Credit card

/// Shows the sum of unpaid invoices + store credit balance for a customer.
/// Calls `GET /api/v1/refunds/credits/:customerId` for store credit;
/// store credit application CTA fires a sheet (Phase 4+).
public struct CustomerBalanceCard: View {
    let customerId: Int64
    let api: APIClient
    @State private var creditBalance: CustomerCreditBalance?
    @State private var isLoading = false

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Balance & Credit")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                HStack(spacing: BrandSpacing.md) {
                    balanceTile
                    creditTile
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await loadCredit() }
    }

    // MARK: Sub-tiles

    private var balanceTile: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("Unpaid").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            // Unpaid total requires invoice list — surfaced as "see Invoices tab" for now.
            Text("See Invoices")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
    }

    private var creditTile: some View {
        let cents = creditBalance?.balanceCents ?? 0
        let formatted = centsToString(cents)
        return VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("Store Credit").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(formatted)
                .font(.brandTitleMedium())
                .foregroundStyle(cents > 0 ? .bizarreSuccess : .bizarreOnSurface)
                .monospacedDigit()
            if cents > 0 {
                Text("Apply credit")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityLabel("Apply store credit")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Store credit: \(formatted)")
    }

    // MARK: Helpers

    private func loadCredit() async {
        isLoading = true
        defer { isLoading = false }
        creditBalance = try? await api.customerCreditBalance(customerId: customerId)
    }

    private func centsToString(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }
}
#endif
