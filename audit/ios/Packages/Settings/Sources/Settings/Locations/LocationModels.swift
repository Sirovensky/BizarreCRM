import Foundation

// MARK: - §60 Location models

public struct Location: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var addressLine1: String
    public var addressLine2: String?
    public var city: String
    public var region: String
    public var postal: String
    public var country: String
    public var phone: String
    public var timezone: String
    public var taxRateId: String?
    public var active: Bool
    public var isPrimary: Bool
    public var openingHours: [LocationBusinessDay]?

    public init(
        id: String,
        name: String,
        addressLine1: String,
        addressLine2: String? = nil,
        city: String,
        region: String,
        postal: String,
        country: String,
        phone: String,
        timezone: String,
        taxRateId: String? = nil,
        active: Bool = true,
        isPrimary: Bool = false,
        openingHours: [LocationBusinessDay]? = nil
    ) {
        self.id = id
        self.name = name
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.region = region
        self.postal = postal
        self.country = country
        self.phone = phone
        self.timezone = timezone
        self.taxRateId = taxRateId
        self.active = active
        self.isPrimary = isPrimary
        self.openingHours = openingHours
    }
}

/// Per-location business day override (distinct from `HoursModels.BusinessDay`).
public struct LocationBusinessDay: Codable, Sendable, Hashable, Identifiable {
    public var id: String { dayOfWeek }
    public let dayOfWeek: String   // "Monday", "Tuesday", …
    public var isOpen: Bool
    public var openTime: String    // "09:00"
    public var closeTime: String   // "18:00"

    public init(dayOfWeek: String, isOpen: Bool, openTime: String, closeTime: String) {
        self.dayOfWeek = dayOfWeek
        self.isOpen = isOpen
        self.openTime = openTime
        self.closeTime = closeTime
    }
}

// MARK: - Inventory balance across locations

public struct LocationInventoryBalance: Codable, Sendable, Identifiable {
    public var id: String { "\(locationId)-\(sku)" }
    public let locationId: String
    public let sku: String
    public let quantity: Int
    public let reorderLevel: Int?

    public init(locationId: String, sku: String, quantity: Int, reorderLevel: Int? = nil) {
        self.locationId = locationId
        self.sku = sku
        self.quantity = quantity
        self.reorderLevel = reorderLevel
    }

    public var isLow: Bool {
        guard let reorder = reorderLevel, reorder > 0 else { return false }
        return quantity <= reorder
    }
}

// MARK: - Transfer request

public struct LocationTransferRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let fromLocationId: String
    public let toLocationId: String
    public let items: [TransferItem]
    public var status: String   // requested / shipped / received
    public var createdAt: Date

    public init(
        id: String,
        fromLocationId: String,
        toLocationId: String,
        items: [TransferItem],
        status: String = "requested",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromLocationId = fromLocationId
        self.toLocationId = toLocationId
        self.items = items
        self.status = status
        self.createdAt = createdAt
    }
}

public struct TransferItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String { sku }
    public let sku: String
    public let quantity: Int
    public let name: String?

    public init(sku: String, quantity: Int, name: String? = nil) {
        self.sku = sku
        self.quantity = quantity
        self.name = name
    }
}

// MARK: - Transfer direction filter

public enum TransferDirection: String, CaseIterable, Sendable, Identifiable {
    case all, incoming, outgoing

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .all:      return "All"
        case .incoming: return "Incoming"
        case .outgoing: return "Outgoing"
        }
    }
}

// MARK: - Employee location access

public struct LocationAccessEntry: Codable, Sendable, Identifiable {
    public let employeeId: String
    public let locationId: String
    public var canView: Bool
    public var canEdit: Bool
    public var canManage: Bool

    public var id: String { "\(employeeId)-\(locationId)" }

    public init(employeeId: String, locationId: String, canView: Bool, canEdit: Bool, canManage: Bool) {
        self.employeeId = employeeId
        self.locationId = locationId
        self.canView = canView
        self.canEdit = canEdit
        self.canManage = canManage
    }
}
