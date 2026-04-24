import Foundation

// MARK: - APIClient+Reports
//
// Append-only extension for reports endpoints.
// Routes grounded against packages/server/src/routes/reports.routes.ts:
//   GET /api/v1/reports/sales          — revenue, time-bucketed by group_by
//   GET /api/v1/reports/dashboard-kpis — expenses + daily COGS breakdown
//   GET /api/v1/reports/inventory      — stock counts + value + top-moving

public extension APIClient {

    // MARK: - Revenue → GET /api/v1/reports/sales
    //
    // Query params: from_date, to_date, group_by (day|week|month)
    // Response envelope: { success, data: { rows, totals, byMethod, from, to } }

    func fetchRevenueReport(
        from: String,
        to: String,
        groupBy: ReportGranularity = .day
    ) async throws -> RevenueReportPayload {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date",   value: to),
            URLQueryItem(name: "group_by",  value: groupBy.rawValue)
        ]
        return try await get("/api/v1/reports/sales", query: query, as: RevenueReportPayload.self)
    }

    // MARK: - Expenses → GET /api/v1/reports/dashboard-kpis
    //
    // Query params: from_date, to_date
    // Response envelope: { success, data: { total_sales, expenses, cogs, daily_sales[] } }
    // No dedicated /expenses endpoint — dashboard-kpis is the correct source.

    func fetchExpensesReport(
        from: String,
        to: String
    ) async throws -> DashboardKpisPayload {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date",   value: to)
        ]
        return try await get("/api/v1/reports/dashboard-kpis", query: query, as: DashboardKpisPayload.self)
    }

    // MARK: - Inventory → GET /api/v1/reports/inventory
    //
    // No date params — returns current stock state.
    // Response envelope: { success, data: { lowStock[], valueSummary[], outOfStock, topMoving[] } }

    func fetchInventoryReport() async throws -> InventoryReportPayload {
        try await get("/api/v1/reports/inventory", as: InventoryReportPayload.self)
    }
}

// MARK: - ReportGranularity
//
// Maps to the server's group_by query parameter for the /reports/sales endpoint.

public enum ReportGranularity: String, CaseIterable, Sendable, Identifiable {
    case day   = "day"
    case week  = "week"
    case month = "month"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }
}

// MARK: - RevenueReportPayload
//
// Mirrors the `data` object from GET /api/v1/reports/sales.
// Server shape:
//   rows[]:    { period, revenue, invoices, unique_customers }
//   totals:    { total_invoices, total_revenue, unique_customers, revenue_change_pct? }
//   byMethod[]: { method, revenue, count }

public struct RevenueReportPayload: Decodable, Sendable {
    public let rows: [RevenueRow]
    public let totals: RevenueTotals
    public let byMethod: [RevenueByMethod]

    public init(rows: [RevenueRow] = [],
                totals: RevenueTotals = RevenueTotals(),
                byMethod: [RevenueByMethod] = []) {
        self.rows = rows
        self.totals = totals
        self.byMethod = byMethod
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rows     = (try? c.decode([RevenueRow].self,      forKey: .rows))     ?? []
        self.totals   = (try? c.decode(RevenueTotals.self,     forKey: .totals))   ?? RevenueTotals()
        self.byMethod = (try? c.decode([RevenueByMethod].self, forKey: .byMethod)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case rows, totals, byMethod
    }
}

public struct RevenueRow: Decodable, Sendable, Identifiable {
    public let period: String
    /// Revenue in dollars (server sends dollars, not cents).
    public let revenue: Double
    public let invoices: Int
    public let uniqueCustomers: Int

    public var id: String { period }
    public var revenueCents: Int64 { Int64(revenue * 100.0) }

