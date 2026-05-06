# T07 — Open Redirect / Unsafe Redirect Targets

Audited: 2026-05-06
Auditor: Claude Sonnet 4.6 (T07 slot)
Scope: `packages/server/src/` — all `res.redirect` calls, `Location:` header writes, host-derived URL construction in auth/signup/billing/voice/estimateSign/admin/notifications routes, OAuth callback URL building, Stripe success/cancel URL construction, BlockChyp callbackUrl.

---

### HIGH — Host-header injection into BlockChyp callbackUrl (unauthenticated public endpoint)

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:386-388`

**What:**
The public `/api/v1/public/payment-links/:token/pay` endpoint (no auth required) reads `X-Forwarded-Host` directly from `req.headers`, bypassing the `trustedProxyIps` gate enforced by `tenantResolver.ts`. An unauthenticated attacker submitting a `POST` with `X-Forwarded-Host: attacker.com` causes the server to register `https://attacker.com/api/v1/public/payment-links/<token>/paid-callback` as the BlockChyp webhook destination. BlockChyp will then POST payment-completion events (including card-last-four, transaction status, amount) to the attacker's server.

**Code:**
```typescript
// paymentLinks.routes.ts:386-388
const protocol = req.headers['x-forwarded-proto'] || (req.secure ? 'https' : 'http');
const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
const callbackUrl = `${protocol}://${host}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;
// callbackUrl is then passed directly to BlockChyp's sendPaymentLink API
const result = await createPaymentLink(req.db, dollars, description, callbackUrl);
```

**Exploit:**
`POST /api/v1/public/payment-links/<valid_token>/pay` with headers `X-Forwarded-Host: attacker.com` and `X-Forwarded-Proto: https`. BlockChyp registers `https://attacker.com/…/paid-callback` as the payment-complete hook; when the customer pays, BlockChyp POSTs the transaction receipt (including partial card data and amount) to the attacker.

**Fix:**
Derive the callback URL from `config.baseDomain` (same pattern as `billing.routes.ts`'s `validateBaseDomain`) or from `req.tenantSlug + config.baseDomain`, never from `req.headers`. Delete the `x-forwarded-host` / `x-forwarded-proto` reads in this handler.

---

### MEDIUM — Host-header injection into voice-call callback URL (authenticated, production)

**Where:** `packages/server/src/routes/voice.routes.ts:131`

**What:**
In production (`config.nodeEnv === 'production'`) the authenticated `POST /api/v1/voice/call` handler builds `callbackBaseUrl` from `req.get('host')` without validation. Any tenant staff member with the `voice/call` permission can inject a forged `Host:` header, causing the telephony provider (Twilio/Telnyx/Plivo/Bandwidth/Vonage) to POST call status, recording notifications, and transcription results to an attacker-controlled URL. These webhooks carry caller IDs, recording URLs, and in the case of transcription, full call transcripts.

**Code:**
```typescript
// voice.routes.ts:130-132 (POST /voice/call — auth required)
const callbackBaseUrl = config.nodeEnv === 'production'
  ? `https://${req.get('host')}`          // <-- unvalidated Host header in prod
  : `https://${lanIp}:${config.port}`;
// callbackBaseUrl is passed to provider.initiateCall() which registers it
// as the TwiML/status/recording/transcription callback URL with the provider.
```

**Exploit:**
An authenticated staff member sends `POST /api/v1/voice/call` with `Host: attacker.com`. The telephony provider registers `https://attacker.com/api/v1/voice/…` as webhook URLs; subsequent call status updates and recording-ready events (with presigned recording URLs or transcript text) are delivered to the attacker rather than this server.

**Fix:**
Replace `req.get('host')` with `req.tenantSlug ? \`${req.tenantSlug}.${config.baseDomain}\` : config.baseDomain`. No user-supplied header should influence provider callback registration.

---

### MEDIUM — Host-header injection into estimate e-sign URL returned to caller

**Where:** `packages/server/src/routes/estimateSign.routes.ts:188`

**What:**
`buildPublicSignUrl()` builds the customer-facing URL from `req.get('host')` without validation. This URL is returned in the JSON response body of `POST /api/v1/estimates/:id/issue-sign-url` (admin/manager auth required). The caller (staff) typically copies this URL and sends it to the customer via email or SMS outside the app. If an attacker with staff credentials (or a compromised staff browser) sends a request with a spoofed `Host:` header, the returned sign URL points to an attacker-controlled domain, enabling a phishing attack on the customer asked to sign the estimate.

**Code:**
```typescript
// estimateSign.routes.ts:185-189
function buildPublicSignUrl(req: Request, rawToken: string): string {
  const proto = req.protocol || 'https';
  const host = req.get('host') || `localhost:${config.port}`;  // <-- no validation
  return `${proto}://${host}/public/api/v1/estimate-sign/${encodeURIComponent(rawToken)}`;
}
```

**Exploit:**
Attacker (compromised staff account) sends `POST /api/v1/estimates/42/issue-sign-url` with `Host: attacker.com`. The response contains `{"url":"https://attacker.com/public/api/v1/estimate-sign/<token>"}`. Staff pastes this into a customer email. Customer clicks, lands on attacker page; attacker can harvest the customer's signature or identity info.

**Fix:**
Replace `req.get('host')` with `req.tenantSlug ? \`${req.tenantSlug}.${config.baseDomain}\` : config.baseDomain`. The tenant context is always available in authed routes via `req.tenantSlug`.

