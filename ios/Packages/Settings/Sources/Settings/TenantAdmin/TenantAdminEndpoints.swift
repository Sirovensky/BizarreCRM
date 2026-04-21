import Foundation
import Networking

// MARK: - DTOs

public struct TenantInfo: Decodable, Sendable {
    public let id: String
    public let slug: String
    public let name: String
    public let createdAt: Date
    public let plan: String
    public let planRenewalDate: Date?
    public let isActive: Bool

    public init(
        id: String,
        slug: String,
        name: String,
        createdAt: Date,
        plan: String,
        planRenewalDate: Date?,
        isActive: Bool
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.createdAt = createdAt
        self.plan = plan
        self.planRenewalDate = planRenewalDate
        self.isActive = isActive
    }
}

public struct APIUsageStats: Decodable, Sendable {
    public let requestsToday: Int
    public let requestsThisMonth: Int
    public let dailyBuckets: [DailyBucket]

    public struct DailyBucket: Decodable, Sendable, Identifiable {
        public var id: String { date }
        public let date: String   // "YYYY-MM-DD"
        public let count: Int

        public init(date: String, count: Int) {
            self.date = date
            self.count = count
        }
    }

    public init(requestsToday: Int, requestsThisMonth: Int, dailyBuckets: [DailyBucket]) {
        self.requestsToday = requestsToday
        self.requestsThisMonth = requestsThisMonth
        self.dailyBuckets = dailyBuckets
    }
}

public struct ImpersonateRequest: Encodable, Sendable {
    public let userId: String
    public let reason: String
    public let managerPin: String

    public init(userId: String, reason: String, managerPin: String) {
        self.userId = userId
        self.reason = reason
        self.managerPin = managerPin
    }
}

public struct ImpersonateResponse: Decodable, Sendable {
    public let accessToken: String
    public let auditId: String
}

// MARK: - Endpoints

public extension APIClient {
    /// `GET /api/v1/tenant` — current tenant metadata.
    func fetchTenantInfo() async throws -> TenantInfo {
        try await get("/api/v1/tenant", as: TenantInfo.self)
    }

    /// `GET /api/v1/tenant/api-usage` — API usage statistics for the last 30 days.
    func fetchAPIUsage() async throws -> APIUsageStats {
        try await get("/api/v1/tenant/api-usage", as: APIUsageStats.self)
    }

    /// `POST /api/v1/tenant/impersonate` — impersonate a user with audit trail.
    /// Admin-only. Returns a short-lived access token.
    func impersonateUser(_ request: ImpersonateRequest) async throws -> ImpersonateResponse {
        try await post("/api/v1/tenant/impersonate", body: request, as: ImpersonateResponse.self)
    }
}
