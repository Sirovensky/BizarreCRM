# T08 — HTTP Request Smuggling / Proxy / Body Parser / Cluster

**Scope:** `packages/server/src/index.ts`, `packages/server/src/middleware/*`, all webhook endpoints (Stripe, Twilio, Telnyx, Vonage, Plivo, Bandwidth, Voice), `ecosystem.config.js`, `packages/server/package.json`.

**Methodology:** Full read of `index.ts` end-to-end (3,900+ lines in segments), every SMS/voice provider in `providers/sms/*.ts`, `routes/billing.routes.ts`, `routes/voice.routes.ts`, `routes/sms.routes.ts`, `middleware/localhostOnly.ts`, `middleware/tenantResolver.ts`, `config.ts`, `ecosystem.config.js`, `package.json`, `package-lock.json`, `node_modules/body-parser/lib/read.js` (decompression limit path), and cross-checked all Express body parser registrations against route order.

---

### HIGH — Unauthenticated 10 MB body buffering on `/api/v1/catalog/bulk-import`

**Where:** `packages/server/src/index.ts:1222–1225` (body parser carve-out) and `packages/server/src/index.ts:1181–1208` (rate limiter) and `packages/server/src/routes/catalog.routes.ts:419` (adminOnly gate)

**What:**
The per-route `express.json({ limit: '10mb' })` parser for `POST /api/v1/catalog/bulk-import` is registered at line 1222, which is BEFORE the global `express.json({ limit: '1mb' })` at line 1228 and — critically — BEFORE the `authMiddleware` that is only applied when the catalog router is mounted at line 1661 (`app.use('/api/v1/catalog', authMiddleware, catalogRoutes)`). Any HTTP request to this path hits the 10 MB body parser immediately, regardless of authentication. The API rate limiter runs before the body parser (as designed), but the rate limit is 300 req/min globally per IP — at 300 × 10 MB = 3 GB per minute that must be buffered in Node process memory before the 401 or 403 response is emitted. No per-IP body-size accounting exists.

**Code:**
```typescript
// index.ts:1222 — body parser registered with no auth, no smaller limit guard
app.post(
  '/api/v1/catalog/bulk-import',
  express.json({ limit: '10mb' }),
);

// index.ts:1661 — authMiddleware only attached here, after the body parser above
app.use('/api/v1/catalog', authMiddleware, catalogRoutes);

// catalog.routes.ts:419 — adminOnly check only fires inside the route handler
router.post('/bulk-import', adminOnly, asyncHandler(async (req, res) => { ... }));
```

**Exploit:**
An unauthenticated attacker sends 300 POST requests per minute with 10 MB bodies (content-type: `application/json`) to `/api/v1/catalog/bulk-import`. Each request is buffered into heap before auth is checked. 300 × 10 MB = 3 GB heap pressure per minute from a single IP; with multiple IPs or proxies the rate limit is per-IP so the aggregate is unbounded. Node OOM-kills or swap-storms the server.

**Fix:**
Add `authMiddleware` (and `adminOnly` if desired at the per-route level) directly into the route carve-out stack before the body parser: `app.post('/api/v1/catalog/bulk-import', authMiddleware, express.json({ limit: '10mb' }))`. This ensures unauthenticated requests never reach the parser. Alternatively, place a shared body-size guard that rejects Content-Length > 1 MB for non-admin tokens before the per-route 10 MB parser fires.

---

### MEDIUM — Twilio webhook HMAC-SHA1 with no upgrade path to Ed25519 / v2 signing

**Where:** `packages/server/src/providers/sms/twilio.ts:101`

**What:**
The Twilio webhook signature verification implementation uses `crypto.createHmac('sha1', this.authToken)`. Twilio deprecated their v1 HMAC-SHA1 scheme and introduced Webhook Signing V2 (Ed25519) in 2021. HMAC-SHA1 is cryptographically weak (SHA-1 is broken for collision resistance) and uses the same `authToken` credential that also authenticates outbound API calls — a compromised authToken value defeats both. There is no configuration option to use the newer `X-Twilio-Signature` Ed25519 path, and no code comment acknowledging the deprecation or future migration plan.

**Code:**
```typescript
// twilio.ts:88–111
verifyWebhookSignature(req: any): boolean {
  const signature = req.headers['x-twilio-signature'];
  if (!signature) return false;
  const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
  const params = req.body || {};
  // ... sort and concat params ...
  const expected = crypto.createHmac('sha1', this.authToken) // ← SHA-1
    .update(data)
    .digest('base64');
  // ...
}
```

**Exploit:**
An attacker who has performed a SHA-1 length-extension attack (feasible with multi-block payloads) or has access to previously valid `X-Twilio-Signature` values from logged/intercepted traffic can potentially forge a signature accepted by this verifier. More practically: authToken leakage (e.g. via DB dump, logs) compromises both outbound API calls and allows forging inbound webhooks — injecting fake SMS/call events, triggering MMS downloads to arbitrary URLs, and poisoning conversation history for all tenants sharing this provider.

