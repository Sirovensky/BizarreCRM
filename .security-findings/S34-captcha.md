# S34 — hCaptcha / reCAPTCHA Integration Findings

Scope: `packages/server/src/utils/hcaptcha.ts`, `packages/server/src/routes/signup.routes.ts`, `packages/server/src/routes/auth.routes.ts`, `packages/server/src/routes/bookingPublic.routes.ts`, `packages/server/src/routes/leads.routes.ts`
Reviewed: 2026-05-05

---

### [HIGH] `skipEmailVerification = true` hardcoded — email ownership never verified in any environment including production

**Where:** `packages/server/src/routes/signup.routes.ts:618`

**What:**
The constant `skipEmailVerification` is hardcoded to `true` (line 618) with no environment-variable guard. The comment at line 614 shows the intended expression was `process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production'`, but SMTP issues caused a blanket disable. As a result, in every environment — including production multi-tenant with `NODE_ENV=production` — POST /signup immediately calls `provisionTenant()` without ever sending or verifying a link. Any email address (including addresses the attacker does not own) can be used to register a tenant. The response body still says "dev mode — email verification bypassed" even in production.

**Code:**
```typescript
// TEMP-NO-EMAIL-VERIF (2026-04-24): email verification fully disabled
// …restore the SEC-H94 / BH-0002 gate by flipping the constant back…
//   const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';
// While this is `true`, /signup provisions tenants synchronously without
// proving control of the email
const skipEmailVerification = true;
if (skipEmailVerification) {
    logger.warn('signup: TEMP-NO-EMAIL-VERIF — email verification disabled', ...);
    const result = await provisionTenant({ … });
```

**Exploit:**
An attacker with a valid hCaptcha token submits `POST /signup` with `admin_email=victim@company.com`. Without email verification a real tenant is immediately provisioned under the victim's email address, the attacker receives authentication tokens in the 201 response, and the victim gets no notification. This enables brand-squatting and creates orphaned tenants under uncontrolled email addresses at scale.

**Fix:**
Restore the conditional: `const skipEmailVerification = process.env.SKIP_EMAIL_VERIFICATION === '1' && config.nodeEnv !== 'production';`. Once SMTP is healthy, remove the env-var escape hatch entirely so this path requires email verification unconditionally. Add a production boot-time fatal if `SKIP_EMAIL_VERIFICATION=1` and `NODE_ENV=production` co-exist.

---

### [MEDIUM] Captcha hostname not asserted — tokens solved on any registered hCaptcha site are accepted

**Where:** `packages/server/src/utils/hcaptcha.ts:104–107` and `packages/server/src/routes/signup.routes.ts:336–337`

**What:**
Both captcha verifiers parse `result.hostname` from the hCaptcha `/siteverify` response but only log it; they never compare it against the expected domain (e.g., `config.baseDomain`). The hCaptcha API returns `hostname` to identify which site the token was generated on. Without asserting this field, a token solved on any other hCaptcha-enabled property — including a site controlled by the attacker — can be replayed against the signup or login endpoint, provided the attacker holds a valid secret/sitekey pair recognised by hCaptcha's backend.

**Code:**
```typescript
// hcaptcha.ts:104-114
const result = await response.json() as HCaptchaApiResponse;
if (result.success === true) {
  return { ok: true };  // hostname never checked
}
logger.warn('hCaptcha verification rejected token', {
  remoteIp,
  hostname: result.hostname,  // logged only
  errors: result['error-codes'] ?? [],
});
```

**Exploit:**
An attacker registers their own domain with the same hCaptcha account or obtains a token from a low-security hCaptcha integration, then uses that token (still within its validity window) against `POST /signup`. The server accepts it because `result.success === true` without verifying `result.hostname === config.baseDomain`.

**Fix:**
After a successful `result.success === true`, assert `result.hostname === config.baseDomain` (or a configured allowlist). Return `{ ok: false, reason: 'Captcha hostname mismatch' }` if the check fails. Expose `config.hCaptchaHostname` to make the expected domain independently configurable from `baseDomain`.

---

### [MEDIUM] Captcha token transmitted in GET query string for `/check-slug` — logged in access logs and CDN caches

**Where:** `packages/server/src/routes/signup.routes.ts:963`

