# T18 — Migration Drift, Schema/Code Mismatches, Missing Indexes, FK Gaps

Audited all 158 migration files (`packages/server/src/db/migrations/`) plus the migration runner (`db/migrate.ts`), cross-referencing code in `routes/`, `middleware/`, and `services/` for column-name drift, missing constraints, and orphan-data paths.

---

### HIGH — Super-admin step-up TOTP always returns 403: wrong column names in SELECT

**Where:** `packages/server/src/middleware/stepUpTotp.ts:362–373`
Also: `packages/server/src/db/master-connection.ts:70–72`

**What:**
`stepUpTotpSuperAdminMiddleware` queries `super_admins` selecting columns `totp_secret`, `totp_iv`, `totp_tag`. The master-DB schema (defined in `master-connection.ts`) names those columns `totp_secret_enc`, `totp_secret_iv`, `totp_secret_tag`. SQLite silently returns `NULL` for non-existent columns in a `SELECT`; the guard at line 373 then unconditionally rejects with `403 "Step-up auth requires 2FA enrollment"`, blocking all enrolled super-admins from every step-up-protected endpoint regardless of valid TOTP.

**Code:**
```typescript
// stepUpTotp.ts:362
.prepare('SELECT id, email, totp_secret, totp_iv, totp_tag FROM super_admins WHERE id = ?...')
// ...
// line 373 — all three fields are NULL → always fires
if (!dbAdmin.totp_secret || !dbAdmin.totp_iv || !dbAdmin.totp_tag) {
  res.status(403).json(errorBody(..., 'Step-up auth requires 2FA enrollment', ...));
  return;
}
```

**Exploit:**
All 17+ endpoints guarded by `requireStepUpTotpSuperAdmin` are permanently inaccessible to enrolled super-admins (`/rotate-jwt-secret`, `DELETE /tenants/:slug`, `/tenants/:slug/backup-restore`, `/config`, etc.). An operator facing an active incident cannot use these endpoints; the effective blast radius is an operational denial-of-service on every critical super-admin mutation.

**Fix:**
Change the `SELECT` in `stepUpTotp.ts:362` to use the correct column names: `totp_secret_enc`, `totp_secret_iv`, `totp_secret_tag`, and update the cast type annotation and the subsequent references at lines 364, 373, and 409 to match.

---

### MEDIUM — Migration 151 silently no-ops for existing DBs (installment_plans schema drift)

**Where:** `packages/server/src/db/migrations/095_billing_enrichment.sql` vs `packages/server/src/db/migrations/151_installment_plans.sql`
Also: `packages/server/src/routes/installments.routes.ts:6`

**What:**
Migration 095 already created `installment_plans` and `installment_schedule` using `CREATE TABLE IF NOT EXISTS`. Migration 151 (intended as the production-quality redesign) also uses `CREATE TABLE IF NOT EXISTS` for both tables. On any database that ran 095 before 151, both `CREATE TABLE` statements in 151 silently no-op, leaving the live schema at the weaker 095 definition: `acceptance_token TEXT` (nullable), `acceptance_signed_at TEXT` (nullable), no `REFERENCES` on `invoice_id`/`customer_id`, no `CHECK (total_cents > 0)`, no `updated_at` column on `installment_plans`, and `installment_schedule.plan_id INTEGER NOT NULL` with **no `REFERENCES` clause at all**. The route comment (`Tables: installment_plans, installment_schedule (migration 095_billing_enrichment.sql)`) confirms the developer tracked this, but the stronger 151 constraints never land.

**Code:**
```sql
-- 095 schema (what actually runs):
acceptance_token      TEXT,           -- nullable
acceptance_signed_at  TEXT,           -- nullable
plan_id               INTEGER NOT NULL -- no REFERENCES, no CASCADE

-- 151 schema (silently skipped for existing DBs):
acceptance_token     TEXT    NOT NULL,
plan_id     INTEGER NOT NULL REFERENCES installment_plans(id) ON DELETE CASCADE,
```

**Exploit:**
Application-level validation in `installments.routes.ts` enforces `acceptance_token` non-empty, but a direct DB write (maintenance script, import, future bypass) can insert a NULL token, creating a legally void payment plan. More critically, `plan_id` carries no FK—see the next finding for the GDPR cascade consequence.

**Fix:**
Replace the `CREATE TABLE IF NOT EXISTS` in migration 151 with an `ALTER TABLE`-based migration that adds the missing columns and a table-rebuild that adds the proper FK/CHECK constraints (using the `PRAGMA writable_schema` or rename-copy pattern from migrations 042, 074, 099).

---

### MEDIUM — GDPR erasure leaves orphaned `installment_schedule` rows

**Where:** `packages/server/src/db/migrations/097_enrichment_cleanup_triggers.sql:83`
Also: `packages/server/src/db/migrations/095_billing_enrichment.sql` (installment_schedule DDL)

**What:**
The `trg_customer_del_enrichment_cleanup` trigger fires on customer hard-delete (GDPR erasure) and runs `DELETE FROM installment_plans WHERE customer_id = OLD.id`. However, `installment_schedule.plan_id` in the 095 schema is declared `INTEGER NOT NULL` with **no `REFERENCES installment_plans(id)` clause** — SQLite therefore applies no cascade. After the trigger removes plan rows, all child `installment_schedule` rows survive with dangling `plan_id` values. Neither migration 097 nor any later migration adds a cleanup statement for `installment_schedule`.

