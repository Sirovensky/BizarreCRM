# S32 — Configuration Encryption Audit

## Scope

- `packages/server/src/utils/configEncryption.ts`
- All callers of `encryptConfigValue` / `decryptConfigValue` / `getConfigValue` / `setConfigValue`
- TOTP encrypt/decrypt in `auth.routes.ts`, `settings.routes.ts`, `super-admin.routes.ts`, `middleware/stepUpTotp.ts`
- Settings routes: `settings.routes.ts`, `settingsExport.routes.ts`
- Services: `blockchyp.ts`, `email.ts`, `webhooks.ts`
- Migrations: `019_totp_2fa.sql`; master schema in `db/master-connection.ts`

---

### [CRITICAL] Wrong column names in super-admin step-up TOTP middleware crashes 7 protected endpoints

**Where:** `packages/server/src/middleware/stepUpTotp.ts:362`

**What:**
`requireStepUpTotpSuperAdmin` issues `SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ?` (line 362), but the `super_admins` schema (defined in `db/master-connection.ts:70-72`) uses `totp_secret_enc`, `totp_secret_iv`, `totp_secret_tag`. `better-sqlite3` calls `.prepare()` eagerly: selecting non-existent columns throws `no such column: totp_secret` synchronously. Because the async middleware has no try/catch, this propagates as an unhandled rejected promise → 500 for every request hitting these endpoints.

**Code:**
```typescript
// middleware/stepUpTotp.ts:361-364 — wrong column names
const dbAdmin = masterDb
  .prepare('SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ? AND is_active = 1')
  .get(superAdmin.superAdminId) as
  | { id: number; email: string | null; totp_secret: string | null; totp_iv: string | null; totp_tag: string | null }
  | undefined;

// db/master-connection.ts:70-72 — actual schema
totp_secret_enc TEXT,
totp_secret_iv  TEXT,
totp_secret_tag TEXT,
```

**Exploit:**
All 7 endpoints guarded by `requireStepUpTotpSuperAdmin` — `/rotate-jwt-secret`, `/tenants/:slug` (PUT/suspend/repair/activate/DELETE), `/force-disable-2fa` — return HTTP 500 to any caller, making them permanently inaccessible in production. A service operator cannot suspend a compromised tenant, delete a tenant, or rotate the JWT secret via the API; disaster-recovery operations require direct DB access.

**Fix:**
Change the SELECT in `stepUpTotp.ts:362` to `SELECT id, email, totp_secret_enc, totp_secret_iv, totp_secret_tag FROM super_admins ...` and update the TypeScript cast and references at lines 364 and 373/409 accordingly. Match `super-admin.routes.ts:475-478` which already uses the correct names.

---

### [HIGH] TOTP v3 key missing in settings.routes.ts — admin TOTP step-up silently blocked

**Where:** `packages/server/src/routes/settings.routes.ts:50-70` and `packages/server/src/routes/auth.routes.ts:112-124`

**What:**
`auth.routes.ts` (the canonical TOTP encrypt path) was upgraded to key version 3 (HKDF-derived via `hkdfKey([jwtSecret, superAdminSecret], 'bizarre-totp-salt-v3', 'totp-key-v3')`). All newly enrolled or re-enrolled TOTP secrets are now written as `v3:iv:tag:data`. However, `settings.routes.ts` maintains a separate `TOTP_DECRYPT_KEYS` map at lines 50-53 that only defines keys 1 and 2 — v3 is absent. When a TOTP secret with prefix `v3` reaches `decryptTotpSecret`, line 66 (`TOTP_DECRYPT_KEYS[3]`) returns `undefined` and line 67 throws `Error('Unknown encryption key version: 3')`.

**Code:**
```typescript
// settings.routes.ts:50-53 — v3 key is missing
const TOTP_DECRYPT_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':totp:v1').digest(),
  2: crypto.createHash('sha256').update(config.jwtSecret + ':totp-encryption:v2:' + config.superAdminSecret).digest(),
  // v3 absent
};

// settings.routes.ts:1136-1141 — error caught, totpValid stays false
try {
  const secret = decryptTotpSecret(caller.totp_secret); // throws for v3
  totpValid = Boolean(verifySync({ token: admin_totp_code, secret }));
} catch (err) {
  logger.error('TOTP verification failed during sensitive user update', { err, targetUserId });
  totpValid = false; // always false for v3 secrets
}
```

