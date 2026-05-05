import Foundation
import Networking

// MARK: - EmailEndpoints — APIClient extension

public extension APIClient {

    // MARK: Email template CRUD

    func listEmailTemplates() async throws -> [EmailTemplate] {
        try await get("/api/v1/email-templates", as: EmailTemplateListResponse.self).templates
    }

    func createEmailTemplate(_ req: CreateEmailTemplateRequest) async throws -> EmailTemplate {
        try await post("/api/v1/email-templates", body: req, as: EmailTemplate.self)
    }

    func updateEmailTemplate(id: Int64, _ req: UpdateEmailTemplateRequest) async throws -> EmailTemplate {
        try await patch("/api/v1/email-templates/\(id)", body: req, as: EmailTemplate.self)
    }

    func deleteEmailTemplate(id: Int64) async throws {
        try await delete("/api/v1/email-templates/\(id)")
    }

    // MARK: Send email

    /// `POST /api/v1/emails/send` → `{ to, subject, html_body, plain_body }`.
    func sendEmail(_ req: EmailSendRequest) async throws -> EmailSendAck {
        try await post("/api/v1/emails/send", body: req, as: EmailSendAck.self)
    }
}
