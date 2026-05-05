import Foundation

// MARK: - Shift schedule models
//
// Server routes (mounted at /api/v1/schedule):
//   GET    /shifts                      — list shifts; non-manager sees own
//   POST   /shifts                      — create shift (manager/admin)
//   PATCH  /shifts/:id                  — partial update (manager/admin)
//   DELETE /shifts/:id                  — delete (manager/admin)
//   POST   /shifts/:id/swap-request     — request a swap (shift owner)
//   POST   /swap/:requestId/accept      — accept swap (target user)
//   POST   /swap/:requestId/decline     — decline swap (target user)
//   POST   /swap/:requestId/cancel      — cancel swap (requester)
//
// Envelope: { success: Bool, data: T?, message: String? }

// MARK: - Shift

/// A single shift row returned by the server.
public struct Shift: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let userId: Int64
    public let startAt: String
    public let endAt: String
    /// Optional role label stored on the shift (e.g. "Technician").
    public let roleTag: String?
    public let locationId: Int64?
    public let notes: String?
    /// "scheduled" | "completed" | "cancelled"
    public let status: String
    public let createdByUserId: Int64?
    public let createdAt: String
    // Joined from users table when listing shifts:
    public let firstName: String?
    public let lastName: String?
    public let username: String?

    public init(
        id: Int64,
        userId: Int64,
        startAt: String,
        endAt: String,
        roleTag: String? = nil,
        locationId: Int64? = nil,
        notes: String? = nil,
        status: String = "scheduled",
        createdByUserId: Int64? = nil,
        createdAt: String = "",
        firstName: String? = nil,
        lastName: String? = nil,
        username: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.startAt = startAt
        self.endAt = endAt
        self.roleTag = roleTag
        self.locationId = locationId
        self.notes = notes
        self.status = status
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
    }

    enum CodingKeys: String, CodingKey {
        case id, status, notes, username
        case userId            = "user_id"
        case startAt           = "start_at"
        case endAt             = "end_at"
        case roleTag           = "role_tag"
        case locationId        = "location_id"
        case createdByUserId   = "created_by_user_id"
        case createdAt         = "created_at"
        case firstName         = "first_name"
        case lastName          = "last_name"
    }

    public var employeeDisplayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (username ?? "User #\(userId)") : parts.joined(separator: " ")
    }
}

// MARK: - CreateShiftRequest

/// POST /api/v1/schedule/shifts body.
public struct CreateShiftRequest: Encodable, Sendable {
    public let userId: Int64
    public let startAt: String
    public let endAt: String
    public let roleTag: String?
    public let locationId: Int64?
    public let notes: String?

    public init(
        userId: Int64,
        startAt: String,
        endAt: String,
        roleTag: String? = nil,
        locationId: Int64? = nil,
        notes: String? = nil
    ) {
        self.userId = userId
        self.startAt = startAt
        self.endAt = endAt
        self.roleTag = roleTag
        self.locationId = locationId
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case userId     = "user_id"
        case startAt    = "start_at"
        case endAt      = "end_at"
        case roleTag    = "role_tag"
        case locationId = "location_id"
        case notes
    }
}

// MARK: - UpdateShiftRequest

/// PATCH /api/v1/schedule/shifts/:id body. All fields optional — server merges.
public struct UpdateShiftRequest: Encodable, Sendable {
    public let startAt: String?
    public let endAt: String?
    public let roleTag: String?
    public let locationId: Int64?
    public let notes: String?

    public init(
        startAt: String? = nil,
        endAt: String? = nil,
        roleTag: String? = nil,
        locationId: Int64? = nil,
        notes: String? = nil
    ) {
        self.startAt = startAt
        self.endAt = endAt
        self.roleTag = roleTag
        self.locationId = locationId
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case startAt    = "start_at"
        case endAt      = "end_at"
        case roleTag    = "role_tag"
        case locationId = "location_id"
        case notes
    }
}

// MARK: - ShiftSwapRequest