    public init(period: String, revenue: Double,
                invoices: Int = 0, uniqueCustomers: Int = 0) {
        self.period          = period
        self.revenue         = revenue
        self.invoices        = invoices
        self.uniqueCustomers = uniqueCustomers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.period          = (try? c.decode(String.self, forKey: .period)) ?? ""
        self.revenue         = (try? c.decode(Double.self, forKey: .revenue)) ?? 0
        self.invoices        = (try? c.decode(Int.self,    forKey: .invoices)) ?? 0
        self.uniqueCustomers = (try? c.decode(Int.self,    forKey: .uniqueCustomers)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case period, revenue, invoices
        case uniqueCustomers = "unique_customers"
    }
}

public struct RevenueTotals: Decodable, Sendable {
    public let totalRevenue: Double
    public let revenueChangePct: Double?
    public let totalInvoices: Int
    public let uniqueCustomers: Int

    public init(totalRevenue: Double = 0,
                revenueChangePct: Double? = nil,
                totalInvoices: Int = 0,
                uniqueCustomers: Int = 0) {
        self.totalRevenue     = totalRevenue
        self.revenueChangePct = revenueChangePct
        self.totalInvoices    = totalInvoices
        self.uniqueCustomers  = uniqueCustomers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalRevenue     = (try? c.decode(Double.self, forKey: .totalRevenue))     ?? 0
        self.revenueChangePct = try? c.decode(Double.self, forKey: .revenueChangePct)
        self.totalInvoices    = (try? c.decode(Int.self,    forKey: .totalInvoices))    ?? 0
        self.uniqueCustomers  = (try? c.decode(Int.self,    forKey: .uniqueCustomers))  ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case totalRevenue      = "total_revenue"
        case revenueChangePct  = "revenue_change_pct"
        case totalInvoices     = "total_invoices"
        case uniqueCustomers   = "unique_customers"
    }
}

public struct RevenueByMethod: Decodable, Sendable, Identifiable {
    public let method: String
    public let revenue: Double
    public let count: Int

    public var id: String { method }

    public init(method: String, revenue: Double, count: Int) {
        self.method  = method
        self.revenue = revenue
        self.count   = count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.method  = (try? c.decode(String.self, forKey: .method))  ?? "Other"
        self.revenue = (try? c.decode(Double.self, forKey: .revenue)) ?? 0
        self.count   = (try? c.decode(Int.self,    forKey: .count))   ?? 0
    }

    enum CodingKeys: String, CodingKey { case method, revenue, count }
}

// MARK: - DashboardKpisPayload
//
// Mirrors `data` from GET /api/v1/reports/dashboard-kpis.
// Used to derive the Expenses chart.

public struct DashboardKpisPayload: Decodable, Sendable {
    public let totalSales: Double
    public let expenses: Double
    public let cogs: Double
    public let dailySales: [DailySaleRow]

    public init(totalSales: Double = 0,
                expenses: Double = 0,
                cogs: Double = 0,
                dailySales: [DailySaleRow] = []) {
        self.totalSales = totalSales
        self.expenses   = expenses
        self.cogs       = cogs
        self.dailySales = dailySales
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalSales = (try? c.decode(Double.self,     forKey: .totalSales)) ?? 0
        self.expenses   = (try? c.decode(Double.self,     forKey: .expenses))   ?? 0
        self.cogs       = (try? c.decode(Double.self,     forKey: .cogs))       ?? 0
        self.dailySales = (try? c.decode([DailySaleRow].self, forKey: .dailySales)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case totalSales = "total_sales"
        case expenses, cogs
        case dailySales = "daily_sales"
    }
}

public struct DailySaleRow: Decodable, Sendable, Identifiable {
    public let date: String
    public let sale: Double
    public let cogs: Double
    public let netProfit: Double
    public let marginPct: Double?

    public var id: String { date }

    public init(date: String, sale: Double, cogs: Double,
                netProfit: Double, marginPct: Double? = nil) {
        self.date      = date
        self.sale      = sale
        self.cogs      = cogs
        self.netProfit = netProfit
        self.marginPct = marginPct
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date      = (try? c.decode(String.self, forKey: .date))      ?? ""
        self.sale      = (try? c.decode(Double.self, forKey: .sale))      ?? 0
        self.cogs      = (try? c.decode(Double.self, forKey: .cogs))      ?? 0
        self.netProfit = (try? c.decode(Double.self, forKey: .netProfit)) ?? 0
        self.marginPct = try? c.decode(Double.self, forKey: .marginPct)
    }

