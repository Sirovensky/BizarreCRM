import Foundation
import Core

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

    public init(openTickets: Int = 0, revenueToday: Double = 0,
                closedToday: Int = 0, ticketsCreatedToday: Int = 0,
                appointmentsToday: Int = 0, avgRepairHours: Double? = nil,
                inventoryValue: Double = 0,
                lowStockCount: Int? = nil) {
        self.openTickets = openTickets
        self.revenueToday = revenueToday
        self.closedToday = closedToday
        self.ticketsCreatedToday = ticketsCreatedToday
        self.appointmentsToday = appointmentsToday
        self.avgRepairHours = avgRepairHours
        self.inventoryValue = inventoryValue
        self.lowStockCount = lowStockCount
    }

    /// Defensive decode — the server payload returns `revenue_trend` as an
    /// array of `{month, revenue}` objects (not a Double MoM delta). The
    /// 12-point sparkline uses `DashboardBIPayload.revenueTrend`. For this
    /// summary we silently ignore the array shape and use `try?` on every
    /// field so a single typeMismatch on one key doesn't blow up the whole
    /// dashboard fetch.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.openTickets         = (try? c.decode(Int.self, forKey: .openTickets)) ?? 0
        self.revenueToday        = (try? c.decode(Double.self, forKey: .revenueToday)) ?? 0
        self.closedToday         = (try? c.decode(Int.self, forKey: .closedToday)) ?? 0
        self.ticketsCreatedToday = (try? c.decode(Int.self, forKey: .ticketsCreatedToday)) ?? 0
        self.appointmentsToday   = (try? c.decode(Int.self, forKey: .appointmentsToday)) ?? 0
        self.avgRepairHours      = try? c.decode(Double.self, forKey: .avgRepairHours)
        self.inventoryValue      = (try? c.decode(Double.self, forKey: .inventoryValue)) ?? 0
        self.lowStockCount       = try? c.decode(Int.self, forKey: .lowStockCount)
    }

    enum CodingKeys: String, CodingKey {
        case openTickets         = "open_tickets"
        case revenueToday        = "revenue_today"
        case closedToday         = "closed_today"
        case ticketsCreatedToday = "tickets_created_today"
        case appointmentsToday   = "appointments_today"
        case avgRepairHours      = "avg_repair_hours"
        case inventoryValue      = "inventory_value"
        case lowStockCount       = "low_stock_count"
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

    // MARK: - §3.7 Announcements
    /// Fetch system announcements since `lastSeenId`. Returns [] if the endpoint doesn't exist yet.
    func systemAnnouncements(since lastSeenId: Int? = nil) async throws -> [SystemAnnouncement] {
        var query: [URLQueryItem] = []
        if let id = lastSeenId {
            query.append(URLQueryItem(name: "since", value: "\(id)"))
        }
        return try await get("/api/v1/system/announcements", query: query, as: [SystemAnnouncement].self)
    }

    // MARK: - §3.12 SMS unread count
    /// Quick count used by the Unread-SMS tile and tab badge. Returns 0 on failure.
    func smsUnreadCount() async throws -> Int {
        let payload = try await get("/api/v1/sms/unread-count", as: SmsUnreadCountPayload.self)
        return payload.count
    }

    // MARK: - §3.12 Team Inbox count
    /// `GET /inbox` count — number of unread team-inbox threads when the tenant
    /// has team inbox enabled. Returns nil when the endpoint is absent (404) so
    /// the tile can hide itself for tenants without team inbox.
    func teamInboxCount() async throws -> Int? {
        do {
            let payload = try await get("/api/v1/inbox", as: TeamInboxCountPayload.self)
            return payload.unreadCount
        } catch let error as URLError where error.code == .badServerResponse {
            return nil
        } catch {
            // 404 / feature-not-enabled → nil (tile hidden)
            AppLog.networking.debug("teamInboxCount: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - §3.7 Announcement model

public struct SystemAnnouncement: Decodable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let body: String
    public let createdAt: String

    public init(id: Int, title: String, body: String, createdAt: String = "") {
        self.id = id; self.title = title; self.body = body; self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = (try? c.decode(Int.self,    forKey: .id))        ?? 0
        self.title     = (try? c.decode(String.self, forKey: .title))     ?? ""
        self.body      = (try? c.decode(String.self, forKey: .body))      ?? ""
        self.createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case createdAt = "created_at"
    }
}

// MARK: - §3.12 SMS unread count payload

public struct SmsUnreadCountPayload: Decodable, Sendable {
    public let count: Int

    public init(count: Int = 0) { self.count = count }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.count = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case count }
}

// MARK: - §3.12 Team Inbox count payload

public struct TeamInboxCountPayload: Decodable, Sendable {
    /// Total unread thread count across all team-inbox threads.
    public let unreadCount: Int

    public init(unreadCount: Int = 0) { self.unreadCount = unreadCount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.unreadCount = (try? c.decode(Int.self, forKey: .unreadCount))
            ?? (try? c.decode(Int.self, forKey: .count)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
        case count       // fallback if server sends just "count"
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
