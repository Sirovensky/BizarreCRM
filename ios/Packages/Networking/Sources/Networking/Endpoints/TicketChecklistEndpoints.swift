import Foundation

// §4.3 / §4.4 — Pre-conditions device checklist endpoints.
//
// Server: PUT /api/v1/tickets/devices/:deviceId/checklist
// Body: { checklist: [{ label: String, checked: Bool }] }
//
// The checklist must be signed (all items acknowledged) before the ticket
// status can transition to "diagnosed". Frontend enforces; server validates.

// MARK: - DTOs

/// A single pre-conditions checklist entry.
public struct ChecklistItemPayload: Encodable, Sendable {
    public let label: String
    public let checked: Bool

    public init(label: String, checked: Bool) {
        self.label = label
        self.checked = checked
    }
}

/// Request body for `PUT /tickets/devices/:deviceId/checklist`.
public struct UpdateDeviceChecklistRequest: Encodable, Sendable {
    public let checklist: [ChecklistItemPayload]
    public let technicianSignature: String?

    public init(checklist: [ChecklistItemPayload], technicianSignature: String? = nil) {
        self.checklist = checklist
        self.technicianSignature = technicianSignature
    }

    enum CodingKeys: String, CodingKey {
        case checklist
        case technicianSignature = "technician_signature"
    }
}

// MARK: - Ticket error states

/// Error states a ticket can be in from the server's perspective.
/// Used to drive §4 error UI (cached data banner, stale-edit 409, etc.).
public enum TicketServerError: Sendable {
    /// HTTP 409 — the ticket was edited by another session; show reload prompt.
    case staleEdit
    /// HTTP 403 — current user lacks permission for the action.
    case permissionDenied
    /// HTTP 404 — ticket was deleted server-side; show removal banner.
    case deletedOnServer
}

// MARK: - APIClient wrappers

public extension APIClient {
    /// `PUT /api/v1/tickets/devices/:deviceId/checklist`
    ///
    /// Persists the pre-conditions intake checklist for a device.
    /// An optional base-64 PNG `technicianSignature` marks the checklist as
    /// signed (required before transitioning to "diagnosed").
    @discardableResult
    func updateDeviceChecklist(
        deviceId: Int64,
        checklist: [ChecklistItemPayload],
        technicianSignature: String? = nil
    ) async throws -> Bool {
        let req = UpdateDeviceChecklistRequest(
            checklist: checklist,
            technicianSignature: technicianSignature
        )
        // Server returns { success: Bool, data: null, message: String? }.
        // We use the shared SuccessResponse shim.
        struct _Resp: Decodable, Sendable { let success: Bool? }
        let resp = try await put(
            "/api/v1/tickets/devices/\(deviceId)/checklist",
            body: req,
            as: _Resp.self
        )
        return resp.success ?? true
    }

    /// `POST /api/v1/tickets/:id/signatures`
    ///
    /// §4.5 — Attach a signed customer acknowledgement (waiver / intake sign-off)
    /// to the ticket. The PNG is base-64 encoded.
    ///
    /// - Parameters:
    ///   - ticketId: The ticket receiving the signature.
    ///   - base64Png: Base-64 PNG of the captured signature.
    ///   - signerName: Printed name of the signer (customer).
    func addTicketSignature(
        ticketId: Int64,
        base64Png: String,
        signerName: String
    ) async throws {
        struct _Body: Encodable, Sendable {
            let base64: String
            let name: String
        }
        struct _Resp: Decodable, Sendable { let success: Bool? }
        _ = try await post(
            "/api/v1/tickets/\(ticketId)/signatures",
            body: _Body(base64: base64Png, name: signerName),
            as: _Resp.self
        )
    }
}
