import Foundation

// MARK: - Sale (revenue input)

public struct Sale: Sendable {
    public let id: String
    public let date: Date
    public let amountCents: Int
    public let customerId: String?
    public let customerName: String?
    public let sku: String?

    public init(
        id: String,
        date: Date,
        amountCents: Int,
        customerId: String? = nil,
        customerName: String? = nil,
        sku: String? = nil
    ) {
        self.id = id
        self.date = date
        self.amountCents = amountCents
        self.customerId = customerId
        self.customerName = customerName
        self.sku = sku
    }
}

// MARK: - COGSEntry

public struct COGSEntry: Sendable {
    public let id: String
    public let date: Date
    public let amountCents: Int
    public let sku: String?
    public let description: String

    public init(id: String, date: Date, amountCents: Int, sku: String? = nil, description: String) {
        self.id = id
        self.date = date
        self.amountCents = amountCents
        self.sku = sku
        self.description = description
    }
}

// MARK: - Expense (for Financial Dashboard — reuses §11 categories)

public struct FinancialExpense: Sendable {
    public let id: String
    public let date: Date
    public let amountCents: Int
    public let category: String
    public let description: String

    public init(id: String, date: Date, amountCents: Int, category: String, description: String) {
        self.id = id
        self.date = date
        self.amountCents = amountCents
        self.category = category
        self.description = description
    }
}

// MARK: - PnLVariance (§59/§15 P&L variance row)

/// Period-over-period change for a single P&L line item.
public struct PnLVariance: Sendable {
    /// Absolute change in cents (current − prior). Positive = improvement for revenue/profit lines.
    public let deltaCents: Int
    /// Percentage change. Nil when prior period was zero (avoids divide-by-zero).
    public let deltaPct: Double?

    public init(currentCents: Int, priorCents: Int) {
        self.deltaCents = currentCents - priorCents
        self.deltaPct = priorCents == 0 ? nil : Double(currentCents - priorCents) / Double(abs(priorCents))
    }

    /// True when the delta represents a favorable movement (revenue/profit grew, or expenses shrank).
    public func isFavorable(higherIsBetter: Bool) -> Bool {
        higherIsBetter ? deltaCents >= 0 : deltaCents <= 0
    }
}

// MARK: - PnLSnapshot

public struct PnLSnapshot: Sendable {
    public let revenueCents: Int
    public let cogsCents: Int
    public let expensesCents: Int
    public let grossProfitCents: Int
    public let netCents: Int

    // §59/§15 P&L variance row — optional prior-period comparison.
    public let variance: PnLVariance?

    public var grossMarginPct: Double {
        guard revenueCents > 0 else { return 0 }
        return Double(grossProfitCents) / Double(revenueCents)
    }

    public var netMarginPct: Double {
        guard revenueCents > 0 else { return 0 }
        return Double(netCents) / Double(revenueCents)
    }

    /// Convenience init without variance (prior-period data not available).
    public init(revenueCents: Int, cogsCents: Int, expensesCents: Int) {
        self.revenueCents = revenueCents
        self.cogsCents = cogsCents
        self.expensesCents = expensesCents
        self.grossProfitCents = revenueCents - cogsCents
        self.netCents = revenueCents - cogsCents - expensesCents
        self.variance = nil
    }

    /// Full init including prior-period net for variance display.
    public init(revenueCents: Int, cogsCents: Int, expensesCents: Int, priorNetCents: Int) {
        self.revenueCents = revenueCents
        self.cogsCents = cogsCents
        self.expensesCents = expensesCents
        self.grossProfitCents = revenueCents - cogsCents
        self.netCents = revenueCents - cogsCents - expensesCents
        self.variance = PnLVariance(currentCents: self.netCents, priorCents: priorNetCents)
    }
}

// MARK: - ExpenseCategoryRow (§59/§15 expense category drilldown)

/// A single category row in the expense breakdown drilldown.
public struct ExpenseCategoryRow: Sendable, Identifiable {
    public var id: String { category }
    public let category: String
    public let amountCents: Int
    public let shareOfTotal: Double   // 0…1

    public init(category: String, amountCents: Int, shareOfTotal: Double) {
        self.category = category
        self.amountCents = amountCents
        self.shareOfTotal = shareOfTotal
    }
}

extension PnLSnapshot {
    // §59/§15 expense category drilldown — derive sorted rows from expenses grouped externally.
    public static func expenseCategoryRows(
        from grouped: [(category: String, amountCents: Int)]
    ) -> [ExpenseCategoryRow] {
        let total = grouped.reduce(0) { $0 + $1.amountCents }
        guard total > 0 else { return [] }
        return grouped.map {
            ExpenseCategoryRow(
                category: $0.category,
                amountCents: $0.amountCents,
                shareOfTotal: Double($0.amountCents) / Double(total)
            )
        }
        .sorted { $0.amountCents > $1.amountCents }
    }
}

