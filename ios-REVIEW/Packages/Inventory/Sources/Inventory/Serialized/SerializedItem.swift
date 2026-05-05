import Foundation

// MARK: - §6.12 Serialized Item

/// Tracks an individual unit of a high-value item (phone, laptop) by IMEI or serial number.
public struct SerializedItem: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Parent SKU of the item model (e.g. "IPH14-128-BLK").
    public let parentSKU: String
    /// IMEI or serial number — globally unique per tenant.
    public let serialNumber: String
    public let status: SerialStatus
    public let locationId: Int64?
    public let receivedAt: Date
    public let soldAt: Date?
    /// Invoice/ticket ID for the sale transaction, if sold.
    public let invoiceId: Int64?

    public init(
        id: Int64,
        parentSKU: String,
        serialNumber: String,
        status: SerialStatus,
        locationId: Int64? = nil,
        receivedAt: Date,
        soldAt: Date? = nil,
        invoiceId: Int64? = nil
    ) {
        self.id = id
        self.parentSKU = parentSKU
        self.serialNumber = serialNumber
        self.status = status
        self.locationId = locationId
        self.receivedAt = receivedAt
        self.soldAt = soldAt
        self.invoiceId = invoiceId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case parentSKU     = "parent_sku"
        case serialNumber  = "serial_number"
        case status
        case locationId    = "location_id"
        case receivedAt    = "received_at"
        case soldAt        = "sold_at"
        case invoiceId     = "invoice_id"
    }
}

// MARK: - Serial Status

public enum SerialStatus: String, Codable, Sendable, CaseIterable {
    case available  = "available"
    case reserved   = "reserved"
    case sold       = "sold"
    case returned   = "returned"

    public var displayName: String {
        switch self {
        case .available: return "Available"
        case .reserved:  return "Reserved"
        case .sold:      return "Sold"
        case .returned:  return "Returned"
        }
    }

    public var isAvailableForSale: Bool { self == .available }
}
