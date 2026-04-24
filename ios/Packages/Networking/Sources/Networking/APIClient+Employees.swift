import Foundation

// MARK: - Server-grounded employee commission models
//
// Server route: GET /api/v1/employees/:id/commissions
// Returns: { success, data: { commissions: [...], total_amount: number } }
// Auth: self or admin only (server enforces).

/// A single commission record returned by GET /api/v1/employees/:id/commissions.
public struct EmployeeCommission: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let userId: Int64
    public let ticketId: Int64?
    public let invoiceId: Int64?
    public let amount: Double
    public let createdAt: String
    /// Linked ticket's order_id (JOIN from server).
    public let ticketOrderId: String?
    /// Linked invoice's order_id (JOIN from server).
    public let invoiceOrderId: String?

    public init(
        id: Int64,
        userId: Int64,
        ticketId: Int64? = nil,
        invoiceId: Int64? = nil,
        amount: Double,
        createdAt: String,
        ticketOrderId: String? = nil,
        invoiceOrderId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.ticketId = ticketId
        self.invoiceId = invoiceId
        self.amount = amount
        self.createdAt = createdAt
        self.ticketOrderId = ticketOrderId
        self.invoiceOrderId = invoiceOrderId
    }

    enum CodingKeys: String, CodingKey {
        case id, amount
        case userId          = "user_id"
        case ticketId        = "ticket_id"
        case invoiceId       = "invoice_id"
        case createdAt       = "created_at"
        case ticketOrderId   = "ticket_order_id"
        case invoiceOrderId  = "invoice_order_id"
    }
}

/// Response wrapper for GET /api/v1/employees/:id/commissions
/// Server returns: { success: true, data: { commissions: [...], total_amount: number } }
public struct EmployeeCommissionsResponse: Decodable, Sendable {
    public let commissions: [EmployeeCommission]
    public let totalAmount: Double

    public init(commissions: [EmployeeCommission], totalAmount: Double) {
        self.commissions = commissions
        self.totalAmount = totalAmount
    }

    enum CodingKeys: String, CodingKey {
        case commissions
        case totalAmount = "total_amount"
    }
}

// MARK: - Time-off request models (server-grounded)
//
// Server route: POST /api/v1/time-off
// Body: { start_date, end_date, kind: "pto"|"sick"|"unpaid", reason? }
// Returns: { success, data: TimeOffRequest }
//
// Server route: GET /api/v1/time-off
// Query: user_id?, status?("pending"|"approved"|"denied"|"cancelled")
// Returns: { success, data: [TimeOffRequest] }

/// Maps server `kind` values. Note: server uses "pto" not "vacation".
public enum TimeOffKind: String, Codable, CaseIterable, Sendable {
    case pto    = "pto"
    case sick   = "sick"
    case unpaid = "unpaid"

    public var displayName: String {
        switch self {
        case .pto:    return "PTO"
        case .sick:   return "Sick Leave"
        case .unpaid: return "Unpaid"
        }
    }
}

public enum TimeOffStatus: String, Codable, CaseIterable, Sendable {
    case pending   = "pending"
    case approved  = "approved"
    case denied    = "denied"
    case cancelled = "cancelled"
}

