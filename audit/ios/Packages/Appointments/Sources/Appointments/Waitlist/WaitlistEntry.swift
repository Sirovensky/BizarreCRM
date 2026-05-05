import Foundation

// MARK: - WaitlistStatus

public enum WaitlistStatus: String, Codable, CaseIterable, Sendable {
    case waiting   = "waiting"
    case offered   = "offered"
    case scheduled = "scheduled"
    case canceled  = "canceled"

    public var displayName: String {
        switch self {
        case .waiting:   return "Waiting"
        case .offered:   return "Offered"
        case .scheduled: return "Scheduled"
        case .canceled:  return "Canceled"
        }
    }
}

// MARK: - PreferredWindow

public struct PreferredWindow: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

// MARK: - WaitlistEntry

public struct WaitlistEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let customerId: Int64
    public let requestedServiceType: String
    public let preferredWindows: [PreferredWindow]
    public let note: String?
    public let createdAt: Date
    public var status: WaitlistStatus

    public init(
        id: String = UUID().uuidString,
        customerId: Int64,
        requestedServiceType: String,
        preferredWindows: [PreferredWindow],
        note: String? = nil,
        createdAt: Date = Date(),
        status: WaitlistStatus = .waiting
    ) {
        self.id = id
        self.customerId = customerId
        self.requestedServiceType = requestedServiceType
        self.preferredWindows = preferredWindows
        self.note = note
        self.createdAt = createdAt
        self.status = status
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case customerId         = "customer_id"
        case requestedServiceType = "requested_service_type"
        case preferredWindows   = "preferred_windows"
        case note
        case createdAt          = "created_at"
        case status
    }
}
