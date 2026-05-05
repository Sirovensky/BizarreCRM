import Foundation

// MARK: - AgedReceivablesCalculator

/// Pure, stateless aged receivables bucketizer. All values in cents.
public enum AgedReceivablesCalculator {

    /// Bucketize outstanding invoices by how many days past due they are.
    /// - Parameters:
    ///   - invoices: Unpaid/outstanding invoices with a due date and amount.
    ///   - asOf:     The reference date for aging (defaults to today).
    /// - Returns: An `AgedReceivablesSnapshot` grouping invoices into 0-30, 31-60, 61-90, 90+ day buckets.
    public static func bucketize(
        invoices: [OutstandingInvoice],
        asOf: Date = Date()
    ) -> AgedReceivablesSnapshot {
        var current    = (cents: 0, count: 0)
        var thirty     = (cents: 0, count: 0)
        var sixty      = (cents: 0, count: 0)
        var ninetyPlus = (cents: 0, count: 0)

        for invoice in invoices {
            let daysPastDue = daysDifference(from: invoice.dueDate, to: asOf)
            let amount = invoice.amountCents
            switch daysPastDue {
            case ...30:
                current.cents += amount
                current.count += 1
            case 31...60:
                thirty.cents += amount
                thirty.count += 1
            case 61...90:
                sixty.cents += amount
                sixty.count += 1
            default:
                ninetyPlus.cents += amount
                ninetyPlus.count += 1
            }
        }

        return AgedReceivablesSnapshot(
            current:    AgedReceivablesBucket(label: "0-30",  totalCents: current.cents,    invoiceCount: current.count),
            thirtyPlus: AgedReceivablesBucket(label: "31-60", totalCents: thirty.cents,     invoiceCount: thirty.count),
            sixtyPlus:  AgedReceivablesBucket(label: "61-90", totalCents: sixty.cents,      invoiceCount: sixty.count),
            ninetyPlus: AgedReceivablesBucket(label: "90+",   totalCents: ninetyPlus.cents, invoiceCount: ninetyPlus.count)
        )
    }

    /// Percentage of total overdue receivables (>30 days) vs total outstanding.
    public static func overduePercentage(snapshot: AgedReceivablesSnapshot) -> Double {
        guard snapshot.totalCents > 0 else { return 0 }
        let overdue = snapshot.thirtyPlus.totalCents + snapshot.sixtyPlus.totalCents + snapshot.ninetyPlus.totalCents
        return Double(overdue) / Double(snapshot.totalCents)
    }

    // MARK: - Private

    /// Number of whole days from `from` to `to`. Negative if `to` < `from`.
    private static func daysDifference(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