**Fix:**
Upgrade to Twilio's v2 webhook signing (Ed25519, `X-Twilio-Signature-Algorithm: SHA256-ECDSA`) and verify via `req.headers['x-twilio-signature-v2']`. Twilio SDK's `validateRequestWithBody` / `validateRequest` methods handle this automatically. If staying on HMAC-SHA1, ensure authToken is never logged and is stored only in the encrypted `store_config` path; this doesn't fix the cryptographic weakness but limits blast radius.

---

### MEDIUM — `express.urlencoded()` has no `verify` callback — rawBody unavailable for form-encoded webhooks

**Where:** `packages/server/src/index.ts:1233`

**What:**
The global `express.json()` parser at line 1228 captures `req.rawBody` via its `verify` callback. The `express.urlencoded()` parser at line 1233 has no `verify` callback — any webhook that arrives with `Content-Type: application/x-www-form-urlencoded` (Twilio SMS/voice, Plivo) will NOT have `req.rawBody` populated. The current Twilio and Plivo implementations happen to work because they verify signatures using `req.body` (parsed key-value pairs) rather than raw bytes. However: (1) future webhook providers or content-type variants relying on rawBody will fail silently, (2) any existing provider sending form-encoded JSON with a body-hash scheme (e.g. a custom Vonage configuration) will silently fail verification and reject all real webhooks, and (3) the discrepancy is a maintenance trap — any developer adding signature verification to a form-encoded webhook path will check for `req.rawBody` (consistent with other paths in the codebase) and not notice that it's always `undefined`.

**Code:**
```typescript
// index.ts:1228–1233
app.use(express.json({
  limit: '1mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; }, // ← captures rawBody
}));
// No verify callback — rawBody is NEVER set for URL-encoded bodies
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
```

**Exploit:**
A developer adds a new form-encoded webhook provider or extends Twilio/Plivo webhook verification to use raw bytes (e.g. to prevent `req.body` key normalization from bypassing the HMAC). The `req.rawBody` check silently returns `undefined` (not a crash), so the provider's `verifyWebhookSignature` returns `false`, and every real webhook is rejected with 403 — causing silent loss of all inbound SMS, voice status updates, or delivery receipts for that provider.

**Fix:**
Add a `verify` callback to the `express.urlencoded()` registration identical to the JSON one:
```typescript
app.use(express.urlencoded({
  extended: true,
  limit: '1mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; },
}));
```

---

### LOW — `httpsServer.maxHeadersCount` unset — relies on Node default

**Where:** `packages/server/src/index.ts:679–682`

**What:**
The HTTPS server is created at line 679 with `requestTimeout`, `headersTimeout`, and `keepAliveTimeout` explicitly set, but `maxHeadersCount` is left at its Node.js default of `null`. In Node.js 22, `null` means the count is governed only by `--max-http-header-size` (default: 16 KB total header block size). While 16 KB limits the memory per request, it doesn't bound the number of individual headers — an attacker can send hundreds of tiny headers that consume parsing CPU time disproportionate to the 16 KB budget. Setting an explicit `maxHeadersCount` (e.g. 50–100) would add defense-in-depth against header-count-based DoS even with small header values.

**Code:**
```typescript
// index.ts:679–682
const httpsServer = createHttpsServer(tlsOptions, app);
httpsServer.requestTimeout = 40_000;
httpsServer.headersTimeout = 45_000;
httpsServer.keepAliveTimeout = 65_000;
// maxHeadersCount not set — defaults to null (unlimited count, only total-size bounded)
```

**Exploit:**
An attacker sends requests containing 100+ tiny, unique headers. Each request stays within the 16 KB size limit but forces Node's HTTP parser to allocate and hash-compare 100 header name/value pairs per request. Combined with a high connection rate, this can degrade throughput on the event loop for parsing-heavy phases even within the rate limit window.

**Fix:**
Add `httpsServer.maxHeadersCount = 100;` (or a similar reasonable bound) immediately after the server is created. HTTP/1.1 well-behaved clients rarely send more than 20–30 headers; 100 is permissive while capping malicious oversending.

---

### INFO — No HTTP/2 (CVE-2023-44487 / Rapid Reset not applicable)

**Where:** `packages/server/src/index.ts:679`

**What:**
The server uses Node's built-in `https.createServer()` — plain HTTP/1.1 with TLS. No HTTP/2 (`spdy`, `http2.createSecureServer`) is used. CVE-2023-44487 (HTTP/2 Rapid Reset attack) is therefore not applicable to this codebase.

---

### INFO — Express 4.22.1 — not affected by CVE-2024-29041 (open redirect)

**Where:** `packages/server/package.json:29`

**What:**
The installed Express version is 4.22.1 (confirmed via `package-lock.json`). CVE-2024-29041 (open-redirect via malformed `Host` header in `res.redirect()`) was fixed in Express 4.19.2. Version 4.22.1 is patched. No action required.

