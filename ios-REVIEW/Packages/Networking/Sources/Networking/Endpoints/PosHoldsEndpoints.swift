import Foundation

/// §16.3 — POS holds (save/resume cart) DTOs + APIClient wrappers.
///
/// Server route: `POST /api/v1/pos/holds` — save a hold.
///               `GET  /api/v1/pos/holds` — list open holds.
///
/// 404/501 fallback: if the endpoint hasn't shipped yet the wrappers
/// throw `APITransportError.httpStatus(404, …)` or `(501, …)` — callers
/// should catch those codes and show a "Coming soon" banner.

// MARK: - DTOs

/// A single line item in a hold payload. Uses snake_case CodingKeys to
/// match the server's JSON contract.
public struct PosHoldItem: Encodable, Sendable, Equatable {
    public let sku: String?
    public let name: String
    public let quantity: Int
    public let unitPriceCents: Int
    public let lineTotalCents: Int

    public init(
        sku: String?,
        name: String,
        quantity: Int,
        unitPriceCents: Int,
        lineTotalCents: Int
    ) {
        self.sku = sku
        self.name = name
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.lineTotalCents = lineTotalCents
    }

    enum CodingKeys: String, CodingKey {
        case sku
        case name
        case quantity
        case unitPriceCents  = "unit_price_cents"
        case lineTotalCents  = "line_total_cents"
    }
}

/// Request body for `POST /pos/holds`.
public struct CreatePosHoldRequest: Encodable, Sendable {
    public let items: [PosHoldItem]
    public let tenderNotes: String?
    public let customerId: Int64?
    public let note: String?

    public init(
        items: [PosHoldItem],
        tenderNotes: String? = nil,
        customerId: Int64? = nil,
        note: String? = nil
    ) {
        self.items = items
        self.tenderNotes = tenderNotes
        self.customerId = customerId
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case items
        case tenderNotes  = "tender_notes"
        case customerId   = "customer_id"
        case note
    }
}

/// A single hold row returned by `GET /pos/holds` or `POST /pos/holds`.
public struct PosHold: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let note: String?
    public let itemsCount: Int
    public let totalCents: Int
    public let createdAt: String

    public init(
        id: Int64,
        note: String?,
        itemsCount: Int,
        totalCents: Int,
        createdAt: String
    ) {
        self.id = id
        self.note = note
        self.itemsCount = itemsCount
        self.totalCents = totalCents
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case note
        case itemsCount  = "items_count"
        case totalCents  = "total_cents"
        case createdAt   = "created_at"
    }
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// Save the current cart as a hold on the server.
    /// Throws `APITransportError.httpStatus(404, _)` or `(501, _)` when
    /// the endpoint has not yet been deployed — callers should treat those
    /// as "Coming soon."
    func holdCart(_ payload: CreatePosHoldRequest) async throws -> PosHold {
        try await post("/api/v1/pos/holds", body: payload, as: PosHold.self)
    }

    /// List all open holds for the current register session.
    /// Same 404/501 fallback contract as `holdCart`.
    func listHolds() async throws -> [PosHold] {
        try await get("/api/v1/pos/holds", as: [PosHold].self)
    }
}
