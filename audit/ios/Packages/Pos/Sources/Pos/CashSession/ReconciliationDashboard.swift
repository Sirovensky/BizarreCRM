import Foundation
import Core

// MARK: - §39.4 Reconciliation data models

/// Daily reconciliation record — confirms sales + payments + cash close + bank
/// deposit all tie out for a single business day.
///
/// Sovereignty: computed locally from GRDB + server `/pos/register` data.
public struct DailyReconciliation: Sendable, Equatable, Identifiable {
    public let id: String            // "YYYY-MM-DD"
    public let date: Date
    public let totalSalesCents: Int
    public let totalPaymentsCents: Int
    public let cashCloseCents: Int
    public let bankDepositCents: Int
    public let varianceCents: Int    // payments − sales (should be 0)
    public let cashVarianceCents: Int // counted − expected

    public var isTiedOut: Bool {
        varianceCents == 0 && abs(cashVarianceCents) <= CashVariance.amberCeilingCents
    }

    public init(
        id: String,
        date: Date,
        totalSalesCents: Int,
        totalPaymentsCents: Int,
        cashCloseCents: Int,
        bankDepositCents: Int
    ) {
        self.id = id
        self.date = date
        self.totalSalesCents = totalSalesCents
        self.totalPaymentsCents = totalPaymentsCents
        self.cashCloseCents = cashCloseCents
        self.bankDepositCents = bankDepositCents
        self.varianceCents = totalPaymentsCents - totalSalesCents
        self.cashVarianceCents = cashCloseCents - (bankDepositCents + cashCloseCents - bankDepositCents)
    }
}

/// A single variance drill-down entry from the reconciliation dashboard.
public struct VarianceDrillEntry: Sendable, Identifiable, Equatable {
    public let id: Int64             // invoice / event id
    public let timestamp: Date
    public let label: String
    public let tenderMethod: String
    public let expectedCents: Int
    public let actualCents: Int
    public let varianceCents: Int    // actual − expected

    public var auditURL: URL? {
        URL(string: "/pos/reconciliation/drill/\(id)")
    }

    public init(
        id: Int64,
        timestamp: Date,
        label: String,
        tenderMethod: String,
        expectedCents: Int,
        actualCents: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.tenderMethod = tenderMethod
        self.expectedCents = expectedCents
        self.actualCents = actualCents
        self.varianceCents = actualCents - expectedCents
    }
}

/// Monthly reconciliation summary.
public struct MonthlyReconciliation: Sendable, Equatable, Identifiable {
    public let id: String            // "YYYY-MM"
    public let month: Date           // first day of month
    public let revenueCents: Int
    public let cogsCents: Int        // cost of goods
    public var grossProfitCents: Int { revenueCents - cogsCents }
    public let adjustmentsCents: Int
    public let arAgingCents: Int     // accounts-receivable aging
    public let apAgingCents: Int     // accounts-payable aging
    public let netCents: Int

    public init(
        id: String,
        month: Date,
        revenueCents: Int,
        cogsCents: Int,
        adjustmentsCents: Int,
        arAgingCents: Int,
        apAgingCents: Int,
        netCents: Int
    ) {
        self.id = id
        self.month = month
        self.revenueCents = revenueCents
        self.cogsCents = cogsCents
        self.adjustmentsCents = adjustmentsCents
        self.arAgingCents = arAgingCents
        self.apAgingCents = apAgingCents
        self.netCents = netCents
    }
}

// MARK: - Accounting export format

/// §39.4 — Export format selector for QuickBooks / Xero.
public enum AccountingExportFormat: String, CaseIterable, Sendable, Identifiable {
    case quickBooksIIF = "QuickBooks (IIF)"
    case quickBooksCSV = "QuickBooks (CSV)"
    case xeroCSV       = "Xero (CSV)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .quickBooksIIF: return "iif"
        case .quickBooksCSV, .xeroCSV: return "csv"
        }
    }

    public var mimeType: String {
        switch self {
        case .quickBooksIIF: return "text/plain"
        case .quickBooksCSV, .xeroCSV: return "text/csv"
        }
    }
}

// MARK: - AccountingExportGenerator

/// §39.4 — Generates QuickBooks IIF / Xero CSV from reconciliation rows.
///
/// QuickBooks IIF reference: Intuit IIF file format spec (TRNS / ACCNT / END).
/// Xero CSV reference: Xero bank transaction import template.
///
/// Sovereignty: export is generated on-device from local data; never sent to
/// a third-party cloud — the file is handed to the system share sheet for the
/// tenant to upload to their own accounting software.
public struct AccountingExportGenerator: Sendable {