**Code:**
```sql
-- 097 trigger body (partial):
DELETE FROM installment_plans    WHERE customer_id = OLD.id;
-- installment_schedule is NOT listed — orphans remain

-- 095 installment_schedule.plan_id (no FK):
plan_id   INTEGER NOT NULL,   -- no REFERENCES, no ON DELETE CASCADE
```

**Exploit:**
After a GDPR erasure request for a customer with active payment plans, `installment_schedule` rows referencing deleted `plan_id` values persist indefinitely. This violates the erasure contract (GDPR Art. 17) and leaks PII-adjacent financial data (amount_cents, due_date) tied to the erased customer's plans.

**Fix:**
Add `DELETE FROM installment_schedule WHERE plan_id IN (SELECT id FROM installment_plans WHERE customer_id = OLD.id)` *before* the `DELETE FROM installment_plans` line in the trigger body, or add `REFERENCES installment_plans(id) ON DELETE CASCADE` to `installment_schedule.plan_id` via a table rebuild.

---

### LOW — `email_messages` missing `created_at` index; PII retention sweep is a full table scan

**Where:** `packages/server/src/db/migrations/001_initial.sql:815`
Also: `packages/server/src/services/retentionSweeper.ts:464`

**What:**
`email_messages` was created with a single index on `(entity_type, entity_id)`. No `created_at` index exists in any of the 158 migrations. The PII retention sweeper executes `DELETE FROM email_messages WHERE created_at < datetime('now', '-N months')` (retentionSweeper.ts:464). Without a `created_at` index, this is a full table scan every sweep cycle. A shop running a multi-year email history with tens of thousands of rows will see the nightly sweep cron hold a write-lock on the table for an extended period.

**Code:**
```typescript
// retentionSweeper.ts:464
const sql = `DELETE FROM ${rule.table} WHERE ${rule.dateColumn} < ${cutoff}`;
// For email_messages: full table scan, no index
```

**Exploit:**
An attacker who can trigger high email traffic (booking confirmations, invoice reminders) to grow `email_messages` can cause the nightly retention sweep to lock the table long enough to starve concurrent read/write operations, degrading service availability.

**Fix:**
Add `CREATE INDEX IF NOT EXISTS idx_email_messages_created_at ON email_messages(created_at);` in a new migration. Compare with `call_logs` which correctly has `idx_call_logs_created_at` (migration 043) and `sms_messages` which has `idx_sms_messages_created_at` (migration 001).

---

### INFO — Four duplicate migration numbers (049, 050, 100, 149) with distinct filenames

**Where:** `packages/server/src/db/migrations/` — files prefixed `049_*`, `050_*`, `100_*`, `149_*`

**What:**
The migration runner sorts filenames lexicographically and tracks by filename, so all eight files across the four sets apply correctly and without collision. However, three files share prefix `049_`, two share `050_`, two share `100_`, and two share `149_`. Any new migration numbered 049–050 or 100 or 149 added by a developer would collide in lexicographic ordering with an ambiguous position relative to the existing duplicates, silently interleaving execution order in unexpected ways.

**Code:**
```
049_customer_is_active.sql
049_po_status_workflow.sql
049_sms_scheduled_and_archival.sql
100_payment_capture_state.sql
100_recovery_cooldown.sql
149_customers_lat_lng.sql
149_retention_default_off.sql
```

**Exploit:**
No current exploitability. A future developer adding migration `049_something.sql` would get surprising interleaving if any of the three existing 049-prefix migrations modify a table the new one depends on.

**Fix:**
Renumber the duplicate-suffix migrations to use the next available sequential numbers (155, 156, …) in a non-destructive rename (update `_migrations` tracking table for existing deployments). Enforce the convention in code review.

---

### INFO — `gift_cards.code_hash` non-unique index; original `code` column still plaintext

**Where:** `packages/server/src/db/migrations/104_gift_card_code_hash.sql:22–25`
Also: `packages/server/src/db/migrations/028_gift_cards.sql` (`code TEXT NOT NULL UNIQUE`)

**What:**
Migration 028 created `gift_cards.code` with a `UNIQUE` constraint. Migration 104 added `code_hash TEXT` with a non-unique index only. The comment in 104 notes a planned follow-up migration to drop the plaintext `code` column "once all redemption paths are hash-first," but that follow-up has not landed in any of the 158 migrations. The plaintext card code therefore persists in the database alongside the hash, and `code_hash` has no UNIQUE constraint—while SHA-256 collision is astronomically unlikely, the inconsistency means a card lookup by hash could theoretically return multiple rows on a corrupted dataset.

**Code:**
```sql
-- migration 028: code has UNIQUE
code TEXT NOT NULL UNIQUE,

-- migration 104: code_hash has plain index only
ALTER TABLE gift_cards ADD COLUMN code_hash TEXT;
CREATE INDEX IF NOT EXISTS idx_gift_cards_code_hash ON gift_cards(code_hash);
-- no UNIQUE
```

**Exploit:**
Plaintext codes in `gift_cards.code` are visible to anyone with DB read access (backup exfiltration, DB admin account compromise). No direct web exploitability beyond S05/SEC-H38 scope.

**Fix:**
(1) Add `CREATE UNIQUE INDEX IF NOT EXISTS idx_gift_cards_code_hash_unique ON gift_cards(code_hash) WHERE code_hash IS NOT NULL` in a new migration. (2) Schedule the planned column drop of `code` once the backfill service (`giftCardCodeHashBackfill.ts`) confirms 100% coverage.

---
