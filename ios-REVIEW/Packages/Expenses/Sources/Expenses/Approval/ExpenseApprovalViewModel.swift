import Foundation
import Observation
import Networking
import Core

// MARK: - ApprovalDecision

public enum ApprovalDecision: Sendable, Equatable {
    case approved
    case denied(reason: String)
}

// MARK: - ApproveExpenseBody / DenyExpenseBody

struct ApproveExpenseBody: Encodable, Sendable {
    let approved: Bool = true
}

struct DenyExpenseBody: Encodable, Sendable {
    let reason: String
}

// MARK: - ApprovalAuditEntry

public struct ApprovalAuditEntry: Sendable, Identifiable {
    public let id: UUID
    public let expenseId: Int64
    public let decision: ApprovalDecision
    public let decidedAt: Date
    public let managerNote: String?

    public init(expenseId: Int64, decision: ApprovalDecision, managerNote: String? = nil) {
        self.id = UUID()
        self.expenseId = expenseId
        self.decision = decision
        self.decidedAt = Date()
        self.managerNote = managerNote
    }
}

// MARK: - BudgetWarning

public struct BudgetWarning: Sendable, Equatable {
    public let employeeId: Int64
    public let monthlyLimitCents: Int
    public let spentCents: Int
    public var overagePercent: Double {
        guard monthlyLimitCents > 0 else { return 0 }
        return Double(spentCents - monthlyLimitCents) / Double(monthlyLimitCents) * 100
    }
}

// MARK: - ExpenseApprovalViewModel

@MainActor
@Observable
public final class ExpenseApprovalViewModel {

    // MARK: - State

    public enum LoadState: Sendable {
        case idle, loading, loaded([Expense]), failed(String)
    }

    public var state: LoadState = .idle
    public var denyReason: String = ""
    public var processingId: Int64?
    public var errorMessage: String?
    public var budgetWarning: BudgetWarning?
    public private(set) var auditLog: [ApprovalAuditEntry] = []

    private let api: APIClient
    private let monthlyBudgetCents: Int?    // nil = no limit configured

    // MARK: - Init

    public init(api: APIClient, monthlyBudgetCents: Int? = nil) {
        self.api = api
        self.monthlyBudgetCents = monthlyBudgetCents
    }

    // MARK: - Load pending

    public func loadPending() async {
        state = .loading
        do {
            let resp: ExpensesListResponse = try await api.get(
                "/api/v1/expenses",
                query: [URLQueryItem(name: "approval_status", value: "pending"),
                        URLQueryItem(name: "pagesize", value: "100")],
                as: ExpensesListResponse.self
            )
            state = .loaded(resp.expenses)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Approve

    public func approve(expense: Expense) async {
        guard processingId == nil else { return }
        processingId = expense.id
        defer { processingId = nil }
        errorMessage = nil

        do {
            _ = try await api.post(
                "/api/v1/expenses/\(expense.id)/approve",
                body: ApproveExpenseBody(),
                as: Expense.self
            )
            let entry = ApprovalAuditEntry(expenseId: expense.id, decision: .approved)
            auditLog = auditLog + [entry]
            checkBudget(expense: expense)
            await loadPending()
        } catch {
            AppLog.ui.error("Approve expense \(expense.id) failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Deny

    public func deny(expense: Expense, reason: String) async {
        guard processingId == nil, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "A denial reason is required."
            return
        }
        processingId = expense.id
        defer { processingId = nil }
        errorMessage = nil

        do {
            _ = try await api.post(
                "/api/v1/expenses/\(expense.id)/deny",
                body: DenyExpenseBody(reason: reason),
                as: Expense.self
            )
            let entry = ApprovalAuditEntry(expenseId: expense.id, decision: .denied(reason: reason), managerNote: reason)
            auditLog = auditLog + [entry]
            denyReason = ""
            await loadPending()
        } catch {
            AppLog.ui.error("Deny expense \(expense.id) failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Budget guard

    private func checkBudget(expense: Expense) {
        guard let limit = monthlyBudgetCents,
              let amount = expense.amount,
              let employeeId = expense.userId else { return }
        let amountCents = Int((amount * 100).rounded())
        let warning = BudgetWarning(
            employeeId: employeeId,
            monthlyLimitCents: limit,
            spentCents: amountCents
        )
        if amountCents > limit {
            budgetWarning = warning
        }
    }
}
