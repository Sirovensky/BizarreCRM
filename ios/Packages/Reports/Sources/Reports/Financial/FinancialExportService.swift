import Foundation

// MARK: - FinancialExportService

/// Produces CSV and PDF representations of financial dashboard data for accountant hand-off.
/// Reuses `CSVComposer` (DataExport Phase 8 pattern) inline to avoid a cross-package dependency.
public enum FinancialExportService {

    // MARK: - CSV Export

    /// CSV with P&L, cash flow, and aged receivables sections.
    public static func exportCSV(data: FinancialDashboardData, period: String) -> String {
        var sections: [String] = []

        // P&L section
        sections.append("P&L Summary — \(period)")
        sections.append(csvRow(["Revenue", centsToDollars(data.pnl.revenueCents)]))
        sections.append(csvRow(["COGS", centsToDollars(data.pnl.cogsCents)]))
        sections.append(csvRow(["Gross Profit", centsToDollars(data.pnl.grossProfitCents)]))
        sections.append(csvRow(["Expenses", centsToDollars(data.pnl.expensesCents)]))
        sections.append(csvRow(["Net Income", centsToDollars(data.pnl.netCents)]))
        sections.append(csvRow(["Gross Margin %", String(format: "%.1f%%", data.pnl.grossMarginPct * 100)]))
        sections.append(csvRow(["Net Margin %", String(format: "%.1f%%", data.pnl.netMarginPct * 100)]))
        sections.append("")

        // Cash flow section
        sections.append("Cash Flow")
        sections.append(csvRow(["Period", "Inflows", "Outflows", "Net"]))
        for point in data.cashFlow {
            sections.append(csvRow([
                point.id,
                centsToDollars(point.inflowCents),
                centsToDollars(point.outflowCents),
                centsToDollars(point.netCents)
            ]))
        }
        sections.append("")

        // Aged receivables
        sections.append("Aged Receivables")
        sections.append(csvRow(["Bucket", "Total", "Invoice Count"]))
        for bucket in data.agedReceivables.buckets {
            sections.append(csvRow([
                bucket.label,
                centsToDollars(bucket.totalCents),
                String(bucket.invoiceCount)
            ]))
        }
        sections.append("")

        // Top customers
        sections.append("Top Customers by Revenue")
        sections.append(csvRow(["Customer", "Revenue"]))
        for c in data.topCustomers {
            sections.append(csvRow([c.name, centsToDollars(c.revenueCents)]))
        }
        sections.append("")

        // Top SKUs
        sections.append("Top SKUs by Margin")
        sections.append(csvRow(["SKU", "Name", "Margin", "Margin %"]))
        for sku in data.topSkus {
            sections.append(csvRow([
                sku.sku,
                sku.name,
                centsToDollars(sku.marginCents),
                String(format: "%.1f%%", sku.marginPct * 100)
            ]))
        }

        return sections.joined(separator: "\r\n")
    }

    // MARK: - Tax Year CSV

    public static func exportTaxYearCSV(data: TaxYearData) -> String {
        var sections: [String] = []
        sections.append("Tax Year \(data.year) Report")
        sections.append("")

        sections.append("Revenue by Month")
        sections.append(csvRow(["Month", "Revenue"]))
        for (month, cents) in data.revenueByMonth {
            sections.append(csvRow([month, centsToDollars(cents)]))
        }
        sections.append("")

        sections.append("Key Totals")
        sections.append(csvRow(["Sales Tax Collected", centsToDollars(data.salesTaxCollectedCents)]))
        sections.append(csvRow(["Total COGS", centsToDollars(data.totalCOGSCents)]))
        sections.append("")

        sections.append("Expenses by Category")
        sections.append(csvRow(["Category", "Amount"]))
        for (category, cents) in data.expensesByCategory {
            sections.append(csvRow([category, centsToDollars(cents)]))
        }

        return sections.joined(separator: "\r\n")
    }

    // MARK: - Private helpers

    private static func csvRow(_ fields: [String]) -> String {
        fields.map(escapeCSV).joined(separator: ",")
    }

    private static func escapeCSV(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\r")
            || value.contains("\n") || value.contains("\"")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func centsToDollars(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "\(cents)"
    }
}
