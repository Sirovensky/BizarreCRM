# S28 — Rate Limiting Completeness Audit

**Slot:** 28  
**Auditor:** security-audit agent  
**Date:** 2026-05-05  
**Scope:** Rate limiting coverage across all sensitive endpoints

---

## Summary

Rate limiting is broadly implemented via a well-designed SQLite-backed `rateLimiter.ts` utility with both window-based and lockout-based modes. Trust-proxy is correctly configured (explicit IP allowlist, not `1`). Auth endpoints (login, 2FA, forgot/reset-password, change-password) all have dedicated per-IP and per-account limits. Public-facing endpoints (booking, portal, payment links, estimate sign) are individually rate-limited.

However, six concrete gaps were found:

---

### [MEDIUM] POST /auth/refresh has no rate limit — JWT flood/DoS

**Where:** `packages/server/src/routes/auth.routes.ts:1210`  
Also: `packages/server/src/index.ts:1183` (global limiter exclusion)

**What:**
`POST /api/v1/auth/refresh` is mounted under `/api/v1/auth` which is explicitly excluded from the global 300 req/min IP limiter (`req.path.startsWith('/auth')` short-circuits at index.ts:1183). The handler has zero dedicated rate limiting. Every call runs `verifyJwtWithRotation` (HMAC-SHA256) plus two async DB queries (session lookup, user lookup). An attacker can flood this endpoint with arbitrary tokens causing sustained CPU and SQLite I/O load.

**Code:**
```typescript
// index.ts:1181-1184 — entire /auth prefix is excluded
app.use('/api/v1', (req, res, next) => {
  if (req.path.startsWith('/auth') || ...) {
    return next();   // <-- /auth/refresh gets no global limit
  }
  const result = consumeWindowRate(limitDb, 'api_v1', ip, 300, 60_000);

// auth.routes.ts:1210 — handler starts with no rate check
router.post('/refresh', asyncHandler(async (req: Request, res: Response) => {
  // No checkWindowRate / consumeWindowRate call anywhere in this handler
  const payload = verifyJwtWithRotation(refreshToken, 'refresh', JWT_VERIFY_OPTIONS);
```

**Exploit:**
An attacker sends thousands of `POST /api/v1/auth/refresh` requests per second with random JWT-format bodies. Each triggers an HMAC-SHA256 verify attempt and a DB read. The global limiter does not fire (auth paths are excluded). The server becomes unavailable to legitimate users.

**Fix:**
Add `consumeWindowRate(db, 'refresh', ip, 60, 60_000)` at the start of the `/refresh` handler, returning 429 when exceeded. A per-IP ceiling of 60/min is generous enough for any real browser/mobile refresh cycle.

---

### [MEDIUM] POST /auth/switch-user — IP-only PIN rate limit, no per-user limit (distributed brute-force)

**Where:** `packages/server/src/routes/auth.routes.ts:1438-1445`  
Also: `auth.routes.ts:241-252` (PIN_RATE_LIMIT definition)

**What:**
The `/switch-user` endpoint enforces only a per-IP PIN rate limit (5 attempts / 15 min). There is no per-target-user rate limit. An attacker controlling multiple IPs (botnet, proxy rotation) can each contribute 5 attempts per 15-minute window, cumulatively brute-forcing a 4-digit (10,000 possibilities) or 6-digit (1,000,000) PIN with 2,000–200,000 IPs at 33 attempts/IP/hour. Contrast: the password login path has an additional per-account limit (10 attempts / 30 min keyed by tenantSlug:username).

**Code:**
```typescript
// auth.routes.ts:1438-1447 — only IP check, no per-user check
router.post('/switch-user', authMiddleware, asyncHandler(async (req, res) => {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkPinRateLimit(db, ip)) {   // keyed by IP only
    res.status(429).json({ ... });
    return;
  }
  // No per-user PIN attempt counter exists
  const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));
```

**Exploit:**
Attacker uses 100 residential proxies, each sending 5 wrong PINs per 15-min window = 100 attempts every 15 minutes = 400/hr continuously. A 4-digit PIN is enumerated within 25 hours on average. Technique is undetected because no single IP exceeds the limit.

**Fix:**
After a successful PIN match (user found but wrong TOTP, or on failure to match), record a per-user failure keyed by user.id in the `pin_user` category with the same 5/15-min window as the IP limit. Check this before running `bcrypt.compareSync` on the full user list.

---

### [MEDIUM] POST /catalog/live-search — shared in-memory global rate limit; single user can starve all others

**Where:** `packages/server/src/routes/catalog.routes.ts:697-712`  
Also: `packages/server/src/services/catalogScraper.ts:862-878`

**What:**
`POST /catalog/live-search` is protected only by an in-memory per-source global counter (30 req/min across ALL users). There is no per-user or per-tenant rate limit. A single authenticated technician or compromised account can exhaust all 30 slots in the shared bucket, making live catalog search unavailable for the entire shop. The in-memory counter resets on server restart, so it is also ineffective under orchestrated restart-then-flood attacks.

