import Foundation

// MARK: - ReportCSVService
//
// Generates CSV from in-memory report data for ShareLink.
// CSV is produced client-side from the snapshot already held in
// ReportsViewModel — no additional server round-trip required.
//
// The server also has GET /api/v1/reports/:type/export (with exportReports
// feature flag + step-up TOTP), but that requires additional auth gates
// not suitable for on-demand iOS export. Client-side generation is the
// correct iOS pattern.

public actor ReportCSVService {

    public init() {}

    // MARK: - Revenue CSV

    /// Writes revenue rows to a temp .csv file and returns its URL.
    public func generateRevenueCSV(rows: [RevenuePoint], period: String) async throws -> URL {
        var lines: [String] = ["period,revenue_usd,invoices"]
        for row in rows {
            lines.append("\(csvEscape(row.date)),\(String(format: "%.2f", row.amountDollars)),\(row.saleCount)")
        }
        return try writeTempCSV(name: "revenue-\(period)", content: lines.joined(separator: "\n"))
    }

    // MARK: - Full snapshot CSV (multi-section)

    /// Writes a multi-section CSV covering revenue, tickets, employees, and turnover.
    public func generateSnapshotCSV(report: ReportSnapshot) async throws -> URL {
        var lines: [String] = []

        // ── Revenue ────────────────────────────────────────────────────────────
        lines.append("# Revenue")
        lines.append("period,revenue_usd,invoices")
        for row in report.revenue {
            lines.append("\(csvEscape(row.date)),\(String(format: "%.2f", row.amountDollars)),\(row.saleCount)")
        }

        lines.append("")

        // ── Tickets by status ──────────────────────────────────────────────────
        lines.append("# Tickets by Status")
        lines.append("status,count")
        for pt in report.ticketsByStatus {
            lines.append("\(csvEscape(pt.status)),\(pt.count)")
        }

        lines.append("")

        // ── Top employees ──────────────────────────────────────────────────────
        lines.append("# Top Employees")
        lines.append("name,tickets_closed,revenue_usd,avg_resolution_hours")
        for emp in report.topEmployees {
            lines.append(
                "\(csvEscape(emp.employeeName)),\(emp.ticketsClosed),"
                + "\(String(format: "%.2f", emp.revenueDollars)),"
                + "\(String(format: "%.1f", emp.avgResolutionHours))"
            )
        }

        lines.append("")

        // ── Inventory turnover ─────────────────────────────────────────────────
        lines.append("# Inventory Turnover")
        lines.append("sku,name,turnover_rate,days_on_hand")
        for row in report.inventoryTurnover {
            lines.append(
                "\(csvEscape(row.sku)),\(csvEscape(row.name)),"
                + "\(String(format: "%.2f", row.turnoverRate)),"
                + "\(String(format: "%.0f", row.daysOnHand))"
            )
        }

        lines.append("")

        // ── CSAT / NPS ─────────────────────────────────────────────────────────
        if let csat = report.csatScore {
            lines.append("# CSAT")
            lines.append("score,prev_score,response_count,trend_pct")
            lines.append(
                "\(String(format: "%.1f", csat.current)),"
                + "\(String(format: "%.1f", csat.previous)),"
                + "\(csat.responseCount),"
                + "\(String(format: "%.1f", csat.trendPct))"
            )
            lines.append("")
        }

        if let nps = report.npsScore {
            lines.append("# NPS")
            lines.append("score,prev_score,promoter_pct,detractor_pct,passive_pct")
            lines.append(
                "\(nps.current),\(nps.previous),"
                + "\(String(format: "%.1f", nps.promoterPct)),"
                + "\(String(format: "%.1f", nps.detractorPct)),"
                + "\(String(format: "%.1f", nps.passivePct))"
            )
        }

        let safePeriod = report.period.replacingOccurrences(of: " ", with: "_")
                                      .replacingOccurrences(of: "/", with: "-")
        return try writeTempCSV(name: "report-\(safePeriod)", content: lines.joined(separator: "\n"))
    }

    // MARK: - Owner P&L CSV

    public func generateOwnerPLCSV(summary: OwnerPLSummary) async throws -> URL {
        var lines: [String] = []

        lines.append("# Owner P&L Summary")
        lines.append("period_from,period_to,days")
        lines.append("\(summary.period.from),\(summary.period.to),\(summary.period.days)")
        lines.append("")

        lines.append("# Revenue")
        lines.append("gross_usd,net_usd,refunds_usd,discounts_usd")
        lines.append(
            "\(usd(summary.revenue.grossCents)),"
            + "\(usd(summary.revenue.netCents)),"
            + "\(usd(summary.revenue.refundsCents)),"
            + "\(usd(summary.revenue.discountsCents))"
        )
        lines.append("")

        lines.append("# Profit")
        lines.append("gross_profit_usd,gross_margin_pct,net_profit_usd,net_margin_pct")
        lines.append(
            "\(usd(summary.grossProfit.cents)),"
            + "\(String(format: "%.1f", summary.grossProfit.marginPct)),"
            + "\(usd(summary.netProfit.cents)),"
            + "\(String(format: "%.1f", summary.netProfit.marginPct))"
        )
        lines.append("")

        lines.append("# Expenses by Category")
        lines.append("category,amount_usd")
        for row in summary.expenses.byCategory {
            lines.append("\(csvEscape(row.category)),\(usd(row.cents))")
        }
        lines.append("")

        lines.append("# Time Series")
        lines.append("bucket,revenue_usd,expense_usd,net_usd")
        for bucket in summary.timeSeries {
            lines.append(
                "\(csvEscape(bucket.bucket)),"
                + "\(usd(bucket.revenueCents)),"
                + "\(usd(bucket.expenseCents)),"
                + "\(usd(bucket.netCents))"
            )
        }
        lines.append("")

        lines.append("# Top Customers")
        lines.append("customer_id,name,revenue_usd")
        for c in summary.topCustomers {
            lines.append("\(c.customerId),\(csvEscape(c.name)),\(usd(c.revenueCents))")
        }
        lines.append("")

        lines.append("# Top Services")
        lines.append("service,count,revenue_usd")
        for s in summary.topServices {
            lines.append("\(csvEscape(s.service)),\(s.count),\(usd(s.revenueCents))")
        }

        return try writeTempCSV(
            name: "owner-pl-\(summary.period.from)-to-\(summary.period.to)",
            content: lines.joined(separator: "\n")
        )
    }

    // MARK: - Private helpers

    private func writeTempCSV(name: String, content: String) throws -> URL {
        let safeName = name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BizarreCRM_\(safeName)_\(Int(Date().timeIntervalSince1970)).csv")
        guard let data = content.data(using: .utf8) else {
            throw ReportCSVError.encodingFailed
        }
        try data.write(to: url)
        return url
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func usd(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }
}

// MARK: - Errors

public enum ReportCSVError: Error, LocalizedError {
    case encodingFailed

    public var errorDescription: String? {
        "Failed to encode CSV data."
    }
}
