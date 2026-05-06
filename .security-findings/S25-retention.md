# S25 — Data Retention / Hard-Delete / GDPR Right-to-Erasure

---

### HIGH: GDPR erase blocked by FK constraint — partial erasure leaves customer row intact

**Where:** `packages/server/src/routes/customers.routes.ts:2206` (hard DELETE), cross-referenced migrations `025`, `026`, `041`, `068`, `123`

**What:**
The `DELETE /:id/gdpr-erase` handler calls `DELETE FROM customers WHERE id = ?` after clearing
tickets/invoices/estimates/sms/call/email rows, but six tables with NOT-NULL foreign keys to
`customers(id)` and **no** `ON DELETE CASCADE` are never cleared first:
`customer_feedback` (mig. 025), `store_credits` (mig. 026), `store_credit_transactions` (mig. 026),
`customer_subscriptions` (mig. 068), `portal_sessions` (mig. 041),
`portal_verification_codes` (mig. 041), and `invoice_templates` (mig. 123).
With `PRAGMA foreign_keys = ON` (confirmed in `tenant-pool.ts:84`), SQLite raises
`FOREIGN KEY constraint failed` and the customer row is never deleted.
There is no transaction wrapping the handler, so all prior DELETEs
(`sms_messages`, `call_logs`, `email_messages`, etc.) have already committed when the error fires.

**Code:**
```typescript
// customers.routes.ts ~2183 — phone set built BEFORE FK tables are cleared
await adb.run(`DELETE FROM sms_messages WHERE conv_phone IN (...)`, ...phoneList);
await adb.run(`DELETE FROM call_logs WHERE conv_phone IN (...)`, ...phoneList);
// ...
await adb.run('DELETE FROM customers WHERE id = ?', id);  // line 2206
// ↑ throws FK constraint if customer has feedback/credits/subscriptions/portal rows
// No transaction — prior deletes already committed. Customer row survives.
```

**Exploit:**
Any customer who has a store-credit balance, a membership subscription, a portal session, or
feedback rows will permanently defeat their own GDPR erasure request: communications data is
destroyed but the identifying customer record persists, violating Art. 17 GDPR.  Compliance
audit trails show `customer_gdpr_erased` never fires for these customers.

**Fix:**
Wrap the entire handler in a `db.transaction(...)` (better-sqlite3 synchronous transaction or
`adb.transaction([...])` batched form). Before the final `DELETE FROM customers`, add explicit
`DELETE FROM customer_feedback`, `store_credits`, `store_credit_transactions`,
`customer_subscriptions`, `portal_sessions`, `portal_verification_codes`, and
`invoice_templates` WHERE `customer_id = ?`.

---

### MEDIUM: GDPR erase skips SMS/call logs from extra phone numbers

**Where:** `packages/server/src/routes/customers.routes.ts:2185–2193`

**What:**
The erasure builds `phoneSet` from only `customer.phone` and `customer.mobile` (the two columns on the
`customers` row itself). It never queries the `customer_phones` table (where additional contact
numbers are stored after POST/PUT operations).  SMS and call-log rows keyed on those extra
`conv_phone` values are never deleted.

**Code:**
```typescript
const phoneSet = new Set<string>();
if (customer.phone)  phoneSet.add(normalizePhone(customer.phone));
if (customer.mobile) phoneSet.add(normalizePhone(customer.mobile));
// customer_phones table is NOT consulted — extra numbers survive erasure
if (phoneSet.size > 0) {
  await adb.run(`DELETE FROM sms_messages WHERE conv_phone IN (...)`, ...phoneList);
  await adb.run(`DELETE FROM call_logs   WHERE conv_phone IN (...)`, ...phoneList);
}
```

**Exploit:**
A customer whose primary contact was changed (old number now in `customer_phones`) retains all
historical SMS/call PII under their old number after the erasure returns HTTP 200 success.

