import Foundation

// MARK: - §6.8 Asset / Loaner Device Model
//
// Backs the server `loaner_devices` table.
// Inventory owns this model; Loaner issue UI lives in Tickets (Agent 3).
// Agent 3 invokes `AssetPickerProtocol` (see AssetPickerProtocol.swift) to
// pick an available asset from the Inventory package without a direct dependency.
//
// Server route base: /api/v1/loaners

/// Status values mirroring the server `loaner_devices.status` CHECK constraint.
public enum AssetStatus: String, Codable, Sendable, CaseIterable {
    /// On the shelf — available for issue.
    case available  = "available"
    /// Currently checked out to a customer.
    case loaned     = "loaned"
    /// Decommissioned / written off.
    case retired    = "retired"

    public var displayName: String {
        switch self {
        case .available: return "Available"
        case .loaned:    return "Loaned"
        case .retired:   return "Retired"
        }
    }

    /// True when this unit may be issued to a customer.
    public var isAvailableForIssue: Bool { self == .available }
}

/// A loaner / physical asset tracked in the Inventory domain.
///
/// Maps 1-to-1 with the server `loaner_devices` table.
public struct InventoryAsset: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Human-readable asset name (e.g. "Loaner iPhone 13 #2").
    public let name: String
    /// Serial number, if tracked.
    public let serial: String?
    /// IMEI, if this is a cellular device (admin-only; redacted for non-admin roles by server).
    public let imei: String?
    /// Physical condition description (e.g. "Good", "Minor scratch on back").
    public let condition: String?
    public let status: AssetStatus
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date

    // Server-computed — only present on list endpoint.
    /// `true` when the device is currently checked out (a non-null `loaner_history` row exists).
    public var isLoanedOut: Bool?
    /// Name of the customer currently holding this device, if loaned.
    public var loanedTo: String?

    public init(
        id: Int64,
        name: String,
        serial: String? = nil,
        imei: String? = nil,
        condition: String? = nil,
        status: AssetStatus,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        isLoanedOut: Bool? = nil,
        loanedTo: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serial = serial
        self.imei = imei
        self.condition = condition
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLoanedOut = isLoanedOut
        self.loanedTo = loanedTo
    }

    enum CodingKeys: String, CodingKey {
        case id, name, serial, imei, condition, status, notes
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
        case isLoanedOut = "is_loaned_out"
        case loanedTo   = "loaned_to"
    }
}

// MARK: - Request DTOs

/// Body for POST /api/v1/loaners  and  PATCH /api/v1/loaners/:id
public struct UpsertAssetRequest: Encodable, Sendable {
    public let name: String
    public let serial: String?
    public let imei: String?
    public let condition: String?
    public let status: AssetStatus?
    public let notes: String?

    public init(
        name: String,
        serial: String? = nil,
        imei: String? = nil,
        condition: String? = nil,
        status: AssetStatus? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.serial = serial
        self.imei = imei
        self.condition = condition
        self.status = status
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case name, serial, imei, condition, status, notes
    }
}

/// Body for POST /api/v1/loaners/:id/loan  (issue asset to customer on a ticket)
public struct LoanAssetRequest: Encodable, Sendable {
    public let ticketDeviceId: Int64
    public let customerId: Int64
    public let conditionOut: String?
    public let notes: String?

    public init(ticketDeviceId: Int64, customerId: Int64, conditionOut: String? = nil, notes: String? = nil) {
        self.ticketDeviceId = ticketDeviceId
        self.customerId = customerId
        self.conditionOut = conditionOut
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case ticketDeviceId = "ticket_device_id"
        case customerId     = "customer_id"
        case conditionOut   = "condition_out"
        case notes
    }
}

/// Body for POST /api/v1/loaners/:id/return
public struct ReturnAssetRequest: Encodable, Sendable {
    public let conditionIn: String?
    public let newStatus: AssetStatus?
    public let notes: String?

    public init(conditionIn: String? = nil, newStatus: AssetStatus? = nil, notes: String? = nil) {
        self.conditionIn = conditionIn
        self.newStatus = newStatus
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case conditionIn = "condition_in"
        case newStatus   = "new_status"
        case notes
    }
}
