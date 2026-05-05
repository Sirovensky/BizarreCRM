import Foundation
import Networking

// MARK: - §6.8 Asset / Loaner Device Endpoints
//
// Server routes: /api/v1/loaners  (backed by loaner_devices table)
// Permission gate: inventory.adjust (reads); admin (IMEI field unredacted)
// Rate limit: 60 writes/min (server-enforced)

public extension APIClient {

    // MARK: List

    /// GET /api/v1/loaners — paginated list of loaner/asset devices.
    func listAssets(page: Int = 1, perPage: Int = 50) async throws -> [InventoryAsset] {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        return try await get("/api/v1/loaners", query: query, as: [InventoryAsset].self)
    }

    /// GET /api/v1/loaners — filter to `available` status only; used by AssetPicker.
    func listAvailableAssets() async throws -> [InventoryAsset] {
        let query = [URLQueryItem(name: "status", value: AssetStatus.available.rawValue)]
        return try await get("/api/v1/loaners", query: query, as: [InventoryAsset].self)
    }

    // MARK: Detail

    /// GET /api/v1/loaners/:id — single asset with loan history.
    func getAsset(id: Int64) async throws -> InventoryAsset {
        return try await get("/api/v1/loaners/\(id)", as: InventoryAsset.self)
    }

    // MARK: Create / Update

    /// POST /api/v1/loaners — create a new loaner device.
    func createAsset(_ request: UpsertAssetRequest) async throws -> InventoryAsset {
        return try await post("/api/v1/loaners", body: request, as: InventoryAsset.self)
    }

    /// PATCH /api/v1/loaners/:id — edit an existing asset.
    func updateAsset(id: Int64, _ request: UpsertAssetRequest) async throws -> InventoryAsset {
        return try await patch("/api/v1/loaners/\(id)", body: request, as: InventoryAsset.self)
    }

    // MARK: Loan / Return lifecycle

    /// POST /api/v1/loaners/:id/loan — issue asset to customer on a ticket.
    func loanAsset(id: Int64, request: LoanAssetRequest) async throws -> InventoryAsset {
        return try await post("/api/v1/loaners/\(id)/loan", body: request, as: InventoryAsset.self)
    }

    /// POST /api/v1/loaners/:id/return — mark asset returned; optionally update condition.
    func returnAsset(id: Int64, request: ReturnAssetRequest) async throws -> InventoryAsset {
        return try await post("/api/v1/loaners/\(id)/return", body: request, as: InventoryAsset.self)
    }

    // MARK: Delete (retire)

    /// DELETE /api/v1/loaners/:id — soft-delete / retire asset.
    func deleteAsset(id: Int64) async throws {
        try await delete("/api/v1/loaners/\(id)")
    }
}
