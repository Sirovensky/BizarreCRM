import Foundation

// §63 ext — Ticket create draft model (Phase 2)

/// Persisted snapshot of in-progress ticket create form fields.
public struct TicketDraft: Codable, Sendable, Equatable {
    public var customerId: String?
    public var customerDisplayName: String?
    public var deviceId: String?
    public var deviceName: String
    public var imei: String
    public var serial: String
    public var notes: String
    public var estimatedCost: Int?
    public var priceText: String
    public var updatedAt: Date

    public init(
        customerId: String? = nil,
        customerDisplayName: String? = nil,
        deviceId: String? = nil,
        deviceName: String = "",
        imei: String = "",
        serial: String = "",
        notes: String = "",
        estimatedCost: Int? = nil,
        priceText: String = "",
        updatedAt: Date = Date()
    ) {
        self.customerId = customerId
        self.customerDisplayName = customerDisplayName
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.imei = imei
        self.serial = serial
        self.notes = notes
        self.estimatedCost = estimatedCost
        self.priceText = priceText
        self.updatedAt = updatedAt
    }
}
