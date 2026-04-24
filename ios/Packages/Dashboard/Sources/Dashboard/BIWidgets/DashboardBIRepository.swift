import Foundation
import Networking

// MARK: - DashboardBIRepository
//
// Minimal read-only data access for the BI widgets in §3.2.
//
// Grounded against packages/server/src/routes/reports.routes.ts:
//   GET /api/v1/reports/dashboard            — revenue_trend, status_counts, staff_leaderboard, top_services
//   GET /api/v1/reports/tech-leaderboard     — line 2178  → TechLeaderboardPayload
//   GET /api/v1/reports/repeat-customers     — line 2245  → RepeatCustomersPayload
//   GET /api/v1/reports/cash-trapped         — line 2381  → CashTrappedPayload
//   GET /api/v1/reports/churn               — line 2538  → ChurnPayload

// MARK: - Protocol

public protocol DashboardBIRepository: Sendable {
    func fetchDashboardSummary() async throws -> DashboardSummaryPayload
    func fetchTechLeaderboard(period: TechLeaderboardPeriod) async throws -> TechLeaderboardPayload
    func fetchTopCustomers() async throws -> RepeatCustomersPayload
    func fetchCashTrapped() async throws -> CashTrappedPayload
    func fetchChurn() async throws -> ChurnPayload
}

// MARK: - Live implementation

public actor DashboardBIRepositoryImpl: DashboardBIRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func fetchDashboardSummary() async throws -> DashboardSummaryPayload {
        try await api.get("/api/v1/reports/dashboard", as: DashboardSummaryPayload.self)
    }

    public func fetchTechLeaderboard(period: TechLeaderboardPeriod = .month) async throws -> TechLeaderboardPayload {
        let query = [URLQueryItem(name: "period", value: period.rawValue)]
        return try await api.get("/api/v1/reports/tech-leaderboard", query: query, as: TechLeaderboardPayload.self)
    }

    public func fetchTopCustomers() async throws -> RepeatCustomersPayload {
        try await api.get("/api/v1/reports/repeat-customers", as: RepeatCustomersPayload.self)
    }

    public func fetchCashTrapped() async throws -> CashTrappedPayload {
        try await api.get("/api/v1/reports/cash-trapped", as: CashTrappedPayload.self)
    }

    public func fetchChurn() async throws -> ChurnPayload {
        try await api.get("/api/v1/reports/churn", as: ChurnPayload.self)
    }
}

// MARK: - Payloads (mirrors server response data objects; decoder uses .convertFromSnakeCase)

// GET /api/v1/reports/dashboard → data.revenue_trend[], data.status_counts[]
public struct DashboardSummaryPayload: Decodable, Sendable {
    public let revenueTrend: [RevenueTrendPoint]
    public let statusCounts: [TicketStatusCount]

    public init(revenueTrend: [RevenueTrendPoint] = [], statusCounts: [TicketStatusCount] = []) {
        self.revenueTrend = revenueTrend
        self.statusCounts = statusCounts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.revenueTrend = (try? c.decode([RevenueTrendPoint].self, forKey: .revenueTrend)) ?? []
        self.statusCounts = (try? c.decode([TicketStatusCount].self, forKey: .statusCounts)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case revenueTrend  = "revenue_trend"
        case statusCounts  = "status_counts"
    }
}

public struct RevenueTrendPoint: Decodable, Sendable, Identifiable {
    public let month: String
    public let revenue: Double
    public var id: String { month }

    public init(month: String, revenue: Double) {
        self.month = month
        self.revenue = revenue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.month   = (try? c.decode(String.self, forKey: .month))   ?? ""
        self.revenue = (try? c.decode(Double.self, forKey: .revenue)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case month, revenue }
}

public struct TicketStatusCount: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let color: String?
    public let count: Int
    public let isClosed: Bool
    public let isCancelled: Bool

