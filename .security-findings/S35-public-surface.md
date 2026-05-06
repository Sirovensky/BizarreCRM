# S35 — Public/Unauthenticated Surface Security Findings

**Scope:** `bookingPublic.routes.ts`, `portal.routes.ts`, `portal-enrich.routes.ts`, `voice.routes.ts`, `paymentLinks.routes.ts`, `estimateSign.routes.ts`, `ticketSignatures.routes.ts`, `leads.routes.ts`, `signup.routes.ts`, `tracking.routes.ts`

---

### HIGH — `voiceInstructionsHandler` has no webhook signature verification

**Where:** `packages/server/src/routes/voice.routes.ts:694–720`; mounted at `packages/server/src/index.ts:1562`

**What:**
`voiceInstructionsHandler` is the TwiML/TeXML/BXML/NCCO endpoint that the telephony provider calls to get call routing instructions. All other voice webhook handlers (`voiceStatusWebhookHandler`, `voiceRecordingWebhookHandler`, `voiceTranscriptionWebhookHandler`, `voiceInboundWebhookHandler`) check `provider.verifyWebhookSignature`. `voiceInstructionsHandler` skips this check entirely and reads `?to=` from an unauthenticated GET request.

**Code:**
```typescript
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  // No provider.verifyWebhookSignature call here
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';
  const provider = getSmsProvider();
  // ...
  if (!provider.generateCallInstructions) {
    res.type('text/xml').send(`<?xml version="1.0" encoding="UTF-8"?>
<Response><Dial>${escapeXml(to)}</Dial></Response>`);
```

**Exploit:**
An external attacker can GET `/api/v1/voice/instructions/connect?to=%2B15551234567` to get TwiML returned that dials an arbitrary number. If Twilio fetches this URL in response to an inbound call, the attacker has effectively hijacked call routing. By calling the store's number and forcing a fraudulent TwiML response, toll fraud or call redirection is possible without any credentials.

**Fix:**
Add `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) { res.status(403)... return; }` at the top of `voiceInstructionsHandler`, matching the pattern used in the four other voice webhook handlers. Alternatively, add a static Twilio IP allowlist at the middleware level.

---

### HIGH — Signup email verification unconditionally bypassed in production

**Where:** `packages/server/src/routes/signup.routes.ts:618`

**What:**
The `skipEmailVerification` constant is hardcoded to `true` (a "TEMP-NO-EMAIL-VERIF" workaround), meaning every `POST /signup` immediately provisions a tenant without verifying the submitted email address. Any attacker can enumerate email addresses by creating tenants with victim emails, create fake tenants under any domain, and exhaust subdomain/slug space — all without proving ownership of the email. The comment says this must be reverted before public SaaS launch, but the flag is currently active on the production codebase.

**Code:**
```typescript
// TEMP-NO-EMAIL-VERIF (2026-04-24): email verification fully disabled
const skipEmailVerification = true;
if (skipEmailVerification) {
  logger.warn('signup: TEMP-NO-EMAIL-VERIF — email verification disabled', ...);
  const result = await provisionTenant({...});
```

**Exploit:**
Attacker POSTs `{ slug: "victim-shop", admin_email: "victim@company.com", admin_password: "x", shop_name: "...", captcha_token: "dev-captcha-token" }` (in dev) or any valid captcha (in prod). A tenant is provisioned immediately, the subdomain `victim-shop.bizarrecrm.com` is taken, and victim's email is associated with an attacker-controlled shop. The 3/hr IP rate limit is bypassable by rotating IPs.

**Fix:**
Set `const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';` and ensure SMTP is configured. Remove the temp bypass before any public launch.

---

### HIGH — Plaintext admin password stored in in-memory map during email verification flow

**Where:** `packages/server/src/routes/signup.routes.ts:105–114`, `660–669`

**What:**
When email verification is enabled (the non-bypassed path), the raw plaintext `adminPassword` is stored in the `pendingSignups` Map for up to 1 hour until the user clicks the verification link. Any heap dump, core dump, debug endpoint, or process memory exposure during that window leaks plaintext credentials. The password is only bcrypt-hashed in `provisionTenant` (called at click-time), but the in-memory store holds the raw value.

