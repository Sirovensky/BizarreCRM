# S36 — Holistic: End-to-End App, Middleware Order, Cross-Module Composition, Security Model Coherence

Auditor: S36 slot (holistic)
Scope: `packages/server/src/index.ts` (3924 lines) + all middleware, WS, cron, and cross-module composition

---

## Middleware Execution Order (confirmed good)

The verified order is:
1. TCP SNI multiplexer → HTTPS server
2. HTTP→HTTPS redirect (sanitized host/URL)
3. Request-ID generation
4. errorEnvelopeMiddleware (patch res.json before routes)
5. compression
6. helmet (CSP, HSTS, noSniff, referrer, frameguard)
7. Permissions-Policy
8. CORS (origin allowlist; credentials:true; no wildcard reflection)
9. Production origin guard (blocks Origin-less state-changing API calls)
10. cookieParser
11. **Global API rate limiter** (`/api/v1`, 300/min per IP, DB-backed)
12. Stripe webhook express.raw() mount (before JSON parser — correct)
13. Large-body carve-out for `/api/v1/catalog/bulk-import` (before global JSON parser)
14. express.json() (1 MB limit, rawBody captured)
15. express.urlencoded() (1 MB limit)
16. requestLogger
17. Cache-Control headers (PII paths → no-store; GET → no-cache)
18. req.db = global db (default)
19. **tenantResolver** (multi-tenant: resolves slug from Host, sets req.db, req.tenantSlug, req.tenantPlan)
20. **CSRF content-type guard** (blocks non-JSON/non-multipart POST/PUT/PATCH/DELETE)
21. crashGuardMiddleware
22. Route handlers (individual authMiddleware per mount)
23. SPA fallback
24. errorHandler

---

### [MEDIUM] tenantResolver DB-error path calls next() without tenant context — unauthenticated routes served with wrong DB

**Where:** `packages/server/src/middleware/tenantResolver.ts:453-456`

**What:**
When the master DB query to look up a tenant slug fails (e.g., DB locked, disk full), the resolver calls `next()` without setting `req.tenantSlug` or updating `req.db` beyond the global default DB already set at line 1271. Auth-gated routes are still protected (authMiddleware at line 100 of auth.ts rejects requests without `req.tenantSlug` in multi-tenant mode), but unauthenticated routes — `/api/v1/portal`, `/api/v1/track`, `/api/v1/tv`, `/portal/api/v2` — will proceed and query the wrong (global single-tenant) database, leaking that shop's data or silently returning empty results to the wrong tenant's subdomain.

**Code:**
```typescript
  try {
    tenant = masterDb.prepare(
      "SELECT id, slug, status, db_path, plan, max_tickets_month, max_users, storage_limit_mb, trial_started_at, trial_ends_at FROM tenants WHERE slug = ?"
    ).get(slug) as typeof tenant;
  } catch (err) {
    log.error('tenant_db_query_failed', { slug, err: err instanceof Error ? err.message : String(err) });
    next(); // Let the request through — better to serve static assets than crash
    return;
  }
```

**Exploit:**
If the master DB is briefly locked during a backup or WAL checkpoint, an attacker requests `GET https://evilslug.example.com/api/v1/track/ORD-123`. The resolver can't look up `evilslug`, calls `next()`, the tracking route queries the global `db`, and returns ticket-tracking data belonging to the single-tenant default shop. Cross-tenant data exposure for any public endpoint.

**Fix:**
Replace the `next()` call in the DB error branch with `res.status(503).json(...)`, refusing to serve the request rather than falling back to the wrong DB. Only non-API static asset paths (already handled before slug extraction) should fall through.

---

### [MEDIUM] Webhook rate limiter uses hardcoded global `db` — wrong store in multi-tenant mode

**Where:** `packages/server/src/index.ts:1538-1551`

**What:**
`webhookRateLimit()` always calls `consumeWindowRate(db, ...)` where `db` is the module-level single-tenant DB handle. In multi-tenant mode, rate limit state for all tenants' webhooks is stored in this global DB (which belongs to the single-tenant installation and is separate from the master DB or any tenant DB). This means: (a) rate limit records from SMS/voice webhooks cross-pollinate across the entire fleet against an unrelated data store; (b) if the operator has removed the single-tenant DB or it is otherwise unavailable in a pure multi-tenant deployment, `consumeWindowRate` throws and the webhook returns 500; (c) an attacker can exhaust the 60 req/min global budget for one IP across ALL tenants by flooding any one tenant's webhook URL.

