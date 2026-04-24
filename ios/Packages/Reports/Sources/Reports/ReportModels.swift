import Foundation

// MARK: - RevenuePoint
//
// Maps to one row from GET /api/v1/reports/sales `data.rows[]`.
// Server shape: { period: String, revenue: Double, invoices: Int, unique_customers: Int }
// The server returns revenue in dollars (not cents). We store as cents for integer math.

public struct RevenuePoint: Codable, Sendable, Identifiable {
    /// Synthetic stable ID for SwiftUI ForEach — derived from date index.
    public let id: Int64
    /// ISO-8601 date or YYYY-MM period string.
    public let date: String
    /// Revenue in cents (converted from server dollars).
    public let amountCents: Int64
    /// Invoice / transaction count for the period.
    public let saleCount: Int

    public var amountDollars: Double { Double(amountCents) / 100.0 }

    // MARK: Decodable — server sends `period` and `revenue` (dollars)
    enum CodingKeys: String, CodingKey {
        case period
        case revenue
        case invoices
        case uniqueCustomers = "unique_customers"
        // Legacy keys kept for in-memory test construction
        case id
        case date
        case amountCents = "amount_cents"
        case saleCount   = "sale_count"
    }

    public init(id: Int64, date: String, amountCents: Int64, saleCount: Int) {
        self.id = id
        self.date = date
        self.amountCents = amountCents
        self.saleCount = saleCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Try server shape first (period + revenue dollars)
        if let period = try? c.decode(String.self, forKey: .period) {
            self.date = period
            let dollars = (try? c.decode(Double.self, forKey: .revenue)) ?? 0.0
            self.amountCents = Int64(dollars * 100.0)
            self.saleCount = (try? c.decode(Int.self, forKey: .invoices)) ?? 0
            self.id = Int64(period.hashValue & 0x7FFF_FFFF_FFFF_FFFF)
        } else {
            // Fallback: legacy / test shape with id, date, amount_cents, sale_count
            self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
            self.date = (try? c.decode(String.self, forKey: .date)) ?? ""
            self.amountCents = (try? c.decode(Int64.self, forKey: .amountCents)) ?? 0
            self.saleCount = (try? c.decode(Int.self, forKey: .saleCount)) ?? 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(amountCents, forKey: .amountCents)
        try c.encode(saleCount, forKey: .saleCount)
    }
}

// MARK: - TicketStatusPoint
//
// Maps to GET /api/v1/reports/tickets `data.byStatus[]`.
// Server shape: { status: String, color: String?, count: Int }

public struct TicketStatusPoint: Codable, Sendable, Identifiable {
    /// Stable synthetic ID from status string hash.
    public let id: Int64
    public let status: String
    public let count: Int
    /// Hex color string from server, e.g. "#FF6B35". Optional.
    public let color: String?

    enum CodingKeys: String, CodingKey {
        case id, status, count, color
    }

    public init(id: Int64, status: String, count: Int, color: String? = nil) {
        self.id = id
        self.status = status
        self.count = count
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = (try? c.decode(String.self, forKey: .status)) ?? ""
        self.count  = (try? c.decode(Int.self, forKey: .count)) ?? 0
        self.color  = try? c.decode(String.self, forKey: .color)
        // id: prefer explicit, else synthesize from status hash
        if let explicit = try? c.decode(Int64.self, forKey: .id) {
            self.id = explicit
        } else {
            self.id = Int64(self.status.hashValue & 0x7FFF_FFFF_FFFF_FFFF)
        }
    }
}

// MARK: - AvgTicketValue
//
// Derived in-client from GET /api/v1/reports/tickets `data.summary`.
// Server returns avg_ticket_value in dollars. No dedicated endpoint.

public struct AvgTicketValue: Codable, Sendable {
    public let currentCents: Int64
    public let previousCents: Int64
    public let trendPct: Double