---

### INFO — PM2 `instances: 1, exec_mode: 'fork'` — cluster mode not used

**Where:** `ecosystem.config.js:76–77`

**What:**
PM2 is configured with a single fork process, not cluster mode (`instances: max` or `exec_mode: 'cluster'`). The rate limiting and session state are SQLite-backed and survive restarts correctly. The sticky-session / login-lockout-counter inconsistency risk from multi-worker cluster mode is not present in this deployment.

---

### INFO — TLS configuration is hardened correctly

**Where:** `packages/server/src/index.ts:649–676`

**What:**
TLS uses `minVersion: 'TLSv1.2'`, an explicit `ciphers` allowlist (ECDHE + AES-GCM + ChaCha20-Poly1305 only), and `honorCipherOrder: true`. The cipher suite matches Mozilla Intermediate profile. No weak ciphers (CBC-mode AES, RC4, DES) are included. HSTS is emitted in production at 180 days + `includeSubDomains`. `headersTimeout: 45_000` and `requestTimeout: 40_000` prevent slowloris-style attacks.

---

### INFO — `trust proxy` set to explicit IP allowlist, not `true`

**Where:** `packages/server/src/index.ts:631–634`, `packages/server/src/config.ts:342–348`

**What:**
`app.set('trust proxy', TRUST_PROXY_ALLOWLIST)` uses an explicit array of trusted proxy IPs from `TRUSTED_PROXY_IPS` env, falling back to `['loopback']`. This was previously `1` (trust first hop unconditionally). The tenantResolver (`middleware/tenantResolver.ts:81–100`) further validates `X-Forwarded-Host` only from socket IPs that appear in `config.trustedProxyIps`, using `req.socket.remoteAddress` (not `req.ip`), preventing X-Forwarded-Host spoofing from untrusted upstreams. The `localhostOnly` middleware (super-admin, management) also uses `req.socket.remoteAddress` directly, not `req.ip`.

---

### INFO — Stripe webhook correctly uses `express.raw()` before global JSON parser

**Where:** `packages/server/src/index.ts:1210–1212`

**What:**
The Stripe webhook is the only endpoint that uses `express.raw({ type: 'application/json', limit: '1mb' })` mounted before the global `express.json()`. The `billing.routes.ts` handler then calls `stripe.webhooks.constructEvent(req.body, sig, secret)` against the raw Buffer. This is the correct pattern — Stripe's SDK verifies the exact wire bytes, not a re-serialized object. The mounting order is confirmed safe.

---

### INFO — body-parser decompression limit enforced correctly

**Where:** `packages/server/src/index.ts:1228–1233`, `node_modules/body-parser/lib/read.js:63–79`

**What:**
Both `express.json({ limit: '1mb' })` and `express.urlencoded({ limit: '1mb' })` pass the `limit` option to `raw-body` which applies it to the **decompressed** stream. Verified by reading `body-parser/lib/read.js:64` (`opts.length = length`) and `getBody(stream, opts, ...)`. A gzip-compressed 10 KB body that expands to 2 MB will be rejected at 1 MB during decompression, before the full expanded payload is materialized. Decompression bomb risk is mitigated.

---

## Scope-cleared checklist

1. **HTTP request smuggling (CL + TE double-header):** Node's HTTP parser (in Node 22) rejects requests with both `Content-Length` and `Transfer-Encoding` headers by default (`--insecure-http-parser` is not set). No custom HTTP server or raw socket ingestion that could accept smuggled requests was found.
2. **CVE-2024-29041 (Express open redirect):** Express 4.22.1 installed, patched. Verified against `package-lock.json`.
3. **HTTP/2 Rapid Reset (CVE-2023-44487):** HTTP/2 not in use. `https.createServer()` is HTTP/1.1 only.
4. **Cluster + sticky sessions:** PM2 `instances: 1, exec_mode: 'fork'`. No multi-worker state inconsistency possible.
5. **trust proxy `true` (XFF spoofing):** Explicit IP allowlist used, fallback to loopback. Cross-checked in tenantResolver and localhostOnly.
6. **Decompression bomb via inflate:** body-parser 1.20.4 enforces the `limit` on decompressed size via `raw-body`. Confirmed by reading source.
7. **Stripe webhook raw-body ordering:** Correctly mounted before global JSON parser with `express.raw()`.
8. **TLS ciphers and minimum version:** Hardened with explicit allowlist, TLSv1.2 minimum, `honorCipherOrder`.
9. **Telnyx/Vonage rawBody availability:** Both send JSON (`application/json`); global `express.json()` verify callback captures `req.rawBody` correctly for these providers.
10. **slowloris / keep-alive abuse:** `headersTimeout: 45s`, `requestTimeout: 40s`, `keepAliveTimeout: 65s` all explicitly set. Adequate protection.
