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

// MARK: - Held Carts (server-side persistent holds)
//
// The server exposes a richer held-carts table at `/api/v1/pos/held-carts`
// (see packages/server/src/routes/heldCarts.routes.ts).
// These wrappers are the authoritative network calls for §16.17 HeldCarts.

/// A held-cart row returned by the server.
public struct HeldCartRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let userId: Int64
    public let workstationId: Int64?
    public let label: String?
    /// JSON-serialised cart snapshot; parse with `PosCartSnapshotStore`.
    public let cartJson: String
    public let customerId: Int64?
    public let totalCents: Int?
    public let createdAt: String
    public let recalledAt: String?
    public let discardedAt: String?
    public let ownerFirstName: String?
    public let ownerLastName: String?

    public var ownerDisplayName: String {
        let parts = [ownerFirstName, ownerLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "Cashier" : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, label
        case userId          = "user_id"
        case workstationId   = "workstation_id"
        case cartJson        = "cart_json"
        case customerId      = "customer_id"
        case totalCents      = "total_cents"
        case createdAt       = "created_at"
        case recalledAt      = "recalled_at"
        case discardedAt     = "discarded_at"
        case ownerFirstName  = "owner_first_name"
        case ownerLastName   = "owner_last_name"
    }
}

/// Request body for `POST /api/v1/pos/held-carts`.
public struct CreateHeldCartRequest: Encodable, Sendable {
    /// JSON-serialised cart (max 64 KB, validated server-side).
    public let cartJson: String
    public let label: String?
    public let customerId: Int64?
    public let totalCents: Int?

    public init(cartJson: String, label: String? = nil, customerId: Int64? = nil, totalCents: Int? = nil) {
        self.cartJson = cartJson
        self.label = label
        self.customerId = customerId
        self.totalCents = totalCents
    }

    enum CodingKeys: String, CodingKey {
        case label
        case cartJson    = "cart_json"
        case customerId  = "customer_id"
        case totalCents  = "total_cents"
    }
}

public extension APIClient {
    /// List open held carts for the current user.
    func heldCarts() async throws -> [HeldCartRow] {
        try await get("/api/v1/pos/held-carts", as: [HeldCartRow].self)
    }

    /// Save a new held cart.
    func createHeldCart(_ body: CreateHeldCartRequest) async throws -> HeldCartRow {
        try await post("/api/v1/pos/held-carts", body: body, as: HeldCartRow.self)
    }

    /// Recall (restore) a held cart — marks `recalled_at` and returns the `cart_json`.
    func recallHeldCart(id: Int64) async throws -> HeldCartRow {
        try await post("/api/v1/pos/held-carts/\(id)/recall", body: EmptyBody(), as: HeldCartRow.self)
    }

    /// Soft-delete (discard) a held cart.
    func discardHeldCart(id: Int64) async throws {
        try await delete("/api/v1/pos/held-carts/\(id)")
    }
}

/// Empty encodable body for POST calls that send no payload.
private struct EmptyBody: Encodable {}
