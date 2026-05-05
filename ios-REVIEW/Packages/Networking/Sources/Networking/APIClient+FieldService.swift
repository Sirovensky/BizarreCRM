// §57 — Field Service convenience extensions on APIClient.
//
// GROUNDING: all paths verified against
//   packages/server/src/routes/fieldService.routes.ts
//   Mount: /api/v1/field-service
//
// Paths confirmed:
//   GET    /api/v1/field-service/jobs            (line 188)
//   GET    /api/v1/field-service/jobs/:id         (line 258)
//   POST   /api/v1/field-service/jobs/:id/status  (line 571)
//
// No separate /check-in route exists on the server.
// Location check-in is performed via POST /jobs/:id/status with
// status="on_site" and location_lat/location_lng coords.
//
// NOTE: No routes are invented. All paths verified before coding.

import Foundation

// MARK: - FSJob

/// Mirrors `field_service_jobs` row as returned by GET /field-service/jobs
/// and GET /field-service/jobs/:id.
public struct FSJob: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let ticketId: Int64?
    public let customerId: Int64?
    public let addressLine: String
    public let city: String?
    public let state: String?
    public let postcode: String?
    public let lat: Double
    public let lng: Double
    public let scheduledWindowStart: String?
    public let scheduledWindowEnd: String?
    public let priority: String
    public let status: String
    public let estimatedDurationMinutes: Int?
    public let actualDurationMinutes: Int?
    public let notes: String?
    public let technicianNotes: String?
    public let assignedTechnicianId: Int64?
    public let customerFirstName: String?
    public let customerLastName: String?
    public let techFirstName: String?
    public let techLastName: String?
    public let createdAt: String?
    public let updatedAt: String?

    public var customerName: String? {
        let parts = [customerFirstName, customerLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var techName: String? {
        let parts = [techFirstName, techLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ticketId               = "ticket_id"
        case customerId             = "customer_id"
        case addressLine            = "address_line"
        case city, state, postcode
        case lat, lng
        case scheduledWindowStart   = "scheduled_window_start"
        case scheduledWindowEnd     = "scheduled_window_end"
        case priority, status
        case estimatedDurationMinutes = "estimated_duration_minutes"
        case actualDurationMinutes    = "actual_duration_minutes"
        case notes
        case technicianNotes         = "technician_notes"
        case assignedTechnicianId    = "assigned_technician_id"
        case customerFirstName       = "customer_first_name"
        case customerLastName        = "customer_last_name"
        case techFirstName           = "tech_first_name"
        case techLastName            = "tech_last_name"
        case createdAt               = "created_at"
        case updatedAt               = "updated_at"
    }
}

// MARK: - FSJobsListResponse

/// Envelope data from GET /field-service/jobs.
/// Server: `{ success, data: { jobs: [...], pagination: {...} } }`
public struct FSJobsListResponse: Decodable, Sendable {
    public let jobs: [FSJob]
    public let pagination: FSPagination
}

public struct FSPagination: Decodable, Sendable {
    public let page: Int
    public let perPage: Int
    public let total: Int
    public let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page
        case perPage    = "per_page"
        case total
        case totalPages = "total_pages"
    }
}

// MARK: - Job status values

public enum FSJobStatus: String, CaseIterable, Sendable {
    case unassigned  = "unassigned"
    case assigned    = "assigned"
    case enRoute     = "en_route"
    case onSite      = "on_site"
    case completed   = "completed"
    case canceled    = "canceled"
    case deferred    = "deferred"

    public var displayLabel: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .assigned:   return "Assigned"
        case .enRoute:    return "En Route"
        case .onSite:     return "On Site"
        case .completed:  return "Completed"
        case .canceled:   return "Canceled"
        case .deferred:   return "Deferred"
        }
    }
}

// MARK: - FSJobStatusRequest

/// Body for POST /field-service/jobs/:id/status.
/// `location_lat` and `location_lng` are optional but must be sent together
/// (server enforces pair-or-neither).
public struct FSJobStatusRequest: Encodable, Sendable {
    public let status: String
    public let locationLat: Double?
    public let locationLng: Double?
    public let notes: String?

    public init(
        status: FSJobStatus,
        locationLat: Double? = nil,
        locationLng: Double? = nil,
        notes: String? = nil
    ) {
        self.status = status.rawValue
        self.locationLat = locationLat
        self.locationLng = locationLng
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case status
        case locationLat = "location_lat"
        case locationLng = "location_lng"
        case notes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        if let v = locationLat  { try c.encode(v, forKey: .locationLat) }
        if let v = locationLng  { try c.encode(v, forKey: .locationLng) }
        if let v = notes        { try c.encode(v, forKey: .notes) }
    }
}

// MARK: - FSJobStatusResponse

public struct FSJobStatusResponse: Decodable, Sendable {
    public let id: Int64
    public let status: String
}

// MARK: - APIClient + FieldService extensions

public extension APIClient {

    // MARK: - List jobs

    /// `GET /api/v1/field-service/jobs`
    ///
    /// Technicians receive only their own assigned jobs.
    /// Managers can filter by `assignedTechnicianId`, `status`, date range.
    func listFieldServiceJobs(
        status: FSJobStatus? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        assignedTechnicianId: Int64? = nil,
        page: Int = 1,
        pageSize: Int = 25
    ) async throws -> FSJobsListResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page",     value: String(page)),
            URLQueryItem(name: "pagesize", value: String(pageSize)),
        ]
        if let s = status {
            query.append(URLQueryItem(name: "status", value: s.rawValue))
        }
        if let f = fromDate {
            query.append(URLQueryItem(name: "from_date", value: f))
        }
        if let t = toDate {
            query.append(URLQueryItem(name: "to_date", value: t))
        }
        if let tid = assignedTechnicianId {
            query.append(URLQueryItem(name: "assigned_technician_id", value: String(tid)))
        }
        return try await get(
            "/api/v1/field-service/jobs",
            query: query,
            as: FSJobsListResponse.self
        )
    }

    // MARK: - Job detail

    /// `GET /api/v1/field-service/jobs/:id`
    func fieldServiceJob(id: Int64) async throws -> FSJob {
        try await get("/api/v1/field-service/jobs/\(id)", as: FSJob.self)
    }

    // MARK: - Update job status (includes location check-in)

    /// `POST /api/v1/field-service/jobs/:id/status`
    ///
    /// Used for all status transitions including location-based check-in
    /// (`status = .onSite` with lat/lng).
    func updateFieldServiceJobStatus(
        id: Int64,
        request: FSJobStatusRequest
    ) async throws -> FSJobStatusResponse {
        try await post(
            "/api/v1/field-service/jobs/\(id)/status",
            body: request,
            as: FSJobStatusResponse.self
        )
    }
}
