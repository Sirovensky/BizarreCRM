import Foundation

// MARK: - APIClient+Dashboard
//
// Append-only extension. All dashboard data routes.
//
// Routes grounded against packages/server/src/routes/reports.routes.ts:
//   GET /api/v1/reports/dashboard        — open tickets, revenue today, KPI summary
//   GET /api/v1/reports/needs-attention  — stale tickets, overdue invoices, low stock
//
// Note: models and method bodies live in Endpoints/DashboardEndpoints.swift.
// This file re-exports the extension so it is discoverable under the canonical
// "APIClient+Dashboard" naming convention used across the Networking package.
//
// Decoder uses .convertFromSnakeCase, so server keys map automatically:
//   open_tickets           → openTickets
//   revenue_today          → revenueToday
//   missing_parts_count    → missingPartsCount
//   low_stock_count        → lowStockCount
//   stale_tickets          → staleTickets (array)
//   overdue_invoices       → overdueInvoices (array)

// Implementation is in Endpoints/DashboardEndpoints.swift.
// Nothing additional to declare here — the extension defined there
// is already visible within the Networking module.

// MARK: - §59 Financial Dashboard — owner-PL summary
//
// Route: GET /api/v1/owner-pl/summary?from=YYYY-MM-DD&to=YYYY-MM-DD&rollup=day|week|month
// Grounded against packages/server/src/routes/ownerPl.routes.ts:534
// Envelope: { success: Bool, data: FinancialSummaryWire }
//
// NOTE: FinancialSummaryWire and FinancialQueryParams are declared in
// ios/Packages/Dashboard/Sources/Dashboard/Financial/FinancialDashboardModels.swift.
// They are NOT re-declared here (ownership rule: append-only, never re-declare).
//
// This extension is intentionally left as a stub comment block.
// The concrete method body lives in DashboardEndpoints.swift below the existing
// dashboardSummary() and needsAttention() methods to keep network logic co-located.
// The Dashboard module imports Networking, so it can call api.ownerPLSummary(params:)
// directly.  The method is added in Endpoints/DashboardEndpoints.swift (see below)
// rather than here to avoid splitting the concrete call-site across two files.
//
// — ownerPLSummary(params:) is defined in Endpoints/DashboardEndpoints.swift
