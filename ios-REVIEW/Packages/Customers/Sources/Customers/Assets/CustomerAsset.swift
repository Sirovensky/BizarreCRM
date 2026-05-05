import Foundation

// §5.7 — Customer asset (device/equipment) row, matching `customer_assets` DB table.
// Server: packages/server/src/routes/customers.routes.ts GET/POST /:id/assets

public struct CustomerAsset: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let customerId: Int64
    /// Human-readable asset name, e.g. "iPhone 14 Pro Max" (required on server).
    public let name: String
    /// Device category, e.g. "Phone", "Laptop", "Tablet".
    public let deviceType: String?
    public let serial: String?
    public let imei: String?
    public let color: String?
    public let notes: String?
    public let createdAt: String
    public let updatedAt: String?

    public init(
        id: Int64,
        customerId: Int64,
        name: String,
        deviceType: String? = nil,
        serial: String? = nil,
        imei: String? = nil,
        color: String? = nil,
        notes: String? = nil,
        createdAt: String,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.customerId = customerId
        self.name = name
        self.deviceType = deviceType
        self.serial = serial
        self.imei = imei
        self.color = color
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, serial, imei, color, notes
        case customerId  = "customer_id"
        case deviceType  = "device_type"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

// MARK: - Request body for POST /:id/assets

public struct CreateCustomerAssetRequest: Encodable, Sendable {
    public let name: String
    public let deviceType: String?
    public let serial: String?
    public let imei: String?
    public let color: String?
    public let notes: String?

    public init(
        name: String,
        deviceType: String? = nil,
        serial: String? = nil,
        imei: String? = nil,
        color: String? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.deviceType = deviceType
        self.serial = serial
        self.imei = imei
        self.color = color
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case name, serial, imei, color, notes
        case deviceType = "device_type"
    }
}