**Fix:**
Before building `phoneSet`, query `SELECT phone FROM customer_phones WHERE customer_id = ?`
and union those numbers into the set — mirroring the pattern already used in `GET /:id/export`
(line ~1944) and `GET /:id/communications` (line ~1688).

---

### HIGH: Tenant termination never removes the uploads directory

**Where:** `packages/server/src/services/tenantTermination.ts:280–423` (executeTermination + purgeExpiredDeletions)

**What:**
`executeTermination` renames the tenant DB into `deleted/` and removes the Cloudflare DNS record
but makes no attempt to clean up `<config.uploadsPath>/<tenantSlug>/`.
`purgeExpiredDeletions` (called after the 30-day grace period) only `unlinkSync`s the `.db`,
`-wal`, and `-shm` files; the uploads directory remains on disk indefinitely after the DB is purged.
This includes ticket photos, customer-signature data URLs written to disk, export archives, and any
other binary uploads the tenant created during their lifetime.

**Code:**
```typescript
// purgeExpiredDeletions — tenantTermination.ts ~490
fs.unlinkSync(full);
try { fs.unlinkSync(full + '-wal'); } catch {}
try { fs.unlinkSync(full + '-shm'); } catch {}
purged += 1;
// No cleanup of uploadsPath/<slug>/ or exportsDir/<slug>/
```

**Exploit:**
After a tenant self-terminates and the 30-day grace elapses, all uploaded files remain readable at
their original filesystem path.  Any process or user with filesystem access (backup scripts,
rogue employees, compromised server) can read former-tenant PII from on-disk photos and signatures
indefinitely — a GDPR Art. 17 / Art. 5(1)(e) storage-limitation violation.

**Fix:**
In `purgeExpiredDeletions`, after unlinking the DB files, also `fs.rmSync(uploadsPath/<slug>/, { recursive: true, force: true })`.
Store the `<tenantSlug>` in the `tenants` table's `archived_db_path` (or a new column) so the slug
is available without parsing the filename.  Mirror the same cleanup in `executeTermination`'s
immediate rename path (at least move / archive the uploads folder alongside the DB).

---

### MEDIUM: Tenant export files orphaned after termination — never swept

**Where:** `packages/server/src/services/tenantExport.ts:718` (`sweepOldExports`), `packages/server/src/services/retentionSweeper.ts:596–614`

**What:**
`sweepOldExports` is called by `runRetentionSweep`, which is called nightly by the `forEachDbAsync`
cron loop against every **active** tenant DB.  Once a tenant is terminated, `closeTenantDb` is
called and the DB file is renamed into `deleted/`; the terminated DB is therefore never iterated
again by `forEachDbAsync`.  Any `.enc` export files written to `<exportsDir>/` before termination
are never removed by the sweep (the DB row that tracks them is inside the now-inaccessible tenant
DB), so they persist on disk past the 7-day retention window indefinitely.

**Code:**
```typescript
// sweepOldExports: called only via runRetentionSweep(tenantDb, ...) per-active-tenant
const expired = db.prepare(
  `SELECT id, file_path FROM tenant_exports
   WHERE started_at < datetime('now', '-${EXPORT_RETENTION_DAYS} days')`
).all();
// After termination, db handle is closed — this query never runs for that tenant again.
```

**Exploit:**
An exported tenant backup (AES-256-GCM encrypted but containing all PII) may remain on-disk weeks
or months after the tenant's DB is purged.  If the exports directory is ever compromised, the
attacker has a complete data snapshot even though the tenant believed their data was deleted.

**Fix:**
During `executeTermination`, enumerate all `.enc` files in `<exportsDir>/` matching the tenant
slug prefix and delete them immediately (before or alongside the DB rename).  Alternatively,
maintain a separate `master_tenant_exports` log in the master DB for post-termination sweep.

---

### LOW: Pre-migration-108 tenants: PII retention silently disabled despite master switch

**Where:** `packages/server/src/services/retentionSweeper.ts:139`, `packages/server/src/db/migrations/108_pii_retention_defaults.sql`

