import Foundation

/// Mirrors `GET /api/v1/reports/dashboard`. Server route:
///   packages/server/src/routes/reports.routes.ts:52
///
/// Decodes fields rendered on the iOS Dashboard. Extra keys are ignored
/// by JSONDecoder by default.
public struct DashboardSummary: Decodable, Sendable {
    // Core ticket metrics
    public let openTickets: Int
    public let revenueToday: Double
    public let closedToday: Int
    public let ticketsCreatedToday: Int
    public let appointmentsToday: Int
    public let avgRepairHours: Double?
    public let inventoryValue: Double

    // §3.1 expanded web-parity tiles — returned by GET /reports/dashboard
    // (server added these fields; decode defensively with defaults)
    public let lowStockCount: Int?
    public let revenueTrend: Double?          // MoM delta %

    public init(openTickets: Int = 0, revenueToday: Double = 0,
                closedToday: Int = 0, ticketsCreatedToday: Int = 0,
                appointmentsToday: Int = 0, avgRepairHours: Double? = nil,
                inventoryValue: Double = 0,
                lowStockCount: Int? = nil, revenueTrend: Double? = nil) {
        self.openTickets = openTickets
        self.revenueToday = revenueToday
        self.closedToday = closedToday
        self.ticketsCreatedToday = ticketsCreatedToday
        self.appointmentsToday = appointmentsToday
        self.avgRepairHours = avgRepairHours
        self.inventoryValue = inventoryValue
        self.lowStockCount = lowStockCount
        self.revenueTrend = revenueTrend
    }
}

/// Mirrors `GET /api/v1/reports/dashboard-kpis`. Server route:
///   packages/server/src/routes/reports.routes.ts:289
///
/// Returns the extended financial KPI set used by the web dashboard tiles.
/// §3.1: Sales today, Tax, Discounts, COGS, Net profit, Refunds, Expenses, Receivables.
public struct DashboardKPIs: Decodable, Sendable {
    public let totalSales: Double
    public let tax: Double
    public let discounts: Double
    public let cogs: Double
    public let netProfit: Double
    public let refunds: Double
    public let expenses: Double
    public let receivables: Double
    public let openTickets: Int?

    public init(totalSales: Double = 0, tax: Double = 0, discounts: Double = 0,
                cogs: Double = 0, netProfit: Double = 0, refunds: Double = 0,
                expenses: Double = 0, receivables: Double = 0, openTickets: Int? = nil) {
        self.totalSales = totalSales
        self.tax = tax
        self.discounts = discounts
        self.cogs = cogs
        self.netProfit = netProfit
        self.refunds = refunds
        self.expenses = expenses
        self.receivables = receivables
        self.openTickets = openTickets
    }
}

/// `GET /api/v1/reports/needs-attention`.
/// packages/server/src/routes/reports.routes.ts:1062
public struct NeedsAttention: Decodable, Sendable {
    public let staleTickets: [StaleTicket]
    public let overdueInvoices: [OverdueInvoice]
    public let missingPartsCount: Int
    public let lowStockCount: Int

    public init(staleTickets: [StaleTicket] = [],
                overdueInvoices: [OverdueInvoice] = [],
                missingPartsCount: Int = 0,
                lowStockCount: Int = 0) {
        self.staleTickets = staleTickets
        self.overdueInvoices = overdueInvoices
        self.missingPartsCount = missingPartsCount
        self.lowStockCount = lowStockCount
    }

    public struct StaleTicket: Decodable, Identifiable, Sendable, Hashable {
        public let id: Int64
        public let orderId: String
        public let customerName: String?
        public let daysStale: Int
        public let status: String?
    }

    public struct OverdueInvoice: Decodable, Identifiable, Sendable, Hashable {
        public let id: Int64
        public let orderId: String?
        public let customerName: String?
        public let amountDue: Double
        public let daysOverdue: Int
    }
}

// MARK: - Top-services payload (for TopSkusWidget — §3.2)

/// Minimal decode of `GET /api/v1/reports/dashboard` — only `top_services` field.
/// Declared in Networking so TopSkusWidget can call `api.dashboardTopServices()` from
/// a proper Endpoints file (§20 containment rule).
public struct DashboardTopServicesPayload: Decodable, Sendable {
    public let topServices: [TopServiceEntry]

    public init(topServices: [TopServiceEntry] = []) { self.topServices = topServices }

    enum CodingKeys: String, CodingKey { case topServices = "top_services" }
}

