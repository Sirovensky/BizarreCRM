# T26 — Subresource Integrity / CDN Script Tampering / Asset Pinning

## Scope

Focus: `packages/server/src/admin/index.html`, `packages/server/src/admin/super-admin.html`,
`packages/server/src/admin/js/admin.js`, `packages/server/src/admin/js/super-admin.js`.
Also checked: global CSP in `src/index.ts`, `packages/management/src/renderer/index.html`.

---

### [LOW] /admin HTML page and /admin/js static mount lack `localhostOnly` middleware

**Where:** `packages/server/src/index.ts:1473` and `packages/server/src/index.ts:1782`

**What:**
The `/admin` HTML page and the `/admin/js/` static file mount are served without the
`localhostOnly` middleware that guards `/super-admin`. In a multi-tenant deployment (or any
deployment behind a public load-balancer), both the admin login page and the full admin-panel
JavaScript (`admin.js`, `super-admin.js`) are reachable by any external IP. While the API
itself (`/api/v1/admin`) is protected by token auth with rate-limiting, the login form is
exposed to brute-force attempts from the internet, and the JavaScript source (including every
API path, session-storage key name, and application logic) is downloadable by an attacker
for offline analysis.

**Code:**
```typescript
// packages/server/src/index.ts:1473 — no localhostOnly
app.use('/admin/js', express.static(path.resolve(__dirname, 'admin/js'), { index: false }));

// packages/server/src/index.ts:1782 — no localhostOnly
app.get('/admin', (req, res) => {
  if (config.multiTenant && req.tenantSlug) {
    return res.status(403).send('Server administration is not available...');
  }
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));
});
```

**Exploit:**
In a multi-tenant SaaS deployment, an attacker accesses `https://<master-domain>/admin` and
receives the login page; `https://<master-domain>/admin/js/super-admin.js` reveals the entire
super-admin UI logic and every API endpoint path. The login endpoint at `/api/v1/admin/login`
is rate-limited to 5 attempts per 15 min per IP, but an attacker using distributed source IPs
can still probe the existence and implementation of the admin panel. Contrast: `/super-admin`
correctly returns `404` to any non-loopback TCP connection.

**Fix:**
Apply `localhostOnly` as the first middleware on both mounts:
```typescript
app.use('/admin/js', localhostOnly, express.static(...));
app.get('/admin', localhostOnly, (req, res) => { ... });
```
For operators who legitimately access the admin panel remotely (single-tenant, home lab), the
recommended alternative is an SSH tunnel or a VPN rather than exposing the panel publicly.

---

### [INFO] Global CSP `script-src` unnecessarily allowlists `static.cloudflareinsights.com`

**Where:** `packages/server/src/index.ts:950`

**What:**
The global `helmet` CSP includes `https://static.cloudflareinsights.com` in `script-src`.
No HTML page in the codebase (neither the admin pages, the management SPA, nor any dynamically
rendered portal page) actually loads a Cloudflare Beacon script tag. The allowlist entry
therefore provides no legitimate functionality while widening the CSP's attack surface: if a
stored XSS injection into any React SPA page ever renders `<script src="https://static.cloudflareinsights.com/...">`, the browser would execute it without a CSP violation.

**Code:**
```typescript
// packages/server/src/index.ts:950
scriptSrc: ["'self'", 'https://static.cloudflareinsights.com'],
// ...
connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
```

**Exploit:**
An attacker who achieves stored XSS in a field rendered inside the React SPA (or who
compromises the `static.cloudflareinsights.com` CDN origin) can inject a script tag pointing
at that CDN. The CSP would permit it, turning a limited XSS into arbitrary script execution
in an operator session.

**Fix:**
Remove `https://static.cloudflareinsights.com` from `scriptSrc` (and the matching
`https://cloudflareinsights.com` from `connectSrc`) until the Beacon script is intentionally
added to a specific HTML page with a narrow per-route CSP. If Cloudflare analytics is later
needed, scope it to only the routes that load the beacon.

---

### [INFO] Super-admin SPA CSP uses `'unsafe-inline'` on `script-src`