---

### MEDIUM — Host-header injection into account-termination warning email

**Where:** `packages/server/src/routes/admin.routes.ts:231-233`
Also: `packages/server/src/services/tenantTermination.ts:161,545`

**What:**
The `POST /api/v1/admin/terminate-tenant` (action: `request`) endpoint builds `appUrl` from `req.protocol` + `req.get('host')` and passes it to `requestTermination()`, which embeds it in an HTML email sent to the tenant's admin address as a "rotate your password here" link. A malicious admin (or CSRF on an admin session) can forge the `Host:` header so the warning email urges the admin to visit an attacker's site to "rotate their password".

**Code:**
```typescript
// admin.routes.ts:231-233
const proto = req.protocol;
const host = req.get('host') || `${req.tenantSlug}.${config.baseDomain}`;
const appUrl = `${proto}://${host}`;  // embedded verbatim in termination email
```

**Exploit:**
Admin triggers step-1 termination with `Host: attacker.com`. The warning email sent to the same admin reads: "If this was NOT you, rotate your password immediately: [https://attacker.com]". If the admin actually clicks that link (believing it's legitimate), they land on the attacker's credential-harvesting page.

**Fix:**
Replace the `req.get('host')` with `req.tenantSlug + '.' + config.baseDomain`. The tenant slug is already on the request object; use it.

---

### MEDIUM — Host-header injection into receipt email/SMS tracking URL

**Where:** `packages/server/src/routes/notifications.routes.ts:279-283` and `:439-446`

**What:**
Both `POST /notifications/send-receipt` (email) and `POST /notifications/send-receipt-sms` use `req.get('host')` unvalidated to build the tracking URL embedded in customer-facing receipts. Requires authenticated manager/admin. A staff member with the right role and a forged `Host:` header can cause a spoofed tracking URL to appear in customer receipt emails and SMS messages, redirecting customers to an attacker-controlled page.

**Code:**
```typescript
// notifications.routes.ts:280 (and :439)
const publicHost = `${req.protocol}://${req.get('host')}`;  // no validation
let trackingUrl: string | null = null;
if (linkedTicket?.tracking_token) {
  trackingUrl = `${publicHost}/track?token=${encodeURIComponent(linkedTicket.tracking_token)}`;
}
// trackingUrl appears as a clickable link in the email HTML and verbatim in the SMS body
```

**Exploit:**
Staff member (or compromised session) sends `POST /api/v1/notifications/send-receipt` with `Host: attacker.com`. Customer receives a legit-looking receipt email with a "View Online" link pointing to `https://attacker.com/track?token=<token>` — attacker can harvest the token or serve malicious content.

**Fix:**
Build `publicHost` from `config.baseDomain` and `req.tenantSlug`, not from `req.get('host')`.

---

### LOW — `effectiveBaseDomain` single-label strip only: deep subdomain bypass

**Where:** `packages/server/src/routes/signup.routes.ts:161-170`

**What:**
`effectiveBaseDomain` strips exactly ONE label (the first dot-delimited label) then tests the remainder against `TRUSTED_BASE_HOSTS`. If an attacker sends `Host: attacker.bizarrecrm.com.attacker2.com` (two dots before the trusted suffix), only one label (`attacker`) is stripped and the remainder (`bizarrecrm.com.attacker2.com`) is not in the trusted set, so the function correctly falls back to `config.baseDomain`. However the function also returns the raw `rawHost` when the hostNoPort is already in `TRUSTED_BASE_HOSTS`. Because `TRUSTED_BASE_HOSTS` includes `localhost`, an attacker can send `Host: localhost` and bypass the subdomain-strip path entirely, getting back `localhost` (raw) as the effective domain — which is the intended behaviour for dev. This is not exploitable as a real open redirect because the trust check explicitly allows `localhost`. Documented here as a hardening observation.

**Code:**
```typescript
// signup.routes.ts:158-159
if (TRUSTED_BASE_HOSTS.has(hostNoPort)) return rawHost; // keep port suffix for dev
```

