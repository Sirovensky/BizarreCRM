import Foundation
import Networking
import Core

// MARK: - RecurringExpenseRunner

/// Client-side runner: fetches recurring rules via the repository and surfaces
/// which one is due next — e.g. "Next recurring expense: Rent on Dec 1".
/// Server generates actual expense records; this only drives dashboard UX.
public actor RecurringExpenseRunner {

    // MARK: - Properties

    private let repository: any RecurringExpenseRepository
    private var cachedRules: [RecurringExpenseRule] = []
    private var lastFetchedAt: Date?

    // MARK: - Init

    /// Primary init — inject a pre-built repository (testable).
    public init(repository: any RecurringExpenseRepository) {
        self.repository = repository
    }

    /// Convenience init for callers that hold an `APIClient` directly.
    public init(api: APIClient) {
        self.repository = LiveRecurringExpenseRepository(api: api)
    }

    // MARK: - Public API

    /// Returns the next upcoming recurring expense label, e.g. "Rent on Jan 1".
    public func nextOccurrenceLabel(relativeTo date: Date = Date()) async -> String? {
        await refreshIfNeeded()
        return upcomingRule(relativeTo: date)?.nextOccurrenceLabel(relativeTo: date)
    }

    /// The full list of rules (for `RecurringExpenseListView`).
    public func fetchRules() async throws -> [RecurringExpenseRule] {
        let rules = try await repository.fetchRules()
        cachedRules = rules
        lastFetchedAt = Date()
        return rules
    }

    public func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule {
        try await repository.createRule(body)
    }

    public func deleteRule(id: Int64) async throws {
        try await repository.deleteRule(id: id)
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
