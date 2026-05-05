import Foundation

// MARK: - PnLCalculator

/// Pure, stateless P&L calculator. All values in cents.
public enum PnLCalculator {

    /// Compute a PnL snapshot from raw revenue, COGS, and expense data.
    public static func compute(
        revenues: [Sale],
        cogs: [COGSEntry],
        expenses: [FinancialExpense]
    ) -> PnLSnapshot {
        let totalRevenue  = revenues.reduce(0)  { $0 + $1.amountCents }
        let totalCOGS     = cogs.reduce(0)      { $0 + $1.amountCents }
        let totalExpenses = expenses.reduce(0)  { $0 + $1.amountCents }
        return PnLSnapshot(
            revenueCents: totalRevenue,
            cogsCents: totalCOGS,
            expensesCents: totalExpenses
        )
    }

    /// Revenue grouped by customer (id → total cents). Useful for top-N customer ranking.
    public static func revenueByCustomer(revenues: [Sale]) -> [(customerId: String, name: String, totalCents: Int)] {
        var map: [String: (name: String, total: Int)] = [:]
        for sale in revenues {
            let key = sale.customerId ?? "__unknown__"
            let current = map[key] ?? (name: sale.customerName ?? "Unknown", total: 0)
            map[key] = (name: current.name, total: current.total + sale.amountCents)
        }
        return map.map { (customerId: $0.key, name: $0.value.name, totalCents: $0.value.total) }
            .sorted { $0.totalCents > $1.totalCents }
    }

    /// Top N customers by revenue.
    public static func topCustomers(revenues: [Sale], limit: Int = 10) -> [TopCustomer] {
        revenueByCustomer(revenues: revenues)
            .prefix(limit)
            .map { TopCustomer(id: $0.customerId, name: $0.name, revenueCents: $0.totalCents) }
    }

    /// COGS grouped by category for breakdown chart.
    public static func cogsByDescription(cogs: [COGSEntry]) -> [(description: String, amountCents: Int)] {
        var map: [String: Int] = [:]
        for entry in cogs {
            map[entry.description, default: 0] += entry.amountCents
        }
        return map.map { (description: $0.key, amountCents: $0.value) }
            .sorted { $0.amountCents > $1.amountCents }
    }

    /// Expenses grouped by category.
    public static func expensesByCategory(expenses: [FinancialExpense]) -> [(category: String, amountCents: Int)] {
        var map: [String: Int] = [:]
        for expense in expenses {
            map[expense.category, default: 0] += expense.amountCents
        }
        return map.map { (category: $0.key, amountCents: $0.value) }
            .sorted { $0.amountCents > $1.amountCents }
    }
}
