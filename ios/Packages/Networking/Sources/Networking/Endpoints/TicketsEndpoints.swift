import Foundation

/// `GET /api/v1/tickets` response.
/// Server route: packages/server/src/routes/tickets.routes.ts:741–828.
/// Shape: `{ data: { tickets: [...], pagination: {...}, status_counts: [...] } }`.
public struct TicketsListResponse: Decodable, Sendable {
    public let tickets: [TicketSummary]
    public let pagination: Pagination?
    public let statusCounts: [StatusCount]?

    enum CodingKeys: String, CodingKey {
        case tickets
        case pagination
        case statusCounts = "status_counts"
    }

    public struct Pagination: Decodable, Sendable {
        public let page: Int
        public let perPage: Int
        public let total: Int
        public let totalPages: Int

        enum CodingKeys: String, CodingKey {
            case page
            case perPage = "per_page"
            case total
            case totalPages = "total_pages"
        }
    }

    public struct StatusCount: Decodable, Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let color: String?
        public let sortOrder: Int?
        public let count: Int

        enum CodingKeys: String, CodingKey {
            case id, name, color, count
            case sortOrder = "sort_order"
        }
    }
}

public struct TicketSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String
    public let customerId: Int64?
    public let total: Int // cents
    public let isPinned: Bool
    public let createdAt: String
    public let updatedAt: String
    public let customer: Customer?
    public let status: Status?
    public let assignedUser: AssignedUser?
    public let firstDevice: FirstDevice?
    public let deviceCount: Int?
    public let slaStatus: String?
    public let urgency: String?
    public let latestSms: LatestSms?

    public struct Customer: Decodable, Sendable, Hashable {
        public let id: Int64
        public let firstName: String?
        public let lastName: String?
        public let phone: String?
        public let mobile: String?
        public let email: String?
        public let organization: String?

        public var displayName: String {
            let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
            if parts.isEmpty { return organization ?? "" }
            return parts.joined(separator: " ")
        }

        enum CodingKeys: String, CodingKey {
            case id, phone, mobile, email, organization
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct Status: Decodable, Sendable, Hashable {
        public let id: Int64
        public let name: String
        public let color: String?
        public let isClosed: Bool?
        public let isCancelled: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name, color
            case isClosed = "is_closed"
            case isCancelled = "is_cancelled"
        }

        /// Android derives the row pill from flags + name, ignoring raw hex color
        /// (see TicketListScreen.kt:387–396). Mirror that logic here.
        public var group: Group {
            let lowered = name.lowercased()
            if isCancelled == true || lowered.contains("cancel") || lowered.contains("void") { return .cancelled }
            if isClosed == true { return .complete }
            if lowered.contains("waiting") || lowered.contains("hold") || lowered.contains("parts") { return .waiting }
            return .inProgress
        }

        public enum Group: Sendable { case inProgress, waiting, complete, cancelled }
    }

    public struct AssignedUser: Decodable, Sendable, Hashable {
        public let id: Int64
        public let firstName: String?
        public let lastName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct FirstDevice: Decodable, Sendable, Hashable {
        public let deviceName: String?
        public let serviceName: String?
        public let additionalNotes: String?

        enum CodingKeys: String, CodingKey {
            case deviceName = "device_name"
            case serviceName = "service_name"
            case additionalNotes = "additional_notes"
        }
    }

    public struct LatestSms: Decodable, Sendable, Hashable {
        public let message: String
        public let direction: String
        public let dateTime: String?

        enum CodingKeys: String, CodingKey {
            case message, direction
            case dateTime = "date_time"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case customerId = "customer_id"
        case total
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case customer, status
        case assignedUser = "assigned_user"
        case firstDevice = "first_device"
        case deviceCount = "device_count"
        case slaStatus = "sla_status"
        case urgency
        case latestSms = "latest_sms"
    }
}

/// Client-side filter chips. Mapped to server query params in the repository.
public enum TicketListFilter: String, CaseIterable, Sendable, Identifiable {
    case all
    case myTickets
    case open
    case inProgress
    case waiting
    case closed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:        return "All"
        case .myTickets:  return "My Tickets"
        case .open:       return "Open"
        case .inProgress: return "In Progress"
        case .waiting:    return "Waiting"
        case .closed:     return "Closed"
        }
    }

    /// Query params the server understands. Some filters are client-side
    /// refinements (my tickets → assigned_to=me); the rest map to status_group.
    public var queryItems: [URLQueryItem] {
        switch self {
        case .all:
            return []
        case .myTickets:
            return [URLQueryItem(name: "assigned_to", value: "me")]
        case .open:
            return [URLQueryItem(name: "status_group", value: "open")]
        case .inProgress:
            return [URLQueryItem(name: "status_group", value: "active")]
        case .waiting:
            return [URLQueryItem(name: "status_group", value: "on_hold")]
        case .closed:
            return [URLQueryItem(name: "status_group", value: "closed")]
        }
    }
}

public extension APIClient {
    func listTickets(filter: TicketListFilter = .all, keyword: String? = nil, pageSize: Int = 50) async throws -> TicketsListResponse {
        var items = filter.queryItems
        items.append(URLQueryItem(name: "pagesize", value: String(pageSize)))
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        return try await get("/api/v1/tickets", query: items, as: TicketsListResponse.self)
    }
}