**Code:**
```typescript
function webhookRateLimit(req: any, res: any, next: any) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const result = consumeWindowRate(db, 'webhook', ip, WEBHOOK_RATE_LIMIT, WEBHOOK_RATE_WINDOW);
  // db is the module-level single-tenant db, not req.db or getMasterDb()
  ...
}
```

**Exploit:**
In multi-tenant SaaS mode, an attacker floods `POST /api/v1/t/shop-a/sms/inbound-webhook` at 60 req/min from a single IP. This fills the global rate limit bucket; all other tenants' webhooks from that IP are rejected for the 60-second window — including a shop that received a legitimate payment confirmation SMS.

**Fix:**
Use `getMasterDb()` (the correct multi-tenant shared store) in multi-tenant mode, falling back to `db` in single-tenant mode. Or use `req.db` after `tenantResolver` has run (webhook tenant resolver sets it). Add `if (config.multiTenant) { const rdb = getMasterDb() ?? db; ... } else { ... }`.

---

### [MEDIUM] Global API rate limiter runs BEFORE tenantResolver — all tenants share bucket in global DB

**Where:** `packages/server/src/index.ts:1181-1208` (rate limiter) vs `1276` (tenantResolver)

**What:**
The `/api/v1` rate limiter at line 1181 fires before `tenantResolver` at line 1276. At rate-limit time, `req.db` is the global single-tenant DB (set at line 1272). The comment acknowledges this: "Use req.db when available (tenant context), fall back to the module-level db for unauthenticated requests". But in practice, tenantResolver hasn't run yet, so `(req.db as Database.Database | undefined) ?? db` always evaluates to `db` — the global DB — for every request. In multi-tenant mode the rate limit table is effectively in the wrong store and all tenant traffic competes in the same bucket keyed only by IP.

**Code:**
```typescript
app.use('/api/v1', (req, res, next) => {   // line 1181
  ...
  const limitDb: Database.Database = (req.db as Database.Database | undefined) ?? db;
  const result = consumeWindowRate(limitDb, 'api_v1', ip, API_RATE_LIMIT, API_RATE_WINDOW);
  ...
});
// ...
app.use(tenantResolver); // line 1276 — runs AFTER rate limiter
```