/// A time-off request row from the server.
public struct TimeOffRequest: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let userId: Int64
    public let startDate: String
    public let endDate: String
    public let kind: TimeOffKind
    public let reason: String?
    public let status: TimeOffStatus
    public let requestedAt: String?
    public let decidedAt: String?
    public let approverUserId: Int64?
    public let denialReason: String?
    // Joined fields from the server:
    public let firstName: String?
    public let lastName: String?

    public init(
        id: Int64,
        userId: Int64,
        startDate: String,
        endDate: String,
        kind: TimeOffKind,
        reason: String? = nil,
        status: TimeOffStatus = .pending,
        requestedAt: String? = nil,
        decidedAt: String? = nil,
        approverUserId: Int64? = nil,
        denialReason: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.reason = reason
        self.status = status
        self.requestedAt = requestedAt
        self.decidedAt = decidedAt
        self.approverUserId = approverUserId
        self.denialReason = denialReason
        self.firstName = firstName
        self.lastName = lastName
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, reason, status
        case userId          = "user_id"
        case startDate       = "start_date"
        case endDate         = "end_date"
        case requestedAt     = "requested_at"
        case decidedAt       = "decided_at"
        case approverUserId  = "approver_user_id"
        case denialReason    = "denial_reason"
        case firstName       = "first_name"
        case lastName        = "last_name"
    }

    public var employeeDisplayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "User #\(userId)" : parts.joined(separator: " ")
    }
}

/// Request body for POST /api/v1/time-off
public struct CreateTimeOffRequest: Encodable, Sendable {
    public let startDate: String
    public let endDate: String
    public let kind: TimeOffKind
    public let reason: String?