**Exploit:**
An authenticated admin whose TOTP secret is v3-encrypted (any account enrolled/re-enrolled after the v3 migration in `auth.routes.ts`) can never pass the `admin_totp_code` step-up check in `PUT /settings/users/:id`. Sensitive user-record mutations (password changes, role promotion, 2FA reset) are permanently blocked for those admins, even with a correct 6-digit code. An attacker who knows this can prevent legitimate admins from locking a compromised user account.

**Fix:**
Add the v3 key derivation to `settings.routes.ts`'s `TOTP_DECRYPT_KEYS` map, using the same `hkdfKey` helper as `auth.routes.ts`. Better long-term: extract the TOTP key table and `decryptSecret` function into a shared `utils/totpEncryption.ts` module so there is exactly one definition.

---

### [MEDIUM] S3 backup credentials stored in plaintext — missing from ENCRYPTED_CONFIG_KEYS

**Where:** `packages/server/src/utils/configEncryption.ts:35-46` and `packages/server/src/routes/settings.routes.ts:308,323`

**What:**
`backup_s3_access_key` and `backup_s3_secret_key` are listed in `SENSITIVE_CONFIG_KEYS` (hidden from non-admins on GET `/config`) and in `ALLOWED_CONFIG_KEYS`, but they are **not** in `ENCRYPTED_CONFIG_KEYS`. The store-write path at `settings.routes.ts:519` checks `ENCRYPTED_CONFIG_KEYS.has(key)` before encrypting — these two keys fail that check and are written as UTF-8 plaintext in the tenant SQLite DB. Any tenant DB exposure (file-system leak, SQLite dump, backup theft before encryption) reveals cloud storage credentials in cleartext.

**Code:**
```typescript
// configEncryption.ts:35-46 — S3 keys absent
export const ENCRYPTED_CONFIG_KEYS = new Set([
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'smtp_pass', 'tcx_password',
  // 'backup_s3_access_key', 'backup_s3_secret_key' ← MISSING
]);
```

**Exploit:**
If an attacker exfiltrates a tenant's SQLite file (e.g., through a path-traversal or a misrouted backup), `backup_s3_access_key` and `backup_s3_secret_key` are immediately readable; the attacker can access the tenant's S3 bucket, exfiltrate or destroy all backup archives, and pivot to any other services sharing those AWS credentials.

**Fix:**
Add `'backup_s3_access_key'` and `'backup_s3_secret_key'` to `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. Read sites that currently call `getConfigValue(db, 'backup_s3_access_key')` will auto-decrypt; read sites that query raw SQL must be updated to call `decryptConfigValue` on the value.

---

### [MEDIUM] webhook_secret stored plaintext despite claim of configEncryption

**Where:** `packages/server/src/services/webhooks.ts:248-267`

**What:**
The file's JSDoc (line 8) states the `webhook_secret` is "stored encrypted via configEncryption," but the implementation in `getOrCreateWebhookSecret` issues bare `INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)` and `SELECT value FROM store_config WHERE key = 'webhook_secret'` with no call to `encryptConfigValue` or `decryptConfigValue`. The `webhook_secret` key is also absent from `ENCRYPTED_CONFIG_KEYS`. The secret is thus stored as 64 hex characters of plaintext.

**Code:**
```typescript
// webhooks.ts:259-266 — no encryption
const candidate = crypto.randomBytes(32).toString('hex');
db.prepare(
  "INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)"
).run(candidate);       // ← plain hex, not encryptConfigValue(candidate)
const row = db
  .prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'")
  .get() as { value?: string } | undefined;