**Exploit:**
A tenant at `shop-a.example.com` makes 300 API calls/minute. This fills the rate bucket in the global DB (not shop-a's own DB). Now a request from the same IP to `shop-b.example.com` is immediately rate-limited even though shop-b's own DB is empty. Effective denial-of-service across tenants from a single IP.

**Fix:**
Move the global rate limiter AFTER tenantResolver (line 1276), so `req.db` is properly set to the tenant DB. Alternatively, always use `getMasterDb()` for the shared rate limit store in multi-tenant mode.

---

### [MEDIUM] Double-mount of importRoutes at unauthenticated prefix exposes all import routes without authMiddleware

**Where:** `packages/server/src/index.ts:1657-1658`

**What:**
`importRoutes` is mounted twice: once at `/api/v1/import/oauth` without `authMiddleware` (for the OAuth callback URL), and once at `/api/v1/import` with `authMiddleware`. Express matches the first applicable mount, so any request to `/api/v1/import/oauth/<anything>` bypasses authMiddleware entirely. The router's internal `requireAdmin(req)` helper checks `req.user?.role !== 'admin'`, but `req.user` is only set by `authMiddleware` — which didn't run. Without `req.user`, the check always fails and throws AppError 403, which protects the oauth endpoints. However, any future route added to `importRoutes` at a path starting with `/oauth/` would be reachable without the proper authMiddleware, and developers may not realize the route is exposed unauthenticated.

**Code:**
```typescript
// OAuth callback must be public (RD redirects browser here before CRM login)
app.use('/api/v1/import/oauth', importRoutes);   // NO authMiddleware — all importRoutes accessible here
app.use('/api/v1/import', authMiddleware, importRoutes);
```

**Exploit:**
The current oath-specific routes are protected by manual `requireAdmin(req)` checks. However, a developer adding a new route like `router.get('/oauth/status', ...)` that forgets `requireAdmin()` would be publicly accessible at `/api/v1/import/oauth/status` with zero authentication.

**Fix:**
Create a dedicated mini-router containing only the OAuth callback route and mount it at `/api/v1/import/oauth`. Mount the main `importRoutes` only once, behind `authMiddleware`. The OAuth callback itself should continue using `requireAdmin()` and also verify session via authMiddleware before `requireAdmin()` is meaningful.

---

### [MEDIUM] CSRF content-type bypass via path substring match for `/setup`

**Where:** `packages/server/src/index.ts:1283-1299`

**What:**
The CSRF content-type guard exempts any request path containing the substring `/setup` from the content-type requirement. This is checked with `req.path.includes('/setup')`, which matches any path with those characters anywhere — including `/api/v1/settings/complete-setup`, `/api/v1/auth/login/2fa-setup`, and any future route that happens to contain "setup". This overly broad exemption means an attacker can send an `application/x-www-form-urlencoded` body to those routes (which bypass CSRF protection), since the body parser at line 1233 already parses urlencoded bodies and populates `req.body`. The CSRF guard is then bypassed.

**Code:**
```typescript
app.use((req, res, next) => {
  if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
    const ct = req.headers['content-type'] || '';
    if (ct.includes('application/json') || ct.includes('multipart/form-data') ||
        req.path.includes('webhook') || req.path.includes('/setup')) {  // ← overly broad
      return next();
    }
```

**Exploit:**
An attacker hosts a malicious page that submits a `<form action="https://shop.example.com/api/v1/settings/complete-setup" method="POST">` with `Content-Type: application/x-www-form-urlencoded`. The CSRF guard is bypassed because the path includes `/setup`. The authMiddleware still requires a valid JWT, so the actual exploitability requires a logged-in admin victim — but that's the standard CSRF scenario.

**Fix:**
Use exact path matches instead of `includes()`. The only legitimately unauthenticated setup paths are `/api/v1/auth/setup` and `/api/v1/management/setup`. Enumerate them explicitly: `['/api/v1/auth/setup', '/api/v1/management/setup'].includes(req.path)`.

---

### [MEDIUM] POS Invoice broadcast missing tenant context — data leaks to platform-level WS bucket

**Where:** `packages/server/src/routes/pos.routes.ts:1323`

**What:**
`broadcast(WS_EVENTS.INVOICE_CREATED, ...)` is called without the third `tenantSlug` argument, defaulting to `null`. In the WS server, `null` maps to the `'null'` bucket which holds super-admin and management (non-tenant) sockets. So this broadcast delivers a POS `invoice_created` event (containing `invoice_id` and `order_id`) to every connected super-admin WebSocket rather than to the originating tenant's sockets. The data in the payload is minimal (IDs only) but the cross-boundary delivery is a design violation and could be exploited to correlate tenant activity from the super-admin WS stream.

**Code:**
```typescript
// pos.routes.ts:1323
broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId });
// Missing third argument: should be req.tenantSlug || null
// Default tenantSlug=null routes to super-admin/management bucket
```

**Exploit:**
A platform operator monitoring the management WebSocket stream receives live `invoice_created` events from all tenants' POS transactions. Even if payload contains only IDs, the volume and timing of events reveals tenant activity levels and, with correlation, can identify busy tenants.

**Fix:**
Pass `req.tenantSlug || null` as the third argument: `broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId }, req.tenantSlug || null)`.

---

### [LOW] Membership renewal cron charges cards without writing an audit log entry

**Where:** `packages/server/src/index.ts:2248-2326` (membershipTenantWork function)

**What:**
The hourly membership renewal cron calls `chargeToken()` against BlockChyp and updates `customer_subscriptions` and `subscription_payments`, but never writes a row to the tenant's `audit_logs` table. Financial operations — especially recurring card charges — must be auditable. A support dispute, a data breach investigation, or a compliance audit cannot reconstruct which charge was made by the server cron vs. a human POS operator without an audit trail. All other money operations in the route handlers call `audit(...)`.

**Code:**
```typescript
if (result.success) {
  tenantDb.prepare(`UPDATE customer_subscriptions SET ... WHERE id = ?`).run(...);
  tenantDb.prepare('INSERT INTO subscription_payments (...) VALUES (...)').run(...);
  console.log(`[Membership] Renewed ${sub.first_name}'s ${sub.tier_name} membership`);
  // ← no audit() call; no audit_logs row written
}
```

**Exploit:**
An operator disputes a customer's claim "my card was charged without my consent". Without an audit log entry, there is no server-side record of the automated charge distinct from human-initiated POS charges — the only evidence is `subscription_payments`, which does not capture IP, user identity, or system context.

**Fix:**
Add `audit(tenantDb, { action: 'membership_renewal_charged', entity: 'customer_subscription', entityId: sub.id, userId: null, metadata: { amount: sub.monthly_price, transactionId: result.transactionId, tierId: sub.tier_id } })` after a successful charge, and a similar entry for failures.

---

### [LOW] WS `broadcast()` management:stats sent to `null` tenant bucket — leaks server metrics to platform channel

**Where:** `packages/server/src/index.ts:2375-2392`

**What:**
The 5-second management stats broadcast uses `broadcast('management:stats', ...)` with no tenant argument (defaults to null). This correctly targets the `null` bucket (super-admin/management sockets). However, any unauthenticated WebSocket that connected before `auth` message handling was processed but arrived after the 5-second timer could receive these stats. The WS auth-timeout is 5 seconds (line 341 in ws/server.ts), meaning a race exists where an unauthenticated socket in `allClients` that hasn't sent `auth` yet will be in `allClients` but NOT in `clientsByTenant` (it's added to the bucket only after auth succeeds at line 510). The `broadcast()` implementation iterates `clientsByTenant.get(tenantBucketKey(null))`, not `allClients`, so unauthenticated sockets are NOT in the null bucket — this is correct. **No actual issue with this specific broadcast.** (INFO-level observation.)

**Code:**
```typescript
broadcast('management:stats', {
  uptime: process.uptime(),
  memory: { rss, heapUsed, heapTotal },
  activeConnections: allClients.size,
  requestsPerSecond: getRequestsPerSecond(),
  requestsPerMinute: getRequestsPerMinute(),
});
// null bucket → only authenticated management sockets receive this. Safe.
```

**Exploit:**
No exploit. The bucket isolation is correct. Noted for completeness.

**Fix:**
No action required. The current design is correct — only authenticated sockets are in the tenant bucket and receive broadcasts.

---

### [LOW] OAuth state bound to `req.user.id` but evaluated via route mounted without authMiddleware

**Where:** `packages/server/src/routes/import.routes.ts:1456, 1484` + `packages/server/src/index.ts:1657`

**What:**
The `/oauth/authorize-url` route calls `requireAdmin(req)` which throws 403 if `req.user` is absent. After the check, it writes `addOAuthState(state, { user_id: req.user!.id, ... })`. The `req.user!.id` is a non-null assertion that will throw a runtime TypeError if `requireAdmin()` somehow fails to throw (e.g., future refactor). The `/oauth/callback` route similarly calls `requireAdmin(req)` then uses `req.user!.id` for state validation. While the current `requireAdmin` implementation always throws on no-auth, the `!` assertion creates a fragile dependency: if `requireAdmin` is ever changed to return false instead of throw, the assertion becomes a crash.

**Code:**
```typescript
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ...);
  }
}
// ...
addOAuthState(state, { user_id: req.user!.id, ... }); // non-null assertion after manual check
```

**Exploit:**
Not directly exploitable in the current code, but the pattern is brittle. If `requireAdmin` is refactored to set a response header and call `res.sendStatus(403)` instead of throwing (a common Express pattern), code execution continues past the guard and `req.user!.id` throws `TypeError: Cannot read property 'id' of undefined`, crashing the process.

**Fix:**
After the `requireAdmin(req)` call, add an explicit null check: `if (!req.user) throw new AppError(...)`. Replace `req.user!.id` with `req.user.id` after the explicit check. Better: move auth entirely to the authMiddleware layer instead of inline manual checks.

---

### [LOW] Cron-fired `forEachDb` acquires tenant DB handles but if callback throws synchronously, handle leaks

**Where:** `packages/server/src/index.ts:198-222` (`forEachDb`)

**What:**
`forEachDb` acquires a pooled tenant DB handle via `await getTenantDb(t.slug)` and passes it to a synchronous callback. If the callback throws synchronously (e.g., a malformed SQL query passed as callback), the `finally { if (pooled !== undefined) releaseTenantDb(t.slug); }` still fires correctly because it's in the same try-finally block. However, `forEachDb` is declared `async function forEachDb(callback: ...)` but the callback type is `(slug, tenantDb) => void` — not `Promise<void>`. If a callback happens to return a Promise (e.g., caller accidentally passes an async function), `forEachDb` will release the DB handle immediately while the callback is still executing asynchronously, creating a use-after-release scenario on the connection.

**Code:**
```typescript
async function forEachDb(callback: (slug: string | null, tenantDb: any) => void): Promise<void> {
  ...
  pooled = await getTenantDb(t.slug);
  callback(t.slug, pooled);  // if callback returns Promise, we don't await it
  ...
  finally {
    if (pooled !== undefined) releaseTenantDb(t.slug);  // released immediately
  }
```

**Exploit:**
A developer refactors a cron to `async` and passes it to `forEachDb` instead of `forEachDbAsync`. The handle is released while the async callback is mid-query, causing `database is closed` errors or returning stale data from the pool. No external attacker can trigger this — it's a developer footgun.

**Fix:**
Change `forEachDb` callback type to `(slug: string | null, tenantDb: any) => void | Promise<void>` and add `await` before the callback call (or rename the function to make the async-only contract explicit and add a TypeScript error for Promise-returning callbacks).

---

## Cross-cutting observations (from holistic read)

**Master JWT vs tenant JWT separation — CONFIRMED CORRECT.** Super-admin routes use `config.superAdminSecret` with `audience: 'bizarre-crm-super-admin'`; tenant routes use `config.jwtSecret` with `audience: 'bizarre-crm-api'`. The management auth middleware explicitly rejects if `config.superAdminSecret` is absent (line 250-252) and verifies `is_active = 1` on the super_admins row. Cross-audience confusion is blocked by `algorithms: ['HS256'], issuer, audience` in both verify calls.

**localhostOnly implementation — CORRECT.** Both the shared `localhostOnly` middleware and the inline copy in `management.routes.ts` use `req.socket.remoteAddress` (not `req.ip`) and a Set of exact loopback strings, preventing X-Forwarded-For spoofing.

**tenantResolver error propagation — CONFIRMED.** On successful resolution, `req.tenantSlug` and `req.db` are always set together. The only divergence is the DB-error fallback noted above. Auth middleware at line 100-103 of auth.ts blocks the fallback path for authenticated routes.

**WS tenant context post-handshake — CONFIRMED STABLE.** The tenant slug is captured from the JWT payload at auth time and stored on `ws.tenantSlug`. It is never updated post-auth. Broadcasts use `ws.tenantSlug` for routing. No drift.

**Impersonation flow — NO DEDICATED AUDIT LOG.** The super-admin `POST /super-admin/api/tenants/:slug/impersonate` route (if it exists) was not found in the searched files — impersonation appears not to be implemented; if added later, it must write to `master_audit_log`.

**Error handler swallowing — CONFIRMED SAFE.** `errorHandler` does not silently drop errors; all unhandled errors surface as 500 with structured logging. `res.headersSent` guard prevents double-send crashes.

**Async error propagation — CONFIRMED.** Routes using `asyncHandler` wrapper propagate async errors to `next(err)` and the central `errorHandler`. The auth middleware's `.catch(() => { res.status(401) })` pattern means DB errors during auth return 401, which is acceptable (no sensitive DB error detail leaked to client).

**Rate limit bypass via alias mount — NOT FOUND.** The global rate limiter at `/api/v1` catches all API traffic. Routes mounted at `/portal/api/v2`, `/public/api/v1`, and `/super-admin/api` are excluded from the global bucket, but these are either public-by-design (portal) or localhost-only (super-admin).

**Content-type confusion (JSON + form) — PARTIAL RISK.** `express.urlencoded()` is registered globally but the CSRF guard blocks urlencoded state-changing requests — except for paths containing `/setup` or `webhook` substrings (see MEDIUM finding above).