**Where:** `packages/server/src/index.ts:1495`

**What:**
The CSP applied to the `/super-admin` SPA routes (`spaCsp`) allows `script-src 'self'
'unsafe-inline'`. This nullifies the CSP's XSS protection for the super-admin dashboard: any
injected inline script in a server-rendered HTML chunk would execute without a CSP violation.
The relaxation exists because the Vite production bundle emits small inline `<script>` bootstrap
blocks. The `/super-admin` route is `localhostOnly`, which substantially limits external
exploitability, but the full super-admin dashboard (all tenant data, audit log, session revocation)
is only one localhost-side XSS away from being compromised.

**Code:**
```typescript
// packages/server/src/index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; " +
  "script-src-attr 'none'; style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' data: blob:; connect-src 'self' ws: wss:; " +
  "font-src 'self' data:; frame-ancestors 'none'";
```

**Exploit:**
If an attacker achieves a DNS rebinding attack against `127.0.0.1` (covered in T10) or
exploits any SSRF that can write to the SPA's HTML via a shared file path, inline scripts
execute freely inside the super-admin panel context. In a normal browser session, any XSS
within a React component would execute with full super-admin API access.

**Fix:**
Replace `'unsafe-inline'` with Vite's `build.modulePreload: false` and a `vite-plugin-csp`
hash/nonce strategy, or use `build.cssCodeSplit: false` combined with
`experimental.renderBuiltUrl` to eliminate inline bootstrap blocks. The Vite ecosystem has
documented paths to a nonce-based CSP; see
[vite-plugin-html-csp-hash](https://github.com/KiraLT/vite-plugin-html-csp-hash) as one option.
The admin panel in `index.html` already achieves `script-src 'self'` (no `unsafe-inline`) — the
same strictness should be the target for the SPA.

---

## SCOPE CLEARED — No CDN/SRI issues found

After full end-to-end inspection, the following conditions are all confirmed safe:

1. **No external CDN `<script>` tags** — `admin/index.html` (line 148) and
   `admin/super-admin.html` (line 70) load only `/admin/js/admin.js` and
   `/admin/js/super-admin.js` respectively, both served from `'self'`.
   No jQuery, Bootstrap, Alpine, Vue, React CDN, or analytics snippet is loaded.

2. **No external `<link rel="stylesheet">` tags** — both HTML files embed all CSS inline in
   `<style>` blocks. No Google Fonts, FontAwesome, or other remote stylesheet.

3. **No mixed-content (`http://`) resources** — zero `http://` resource URLs in all admin files.

4. **No untrusted iframe embeds** — neither HTML file contains an `<iframe>`.
   `adminCsp` includes `frame-ancestors 'none'` (index.ts:1471).

5. **No form with non-self `action` attribute** — both pages use JavaScript `fetch()` calls
   to `/api/v1/admin` and `/super-admin/api` respectively. No `<form>` tag with an `action`
   attribute exists in either file.

6. **No `window.opener` / reverse tabnabbing** — neither admin JS file contains
   `target="_blank"`, `window.open()`, or `window.opener` references.

7. **No URL fragment token leak** — neither file uses `window.location.hash`,
   `onhashchange`, or puts tokens in URL fragments.

8. **Third-party widgets (Stripe.js, hCaptcha, Twilio) not loaded** — these are referenced
   only in the React tenant SPA (customer-facing), not in the admin panel pages audited here.

9. **Management SPA (`index.html`) has strict `default-src 'none'` meta CSP** — no external
   resources allowed; Google Fonts were explicitly removed per the `@audit-fixed` comment
   (management/src/renderer/index.html:7–22).

10. **`admin.js` and `super-admin.js` use `esc()` on all server-provided string values**
    before inserting via `innerHTML`. Numeric dashboard KPIs (`active_tenants`,
    `total_tenants`, etc.) are produced by SQL `COUNT()` / `Math.round()` on the server and
    are not string fields (verified in super-admin.routes.ts:658–665). The 2FA TOTP secret
    is rendered with `esc(secretCode)` (super-admin.js:60).
