import Foundation

// MARK: - RevenuePoint

public struct RevenuePoint: Codable, Sendable, Identifiable {
    public let id: Int64
    public let date: String
    public let amountCents: Int64
    public let saleCount: Int

    public var amountDollars: Double { Double(amountCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case amountCents = "amount_cents"
        case saleCount   = "sale_count"
    }

    public init(id: Int64, date: String, amountCents: Int64, saleCount: Int) {
        self.id = id
        self.date = date
        self.amountCents = amountCents
        self.saleCount = saleCount
    }
}

// MARK: - TicketStatusPoint

public struct TicketStatusPoint: Codable, Sendable, Identifiable {
    public let id: Int64
    public let status: String
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case id, status, count
    }

    public init(id: Int64, status: String, count: Int) {
        self.id = id
        self.status = status
        self.count = count
    }
}

// MARK: - AvgTicketValue

public struct AvgTicketValue: Codable, Sendable {
    public let currentCents: Int64
    public let previousCents: Int64
    public let trendPct: Double

    public var currentDollars: Double  { Double(currentCents)  / 100.0 }
    public var previousDollars: Double { Double(previousCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case currentCents  = "current_cents"
        case previousCents = "previous_cents"
        case trendPct      = "trend_pct"
    }

    public init(currentCents: Int64, previousCents: Int64, trendPct: Double) {
        self.currentCents = currentCents
        self.previousCents = previousCents
        self.trendPct = trendPct
    }
}

// MARK: - EmployeePerf

public struct EmployeePerf: Codable, Sendable, Identifiable {
    public let id: Int64
    public let employeeName: String
    public let ticketsClosed: Int
    public let revenueCents: Int64
    public let avgResolutionHours: Double

    public var revenueDollars: Double { Double(revenueCents) / 100.0 }

    enum CodingKeys: String, CodingKey {
        case id
        case employeeName      = "employee_name"
        case ticketsClosed     = "tickets_closed"
        case revenueCents      = "revenue_cents"
        case avgResolutionHours = "avg_resolution_hours"
    }

    public init(id: Int64, employeeName: String, ticketsClosed: Int,
                revenueCents: Int64, avgResolutionHours: Double) {
        self.id = id
        self.employeeName = employeeName
        self.ticketsClosed = ticketsClosed
        self.revenueCents = revenueCents
        self.avgResolutionHours = avgResolutionHours
    }
}

// MARK: - InventoryTurnoverRow

public struct InventoryTurnoverRow: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sku: String
    public let name: String
    public let turnoverRate: Double
    public let daysOnHand: Double

    enum CodingKeys: String, CodingKey {
        case id
        case sku
        case name
        case turnoverRate = "turnover_rate"
        case daysOnHand   = "days_on_hand"
    }

    public init(id: Int64, sku: String, name: String,
                turnoverRate: Double, daysOnHand: Double) {
        self.id = id
        self.sku = sku
        self.name = name
        self.turnoverRate = turnoverRate
        self.daysOnHand = daysOnHand
    }
}

// MARK: - CSATScore

public struct CSATScore: Codable, Sendable {
    public let current: Double
    public let previous: Double
    public let responseCount: Int
    public let trendPct: Double

    enum CodingKeys: String, CodingKey {
        case current
        case previous
        case responseCount = "response_count"
        case trendPct      = "trend_pct"
    }

    public init(current: Double, previous: Double,
                responseCount: Int, trendPct: Double) {
        self.current = current
        self.previous = previous
        self.responseCount = responseCount
        self.trendPct = trendPct
    }
}

// MARK: - NPSScore

public struct NPSScore: Codable, Sendable {
    public let current: Int
    public let previous: Int
    public let promoterPct: Double
    public let detractorPct: Double
    public let themes: [String]

    public var passivePct: Double { max(0, 100.0 - promoterPct - detractorPct) }

    enum CodingKeys: String, CodingKey {
        case current
        case previous
        case promoterPct   = "promoter_pct"
        case detractorPct  = "detractor_pct"
        case themes
    }

    public init(current: Int, previous: Int,
                promoterPct: Double, detractorPct: Double,
                themes: [String]) {
        self.current = current
        self.previous = previous
        self.promoterPct = promoterPct
        self.detractorPct = detractorPct
        self.themes = themes
    }
}

// MARK: - DrillThroughRecord

public struct DrillThroughRecord: Codable, Sendable, Identifiable {
    public let id: Int64
    public let label: String
    public let detail: String?
    public let amountCents: Int64?

    public var amountDollars: Double? {
        guard let c = amountCents else { return nil }
        return Double(c) / 100.0
    }

    enum CodingKeys: String, CodingKey {
        case id, label, detail
        case amountCents = "amount_cents"
    }

    public init(id: Int64, label: String, detail: String?, amountCents: Int64?) {
        self.id = id
        self.label = label
        self.detail = detail
        self.amountCents = amountCents
    }
}

// MARK: - ScheduledReport

public struct ScheduledReport: Codable, Sendable, Identifiable {
    public let id: Int64
    public let reportType: String
    public let frequency: ScheduleFrequency
    public let recipientEmails: [String]
    public let isActive: Bool
    public let nextRunAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportType       = "report_type"
        case frequency
        case recipientEmails  = "recipient_emails"
        case isActive         = "is_active"
        case nextRunAt        = "next_run_at"
    }

    public init(id: Int64, reportType: String, frequency: ScheduleFrequency,
                recipientEmails: [String], isActive: Bool, nextRunAt: String?) {
        self.id = id
        self.reportType = reportType
        self.frequency = frequency
        self.recipientEmails = recipientEmails
        self.isActive = isActive
        self.nextRunAt = nextRunAt
    }
}

public enum ScheduleFrequency: String, Codable, Sendable, CaseIterable {
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"

    public var displayName: String {
        switch self {
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

// MARK: - DateRangePreset

public enum DateRangePreset: String, Sendable, CaseIterable, Identifiable {
    case sevenDays   = "7D"
    case thirtyDays  = "30D"
    case ninetyDays  = "90D"
    case custom      = "Custom"

    public var id: String { rawValue }

    public var displayLabel: String { rawValue }

    /// Returns (from, to) ISO-8601 date strings for API queries.
    public func dateRange(relativeTo now: Date = Date()) -> (from: String, to: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let to = formatter.string(from: now)
        let days: Int
        switch self {
        case .sevenDays:   days = 7
        case .thirtyDays:  days = 30
        case .ninetyDays:  days = 90
        case .custom:      days = 30 // fallback; caller provides custom dates
        }
        let from = formatter.string(from: now.addingTimeInterval(-Double(days) * 86400))
        return (from, to)
    }
}