    public var currentDollars: Double  { Double(currentCents)  / 100.0 }
    public var previousDollars: Double { Double(previousCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case currentCents  = "current_cents"
        case previousCents = "previous_cents"
        case trendPct      = "trend_pct"
    }

    public init(currentCents: Int64, previousCents: Int64, trendPct: Double) {
        self.currentCents = currentCents
        self.previousCents = previousCents
        self.trendPct = trendPct
    }

    /// Convenience init from server dollars.
    public init(currentDollars: Double, previousDollars: Double) {
        self.currentCents = Int64(currentDollars * 100.0)
        self.previousCents = Int64(previousDollars * 100.0)
        self.trendPct = previousDollars > 0
            ? ((currentDollars - previousDollars) / previousDollars) * 100.0
            : 0.0
    }
}

// MARK: - EmployeePerf
//
// Maps to GET /api/v1/reports/employees `data.rows[]`.
// Server shape: { id, name, role, tickets_assigned, tickets_closed,
//                 commission_earned, hours_worked, revenue_generated }
// All money values are in dollars from server.

public struct EmployeePerf: Codable, Sendable, Identifiable {
    public let id: Int64
    public let employeeName: String
    public let ticketsClosed: Int
    /// Revenue in cents (converted from server dollars).
    public let revenueCents: Int64
    /// Hours worked (from timesheets). Used as proxy for avg resolution hours.
    public let avgResolutionHours: Double
    /// Tickets assigned in the period.
    public let ticketsAssigned: Int

