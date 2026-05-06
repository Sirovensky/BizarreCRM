# T06 — HTTP Cache / CDN Cache / Browser Cache Poisoning

Auditor: slot T06
Files reviewed: `packages/server/src/index.ts`, `packages/server/src/routes/bookingPublic.routes.ts`,
`packages/server/src/routes/portal.routes.ts`, `packages/server/src/routes/portal-enrich.routes.ts`,
`packages/server/src/routes/paymentLinks.routes.ts`, `packages/server/src/routes/voice.routes.ts`,
`packages/server/src/routes/ticketSignatures.routes.ts`, `packages/server/src/routes/tv.routes.ts`,
`packages/server/src/routes/estimateSign.routes.ts`, `packages/server/src/utils/signedUploads.ts`,
`packages/server/src/middleware/tenantResolver.ts`

---

### MEDIUM — QR endpoint behind authMiddleware served with Cache-Control: public

**Where:** `packages/server/src/index.ts:1307-1318`

**What:**
`GET /api/v1/qr` is protected by `authMiddleware` (line 1307), meaning the QR image is user/tenant-specific (the `data` parameter encodes ticket IDs, order IDs, or other internal data). However, the response unconditionally sets `Cache-Control: public, max-age=3600` (line 1313). Any CDN, shared corporate proxy, or caching reverse proxy placed in front of the server will store this image for up to one hour and serve it to any subsequent requester — stripping the authentication entirely for cached responses.

**Code:**
```typescript
app.get('/api/v1/qr', authMiddleware, async (req, res) => {
  const data = req.query.data as string;
  if (!data || data.length > 2000) return res.status(400).send('Invalid data');
  try {
    const png = await QRCode.toBuffer(data, { width: 200, margin: 1 });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=3600');  // ← BUG: public on auth-gated endpoint
    res.send(png);
```

**Exploit:**
Attacker A (authenticated) requests `GET /api/v1/qr?data=ORDER-12345`; the CDN caches it publicly. Attacker B (unauthenticated, different tenant) requests the same URL — receives the cached QR image encoding internal order/ticket data without any authentication check.

**Fix:**
Replace with `Cache-Control: private, no-store` since QR codes are computed on-demand from user-controlled `data` and the content is never the same across users or tenants.

---

### MEDIUM — Public booking /availability served with Cache-Control: public without Vary: Host (multi-tenant cross-tenant cache poisoning)

**Where:** `packages/server/src/routes/bookingPublic.routes.ts:219`

**What:**
`GET /public/api/v1/booking/availability` responds with `Cache-Control: public, max-age=60`. In multi-tenant mode, this endpoint is mounted after `tenantResolver` (index.ts:1276, 1707), which selects the tenant DB based on the HTTP `Host` subdomain. A CDN or shared caching proxy that stores `public` responses does not vary its cache key by `Host` header unless instructed via `Vary: Host`. Without this header, the cached response for `tenant-a.example.com/public/api/v1/booking/availability?service_id=1&date=2026-05-06` can be served to requests for `tenant-b.example.com` with the same path and query — exposing tenant A's booking schedule and service IDs to tenant B's users.

**Code:**
```typescript
// packages/server/src/routes/bookingPublic.routes.ts:218-219
// Set Cache-Control after successful validation but before any DB query that could throw
res.set('Cache-Control', 'public, max-age=60');
// Missing: res.setHeader('Vary', 'Host');
```

**Exploit:**
In a multi-tenant SaaS deployment with a CDN (Cloudflare, etc.): attacker visits `tenant-a.example.com/public/api/v1/booking/availability?service_id=1&date=2026-05-06`, which gets CDN-cached. Another user visiting `tenant-b.example.com` (different Host) with the same path receives tenant A's availability data. This reveals tenant A's booking configuration and appointment availability cross-tenant.

**Fix:**
Add `res.setHeader('Vary', 'Host')` immediately after the `Cache-Control` header, or switch to `Cache-Control: private, max-age=60` which prevents shared caching altogether. The same change is needed for `GET /public/api/v1/booking/config` which also returns tenant-specific data (store name, phone, services) but sets no `Cache-Control` at all — relying on the global `private, no-cache` default only for `/api/v1/*` prefixed paths (line 1252-1259), which does NOT apply to `/public/api/v1/*`.

---

### LOW — /public/api/v1/booking/config has no Cache-Control header (falls through global middleware that only covers /api/v1/*)