**Exploit:**
No direct exploitable redirect. In production, `localhost` won't resolve to an attacker host. The risk is environmental: if a staging or CI deployment exposes the signup endpoint on `localhost` with a known SMTP server, a social-engineering campaign could exploit the `localhost` trust but this requires physical/network access.

**Fix:**
In production (`config.nodeEnv === 'production'`), do not allow `localhost` or `127.0.0.1` as trusted base hosts — use only `config.baseDomain`. Guard with: `if (config.nodeEnv === 'production' && (hostNoPort === 'localhost' || hostNoPort === '127.0.0.1')) return config.baseDomain;` before the trust check.

---

### INFO — `res.redirect` HTTP→HTTPS in index.ts reads raw `Host:` but sanitizes it

**Where:** `packages/server/src/index.ts:692-715, 854-858`

**What:**
The HTTPS-upgrade middleware and the raw-HTTP redirect server both read `req.headers.host` but pass it through `sanitizeRedirectHost()` (which validates against `config.baseDomain` and its subdomains) and `sanitizeRedirectUrl()` (which rejects `//`-relative and non-path URLs). These paths are well-defended and not exploitable.

**Code:**
```typescript
// index.ts:692-703 — sanitizeRedirectHost
function sanitizeRedirectHost(rawHost: string): string {
  const noCrlf = rawHost.replace(/[\r\n\0]/g, '').split(':')[0].toLowerCase();
  if (!/^[a-zA-Z0-9.-]+$/.test(noCrlf) || noCrlf.length > 253) return config.baseDomain;
  if (noCrlf === 'localhost' || noCrlf === '127.0.0.1') return noCrlf;
  if (noCrlf === config.baseDomain) return noCrlf;
  if (noCrlf.endsWith('.' + config.baseDomain)) return noCrlf;
  return config.baseDomain;  // untrusted host → safe fallback
}
```

**Exploit:**
Not exploitable. Documented as confirmation that the HTTPS-upgrade redirect paths are correctly handled, unlike the routes above.

**Fix:**
No change required. This is the correct pattern; the above findings should adopt the same approach.

---

### INFO — Password-reset email URL uses `config.baseDomain` (correctly hardened)

**Where:** `packages/server/src/routes/auth.routes.ts:1741-1743`

**What:**
`POST /forgot-password` correctly uses `config.baseDomain` (not any request header) to build the password-reset URL, per SEC-H7 comment. This is the correct pattern. Documented as confirmation.

**Code:**
```typescript
// auth.routes.ts:1741-1743
const tenantSlug = (req as any).tenantSlug || null;
const host = tenantSlug ? `${tenantSlug}.${config.baseDomain}` : config.baseDomain;
const resetUrl = `https://${host}/reset-password/${resetToken}`;
```

**Exploit:**
Not exploitable. Host-header injection is explicitly blocked here.

**Fix:**
No change. This is the reference implementation; routes T07-F1 through T07-F4 above should follow this same pattern.

---

## Scope Cleared

The following surfaces were checked and found safe or not applicable:

- **Login `?return=` / `?next=` open redirect:** No query-parameter-driven redirects exist in `auth.routes.ts`. The only `res.redirect` calls in `signup.routes.ts` redirect to URLs built from `effectiveBaseDomain()` (validated against `TRUSTED_BASE_HOSTS`) + a hardcoded path, never from query params.
- **OAuth `redirect_uri` allowlist:** `import.routes.ts:1457,1494` builds `redirectUri` from `req.get('host')`, but this URI is used as a parameter to the *RepairDesk* OAuth server (not a local redirect). The server itself never performs a `res.redirect` to this URI; it only passes it to the third party for token exchange. Risk is credential-exfil to an attacker-controlled OAuth flow if the Host header is spoofed — covered by this slot's host-header findings above.
- **Stripe `success_url` / `cancel_url`:** `services/stripe.ts:485-486` — both URLs are built from `baseUrl`, which is set in `billing.routes.ts:39` using `config.baseDomain` (not request headers). Not exploitable.
- **`javascript:` / `data:` scheme redirect:** No `res.redirect` anywhere in the codebase accepts a user-supplied URL value. All redirect targets are either hardcoded paths, or composed from `config.baseDomain`. No `javascript:` / `data:` scheme injection possible through `res.redirect`.
- **Protocol-relative `//attacker.com` redirect:** `sanitizeRedirectUrl()` in `index.ts:710` explicitly rejects strings starting with `//`. No other redirect path accepts user-supplied paths.
- **Booking / logout redirect with `?next=`:** No such parameters exist in `bookingPublic.routes.ts` or any logout route. The booking public routes have no redirect calls at all.
- **Voice recording `res.redirect`:** Calls `validateRecordingUrl()` first (allowlist of Twilio/Telnyx/Plivo/Bandwidth/Vonage hostnames, HTTPS-only, no IP literals). Not exploitable via stored recording URL injection.