**Code:**
```typescript
const pendingSignups = new Map<string, {
  slug: string;
  shopName: string;
  adminEmail: string;
  adminPassword: string;  // ← plaintext
  // ...
}>();
// Later at signup time:
pendingSignups.set(verifyToken, {
  adminPassword: admin_password,  // raw from request body
```

**Exploit:**
An attacker who gains read access to the Node.js heap (via `--inspect` port, `/metrics` endpoint, or OS-level) can extract plaintext passwords for all users who signed up but have not yet verified their email.

**Fix:**
Hash the password immediately with `bcrypt.hash(admin_password, 12)` at POST /signup time before storing in `pendingSignups`. Pass the hash to `provisionTenant` instead of the raw password, and update `provisionTenant` to accept a pre-hashed value.

---

### MEDIUM — `voiceInstructionsHandler` accepts arbitrary `?to=` phone number without validation

**Where:** `packages/server/src/routes/voice.routes.ts:698–720`

**What:**
The `?to` query parameter is read verbatim from an unauthenticated GET request and passed directly to `provider.generateCallInstructions(action, { to, ... })` or escaped into TwiML. There is no validation that `to` is a valid phone number format, or any restriction on what numbers can be dialed. Beyond the signature-bypass issue above, even if signature verification were added, this endpoint lets the telephony provider dial any number specified in the TwiML URL — including premium-rate numbers.

**Code:**
```typescript
const to = (req.query.to as string) || '';
// ...
if (!provider.generateCallInstructions) {
  res.type('text/xml').send(`<Response><Dial>${escapeXml(to)}</Dial></Response>`);
```

**Exploit:**
If an attacker can forge Twilio signatures (or in the current no-verification state), they can dial premium-rate numbers, international numbers, or other high-cost destinations by crafting requests to this endpoint.

**Fix:**
Validate `to` against an E.164 phone number regex (`/^\+?[1-9]\d{1,14}$/`). Optionally add a country-code or prefix allowlist matching the tenant's country setting.

---

### MEDIUM — Payment link `callbackUrl` built from untrusted `X-Forwarded-Host` header

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:386–388`

**What:**
The `POST /:token/pay` public endpoint (no auth) builds the BlockChyp `callbackUrl` using `req.headers['x-forwarded-host']` before falling back to `req.headers.host`. If `X-Forwarded-Host` is not validated against the trusted proxy allowlist, an attacker can supply a forged `X-Forwarded-Host: evil.com` header and redirect the BlockChyp payment callback (including payment confirmation) to an attacker-controlled server. The `callbackUrl` endpoint (`/paid-callback`) is also mentioned in the code but does not appear to be implemented, meaning payment confirmations silently fail regardless.

**Code:**
```typescript
const protocol = req.headers['x-forwarded-proto'] || (req.secure ? 'https' : 'http');
const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
const callbackUrl = `${protocol}://${host}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;
```

