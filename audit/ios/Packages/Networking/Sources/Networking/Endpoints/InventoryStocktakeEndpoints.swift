import Foundation

// MARK: - Stocktake DTOs
//
// Server ground truth: packages/server/src/routes/stocktake.routes.ts
// Mounted at: /api/v1/stocktake  (not /api/v1/inventory/stocktake)
//
// Lifecycle:
//   POST /api/v1/stocktake           — open a new count session
//   GET  /api/v1/stocktake           — list sessions
//   GET  /api/v1/stocktake/:id       — session + counts + variance
//   POST /api/v1/stocktake/:id/counts  — UPSERT a per-item scan
//   POST /api/v1/stocktake/:id/commit  — apply variance, close session (manager/admin)
//   POST /api/v1/stocktake/:id/cancel  — abandon without applying variance

/// Request body for `POST /api/v1/stocktake`.
public struct StartStocktakeRequest: Encodable, Sendable {
    /// Display name for the session (required by server).
    public let name: String
    /// Optional location filter — server column: location (nullable).
    public let location: String?
    /// Optional notes.
    public let notes: String?

    public init(name: String, location: String? = nil, notes: String? = nil) {
        self.name = name
        self.location = location
        self.notes = notes
    }
}

/// A single scanned/counted row in a stocktake session.
/// Maps to `StocktakeCountRow` from the server response.
public struct StocktakeRow: Codable, Sendable, Identifiable {
    public let id: Int64
    /// Maps to inventory_item_id; used as the key for UPSERT counts.
    public let inventoryItemId: Int64
    public let sku: String
    public let productName: String?
    public let expectedQty: Int
    /// Filled by the operator; nil = not yet counted.
    public var actualQty: Int?

    public var discrepancy: Int? {
        guard let actual = actualQty else { return nil }
        return actual - expectedQty
    }
    public var hasDiscrepancy: Bool { (discrepancy ?? 0) != 0 }

    public init(id: Int64, inventoryItemId: Int64 = 0, sku: String,
                productName: String? = nil, expectedQty: Int, actualQty: Int? = nil) {
        self.id = id
        self.inventoryItemId = inventoryItemId
        self.sku = sku
        self.productName = productName
        self.expectedQty = expectedQty
        self.actualQty = actualQty
    }

    enum CodingKeys: String, CodingKey {
        case id
        case inventoryItemId  = "inventory_item_id"
        case sku
        case productName      = "name"    // server returns `name` from the JOIN
        case expectedQty      = "expected_qty"
        case actualQty        = "counted_qty"
    }
}

/// A stocktake session header returned by the server.
/// Maps to the `StocktakeRow` interface in stocktake.routes.ts.
public struct StocktakeSession: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    /// "open" | "committed" | "cancelled"
    public let status: String
    public let location: String?
    public let openedAt: String?
    public let committedAt: String?
    /// Populated when fetching via GET /stocktake/:id (includes counts).
    public let counts: [StocktakeRow]

    public init(id: Int64, name: String = "", status: String,
                location: String? = nil, openedAt: String? = nil,
                committedAt: String? = nil, counts: [StocktakeRow] = []) {
        self.id = id
        self.name = name
        self.status = status
        self.location = location
        self.openedAt = openedAt
        self.committedAt = committedAt
        self.counts = counts
    }

    /// Expose counts as rows for backwards-compat with StocktakeScanViewModel.
    public var rows: [StocktakeRow] { counts }

    enum CodingKeys: String, CodingKey {
        case id, name, status, location, counts
        case openedAt    = "opened_at"
        case committedAt = "committed_at"
    }
}

/// Server `GET /stocktake/:id` returns `{ session, counts, summary }`.
public struct StocktakeDetailResponse: Decodable, Sendable {
    public let session: StocktakeSession
    public let counts: [StocktakeRow]
    public let summary: StocktakeSummaryDTO

    public struct StocktakeSummaryDTO: Decodable, Sendable {
        public let itemsCounted: Int
        public let itemsWithVariance: Int
        public let totalVariance: Int
        public let surplus: Int
        public let shortage: Int

        enum CodingKeys: String, CodingKey {
            case itemsCounted       = "items_counted"
            case itemsWithVariance  = "items_with_variance"
            case totalVariance      = "total_variance"
            case surplus, shortage
        }
    }
}

/// Request body for `POST /api/v1/stocktake/:id/counts`.
/// Re-scanning the same item replaces the prior row (UPSERT).
public struct UpsertStocktakeCountRequest: Encodable, Sendable {
    public let inventoryItemId: Int64
    public let countedQty: Int
    public let notes: String?

