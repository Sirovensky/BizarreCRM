# S07 — CSRF Protection Security Findings

Scope: `packages/server/src/utils/csrf.ts`, `packages/server/src/index.ts` (middleware order), all cookie-auth routes, Stripe/Twilio webhook endpoints
Reviewed: 2026-05-05

---

### [MEDIUM] portal-enrich v2 state-changing routes accept cookie auth but have NO CSRF protection

- Files:
  - `packages/server/src/routes/portal-enrich.routes.ts` — `DELETE /ticket/:id/photos` (line 493), `POST /ticket/:id/review` (line 704), `POST /customer/:id/referral-code` (line 861)
  - `packages/server/src/index.ts:1618` — mounted at `/portal/api/v2`
- Description: The `portalAuth` middleware in `portal-enrich.routes.ts` (line 72) accepts the portal session token from either `Authorization: Bearer` or the `portalToken` cookie. The `portalToken` is an auto-sent cookie (it is cleared with `res.clearCookie('portalToken')` in `portal.routes.ts:145`, implying the browser stores it). None of the three state-changing handlers in this file apply `requireCsrfToken`. The v1 portal routes (`portal.routes.ts`) correctly guard all their mutations — `POST /logout`, `POST /tickets/:id/comments`, `POST /tickets/:id/pay-link`, `POST /tickets/:id/feedback`, `POST /estimates/:id/approve` — with `requireCsrfToken`. The v2 routes were added later and missed the pattern.
- Exploit: An attacker's page can trigger `DELETE /portal/api/v2/ticket/123/photos`, `POST /portal/api/v2/ticket/123/review` (submitting a 1-star review), or `POST /portal/api/v2/customer/456/referral-code` on behalf of any authenticated portal customer who visits the attacker page, since the browser automatically sends the `portalToken` cookie and no extra header token is checked.
- Note: The global content-type guard (`index.ts:1284–1302`) blocks plain HTML `<form>` submissions (must be `application/json`), but a cross-origin `fetch` with `credentials: 'include'` and `Content-Type: application/json` can be issued from any origin — CORS is not a defence here because the portal paths are in `NO_ORIGIN_ALLOWED_PATHS` (line 1030), so they bypass the origin-enforcement middleware entirely.
- Fix: Import and apply `requireCsrfToken` from `utils/csrf.ts` to each of the three state-changing handlers in `portal-enrich.routes.ts`, in the same position as the v1 routes (after `portalAuth`, before the `asyncHandler`).

---

### [LOW] Twilio/voice webhook signature verification is conditional — missing implementation silently skips check

- Files:
  - `packages/server/src/providers/sms/types.ts:85` — `verifyWebhookSignature` is declared optional (`?`)
  - `packages/server/src/routes/voice.routes.ts:449, 506, 655, 737`
  - `packages/server/src/routes/sms.routes.ts:1123, 1503`
