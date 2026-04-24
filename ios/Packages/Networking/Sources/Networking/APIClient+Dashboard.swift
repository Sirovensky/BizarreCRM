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
