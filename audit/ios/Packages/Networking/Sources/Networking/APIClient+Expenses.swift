// MARK: - §11 Expenses — ownership marker
//
// Ownership: §11 Expenses (iOS) — Agent 5.
//
// Confirmed server routes (method → path):
//   GET    /api/v1/expenses                      → ExpensesListResponse (ExpensesEndpoints.swift)
//   GET    /api/v1/expenses/:id                  → Expense (ExpensesEndpoints.swift)
//   POST   /api/v1/expenses                      → ExpenseWriteResponse (ExpensesEndpoints.swift)
//   PUT    /api/v1/expenses/:id                  → ExpenseWriteResponse (ExpensesEndpoints.swift)
//   DELETE /api/v1/expenses/:id                  → (void) (ExpensesEndpoints.swift)
//   POST   /api/v1/expenses/:id/receipt          → ExpenseReceiptUploadResponse (ExpensesEndpoints.swift)
//   GET    /api/v1/expenses/:id/receipt          → ExpenseReceiptStatusResponse (ExpensesEndpoints.swift)
//   DELETE /api/v1/expenses/:id/receipt          → (void) (ExpensesEndpoints.swift)
//   POST   /api/v1/expenses/mileage              → MileageEntry (Expenses pkg: MileageEndpoints.swift)
//   GET    /api/v1/expenses/recurring            → [RecurringExpenseRule] (Expenses pkg: RecurringExpenseEndpoints.swift)
//   POST   /api/v1/expenses/recurring            → RecurringExpenseRule (Expenses pkg: RecurringExpenseEndpoints.swift)
//   DELETE /api/v1/expenses/recurring/:id        → (void) (Expenses pkg: RecurringExpenseEndpoints.swift)
//
// Mileage and recurring-rule types (`MileageEntry`, `RecurringExpenseRule`) are
// defined in the `Expenses` SwiftPM package, not here, so their APIClient
// extensions live in the Expenses package itself (MileageEndpoints.swift /
// RecurringExpenseEndpoints.swift) to avoid cross-package DTO duplication.
//
// General expense CRUD + receipt upload: Endpoints/ExpensesEndpoints.swift.
