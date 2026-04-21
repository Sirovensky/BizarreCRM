import Foundation

// MARK: - MessageTemplate model

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

public struct MessageTemplate: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public var name: String
    public var body: String
    public var channel: MessageChannel
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

    enum CodingKeys: String, CodingKey {
        case id, name, body, channel, category
        case createdAt = "created_at"
    }
}

public struct MessageTemplateListResponse: Decodable, Sendable {
    public let templates: [MessageTemplate]

    public init(templates: [MessageTemplate]) {
        self.templates = templates
    }
}

// MARK: - Request bodies

public struct CreateMessageTemplateRequest: Encodable, Sendable {
    public let name: String
    public let body: String
    public let channel: MessageChannel
    public let category: MessageTemplateCategory

    public init(name: String, body: String, channel: MessageChannel, category: MessageTemplateCategory) {
        self.name = name
        self.body = body
        self.channel = channel
        self.category = category
    }
}

public struct UpdateMessageTemplateRequest: Encodable, Sendable {
    public let name: String
    public let body: String
    public let channel: MessageChannel
    public let category: MessageTemplateCategory

    public init(name: String, body: String, channel: MessageChannel, category: MessageTemplateCategory) {
        self.name = name
        self.body = body
        self.channel = channel
        self.category = category
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func listMessageTemplates() async throws -> [MessageTemplate] {
        try await get("/api/v1/message-templates", as: MessageTemplateListResponse.self).templates
    }

    func createMessageTemplate(_ req: CreateMessageTemplateRequest) async throws -> MessageTemplate {
        try await post("/api/v1/message-templates", body: req, as: MessageTemplate.self)
    }

    func updateMessageTemplate(id: Int64, _ req: UpdateMessageTemplateRequest) async throws -> MessageTemplate {
        try await patch("/api/v1/message-templates/\(id)", body: req, as: MessageTemplate.self)
    }

    func deleteMessageTemplate(id: Int64) async throws {
        try await delete("/api/v1/message-templates/\(id)")
    }
}