- Description: Every webhook handler guards with `if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req))` — the check is skipped entirely when the method is absent. The interface marks the method optional, so any SMS/voice provider that omits it (e.g. a future custom provider, or the `bizarresms` / `bandwidth` providers if they don't implement the method) will pass all inbound webhook requests without signature verification. The current Twilio provider correctly implements the check.
- Exploit: If an operator switches to or writes a provider without `verifyWebhookSignature`, any party that can POST to the public webhook URLs can inject synthetic inbound messages, manipulate call logs, or trigger status transitions without possessing a valid signature.
- Fix: Make `verifyWebhookSignature` required (not optional) in the `SmsProvider` interface, or add a `failClosed` fallback: when `provider.verifyWebhookSignature` is undefined, return 403 rather than continuing. A log-level warning already fires on failure; the fallback should be a hard reject.

---

### [LOW] CSRF cookie (auth) `csrf_token` is tied to the refresh-token lifetime, not the access-token session

- File: `packages/server/src/routes/auth.routes.ts:430–437`
- Description: The `csrf_token` cookie is only used to protect `POST /auth/refresh`. Its lifetime is set to match `refreshDays * 24 * 60 * 60 * 1000` (default 7–30 days). The token is a random 24-byte base64url value, which is secure. However: (1) on logout the `csrf_token` is cleared (line 1423) only for the current device; other concurrent sessions/tabs retain their copy. (2) `POST /auth/switch-user` rotates `csrf_token` (line 1575) but the other auth POSTs that rely on `authMiddleware` (e.g. `POST /auth/change-password`, `POST /auth/account/2fa/disable`) use JWT Bearer access tokens, not cookies — so they are correctly not vulnerable to CSRF. This is informational.
- Note: The `refreshToken` cookie and its `csrf_token` pair are `SameSite=Strict`, which is the strongest possible defence; the double-submit is a belt-and-suspenders backup. No exploitable weakness exists here, but the long-lived csrf_token is not rotated per-request; it persists across browser sessions if the user doesn't explicitly log out.

---

## NO FURTHER FINDINGS

**Items verified clean:**

- **Double-submit correctness**: `requireCsrfToken` in `csrf.ts` reads token from `req.cookies[CSRF_COOKIE_NAME]` and `req.header('x-csrf-token')`, compares with `crypto.timingSafeEqual` — correct implementation.
- **SameSite + Secure flags**: Both `portalCsrfToken` (SameSite=Strict) and `refreshToken`/`csrf_token` (SameSite=Strict) have correct attributes; `secure` is gated on `nodeEnv === 'production'` for the portal token and `req.secure || production` for auth tokens.
- **Token in URL / Referer leakage**: Tokens are returned in JSON response bodies only; the deprecated `GET /verify?token=` logs a warning but the token itself is the portal session token, not a CSRF token. No CSRF token appears in query strings or URLs.
- **Stripe webhook CSRF exemption + signature**: Mounted before global middleware at `index.ts:1215`; `webhookHandler` verifies `stripe-signature` before processing — correctly exempt and correctly verified.
- **CORS misconfiguration**: `credentials: true` is paired with explicit origin reflection (never `*`); attacker origins will not be in the allowlist; `NO_ORIGIN_ALLOWED_PATHS` exempts portal paths from the Origin-header enforcement, but that only affects origin-header gating, not CSRF — the CSRF token mechanism itself is unaffected by the origin exemption for read-only GETs.
- **GET endpoints mutating state**: No `router.get` calls were found that issue INSERT/UPDATE/DELETE in portal or auth routes (verified by grep).
- **Auth routes CSRF coverage**: The only cookie-auth endpoint for the main app session is `POST /auth/refresh`; all other auth POSTs use `authMiddleware` which requires a `Bearer` token header, making them immune to CSRF.
- **Token tied to session/user**: `generateCsrfToken()` generates 32 random bytes (portal) and `crypto.randomBytes(24).toString('base64url')` (auth). Neither is predictable from session data.

---

**Summary**: 1 MEDIUM (portal-enrich v2 mutation routes missing `requireCsrfToken`), 1 LOW (optional webhook signature verification), 1 LOW-INFO (csrf_token lifetime note).

---

## PASS 2 — DEEP DIVE

### Correction to Pass 1 MEDIUM finding — exploitability re-assessed

**Pass 1 stated** that the portal-enrich v2 mutation routes are CSRF-exploitable because `portalAuth` falls back to `req.cookies?.portalToken`. **Further investigation** shows that `portalToken` is stored exclusively in `sessionStorage` by the web client (`CustomerPortalPage.tsx:279`, `usePortalAuth.ts:77`) and sent only via `Authorization: Bearer` header — never set as a browser cookie by the server (`grep res.cookie packages/server/src/routes/portal.routes.ts` produces no portalToken setter; only `clearCookie('portalToken')` exists as defensive cleanup). The browser therefore does NOT auto-send `portalToken` on cross-site requests.

**Revised assessment**: The missing `requireCsrfToken` on the three portal-enrich v2 mutation routes (`DELETE /ticket/:id/photos`, `POST /ticket/:id/review`, `POST /customer/:id/referral-code`) represents a **latent CSRF / defense-in-depth gap** rather than an immediately exploitable vulnerability. The server code actively accepts the token from the cookie fallback path, which means if any future client change stores `portalToken` as a cookie (e.g., mobile deep-link, server-side-rendering, or Electron wrapper), all three routes become CSRF targets without any additional code change. The severity is **re-classified LOW** (latent risk), with the recommendation to add `requireCsrfToken` unchanged.

---

### [LOW] Tracking message route accepts portalToken cookie but has no CSRF check

**Where:** `packages/server/src/routes/tracking.routes.ts:589–598, 623` and `packages/server/src/index.ts:1595`

**What:**
`POST /api/v1/track/portal/:orderId/message` is the write endpoint in the public tracking surface. It calls `extractPortalSessionToken(req)` which reads the portal session token from `Authorization: Bearer` header **or** from `req.cookies?.portalToken` (lines 591–598). If a valid portal session is found via the cookie path, the endpoint skips the tracking-token requirement and the 3-per-minute rate limit, and writes a customer message without any CSRF check. The path is in `NO_ORIGIN_ALLOWED_PATHS` (`/api/v1/track` at `index.ts:1024`), so the production Origin guard is bypassed too.

**Code:**
```typescript
// tracking.routes.ts:589–598
function extractPortalSessionToken(req: Request): string | undefined {
  const authHeader = req.headers.authorization;
  if (authHeader && typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
    const headerToken = authHeader.slice(7).trim();
    if (headerToken) return headerToken;
  }
  const cookies = (req as Request & { cookies?: Record<string, string> }).cookies;
  if (cookies && typeof cookies.portalToken === 'string' && cookies.portalToken.length > 0) {
    return cookies.portalToken; // ← cookie fallback, no CSRF guard on the route
  }
  return undefined;
}
```

**Exploit:**
Currently not exploitable because `portalToken` is stored in `sessionStorage` by the official web client, not as a browser cookie. However, if any future client (mobile app webview, electron wrapper, or SSR change) begins storing `portalToken` as a cookie, an attacker page could `fetch('/api/v1/track/portal/T-0001/message', { method:'POST', credentials:'include', body: JSON.stringify({content:'spam'}) })` and forge messages from an authenticated portal customer without knowing their token.

**Fix:**
Either (a) remove the cookie fallback from `extractPortalSessionToken` so only the `Authorization: Bearer` path is accepted (eliminating the CSRF surface entirely), or (b) add `requireCsrfToken` as middleware on this route, consistent with the `POST /portal/:id/comments` pattern in `portal.routes.ts:1221`.

---

### [INFO] `voiceInstructionsHandler` (GET) has no authentication and leaks store phone number

**Where:** `packages/server/src/routes/voice.routes.ts:694–720` and `packages/server/src/index.ts:1562`

**What:**
`GET /api/v1/voice/instructions/:action` is mounted with only `webhookRateLimit` middleware (60 req/min per IP). There is no authentication and no signature check. The handler reads `store_phone` from `store_config` and embeds it in the returned TwiML/NCCO/BXML response. Any unauthenticated caller can enumerate the store phone number by hitting this endpoint, and can observe what provider-specific call instructions are generated for any `to` phone number. The `to` parameter is escaped via `escapeXml` so TwiML injection is prevented, but the response reveals the store's internal telephony configuration.

**Code:**
```typescript
// voice.routes.ts:694–698,712
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';
  // ...
  const instructions = provider.generateCallInstructions(action, { to, from: storePhone, announceRecording });
  // storePhone included in TwiML response body — readable by any caller
```

**Exploit:**
An external attacker can call `GET /api/v1/voice/instructions/connect?to=+1555...` to discover the store phone number and confirm the telephony provider in use, aiding targeted social engineering or provider-specific attacks. Not a direct CSRF or code-execution risk; this is an information disclosure.

**Fix:**
Add `authMiddleware` to the `voiceInstructionsHandler` mount in `index.ts:1562`, or add a shared secret/HMAC check (similar to the recording signed-URL pattern at `voice.routes.ts:256–281`) so only the telephony provider can call this endpoint. The Twilio webhook URL for `<Record>` and `<Dial>` callbacks can use the same HMAC pattern.

---

### [INFO] `http://localhost` is unconditionally in the CORS allow-list including production

**Where:** `packages/server/src/index.ts:1003–1004`

**What:**
`rawAllowedOrigins` always includes `https://localhost:${config.port}` and `http://localhost:${config.port}`, regardless of `NODE_ENV`. After `normalizeOrigin`, these become `https://localhost` and `http://localhost` (when the port is the default port), which are always in `allowedOrigins`. In production, a page served from `http://localhost` on the victim's own machine can make credentialed cross-origin requests to the API. LAN IPs (10/8, 172.16/12, etc.) are correctly DEV-only (`index.ts:1069–1073`), but localhost is not similarly guarded.

**Code:**
```typescript
// index.ts:1002–1007
const rawAllowedOrigins = [
  `https://localhost:${config.port}`,
  `http://localhost:${config.port}`,  // ← always included, even in production
  ...(process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean) || []),
];
```

**Exploit:**
An attacker who can serve content from `http://localhost` on the victim's machine (e.g., via a local software install or malware) can make credentialed API requests to the CRM backend. The attack requires local code execution and the `refreshToken` cookie is `SameSite=Strict`, so the blast radius is limited to endpoints that use the `portalCsrfToken` cookie (which is `SameSite=Strict`) or `Authorization: Bearer`. In practice the real CSRF protections (SameSite=Strict + CSRF token) mitigate this, but the allowlist entry is unnecessary in production.