    public var revenueDollars: Double { Double(revenueCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case id
        // Server keys
        case name
        case ticketsAssigned    = "tickets_assigned"
        case ticketsClosed      = "tickets_closed"
        case revenueGenerated   = "revenue_generated"
        case hoursWorked        = "hours_worked"
        // Legacy test/in-memory keys
        case employeeName       = "employee_name"
        case revenueCents       = "revenue_cents"
        case avgResolutionHours = "avg_resolution_hours"
    }

    public init(id: Int64, employeeName: String, ticketsClosed: Int,
                revenueCents: Int64, avgResolutionHours: Double,
                ticketsAssigned: Int = 0) {
        self.id = id
        self.employeeName = employeeName
        self.ticketsClosed = ticketsClosed
        self.revenueCents = revenueCents
        self.avgResolutionHours = avgResolutionHours
        self.ticketsAssigned = ticketsAssigned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        // Prefer server `name` field; fall back to legacy `employee_name`
        if let name = try? c.decode(String.self, forKey: .name) {
            self.employeeName = name
        } else {
            self.employeeName = (try? c.decode(String.self, forKey: .employeeName)) ?? ""
        }
        self.ticketsClosed = (try? c.decode(Int.self, forKey: .ticketsClosed)) ?? 0
        self.ticketsAssigned = (try? c.decode(Int.self, forKey: .ticketsAssigned)) ?? 0
        // Revenue: prefer server dollars → convert; fall back to legacy cents
        if let dollars = try? c.decode(Double.self, forKey: .revenueGenerated) {
            self.revenueCents = Int64(dollars * 100.0)
        } else {
            self.revenueCents = (try? c.decode(Int64.self, forKey: .revenueCents)) ?? 0
        }
        // Hours: prefer server hours_worked; fall back to legacy avg_resolution_hours
        if let hours = try? c.decode(Double.self, forKey: .hoursWorked) {
            self.avgResolutionHours = hours
        } else {
            self.avgResolutionHours = (try? c.decode(Double.self, forKey: .avgResolutionHours)) ?? 0.0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(employeeName, forKey: .employeeName)
        try c.encode(ticketsClosed, forKey: .ticketsClosed)
        try c.encode(revenueCents, forKey: .revenueCents)
        try c.encode(avgResolutionHours, forKey: .avgResolutionHours)
    }
}

// MARK: - InventoryTurnoverRow
//
// Maps to GET /api/v1/reports/inventory-turnover `data.by_category[]`.
// Server shape: { category, sold_units, sold_value, avg_stock_value,
//                 turns_90d, status: "healthy"|"slow"|"stagnant" }
// Also used by the legacy inventory turnover table with sku/name/daysOnHand.

public struct InventoryTurnoverRow: Codable, Sendable, Identifiable {
    public let id: Int64
    /// Category label (from server) or SKU for legacy rows.
    public let sku: String
    /// Display name — category name (server) or item name (legacy).
    public let name: String
    /// Turns per 90-day window (server) or arbitrary rate (legacy).
    public let turnoverRate: Double
    /// Approximate days-on-hand (derived: 90 / max(turns,0.01)). Simulated for category rows.
    public let daysOnHand: Double
    /// Health status from server: "healthy", "slow", "stagnant", or nil for legacy rows.
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sku
        case name
        case category
        case turnoverRate  = "turnover_rate"
        case turns90d      = "turns_90d"
        case daysOnHand    = "days_on_hand"
        case status
    }

    public init(id: Int64, sku: String, name: String,
                turnoverRate: Double, daysOnHand: Double,
                status: String? = nil) {
        self.id = id
        self.sku = sku
        self.name = name
        self.turnoverRate = turnoverRate
        self.daysOnHand = daysOnHand
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try? c.decode(String.self, forKey: .status)
        // Prefer server `category` as both sku and name; fall back to legacy fields
        if let cat = try? c.decode(String.self, forKey: .category) {
            self.sku = cat
            self.name = cat
            let t = (try? c.decode(Double.self, forKey: .turns90d)) ?? 0.0
            self.turnoverRate = t
            self.daysOnHand = t > 0.001 ? (90.0 / t) : 9999.0
            self.id = Int64(cat.hashValue & 0x7FFF_FFFF_FFFF_FFFF)
        } else {
            self.id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
            self.sku = (try? c.decode(String.self, forKey: .sku)) ?? ""
            self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
            self.turnoverRate = (try? c.decode(Double.self, forKey: .turnoverRate)) ?? 0.0
            self.daysOnHand = (try? c.decode(Double.self, forKey: .daysOnHand)) ?? 0.0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sku, forKey: .sku)
        try c.encode(name, forKey: .name)
        try c.encode(turnoverRate, forKey: .turnoverRate)
        try c.encode(daysOnHand, forKey: .daysOnHand)
    }
}

// MARK: - CSATScore

public struct CSATScore: Codable, Sendable {
    public let current: Double
    public let previous: Double
    public let responseCount: Int
    public let trendPct: Double

    enum CodingKeys: String, CodingKey {
        case current
        case previous
        case responseCount = "response_count"
        case trendPct      = "trend_pct"
    }

    public init(current: Double, previous: Double,
                responseCount: Int, trendPct: Double) {
        self.current = current
        self.previous = previous
        self.responseCount = responseCount
        self.trendPct = trendPct
    }
}

// MARK: - NPSScore

public struct NPSScore: Codable, Sendable {
    public let current: Int
    public let previous: Int
    public let promoterPct: Double
    public let detractorPct: Double
    public let themes: [String]

    public var passivePct: Double { max(0, 100.0 - promoterPct - detractorPct) }

    enum CodingKeys: String, CodingKey {
        case current
        case previous
        case promoterPct   = "promoter_pct"
        case detractorPct  = "detractor_pct"
        case themes
    }

    public init(current: Int, previous: Int,
                promoterPct: Double, detractorPct: Double,
                themes: [String]) {
        self.current = current
        self.previous = previous
        self.promoterPct = promoterPct
        self.detractorPct = detractorPct
        self.themes = themes
    }
}

// MARK: - DrillThroughRecord

public struct DrillThroughRecord: Codable, Sendable, Identifiable {
    public let id: Int64
    public let label: String
    public let detail: String?
    public let amountCents: Int64?

