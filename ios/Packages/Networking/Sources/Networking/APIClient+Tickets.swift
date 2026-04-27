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
}
