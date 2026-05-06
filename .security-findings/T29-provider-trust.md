# T29 — Provider / 3rd-Party API Response Trust Boundary

**Audited files:**
- `packages/server/src/services/stripe.ts`
- `packages/server/src/services/blockchyp.ts`
- `packages/server/src/services/cloudflareDns.ts`
- `packages/server/src/services/githubUpdater.ts`
- `packages/server/src/services/catalogScraper.ts`
- `packages/server/src/services/catalogSync.ts`
- `packages/server/src/services/walletPass.ts`
- `packages/server/src/services/email.ts`
- `packages/server/src/providers/sms/twilio.ts`
- `packages/server/src/providers/sms/vonage.ts`
- `packages/server/src/providers/sms/telnyx.ts`
- `packages/server/src/providers/sms/bandwidth.ts`
- `packages/server/src/providers/sms/plivo.ts`
- `packages/server/src/providers/sms/index.ts`
- `packages/server/src/routes/geocode.routes.ts`
- `packages/server/src/routes/sms.routes.ts`
- `packages/server/src/routes/fieldService.routes.ts`
- `packages/server/src/routes/customers.routes.ts`
- `packages/server/src/routes/catalog.routes.ts`

---

### MEDIUM — `customer.subscription.updated` ignores `trialing`/`past_due` status: paying tenant keeps plan indefinitely

**Where:** `packages/server/src/services/stripe.ts:897-926`

**What:**
The `customer.subscription.updated` webhook handler only acts on `status === 'active'` (upgrade to pro) and `status === 'canceled' || status === 'unpaid'` (downgrade to free). Stripe's subscription state machine also produces `'trialing'`, `'past_due'`, `'incomplete'`, and `'incomplete_expired'`. A subscription that legitimately transitions from `active` → `past_due` via this webhook leaves the tenant on `plan = 'pro'` indefinitely because the status update silently falls through both branches without touching the tenant row. The `invoice.payment_failed` path does handle `past_due` separately, but a provider-side feature change or a MitM that substitutes `status: "trialing"` in the response body would block the downgrade path entirely.

**Code:**
```typescript
if (sub.status === 'active') {
  masterDb.prepare(`UPDATE tenants SET plan = 'pro', ... WHERE id = ?`).run(tenantWithSub.id);
} else if (sub.status === 'canceled' || sub.status === 'unpaid') {
  masterDb.prepare(`UPDATE tenants SET plan = 'free', ... WHERE id = ?`).run(tenantWithSub.id);
}
// 'trialing', 'past_due', 'incomplete', 'incomplete_expired' — silently no-op
```

**Exploit:**
A compromised provider sub-account, misconfigured TLS, or a future Stripe API change that emits `status: "past_due"` instead of `status: "unpaid"` on cancellation would leave a downgraded tenant continuing to access paid-tier features. Additionally an attacker who can forge a single `customer.subscription.updated` event body (bypassing signature via a compromised Stripe test-mode credential) with `status: "trialing"` would neutralise a legitimate cancellation already in flight.

**Fix:**
Add an explicit `else` branch (or a `default` label) that sets `payment_past_due = 1` for `'past_due'` and downgrades to `'free'` for `'incomplete_expired'`/`'incomplete'` beyond their collection window. At minimum add a `default` log-and-alert branch so silent fall-through is impossible.

---

### MEDIUM — Nominatim geocode response: no Content-Length cap, no response-body size guard

**Where:** `packages/server/src/routes/geocode.routes.ts:36-47`

**What:**
`/api/v1/geocode` proxies a request to `https://nominatim.openstreetmap.org/search` and calls `response.json()` directly on the full response. There is no Content-Length check and no buffered-read cap. A MitM or a future Nominatim API version that returns a large response (e.g., hundreds of results instead of `limit=1`) would cause Node.js's built-in fetch to buffer the entire response body before `json()` can parse it. The catalogScraper and cloudflareDns services both implement the 10 MiB / arrayBuffer cap pattern; the geocode handler does not.

**Code:**
```typescript
const response = await fetch(url.toString(), {
  headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'en' },
  signal: AbortSignal.timeout(5000),
});
// No content-length check
body = await response.json();  // unbounded buffer
```

**Exploit:**
A compromised Nominatim DNS (DNS rebinding, BGP hijack, or a hypothetical self-hosted Nominatim whose config is flipped) returns a multi-megabyte JSON array. Every geocode lookup by any tenant exhausts Node.js heap proportionally; at moderate request rates this becomes a per-request memory DoS that can OOM the process.

**Fix:**
Add a `Content-Length` header check against a cap (e.g. 512 KB) before calling `json()`, or switch to `arrayBuffer()` with a streaming cap. Mirror the pattern already used in `catalogScraper.ts:430-443`.

---

### LOW — Geocode coordinates returned to client lack bounds validation: `customers.routes.ts` silently stores out-of-range lat/lng from geocode response

**Where:** `packages/server/src/routes/customers.routes.ts:1051-1052` and `packages/server/src/routes/geocode.routes.ts:59-66`

