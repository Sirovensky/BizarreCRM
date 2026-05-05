// MARK: - Invoices API (append-only)
//
// Ownership: §7 Invoices — Payment Recording (iOS)
//
// Confirmed server routes (method → path → response shape):
//   GET    /api/v1/invoices                  → { success, data: { invoices, pagination, aging_summary } }
//   GET    /api/v1/invoices/:id              → { success, data: InvoiceDetail }
//   POST   /api/v1/invoices/:id/payments     → { success, data: RecordPaymentResponse }
//     Body: { amount (Double dollars), method, method_detail?, transaction_id?,
//             notes?, payment_type ("payment" | "deposit") }
//     Server: invoices.routes.ts:537 — idempotent + requirePermission('invoices.record_payment')
//     409 → duplicate payment within 5 s window; 400 → voided invoice or bad customer_id.
//
//   POST   /api/v1/refunds                   → { success, data: { id } }
//     Body: { invoice_id?, customer_id, amount (Double dollars), type, reason?, method? }
//     Server: refunds.routes.ts:107 — idempotent + requirePermission('refunds.create')
//     Role gate: admin or manager (enforced server-side, 403 returned otherwise).
//     Approval step: PATCH /api/v1/refunds/:id/approve  (separate permission)
//
// All implementation lives in Endpoints/InvoicesEndpoints.swift (same module).
// This file is the declared ownership point for §7 Invoices — append new
// invoice/payment endpoint wrappers here as the server exposes them.

// This file is intentionally left as a documentation/ownership marker.
// Append new methods to the APIClient extensions in Endpoints/InvoicesEndpoints.swift.