**Exploit:**
Attacker sends `POST /api/v1/public/payment-links/<token>/pay` with `X-Forwarded-Host: attacker.com`. BlockChyp posts payment confirmation to `https://attacker.com/...`, attacker can see the payment was completed and mark it as paid on their side while the server never marks the link paid (since `/paid-callback` isn't implemented).

**Fix:**
Use `req.hostname` (which respects Express's `trust proxy` setting) or the configured `config.baseDomain` instead of reading `X-Forwarded-Host` directly. Add the paid-callback handler with BlockChyp signature verification.

---

### MEDIUM — Portal-enrich v2 `portalAuth` does not enforce idle timeout (4h rule bypass)

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:65–98`

**What:**
The `portalAuth` middleware in `portal-enrich.routes.ts` only checks `expires_at > datetime('now')` but does not check `last_used_at` for idle session enforcement. By contrast, `portal.routes.ts:portalAuth` enforces a 4-hour idle timeout (SEC-M45) and evicts sessions that have not been used recently. A compromised or stolen portal session can be used indefinitely on the v2 enrichment routes (receipt PDFs, warranty certs, loyalty, referrals, photos, reviews) until the 24-hour absolute expiry, even if the customer logged out or the session was considered idle.

**Code:**
```typescript
// portal-enrich.routes.ts portalAuth — no last_used_at check:
const session = await adb.get<AnyRow>(
  `SELECT customer_id, scope, ticket_id, token
     FROM portal_sessions
    WHERE token = ? AND expires_at > datetime('now')`,
  token,
);
// no idle-timeout check, no last_used_at update
```

**Exploit:**
Attacker steals a portal session token (e.g. via network interception on HTTP, SSRF, or log exposure). On portal v1 routes the session would be evicted after 4h idle. On portal v2 (`/portal/api/v2/*`) the attacker can continue reading receipts, warranty certs, loyalty points, and submitting reviews for up to 24 hours even after the customer's v1 session was kicked.

**Fix:**
Extract the idle-timeout logic from `portal.routes.ts:portalAuth` into a shared utility and apply it in `portal-enrich.routes.ts:portalAuth`. Also update `last_used_at` on every v2 request so the idle window resets for active sessions.

---

### MEDIUM — Referral code has only 24 bits of entropy (16.7M space), brute-forceable

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:211–213`

**What:**
`generateReferralCode()` returns `crypto.randomBytes(3).toString('hex').toUpperCase()` — a 6-character hex string with 24 bits of entropy (16,777,216 possible values). Referral codes are publicly usable (they're shared with potential new customers). If the referral-redeem endpoint doesn't have its own rate limit, the entire code space can be exhausted in hours with a modest botnet.

**Code:**
```typescript
function generateReferralCode(): string {
  return crypto.randomBytes(3).toString('hex').toUpperCase(); // 6 chars, 16M space
}
```

**Exploit:**
Attacker bruteforces valid referral codes to claim loyalty rewards or referral bonuses without a real referral. With 16M codes and a 30-request/min rate limit, the full space can be scanned in ~9 months from one IP, or much faster from a botnet.

**Fix:**
Increase to at least `crypto.randomBytes(8).toString('base64url')` (~11 chars, 64 bits entropy). Alternatively, add a per-IP rate limit on the referral-redeem endpoint and limit redemptions per code.

---

### MEDIUM — Public estimate sign endpoint — no captcha, no identity verification

**Where:** `packages/server/src/routes/estimateSign.routes.ts:497–642`

**What:**
`POST /public/api/v1/estimate-sign/:token` accepts `signer_name` (free text, ≤200 chars), optional `signer_email`, and a signature image. The signer's identity is entirely self-asserted — anyone with the sign link can submit any name. The rate limit is only 10 requests/hr per IP, which is adequate for brute-force protection but does not prevent a person who intercepts a sign link from signing as "CEO John Smith" on a contract. There is no captcha, no email OTP, and no identity cross-check against the estimate's customer record.

**Code:**
```typescript
const signerName = (req.body.signer_name || '').trim();
if (!signerName || signerName.length > 200) {
  throw new AppError('signer_name is required and must be ≤ 200 characters', 400);
}
// No verification that signerName matches the estimate's customer
```

**Exploit:**
Attacker intercepts the sign link (e.g., via email forwarding, shoulder-surfing, or shared device). They submit `signer_name: "Customer Name"` (which they read from the estimate's line items visible in the GET response), sign the estimate, and it is legally binding. The audit log shows `signer_ip` but not whether identity was verified.

**Fix:**
Add a light identity gate: require `signer_email` and verify it matches the estimate's customer email (compare via constant-time hash to avoid timing leak). If no email on file, require the last-4 of the customer's phone number. Document the limitation as INFO if a fully-unverified design decision is intentional.

---

### MEDIUM — `POST /api/v1/track/lookup` uses suffix-LIKE to find customers by phone last-4, leaks all customer tickets

**Where:** `packages/server/src/routes/tracking.routes.ts:263–273`

**What:**
The `/lookup` endpoint finds customers by matching the last 4 digits of the phone number with `LIKE '%${last4}'`. This is a known-weak authentication factor: with only 10,000 possible last-4 values (0000–9999), an attacker can iterate all combinations from multiple IPs to enumerate every customer's ticket list. Although there is a per-last4 rate limit of 10/hr, only 3 digits of per-IP rate limiting (1 per 5s) protects the global surface. A botnet rotating 10 IPs can exhaust all 10,000 last-4 combinations in under 14 hours.

**Code:**
```typescript
const last4Key = `lookup_last4:${last4}`;
if (!checkWindowRate(req.db, 'tracking_last4', last4Key, 10, 60 * 60 * 1000)) {
// ...
const customers = await adb.all<AnyRow>(`
  WHERE ...
    LIKE ?
`, `%${last4}`, `%${last4}`, `%${last4}`);
```

**Exploit:**
Attacker iterates all 10,000 last-4 combinations with 10 IPs (1 per 5s each), receiving all customer tickets per phone segment. This allows customer enumeration and reveals repair history, customer names, and device types across the entire tenant.

**Fix:**
Require both last-4 AND an order_id to narrow the lookup to a specific customer's ticket (the `order_id` filter already exists but is optional). Make both fields mandatory in `/lookup`, or add a CAPTCHA gate after 3 failed lookups per IP.

---

### LOW — Portal session token returned in JSON response body (not just httpOnly cookie)

**Where:** `packages/server/src/routes/portal.routes.ts:521`, `675–683`

**What:**
Both `POST /quick-track` and `POST /login` return the portal session token in the JSON response body (`{ data: { token, ... } }`). While this is intentional for API clients (mobile apps), it means the token is also returned to web clients where it could be read by any JavaScript (XSS). The httpOnly cookie pattern (used for staff JWT) would prevent XSS token theft. Additionally, a token logged via `audit()` would expose it in audit logs.

**Code:**
```typescript
// POST /quick-track response:
res.json({ success: true, data: { token, csrf_token: csrfToken, ticket: detail } });
// POST /login response:
res.json({ success: true, data: { token, csrf_token: csrfToken, ... } });
```

**Exploit:**
An XSS vulnerability anywhere on the portal page (including third-party widgets, Google review redirect) can steal the portal session token from JavaScript-accessible memory or `localStorage` if the frontend stores it there.

**Fix:**
Issue the portal session token as an `httpOnly; SameSite=Strict` cookie (matching the staff refresh token pattern), eliminating JS-readable token exposure. Keep the JSON body token for backward-compat of native app clients only if needed, with explicit documentation.

---

### LOW — Tracking endpoint `GET /track/portal/:orderId` returns IMEI/serial (selected but not mapped in response)

**Where:** `packages/server/src/routes/tracking.routes.ts:414–417`, `477–482`

**What:**
The SQL query for `GET /track/portal/:orderId` selects `imei, serial_number` from `ticket_devices`, but the response mapping only includes `name, type, status, due_on, notes`. The IMEI and serial are currently not returned because they are not mapped. However, this is a latent PII exposure risk — if a developer adds them to the response object without realizing they are sensitive, or if the code is refactored to use `...d` spread, IMEI and serial numbers would be exposed to anyone with a tracking token.

**Code:**
```typescript
SELECT device_name, device_type, imei, serial_number, status, due_on, additional_notes
FROM ticket_devices WHERE ticket_id = ?
// ...
devices: devices.map(d => ({
  name: d.device_name,
  type: d.device_type,    // imei and serial_number NOT included but ARE fetched
  status: d.status,
```

**Exploit:**
Low severity currently (not returned), but if the select list or mapping changes, full IMEI/serial numbers would be exposed to any user with a tracking token (which is 64-bit random, but still unauthenticated access to sensitive hardware identifiers).

**Fix:**
Remove `imei, serial_number` from the SELECT in the tracking portal query since they are not used in the response. This eliminates the latent risk and reduces DB data transfer.

---

### LOW — Estimate sign link default TTL is 30 days (exceeds recommended maximum)

**Where:** `packages/server/src/routes/estimateSign.routes.ts:38`, `40`

**What:**
`DEFAULT_TTL_MINUTES = 4320` (3 days). `MAX_TTL_MINUTES = 30 * 24 * 60` (30 days). The comment in the hunt prompt flags portal tokens > 30 days; here the estimate sign URL can be valid for up to 30 days. Given that no identity verification is performed on the signer, a sign link intercepted from an email can be used for up to 30 days to submit a fraudulent signature. The HMAC is single-use (consumed_at), so replay is prevented, but the long window allows interception attacks.

**Code:**
```typescript
const DEFAULT_TTL_MINUTES = 4320; // 3 days
const MAX_TTL_MINUTES = 30 * 24 * 60; // 30 days max
```

**Exploit:**
Admin issues a sign link to a customer with a 30-day TTL. Attacker intercepts the email (via compromised email account, MITM on email delivery). Up to 30 days later, attacker submits the signature.

**Fix:**
Reduce `MAX_TTL_MINUTES` to 7 days maximum and `DEFAULT_TTL_MINUTES` to 48 hours. Consider sending a reminder SMS/email with a fresh link if the original expires unused.

---

### LOW — `POST /api/v1/track/portal/:orderId/message` does not validate message content size before trim

**Where:** `packages/server/src/routes/tracking.routes.ts:709–721`

**What:**
The message content is truncated to 5000 characters via `.slice(0, 5000)` before INSERT, but no explicit rejection of oversized content occurs. A body parser limit of 1MB (`express.json({ limit: '1mb' })`) is the only upstream guard. An attacker can POST a ~1MB content field, which is accepted, processed, and silently truncated. This is a minor DoS/spam amplification concern (wasting DB writes and body parsing).

**Code:**
```typescript
const rawContent = typeof content === 'string' ? content : ...;
const trimmedContent = rawContent.trim();
// ...
`, ticket.id, trimmedContent.slice(0, 5000));
```

**Exploit:**
Attacker submits 1MB messages on behalf of a ticket, generating noise in the ticket notes and consuming DB space. Rate limit (3/min per IP) partially mitigates this.

**Fix:**
Add `if (trimmedContent.length > 5000) { return res.status(400)...'Message too long (max 5000 chars)' }` before the INSERT, making the limit explicit and rejecting rather than silently truncating.

---

### INFO — SMS `send-code` endpoint lacks CAPTCHA (SEC-M21-captcha deferred)

**Where:** `packages/server/src/routes/portal.routes.ts:721–724`

**What:**
The portal `POST /register/send-code` SMS OTP endpoint has rate limits (3/hr per phone, 1/5s per IP, 10/day per phone) but explicitly defers a CAPTCHA integration as `SEC-M21-captcha` out-of-scope. Without CAPTCHA, a distributed botnet can continuously send SMS codes to victim phone numbers at the rate limit (up to 10/day per phone), which counts as SMS spam/harassment and inflates the tenant's SMS costs.

**Fix:**
Implement the deferred SEC-M21-captcha: add hCaptcha or Turnstile verification after the first 2 code requests per phone per hour. The `verifyCaptchaToken` helper from `signup.routes.ts` can be reused.

---

### INFO — Payment link `/paid-callback` webhook handler does not exist

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:388`

**What:**
The `POST /:token/pay` handler constructs `callbackUrl = .../paid-callback` and passes it to BlockChyp, but no route handler for `paid-callback` is registered anywhere in the codebase. When a customer completes payment on BlockChyp's hosted page, the callback fires to an unregistered route (404) and the payment link is never marked as `paid`. This is a business logic gap — payments succeed at the provider but the payment link remains `active`, potentially allowing the customer to pay again or the shop to not receive the paid status.

**Fix:**
Implement `POST /api/v1/public/payment-links/:token/paid-callback` with BlockChyp signature verification, then update the `payment_links` row to `status = 'paid'`, `paid_at = now()`, and broadcast the update via WebSocket.

---
