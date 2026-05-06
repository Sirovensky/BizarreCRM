# S30 — WebSocket Authentication, Authorization, Message Handling, Broadcast Scoping

---

### [HIGH] WS auth bypasses session revocation — revoked JWT authenticates new socket

**Where:** `packages/server/src/ws/server.ts:443–450`
Also compare: `packages/server/src/middleware/auth.ts:126–129` (HTTP middleware checks sessions table), `packages/server/src/routes/auth.routes.ts:1420` (logout deletes session)

**What:**
The HTTP `authMiddleware` verifies a JWT *and* queries `sessions WHERE id = ? AND expires_at > datetime('now')`, rejecting tokens whose session row was deleted (logout, forced-logout, admin-disable). The WS `auth` message handler at line 443 calls `verifyJwtWithRotation()` only — no session DB lookup. A revoked JWT (user logged out, password changed, account disabled) will still successfully authenticate a new WebSocket connection for up to 1 hour (the access-token TTL). Additionally, once a WS connection is established the token is never re-checked: an existing connection outlives both the JWT's expiry and any subsequent session deletion indefinitely.

**Code:**
```typescript
const payload = verifyJwtWithRotation(
  tokenCandidate,
  'access',
  JWT_VERIFY_OPTIONS,
) as { userId: number; tenantSlug?: string | null; role?: string };
ws.userId = payload.userId;
// No session lookup. HTTP middleware does:
//   SELECT id FROM sessions WHERE id = ? AND expires_at > datetime('now')
// WS never does this, so a deleted session passes here.
ws.tenantSlug = payload.tenantSlug || null;
```

**Exploit:**
Attacker steals a staff JWT (XSS, memory inspection, shared device). Victim clicks "Logout" — session row deleted. Attacker immediately opens a WS connection with the stolen token: the auth handler accepts it because it only verifies the signature, not the session. The attacker receives all tenant WS broadcasts (ticket updates, invoice events, SMS messages) for up to 60 minutes.

**Fix:**
Add an async DB lookup inside the WS `auth` handler that replicates the HTTP middleware session check. Require `asyncDb` access (pass it into `setupWebSocket` from `index.ts`). Additionally implement a 30-minute re-authentication sweep that terminates connections whose session row no longer exists or whose JWT `exp` has passed.

---

### [MEDIUM] Missing `payload.type` guard in WS auth allows future token-type confusion

**Where:** `packages/server/src/ws/server.ts:443–450` vs `packages/server/src/middleware/auth.ts:86–89`

**What:**
The HTTP `authMiddleware` checks `payload.type !== 'access'` and rejects the token with 401. The WS auth handler casts the verified payload to `{ userId; tenantSlug?; role? }` with no `type` field assertion — it does not verify `payload.type === 'access'`. Currently mitigated because access tokens are signed with `config.accessJwtSecret` (HKDF-derived) and refresh tokens with `config.refreshJwtSecret` (different HKDF derivation), so a refresh token will fail signature verification. However, in the transition period documented in `utils/jwtSecrets.ts` when `ACCESS_JWT_SECRET` is not set in env, both access and refresh tokens may fall back to the raw `JWT_SECRET`, allowing a refresh token to pass the WS signature check and authenticate a WS socket with a long-lived (30/90 day) credential that the HTTP layer would reject.

**Code:**
```typescript
// HTTP middleware — line 86:
if (payload.type !== 'access') {
  res.status(401).json(errorBody(ERROR_CODES.ERR_AUTH_INVALID_TOKEN_TYPE, ...));
  return;
}

// WS auth handler — line 447: no type check at all
) as { userId: number; tenantSlug?: string | null; role?: string };
ws.userId = payload.userId;
```

**Exploit:**
During the transition window (before `ACCESS_JWT_SECRET`/`REFRESH_JWT_SECRET` are set), an attacker who can read the refresh token from its `HttpOnly` cookie (e.g. via SSRF to `/api/v1/auth/refresh`, or OS-level cookie access on a shared kiosk) sends it as the WS `auth` token. The socket authenticates and stays alive for up to 90 days, bypassing the 1-hour access-token expiry.

**Fix:**
Add `if ((payload as any).type !== 'access') throw new Error('wrong token type')` immediately after `verifyJwtWithRotation` returns. Mirror the HTTP middleware logic exactly.

---

### [MEDIUM] POS `/sales` broadcast misses `tenantSlug` — events misdirected in multi-tenant

**Where:** `packages/server/src/routes/pos.routes.ts:1323`

**What:**
Every other route that calls `broadcast()` for tenant-scoped events passes `req.tenantSlug || null`. The `/pos/sales` handler at line 1323 calls `broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id, order_id })` with **no third argument**, so `tenantSlug` defaults to `null`. The `broadcast()` function routes to the `tenantBucketKey(null)` bucket which, in multi-tenant mode, contains only super-admin/management sockets — not the tenant's staff. The invoice-created event is silently dropped for all tenant clients. In single-tenant mode the null bucket contains all staff so the event is delivered, masking the bug in development. A separate `POST /pos/ticket` at line 2447 correctly passes `req.tenantSlug || null`.

**Code:**
```typescript
// pos.routes.ts:1323 — missing third argument
broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId });

// Every other caller correctly does:
broadcast(WS_EVENTS.INVOICE_CREATED, invoice, req.tenantSlug || null);
```

**Exploit:**
In a multi-tenant deployment, a POS cashier completes a sale via `/pos/sales`. No `invoice:created` WS event is delivered to the tenant's web clients, so the UI does not update in real-time. Super-admin management consoles erroneously receive the event (invoice ID, order ID) from a tenant they may not be authorized to view at the WS layer, constituting a cross-scope data exposure to management-dashboard observers.

