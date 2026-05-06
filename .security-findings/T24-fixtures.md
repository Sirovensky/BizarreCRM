# T24 — Test Fixtures / Sample Data / Seed Data

## Scope
- `packages/server/src/services/sampleData.ts`
- `packages/server/src/db/seed.ts`
- `packages/server/src/db/device-models-seed.ts` + `device-models-seed-runner.ts`
- `packages/server/src/scripts/full-import.ts`, `reimport-notes.ts`, `reset-database.ts`
- `packages/server/src/__tests__/repairPricing.dpi.test.ts`
- `packages/server/src/__tests__/setupWizard.gate.test.ts`
- `packages/server/src/db/migrations/011_repair_conditions_categories.sql` (and all migrations)
- `.env.example`
- `README.md`, `scripts/README.md`

---

### HIGH — Default `admin/admin123` credentials publicly documented and used as script fallback

**Where:** `packages/server/src/scripts/full-import.ts:33`, `README.md:56-57`, `scripts/README.md:48`, `.env.example:183`

**What:**
`full-import.ts` falls back to `username: 'admin', password: 'admin123'` when `ADMIN_USERNAME`/`ADMIN_PASSWORD` env vars are absent. The README and `scripts/README.md` both openly publish these credentials as the stated defaults. A developer who clones the repo, runs the setup wizard, picks `admin` as username, and uses `admin123` as the setup password (guided by the README) has a live instance with documented credentials. The `index.ts:603` startup check only blocks this in `NODE_ENV=production` — in development it only warns. The `full-import.ts` script is designed to run against a live server ("Server must be running"), so if that server is accessible (e.g. exposed via ngrok during testing), any attacker who reads the README can authenticate.

**Code:**
```typescript
// full-import.ts:29-36
async function login(): Promise<string> {
  const resp = await fetch(`${SERVER_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: process.env.ADMIN_USERNAME || 'admin',
      password: process.env.ADMIN_PASSWORD || 'admin123'
    }),
  });
```

**Exploit:**
Attacker reads README (public repo), sees `admin`/`admin123` defaults, hits `/api/v1/auth/login` on any dev/staging server running with default credentials, obtains a JWT, and has full admin access. The `index.ts` production block doesn't protect dev/staging.

**Fix:**
Remove the hardcoded fallbacks from `full-import.ts` — require `ADMIN_USERNAME` and `ADMIN_PASSWORD` env vars explicitly and fail with a clear message if absent. Redact `admin123` from README and `scripts/README.md`; replace with instructions to run `POST /setup` and choose a strong password. Add an INSECURE_SECRETS check in the startup path that also applies in `NODE_ENV=development` (just with `warn` severity).

---

### MEDIUM — Default PIN `1234` seeded for every new user; PIN_NOT_SET gate only covers switch-user, not all PIN paths

**Where:** `packages/server/src/services/tenant-provisioning.ts:347`, `packages/server/src/routes/auth.routes.ts:643`, `packages/server/src/db/migrations/101_pin_set_flag.sql`

**What:**
Every new admin user is seeded with `bcrypt('1234')` as their PIN and `pin_set=0` (the DB default). The PROD12 gate (`auth.routes.ts:1471`) refuses `POST /auth/switch-user` when `pin_set === 0`, which forces the user to set a real PIN before using the switch-user flow. However, no equivalent gate exists on `POST /auth/change-pin` (setting the PIN the first time) or anywhere a staff member could use the default PIN `1234` before they've changed it. Additionally, the setup wizard path in `auth.routes.ts:643` also seeds `1234` for the initial admin's PIN with `pin_set` defaulting to 0 — so the initial admin's PIN is known until they explicitly change it.

**Code:**
```typescript
// tenant-provisioning.ts:347-358
const defaultPin = await bcrypt.hash('1234', 12);
tenantDb.prepare(`
  INSERT INTO users (username, email, password_hash, password_set, first_name, last_name, role, pin, is_active)
  VALUES (?, ?, ?, 1, ?, ?, 'admin', ?, 1)
`).run(
  opts.adminEmail.split('@')[0],
  opts.adminEmail,
  passwordHash,
  opts.adminFirstName || 'Admin',
  opts.adminLastName || '',
  defaultPin,  // always '1234'
);
```

**Exploit:**
An attacker with a credential for one user account can attempt `POST /auth/switch-user` on a newly-provisioned tenant before the admin has changed their PIN, or on any staff account whose PIN was never changed. The switch-user flow gives access to any active user account, bypassing that user's individual password.

**Fix:**
The existing PROD12 gate on switch-user is correct. Extend the same `pin_set === 0` check to the POS quick-PIN login path and any other PIN-accepting endpoint. Consider surfacing a forced PIN-change prompt in the setup wizard UI alongside the password-change step. Do not seed with `1234` — instead, seed with `null` and require the user to set a PIN on first use.

---

### MEDIUM — `.env.example` has uncommented live-format Stripe key placeholders

**Where:** `.env.example:91-93`

**What:**
The `.env.example` contains three uncommented assignments for Stripe credentials:
```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRO_PRICE_ID=price_...
```
These are not commented out like the other optional vars. A developer copy-pasting `.env.example` to `.env` (common practice) will have these three lines active with placeholder values. When `config.ts` reads these, `STRIPE_SECRET_KEY` becomes `sk_test_...` — not empty — so `config.stripeEnabled` is set to `true` (it checks `STRIPE_SECRET_KEY && STRIPE_WEBHOOK_SECRET && STRIPE_PRO_PRICE_ID`, all of which are truthy). This causes the Stripe billing subsystem to load and potentially attempt real API calls using the malformed placeholder value as a secret key.

**Code:**
```bash
# .env.example:91-93
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRO_PRICE_ID=price_...
```

**Exploit:**
Low-severity on its own — the placeholder key will be rejected by Stripe APIs. But it creates a false config state: the server believes Stripe is enabled and routes billing traffic accordingly. If an operator replaces only one of the three values with a real key (e.g. their real `sk_test_` key) and leaves the others as placeholder, the webhook verification will fail silently using `whsec_...` as the secret, meaning legitimate Stripe webhook events will be rejected and the platform won't record subscription payments.

**Fix:**
Comment out all three Stripe env vars in `.env.example` so they follow the same pattern as the other optional vars. Add a startup warning (not fatal) when `STRIPE_SECRET_KEY` looks like a placeholder value (`sk_test_...` or `sk_live_...` verbatim without additional chars).

---

### LOW — `full-import.ts` script fallback `SERVER_URL=http://localhost:443` defaults to cleartext HTTP

