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

    // MARK: - Customer picker (SMS compose)

    /// `GET /api/v1/customers` — minimal summaries for the SMS compose customer picker.
    ///
    /// Returns only fields needed by the picker (id, first_name, last_name, phone, mobile).
    /// Full customer detail lives in `APIClient+Customers.swift`.
    func listCustomerPickerItems() async throws -> [CustomerPickerItem] {
        let raw = try await get("/api/v1/customers", as: [CustomerPickerItemRaw].self)
        return raw.map { CustomerPickerItem(id: $0.id, firstName: $0.firstName, lastName: $0.lastName, phone: $0.phone ?? $0.mobile ?? "") }
    }

    // MARK: - SMS unread count

    /// `GET /api/v1/sms/unread-count` — total unread conversation count for badge.
    func smsUnreadCount() async throws -> SmsUnreadCountResponse {
        try await get("/api/v1/sms/unread-count", as: SmsUnreadCountResponse.self)
    }

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

// MARK: - Customer picker types

/// Minimal customer representation for SMS compose customer picker.
public struct CustomerPickerItem: Identifiable, Sendable, Hashable {
    public let id: Int64
    public let firstName: String?
    public let lastName: String?
    public let phone: String

    public init(id: Int64, firstName: String?, lastName: String?, phone: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
    }

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? phone : parts.joined(separator: " ")
    }
}

/// Raw decoding helper — maps snake_case server fields.
struct CustomerPickerItemRaw: Decodable, Sendable {
    let id: Int64
    let firstName: String?
    let lastName: String?
    let phone: String?
    let mobile: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName  = "last_name"
        case phone, mobile
    }
}

// MARK: - Unread count response

/// Response for `GET /api/v1/sms/unread-count`.
public struct SmsUnreadCountResponse: Decodable, Sendable {
    public let count: Int
}
