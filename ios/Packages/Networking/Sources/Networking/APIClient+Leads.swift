import Foundation

// MARK: - Leads API (append-only; grounded against packages/server/src/routes/leads.routes.ts)
//
// Confirmed server routes (method → path → response shape):
//   GET    /api/v1/leads                  → { success, data: { leads, pagination } }
//   GET    /api/v1/leads/:id              → { success, data: LeadDetail }
//   PUT    /api/v1/leads/:id              → { success, data: LeadDetail }
//   POST   /api/v1/leads/:id/convert      → { success, data: { ticket, message } }
//   POST   /api/v1/leads/:id/reminder     → { success, data: LeadReminder }
//   GET    /api/v1/leads/:id/reminders    → { success, data: [LeadReminder] }
//
// All implementations live in LeadsEndpoints.swift (same Networking module).
// This file is the declared ownership point for §9 Leads — append new lead
// endpoint wrappers here as the server adds them.

// MARK: - Lead reminder types

/// Body for `POST /api/v1/leads/:id/reminder`.
public struct LeadReminderBody: Encodable, Sendable {
    /// ISO-8601 timestamp when the reminder should fire.
    public let remindAt: String
    /// Optional free-text note attached to the reminder.
    public let note: String?

    public init(remindAt: String, note: String? = nil) {
        self.remindAt = remindAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case remindAt = "remind_at"
        case note
    }
}

/// Single reminder row returned by the server.
public struct LeadReminder: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let leadId: Int64
    public let remindAt: String
    public let note: String?
    public let createdByFirstName: String?
    public let createdByLastName: String?

    enum CodingKeys: String, CodingKey {
        case id, note
        case leadId             = "lead_id"
        case remindAt           = "remind_at"
        case createdByFirstName = "created_by_first_name"
        case createdByLastName  = "created_by_last_name"
    }
}

// MARK: - Reminder endpoints extension

public extension APIClient {
    /// `POST /api/v1/leads/:id/reminder` — create a follow-up reminder.
    @discardableResult
    func createLeadReminder(leadId: Int64, body: LeadReminderBody) async throws -> LeadReminder {
        try await post("/api/v1/leads/\(leadId)/reminder", body: body, as: LeadReminder.self)
    }

    /// `GET /api/v1/leads/:id/reminders` — fetch all reminders for a lead.
    func listLeadReminders(leadId: Int64) async throws -> [LeadReminder] {
        try await get("/api/v1/leads/\(leadId)/reminders", as: [LeadReminder].self)
    }

    /// `DELETE /api/v1/leads/:id` — permanently delete a lead record.
    ///
    /// Server endpoint: `DELETE /api/v1/leads/:id` (confirmed in leads.routes.ts).
    /// Returns `{ success: true, message: "Lead deleted" }`.
    func deleteLead(id: Int64) async throws {
        _ = try await delete("/api/v1/leads/\(id)")
    }

    /// `PATCH /api/v1/leads/:id/tags` — replace the tag list on a lead.
    ///
    /// Body: `{ tags: ["vip", "corporate"] }`.
    /// Server endpoint: `PATCH /api/v1/leads/:id/tags` (§9 extension).
    @discardableResult
    func setLeadTags(leadId: Int64, tags: [String]) async throws -> LeadDetail {
        struct Body: Encodable { let tags: [String] }
        return try await patch("/api/v1/leads/\(leadId)/tags", body: Body(tags: tags), as: LeadDetail.self)
    }
}
