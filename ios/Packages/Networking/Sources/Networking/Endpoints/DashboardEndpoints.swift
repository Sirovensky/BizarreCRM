import Foundation

/// Mirrors `GET /api/v1/reports/dashboard`. Server route:
///   packages/server/src/routes/reports.routes.ts:31
///
/// Only decoding fields we actually render on the iOS Dashboard MVP. Extra
/// keys are fine because JSONDecoder ignores unknown fields by default.
public struct DashboardSummary: Decodable, Sendable {
    public let openTickets: Int
    public let revenueToday: Double
    public let closedToday: Int
    public let ticketsCreatedToday: Int
    public let appointmentsToday: Int
    public let avgRepairHours: Double?
    public let inventoryValue: Double
}

/// `GET /api/v1/reports/needs-attention`.
/// packages/server/src/routes/reports.routes.ts:1062
public struct NeedsAttention: Decodable, Sendable {
    public let staleTickets: [StaleTicket]
    public let overdueInvoices: [OverdueInvoice]
    public let missingPartsCount: Int
    public let lowStockCount: Int

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

public extension APIClient {
    func dashboardSummary() async throws -> DashboardSummary {
        try await get("/api/v1/reports/dashboard", as: DashboardSummary.self)
    }

    func needsAttention() async throws -> NeedsAttention {
        try await get("/api/v1/reports/needs-attention", as: NeedsAttention.self)
    }
}