    public init(id: Int, name: String, color: String?, count: Int,
                isClosed: Bool = false, isCancelled: Bool = false) {
        self.id = id; self.name = name; self.color = color; self.count = count
        self.isClosed = isClosed; self.isCancelled = isCancelled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id          = (try? c.decode(Int.self,    forKey: .id))          ?? 0
        self.name        = (try? c.decode(String.self, forKey: .name))        ?? ""
        self.color       = try? c.decode(String.self, forKey: .color)
        self.count       = (try? c.decode(Int.self,    forKey: .count))       ?? 0
        self.isClosed    = (try? c.decode(Bool.self,   forKey: .isClosed))    ?? false
        self.isCancelled = (try? c.decode(Bool.self,   forKey: .isCancelled)) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, count
        case isClosed    = "is_closed"
        case isCancelled = "is_cancelled"
    }
}

// GET /api/v1/reports/tech-leaderboard → data.leaderboard[]
public enum TechLeaderboardPeriod: String, Sendable {
    case week = "week"
    case month = "month"
    case quarter = "quarter"
}

public struct TechLeaderboardPayload: Decodable, Sendable {
    public let period: String
    public let leaderboard: [TechLeaderboardEntry]

    public init(period: String = "month", leaderboard: [TechLeaderboardEntry] = []) {
        self.period = period; self.leaderboard = leaderboard
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.period      = (try? c.decode(String.self,                forKey: .period))      ?? "month"
        self.leaderboard = (try? c.decode([TechLeaderboardEntry].self, forKey: .leaderboard)) ?? []
    }

    enum CodingKeys: String, CodingKey { case period, leaderboard }
}

public struct TechLeaderboardEntry: Decodable, Sendable, Identifiable {
    public let userId: Int
    public let name: String
    public let ticketsClosed: Int
    public let revenue: Double
    public let csatAvg: Double?
    public var id: Int { userId }

    public init(userId: Int, name: String, ticketsClosed: Int, revenue: Double, csatAvg: Double? = nil) {
        self.userId = userId; self.name = name; self.ticketsClosed = ticketsClosed
        self.revenue = revenue; self.csatAvg = csatAvg
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.userId        = (try? c.decode(Int.self,    forKey: .userId))        ?? 0
        self.name          = (try? c.decode(String.self, forKey: .name))          ?? ""
        self.ticketsClosed = (try? c.decode(Int.self,    forKey: .ticketsClosed)) ?? 0
        self.revenue       = (try? c.decode(Double.self, forKey: .revenue))       ?? 0
        self.csatAvg       = try? c.decode(Double.self, forKey: .csatAvg)
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"; case name
        case ticketsClosed = "tickets_closed"; case revenue
        case csatAvg = "csat_avg"
    }
}

// GET /api/v1/reports/repeat-customers → data.top[]
public struct RepeatCustomersPayload: Decodable, Sendable {
    public let top: [TopCustomerEntry]
    public let combinedSharePct: Double
    public let totalRevenue: Double

    public init(top: [TopCustomerEntry] = [], combinedSharePct: Double = 0, totalRevenue: Double = 0) {
        self.top = top; self.combinedSharePct = combinedSharePct; self.totalRevenue = totalRevenue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.top              = (try? c.decode([TopCustomerEntry].self, forKey: .top))              ?? []
        self.combinedSharePct = (try? c.decode(Double.self,             forKey: .combinedSharePct)) ?? 0
        self.totalRevenue     = (try? c.decode(Double.self,             forKey: .totalRevenue))     ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case top
        case combinedSharePct = "combined_share_pct"
        case totalRevenue     = "total_revenue"
    }
}

public struct TopCustomerEntry: Decodable, Sendable, Identifiable {
    public let customerId: Int
    public let name: String
    public let ticketCount: Int
    public let totalSpent: Double
    public let sharePct: Double
    public var id: Int { customerId }