**Code:**
```typescript
// catalog.routes.ts:697 — no per-user check before calling liveSearchSupplier
router.post('/live-search', asyncHandler(async (req, res) => {
  const products = await liveSearchSupplier(db, source, q.trim());
  // catalogScraper.ts:865-877 — global in-memory counter only
  const liveSearchCounts = new Map<string, { count: number; resetAt: number }>();
  function rateLimitLiveSearch(source: CatalogSource): void {
    // One shared bucket per source — all users share this 30/min ceiling
    if (bucket.count >= LIVE_SEARCH_MAX) throw ...;
  }
```

**Exploit:**
An authenticated user (any role) scripts 30 rapid `POST /catalog/live-search` requests per minute. The global counter for that source reaches 30, and all other users in the shop receive 429 errors from `liveSearchSupplier` for the remainder of the window. Additionally, a server restart clears the counter, allowing immediate re-flood.

**Fix:**
Add `consumeWindowRate(req.db, 'catalog_live_search', String(req.user!.id), 10, 60_000)` at the start of the handler (per-user, 10/min). Retain the global service-level `rateLimitLiveSearch` counter as a secondary backstop.

---

### [LOW] checkWindowRate + recordWindowFailure split pattern creates TOCTOU race at auth limit boundary

**Where:** `packages/server/src/routes/auth.routes.ts:707,756` (login IP), `auth.routes.ts:1651,1681,1703` (forgot-password), `auth.routes.ts:1443,1481` (switch-user)  
Also: `packages/server/src/utils/rateLimiter.ts:53-58` (deprecated annotation)

**What:**
Fourteen route handlers use the deprecated `checkWindowRate` → async work → `recordWindowFailure` split pattern. Each function uses its own SQLite transaction, but there is an async gap between them (the handler awaits DB queries between check and record). At the limit boundary (e.g., count = maxAttempts-1), two concurrent requests can both pass `checkWindowRate` before either calls `recordWindowFailure`, allowing up to maxAttempts+1 attempts in a coordinated burst. The `consumeWindowRate` helper (used by newer routes) is atomic and does not have this race.

**Code:**
```typescript
// auth.routes.ts:707 — check (sync, count < 5 passes)
if (!checkLoginRateLimit(db, ip)) { return 429; }

// auth.routes.ts:733 — ASYNC GAP: second concurrent request's check runs here
const user = await adb.get('SELECT ... FROM users WHERE ...');

// auth.routes.ts:756 — record only on failure (sync)
recordLoginFailure(db, ip);  // now count = 1; second concurrent req still at 0
```

**Exploit:**
Attacker sends two concurrent POST /login requests from the same IP when the counter is at maxAttempts-1. Both pass the check. Each completes its async work (bcrypt + DB query). Each calls recordWindowFailure. Net result: counter advances by 2 but both requests were allowed through. At a 5-attempt limit, an attacker can effectively get 6 attempts per window. Practical impact is limited to +1 extra attempt per burst, not a bypass.

**Fix:**
Migrate all callers of `checkWindowRate`+`recordWindowFailure` to the atomic `consumeWindowRate`. The rateLimiter source already flags these as `@deprecated` (line 53). Priority callers: login IP (line 707/756), forgot-password (line 1651/1681), switch-user PIN (line 1443/1481).

---

### [LOW] POST /blockchyp/test-connection — admin-gated but no rate limit on real terminal network call

**Where:** `packages/server/src/routes/blockchyp.routes.ts:45-62`

**What:**
The `POST /blockchyp/test-connection` endpoint is gated to admin role but has no rate limit. Each call invokes `testConnection(db, terminalName)` which makes a real TLS network call to the BlockChyp payment terminal on the LAN or cloud. An admin account (or a session with a stolen admin JWT) can spam this endpoint, causing the terminal to be repeatedly pinged, potentially disrupting in-progress payment transactions by monopolising the terminal's connection queue.

**Code:**
```typescript
// blockchyp.routes.ts:45-62 — no rate limit check
router.post('/test-connection', asyncHandler(async (req, res) => {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  // No consumeWindowRate / checkWindowRate call
  refreshClient();
  const result = await testConnection(db, terminalName); // real network call
  res.json({ success: result.success, data: result });
}));
```

**Exploit:**
A compromised admin account (or stolen admin JWT) repeatedly hits `POST /api/v1/blockchyp/test-connection` in a tight loop. The BlockChyp terminal receives hundreds of ping/test requests, potentially timing out in-flight payment captures on other routes.

**Fix:**
Add `consumeWindowRate(req.db, 'blockchyp_test', String(req.user!.id), 3, 60_000)` — 3 test attempts per minute per admin is sufficient for a legitimate "does this config work?" workflow.

---