**What:**
`geocode.routes.ts` returns coordinates parsed via `parseFloat` with only an `isNaN` guard (line 62). There is no `-90 ≤ lat ≤ 90` / `-180 ≤ lng ≤ 180` bounds check on the geocode response. The fieldService routes correctly validate with `validateLatLng()`, but `customers.routes.ts` writes lat/lng from the request body with only an `isFinite` check (lines 1051-1052 and 1399-1407). A poisoned Nominatim response returning coordinates outside the valid range (or sentinel values like `999` or `-999`) would be silently stored in the `customers` table, poisoning haversine routing calculations.

**Code:**
```typescript
// geocode.routes.ts — no range guard
const lat = parseFloat(String(first.lat ?? ''));
const lng = parseFloat(String(first.lon ?? ''));
if (isNaN(lat) || isNaN(lng)) {  // only NaN check, not range
  return void res.json({ success: true, data: null });
}

// customers.routes.ts — only isFinite, no range
const lat = typeof inputAny.lat === 'number' && isFinite(inputAny.lat) ? inputAny.lat : null;
const lng = typeof inputAny.lng === 'number' && isFinite(inputAny.lng) ? inputAny.lng : null;
```

**Exploit:**
A compromised geocode provider returns `lat: 999, lng: 999`. The geocode route passes them through; the client stores them via `PATCH /customers/:id`. Any query that computes haversine distances from these rows silently returns corrupted route-optimization data. The values `999`/`-999` are `isFinite()` truthy and would pass validation in both locations.

**Fix:**
Add `lat < -90 || lat > 90` / `lng < -180 || lng > 180` rejection in `geocode.routes.ts` before emitting the response, and apply the same bounds check in `customers.routes.ts` (mirroring the `fieldService.routes.ts:validateLatLng` helper).

---

### LOW — Inbound SMS message body: no application-level length cap before DB write and auto-responder matching

**Where:** `packages/server/src/routes/sms.routes.ts:1032-1093`

**What:**
After provider signature verification, `msgBody` is written to `sms_messages.message` (line 1032) and then immediately passed into `tryAutoRespond` (line 1092). While the global `express.urlencoded` parser caps the entire request body at 1 MB (index.ts line 1233), that cap is for the full multi-field form body. Twilio and other providers may send large concatenated SMS messages (via multiple SMS segments with no client-enforced limit). There is no application-level max-length check on `msgBody` before the DB write or the regex-based auto-responder matching. A compromised or MitM provider response that maximises the body field to the full 1 MB limit would write a 1 MB string to the DB and force all auto-responder regexes to run against it.

**Code:**
```typescript
const { from, to, body: msgBody, providerId, media, messageType } = parsed;
// ...
await adb.run(
  `INSERT INTO sms_messages (..., message, ...) VALUES (?, ...)`,
  from, to || '', convPhone, msgBody, ...   // no length cap on msgBody
);
// ...
const match = await tryAutoRespond(adb, { from: convPhone, body: msgBody, ... });
```

**Exploit:**
A MitM that injects a 900 KB `Body` field in a Twilio-style URL-encoded webhook payload (staying under the 1 MB urlencoded limit) causes the server to write 900 KB to the `sms_messages` table on every inbound message, and runs all configured auto-responder regexes (which may include pathological patterns) against it. At the Twilio webhook rate-limit of 60/min, this is 54 MB of DB writes per minute plus regex work per message.

**Fix:**
Truncate or reject `msgBody` exceeding a reasonable SMS limit (e.g. 10,000 characters covers 14 concatenated segments) immediately after `parseInboundWebhook` and before the DB write. Log a warning if a provider sends an oversized body.

---

### LOW — `customer.subscription.updated` with `status: 'active'` unconditionally upgrades any plan to `pro` without checking the subscribed price ID

**Where:** `packages/server/src/services/stripe.ts:897-907`

**What:**
When `customer.subscription.updated` fires with `status: 'active'`, the handler upgrades the tenant to `plan = 'pro'` without verifying that `sub.items.data[0].price.id` matches the configured `STRIPE_PRO_PRICE_ID` or `STRIPE_ENTERPRISE_PRICE_ID`. A compromised Stripe sub-account or a provider API change that sets any subscription to `active` (e.g. a free-tier Stripe product accidentally linked to a customer) would cause the tenant to be elevated to `pro` without any payment validation.

**Code:**
```typescript
if (sub.status === 'active') {
  masterDb.prepare(
    `UPDATE tenants SET plan = 'pro', failed_charge_count = 0, payment_past_due = 0, ...`
  ).run(tenantWithSub.id);
}
// No check: is sub.items.data[0]?.price.id === config.stripeProPriceId ?
```

**Exploit:**
A Stripe test-mode key leaks to an attacker who creates a free/trial product and subscribes a tenant to it. When Stripe fires `customer.subscription.updated` with `status: 'active'`, the tenant is set to `plan = 'pro'` regardless of what product they are subscribed to. Note: the webhook signature is valid (real Stripe event), so signature checks do not help here.