**What:**
The `/check-slug/:slug` endpoint accepts the hCaptcha response token via the `?captcha=<token>` query parameter on a GET request. Bearer tokens in URLs are captured verbatim by every layer in the request path: server access logs, reverse proxy logs, CDN edge logs, browser history, and `Referer` headers on subsequent navigations. A replayed token (before hCaptcha marks it consumed) could be extracted from logs and submitted against a more sensitive endpoint. Additionally, the short validity window (~2 minutes) means an adversary with log access has a brief but real replay window.

**Code:**
```typescript
// signup.routes.ts:963
const captchaToken = req.query.captcha;   // token in URL query string
const captchaResult = await verifyCaptchaToken(captchaToken, ip);
```

**Exploit:**
Server access logs contain entries like `GET /api/v1/signup/check-slug/myshop?captcha=P1_ey...`. An attacker with read access to the web server logs (common in shared hosting, misconfigured S3 log buckets, or insider threat) extracts the token and replays it against `POST /signup` before hCaptcha's server-side consumption marks it used.

**Fix:**
Change `/check-slug` to accept POST with the captcha token in the JSON body, or pass the token via a custom request header (e.g., `X-Captcha-Token`). Neither headers nor POST bodies appear in standard access-log formats.

---

### [LOW] Forgot-password captcha gate is unreachable dead code — rate-limit threshold (3) is lower than captcha threshold (5)

**Where:** `packages/server/src/routes/auth.routes.ts:1651` and `1665–1676`

**What:**
`POST /forgot-password` applies a hard rate-limit of 3 attempts per hour per IP (`checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)` at line 1651). The captcha gate fires when `countRateLimitAttempts(db, 'forgot_password', ip) >= CAPTCHA_FAILURE_THRESHOLD` where `CAPTCHA_FAILURE_THRESHOLD = 5`. Because `checkWindowRate` blocks (returns 429) once the count reaches 3, the count can never reach 5 during an active window — the captcha block at line 1666 is therefore never executed. The intent was to add friction before the hard block, but the threshold ordering inverts the desired behavior.

**Code:**
```typescript
// Blocks at count >= 3:
if (!checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)) {
  res.status(429).json({ ... }); return;
}
// Dead code — count is always < 3 when this line executes:
const forgotAttempts = countRateLimitAttempts(db, 'forgot_password', ip);
if (forgotAttempts >= CAPTCHA_FAILURE_THRESHOLD) {  // CAPTCHA_FAILURE_THRESHOLD = 5
  const captchaResult = await verifyHcaptcha(req.body?.captcha_token, ip);
  ...
}
```

**Exploit:**
The captcha gate provides zero additional protection for forgot-password. An attacker making 3 probes per hour hits the hard 429 immediately without ever solving a captcha. The intended captcha burden (solving between attempts 3–5) is entirely absent.

**Fix:**
Either lower `CAPTCHA_FAILURE_THRESHOLD` to 2 (requiring captcha on the 3rd attempt) or raise the hard rate-limit to 6+ so the captcha gate at 5 becomes reachable. The most useful configuration: captcha after N failures, hard block after M > N failures — e.g., captcha at 2, hard block at 5.

---

### [LOW] Duplicate captcha implementation in `signup.routes.ts` diverges from shared `hcaptcha.ts`

**Where:** `packages/server/src/routes/signup.routes.ts:253–366` and `packages/server/src/utils/hcaptcha.ts:55–122`

**What:**
`signup.routes.ts` contains a full standalone `verifyCaptchaToken()` function (lines 263–366) that duplicates the hCaptcha verification logic of the shared `verifyHcaptcha()` in `hcaptcha.ts`. The two implementations have already diverged: the local function has an additional `SIGNUP_CAPTCHA_REQUIRED` opt-out branch (lines 282–289) that the shared utility lacks. Any future fix applied to `hcaptcha.ts` (e.g., hostname assertion) must be manually mirrored to the local copy or it will silently not apply to signup. The comment in `hcaptcha.ts` even names this risk ("SEC-H94 agent may also generate this file. Last writer wins").

**Code:**
```typescript
// signup.routes.ts:263 — fully duplicated function
async function verifyCaptchaToken(token: unknown, ip: string): Promise<{ ok: boolean; reason?: string }> { … }

// hcaptcha.ts:55 — shared utility
export async function verifyHcaptcha(token: unknown, remoteIp: string): Promise<HCaptchaResult> { … }
```