    public init(inventoryItemId: Int64, countedQty: Int, notes: String? = nil) {
        self.inventoryItemId = inventoryItemId
        self.countedQty = countedQty
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case inventoryItemId = "inventory_item_id"
        case countedQty      = "counted_qty"
        case notes
    }
}

/// Response from `POST /api/v1/stocktake/:id/counts`.
public struct UpsertStocktakeCountResponse: Decodable, Sendable {
    public let stocktakeId: Int64
    public let inventoryItemId: Int64
    public let name: String
    public let expectedQty: Int
    public let countedQty: Int
    public let variance: Int

    enum CodingKeys: String, CodingKey {
        case name, variance
        case stocktakeId    = "stocktake_id"
        case inventoryItemId = "inventory_item_id"
        case expectedQty    = "expected_qty"
        case countedQty     = "counted_qty"
    }
}

/// One finalize line — legacy field kept for offline queue encoding.
public struct FinalizeStocktakeLine: Encodable, Sendable {
    public let sku: String
    public let actualQty: Int
    public let writeOffReason: String?

    public init(sku: String, actualQty: Int, writeOffReason: String? = nil) {
        self.sku = sku
        self.actualQty = actualQty
        self.writeOffReason = writeOffReason
    }

    enum CodingKeys: String, CodingKey {
        case sku
        case actualQty      = "actual_qty"
        case writeOffReason = "write_off_reason"
    }
}

/// Offline-queue payload for a pending commit.
public struct FinalizeStocktakeRequest: Encodable, Sendable {
    public let lines: [FinalizeStocktakeLine]

    public init(lines: [FinalizeStocktakeLine]) {
        self.lines = lines
    }
}

// MARK: - Internal helpers

/// Empty body for POST requests that require no payload.
private struct _StocktakeEmptyBody: Encodable, Sendable {}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /api/v1/stocktake` — open a new count session.
    func startStocktake(_ req: StartStocktakeRequest) async throws -> StocktakeSession {
        try await post("/api/v1/stocktake", body: req, as: StocktakeSession.self)
    }

    /// `GET /api/v1/stocktake` — list sessions (most recent first, up to 200).
    func listStocktakes(status: String? = nil) async throws -> [StocktakeSession] {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        return try await get("/api/v1/stocktake", query: query.isEmpty ? nil : query,
                             as: [StocktakeSession].self)
    }

    /// `GET /api/v1/stocktake/:id` — session detail with all counts + variance.
    func stocktakeDetail(id: Int64) async throws -> StocktakeDetailResponse {
        try await get("/api/v1/stocktake/\(id)", as: StocktakeDetailResponse.self)
    }

    /// `GET /api/v1/stocktake/:id` — convenience overload returning a session-only view.
    func stocktakeSession(id: Int64) async throws -> StocktakeSession {
        let detail = try await stocktakeDetail(id: id)
        // Rebuild a session that carries the counts so existing code that reads
        // session.rows keeps working without changes.
        return StocktakeSession(
            id: detail.session.id,
            name: detail.session.name,
            status: detail.session.status,
            location: detail.session.location,
            openedAt: detail.session.openedAt,
            committedAt: detail.session.committedAt,
            counts: detail.counts
        )
    }

    /// `POST /api/v1/stocktake/:id/counts` — UPSERT a single item count.
    func upsertStocktakeCount(
        sessionId: Int64,
        request: UpsertStocktakeCountRequest
    ) async throws -> UpsertStocktakeCountResponse {
        try await post("/api/v1/stocktake/\(sessionId)/counts",
                       body: request,
                       as: UpsertStocktakeCountResponse.self)
    }

    /// `POST /api/v1/stocktake/:id/commit` — apply variance and close session.
    /// Requires admin or manager role (enforced server-side).
    func commitStocktake(id: Int64) async throws -> CreatedResource {
        return try await post("/api/v1/stocktake/\(id)/commit",
                              body: _StocktakeEmptyBody(),
                              as: CreatedResource.self)
    }

    /// `POST /api/v1/stocktake/:id/cancel` — abandon without applying variance.
    func cancelStocktake(id: Int64) async throws -> CreatedResource {
        return try await post("/api/v1/stocktake/\(id)/cancel",
                              body: _StocktakeEmptyBody(),
                              as: CreatedResource.self)
    }

    /// Compatibility shim: `finalizeStocktake` → `commitStocktake`.
    /// Old callers queued offline ops under "stocktake.finalize"; new ones use
    /// `commitStocktake` which calls the correct `/commit` path.
    @available(*, deprecated, renamed: "commitStocktake(id:)")
    func finalizeStocktake(id: Int64, request: FinalizeStocktakeRequest) async throws -> CreatedResource {
        try await commitStocktake(id: id)
    }
}