**Fix:**
Validate `sub.items.data[0]?.price.id` against the configured price IDs before granting `plan = 'pro'`. Unknown or mismatched price IDs should log a warning and leave the plan unchanged (or set to free). This mirrors how `updateSubscription` explicitly calls `resolvePriceIdForPlan()`.

---

### INFO — `catalogScraper` bulk-import path accepts `image_url` / `product_url` from admin without protocol validation

**Where:** `packages/server/src/routes/catalog.routes.ts:468-469`

**What:**
The `/bulk-import` endpoint validates `image_url` and `product_url` only for length (2048 chars). There is no `http:`/`https:` protocol filter analogous to the one applied to scraped image URLs in `catalogScraper.ts:295-305`. A privileged admin who imports a CSV with `javascript:alert(1)` or `data:text/html,...` in `image_url` would store those values in `supplier_catalog`. The frontend rendering of `<img src="{image_url}">` on the catalog page would then execute JavaScript in the admin's browser.

**Code:**
```typescript
// catalog.routes.ts:468-469 (bulk-import)
const imageUrl = item.image_url ? validateTextLength(String(item.image_url).trim(), 2048, 'item.image_url') : null;
const productUrl = item.product_url ? validateTextLength(String(item.product_url).trim(), 2048, 'item.product_url') : null;
// No protocol check; catalogScraper.ts:292-304 has the guard only on the scraper path
```

**Exploit:**
A rogue admin (or a compromised admin session) imports a catalog CSV with `image_url: "javascript:alert(document.cookie)"`. The value passes the length check and is stored in `supplier_catalog`. Whenever the catalog page renders a product thumbnail, the browser executes the stored JavaScript in the admin context.

**Fix:**
Apply the same URL allowlist check from `catalogScraper.ts:292-305` to the `/bulk-import` and any other manual-insert path (including `catalog.routes.ts` line 796 `parts_order_queue.image_url`). Extract the check into a shared helper `validateCatalogUrl(url)` and call it from both paths.

---

## SCOPE CLEARED — items verified safe

1. **Stripe webhook signature** (`stripe.ts:529-539`): Uses `stripe.webhooks.constructEvent` with explicit `WEBHOOK_TOLERANCE_SECONDS = 300`. Relies on Stripe SDK HMAC-SHA256; no custom implementation. Safe.

2. **Stripe plan field trust** (`stripe.ts:760-841`): `checkout.session.completed` sets plan to hardcoded string `'pro'` — never interpolates any Stripe response field as the plan name. `updateSubscription` uses `resolvePriceIdForPlan()` which validates against a closed enum. Safe.

3. **BlockChyp `approved` field** (`blockchyp.ts:495-503`): Charge success path gates on `data.approved === true` (boolean). The service does not trust arbitrary string status fields. `reconcileAfterTimeout` also gates on `data.approved`. Safe.

4. **BlockChyp `sigFile` field** (`blockchyp.ts:506-509`): Treated as hex-encoded bytes, written to disk via `saveSignatureFile` using `Buffer.from(sigFileHex, 'hex')` — invalid hex is silently truncated by Node, never passed to a shell or template. Safe.

5. **GitHub updater tarball** (`githubUpdater.ts`): `performUpdate` is explicitly stubbed to return `{ success: false }` — no tarball download or execution occurs server-side. The `checkForUpdates` path only uses `git fetch` + `git rev-parse` via `execFile` (no shell, no tarball), with UP1/UP2/UP3 guards for SHA pinning, origin URL verification, and downgrade rejection. Safe.

6. **Cloudflare DNS response fields** (`cloudflareDns.ts:123-128`): `cfRequest` validates `body.success === true` before trusting `body.result`. The returned record `.id` (a string) is stored via parameterized SQL in `tenants.cloudflare_record_id`. No untrusted fields are interpolated into HTML or commands. Safe.

7. **SMS provider webhook signature** (all providers in `providers/sms/`): Twilio uses HMAC-SHA1 with `timingSafeEqual`; Telnyx uses Ed25519 with raw-body + timestamp replay guard; Vonage uses `verifyVonageJwt` with HS256 + `payload_hash` binding; Plivo uses HMAC-SHA256 V3; Bandwidth uses Basic auth with `timingSafeEqual`. All fail closed. Safe.

8. **WalletPass HTML escaping** (`walletPass.ts:51-58`, `197-248`): All customer-derived fields are passed through `escapeHtml()` before interpolation into the HTML template. No raw database values reach the HTML output. Safe.

9. **Email HTML sanitization** (`email.ts:169-187`): `sanitizeEmailHtml` strips `<script>` blocks, inline `on*=` handlers, and `javascript:` URLs. Body capped at 200 KB. `sanitizeSubject` strips CR/LF. Combined with nodemailer's parameterized header construction, SMTP header injection is not possible via these inputs. Safe.

10. **Geocode coordinate NaN handling** (`geocode.routes.ts:62-65`): `isNaN` check prevents `NaN` from propagating. However, bounds validation is missing (see MEDIUM finding above).