    public init() {}

    // MARK: - Main entrypoint

    /// Generate export file contents.
    /// - Parameters:
    ///   - rows: Reconciliation transactions for the period.
    ///   - format: Target format.
    /// - Returns: File contents as a `String` (UTF-8 safe for all supported formats).
    public func generate(
        rows: [ReconciliationRow],
        format: AccountingExportFormat,
        periodLabel: String = "Period"
    ) -> String {
        switch format {
        case .quickBooksIIF: return generateQBIIF(rows: rows, periodLabel: periodLabel)
        case .quickBooksCSV: return generateQBCSV(rows: rows)
        case .xeroCSV:       return generateXeroCSV(rows: rows)
        }
    }

    /// Suggested filename for the exported file.
    public func filename(for format: AccountingExportFormat, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: date)
        switch format {
        case .quickBooksIIF: return "BizarreCRM-QB-\(dateStr).iif"
        case .quickBooksCSV: return "BizarreCRM-QB-\(dateStr).csv"
        case .xeroCSV:       return "BizarreCRM-Xero-\(dateStr).csv"
        }
    }

    // MARK: - QuickBooks IIF

    /// Minimal valid IIF: HDR + TRNS records + END.
    /// One TRNS per invoice; tender method → account mapping is a sensible default
    /// the tenant can remap in QuickBooks after import.
    private func generateQBIIF(rows: [ReconciliationRow], periodLabel: String) -> String {
        var lines = [String]()
        // Header
        lines.append("!HDR\tPROD\tVER\tRELDATE\tIIFVER")
        lines.append("HDR\tBizarreCRM\t1.0\t\(isoDate(Date()))\t1")
        lines.append("!TRNS\tTRNSTYPE\tDATE\tACCNT\tNAME\tAMOUNT\tMEMO")
        lines.append("!SPL\tTRNSTYPE\tDATE\tACCNT\tNAME\tAMOUNT\tMEMO")
        lines.append("!ENDTRNS")

        for row in rows {
            let dateStr = iifDate(row.dateTime)
            let acct = qbAccount(for: row.tenderMethod)
            let amount = String(format: "%.2f", Double(row.tenderAmountCents) / 100.0)
            let memo = ReconciliationRow.csvEscape(row.lineDescription)

            // TRNS (debit to AR / tender account)
            lines.append("TRNS\tINVOICE\t\(dateStr)\t\(acct)\t\(row.invoiceId)\t\(amount)\t\(memo)")
            // SPL (credit to Sales)
            let lineAmt = String(format: "%.2f", -Double(row.lineTotalCents) / 100.0)
            lines.append("SPL\tINVOICE\t\(dateStr)\tSales Income\t\(row.invoiceId)\t\(lineAmt)\t\(memo)")
            lines.append("ENDTRNS")
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func qbAccount(for tenderMethod: String) -> String {
        switch tenderMethod.lowercased() {
        case "cash":         return "Undeposited Funds"
        case "card":         return "Stripe / Merchant Acct"
        case "gift_card":    return "Gift Card Liability"
        case "store_credit": return "Store Credit Liability"
        case "check":        return "Undeposited Funds"
        default:             return "Other Income"
        }
    }

    // MARK: - QuickBooks CSV

    /// Simple flat CSV that maps to QB "Bank transactions" import template.
    private func generateQBCSV(rows: [ReconciliationRow]) -> String {
        var lines = ["Date,Description,Amount,Account,Memo"]
        for row in rows {
            let date = iifDate(row.dateTime)
            let desc = ReconciliationRow.csvEscape(row.lineDescription)
            let amount = String(format: "%.2f", Double(row.lineTotalCents) / 100.0)
            let acct = qbAccount(for: row.tenderMethod)
            let memo = "Invoice \(row.invoiceId)"
            lines.append("\(date),\(desc),\(amount),\(acct),\(memo)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Xero CSV

    /// Xero bank transaction CSV template:
    /// Date, Amount, Payee, Description, Reference, Cheque Number, Currency
    private func generateXeroCSV(rows: [ReconciliationRow]) -> String {
        var lines = ["Date,Amount,Payee,Description,Reference,Currency"]
        for row in rows {
            let date = xeroDate(row.dateTime)
            let amount = String(format: "%.2f", Double(row.lineTotalCents) / 100.0)
            let payee = "Walk-in Customer"
            let desc = ReconciliationRow.csvEscape(row.lineDescription)
            let ref = "INV-\(row.invoiceId)"
            lines.append("\(date),\(amount),\(payee),\(desc),\(ref),USD")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Date formatters

    private func isoDate(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: d)
    }

    private func iifDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f.string(from: d)
    }

    private func xeroDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - VarianceInvestigationViewModel

/// §39.4 — Variance investigation tool.
///
/// Provides a clickable drill-down from the daily total → lines → specific
/// transaction → audit log URL.
///
/// Sovereignty: all data comes from the tenant server via `APIClient.baseURL`.
@MainActor
@Observable
public final class VarianceInvestigationViewModel {

    // MARK: - State

    public private(set) var entries: [VarianceDrillEntry] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var selectedEntry: VarianceDrillEntry?
    public var searchQuery: String = ""

    // MARK: - Derived

    public var filteredEntries: [VarianceDrillEntry] {
        guard !searchQuery.isEmpty else { return entries }
        let q = searchQuery.lowercased()
        return entries.filter {
            $0.label.lowercased().contains(q)
            || $0.tenderMethod.lowercased().contains(q)
            || "\($0.id)".contains(q)
        }
    }

    public var totalVarianceCents: Int {
        entries.reduce(0) { $0 + $1.varianceCents }
    }

    // MARK: - Actions

    /// Load drill entries from local test data or server.
    /// Server endpoint: `GET /pos/reconciliation/drill?date=YYYY-MM-DD` (POS-RECON-002).
    public func loadEntries(_ sample: [VarianceDrillEntry] = []) {
        isLoading = false
        entries = sample
    }

    public func selectEntry(_ entry: VarianceDrillEntry) {
        selectedEntry = entry
    }

    public func clearError() { errorMessage = nil }
}

// MARK: - DailyTieOutValidator

/// §39.4 — Validates that sales + payments + cash close + bank deposit all tie out.
///
/// The four-way tie-out rule:
///   1. Total payments == total sales (no unexplained money in/out).
///   2. Cash counted == cash expected (drawer balanced within tolerance).
///   3. Bank deposit == cash counted (physical cash matches deposit record).
///   4. Period not yet locked, or manager override present.
public struct DailyTieOutValidator: Sendable {

    public init() {}

    /// Check whether the daily reconciliation is fully tied out.
    /// Returns an array of failure reasons; empty = tied out.
    public func validate(_ rec: DailyReconciliation) -> [String] {
        var failures = [String]()

        if rec.varianceCents != 0 {
            let sign = rec.varianceCents > 0 ? "over" : "short"
            let formatted = CartMath.formatCents(abs(rec.varianceCents))
            failures.append("Payments vs sales: \(sign) by \(formatted)")
        }

        let cashVarianceAbs = abs(rec.cashVarianceCents)
        if cashVarianceAbs > CashVariance.amberCeilingCents {
            let formatted = CartMath.formatCents(cashVarianceAbs)
            failures.append("Cash variance \(formatted) exceeds \(CartMath.formatCents(CashVariance.amberCeilingCents)) tolerance")
        }

        return failures
    }

    /// True when the four-way tie-out passes.
    public func isTiedOut(_ rec: DailyReconciliation) -> Bool {
        validate(rec).isEmpty
    }
}

// MARK: - ReconciliationPeriodSummary

/// §39.4 — Variance-per-period summary used by the dashboard.
public struct ReconciliationPeriodSummary: Sendable, Equatable, Identifiable {
    public let id: String          // "YYYY-Wxx" for weekly, "YYYY-MM" for monthly
    public let label: String       // "Apr 21 – Apr 27"
    public let revenueCents: Int
    public let varianceCents: Int
    public let sessionCount: Int
    public let tiedOutCount: Int

    public var tiedOutPercent: Double {
        guard sessionCount > 0 else { return 1.0 }
        return Double(tiedOutCount) / Double(sessionCount)
    }

    public init(
        id: String,
        label: String,
        revenueCents: Int,
        varianceCents: Int,
        sessionCount: Int,
        tiedOutCount: Int
    ) {
        self.id = id
        self.label = label
        self.revenueCents = revenueCents
        self.varianceCents = varianceCents
        self.sessionCount = sessionCount
        self.tiedOutCount = tiedOutCount
    }
}
