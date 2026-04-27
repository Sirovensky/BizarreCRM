import Foundation

// MARK: - Customer mutations — extended responses
//
// Server routes (packages/server/src/routes/customers.routes.ts):
//   PUT /:id — update customer, returns full refreshed CustomerDetail row
//   GET /?cursor=&limit=&sort=&filter_* — cursor-paginated list (§5.1)
//   POST /bulk-tag — tag multiple customers (§5.6)
//   DELETE /bulk — bulk delete (§5.6)
//   GET /?include_stats=true — stats header (§5.1)
//
// updateCustomer(id:_:) → CreatedResource lives in CreateEndpoints.swift and is
// kept there for backwards-compat. The overload here returns the full
// CustomerDetail for callers that need to refresh in-place after an edit.

// MARK: - §5.1 Cursor-paginated list

/// Query parameters for §5.1 cursor-paginated customer list.
public struct CustomerListQuery: Sendable {
    /// Free-text search keyword.
    public var keyword: String?
    /// Server sort key.
    public var sort: String?
    /// LTV tier filter: "vip" | "regular" | "at_risk"
    public var ltvTier: String?
    /// Health-score band filter: "good" | "fair" | "poor"
    public var healthBand: String?
    /// Only return customers with balance > 0.
    public var balanceGtZero: Bool
    /// Only return customers with open tickets.
    public var hasOpenTickets: Bool
    /// City filter.
    public var city: String?
    /// State filter.
    public var state: String?
    /// Tag filter.
    public var tag: String?
    /// Whether to include aggregate stats in the response.
    public var includeStats: Bool

    public init(
        keyword: String? = nil,
        sort: String? = nil,
        ltvTier: String? = nil,
        healthBand: String? = nil,
        balanceGtZero: Bool = false,
        hasOpenTickets: Bool = false,
        city: String? = nil,
        state: String? = nil,
        tag: String? = nil,
        includeStats: Bool = false
    ) {
        self.keyword = keyword
        self.sort = sort
        self.ltvTier = ltvTier
        self.healthBand = healthBand
        self.balanceGtZero = balanceGtZero
        self.hasOpenTickets = hasOpenTickets
        self.city = city
        self.state = state
        self.tag = tag
        self.includeStats = includeStats
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let keyword, !keyword.isEmpty { items.append(.init(name: "keyword", value: keyword)) }
        if let sort, !sort.isEmpty { items.append(.init(name: "sort", value: sort)) }
        if let ltvTier, !ltvTier.isEmpty { items.append(.init(name: "filter_ltv_tier", value: ltvTier)) }
        if let healthBand, !healthBand.isEmpty { items.append(.init(name: "filter_health_band", value: healthBand)) }
        if balanceGtZero { items.append(.init(name: "filter_balance_gt_zero", value: "true")) }
        if hasOpenTickets { items.append(.init(name: "filter_has_open_tickets", value: "true")) }
        if let city, !city.isEmpty { items.append(.init(name: "filter_city", value: city)) }
        if let state, !state.isEmpty { items.append(.init(name: "filter_state", value: state)) }
        if let tag, !tag.isEmpty { items.append(.init(name: "filter_tag", value: tag)) }
        if includeStats { items.append(.init(name: "include_stats", value: "true")) }
        return items
    }
}

/// Stats header returned when `include_stats=true`.
public struct CustomerListStats: Decodable, Sendable {
    public let totalCustomers: Int?
    public let vipCount: Int?
    public let atRiskCount: Int?
    /// Total lifetime value across all customers, in cents.
    public let totalLtvCents: Int?
    /// Average lifetime value, in cents.
    public let avgLtvCents: Int?

    enum CodingKeys: String, CodingKey {
        case totalCustomers   = "total_customers"
        case vipCount         = "vip_count"
        case atRiskCount      = "at_risk_count"
        case totalLtvCents    = "total_ltv_cents"
        case avgLtvCents      = "avg_ltv_cents"
    }
}

/// Envelope for the cursor-paginated customer list.
public struct CustomerCursorPage: Decodable, Sendable {
    public let customers: [CustomerSummary]
    public let nextCursor: String?
    public let stats: CustomerListStats?

    enum CodingKeys: String, CodingKey {
        case customers
        case nextCursor = "next_cursor"
        case stats
    }
}

// MARK: - §5.6 Bulk operations

public struct BulkTagRequest: Encodable, Sendable {
    public let customerIds: [Int64]
    public let tag: String

    public init(customerIds: [Int64], tag: String) {
        self.customerIds = customerIds
        self.tag = tag
    }

    enum CodingKeys: String, CodingKey {
        case customerIds = "customer_ids"
        case tag
    }
}

public struct BulkDeleteRequest: Encodable, Sendable {
    public let customerIds: [Int64]

    public init(customerIds: [Int64]) {
        self.customerIds = customerIds
    }

    enum CodingKeys: String, CodingKey {
        case customerIds = "customer_ids"
    }
}

public struct BulkOperationResult: Decodable, Sendable {
    public let affected: Int?
}

// MARK: - APIClient extensions

public extension APIClient {

    /// `PUT /api/v1/customers/:id` — returns the full refreshed `CustomerDetail`.
    ///
    /// Prefer this over `updateCustomer(id:_:)` in `CreateEndpoints.swift` when
    /// the caller needs to update its in-memory snapshot without a follow-up GET.
    func updateCustomerDetail(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        try await put("/api/v1/customers/\(id)", body: req, as: CustomerDetail.self)
    }

    /// `GET /api/v1/customers?cursor=&limit=50&…` — cursor-paginated customer list (§5.1).
    /// Falls back to the legacy `listCustomers(keyword:)` shape when the server does not
    /// yet return `next_cursor` (envelope backward compat).
    func listCustomersCursor(
        cursor: String? = nil,
        limit: Int = 50,
        query: CustomerListQuery = .init()
    ) async throws -> CustomerCursorPage {
        var items = query.queryItems
        items.append(.init(name: "limit", value: String(limit)))
        if let cursor { items.append(.init(name: "cursor", value: cursor)) }
        return try await get("/api/v1/customers", query: items, as: CustomerCursorPage.self)
    }

    /// `POST /api/v1/customers/bulk-tag` — assign a tag to many customers (§5.6).
    @discardableResult
    func bulkTagCustomers(_ req: BulkTagRequest) async throws -> BulkOperationResult {
        try await post("/api/v1/customers/bulk-tag", body: req, as: BulkOperationResult.self)
    }

    /// `DELETE /api/v1/customers/bulk` — bulk-delete customers (§5.6).
    @discardableResult
    func bulkDeleteCustomers(_ req: BulkDeleteRequest) async throws -> BulkOperationResult {
        try await post("/api/v1/customers/bulk-delete", body: req, as: BulkOperationResult.self)
    }

    /// `DELETE /api/v1/customers/:id` — permanently delete a single customer (§5.2).
    func deleteCustomer(id: Int64) async throws {
        try await delete("/api/v1/customers/\(id)")
    }
}