/// A shift swap request row returned by the server.
public struct ShiftSwapRequest: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let requesterUserId: Int64
    public let targetUserId: Int64
    public let shiftId: Int64
    /// "pending" | "accepted" | "declined" | "canceled"
    public let status: String
    public let createdAt: String
    public let decidedAt: String?

    public init(
        id: Int64,
        requesterUserId: Int64,
        targetUserId: Int64,
        shiftId: Int64,
        status: String = "pending",
        createdAt: String = "",
        decidedAt: String? = nil
    ) {
        self.id = id
        self.requesterUserId = requesterUserId
        self.targetUserId = targetUserId
        self.shiftId = shiftId
        self.status = status
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterUserId = "requester_user_id"
        case targetUserId    = "target_user_id"
        case shiftId         = "shift_id"
        case createdAt       = "created_at"
        case decidedAt       = "decided_at"
    }
}

// MARK: - CreateSwapRequestBody

private struct CreateSwapRequestBody: Encodable, Sendable {
    let targetUserId: Int64

    enum CodingKeys: String, CodingKey {
        case targetUserId = "target_user_id"
    }
}

// MARK: - DeleteShiftResponse

private struct DeleteShiftResponse: Decodable, Sendable {
    let id: Int64
}

// MARK: - APIClient + Shifts

public extension APIClient {

    // MARK: Shifts — List

    /// GET /api/v1/schedule/shifts
    /// - Parameters:
    ///   - userId: Filter by employee. Nil = server-default (own for non-manager).
    ///   - fromDate: ISO-8601 datetime lower bound for `start_at`.
    ///   - toDate: ISO-8601 datetime upper bound for `start_at`.
    func listShifts(
        userId: Int64? = nil,
        fromDate: String? = nil,
        toDate: String? = nil
    ) async throws -> [Shift] {
        var query: [URLQueryItem] = []
        if let u = userId    { query.append(URLQueryItem(name: "user_id",   value: "\(u)")) }
        if let f = fromDate  { query.append(URLQueryItem(name: "from_date", value: f)) }
        if let t = toDate    { query.append(URLQueryItem(name: "to_date",   value: t)) }
        return try await get(
            "/api/v1/schedule/shifts",
            query: query.isEmpty ? nil : query,
            as: [Shift].self
        )
    }

    // MARK: Shifts — Create

    /// POST /api/v1/schedule/shifts — manager/admin only.
    func createShift(_ body: CreateShiftRequest) async throws -> Shift {
        try await post("/api/v1/schedule/shifts", body: body, as: Shift.self)
    }

    // MARK: Shifts — Update

    /// PATCH /api/v1/schedule/shifts/:id — manager/admin only.
    func updateShift(id: Int64, _ body: UpdateShiftRequest) async throws -> Shift {
        try await patch("/api/v1/schedule/shifts/\(id)", body: body, as: Shift.self)
    }

    // MARK: Shifts — Delete

    /// DELETE /api/v1/schedule/shifts/:id — manager/admin only.
    func deleteShift(id: Int64) async throws {
        try await delete("/api/v1/schedule/shifts/\(id)")
    }

    // MARK: Swap Requests

    /// POST /api/v1/schedule/shifts/:id/swap-request — shift owner only.
    func requestShiftSwap(shiftId: Int64, targetUserId: Int64) async throws -> ShiftSwapRequest {
        let body = CreateSwapRequestBody(targetUserId: targetUserId)
        return try await post(
            "/api/v1/schedule/shifts/\(shiftId)/swap-request",
            body: body,
            as: ShiftSwapRequest.self
        )
    }

    /// POST /api/v1/schedule/swap/:requestId/accept — target user only.
    func acceptShiftSwap(requestId: Int64) async throws -> ShiftSwapRequest {
        let body = EmptyBody()
        return try await post(
            "/api/v1/schedule/swap/\(requestId)/accept",
            body: body,
            as: ShiftSwapRequest.self
        )
    }

    /// POST /api/v1/schedule/swap/:requestId/decline — target user only.
    func declineShiftSwap(requestId: Int64) async throws -> ShiftSwapRequest {
        let body = EmptyBody()
        return try await post(
            "/api/v1/schedule/swap/\(requestId)/decline",
            body: body,
            as: ShiftSwapRequest.self
        )
    }

    /// POST /api/v1/schedule/swap/:requestId/cancel — requester only.
    func cancelShiftSwap(requestId: Int64) async throws -> ShiftSwapRequest {
        let body = EmptyBody()
        return try await post(
            "/api/v1/schedule/swap/\(requestId)/cancel",
            body: body,
            as: ShiftSwapRequest.self
        )
    }
}

// EmptyBody already defined in NotificationsEndpoints.swift (module-wide).