    public init(customerId: Int, name: String, ticketCount: Int, totalSpent: Double, sharePct: Double = 0) {
        self.customerId = customerId; self.name = name; self.ticketCount = ticketCount
        self.totalSpent = totalSpent; self.sharePct = sharePct
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.customerId  = (try? c.decode(Int.self,    forKey: .customerId))  ?? 0
        self.name        = (try? c.decode(String.self, forKey: .name))        ?? ""
        self.ticketCount = (try? c.decode(Int.self,    forKey: .ticketCount)) ?? 0
        self.totalSpent  = (try? c.decode(Double.self, forKey: .totalSpent))  ?? 0
        self.sharePct    = (try? c.decode(Double.self, forKey: .sharePct))    ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case customerId  = "customer_id"; case name
        case ticketCount = "ticket_count"
        case totalSpent  = "total_spent"
        case sharePct    = "share_pct"
    }
}

// GET /api/v1/reports/cash-trapped → data
public struct CashTrappedPayload: Decodable, Sendable {
    public let totalCashTrapped: Double
    public let itemCount: Int
    public let topOffenders: [CashTrappedItem]

    public init(totalCashTrapped: Double = 0, itemCount: Int = 0, topOffenders: [CashTrappedItem] = []) {
        self.totalCashTrapped = totalCashTrapped; self.itemCount = itemCount; self.topOffenders = topOffenders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalCashTrapped = (try? c.decode(Double.self,            forKey: .totalCashTrapped)) ?? 0
        self.itemCount        = (try? c.decode(Int.self,               forKey: .itemCount))        ?? 0
        self.topOffenders     = (try? c.decode([CashTrappedItem].self, forKey: .topOffenders))     ?? []
    }

    enum CodingKeys: String, CodingKey {
        case totalCashTrapped = "total_cash_trapped"
        case itemCount        = "item_count"
        case topOffenders     = "top_offenders"
    }
}

public struct CashTrappedItem: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let category: String?
    public let inStock: Int
    public let value: Double

    public init(id: Int, name: String, category: String?, inStock: Int, value: Double) {
        self.id = id; self.name = name; self.category = category; self.inStock = inStock; self.value = value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id       = (try? c.decode(Int.self,    forKey: .id))       ?? 0
        self.name     = (try? c.decode(String.self, forKey: .name))     ?? ""
        self.category = try? c.decode(String.self, forKey: .category)
        self.inStock  = (try? c.decode(Int.self,    forKey: .inStock))  ?? 0
        self.value    = (try? c.decode(Double.self, forKey: .value))    ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, value
        case inStock = "in_stock"
    }
}

// GET /api/v1/reports/churn → data
public struct ChurnPayload: Decodable, Sendable {
    public let thresholdDays: Int
    public let atRiskCount: Int
    public let customers: [ChurnCustomer]

    public init(thresholdDays: Int = 90, atRiskCount: Int = 0, customers: [ChurnCustomer] = []) {
        self.thresholdDays = thresholdDays; self.atRiskCount = atRiskCount; self.customers = customers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.thresholdDays = (try? c.decode(Int.self,            forKey: .thresholdDays)) ?? 90
        self.atRiskCount   = (try? c.decode(Int.self,            forKey: .atRiskCount))   ?? 0
        self.customers     = (try? c.decode([ChurnCustomer].self, forKey: .customers))    ?? []
    }

    enum CodingKeys: String, CodingKey {
        case thresholdDays = "threshold_days"
        case atRiskCount   = "at_risk_count"
        case customers
    }
}

public struct ChurnCustomer: Decodable, Sendable, Identifiable {
    public let customerId: Int
    public let name: String
    public let daysInactive: Int
    public let lifetimeSpent: Double
    public var id: Int { customerId }

    public init(customerId: Int, name: String, daysInactive: Int, lifetimeSpent: Double) {
        self.customerId = customerId; self.name = name
        self.daysInactive = daysInactive; self.lifetimeSpent = lifetimeSpent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.customerId    = (try? c.decode(Int.self,    forKey: .customerId))    ?? 0
        self.name          = (try? c.decode(String.self, forKey: .name))          ?? ""
        self.daysInactive  = (try? c.decode(Int.self,    forKey: .daysInactive))  ?? 0
        self.lifetimeSpent = (try? c.decode(Double.self, forKey: .lifetimeSpent)) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case customerId    = "customer_id"; case name
        case daysInactive  = "days_inactive"
        case lifetimeSpent = "lifetime_spent"
    }
}