**Fix:**
Change line 1323 to `broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId }, req.tenantSlug || null)`.

---

### [LOW] `management:stats` and `management:crash` broadcast to all staff in single-tenant mode

**Where:** `packages/server/src/index.ts:2380`, `packages/server/src/index.ts:3886`
Also: `packages/server/src/services/githubUpdater.ts:337`

**What:**
Three platform broadcasts — `management:stats` (process memory, uptime, request rates, active connection count every 5 s), `management:crash` (error message, partial stack trace, crashed route path), and `management:update_available` (current/latest commit SHA, commit message) — are sent with `tenantSlug = null` (the default). In single-tenant deployments all authenticated sockets live in the `null` bucket, so every logged-in staff member including the `staff` role receives these. No role gate is applied inside `broadcast()` for these event types. The `scrubSensitive()` function does not filter non-PII operational data. A staff user opening the browser dev-tools WS inspector sees server memory consumption, crash details (file paths, DB column/table names in error messages despite partial redaction), and internal commit SHAs.

**Code:**
```typescript
// index.ts:2380 — no tenantSlug, no role filter
broadcast('management:stats', {
  uptime: process.uptime(),
  memory: { rss, heapUsed, heapTotal },
  activeConnections: allClients.size,
  requestsPerSecond: getRequestsPerSecond(),
  requestsPerMinute: getRequestsPerMinute(),
});
// index.ts:3886
broadcast('management:crash', entry); // CrashEntry: route, errorMessage, errorStack
```

**Exploit:**
A staff user (e.g. a part-time cashier) connects to the WS and listens to raw frames. Every 5 seconds they receive heap/RSS memory data useful for timing memory-exhaustion attacks. On any server crash they receive `errorStack` containing DB query strings, internal file paths, and column names that help fingerprint the technology stack for targeted injection or path-traversal attempts.

**Fix:**
Add a role guard inside the broadcast loop for `management:*` events (check `ws.role === 'admin'` or a new `MANAGEMENT_ROLES` set), or switch these broadcasts to use a dedicated management socket bucket that only super-admin / local Electron connections land in. Alternatively, use `sendToUser` targeted to specific admin user IDs instead of a bucket broadcast.

---

### [LOW] WS connection persists indefinitely after JWT expiry — no revalidation or expiry timeout

**Where:** `packages/server/src/ws/server.ts:301–643`

**What:**
The JWT is validated exactly once at the `auth` message. After that, the connection lives as long as the TCP session and the heartbeat keep it alive (30-second ping/pong, no upper-bound). The `JWT_VERIFY_OPTIONS` include the `exp` claim (jsonwebtoken enforces expiry), but only at auth time. A WS socket authenticated at t=0 with a 1-hour access token remains registered in `clients` and `clientsByTenant` at t=2h, t=24h, etc., receiving all future broadcasts. This contradicts the 1-hour access-token design and the IDLE_SESSION_MAX_DAYS policy enforced by HTTP middleware.

**Code:**
```typescript
// One-time auth — no subsequent recheck
ws.userId = payload.userId;
ws.tenantSlug = payload.tenantSlug || null;
ws.role = ...;
// Socket stays in clientsByTenant forever after this.
// No scheduled re-check of exp or session validity.
```

**Exploit:**
An employee whose access token expires (after 1 h) should lose real-time access when their session also idles out. On HTTP they'd get 401 on the next API call. On WS, they continue receiving all tenant broadcasts — ticket updates, SMS messages, invoice events — until they manually close the browser or lose network. An attacker who briefly steals credentials, authenticates a WS connection, and loses the token still retains live broadcast access indefinitely.

**Fix:**
Schedule a periodic re-check (e.g. every 15 minutes) that re-verifies the JWT's `exp` and re-queries the sessions table for each active socket. On failure, close the socket with code 4401 (application-level auth expiry). Use `jwt.decode()` (no re-verify needed) to read the `exp` claim for cheap local expiry checks.

---

### [INFO] WS `auth` handler does not check `payload.type === 'access'` — missing defense-in-depth

*(Combined with the HIGH finding on session revocation — see MEDIUM finding above for full detail.)*

---

### [INFO] `authTimeout` closes on malformed message but auth-retry path allows rapid socket recycling

**Where:** `packages/server/src/ws/server.ts:405–415`

**What:**
When a malformed message is received before auth, `clearAuthTimeout()` is called and the socket is kept open (not closed). The 5-second auth timer has been cancelled so the socket can now idle indefinitely as an unauthenticated connection consuming a slot in the per-IP cap. A client that rapidly sends malformed messages just before the 5-second window expires gets their socket kept alive past the timeout window.

**Code:**
```typescript
const msg = parseInbound(raw);
if (!msg) {
  log.warn('ws malformed inbound message', { ... });
  clearAuthTimeout(); // Timer cleared but socket NOT closed
  return;             // Socket stays open, no longer on a death timer
}
```

**Exploit:**
An attacker connects 20 sockets (per-IP cap), sends a malformed message on each just before the 5s timer fires, cancelling the timers. The sockets now hold slots at the per-IP cap level indefinitely without being authenticated, starving legitimate clients from the same IP.

**Fix:**
On receiving any malformed pre-auth message, close the socket immediately (`ws.close(1008, 'invalid message')`) rather than just cancelling the auth timer. Or re-arm a shorter (1 s) timer after a malformed pre-auth message.

---