### [INFO] geocode.routes.ts has no rate limit and is not mounted in index.ts

**Where:** `packages/server/src/routes/geocode.routes.ts:17-68`  
Also: `packages/server/src/index.ts` (no import or `app.use` for geocode)

**What:**
`geocode.routes.ts` exports a `GET /` route that proxies requests to Nominatim (OpenStreetMap's public geocoding API, no API key) with no per-user or per-IP rate limit. The route is never imported or mounted in `index.ts`, so it is currently dead code. If mounted in the future, unauthenticated callers (it uses `authMiddleware` on the route file? — actually no, the router itself has no auth middleware and is never mounted with one) could freely drive Nominatim requests, risking the server's IP being rate-limited or banned by Nominatim's 1 req/s policy.

**Code:**
```typescript
// geocode.routes.ts:17 — no auth, no rate limit
router.get('/', asyncHandler(async (req, res) => {
  const address = typeof req.query.address === 'string' ? req.query.address.trim() : '';
  // direct Nominatim call — no consumeWindowRate, no checkWindowRate
  const response = await fetch(url.toString(), { ... });
```

**Fix:**
Either remove the file or, before mounting, add `authMiddleware` and `consumeWindowRate(req.db, 'geocode', req.ip ?? 'unknown', 10, 60_000)` — 10 geocodes/min per IP is generous for an address-blur use case.

---

## Checklist Results

| Endpoint | Rate Limit | Notes |
|---|---|---|
| `POST /auth/login` | IP (5/15min) + per-account (10/30min) + captcha after 5 | PASS |
| `POST /auth/forgot-password` | IP (3/hr) + captcha after threshold | PASS |
| `POST /auth/reset-password` | IP (10/hr) | PASS |
| `POST /auth/login/2fa-verify` | IP (5/15min) + per-user lockout (5/15min) | PASS |
| `POST /auth/login/2fa-backup` | IP (5/15min) + per-user lockout (5/15min) | PASS |
| `POST /auth/account/2fa/disable` | per-user TOTP lockout | PASS |
| `POST /auth/recover-with-backup-code` | IP login limit (5/15min) | PASS |
| `POST /auth/refresh` | **NONE** | **FAIL — MEDIUM** |
| `POST /auth/switch-user` | IP only (5/15min) — no per-user | **PARTIAL — MEDIUM** |
| `POST /signup` | IP (3/hr) + per-email (3/hr) | PASS |
| `POST /sms/send` | per-user (5/min) + tenant daily cap (500/day) + per-destination (3/hr) | PASS |
| `POST /voice/call` | per-user (10/min) | PASS |
| `POST /public/api/v1/booking` (GET config/avail) | IP (60/hr, 120/hr) | PASS |
| `POST /portal/quick-track` | IP (10/15min) + per-order (5/hr) + per-phone4 (5/hr) | PASS |
| `POST /portal/register/send-code` | IP (1/5s) + per-phone (3/hr) + daily cap (10/day) | PASS |
| `POST /portal/login` | IP+hash(last4) (5/10min) | PASS |
| `POST /api/v1/public/payment-links/:token/pay` | IP (6/min) | PASS |
| `GET /api/v1/public/payment-links/:token` | IP (30/min) | PASS |
| `POST /catalog/sync` | per-user admin (3/hr) | PASS |
| `POST /catalog/live-search` | global in-memory (30/min all users) — no per-user | **FAIL — MEDIUM** |
| `POST /public/api/v1/estimate-sign` | IP (60/hr) | PASS |
| Geocode | No rate limit + NOT MOUNTED | **INFO** |
| `POST /blockchyp/test-connection` | admin-gated, no rate limit | **FAIL — LOW** |

---

## Trust Proxy / req.ip Verification

`app.set('trust proxy', TRUST_PROXY_ALLOWLIST)` at `index.ts:634` uses an explicit IP allowlist (`config.trustedProxyIps` + loopback), not the blanket `1`. This means `req.ip` only reflects the `X-Forwarded-For` header when the connection arrives from a trusted proxy IP. Direct connections from untrusted IPs use `req.socket.remoteAddress`, which cannot be spoofed. **No bypass via X-Forwarded-For is possible against the current configuration.**

## In-Memory vs Persistent Limiters

All auth-path limiters (`login_ip`, `login_user`, `totp`, `pin`, `forgot_password`, `reset_password`, `signup`) use the SQLite-backed `checkWindowRate`/`consumeWindowRate` and survive server restarts. The `catalog/live-search` limiter (`liveSearchCounts` in `catalogScraper.ts:864`) is in-memory and resets on restart — noted above as MEDIUM.

## Multi-Process Note

`rateLimiter.ts` explicitly states SQLite-backed limits work correctly in multi-process deployments (index.ts:1175-1177 comment). The in-memory `liveSearchCounts` map does NOT survive across processes or restarts — a second worker process would have its own 30/min ceiling.
