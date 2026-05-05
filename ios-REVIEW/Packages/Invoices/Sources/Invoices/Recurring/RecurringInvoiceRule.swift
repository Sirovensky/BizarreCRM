import Foundation

// §7.8 Recurring Invoice Rule

// MARK: - RecurringFrequency

public enum RecurringFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case monthly  = "monthly"
    case quarterly = "quarterly"
    case yearly   = "yearly"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly:    return "Yearly"
        }
    }
}

// MARK: - RecurringInvoiceRule

/// Server-authoritative rule that governs automatic invoice generation.
/// Client displays history; server executes the schedule.
public struct RecurringInvoiceRule: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// The customer for whom invoices will be generated.
    public let customerId: Int64
    /// Template invoice whose line items are copied on each run.
    public let templateInvoiceId: Int64
    /// How often the rule fires.
    public let frequency: RecurringFrequency
    /// Day-of-month (1–28) on which the invoice is generated.
    public let dayOfMonth: Int
    /// UTC timestamp of the next scheduled run.
    public let nextRunAt: Date
    /// When the rule became (or becomes) active.
    public let startDate: Date
    /// Optional hard stop; nil = runs indefinitely.
    public let endDate: Date?
    /// If true the server emails the generated invoice automatically.
    public let autoSend: Bool
    /// Optional human label for admin UI.
    public let name: String?

    public init(
        id: Int64,
        customerId: Int64,
        templateInvoiceId: Int64,
        frequency: RecurringFrequency,
        dayOfMonth: Int,
        nextRunAt: Date,
        startDate: Date,
        endDate: Date? = nil,
        autoSend: Bool = false,
        name: String? = nil
    ) {
        self.id = id
        self.customerId = customerId
        self.templateInvoiceId = templateInvoiceId
        self.frequency = frequency
        self.dayOfMonth = max(1, min(28, dayOfMonth))
        self.nextRunAt = nextRunAt
        self.startDate = startDate
        self.endDate = endDate
        self.autoSend = autoSend
        self.name = name
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, frequency, name
        case customerId        = "customer_id"
        case templateInvoiceId = "template_invoice_id"
        case dayOfMonth        = "day_of_month"
        case nextRunAt         = "next_run_at"
        case startDate         = "start_date"
        case endDate           = "end_date"
        case autoSend          = "auto_send"
    }
}

// MARK: - Create / Update DTOs

public struct CreateRecurringRuleRequest: Encodable, Sendable {
    public let customerId: Int64
    public let templateInvoiceId: Int64
    public let frequency: String
    public let dayOfMonth: Int
    public let startDate: String   // YYYY-MM-DD
    public let endDate: String?
    public let autoSend: Bool
    public let name: String?

    public init(
        customerId: Int64,
        templateInvoiceId: Int64,
        frequency: RecurringFrequency,
        dayOfMonth: Int,
        startDate: String,
        endDate: String? = nil,
        autoSend: Bool = false,
        name: String? = nil
    ) {
        self.customerId = customerId
        self.templateInvoiceId = templateInvoiceId
        self.frequency = frequency.rawValue
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.endDate = endDate
        self.autoSend = autoSend
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case frequency, name
        case customerId        = "customer_id"
        case templateInvoiceId = "template_invoice_id"
        case dayOfMonth        = "day_of_month"
        case startDate         = "start_date"
        case endDate           = "end_date"
        case autoSend          = "auto_send"
    }
}
