import Foundation

// MARK: - OwnerPLCSVExporter
//
// §59 Export-to-CSV copy: produces an RFC-4180 compliant CSV string from
// OwnerPLSummary for sharing via UIActivityViewController.
// Covers: revenue (gross or net per toggle), profit, expenses, AR, tax,
// time-series buckets (with YoY delta where available), top customers, top services.

public enum OwnerPLCSVExporter {

    public static func export(summary: OwnerPLSummary, showNetRevenue: Bool) -> String {
        var rows: [String] = []

        // Header
        rows.append(csvRow(["BizarreCRM — Owner P&L Export"]))
        rows.append(csvRow(["Period", "\(summary.period.from) to \(summary.period.to) (\(summary.period.days) days)"]))
        rows.append("")

        // Summary
        rows.append(csvRow(["Summary", "Amount"]))
        let revenueLabel = showNetRevenue ? "Net Revenue" : "Gross Revenue"
        let revenueCents = showNetRevenue ? summary.revenue.netCents : summary.revenue.grossCents
        rows.append(csvRow([revenueLabel, dollars(revenueCents)]))
        if let pct = summary.yoyRevenuePct {
            rows.append(csvRow(["  YoY Revenue Delta", String(format: "%+.1f%%", pct * 100)]))
        }
        rows.append(csvRow(["COGS (Inventory)", dollars(summary.cogs.inventoryCents)]))
        rows.append(csvRow(["COGS (Labor)", dollars(summary.cogs.laborCents)]))
        rows.append(csvRow(["Gross Profit", dollars(summary.grossProfit.cents)]))
        rows.append(csvRow(["  Gross Margin %", String(format: "%.1f%%", summary.grossProfit.marginPct * 100)]))
        rows.append(csvRow(["Total Expenses", dollars(summary.expenses.totalCents)]))
        rows.append(csvRow(["Net Profit", dollars(summary.netProfit.cents)]))
        rows.append(csvRow(["  Net Margin %", String(format: "%.1f%%", summary.netProfit.marginPct * 100)]))
        if let pct = summary.yoyNetProfitPct {
            rows.append(csvRow(["  YoY Net Profit Delta", String(format: "%+.1f%%", pct * 100)]))
        }
        rows.append(csvRow(["AR Outstanding", dollars(summary.ar.outstandingCents)]))
        rows.append(csvRow(["AR Overdue", dollars(summary.ar.overdueCents)]))
        rows.append(csvRow(["Tax Outstanding", dollars(summary.taxLiability.outstandingCents)]))
        rows.append("")

        // Expenses by category
        if !summary.expenses.byCategory.isEmpty {
            rows.append(csvRow(["Expenses by Category", "Amount"]))
            for row in summary.expenses.byCategory {
                rows.append(csvRow([row.category, dollars(row.cents)]))
            }
            rows.append("")
        }

        // Time series
        if !summary.timeSeries.isEmpty {
            let hasYoY = summary.timeSeries.contains { $0.yoyRevenueDeltaCents != nil }
            var header = ["Period", showNetRevenue ? "Net Revenue" : "Revenue", "Expenses", "Net"]
            if hasYoY { header.append("YoY Revenue Delta") }
            rows.append(csvRow(header))
            for bucket in summary.timeSeries {
                let revenueVal = showNetRevenue
                    ? bucket.revenueCents - bucket.expenseCents
                    : bucket.revenueCents
                var cols = [bucket.bucket, dollars(revenueVal), dollars(bucket.expenseCents), dollars(bucket.netCents)]
                if hasYoY {
                    cols.append(bucket.yoyRevenueDeltaCents.map { dollars($0) } ?? "N/A")
                }
                rows.append(csvRow(cols))
            }
            rows.append("")
        }

        // Top customers
        if !summary.topCustomers.isEmpty {
            rows.append(csvRow(["Top Customers", "Revenue"]))
            for c in summary.topCustomers {
                rows.append(csvRow([c.name.isEmpty ? "Customer #\(c.customerId)" : c.name,
                                    dollars(c.revenueCents)]))
            }
            rows.append("")
        }

        // Top services
        if !summary.topServices.isEmpty {
            rows.append(csvRow(["Top Services", "Revenue", "Count"]))
            for svc in summary.topServices {
                rows.append(csvRow([svc.service, dollars(svc.revenueCents), "\(svc.count)"]))
            }
        }

        return rows.joined(separator: "\r\n")
    }

    // MARK: - Private helpers

    private static func csvRow(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\r")
            || value.contains("\n") || value.contains("\"")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func dollars(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "\(cents)"
    }
}
