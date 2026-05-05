import Foundation

// MARK: - RecurringFrequency

public enum RecurringFrequency: String, Codable, Sendable, CaseIterable, Identifiable {
    case monthly
    case yearly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

// MARK: - RecurringExpenseRule

/// Server-side entity describing a recurring expense schedule.
public struct RecurringExpenseRule: Codable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let merchant: String
    public let amountCents: Int
    public let category: String
    public let frequency: RecurringFrequency
    public let dayOfMonth: Int       // 1–31
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, merchant, category, frequency, notes
        case amountCents  = "amount_cents"
        case dayOfMonth   = "day_of_month"
    }

    public init(
        id: Int64,
        merchant: String,
        amountCents: Int,
        category: String,
        frequency: RecurringFrequency,
        dayOfMonth: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.merchant = merchant
        self.amountCents = amountCents
        self.category = category
        self.frequency = frequency
        self.dayOfMonth = dayOfMonth
        self.notes = notes
    }

    // MARK: - Computed helpers

    public var amountDollars: Double { Double(amountCents) / 100.0 }

    /// Human-readable next-occurrence description, e.g. "Rent on Jan 1".
    public func nextOccurrenceLabel(relativeTo reference: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let today = cal.startOfDay(for: reference)

        var components = cal.dateComponents([.year, .month], from: today)
        components.day = min(dayOfMonth, cal.range(of: .day, in: .month, for: today)?.count ?? dayOfMonth)

        guard var candidate = cal.date(from: components) else { return merchant }

        // If candidate is today or in the past, advance by one period.
        if candidate <= today {
            switch frequency {
            case .monthly:
                candidate = cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            case .yearly:
                candidate = cal.date(byAdding: .year, value: 1, to: candidate) ?? candidate
            }
        }

        let df = DateFormatter()
        df.dateFormat = "MMM d"
        df.locale = Locale(identifier: "en_US_POSIX")
        return "\(merchant) on \(df.string(from: candidate))"
    }
}

// MARK: - Create / Update bodies

public struct CreateRecurringExpenseBody: Encodable, Sendable {
    public let merchant: String
    public let amountCents: Int
    public let category: String
    public let frequency: String
    public let dayOfMonth: Int
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case merchant, category, frequency, notes
        case amountCents  = "amount_cents"
        case dayOfMonth   = "day_of_month"
    }

    public init(rule: RecurringExpenseRule) {
        self.merchant    = rule.merchant
        self.amountCents = rule.amountCents
        self.category    = rule.category
        self.frequency   = rule.frequency.rawValue
        self.dayOfMonth  = rule.dayOfMonth
        self.notes       = rule.notes
    }

    public init(merchant: String, amountCents: Int, category: String,
                frequency: RecurringFrequency, dayOfMonth: Int, notes: String?) {
        self.merchant    = merchant
        self.amountCents = amountCents
        self.category    = category
        self.frequency   = frequency.rawValue
        self.dayOfMonth  = dayOfMonth
        self.notes       = notes
    }
}