**Where:** `packages/server/src/scripts/full-import.ts:27`

**What:**
The `SERVER_URL` default is `'http://localhost:443'` — HTTP not HTTPS. The server always starts with TLS certs and refuses HTTP. If a developer runs this script without setting `SERVER_URL`, the login request goes to `http://localhost:443` which will fail (the server serves HTTPS on 443). However, the error message will be opaque. More critically, the pattern teaches bad habits: future forks or CI jobs may set `SERVER_URL` to an http:// staging URL, sending the admin credential in cleartext.

**Code:**
```typescript
// full-import.ts:27
const SERVER_URL = process.env.SERVER_URL || 'http://localhost:443';
```

**Exploit:**
Low exploitation risk since the server rejects HTTP. Risk is latent: an operator who sets up an HTTP-accessible staging instance for import work sends `admin`/`admin123` (or their real admin password) in cleartext over the network. Combined with the default credential exposure (HIGH above), this creates a compound attack surface.

**Fix:**
Change default to `'https://localhost:443'`. Add a startup check: if `SERVER_URL.startsWith('http://')` and `NODE_ENV` is not `development`, log a warning.

---

### INFO — Sample data uses `example.com` emails and 555-01xx phones (safe, no GDPR/SMS risk)

**Where:** `packages/server/src/services/sampleData.ts:83-89`

**What:**
Sample customers use `@example.com` addresses (RFC 2606 reserved, non-deliverable) and `3035550101-3035550105` phone numbers (555-01xx block, per the comment at line 80, reserved for fictional use in telephony). `email_opt_in=0` and `sms_opt_in=0` are set at INSERT time (line 176). The SMS notification path (notifications.ts:403-405) correctly evaluates `sms_opt_in === 0` as opted-out. The dunning scheduler (dunningScheduler.ts:685-686) also respects `sms_opt_in !== 0` as a hard gate. No real PII is embedded. Migrations 162 and 163 (mentioned in audit brief) do not exist in this branch.

**Exploit:**
No exploitable issue. Sample data is correctly sandboxed.

**Fix:**
No change required. Consider adding an explicit `source = 'sample_data'` WHERE-clause filter to the dunning eligibility query as defense-in-depth (it currently relies only on the opt-in flags).

---

### INFO — Test fixtures (repairPricing.dpi.test.ts, setupWizard.gate.test.ts) are clean — no live credentials or real PII

**Where:** `packages/server/src/__tests__/repairPricing.dpi.test.ts`, `packages/server/src/__tests__/setupWizard.gate.test.ts`

**What:**
Both test files use in-memory SQLite (`:memory:`), generic fixture data (`Apple`, `iPhone 13`, `mobilesentrix` as supplier source name), and no API keys, no real email addresses, no phone numbers, no tokens. The `setupWizard.gate.test.ts` file uses `127.0.0.1` as the mock IP. No hardcoded credentials. The ALLOWED_CONFIG_KEYS set in the inline test handler correctly mirrors the real production allowlist.

**Exploit:**
No exploitable issue.

**Fix:**
No change needed.

---

### INFO — `admin123` startup check only runs in single-tenant mode (multi-tenant provisioning uses user-supplied password)

**Where:** `packages/server/src/index.ts:599-617`

**What:**
The `admin123` startup-block (lines 601-614) queries `users WHERE username = 'admin'` — only meaningful in single-tenant mode where the setup wizard creates a user named `admin`. In multi-tenant mode, the admin username is derived from the email prefix (`opts.adminEmail.split('@')[0]`) and can be any string. The multi-tenant provisioning path never seeds `admin123`; it uses the caller-supplied `opts.adminPassword`. This is correct by design but the startup check is invisible to multi-tenant deployments where a careless operator set their own shop's admin password to `admin123` during signup.

**Exploit:**
Low risk — multi-tenant signups require the password at `POST /api/v1/signup` with a 8–128 char validation, and a captcha. But `admin123` passes the 8-char minimum.

**Fix:**
Consider adding a background check at tenant provision time (and on first login) that warns the operator if their password bcrypt-matches `admin123` or other common passwords from a short blocklist. The `zxcvbn` library or a short static blocklist would suffice.

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 1 |
| MEDIUM | 2 |
| LOW | 1 |
| INFO | 3 |

**Most impactful finding:** HIGH — default `admin/admin123` credentials are publicly documented in the README and used as the fallback in `full-import.ts`, enabling trivial authentication against any dev/staging server that followed the README setup guide. The startup block in `index.ts` only hard-fails this in `NODE_ENV=production`, leaving dev and staging instances exposed.

Migrations 162 and 163 referenced in the audit brief do not exist in this branch (latest migration is 154). No real customer emails, real phone numbers, SMTP credentials, or live API keys were found in any seed file, migration, or test fixture.
