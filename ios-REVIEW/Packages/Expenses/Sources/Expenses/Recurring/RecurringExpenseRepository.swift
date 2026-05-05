import Foundation
import Networking
import Core

// MARK: - RecurringExpenseRepository

/// §20 containment-compliant repository for recurring expense rules.
/// All calls to `APIClient` for recurring expenses are funnelled here.
public protocol RecurringExpenseRepository: Sendable {
    /// Fetch all recurring expense rules for the current tenant.
    func fetchRules() async throws -> [RecurringExpenseRule]
    /// Create a new recurring rule. Returns the server-persisted entity.
    func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule
    /// Permanently delete a recurring rule by ID.
    func deleteRule(id: Int64) async throws
}

// MARK: - LiveRecurringExpenseRepository

public actor LiveRecurringExpenseRepository: RecurringExpenseRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func fetchRules() async throws -> [RecurringExpenseRule] {
        try await api.listRecurringExpenseRules()
    }

    public func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule {
        try await api.createRecurringExpenseRule(body)
    }

    public func deleteRule(id: Int64) async throws {
        try await api.deleteRecurringExpenseRule(id: id)
    }
}
