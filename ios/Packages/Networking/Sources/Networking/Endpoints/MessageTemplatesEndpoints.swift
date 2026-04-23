import Foundation

// MARK: - MessageTemplate model
//
// Server ground truth: packages/server/src/routes/sms.routes.ts:839-886
//   GET    /sms/templates          → { success, data: { templates: [...], available_variables: [...] } }
//   POST   /sms/templates          → { success, data: <template> }
//   PUT    /sms/templates/:id      → { success, data: <template> }  (full update, not partial PATCH)
//   DELETE /sms/templates/:id      → { success, data: { message: "Template deleted" } }
//
// The server stores templates in `sms_templates` with columns:
//   id, name, content, category, is_active, created_at
// Note: server uses `content` not `body`, and does NOT have a `channel` column.
// The iOS `MessageTemplate.channel` is a client-side concept mapped from `category`.
// `channel` and `body` are mapped from server's `category` and `content` respectively.

public enum MessageChannel: String, Codable, CaseIterable, Sendable {
    case sms = "sms"
    case email = "email"
}

public enum MessageTemplateCategory: String, Codable, CaseIterable, Sendable {
    case reminder = "reminder"
    case promo = "promo"
    case confirmation = "confirmation"
    case apology = "apology"

    public var displayName: String {
        switch self {
        case .reminder: return "Reminder"
        case .promo: return "Promo"
        case .confirmation: return "Confirmation"
        case .apology: return "Apology"
        }
    }
}

/// Matches the `sms_templates` table row shape.
/// Server sends: `id`, `name`, `content`, `category`, `is_active`, `created_at`.
public struct MessageTemplate: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public var name: String
    /// Maps to server column `content`.
    public var body: String
    /// Client-side concept; SMS templates from `/sms/templates` are always `.sms`.
    public var channel: MessageChannel
    /// Maps to server column `category` (nullable → defaults to `.reminder`).
    public var category: MessageTemplateCategory
    public let createdAt: String?

    public init(
        id: Int64,
        name: String,
        body: String,
        channel: MessageChannel,
        category: MessageTemplateCategory,
        createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.channel = channel
        self.category = category
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Server field is `content`; fall back to `body` for forward compat.
        if let content = try? c.decode(String.self, forKey: .content) {
            body = content
        } else {
            body = (try? c.decode(String.self, forKey: .body)) ?? ""
        }
        channel = (try? c.decode(MessageChannel.self, forKey: .channel)) ?? .sms
        category = (try? c.decode(MessageTemplateCategory.self, forKey: .category)) ?? .reminder
        createdAt = try? c.decode(String.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(body, forKey: .content)   // send as `content` to server
        try c.encode(channel, forKey: .channel)
        try c.encode(category, forKey: .category)
        try? c.encode(createdAt, forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, channel, category
        case body     = "body"     // unused on decode; kept so tests can encode
        case content  = "content"  // server field name
        case createdAt = "created_at"
    }
}

/// Envelope from `GET /sms/templates`.
public struct SmsTemplateListData: Decodable, Sendable {
    public let templates: [MessageTemplate]
    public let availableVariables: [String]?

    public init(templates: [MessageTemplate], availableVariables: [String]? = nil) {
        self.templates = templates
        self.availableVariables = availableVariables
    }

    enum CodingKeys: String, CodingKey {
        case templates
        case availableVariables = "available_variables"
    }
}

// Keep for backward compat used by other tests.
public typealias MessageTemplateListResponse = SmsTemplateListData

// MARK: - Request bodies

/// `POST /sms/templates` — server reads `name`, `content`, `category`.
public struct CreateMessageTemplateRequest: Encodable, Sendable {
    public let name: String
    public let content: String
    public let category: String

    public init(name: String, body: String, channel: MessageChannel, category: MessageTemplateCategory) {
        self.name = name
        self.content = body
        self.category = category.rawValue
    }
}

/// `PUT /sms/templates/:id` — server reads `name`, `content`, `category`, `is_active`.
public struct UpdateMessageTemplateRequest: Encodable, Sendable {
    public let name: String
    public let content: String
    public let category: String

    public init(name: String, body: String, channel: MessageChannel, category: MessageTemplateCategory) {
        self.name = name
        self.content = body
        self.category = category.rawValue
    }
}

// MARK: - APIClient extensions
// Ground truth: sms.routes.ts:839–886

public extension APIClient {
    /// `GET /api/v1/sms/templates`
    func listMessageTemplates() async throws -> [MessageTemplate] {
        try await get("/api/v1/sms/templates", as: SmsTemplateListData.self).templates
    }

    /// `POST /api/v1/sms/templates`
    func createMessageTemplate(_ req: CreateMessageTemplateRequest) async throws -> MessageTemplate {
        try await post("/api/v1/sms/templates", body: req, as: MessageTemplate.self)
    }

    /// `PUT /api/v1/sms/templates/:id` (server uses PUT, not PATCH)
    func updateMessageTemplate(id: Int64, _ req: UpdateMessageTemplateRequest) async throws -> MessageTemplate {
        try await put("/api/v1/sms/templates/\(id)", body: req, as: MessageTemplate.self)
    }

    /// `DELETE /api/v1/sms/templates/:id`
    func deleteMessageTemplate(id: Int64) async throws {
        try await delete("/api/v1/sms/templates/\(id)")
    }
}