**Where:** `packages/server/src/routes/bookingPublic.routes.ts:112-192` and `packages/server/src/index.ts:1252-1259`

**What:**
The global cache-control middleware at index.ts:1252 only fires for the `/api/v1` mount prefix — it sets `private, no-cache` for all GET requests under that prefix. The booking config endpoint is mounted at `/public/api/v1/booking` (index.ts:1707), so the prefix is `/public/api/v1/`, which the middleware never matches. The endpoint returns tenant-specific data (store name, phone, booking services list, hours, exception dates) without any `Cache-Control` header. Express then falls through to the default `ETag`-based caching (`etag: weak`, line 636), which means a CDN or shared proxy can cache tenant-specific configuration data indefinitely under a permissive default policy.

**Code:**
```typescript
// index.ts:1252–1259 — does NOT match /public/api/v1/*
app.use('/api/v1', (req, _res, next) => {
  const isPii = PII_PATH_PREFIXES.some(...)
  if (isPii) {
    _res.setHeader('Cache-Control', 'private, no-store, max-age=0');
  } else if (req.method === 'GET') {
    _res.setHeader('Cache-Control', 'private, no-cache');
  }
  next();
});
// /public/api/v1/booking/config → no Cache-Control header set
```

**Exploit:**
A CDN with `default-ttl` rules caches the unguarded `/public/api/v1/booking/config` response for tenant A. Requests for the same path from a different tenant (different `Host` but same URL path) receive stale cross-tenant data until the CDN TTL expires.

**Fix:**
Extend the cache-control middleware to also cover `/public/api/v1` paths, or add an explicit `Cache-Control: public, max-age=60, Vary: Host` to `GET /config` similar to `GET /availability`. A simpler fix: apply `res.set('Cache-Control', 'public, max-age=60')` + `res.setHeader('Vary', 'Host')` inside the `/config` handler.

---

### LOW — Signed-URL file endpoint (/signed-url/*) serves sensitive uploads with no Cache-Control header

**Where:** `packages/server/src/index.ts:1358-1394`

**What:**
The signed-URL endpoint serves customer PII files (MMS photos, recording audio, bench/shrinkage images, receipt attachments) to unauthenticated callers whose authenticity is established solely by the HMAC signature and `exp` timestamp. The handler calls `res.sendFile(resolved)` with no `Cache-Control` header (line 1389). Express will emit `ETag` + `Last-Modified` for file responses by default (Node `fs.stat` populates these). A browser or proxy that receives `ETag` and no explicit `no-store` will cache the file and may re-serve it without re-verifying the signature, including after the signature has expired. An attacker who obtains a short-lived signed URL could re-request from a warm browser cache after `exp` without triggering a server-side signature check.

**Code:**
```typescript
// index.ts:1389
res.sendFile(resolved, (err) => {  // ← no Cache-Control set; ETag auto-emitted
  if (err && !res.headersSent) {
    res.status(404).json({ success: false, message: 'File not found' });
  }
});
```

**Exploit:**
Attacker obtains a 1-hour signed URL for a customer photo. The URL is delivered in an email and opened in a browser which caches the response (browser stores ETag). After the `exp` passes (signature expired), the attacker re-navigates to the URL. The browser sends an `If-None-Match` conditional GET; if the server processes it (etag match → 304), the cached sensitive content remains accessible from browser disk cache without an updated signature. At minimum the browser cache continues serving the stale file until evicted.

**Fix:**
Add `res.setHeader('Cache-Control', 'private, no-store')` before the `res.sendFile` call so browsers and proxies never cache the content at all, consistent with the intent of time-limited signed URLs. Alternatively set `max-age` to equal the remaining TTL so the cache entry automatically expires when the signature does: `res.setHeader('Cache-Control', \`private, max-age=${Math.max(0, exp - Math.floor(Date.now()/1000))}\`)`.

---

### LOW — /admin HTML and /super-admin SPA index.html served with no Cache-Control: no-store

**Where:** `packages/server/src/index.ts:1782-1788` (admin) and `packages/server/src/index.ts:1510-1526` (super-admin SPA)

