import Foundation
import Networking

// MARK: - EmailTemplateCategory

/// Category of an email template.
public enum EmailTemplateCategory: String, Codable, CaseIterable, Sendable {
    case reminder = "reminder"
    case promo = "promo"
    case confirmation = "confirmation"
    case invoice = "invoice"
    case followup = "followup"

    public var displayName: String {
        switch self {
        case .reminder: return "Reminder"
        case .promo: return "Promo"
        case .confirmation: return "Confirmation"
        case .invoice: return "Invoice"
        case .followup: return "Follow-up"
        }
    }
}

// MARK: - EmailTemplate

/// An email template with HTML + plain bodies and dynamic variables.
public struct EmailTemplate: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public var name: String
    public var subject: String
    public var htmlBody: String
    /// Explicit plain-text version. When `nil`, plain text is derived by stripping HTML from `htmlBody`.
    public var plainBody: String?
    public var category: EmailTemplateCategory
    /// Variable tokens referenced in this template, e.g. `["{first_name}", "{ticket_no}"]`.
    public var dynamicVars: [String]
    public let createdAt: String?

    public init(
        id: Int64,
        name: String,
        subject: String,
        htmlBody: String,
        plainBody: String?,
        category: EmailTemplateCategory,
        dynamicVars: [String],
        createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainBody = plainBody
        self.category = category
        self.dynamicVars = dynamicVars
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, subject, category
        case htmlBody = "html_body"
        case plainBody = "plain_body"
        case dynamicVars = "dynamic_vars"
        case createdAt = "created_at"
    }
}

// MARK: - Request / Response types

public struct EmailTemplateListResponse: Decodable, Sendable {
    public let templates: [EmailTemplate]

    public init(templates: [EmailTemplate]) {
        self.templates = templates
    }
}

public struct CreateEmailTemplateRequest: Encodable, Sendable {
    public let name: String
    public let subject: String
    public let htmlBody: String
    public let plainBody: String?
    public let category: EmailTemplateCategory
    public let dynamicVars: [String]

    public init(
        name: String,
        subject: String,
        htmlBody: String,
        plainBody: String?,
        category: EmailTemplateCategory,
        dynamicVars: [String]
    ) {
        self.name = name
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainBody = plainBody
        self.category = category
        self.dynamicVars = dynamicVars
    }

    enum CodingKeys: String, CodingKey {
        case name, subject, category
        case htmlBody = "html_body"
        case plainBody = "plain_body"
        case dynamicVars = "dynamic_vars"
    }
}

public struct UpdateEmailTemplateRequest: Encodable, Sendable {
    public let name: String
    public let subject: String
    public let htmlBody: String
    public let plainBody: String?
    public let category: EmailTemplateCategory
    public let dynamicVars: [String]

    public init(
        name: String,
        subject: String,
        htmlBody: String,
        plainBody: String?,
        category: EmailTemplateCategory,
        dynamicVars: [String]
    ) {
        self.name = name
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainBody = plainBody
        self.category = category
        self.dynamicVars = dynamicVars
    }

    enum CodingKeys: String, CodingKey {
        case name, subject, category
        case htmlBody = "html_body"
        case plainBody = "plain_body"
        case dynamicVars = "dynamic_vars"
    }
}

// MARK: - Send request + ack

public struct EmailSendRequest: Encodable, Sendable {
    public let to: String
    public let subject: String
    public let htmlBody: String
    public let plainBody: String

    public init(to: String, subject: String, htmlBody: String, plainBody: String) {
        self.to = to
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainBody = plainBody
    }

    enum CodingKeys: String, CodingKey {
        case to, subject
        case htmlBody = "html_body"
        case plainBody = "plain_body"
    }
}

/// Minimal acknowledgement returned by `POST /emails/send`.
public struct EmailSendAck: Decodable, Sendable {
    public let queued: Bool?
    public init(queued: Bool? = true) { self.queued = queued }
}
