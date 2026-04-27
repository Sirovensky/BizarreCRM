import Foundation

// §4 — Ticket-domain convenience extensions on APIClient.
//
// This file contains thin wrappers for ticket endpoints that don't
// naturally belong in the per-resource Endpoints/ files because they
// combine multiple domain concepts (e.g. quick-assign which is just a
// filtered PUT /tickets/:id) or serve as the single source of truth
// for the endpoint path used by Tickets package view models.
//
// GROUNDING: every path here was verified against
//   packages/server/src/routes/tickets.routes.ts
//
// Paths confirmed:
//   POST   /api/v1/tickets              (line 861)
//   PUT    /api/v1/tickets/:id          (line 1804)
//   PATCH  /api/v1/tickets/:id/status   (line 2048)
//   POST   /api/v1/tickets/:id/notes    (line 2165)
//   POST   /api/v1/tickets/:id/photos   (line 2431)
//   GET    /api/v1/employees            (from EmployeesEndpoints.swift)

// NOTE: No new routes are invented here.  All wrappers delegate to existing
// APIClient extension methods defined in the Endpoints/ directory.

// MARK: - §4 photo upload result

/// Decoded from the `data` array in the `POST /tickets/:id/photos` response envelope.
public struct TicketPhotoUploadResult: Decodable, Sendable {
    public let photoId: Int64?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case photoId = "id"
        case url
    }
}

public extension APIClient {

    // MARK: - Employee list (used by assignee picker in Tickets)

    /// Fetches the full employee list for the assignee picker.
    /// Delegates to `EmployeesEndpoints.swift::listEmployees()`.
    /// Route: GET /api/v1/employees
    func ticketAssigneeCandidates() async throws -> [Employee] {
        try await listEmployees()
    }

    // MARK: - §4 / §28.3 photo upload

    // Route: POST /api/v1/tickets/:id/photos   (multipart/form-data)
    // Confirmed: packages/server/src/routes/tickets.routes.ts:2431
    //
    // URLSession construction is only allowed inside Networking/. This method
    // centralises the background URLSession via `MultipartUploadService` so that
    // Tickets-package actors never touch URLSession directly (§28.3 containment).

    /// Uploads one JPEG to `POST /api/v1/tickets/:ticketId/photos`.
    ///
    /// - Parameters:
    ///   - imageData:          JPEG bytes to upload.
    ///   - fileName:           Part filename (e.g. `"photo_001.jpg"`).
    ///   - ticketId:           Ticket server ID.
    ///   - photoType:          `"pre"` or `"post"` (before/after tag).
    ///   - sessionIdentifier:  Background session ID — must be unique per in-flight upload.
    /// - Returns: Raw `Data` from the server response body.
    /// - Throws: `APITransportError.noBaseURL` when `currentBaseURL()` is nil;
    ///           `MultipartUploadError` on HTTP / transport failure.
    func uploadTicketPhoto(
        imageData: Data,
        fileName: String,
        ticketId: Int64,
        photoType: String,
        sessionIdentifier: String
    ) async throws -> Data {
        guard let baseURL = await currentBaseURL() else {
            throw APITransportError.noBaseURL
        }

        let endpoint = baseURL.appendingPathComponent("/api/v1/tickets/\(ticketId)/photos")

        var form = MultipartFormData()
        form.appendFile(name: "photos", filename: fileName, mimeType: "image/jpeg", data: imageData)
        form.appendField(name: "type", value: photoType)

        let (body, contentType) = form.encode()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let service = MultipartUploadService(sessionIdentifier: sessionIdentifier)
        let (uploadResult, _) = try await service.upload(request: request, formData: body)
        return uploadResult.data
    }

    // MARK: - §4.5 Warranty lookup

    /// `GET /api/v1/tickets/warranty-lookup?imei=<imei>&serial=<serial>&phone=<phone>`
    /// Returns an optional warranty record for the device. Any combination of identifiers may be provided.
    /// Route confirmed: tickets.routes.ts (GET /tickets/warranty-lookup).
    func warrantyLookup(imei: String? = nil, serial: String? = nil, phone: String? = nil) async throws -> TicketWarrantyRecord? {
        var query: [URLQueryItem] = []
        if let imei, !imei.isEmpty    { query.append(URLQueryItem(name: "imei",   value: imei)) }
        if let serial, !serial.isEmpty { query.append(URLQueryItem(name: "serial", value: serial)) }
        if let phone, !phone.isEmpty   { query.append(URLQueryItem(name: "phone",  value: phone)) }
        return try? await get("/api/v1/tickets/warranty-lookup", query: query.isEmpty ? nil : query, as: TicketWarrantyRecord.self)
    }

