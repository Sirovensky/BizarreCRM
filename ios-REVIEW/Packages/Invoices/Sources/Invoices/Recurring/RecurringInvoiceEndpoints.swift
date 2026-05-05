import Foundation
import Networking

// §7.8 Recurring Invoice CRUD endpoints

public extension APIClient {

    /// `GET /api/v1/invoices/recurring` — list all rules for the tenant.
    func listRecurringRules() async throws -> [RecurringInvoiceRule] {
        try await get(
            "/api/v1/invoices/recurring",
            query: nil,
            as: [RecurringInvoiceRule].self
        )
    }

    /// `GET /api/v1/invoices/recurring/:id`
    func recurringRule(id: Int64) async throws -> RecurringInvoiceRule {
        try await get(
            "/api/v1/invoices/recurring/\(id)",
            query: nil,
            as: RecurringInvoiceRule.self
        )
    }

    /// `POST /api/v1/invoices/recurring`
    func createRecurringRule(_ req: CreateRecurringRuleRequest) async throws -> RecurringInvoiceRule {
        try await post(
            "/api/v1/invoices/recurring",
            body: req,
            as: RecurringInvoiceRule.self
        )
    }

    /// `PUT /api/v1/invoices/recurring/:id`
    func updateRecurringRule(id: Int64, _ req: CreateRecurringRuleRequest) async throws -> RecurringInvoiceRule {
        try await put(
            "/api/v1/invoices/recurring/\(id)",
            body: req,
            as: RecurringInvoiceRule.self
        )
    }

    /// `DELETE /api/v1/invoices/recurring/:id`
    func deleteRecurringRule(id: Int64) async throws {
        try await delete("/api/v1/invoices/recurring/\(id)")
    }
}