    public var amountDollars: Double? {
        guard let c = amountCents else { return nil }
        return Double(c) / 100.0
    }

    enum CodingKeys: String, CodingKey {
        case id, label, detail
        case amountCents = "amount_cents"
    }

    public init(id: Int64, label: String, detail: String?, amountCents: Int64?) {
        self.id = id
        self.label = label
        self.detail = detail
        self.amountCents = amountCents
    }
}

// MARK: - ScheduledReport

public struct ScheduledReport: Codable, Sendable, Identifiable {
    public let id: Int64
    public let reportType: String
    public let frequency: ScheduleFrequency
    public let recipientEmails: [String]
    public let isActive: Bool
    public let nextRunAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportType       = "report_type"
        case frequency
        case recipientEmails  = "recipient_emails"
        case isActive         = "is_active"
        case nextRunAt        = "next_run_at"
    }

    public init(id: Int64, reportType: String, frequency: ScheduleFrequency,
                recipientEmails: [String], isActive: Bool, nextRunAt: String?) {
        self.id = id
        self.reportType = reportType
        self.frequency = frequency
        self.recipientEmails = recipientEmails
        self.isActive = isActive
        self.nextRunAt = nextRunAt
    }
}

public enum ScheduleFrequency: String, Codable, Sendable, CaseIterable {
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"