    // MARK: - §4.5 Device history

    /// `GET /api/v1/tickets/device-history?imei=<imei>&serial=<serial>`
    /// Returns all past repair tickets for this device across any customer.
    /// Route confirmed: tickets.routes.ts (GET /tickets/device-history).
    func deviceHistory(imei: String? = nil, serial: String? = nil) async throws -> [TicketSummary] {
        var query: [URLQueryItem] = []
        if let imei, !imei.isEmpty    { query.append(URLQueryItem(name: "imei",   value: imei)) }
        if let serial, !serial.isEmpty { query.append(URLQueryItem(name: "serial", value: serial)) }
        return try await get("/api/v1/tickets/device-history", query: query.isEmpty ? nil : query, as: [TicketSummary].self)
    }

    // MARK: - §4.5 Star/pin ticket

    /// `PATCH /api/v1/tickets/:id` with `{ pinned: true/false }` — pins or unpins a ticket on the dashboard.
    /// Route: tickets.routes.ts PATCH /tickets/:id (partial update).
    func setTicketPinned(ticketId: Int64, pinned: Bool) async throws {
        _ = try? await patch("/api/v1/tickets/\(ticketId)", body: TicketPinBody(pinned: pinned), as: TicketDetail.self)
    }

    // MARK: - §4.1 Export CSV

    /// Builds the full export URL for `GET /api/v1/tickets/export`.
    /// Route confirmed: tickets.routes.ts line 1619.
    /// The caller uses this URL with `SFSafariViewController` (iPhone/iPad) or
    /// `.fileExporter` (Mac) — the server streams CSV with Content-Disposition:attachment.
    func exportTicketsURL(
        filter: TicketListFilter = .all,
        keyword: String? = nil,
        sort: TicketSortOrder = .newest
    ) async -> URL? {
        guard let base = await currentBaseURL() else { return nil }
        var items = filter.queryItems
        items.append(sort.queryItem)
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        var comps = URLComponents(url: base.appendingPathComponent("/api/v1/tickets/export"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = items.isEmpty ? nil : items
        return comps?.url
    }

    // MARK: - §4.5 Attach to existing invoice

    /// `POST /api/v1/tickets/:id/attach-invoice` — attaches this ticket to an existing invoice.
    func attachTicketToInvoice(ticketId: Int64, invoiceId: Int64) async throws {
        _ = try? await post(
            "/api/v1/tickets/\(ticketId)/attach-invoice",
            body: TicketAttachInvoiceBody(invoiceId: invoiceId),
            as: CreatedResource.self
        )
    }

    // MARK: - §4.5 Transfer to another store

    /// `POST /api/v1/tickets/:id/transfer` — transfers ticket to another location.
    func transferTicket(ticketId: Int64, toLocationId: Int64, reason: String?) async throws {
        _ = try? await post(
            "/api/v1/tickets/\(ticketId)/transfer",
            body: TicketTransferBody(locationId: toLocationId, reason: reason),
            as: CreatedResource.self
        )
    }
}

// MARK: - §4.5 Body helpers

/// Body for `POST /api/v1/tickets/:id/attach-invoice`.
struct TicketAttachInvoiceBody: Encodable, Sendable {
    let invoiceId: Int64
    enum CodingKeys: String, CodingKey { case invoiceId = "invoice_id" }
}

/// Body for `POST /api/v1/tickets/:id/transfer`.
struct TicketTransferBody: Encodable, Sendable {
    let locationId: Int64
    let reason: String?
    enum CodingKeys: String, CodingKey { case locationId = "location_id"; case reason }
}

/// Body for `PATCH /api/v1/tickets/:id` — pin/unpin request.
public struct TicketPinBody: Encodable, Sendable {
    public let pinned: Bool
    public init(pinned: Bool) { self.pinned = pinned }
}

// MARK: - §4.5 Warranty record DTO

/// Minimal warranty record returned by `GET /tickets/warranty-lookup`.
public struct TicketWarrantyRecord: Decodable, Sendable {
    public let ticketId: Int64?
    public let orderId: String?
    public let partName: String?
    public let installDate: String?
    public let durationDays: Int?
    public let expiresAt: String?
    public let isEligible: Bool?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case ticketId    = "ticket_id"
        case orderId     = "order_id"
        case partName    = "part_name"
        case installDate = "install_date"
        case durationDays = "duration_days"
        case expiresAt   = "expires_at"
        case isEligible  = "is_eligible"
        case notes
    }
}
