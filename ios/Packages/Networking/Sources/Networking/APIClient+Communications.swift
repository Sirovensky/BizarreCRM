import Foundation

/// Communications-module conveniences on `APIClient`.
///
/// Ground truth routes (packages/server/src/routes/sms.routes.ts):
///   PATCH /sms/conversations/:phone/archive  → SmsConversationArchiveResult  (ENR-SMS7)
///   POST  /sms/preview-template             → SmsTemplatePreviewResult
///
/// All other SMS/template endpoints live in their canonical endpoint files:
///   SmsEndpoints.swift      — conversations list, flag, pin, read, archive, mark-read
///   SmsThreadEndpoints.swift — thread fetch, send
///   MessageTemplatesEndpoints.swift — templates CRUD
///
/// This extension is append-only per §12 ownership rules.
public extension APIClient {

    // MARK: - Preview template

    /// `POST /api/v1/sms/preview-template` — render a template with caller-supplied vars.
    /// Server: sms.routes.ts:892.
    /// Returns the rendered preview string and its character count.
    func previewSmsTemplate(
        templateId: Int64,
        vars: [String: String]
    ) async throws -> SmsTemplatePreviewResult {
        let body = SmsTemplatePreviewRequest(templateId: templateId, vars: vars)
        return try await post("/api/v1/sms/preview-template", body: body, as: SmsTemplatePreviewResult.self)
    }
}

// MARK: - Request / response types

/// `POST /api/v1/sms/preview-template` request body.
/// Server reads: `template_id`, `vars`.
public struct SmsTemplatePreviewRequest: Encodable, Sendable {
    public let templateId: Int64
    public let vars: [String: String]

    public init(templateId: Int64, vars: [String: String]) {
        self.templateId = templateId
        self.vars = vars
    }

    enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case vars
    }
}

/// Response data from `POST /api/v1/sms/preview-template`.
/// Server: `{ preview: String, char_count: Int }`.
public struct SmsTemplatePreviewResult: Decodable, Sendable {
    public let preview: String
    public let charCount: Int

    enum CodingKeys: String, CodingKey {
        case preview
        case charCount = "char_count"
    }
}