    public var displayName: String {
        switch self {
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

// MARK: - DateRangePreset

public enum DateRangePreset: String, Sendable, CaseIterable, Identifiable {
    case sevenDays   = "7D"
    case thirtyDays  = "30D"
    case ninetyDays  = "90D"
    case custom      = "Custom"

    public var id: String { rawValue }

    public var displayLabel: String { rawValue }

    /// Returns (from, to) ISO-8601 date strings for API queries.
    public func dateRange(relativeTo now: Date = Date()) -> (from: String, to: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let to = formatter.string(from: now)
        let days: Int
        switch self {
        case .sevenDays:   days = 7
        case .thirtyDays:  days = 30
        case .ninetyDays:  days = 90
        case .custom:      days = 30 // fallback; caller provides custom dates
        }
        let from = formatter.string(from: now.addingTimeInterval(-Double(days) * 86400))
        return (from, to)
    }
}

// MARK: - ExpensesReport
//
// Derived from GET /api/v1/reports/dashboard-kpis `data`.
// Server fields used: expenses (total), daily_sales[].sale (to compute net).
// No dedicated expenses endpoint exists — we extract from dashboard-kpis.

public struct ExpensesReport: Sendable {
    /// Total expenses in dollars for the period.
    public let totalDollars: Double
    /// Total revenue in dollars for the same period (for margin).
    public let revenueDollars: Double
    /// Gross profit = revenue - expenses.
    public var grossProfitDollars: Double { revenueDollars - totalDollars }
    /// Margin % = (revenue - expenses) / revenue * 100, nil when revenue == 0.
    public var marginPct: Double? {
        guard revenueDollars > 0 else { return nil }
        return (grossProfitDollars / revenueDollars) * 100.0
    }
    /// Daily breakdown points for the bar chart.
    public let dailyBreakdown: [ExpenseDayPoint]

    public init(totalDollars: Double, revenueDollars: Double,
                dailyBreakdown: [ExpenseDayPoint] = []) {
        self.totalDollars = totalDollars
        self.revenueDollars = revenueDollars
        self.dailyBreakdown = dailyBreakdown
    }
}

public struct ExpenseDayPoint: Sendable, Identifiable {
    public let id: String
    public let date: String
    /// Revenue for this day in dollars.
    public let revenue: Double
    /// COGS for this day in dollars.
    public let cogs: Double
    /// Net profit (revenue - cogs).
    public var netProfit: Double { revenue - cogs }

    public init(date: String, revenue: Double, cogs: Double) {
        self.id = date
        self.date = date
        self.revenue = revenue
        self.cogs = cogs
    }
}

// MARK: - InventoryReport
//
// Maps to GET /api/v1/reports/inventory `data`.
// Server fields: lowStock[], valueSummary[], outOfStock, topMoving[].

public struct InventoryReport: Sendable {
    public let outOfStockCount: Int
    public let lowStockCount: Int
    public let valueSummary: [InventoryValueEntry]
    public let topMoving: [InventoryMovementItem]

    public init(outOfStockCount: Int, lowStockCount: Int,
                valueSummary: [InventoryValueEntry],
                topMoving: [InventoryMovementItem]) {
        self.outOfStockCount = outOfStockCount
        self.lowStockCount = lowStockCount
        self.valueSummary = valueSummary
        self.topMoving = topMoving
    }
}

public struct InventoryValueEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let itemType: String
    public let itemCount: Int
    public let totalUnits: Int
    public let totalCostValue: Double
    public let totalRetailValue: Double

    enum CodingKeys: String, CodingKey {
        case itemType        = "item_type"
        case itemCount       = "item_count"
        case totalUnits      = "total_units"
        case totalCostValue  = "total_cost_value"
        case totalRetailValue = "total_retail_value"
    }

    public init(itemType: String, itemCount: Int, totalUnits: Int,
                totalCostValue: Double, totalRetailValue: Double) {
        self.id = itemType
        self.itemType = itemType
        self.itemCount = itemCount
        self.totalUnits = totalUnits
        self.totalCostValue = totalCostValue
        self.totalRetailValue = totalRetailValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.itemType = (try? c.decode(String.self, forKey: .itemType)) ?? ""
        self.id = self.itemType
        self.itemCount = (try? c.decode(Int.self, forKey: .itemCount)) ?? 0
        self.totalUnits = (try? c.decode(Int.self, forKey: .totalUnits)) ?? 0
        self.totalCostValue = (try? c.decode(Double.self, forKey: .totalCostValue)) ?? 0
        self.totalRetailValue = (try? c.decode(Double.self, forKey: .totalRetailValue)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(itemType, forKey: .itemType)
        try c.encode(itemCount, forKey: .itemCount)
        try c.encode(totalUnits, forKey: .totalUnits)
        try c.encode(totalCostValue, forKey: .totalCostValue)
        try c.encode(totalRetailValue, forKey: .totalRetailValue)
    }
}

public struct InventoryMovementItem: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let sku: String?
    /// Units used/sold in the analysis period.
    public let usedQty: Int
    /// Current in-stock count.
    public let inStock: Int

    enum CodingKeys: String, CodingKey {
        case name
        case sku
        case usedQty = "used_qty"
        case inStock = "in_stock"
    }

    public init(name: String, sku: String?, usedQty: Int, inStock: Int) {
        self.id = name
        self.name = name
        self.sku = sku
        self.usedQty = usedQty
        self.inStock = inStock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.id = self.name
        self.sku = try? c.decode(String.self, forKey: .sku)
        self.usedQty = (try? c.decode(Int.self, forKey: .usedQty)) ?? 0
        self.inStock = (try? c.decode(Int.self, forKey: .inStock)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(sku, forKey: .sku)
        try c.encode(usedQty, forKey: .usedQty)
        try c.encode(inStock, forKey: .inStock)
    }
}

// MARK: - SalesReportResponse
//
// Envelope for GET /api/v1/reports/sales.

public struct SalesReportResponse: Decodable, Sendable {
    public let rows: [RevenuePoint]
    public let totals: SalesTotals
    public let byMethod: [PaymentMethodPoint]

    enum CodingKeys: String, CodingKey {
        case rows
        case totals
        case byMethod = "byMethod"
    }

    public init(rows: [RevenuePoint] = [], totals: SalesTotals = SalesTotals(),
                byMethod: [PaymentMethodPoint] = []) {
        self.rows = rows
        self.totals = totals
        self.byMethod = byMethod
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rows = (try? c.decode([RevenuePoint].self, forKey: .rows)) ?? []
        self.totals = (try? c.decode(SalesTotals.self, forKey: .totals)) ?? SalesTotals()
        self.byMethod = (try? c.decode([PaymentMethodPoint].self, forKey: .byMethod)) ?? []
    }
}

public struct SalesTotals: Decodable, Sendable {
    public let totalRevenue: Double
    public let revenueChangePct: Double?
    public let totalInvoices: Int
    public let uniqueCustomers: Int

    enum CodingKeys: String, CodingKey {
        case totalRevenue    = "total_revenue"
        case revenueChangePct = "revenue_change_pct"
        case totalInvoices   = "total_invoices"
        case uniqueCustomers = "unique_customers"
    }

    public init(totalRevenue: Double = 0, revenueChangePct: Double? = nil,
                totalInvoices: Int = 0, uniqueCustomers: Int = 0) {
        self.totalRevenue = totalRevenue
        self.revenueChangePct = revenueChangePct
        self.totalInvoices = totalInvoices
        self.uniqueCustomers = uniqueCustomers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalRevenue = (try? c.decode(Double.self, forKey: .totalRevenue)) ?? 0
        self.revenueChangePct = try? c.decode(Double.self, forKey: .revenueChangePct)
        self.totalInvoices = (try? c.decode(Int.self, forKey: .totalInvoices)) ?? 0
        self.uniqueCustomers = (try? c.decode(Int.self, forKey: .uniqueCustomers)) ?? 0
    }
}

public struct PaymentMethodPoint: Decodable, Sendable, Identifiable {
    public let id: String
    public let method: String
    public let revenue: Double
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case method
        case revenue
        case count
    }

    public init(method: String, revenue: Double, count: Int) {
        self.id = method
        self.method = method
        self.revenue = revenue
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.method = (try? c.decode(String.self, forKey: .method)) ?? "Other"
        self.id = self.method
        self.revenue = (try? c.decode(Double.self, forKey: .revenue)) ?? 0
        self.count = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }
}

// MARK: - TicketsReportResponse
//
// Envelope for GET /api/v1/reports/tickets.

public struct TicketsReportResponse: Decodable, Sendable {
    public let byStatus: [TicketStatusPoint]
    public let summary: TicketsSummary

    enum CodingKeys: String, CodingKey {
        case byStatus = "byStatus"
        case summary
    }

    public init(byStatus: [TicketStatusPoint] = [], summary: TicketsSummary = TicketsSummary()) {
        self.byStatus = byStatus
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.byStatus = (try? c.decode([TicketStatusPoint].self, forKey: .byStatus)) ?? []
        self.summary = (try? c.decode(TicketsSummary.self, forKey: .summary)) ?? TicketsSummary()
    }
}

public struct TicketsSummary: Decodable, Sendable {
    public let totalCreated: Int
    public let totalClosed: Int
    public let avgTicketValue: Double

    enum CodingKeys: String, CodingKey {
        case totalCreated  = "total_created"
        case totalClosed   = "total_closed"
        case avgTicketValue = "avg_ticket_value"
    }

    public init(totalCreated: Int = 0, totalClosed: Int = 0, avgTicketValue: Double = 0) {
        self.totalCreated = totalCreated
        self.totalClosed = totalClosed
        self.avgTicketValue = avgTicketValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalCreated = (try? c.decode(Int.self, forKey: .totalCreated)) ?? 0
        self.totalClosed = (try? c.decode(Int.self, forKey: .totalClosed)) ?? 0
        self.avgTicketValue = (try? c.decode(Double.self, forKey: .avgTicketValue)) ?? 0
    }
}

// MARK: - EmployeesReportResponse
//
// Envelope for GET /api/v1/reports/employees.

public struct EmployeesReportResponse: Decodable, Sendable {
    public let rows: [EmployeePerf]

    enum CodingKeys: String, CodingKey { case rows }

    public init(rows: [EmployeePerf] = []) { self.rows = rows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rows = (try? c.decode([EmployeePerf].self, forKey: .rows)) ?? []
    }
}

// MARK: - InventoryReportResponse
//
// Envelope for GET /api/v1/reports/inventory.

public struct InventoryReportResponse: Decodable, Sendable {
    public let lowStock: [InventoryMovementItem]
    public let valueSummary: [InventoryValueEntry]
    public let outOfStock: Int
    public let topMoving: [InventoryMovementItem]

    enum CodingKeys: String, CodingKey {
        case lowStock    = "lowStock"
        case valueSummary = "valueSummary"
        case outOfStock  = "outOfStock"
        case topMoving   = "topMoving"
    }

    public init(lowStock: [InventoryMovementItem] = [],
                valueSummary: [InventoryValueEntry] = [],
                outOfStock: Int = 0,
                topMoving: [InventoryMovementItem] = []) {
        self.lowStock = lowStock
        self.valueSummary = valueSummary
        self.outOfStock = outOfStock
        self.topMoving = topMoving
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lowStock = (try? c.decode([InventoryMovementItem].self, forKey: .lowStock)) ?? []
        self.valueSummary = (try? c.decode([InventoryValueEntry].self, forKey: .valueSummary)) ?? []
        self.outOfStock = (try? c.decode(Int.self, forKey: .outOfStock)) ?? 0
        self.topMoving = (try? c.decode([InventoryMovementItem].self, forKey: .topMoving)) ?? []
    }
}

// MARK: - DashboardKpisResponse
//
// Envelope for GET /api/v1/reports/dashboard-kpis `data`.
// Used to extract expenses and daily sales.

public struct DashboardKpisResponse: Decodable, Sendable {
    public let totalSales: Double
    public let expenses: Double
    public let cogs: Double
    public let dailySales: [DailySalePoint]

    enum CodingKeys: String, CodingKey {
        case totalSales  = "total_sales"
        case expenses
        case cogs
        case dailySales  = "daily_sales"
    }

    public init(totalSales: Double = 0, expenses: Double = 0,
                cogs: Double = 0, dailySales: [DailySalePoint] = []) {
        self.totalSales = totalSales
        self.expenses = expenses
        self.cogs = cogs
        self.dailySales = dailySales
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalSales = (try? c.decode(Double.self, forKey: .totalSales)) ?? 0
        self.expenses = (try? c.decode(Double.self, forKey: .expenses)) ?? 0
        self.cogs = (try? c.decode(Double.self, forKey: .cogs)) ?? 0
        self.dailySales = (try? c.decode([DailySalePoint].self, forKey: .dailySales)) ?? []
    }
}

public struct DailySalePoint: Decodable, Sendable, Identifiable {
    public let id: String
    public let date: String
    public let sale: Double
    public let cogs: Double
    public let netProfit: Double
    public let marginPct: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case sale
        case cogs
        case netProfit  = "net_profit"
        case marginPct  = "margin"
    }

    public init(date: String, sale: Double, cogs: Double,
                netProfit: Double, marginPct: Double?) {
        self.id = date
        self.date = date
        self.sale = sale
        self.cogs = cogs
        self.netProfit = netProfit
        self.marginPct = marginPct
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = (try? c.decode(String.self, forKey: .date)) ?? ""
        self.id = self.date
        self.sale = (try? c.decode(Double.self, forKey: .sale)) ?? 0
        self.cogs = (try? c.decode(Double.self, forKey: .cogs)) ?? 0
        self.netProfit = (try? c.decode(Double.self, forKey: .netProfit)) ?? 0
        self.marginPct = try? c.decode(Double.self, forKey: .marginPct)
    }
}
