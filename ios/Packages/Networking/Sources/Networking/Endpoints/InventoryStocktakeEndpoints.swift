import Foundation

// MARK: - Stocktake DTOs

/// Request body for `POST /api/v1/inventory/stocktake/start`.
public struct StartStocktakeRequest: Encodable, Sendable {
    /// Optional category filter; nil means "all items".
    public let category: String?
    /// Optional location filter.
    public let location: String?
    public let name: String?

    public init(category: String? = nil, location: String? = nil, name: String? = nil) {
        self.category = category
        self.location = location
        self.name = name
    }
}

/// A single scanned/counted row in a stocktake session.
public struct StocktakeRow: Codable, Sendable, Identifiable {
    public let id: Int64
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

    public init(id: Int64, sku: String, productName: String? = nil,
                expectedQty: Int, actualQty: Int? = nil) {
        self.id = id
        self.sku = sku
        self.productName = productName
        self.expectedQty = expectedQty
        self.actualQty = actualQty
    }

    enum CodingKeys: String, CodingKey {
        case id, sku
        case productName  = "product_name"
        case expectedQty  = "expected_qty"
        case actualQty    = "actual_qty"
    }
}

/// A stocktake session header returned by the server.
public struct StocktakeSession: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String?
    public let status: String    // "open" | "finalized"
    public let category: String?
    public let location: String?
    public let createdAt: String?
    public let rows: [StocktakeRow]

    public init(id: Int64, name: String? = nil, status: String,
                category: String? = nil, location: String? = nil,
                createdAt: String? = nil, rows: [StocktakeRow] = []) {
        self.id = id
        self.name = name
        self.status = status
        self.category = category
        self.location = location
        self.createdAt = createdAt
        self.rows = rows
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, category, location, rows
        case createdAt = "created_at"
    }
}

/// One finalize line — the actual counted quantity + optional write-off reason.
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

/// Request body for `POST /api/v1/inventory/stocktake/:id/finalize`.
public struct FinalizeStocktakeRequest: Encodable, Sendable {
    public let lines: [FinalizeStocktakeLine]

    public init(lines: [FinalizeStocktakeLine]) {
        self.lines = lines
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /api/v1/inventory/stocktake/start` — create a new session.
    func startStocktake(_ req: StartStocktakeRequest) async throws -> StocktakeSession {
        try await post("/api/v1/inventory/stocktake/start",
                       body: req, as: StocktakeSession.self)
    }

    /// `GET /api/v1/inventory/stocktake` — list open + recent sessions.
    func listStocktakes() async throws -> [StocktakeSession] {
        try await get("/api/v1/inventory/stocktake", as: [StocktakeSession].self)
    }

    /// `GET /api/v1/inventory/stocktake/:id` — session detail with rows.
    func stocktakeSession(id: Int64) async throws -> StocktakeSession {
        try await get("/api/v1/inventory/stocktake/\(id)", as: StocktakeSession.self)
    }

    /// `POST /api/v1/inventory/stocktake/:id/finalize`
    func finalizeStocktake(id: Int64, request: FinalizeStocktakeRequest) async throws -> CreatedResource {
        try await post("/api/v1/inventory/stocktake/\(id)/finalize",
                       body: request, as: CreatedResource.self)
    }
}
