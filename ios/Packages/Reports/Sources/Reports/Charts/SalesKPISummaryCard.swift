import SwiftUI
import Core
import Charts
import DesignSystem

// MARK: - SalesKPISummaryCard
//
// §15.2 — Total invoices / revenue / unique customers / period-over-period delta.
// Wired to SalesTotals from GET /api/v1/reports/sales.

public struct SalesKPISummaryCard: View {
    public let totals: SalesTotals

    public init(totals: SalesTotals) {
        self.totals = totals
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Period Summary")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .accessibilityElement(children: .contain)
    }

    // MARK: - iPhone: 2x2 grid

    private var phoneLayout: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: BrandSpacing.md
        ) {
            kpiCell(
                label: "Revenue",
                value: formatCurrency(totals.totalRevenue),
                delta: totals.revenueChangePct,
                icon: "dollarsign.circle.fill",
                tint: .bizarreOrange
            )
            kpiCell(
                label: "Invoices",
                value: "\(totals.totalInvoices)",
                delta: nil,
                icon: "doc.text.fill",
                tint: .bizarrePrimary
            )
            kpiCell(
                label: "Customers",
                value: "\(totals.uniqueCustomers)",
                delta: nil,
                icon: "person.2.fill",
                tint: .bizarreSuccess
            )
            kpiCell(
                label: "Avg Invoice",
                value: totals.totalInvoices > 0
                    ? formatCurrency(totals.totalRevenue / Double(totals.totalInvoices))
                    : "$0",
                delta: nil,
                icon: "chart.bar.fill",
                tint: .bizarreInfo
            )
        }
    }

    // MARK: - iPad: single row of 4

    private var ipadLayout: some View {
        HStack(spacing: BrandSpacing.xl) {
            kpiCell(
                label: "Revenue",
                value: formatCurrency(totals.totalRevenue),
                delta: totals.revenueChangePct,
                icon: "dollarsign.circle.fill",
                tint: .bizarreOrange
            )
            Divider().frame(height: 48)
            kpiCell(
                label: "Invoices",
                value: "\(totals.totalInvoices)",
                delta: nil,
                icon: "doc.text.fill",
                tint: .bizarrePrimary
            )
            Divider().frame(height: 48)
            kpiCell(
                label: "Customers",
                value: "\(totals.uniqueCustomers)",
                delta: nil,
                icon: "person.2.fill",
                tint: .bizarreSuccess
            )
            Divider().frame(height: 48)
            kpiCell(
                label: "Avg Invoice",
                value: totals.totalInvoices > 0
                    ? formatCurrency(totals.totalRevenue / Double(totals.totalInvoices))
                    : "$0",
                delta: nil,
                icon: "chart.bar.fill",
                tint: .bizarreInfo
            )
            Spacer(minLength: 0)
        }
    }

    // MARK: - KPI cell

    @ViewBuilder
    private func kpiCell(
        label: String,
        value: String,
        delta: Double?,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
            if let pct = delta {
                deltaBadge(pct: pct)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(delta.map { d in ", \(String(format: "%.1f", abs(d)))% \(d >= 0 ? "up" : "down")" } ?? "")")
    }

    @ViewBuilder
    private func deltaBadge(pct: Double) -> some View {
        let up = pct >= 0
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(String(format: "%.1f%%", abs(pct)))
                .font(.brandLabelSmall())
        }
        .foregroundStyle(up ? Color.bizarreSuccess : Color.bizarreError)
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value >= 10_000 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