**Fix:**
Guard the localhost entries with `config.nodeEnv !== 'production'`: remove `https://localhost:${config.port}` and `http://localhost:${config.port}` from `rawAllowedOrigins` in production, or add them conditionally (`if (config.nodeEnv !== 'production')`). Operators who legitimately run the CRM on localhost in production can add it to `ALLOWED_ORIGINS`.

---

### Verified clean in Pass 2 (items not in Pass 1 scope)

- **Stripe webhook body-parser ordering**: `express.raw()` at `index.ts:1212` is before `express.json()` at `index.ts:1228`. Body-parser skips re-parsing (via `req._body` flag) so no double-parse. Correct.
- **SMS/voice rawBody for Telnyx/Vonage**: Both providers use `req.rawBody` captured by the global `express.json` `verify` callback. Both fail-closed (`return false`) when `rawBody` is absent — no silent bypass.
- **Console SMS provider in production**: `ConsoleProvider` lacks `verifyWebhookSignature` so all inbound webhook requests pass through. Impact is contained because `ConsoleProvider.parseInboundWebhook` returns `null` (no message stored). Still, a production operator using the console provider (possible: it is the default fallback) accepts all forged webhook POSTs without error, confirming the Pass 1 [LOW] finding.
- **Content-type guard `webhook`/`setup` bypass**: Only paths whose `req.path` literally contains 'webhook' or '/setup' bypass the CT guard. Express `req.path` is the path only (no query string), so `?webhook=1` does not trigger the bypass. All webhook endpoints are pre-registered and correct.
- **Token not in URLs or logs**: CSRF tokens are returned in JSON response bodies and cookies only; never in query strings, `Location` headers, or log lines.
- **GET endpoints mutating state**: `GET /portal/verify` updates `last_used_at` (acceptable side-effect on a read); no portal or enrich GET creates financial records or user-visible mutations.
- **`portalToken` never set as a server-side cookie**: Confirmed by exhaustive `grep` — `res.cookie('portalToken', ...)` does not exist in any route file. The `clearCookie('portalToken')` at `portal.routes.ts:145` is defensive cleanup. Cookie-fallback path in `portalAuth` is dead code under the current web client.
- **Cookie SameSite/Secure audit**: All server-issued cookies (`refreshToken`, `csrf_token`, `deviceTrust`, `portalCsrfToken`) are `SameSite=Strict`; `Secure` flag is `true` in production for all of them. No `SameSite=None` or missing `SameSite`.
- **CORS reflect-origin**: `cors()` uses an explicit allowlist checked by `isCorsOriginAllowed()`; it never echoes arbitrary origins. `credentials: true` is safe because the reflected origin is always from the allowlist, never `*`.
- **Double-submit constant-time comparison**: `safeEquals()` in `csrf.ts:52–60` uses `crypto.timingSafeEqual` with a length check. Empty strings are caught by the `if (!cookieToken || !headerToken)` guard before reaching `safeEquals`. No timing oracle.

---

**Updated Summary**: Pass 1 MEDIUM re-classified to LOW (latent risk — portalToken is sessionStorage not cookie). 2 new INFO findings (voiceInstructions no auth, localhost in prod CORS). 1 new LOW (tracking message route latent CSRF). Confirmed: 5 low/info-level issues total, 0 critical/high. No new MEDIUM or above.