return row?.value || candidate;  // ← plain hex returned directly
```

**Exploit:**
An attacker who reads the tenant DB (SQLite file exfil, backup, or SQLi that can dump `store_config`) gets the HMAC-SHA256 signing key for all outbound webhooks. They can forge valid webhook POST bodies that any integrated third-party endpoint will accept as genuine BizarreCRM events.

**Fix:**
Wrap `candidate` in `encryptConfigValue(candidate)` on write and `decryptConfigValue(row.value)` on read. Add `'webhook_secret'` to `ENCRYPTED_CONFIG_KEYS` so the standard `getConfigValue` / `setConfigValue` helpers handle it automatically.

---

### [MEDIUM] PUT /store response leaks raw ciphertext for encrypted config keys

**Where:** `packages/server/src/routes/settings.routes.ts:594-597`

**What:**
`PUT /store` writes encrypted values to the DB correctly (line 582 encrypts if key is in `ENCRYPTED_CONFIG_KEYS`), but the response body at lines 594-597 performs a raw `SELECT * FROM store_config` and puts every row's `value` field directly into the JSON response without decryption. Admin clients therefore receive `enc:v1:<hex_iv>:<hex_tag>:<hex_ct>` blobs for `tcx_password`, `smtp_pass`, and any other encrypted key that was previously stored. `GET /store` (line 556-567) and `GET /config` (line 391-406) do decrypt; only the `PUT /store` success response is missing the decryption loop.

**Code:**
```typescript
// settings.routes.ts:594-597 — missing decryption in response
const rows = await adb.all<any>('SELECT key, value FROM store_config');
const cfg: Record<string, string> = {};
for (const row of rows) cfg[row.key] = row.value;  // ← raw ciphertext!
res.json({ success: true, data: cfg });
```

**Exploit:**
A frontend that reads the PUT response to refresh its settings state will display or log `enc:v1:...` ciphertext blobs to the admin UI or browser console, confirming the encryption scheme (AES-256-GCM, versioned format) and providing ciphertexts that could be used in key-recovery timing attacks if any decryption oracle is later found.

**Fix:**
Mirror the decryption loop from `GET /store` (lines 563-565): `cfg[row.key] = (isAdmin && ENCRYPTED_CONFIG_KEYS.has(row.key)) ? decryptConfigValue(row.value) : row.value;` in the PUT response.

---

### [INFO] HMAC-wrapping of HKDF output in configEncryption key derivation adds no security

**Where:** `packages/server/src/utils/configEncryption.ts:30`

**What:**
The AES key for config-value encryption is derived as `HMAC-SHA256(key='bizarre-crm:config-secrets:v1', msg=config.configEncryptionKey)`. `configEncryptionKey` is itself either a 32-byte random hex env var (production) or `HKDF(JWT_SECRET, 'config-enc')` (dev). Wrapping an already-keyed HKDF output with a second HMAC keyed by a public static string provides no additional entropy or domain separation; it merely transforms the key deterministically. If `CONFIG_ENCRYPTION_KEY` is a full 32-byte random, the HMAC step is redundant. In dev the chain is `HKDF(JWT_SECRET, 'config-enc') → HMAC(static_label, hkdf_output)`, which is equivalent in practice to `HKDF(JWT_SECRET, 'config-enc')` alone.

**Code:**
```typescript
// configEncryption.ts:30
1: crypto.createHmac('sha256', 'bizarre-crm:config-secrets:v1').update(config.configEncryptionKey).digest(),
```

**Exploit:**
No direct exploitability; security depends entirely on `configEncryptionKey` entropy, which is fine when `CONFIG_ENCRYPTION_KEY` is set. The HMAC step misleads reviewers into thinking an independent salt is involved.

**Fix:**
Use the HKDF output directly as the AES key (after hex-decoding the 64-char hex string to 32 bytes), or derive the AES key via `hkdfSync` with `configEncryptionKey` as IKM and a domain-separated info string. Remove the HMAC-wrapping layer.

---

## Summary

| SEV | Count |
|---|---|
| CRITICAL | 1 |
| HIGH | 1 |
| MEDIUM | 3 |
| INFO | 1 |

Most severe: **CRITICAL** — `requireStepUpTotpSuperAdmin` selects wrong column names (`totp_secret`/`totp_iv`/`totp_tag` vs actual `totp_secret_enc`/`totp_secret_iv`/`totp_secret_tag`), crashing all 7 super-admin destructive endpoints with HTTP 500.
