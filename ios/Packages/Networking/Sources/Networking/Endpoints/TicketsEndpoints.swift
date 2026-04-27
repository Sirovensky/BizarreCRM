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

    /// Every pagination field is optional — per §20.5 the iOS client must
    /// never hard-fail on `page` / `per_page` / `total_pages` shape
    /// changes. The server is migrating to cursor envelopes; we just read
    /// whatever keys survive and ignore the rest.
    public struct Pagination: Decodable, Sendable {
        public let page: Int?
        public let perPage: Int?
        public let total: Int?
        public let totalPages: Int?

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

/// Sort options for the ticket list — maps to server `sort` query param.
public enum TicketSortOrder: String, CaseIterable, Sendable, Identifiable {
    case newest    = "newest"
    case oldest    = "oldest"
    case status    = "status"
    case urgency   = "urgency"
    case assignee  = "assignee"
    case dueDate   = "due_date"
    case totalDesc = "total_desc"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .newest:    return "Newest first"
        case .oldest:    return "Oldest first"
        case .status:    return "Status"
        case .urgency:   return "Urgency"
        case .assignee:  return "Assignee"
        case .dueDate:   return "Due date"
        case .totalDesc: return "Total (high–low)"
        }
    }

    public var queryItem: URLQueryItem { URLQueryItem(name: "sort", value: rawValue) }
}

public extension APIClient {
    func listTickets(
        filter: TicketListFilter = .all,
        keyword: String? = nil,
        sort: TicketSortOrder = .newest,
        pageSize: Int = 50
    ) async throws -> TicketsListResponse {
        var items = filter.queryItems
        items.append(URLQueryItem(name: "pagesize", value: String(pageSize)))
        items.append(sort.queryItem)
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        return try await get("/api/v1/tickets", query: items, as: TicketsListResponse.self)
    }
}

// MARK: - Note operations

/// `POST /api/v1/tickets/:id/notes` body.
/// Server route: tickets.routes.ts:2036. Required: `content`.
/// Optional: `type` (internal/customer/diagnostic/sms/email), `is_flagged`, `ticket_device_id`.
public struct AddTicketNoteRequest: Encodable, Sendable {
    public let type: String
    public let content: String
    public let isFlagged: Bool
    public let ticketDeviceId: Int64?

    public init(
        type: String = "internal",
        content: String,
        isFlagged: Bool = false,
        ticketDeviceId: Int64? = nil
    ) {
        self.type = type
        self.content = content
        self.isFlagged = isFlagged
        self.ticketDeviceId = ticketDeviceId
    }

    enum CodingKeys: String, CodingKey {
        case type, content
        case isFlagged = "is_flagged"
        case ticketDeviceId = "ticket_device_id"
    }
}

/// Response from `POST /tickets/:id/notes` — the saved note row.
public struct AddTicketNoteResponse: Decodable, Sendable {
    public let id: Int64
    public let type: String?
    public let content: String?
    public let isFlagged: Bool?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, content
        case isFlagged = "is_flagged"
        case createdAt = "created_at"
    }
}

public extension APIClient {
    /// `POST /api/v1/tickets/:id/notes`
    func addTicketNote(ticketId: Int64, _ req: AddTicketNoteRequest) async throws -> AddTicketNoteResponse {
        try await post(
            "/api/v1/tickets/\(ticketId)/notes",
            body: req,
            as: AddTicketNoteResponse.self
        )
    }
}

// MARK: - Device operations

/// `POST /api/v1/tickets/:id/devices` body.
/// Server route: tickets.routes.ts:2617. Adds a device row to a ticket.
public struct AddTicketDeviceRequest: Encodable, Sendable {
    public let deviceName: String
    public let deviceType: String?
    public let imei: String?
    public let serial: String?
    public let securityCode: String?
    public let color: String?
    public let network: String?
    public let price: Double
    public let additionalNotes: String?
    public let serviceId: Int64?

    public init(
        deviceName: String,
        deviceType: String? = nil,
        imei: String? = nil,
        serial: String? = nil,
        securityCode: String? = nil,
        color: String? = nil,
        network: String? = nil,
        price: Double = 0,
        additionalNotes: String? = nil,
        serviceId: Int64? = nil
    ) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.imei = imei
        self.serial = serial
        self.securityCode = securityCode
        self.color = color
        self.network = network
        self.price = price
        self.additionalNotes = additionalNotes
        self.serviceId = serviceId
    }

    enum CodingKeys: String, CodingKey {
        case imei, serial, color, network, price
        case deviceName = "device_name"
        case deviceType = "device_type"
        case securityCode = "security_code"
        case additionalNotes = "additional_notes"
        case serviceId = "service_id"
    }
}

/// `PUT /api/v1/tickets/devices/:deviceId` body.
/// Server accepts a sparse update — only non-nil fields are sent.
public struct UpdateTicketDeviceRequest: Encodable, Sendable {
    public let deviceName: String?
    public let imei: String?
    public let serial: String?
    public let securityCode: String?
    public let color: String?
    public let network: String?
    public let price: Double?
    public let additionalNotes: String?
    public let serviceId: Int64?

    public init(
        deviceName: String? = nil,
        imei: String? = nil,
        serial: String? = nil,
        securityCode: String? = nil,
        color: String? = nil,
        network: String? = nil,
        price: Double? = nil,
        additionalNotes: String? = nil,
        serviceId: Int64? = nil
    ) {
        self.deviceName = deviceName
        self.imei = imei
        self.serial = serial
        self.securityCode = securityCode
        self.color = color
        self.network = network
        self.price = price
        self.additionalNotes = additionalNotes
        self.serviceId = serviceId
    }

