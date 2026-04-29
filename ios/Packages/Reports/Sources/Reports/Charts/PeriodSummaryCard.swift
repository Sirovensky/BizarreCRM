import SwiftUI
import Charts
import DesignSystem

// MARK: - PeriodSummaryCard
//
// §91.2-2: Period Summary card — 4 labelled columns (Sales / Tickets / Customers / Avg).
// §91.2-3: Use compact currency ($0K not $0.00) so values never truncate.
//
// Wired to SalesTotals from GET /api/v1/reports/sales `data.totals`.

public struct PeriodSummaryCard: View {
    public let totals: SalesTotals
    /// Average ticket value in dollars (from AvgTicketValue.currentDollars). Optional.
    public let avgTicketDollars: Double?

    public init(totals: SalesTotals, avgTicketDollars: Double? = nil) {
        self.totals = totals
        self.avgTicketDollars = avgTicketDollars
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)
                Text("Period Summary")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }

            Divider()

            // §91.2-2: 4 clearly-labelled columns with equal width.
            // §91.2-3: compact currency (no cents, abbreviate to K when ≥ $1 000).
            HStack(spacing: 0) {
                summaryColumn(
                    label: "Sales",
                    value: compactCurrency(totals.totalRevenue),
                    icon: "dollarsign.circle",
                    color: .bizarreOrange
                )
                columnDivider
                summaryColumn(
                    label: "Tickets",
                    value: "\(totals.totalInvoices)",
                    icon: "ticket",
                    color: .bizarreTeal
                )
                columnDivider
                summaryColumn(
                    label: "Customers",
                    value: "\(totals.uniqueCustomers)",
                    icon: "person.2",
                    color: .bizarreSuccess
                )
                columnDivider
                summaryColumn(
                    label: "Avg",
                    value: compactCurrency(avgTicketDollars ?? avgFromTotals),
                    icon: "chart.bar",
                    color: .bizarreOnSurfaceMuted
                )
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Column view

    private func summaryColumn(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: BrandSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color.opacity(0.8))
                .accessibilityHidden(true)
            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(color)
                // §91.2-3: allow shrinking but never truncate — compact format prevents overflow.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var columnDivider: some View {
        Divider()
            .frame(height: 44)
            .accessibilityHidden(true)
    }

    // MARK: - Helpers

    /// Compact currency: no cents; abbreviate thousands.
    /// $0 → "$0", $999 → "$999", $1 500 → "$1.5K", $15 000 → "$15K".
    private func compactCurrency(_ dollars: Double) -> String {
        if dollars >= 1_000 {
            let k = dollars / 1_000.0
            // Show one decimal only when < 10K for clarity.
            if k < 10 {
                return String(format: "$%.1fK", k)
            } else {
                return String(format: "$%.0fK", k)
            }
        }
        return String(format: "$%.0f", dollars)
    }

    /// Derive avg ticket from totals when no explicit value provided.
    private var avgFromTotals: Double {
        guard totals.totalInvoices > 0 else { return 0 }
        return totals.totalRevenue / Double(totals.totalInvoices)
    }

    private var accessibilitySummary: String {
        let avg = avgTicketDollars ?? avgFromTotals
        return "Period Summary: Sales \(compactCurrency(totals.totalRevenue)), "
             + "Tickets \(totals.totalInvoices), "
             + "Customers \(totals.uniqueCustomers), "
             + "Average \(compactCurrency(avg))"
    }
}