**What:**
`DEFAULT_PII_MONTHS = 0` is the fallback when a tenant's `store_config` row for
`retention_sms_months` / `retention_calls_months` / `retention_email_months` /
`retention_ticket_notes_months` is missing.  Migration 108 seeds those keys at `24` via
`INSERT OR IGNORE`, but tenants that pre-date migration 108 and never had the migration applied
(or had the rows deleted) will fall through to `0` (disabled) even after enabling the
`retention_sweep_enabled` master switch.  The inline comment on `readPiiRetentionMonths` says
"falling back to the 24mo default", contradicting the actual code.

**Code:**
```typescript
const DEFAULT_PII_MONTHS = 0;           // line 139 — "disabled" sentinel
// readPiiRetentionMonths (line 354):
const parsed = row?.value !== undefined ? Number.parseInt(row.value, 10) : NaN;
if (!Number.isFinite(parsed) || parsed < MIN_PII_MONTHS) {
  return DEFAULT_PII_MONTHS;   // returns 0 → PII sweep skipped silently
}
```

**Exploit:**
A tenant admin enabling `retention_sweep_enabled = '1'` believes PII is being swept per their
privacy policy.  For pre-108 tenants with missing config keys, the sweep silently does nothing for
all four PII tables, constituting a quiet compliance failure with no operator-visible warning.

**Fix:**
Change `DEFAULT_PII_MONTHS` from `0` to `24` (or whatever the policy default is), and add a
log-level warning whenever `readPiiRetentionMonths` has to use the hardcoded fallback so operators
can detect missing config keys.  Alternatively, make the migration runner idempotent and re-seed
missing keys during every startup rather than relying on `INSERT OR IGNORE`.

---

### LOW: Customer notes hard-delete has no audit log

**Where:** `packages/server/src/routes/customers.routes.ts:2470–2472`

**What:**
`DELETE /:id/notes/:noteId` permanently removes a customer note without writing any `audit_logs`
entry.  Any user with the `customers.edit` permission can silently destroy the CRM note history
for any customer.  Contrast with `GET /:id/export` which writes an audit row, and
ticket-note deletes which write a `ticket_history` entry.

**Code:**
```typescript
await adb.run('DELETE FROM customer_notes WHERE id = ?', noteId);
// No audit() call — the deletion is untracked
res.json({ success: true, data: null });
```

**Exploit:**
A rogue employee (e.g. about to be terminated) deletes damaging notes about their own misconduct
from a customer file; there is no forensic record that the note ever existed.

**Fix:**
Add `audit(req.db, 'customer_note_deleted', req.user!.id, req.ip || 'unknown', { customer_id: customerId, note_id: noteId })` before the `DELETE`.

---

### LOW: Soft-deleted (or GDPR-erased) customers readable via CRM health-score endpoints

**Where:** `packages/server/src/routes/crm.routes.ts:141`, `crm.routes.ts:208`

**What:**
`GET /customers/:id/health-score` and `GET /customers/:id/ltv-tier` query `customers` without an
`AND is_deleted = 0` guard.  A soft-deleted customer (or one where the customer row survived a
failed GDPR erasure, per Finding 1 above) can be read by any manager or admin.  The endpoints
return health score, LTV tier, and lifetime-value-cents — metadata derived from PII the operator
may believe has been erased.

**Code:**
```typescript
// crm.routes.ts:141
const row = await adb.get<...>(
  `SELECT health_score, health_tier, last_interaction_at, lifetime_value_cents
     FROM customers WHERE id = ?`,   // no is_deleted = 0 filter
  id,
);
```

**Exploit:**
After a customer deletion request, a manager queries the health-score endpoint with the known
customer ID and retrieves their calculated lifetime value and interaction timestamp, revealing
retained PII that was supposed to be inaccessible.

**Fix:**
Add `AND is_deleted = 0` (or `AND is_deleted = 0 AND id IS NOT NULL` for hard-deleted rows) to
both SELECT statements. For customers hard-deleted via gdpr-erase, also confirm the row is gone
before returning data.

---