    enum CodingKeys: String, CodingKey {
        case imei, serial, color, network, price
        case deviceName = "device_name"
        case securityCode = "security_code"
        case additionalNotes = "additional_notes"
        case serviceId = "service_id"
    }
}

public extension APIClient {
    /// `POST /api/v1/tickets/:id/devices`
    func addTicketDevice(ticketId: Int64, _ req: AddTicketDeviceRequest) async throws -> CreatedResource {
        try await post(
            "/api/v1/tickets/\(ticketId)/devices",
            body: req,
            as: CreatedResource.self
        )
    }

    /// `PUT /api/v1/tickets/devices/:deviceId`
    func updateTicketDevice(deviceId: Int64, _ req: UpdateTicketDeviceRequest) async throws -> CreatedResource {
        try await put(
            "/api/v1/tickets/devices/\(deviceId)",
            body: req,
            as: CreatedResource.self
        )
    }

    /// `DELETE /api/v1/tickets/devices/:deviceId`
    func deleteTicketDevice(deviceId: Int64) async throws {
        try await delete("/api/v1/tickets/devices/\(deviceId)")
    }
}

// MARK: - Checklist operations

/// A single pre/post-condition checklist item.
public struct ChecklistItem: Codable, Sendable, Identifiable, Equatable {
    public let id: String       // client-generated stable UUID string
    public var label: String
    public var checked: Bool

    public init(id: String = UUID().uuidString, label: String, checked: Bool = false) {
        self.id = id
        self.label = label
        self.checked = checked
    }
}

/// `PUT /api/v1/tickets/devices/:deviceId/checklist` body.
/// Server route: tickets.routes.ts:3158. `items` is a JSON array.
public struct UpdateChecklistRequest: Encodable, Sendable {
    public let items: [ChecklistItem]
    public init(items: [ChecklistItem]) { self.items = items }
}

public extension APIClient {
    /// `PUT /api/v1/tickets/devices/:deviceId/checklist`
    func updateDeviceChecklist(deviceId: Int64, items: [ChecklistItem]) async throws -> CreatedResource {
        let req = UpdateChecklistRequest(items: items)
        return try await put(
            "/api/v1/tickets/devices/\(deviceId)/checklist",
            body: req,
            as: CreatedResource.self
        )
    }
}

// MARK: - Parts operations

/// `POST /api/v1/tickets/devices/:deviceId/parts` body.
/// Server route: tickets.routes.ts:2893.
public struct AddDevicePartRequest: Encodable, Sendable {
    public let name: String
    public let sku: String?
    public let quantity: Int
    public let price: Double
    public let inventoryItemId: Int64?

    public init(
        name: String,
        sku: String? = nil,
        quantity: Int = 1,
        price: Double = 0,
        inventoryItemId: Int64? = nil
    ) {
        self.name = name
        self.sku = sku
        self.quantity = quantity
        self.price = price
        self.inventoryItemId = inventoryItemId
    }

    enum CodingKeys: String, CodingKey {
        case name, sku, quantity, price
        case inventoryItemId = "inventory_item_id"
    }
}

public extension APIClient {
    /// `POST /api/v1/tickets/devices/:deviceId/parts`
    func addDevicePart(deviceId: Int64, _ req: AddDevicePartRequest) async throws -> CreatedResource {
        try await post(
            "/api/v1/tickets/devices/\(deviceId)/parts",
            body: req,
            as: CreatedResource.self
        )
    }

    /// `DELETE /api/v1/tickets/devices/parts/:partId`
    func deleteDevicePart(partId: Int64) async throws {
        try await delete("/api/v1/tickets/devices/parts/\(partId)")
    }
}

// MARK: - Convert to invoice

/// Response from `POST /tickets/:id/convert-to-invoice`.
public struct ConvertToInvoiceResponse: Decodable, Sendable {
    public let invoiceId: Int64?
    public let id: Int64?

    public var resolvedInvoiceId: Int64? { invoiceId ?? id }

    enum CodingKeys: String, CodingKey {
        case invoiceId = "invoice_id"
        case id
    }
}

private struct _EmptyBody: Encodable, Sendable {}

public extension APIClient {
    /// `POST /api/v1/tickets/:id/convert-to-invoice`
    func convertTicketToInvoice(ticketId: Int64) async throws -> ConvertToInvoiceResponse {
        try await post(
            "/api/v1/tickets/\(ticketId)/convert-to-invoice",
            body: _EmptyBody(),
            as: ConvertToInvoiceResponse.self
        )
    }
}

// MARK: - Delete ticket

public extension APIClient {
    /// `DELETE /api/v1/tickets/:id` — soft-delete server-side.
    func deleteTicket(ticketId: Int64) async throws {
        try await delete("/api/v1/tickets/\(ticketId)")
    }
}

// MARK: - Duplicate ticket

/// Response from `POST /tickets/:id/duplicate`.
public struct DuplicateTicketResponse: Decodable, Sendable {
    public let id: Int64?
    public let ticketId: Int64?

    public var resolvedId: Int64? { id ?? ticketId }

    enum CodingKeys: String, CodingKey {
        case id
        case ticketId = "ticket_id"
    }
}

public extension APIClient {
    /// `POST /api/v1/tickets/:id/duplicate` — copies customer + devices + clears status.
    func duplicateTicket(ticketId: Int64) async throws -> DuplicateTicketResponse {
        try await post(
            "/api/v1/tickets/\(ticketId)/duplicate",
            body: _EmptyBody(),
            as: DuplicateTicketResponse.self
        )
    }
}
