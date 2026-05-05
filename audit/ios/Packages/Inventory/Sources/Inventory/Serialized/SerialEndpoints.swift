import Foundation
import Networking

// MARK: - §6.12 Serialized Item DTOs

public struct CreateSerialRequest: Encodable, Sendable {
    public let parentSKU: String
    public let serialNumber: String
    public let locationId: Int64?

    public init(parentSKU: String, serialNumber: String, locationId: Int64? = nil) {
        self.parentSKU = parentSKU
        self.serialNumber = serialNumber
        self.locationId = locationId
    }

    enum CodingKeys: String, CodingKey {
        case parentSKU    = "parent_sku"
        case serialNumber = "serial_number"
        case locationId   = "location_id"
    }
}

public struct UpdateSerialStatusRequest: Encodable, Sendable {
    public let status: SerialStatus
    public let invoiceId: Int64?

    public init(status: SerialStatus, invoiceId: Int64? = nil) {
        self.status = status
        self.invoiceId = invoiceId
    }

    enum CodingKeys: String, CodingKey {
        case status
        case invoiceId = "invoice_id"
    }
}

// MARK: - APIClient extension

public extension APIClient {

    /// POST /api/v1/inventory/serials
    func createSerial(_ request: CreateSerialRequest) async throws -> SerializedItem {
        try await post("/api/v1/inventory/serials", body: request, as: SerializedItem.self)
    }

    /// GET /api/v1/inventory/serials/:sn
    func getSerial(serialNumber: String) async throws -> SerializedItem {
        try await get("/api/v1/inventory/serials/\(serialNumber)", as: SerializedItem.self)
    }

    /// PATCH /api/v1/inventory/serials/:id/status
    func updateSerialStatus(id: Int64, request: UpdateSerialStatusRequest) async throws -> SerializedItem {
        try await patch("/api/v1/inventory/serials/\(id)/status", body: request, as: SerializedItem.self)
    }

    /// GET /api/v1/inventory/serials?parent_sku=<sku>
    func listSerials(parentSKU: String) async throws -> [SerializedItem] {
        let query = [URLQueryItem(name: "parent_sku", value: parentSKU)]
        return try await get("/api/v1/inventory/serials", query: query, as: [SerializedItem].self)
    }
}