    enum CodingKeys: String, CodingKey {
        case date, sale, cogs
        case netProfit = "net_profit"
        case marginPct = "margin"
    }
}

// MARK: - InventoryReportPayload
//
// Mirrors `data` from GET /api/v1/reports/inventory.

public struct InventoryReportPayload: Decodable, Sendable {
    public let lowStock: [InventoryItemRow]
    public let valueSummary: [InventoryValueRow]
    public let outOfStock: Int
    public let topMoving: [InventoryItemRow]

    public init(lowStock: [InventoryItemRow] = [],
                valueSummary: [InventoryValueRow] = [],
                outOfStock: Int = 0,
                topMoving: [InventoryItemRow] = []) {
        self.lowStock     = lowStock
        self.valueSummary = valueSummary
        self.outOfStock   = outOfStock
        self.topMoving    = topMoving
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lowStock     = (try? c.decode([InventoryItemRow].self,  forKey: .lowStock))     ?? []
        self.valueSummary = (try? c.decode([InventoryValueRow].self, forKey: .valueSummary)) ?? []
        self.outOfStock   = (try? c.decode(Int.self,                 forKey: .outOfStock))   ?? 0
        self.topMoving    = (try? c.decode([InventoryItemRow].self,  forKey: .topMoving))    ?? []
    }

    enum CodingKeys: String, CodingKey {
        case lowStock = "lowStock"
        case valueSummary = "valueSummary"
        case outOfStock = "outOfStock"
        case topMoving = "topMoving"
    }
}

public struct InventoryItemRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let sku: String?
    public let inStock: Int
    public let reorderLevel: Int?
    public let usedQty: Int

    public init(id: Int64, name: String, sku: String? = nil,
                inStock: Int = 0, reorderLevel: Int? = nil, usedQty: Int = 0) {
        self.id           = id
        self.name         = name
        self.sku          = sku
        self.inStock      = inStock
        self.reorderLevel = reorderLevel
        self.usedQty      = usedQty
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id           = (try? c.decode(Int64.self,  forKey: .id))           ?? 0
        self.name         = (try? c.decode(String.self, forKey: .name))         ?? ""
        self.sku          = try? c.decode(String.self, forKey: .sku)
        self.inStock      = (try? c.decode(Int.self,    forKey: .inStock))      ?? 0
        self.reorderLevel = try? c.decode(Int.self,    forKey: .reorderLevel)
        self.usedQty      = (try? c.decode(Int.self,    forKey: .usedQty))      ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sku
        case inStock      = "in_stock"
        case reorderLevel = "reorder_level"
        case usedQty      = "used_qty"
    }
}

public struct InventoryValueRow: Decodable, Sendable, Identifiable {
    public let itemType: String
    public let itemCount: Int
    public let totalUnits: Int
    public let totalCostValue: Double
    public let totalRetailValue: Double

    public var id: String { itemType }

    public init(itemType: String, itemCount: Int, totalUnits: Int,
                totalCostValue: Double, totalRetailValue: Double) {
        self.itemType         = itemType
        self.itemCount        = itemCount
        self.totalUnits       = totalUnits
        self.totalCostValue   = totalCostValue
        self.totalRetailValue = totalRetailValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.itemType         = (try? c.decode(String.self, forKey: .itemType))         ?? ""
        self.itemCount        = (try? c.decode(Int.self,    forKey: .itemCount))        ?? 0
        self.totalUnits       = (try? c.decode(Int.self,    forKey: .totalUnits))       ?? 0
        self.totalCostValue   = (try? c.decode(Double.self, forKey: .totalCostValue))   ?? 0
        self.totalRetailValue = (try? c.decode(Double.self, forKey: .totalRetailValue)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case itemType         = "item_type"
        case itemCount        = "item_count"
        case totalUnits       = "total_units"
        case totalCostValue   = "total_cost_value"
        case totalRetailValue = "total_retail_value"
    }
}
