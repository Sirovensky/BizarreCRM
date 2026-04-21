import Foundation
import Networking
import Core

// MARK: - RecurringExpenseRunner

/// Client-side runner: fetches recurring rules and tells the UI which one
/// is due next. Server generates actual expense records; this just surfaces
/// "Next recurring expense: Rent on Dec 1" in the dashboard.
public actor RecurringExpenseRunner {

    // MARK: - Properties

    private let api: APIClient
    private var cachedRules: [RecurringExpenseRule] = []
    private var lastFetchedAt: Date?

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Returns the next upcoming recurring expense label, e.g. "Rent on Jan 1".
    public func nextOccurrenceLabel(relativeTo date: Date = Date()) async -> String? {
        await refreshIfNeeded()
        return upcomingRule(relativeTo: date)?.nextOccurrenceLabel(relativeTo: date)
    }

    /// The full list of rules (for `RecurringExpenseListView`).
    public func fetchRules() async throws -> [RecurringExpenseRule] {
        let rules: [RecurringExpenseRule] = try await api.get(
            "/api/v1/expenses/recurring", as: [RecurringExpenseRule].self
        )
        cachedRules = rules
        lastFetchedAt = Date()
        return rules
    }

    public func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule {
        try await api.post("/api/v1/expenses/recurring", body: body, as: RecurringExpenseRule.self)
    }

    public func deleteRule(id: Int64) async throws {
        try await api.delete("/api/v1/expenses/recurring/\(id)")
    }

    // MARK: - Private

    private func refreshIfNeeded() async {
        guard let last = lastFetchedAt,
              Date().timeIntervalSince(last) < 300 else {
            _ = try? await fetchRules()
            return
        }
    }

    private func upcomingRule(relativeTo date: Date) -> RecurringExpenseRule? {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let today = cal.startOfDay(for: date)

        return cachedRules.min { lhs, rhs in
            nextDate(for: lhs, after: today, cal: cal) < nextDate(for: rhs, after: today, cal: cal)
        }
    }

    private func nextDate(for rule: RecurringExpenseRule, after today: Date, cal: Calendar) -> Date {
        var components = cal.dateComponents([.year, .month], from: today)
        components.day = min(rule.dayOfMonth, cal.range(of: .day, in: .month, for: today)?.count ?? rule.dayOfMonth)
        guard var candidate = cal.date(from: components) else { return .distantFuture }
        if candidate <= today {
            switch rule.frequency {
            case .monthly: candidate = cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            case .yearly:  candidate = cal.date(byAdding: .year,  value: 1, to: candidate) ?? candidate
            }
        }
        return candidate
    }
}