public struct TopServiceEntry: Decodable, Sendable, Identifiable {
    public let name: String
    public let count: Int
    public let revenue: Double
    public var id: String { name }

    public init(name: String, count: Int, revenue: Double) {
        self.name = name; self.count = count; self.revenue = revenue
    }

    enum CodingKeys: String, CodingKey { case name, count, revenue }
}

public extension APIClient {
    func dashboardSummary() async throws -> DashboardSummary {
        try await get("/api/v1/reports/dashboard", as: DashboardSummary.self)
    }

    /// §3.2 Top services — sourced from `GET /api/v1/reports/dashboard`.
    func dashboardTopServices() async throws -> [TopServiceEntry] {
        let payload = try await get("/api/v1/reports/dashboard", as: DashboardTopServicesPayload.self)
        return payload.topServices
    }

    func needsAttention() async throws -> NeedsAttention {
        try await get("/api/v1/reports/needs-attention", as: NeedsAttention.self)
    }

    /// §3.1 — Extended KPI set for web-parity tiles.
    /// Calls `GET /api/v1/reports/dashboard-kpis`.
    func dashboardKPIs() async throws -> DashboardKPIs {
        try await get("/api/v1/reports/dashboard-kpis", as: DashboardKPIs.self)
    }

    // MARK: - §59 Financial Dashboard — owner-PL summary
    //
    // Route: GET /api/v1/owner-pl/summary?from=YYYY-MM-DD&to=YYYY-MM-DD&rollup=day|week|month
    // Grounded against packages/server/src/routes/ownerPl.routes.ts:534
    // Envelope: { success: Bool, data: OwnerPLSummaryWire }
    // Admin-only; server validates role + rate-limits.

    func ownerPLSummary(from: String, to: String, rollup: String = "day") async throws -> OwnerPLSummaryWire {
        let query = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "rollup", value: rollup),
        ]
        return try await get("/api/v1/owner-pl/summary", query: query, as: OwnerPLSummaryWire.self)
    }
}

// MARK: - Wire DTOs for GET /api/v1/owner-pl/summary
//
// Defined in Networking so Dashboard (and future modules) can decode
// without a circular dependency. View-layer models (dollars, not cents)
// live in Dashboard/Financial/FinancialDashboardModels.swift.

public struct OwnerPLPeriodWire: Codable, Sendable {
    public let from: String
    public let to: String
    public let days: Int
}

public struct OwnerPLRevenueCentsWire: Codable, Sendable {
    public let grossCents: Int
    public let netCents: Int
    public let refundsCents: Int
    public let discountsCents: Int

    enum CodingKeys: String, CodingKey {
        case grossCents = "gross_cents"
        case netCents = "net_cents"
        case refundsCents = "refunds_cents"
        case discountsCents = "discounts_cents"
    }
}

public struct OwnerPLProfitWire: Codable, Sendable {
    public let cents: Int
    public let marginPct: Double

    enum CodingKeys: String, CodingKey {
        case cents
        case marginPct = "margin_pct"
    }
}

public struct OwnerPLARWire: Codable, Sendable {
    public let outstandingCents: Int
    public let overdueCents: Int
    public let truncated: Bool

    enum CodingKeys: String, CodingKey {
        case outstandingCents = "outstanding_cents"
        case overdueCents = "overdue_cents"
        case truncated
    }
}

public struct OwnerPLTopCustomerWire: Codable, Sendable {
    public let customerId: Int
    public let name: String
    public let revenueCents: Int

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case name
        case revenueCents = "revenue_cents"
    }
}

/// Full payload for GET /api/v1/owner-pl/summary — decoded from server JSON.
/// Monetary values are integer cents (SEC-H34); callers convert to dollars.
/// Codable (not just Decodable) so test spies can round-trip via JSONEncoder.
public struct OwnerPLSummaryWire: Codable, Sendable {
    public let period: OwnerPLPeriodWire
    public let revenue: OwnerPLRevenueCentsWire
    public let grossProfit: OwnerPLProfitWire
    public let netProfit: OwnerPLProfitWire
    public let ar: OwnerPLARWire
    public let topCustomers: [OwnerPLTopCustomerWire]

    enum CodingKeys: String, CodingKey {
        case period
        case revenue
        case grossProfit = "gross_profit"
        case netProfit = "net_profit"
        case ar
        case topCustomers = "top_customers"
    }
}
