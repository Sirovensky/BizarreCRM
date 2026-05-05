import Foundation
import Networking

// MARK: - APIClient + Recurring expense endpoints
//
// Server: packages/server/src/routes/expenses.routes.ts
//   GET    /api/v1/expenses/recurring        — list all recurring rules for the tenant
//   POST   /api/v1/expenses/recurring        — create a new rule
//   DELETE /api/v1/expenses/recurring/:id    — delete a rule
//
// RecurringExpenseRule / CreateRecurringExpenseBody are defined in
// RecurringExpenseRule.swift (this package). Extension lives here to avoid
// cross-package DTO duplication.

public extension APIClient {

    /// `GET /api/v1/expenses/recurring` — fetch all recurring expense rules.
    func listRecurringExpenseRules() async throws -> [RecurringExpenseRule] {
        try await get("/api/v1/expenses/recurring", as: [RecurringExpenseRule].self)
    }

    /// `POST /api/v1/expenses/recurring` — create a new recurring expense rule.
    func createRecurringExpenseRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule {
        try await post("/api/v1/expenses/recurring", body: body, as: RecurringExpenseRule.self)
    }

    /// `DELETE /api/v1/expenses/recurring/:id` — permanently remove a rule.
    func deleteRecurringExpenseRule(id: Int64) async throws {
        try await delete("/api/v1/expenses/recurring/\(id)")
    }
}
