import Foundation
import Networking

// MARK: - AutoResponderEndpoints — §12.7 auto-responder CRUD

/// APIClient extension for SMS auto-responder rules.
/// Routes: `GET/POST/PATCH/DELETE /api/v1/sms/auto-responders`.
public extension APIClient {

    // MARK: List

    /// `GET /api/v1/sms/auto-responders` — fetch all rules for this tenant.
    func listAutoResponders() async throws -> [AutoResponderRule] {
        try await get("/api/v1/sms/auto-responders", as: AutoResponderListResponse.self).rules
    }

    // MARK: Create

    /// `POST /api/v1/sms/auto-responders` — create a new rule.
    func createAutoResponder(_ rule: AutoResponderRule) async throws -> AutoResponderRule {
        try await post("/api/v1/sms/auto-responders", body: rule, as: AutoResponderRule.self)
    }

    // MARK: Update / toggle

    /// `PATCH /api/v1/sms/auto-responders/:id` — partial update (e.g. toggle enabled).
    func updateAutoResponder(id: UUID, body: AutoResponderRule) async throws -> AutoResponderRule {
        try await patch("/api/v1/sms/auto-responders/\(id)", body: body, as: AutoResponderRule.self)
    }

    /// `PATCH /api/v1/sms/auto-responders/:id { enabled }` — convenience toggle.
    func toggleAutoResponder(id: UUID, enabled: Bool) async throws -> AutoResponderRule {
        try await patch(
            "/api/v1/sms/auto-responders/\(id)",
            body: AutoResponderToggleRequest(enabled: enabled),
            as: AutoResponderRule.self
        )
    }

    // MARK: Delete

    /// `DELETE /api/v1/sms/auto-responders/:id` — remove a rule.
    func deleteAutoResponder(id: UUID) async throws {
        try await delete("/api/v1/sms/auto-responders/\(id)")
    }
}

// MARK: - Request / response types

/// Response envelope for `GET /api/v1/sms/auto-responders`.
public struct AutoResponderListResponse: Decodable, Sendable {
    public let rules: [AutoResponderRule]
}

/// `PATCH /api/v1/sms/auto-responders/:id` body for toggling enabled state.
public struct AutoResponderToggleRequest: Encodable, Sendable {
    public let enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
}
