# iOS — Server API Gap Audit (§74)

_Last audited: 2026-04-20 against `packages/server/src/routes/`._

Phase 0 baseline expected the endpoints below to exist or be explicitly
stubbed. This file records actual status so Phase 2+ surfaces know which
domains can ship vs. which need a server ticket opened first.

Re-run quarterly. Update `Status` + `Source` columns in-place; add rows
for new endpoints rather than editing old ones so git history stays
useful.

## Matrix

| # | Endpoint | Status | Source | Notes |
|---|----------|--------|--------|-------|
| 1  | `POST /telemetry/events`            | **missing** | —                                    | Required by §32 (analytics). iOS shim returns `APIError.notImplemented`. |
| 2  | `POST /telemetry/crashes`           | **missing** | —                                    | Required by §32.3. Until server ships, iOS buffers to a local ring buffer and drops on rotation. |
| 3  | `GET /sync/delta?since=<cursor>`    | **missing** | —                                    | Required by §20.4 (delta sync). Without it, offline-first relies entirely on per-list cursor pagination — acceptable short-term. |
| 4  | `POST /sync/conflicts/resolve`      | **missing** | —                                    | Required by §20.6. iOS currently wins-or-queues; no server-authoritative conflict merge. |
| 5  | `POST /device-tokens`               | **missing** | —                                    | Required by §21.1. Blocks remote push. Local notifications only until shipped. |
| 6  | `POST /call-logs`                   | **missing** | —                                    | Required by §42. Call history ingestion blocked; tickets can still be created manually. |
| 7  | `GET /gift-cards/:code`             | exists      | `giftCards.routes.ts:159` (`/lookup/:code`) | URL mismatch — iOS APIClient must post to `/lookup/:code` not the bare pattern. |
| 8  | `POST /gift-cards/redeem`           | exists      | `giftCards.routes.ts:290` (`/:id/redeem`) | URL mismatch — iOS must PATCH `/gift-cards/:id/redeem`. |
| 9  | `POST /store-credit/:customerId`    | **missing** | —                                    | Only embedded in invoice flow. Needed for standalone store-credit grants per §40. |
| 10 | `POST /payment-links`               | exists      | `paymentLinks.routes.ts:105`         | Happy path works. |
| 11 | `GET /payment-links/:id/status`     | **partial** | `paymentLinks.routes.ts:96` (`/:id`) | Base `GET /:id` exists; no dedicated `/status` suffix. iOS must poll `/:id` and read fields client-side. |
| 12 | `GET /public/tracking/:shortId`     | **partial** | `tracking.routes.ts:170+`            | Uses `/token/:token` + `/lookup` paths. iOS deep-link shortener needs to match server URL shape. |
| 13 | `POST /nlq-search`                  | **missing** | —                                    | Required by §18.6. Without NLQ, global search falls back to the existing multi-entity search endpoint. |
| 14 | `POST /pos/cash-sessions`           | **missing** | —                                    | Only `/pos/cash-in` + `/pos/cash-out` exist. Required by §39 session open/close. |
| 15 | `POST /pos/cash-sessions/:id/close` | **missing** | —                                    | Same as above. POS can still transact, but reconciliation report is not available. |
| 16 | `GET /audit-logs`                   | exists      | `settings.routes.ts:1652`            | Admin-only. |
| 17 | `POST /imports/start`               | **partial** | `import.routes.ts:221` (`/repairdesk/start`) | Only the RepairDesk-specific path exists. Generalized `/start` for CSV / other vendors still TBD. |
| 18 | `GET /imports/:id/status`           | **partial** | `import.routes.ts:340` (`/repairdesk/status`) | Same. |
| 19 | `POST /exports/start`               | exists      | `tenantExport.routes.ts:92`          | Enqueues export job. |
| 20 | `GET /exports/:id/download`         | exists      | `tenantExport.routes.ts:156` (`/download/:signedToken`) | URL mismatch — iOS must use signed-token path, not naive `:id`. |
| 21 | `POST /tickets/:id/signatures`      | **missing** | —                                    | Required by §4.5. Signature capture blocked. |
| 22 | `POST /tickets/:id/pre-conditions`  | **missing** | —                                    | Required by §4.3. Pre-condition checklist blocked. |
| 23 | `GET /device-templates`             | exists      | `deviceTemplates.routes.ts:139`      | Happy path works. |
| 24 | `POST /locations`                   | **missing** | —                                    | Required by §60. Multi-location tenants blocked on create. |
| 25 | `GET /memberships/:id/wallet-pass`  | **partial** | `crm.routes.ts:250` (`/customers/:id/wallet-pass`) | Exists under `/customers/:id/wallet-pass`; membership vs. customer ID mismatch needs reconciling. |

## Server tickets to open

**Block until server ships:**

- `TELEMETRY-IOS-001` — POST `/telemetry/events` + POST `/telemetry/crashes`.
- `SYNC-DELTA-001` — GET `/sync/delta?since=cursor` + POST `/sync/conflicts/resolve`.
- `PUSH-TOKEN-001` — POST `/device-tokens` (APNs registration).
- `CALL-LOG-001` — POST `/call-logs`.
- `NLQ-SEARCH-001` — POST `/nlq-search`.
- `POS-SESSIONS-001` — POST `/pos/cash-sessions` + POST `/pos/cash-sessions/:id/close`.
- `TICKET-SIGNATURES-001` — POST `/tickets/:id/signatures`.
- `TICKET-PRECONDITIONS-001` — POST `/tickets/:id/pre-conditions`.
- `LOCATIONS-001` — POST `/locations`.
- `STORE-CREDIT-STANDALONE-001` — POST `/store-credit/:customerId` (outside invoice flow).

**URL-shape mismatches (cheap server alias OR iOS path correction):**

- Gift cards — `/gift-cards/lookup/:code` and `/gift-cards/:id/redeem`. Decide: rename server route or teach APIClient the real path.
- Payment link status — iOS reads `GET /payment-links/:id` and inspects `status` field; no server change needed.
- Public tracking — align on `/public/tracking/token/:token` for the signed link.
- Export download — use server's `/exports/download/:signedToken`.
- Wallet pass — iOS hits `/customers/:id/wallet-pass` (accepts customer ID as membership key when they match).

## iOS side — shim posture

For every `missing` endpoint:

1. Repository catches `APITransportError.httpStatus(404, _)` or `APITransportError.httpStatus(501, _)` and surfaces a typed `FeatureUnavailable` error.
2. View renders "Coming soon — not yet enabled on your server." No crash, no retry loop.
3. Mutations that would have enqueued into `SyncQueueStore` instead show a dismissible banner and drop the input — we don't queue for endpoints that don't exist, because the flush worker will just DLQ every retry.

## Schedule

- **Next audit:** 2026-07-20 (quarterly).
- **Owner:** whichever iOS agent is dispatching Phase 2+ domain work when the audit falls due. Record results in git history.