// MARK: - CashFlowPoint

public struct CashFlowPoint: Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let inflowCents: Int
    public let outflowCents: Int

    public var netCents: Int { inflowCents - outflowCents }

    public init(id: String, date: Date, inflowCents: Int, outflowCents: Int) {
        self.id = id
        self.date = date
        self.inflowCents = inflowCents
        self.outflowCents = outflowCents
    }
}

// MARK: - AgedReceivablesBucket

public struct AgedReceivablesBucket: Sendable {
    public let label: String          // "0-30", "31-60", "61-90", "90+"
    public let totalCents: Int
    public let invoiceCount: Int

    public init(label: String, totalCents: Int, invoiceCount: Int) {
        self.label = label
        self.totalCents = totalCents
        self.invoiceCount = invoiceCount
    }
}

// MARK: - AgedReceivablesSnapshot

public struct AgedReceivablesSnapshot: Sendable {
    public let current: AgedReceivablesBucket    // 0-30 days
    public let thirtyPlus: AgedReceivablesBucket // 31-60
    public let sixtyPlus: AgedReceivablesBucket  // 61-90
    public let ninetyPlus: AgedReceivablesBucket // 90+
    public let totalCents: Int

    public var buckets: [AgedReceivablesBucket] { [current, thirtyPlus, sixtyPlus, ninetyPlus] }

    public init(
        current: AgedReceivablesBucket,
        thirtyPlus: AgedReceivablesBucket,
        sixtyPlus: AgedReceivablesBucket,
        ninetyPlus: AgedReceivablesBucket
    ) {
        self.current = current
        self.thirtyPlus = thirtyPlus
        self.sixtyPlus = sixtyPlus
        self.ninetyPlus = ninetyPlus
        self.totalCents = current.totalCents + thirtyPlus.totalCents
            + sixtyPlus.totalCents + ninetyPlus.totalCents
    }
}

// MARK: - OutstandingInvoice (input for aged AR)

public struct OutstandingInvoice: Sendable {
    public let id: String
    public let dueDate: Date
    public let amountCents: Int
    public let customerId: String?

    public init(id: String, dueDate: Date, amountCents: Int, customerId: String?) {
        self.id = id
        self.dueDate = dueDate
        self.amountCents = amountCents
        self.customerId = customerId
    }
}

// MARK: - TopCustomer

public struct TopCustomer: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let revenueCents: Int

    public init(id: String, name: String, revenueCents: Int) {
        self.id = id
        self.name = name
        self.revenueCents = revenueCents
    }
}

// MARK: - TopSkuByMargin

public struct TopSkuByMargin: Sendable, Identifiable {
    public let id: String
    public let sku: String
    public let name: String
    public let marginCents: Int
    public let marginPct: Double

    public init(id: String, sku: String, name: String, marginCents: Int, marginPct: Double) {
        self.id = id
        self.sku = sku
        self.name = name
        self.marginCents = marginCents
        self.marginPct = marginPct
    }
}

// MARK: - FinancialDashboardData (aggregate loaded by VM)

public struct FinancialDashboardData: Sendable {
    public let pnl: PnLSnapshot
    public let cashFlow: [CashFlowPoint]
    public let agedReceivables: AgedReceivablesSnapshot
    public let topCustomers: [TopCustomer]
    public let topSkus: [TopSkuByMargin]
    /// §59/§15 expense category drilldown — pre-grouped by the VM from server payload.
    public let expenseCategoryRows: [ExpenseCategoryRow]

    public init(
        pnl: PnLSnapshot,
        cashFlow: [CashFlowPoint],
        agedReceivables: AgedReceivablesSnapshot,
        topCustomers: [TopCustomer],
        topSkus: [TopSkuByMargin],
        expenseCategoryRows: [ExpenseCategoryRow] = []
    ) {
        self.pnl = pnl
        self.cashFlow = cashFlow
        self.agedReceivables = agedReceivables
        self.topCustomers = topCustomers
        self.topSkus = topSkus
        self.expenseCategoryRows = expenseCategoryRows
    }
}

// MARK: - TaxYearData

public struct TaxYearData: Sendable {
    public let year: Int
    public let revenueByMonth: [(month: String, amountCents: Int)]
    public let salesTaxCollectedCents: Int
    public let expensesByCategory: [(category: String, amountCents: Int)]
    public let totalCOGSCents: Int

    public init(
        year: Int,
        revenueByMonth: [(month: String, amountCents: Int)],
        salesTaxCollectedCents: Int,
        expensesByCategory: [(category: String, amountCents: Int)],
        totalCOGSCents: Int
    ) {
        self.year = year
        self.revenueByMonth = revenueByMonth
        self.salesTaxCollectedCents = salesTaxCollectedCents
        self.expensesByCategory = expensesByCategory
        self.totalCOGSCents = totalCOGSCents
    }
}