**What:**
`GET /admin` sends `admin/index.html` with only a custom CSP header — no `Cache-Control` header is set (line 1787). Similarly, `GET /super-admin` and `GET /super-admin/*` send the SPA `index.html` with only a CSP header set on an outer middleware (line 1502) but no `Cache-Control`. Express's `res.sendFile` will auto-generate `ETag` + `Last-Modified`. A browser may cache the admin HTML. After the operator logs out and the admin session is invalidated, if the browser's back button or cache serves the prior HTML, the admin panel UI remains visible to a local observer (e.g. shared workstation), and subsequent JavaScript execution may re-use cached resources. For `/super-admin` this is particularly relevant since it is localhost-only but multiple users may share the machine.

**Code:**
```typescript
// index.ts:1782–1788
app.get('/admin', (req, res) => {
  if (config.multiTenant && req.tenantSlug) {
    return res.status(403).send('...');
  }
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));  // ← no Cache-Control
});
// index.ts:1510–1526 — same pattern for /super-admin
```

**Exploit:**
Operator logs into admin panel on a shared workstation, performs work, logs out. A second user clicks browser back or opens browser history — cached `admin/index.html` loads, revealing the admin UI shell. If the SPA re-hydrates using cached JS bundles and the old session cookie is still in the jar (e.g., tab was not fully closed), partial admin access may persist.

**Fix:**
Add `res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private')` before the `res.sendFile` call for both the `/admin` and `/super-admin/*` handlers, mirroring the pattern already used for the portal-enrich v2 and payment-links public routes.

---

### INFO — widget.js served public without Vary: Host in multi-tenant mode

**Where:** `packages/server/src/routes/portal.routes.ts:1613-1623`

**What:**
`GET /api/v1/portal/widget.js` sets `Cache-Control: public, max-age=300` with no `Vary` header. In multi-tenant mode, the widget script content is identical across tenants (it's a static function). However, the script's runtime behavior uses `data-server` to point to a tenant subdomain. If a CDN caches the response and serves it cross-tenant, the cached copy is functionally safe because the script itself contains no per-tenant secrets. This is an INFO-level observation since the content is static, but it should be reviewed if the widget ever becomes tenant-parameterized.

**Code:**
```typescript
router.get('/widget.js', (_req: Request, res: Response) => {
  res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300');  // no Vary: Host
  res.send(getWidgetScript());
});
```

**Exploit:**
No immediate exploit since the widget script is tenant-agnostic static content. If ever parameterized (e.g., embed tenant name or API keys), the missing `Vary: Host` would cause cross-tenant script poisoning.

**Fix:**
Add `res.setHeader('Vary', 'Host')` as a precautionary measure now, before any tenant-parameterization work is done.

---

### INFO — CORS `Access-Control-Max-Age` not explicitly set; browser default allows 5s preflight caching

**Where:** `packages/server/src/index.ts:1105-1128`

**What:**
The `cors()` middleware is called without a `maxAge` option (line 1105). The npm `cors` library does not emit an `Access-Control-Max-Age` header when `maxAge` is not configured. Per the Fetch spec, when no `Access-Control-Max-Age` is present browsers use a default of 5 seconds before re-sending preflights. This means CORS allowlist changes (e.g., removing a compromised origin) take effect immediately on new requests without a window of cached-stale-allowlist exposure. The current behavior is actually secure by default. Noting as INFO because the absence of the header is intentional but worth documenting as a known behavior rather than an oversight.

**Code:**
```typescript
app.use(cors({
  origin: (origin, callback) => {
    if (!origin) { return callback(null, true); }
    if (isCorsOriginAllowed(origin)) { return callback(null, true); }
    logCorsRejection(origin);
    callback(new Error(`CORS not allowed: ${origin} ...`));
  },
  credentials: true,
  // maxAge: not set — browser default 5s applies
}));
```

**Exploit:**
None from omission. A long `Access-Control-Max-Age` (e.g., 86400s) would be the vulnerability — stale CORS caches would serve the old allowlist. The current unset behavior is correct.

**Fix:**
Consider adding `maxAge: 600` (10 minutes) explicitly for documentation purposes and to provide a bounded cache window that is both performant and quickly invalidated after policy changes.

---

## Summary

| SEV | Count | Title |
|-----|-------|-------|
| MEDIUM | 2 | QR endpoint public cache; booking multi-tenant Vary gap |
| LOW | 3 | booking/config missing Cache-Control; signed-URL no-store gap; admin HTML no-store |
| INFO | 2 | widget.js Vary gap; CORS maxAge implicit |