    public init(startDate: String, endDate: String, kind: TimeOffKind, reason: String? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case kind, reason
        case startDate = "start_date"
        case endDate   = "end_date"
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: - Commissions

    /// GET /api/v1/employees/:id/commissions
    /// Auth: self or admin. Optional date filters.
    func getEmployeeCommissions(
        userId: Int64,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> EmployeeCommissionsResponse {
        var query: [URLQueryItem] = []
        if let from = fromDate { query.append(URLQueryItem(name: "from_date", value: from)) }
        if let to   = toDate   { query.append(URLQueryItem(name: "to_date",   value: to)) }
        return try await get(
            "/api/v1/employees/\(userId)/commissions",
            query: query.isEmpty ? nil : query,
            as: EmployeeCommissionsResponse.self
        )
    }

    // MARK: - Time-off

    /// POST /api/v1/time-off  — self-service submission.
    func submitTimeOff(_ body: CreateTimeOffRequest) async throws -> TimeOffRequest {
        try await post(
            "/api/v1/time-off",
            body: body,
            as: TimeOffRequest.self
        )
    }

    /// GET /api/v1/time-off — list requests.
    /// Managers pass `userId` to see a specific employee; omit to see own.
    func listTimeOffRequests(
        userId: Int64? = nil,
        status: TimeOffStatus? = nil
    ) async throws -> [TimeOffRequest] {
        var query: [URLQueryItem] = []
        if let u = userId { query.append(URLQueryItem(name: "user_id", value: "\(u)")) }
        if let s = status  { query.append(URLQueryItem(name: "status",  value: s.rawValue)) }
        return try await get(
            "/api/v1/time-off",
            query: query.isEmpty ? nil : query,
            as: [TimeOffRequest].self
        )
    }

    // MARK: - Employee detail

    /// GET /api/v1/employees/:id
    /// Returns the employee profile. Admin/self callers also get clock_entries,
    /// commissions, is_clocked_in, current_clock_entry in the response.
    func getEmployee(id: Int64) async throws -> EmployeeDetail {
        try await get("/api/v1/employees/\(id)", as: EmployeeDetail.self)
    }

    // MARK: - Employee performance

    /// GET /api/v1/employees/:id/performance
    /// Optional date range filters: from_date, to_date (yyyy-MM-dd).
    func getEmployeePerformance(
        id: Int64,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> EmployeePerformance {
        var query: [URLQueryItem] = []
        if let from = fromDate { query.append(URLQueryItem(name: "from_date", value: from)) }
        if let to   = toDate   { query.append(URLQueryItem(name: "to_date",   value: to)) }
        return try await get(
            "/api/v1/employees/\(id)/performance",
            query: query.isEmpty ? nil : query,
            as: EmployeePerformance.self
        )
    }

    // MARK: - Role assignment

    /// PUT /api/v1/roles/users/:userId/role — assign a custom role to a user (admin only).
    /// Body: { role_id: Int }
    func assignEmployeeRole(userId: Int64, roleId: Int) async throws {
        let body = AssignRoleBody(roleId: roleId)
        _ = try await put(
            "/api/v1/roles/users/\(userId)/role",
            body: body,
            as: AssignRoleResult.self
        )
    }

    // MARK: - Deactivate / reactivate

    /// PUT /api/v1/settings/users/:id — set is_active flag (admin only).
    /// The settings route accepts a partial update: only `is_active` is required.
    func setEmployeeActive(id: Int64, isActive: Bool) async throws -> Employee {
        let body = SetActiveBody(isActive: isActive ? 1 : 0)
        return try await put(
            "/api/v1/settings/users/\(id)",
            body: body,
            as: Employee.self
        )
    }

    // MARK: - Settings user list (all users including inactive)

    /// GET /api/v1/settings/users — full user list including inactive (admin only).
    func listAllUsers() async throws -> [Employee] {
        try await get("/api/v1/settings/users", as: [Employee].self)
    }
}

// MARK: - Employee detail model

/// Full detail returned by GET /api/v1/employees/:id for admin/self callers.
/// Non-privileged callers get the same base fields as `Employee` with nil arrays.
public struct EmployeeDetail: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let username: String?
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let role: String?
    public let avatarUrl: String?
    public let isActive: Int?
    public let homeLocationId: Int64?
    public let createdAt: String?
    public let permissions: String?

    // Privileged fields (admin/self only):
    public let clockEntries: [ClockEntry]?
    public let commissions: [EmployeeCommission]?
    public let isClockedIn: Bool?
    public let currentClockEntry: ClockEntry?

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (username ?? "User #\(id)") : parts.joined(separator: " ")
    }

    public var active: Bool { (isActive ?? 0) != 0 }

    enum CodingKeys: String, CodingKey {
        case id, username, email, role, permissions
        case firstName          = "first_name"
        case lastName           = "last_name"
        case avatarUrl          = "avatar_url"
        case isActive           = "is_active"
        case homeLocationId     = "home_location_id"
        case createdAt          = "created_at"
        case clockEntries       = "clock_entries"
        case commissions
        case isClockedIn        = "is_clocked_in"
        case currentClockEntry  = "current_clock_entry"
    }
}

// MARK: - Clock entry model (used in EmployeeDetail)

public struct ClockEntry: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let userId: Int64
    public let clockIn: String
    public let clockOut: String?
    public let totalHours: Double?
    public let locationId: Int64?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case userId      = "user_id"
        case clockIn     = "clock_in"
        case clockOut    = "clock_out"
        case totalHours  = "total_hours"
        case locationId  = "location_id"
    }
}

// MARK: - Employee performance model

/// Returned by GET /api/v1/employees/:id/performance
public struct EmployeePerformance: Decodable, Sendable {
    public let totalTickets: Int
    public let closedTickets: Int
    public let totalRevenue: Double
    public let avgTicketValue: Double
    public let avgRepairHours: Double?
    public let totalDevicesRepaired: Int

    enum CodingKeys: String, CodingKey {
        case totalTickets        = "total_tickets"
        case closedTickets       = "closed_tickets"
        case totalRevenue        = "total_revenue"
        case avgTicketValue      = "avg_ticket_value"
        case avgRepairHours      = "avg_repair_hours"
        case totalDevicesRepaired = "total_devices_repaired"
    }
}

// MARK: - Assign role body

struct AssignRoleBody: Encodable, Sendable {
    let roleId: Int

    enum CodingKeys: String, CodingKey {
        case roleId = "role_id"
    }
}

struct AssignRoleResult: Decodable, Sendable {
    let userId: Int64
    let roleId: Int

    enum CodingKeys: String, CodingKey {
        case userId  = "user_id"
        case roleId  = "role_id"
    }
}

// MARK: - Set active body

struct SetActiveBody: Encodable, Sendable {
    let isActive: Int

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}