**Exploit:**
When hostname assertion or replay-prevention logic is added to `hcaptcha.ts`, the identical gap in `verifyCaptchaToken` means signup remains unprotected. A security review that patches only the shared helper misses the local copy.

**Fix:**
Delete `verifyCaptchaToken` from `signup.routes.ts` and replace all three call sites (POST /signup, GET /check-slug) with the shared `verifyHcaptcha()` from `hcaptcha.ts`. Port the `signupCaptchaRequired` opt-out logic into `verifyHcaptcha` as a named option parameter so the shared function handles all captcha verification across the codebase.

---

### [LOW] In-memory pending-signup map stores admin password in plaintext

**Where:** `packages/server/src/routes/signup.routes.ts:104–114`

**What:**
The `pendingSignups` Map (used in the production email-verification path, currently bypassed by `TEMP-NO-EMAIL-VERIF`) stores the raw `adminPassword` string in plaintext for up to 1 hour (the `PENDING_SIGNUP_TTL_MS` window). If the process heap is dumped (core dump, `process.memoryUsage` endpoint, or a memory-leak diagnostic tool), the plaintext passwords of all pending signups are recoverable. The `logger.info` call at line 673 also logs the `tokenPrefix` to the logging system, which keeps those tokens alive in log aggregators longer than intended.

**Code:**
```typescript
const pendingSignups = new Map<string, {
  slug: string; shopName: string; adminEmail: string;
  adminPassword: string;   // plaintext for up to PENDING_SIGNUP_TTL_MS = 1h
  …
}>();
```

**Exploit:**
An attacker who obtains a heap dump or can trigger a process crash with core dump recovers all pending admin passwords. Combined with the tenant `adminEmail`, they have full admin credentials for accounts that have not yet been activated.

**Fix:**
Bcrypt-hash `adminPassword` before storing it in `pendingSignups` (12 rounds to match production), then pass the hash to `provisionTenant` after removing the plain-text hash step there. Alternatively, require the user to re-enter the password at the /verify step and never store it in-memory.

---

### [INFO] `dev-captcha-token` bypass string is a well-known constant across the codebase

**Where:** `packages/server/src/utils/hcaptcha.ts:63` and `packages/server/src/routes/signup.routes.ts:268`

**What:**
Both captcha verifiers accept the literal string `'dev-captcha-token'` as a bypass when `NODE_ENV !== 'production'`. This string is hardcoded in the source and visible in any Git clone or code review. If a staging or CI environment runs with `NODE_ENV` set to anything other than `'production'` (e.g., `'staging'`, `'test'`, `'qa'`), the bypass is active and any request with `captcha_token: "dev-captcha-token"` skips captcha verification entirely. The guard relies on the operator setting exactly `NODE_ENV=production` for every non-local deployment.

**Code:**
```typescript
// hcaptcha.ts:63
if (!isProd && responseToken === 'dev-captcha-token') {
  return { ok: true };
}
```

**Fix:**
Add a separate `CAPTCHA_DEV_TOKEN` environment variable (defaulting to a random value at startup) rather than a hardcoded string. Alternatively, gate the bypass additionally on `HCAPTCHA_ENABLED !== 'true'` so it can never fire in any deployment that has `HCAPTCHA_SECRET` set, regardless of `NODE_ENV`.

---

### [INFO] No captcha on public booking GET endpoints — acceptable, but future POST submission route needs it

**Where:** `packages/server/src/routes/bookingPublic.routes.ts`

**What:**
The public booking router (`/public/api/v1/booking`) currently exposes only GET /config (60 req/IP/hr) and GET /availability (120 req/IP/hr). Both are read-only and IP rate-limited; no captcha is applied. There is no POST endpoint for submitting a booking request in this file. Leads (`leads.routes.ts`) are internal-only (authenticated via `authMiddleware`). The current surface is acceptable. However, the comment at `portal.routes.ts:720–723` explicitly notes `SEC-M21-captcha` (CAPTCHA on portal send-code) as a pending TODO — if a public booking-submission POST is added in the future, it will need captcha from the start.

**Fix:**
Track the future booking-submission endpoint in the backlog with a `CAPTCHA_REQUIRED` annotation. When implementing it, wire `verifyHcaptcha()` before any write operation (appointment creation, lead creation, or customer lookup).

---
