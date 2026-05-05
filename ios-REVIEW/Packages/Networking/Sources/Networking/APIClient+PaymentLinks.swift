// MARK: - Payment Links API (append-only)
//
// Ownership: §41 Payment Links (iOS)
//
// Confirmed server routes (method → path → notes):
//   GET    /api/v1/payment-links              → list, newest first. Optional ?status filter.
//   GET    /api/v1/payment-links/:id          → full row. Manager/admin only.
//   POST   /api/v1/payment-links              → create. Body: dollars (not cents). Manager/admin only.
//                                               Response: { success, data: { id, token } }
//   DELETE /api/v1/payment-links/:id          → soft-cancel. Manager/admin only.
//                                               Response: { success, data: { id, status } }
//
// Public (no auth) routes — not called by staff iOS app; listed for completeness:
//   GET    /api/v1/public/payment-links/:token    → customer-facing lookup
//   POST   /api/v1/public/payment-links/:token/click → increment click_count
//
// Response envelope: `{ success: Bool, data: T?, message: String? }`.
// All money on the wire for CREATE is Double dollars; the DB stores integer cents.
// iOS surface is always cents-only — conversion at the edge in CreatePaymentLinkRequest.
//
// Wrappers live in Endpoints/PaymentLinksEndpoints.swift (same module).
// Append new payment-link API methods there as the server exposes them.

// This file is intentionally a documentation/ownership marker.
// All implementation lives in Endpoints/PaymentLinksEndpoints.swift.
