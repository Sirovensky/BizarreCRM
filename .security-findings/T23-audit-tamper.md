# T23 — Audit-Log Tampering / Append-Only Enforcement / Log Injection / Timestamp Forgery

Scope: `utils/audit.ts`, `utils/masterAudit.ts`, `db/migrations/022_audit_logs.sql`,
`db/master-connection.ts`, `routes/settings.routes.ts`, `routes/settingsExport.routes.ts`,
`routes/tickets.routes.ts`, `routes/invoices.routes.ts`, `services/ticketStatus.ts`,
`routes/smsAutoResponders.routes.ts`, `middleware/auth.ts`.

---

### MEDIUM — No DB-level protection prevents UPDATE/DELETE on audit_logs

**Where:** `packages/server/src/db/migrations/022_audit_logs.sql:1`
`packages/server/src/routes/customers.routes.ts:2219`

**What:**
The `audit_logs` table is created with no `BEFORE UPDATE`, `BEFORE DELETE`, or `AFTER UPDATE` triggers
that would abort mutation attempts. Append-only enforcement exists solely by code convention — no route
intentionally issues `UPDATE audit_logs` except the GDPR-erase path (which is legitimate and scoped) and
the background retention sweep. Any tenant `admin` with raw SQL access (e.g. via a future SQL console
route, a misconfigured admin tool, or a SQL-injection bug elsewhere in the codebase) can silently alter
or erase audit rows after the fact.

**Code:**
```sql
-- migrations/022_audit_logs.sql — no triggers, no write-block
CREATE TABLE IF NOT EXISTS audit_logs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    event      TEXT NOT NULL,
    user_id    INTEGER,
    ip_address TEXT,
    details    TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

**Exploit:**
A malicious admin or a future SQL-execution endpoint issues `DELETE FROM audit_logs WHERE user_id = X`
or `UPDATE audit_logs SET details = '{}' WHERE event = 'role_changed'`; the operation succeeds silently
and the forensic record is gone. The `master_audit_log` has the same gap — no triggers protect it either.

**Fix:**
Add SQLite `BEFORE UPDATE` and `BEFORE DELETE` triggers on `audit_logs` (and `master_audit_log`) that
unconditionally `SELECT RAISE(ABORT, 'audit_log is immutable')`. The legitimate GDPR scrub path already
uses `JSON_REMOVE` on `details` only — exempt that operation via a special sentinel event if needed, or
accept the restriction and limit GDPR scrubbing to a separate privacy table.

---

### MEDIUM — GET /settings-ext/history audit log viewer missing adminOnly guard

**Where:** `packages/server/src/routes/settingsExport.routes.ts:401`

**What:**
The `GET /settings-ext/history` endpoint returns the most recent settings-change audit events from
`audit_logs` filtered to `settings_%` events and user creation/deletion. The route file's comment states
"All endpoints require admin role," but the actual `router.get('/history', asyncHandler(...))` definition
at line 401 does **not** include the `adminOnly` middleware. The parent mount at `index.ts:1641` only
applies `authMiddleware` (valid JWT, any role). A cashier, technician, or any other non-admin user can
call this endpoint and read the settings-change history, exposing admin usernames, setting keys modified,
and timestamps.

**Code:**
```typescript
// settingsExport.routes.ts — compare lines 213 (has adminOnly) vs 401 (missing it)
router.get(
  '/export.json',
  adminOnly,           // ← present
  asyncHandler(async (req, res) => { ... })
);

router.get(
  '/history',          // ← adminOnly is NOT here
  asyncHandler(async (req, res) => {
    // returns audit_logs rows filtered to settings events + user CRUD
  })
);
```

**Exploit:**
An authenticated cashier sends `GET /api/v1/settings-ext/history` with their valid JWT and receives a
paginated list of audit events that includes `user_created`, `user_role_changed`, `password_changed_by_admin`,
and all `setting_changed` rows — information that should be restricted to admins.

**Fix:**
Add `adminOnly` as the second argument to the `router.get('/history', ...)` call, matching the pattern
used by `/export.json`, `/import`, and `/bulk` on the same router.

---

### MEDIUM — smsAutoResponders /history queries non-existent table `audit_log` (silently returns empty)

**Where:** `packages/server/src/routes/smsAutoResponders.routes.ts:191`

**What:**
The `GET /sms-auto-responders/:id` detail endpoint attempts to read the last 20 match timestamps from
the audit log using table name `audit_log` (without trailing `s`) and column name `action` — neither
of which exist in this schema. The correct table is `audit_logs` and the column is `event`. The query
is wrapped in `.catch(() => [])` so the SQL error is swallowed silently and `recent_matches` always
returns an empty array, making the responder match history invisible to operators.

**Code:**
```typescript
// smsAutoResponders.routes.ts:190-198
const recentMatches = await adb.all<{ created_at: string; details: string }>(
  `SELECT created_at, details
     FROM audit_log          -- wrong: table is 'audit_logs'
    WHERE action = 'sms_auto_responder_matched'  -- wrong: column is 'event'
      AND JSON_EXTRACT(details, '$.responder_id') = ?
    ORDER BY created_at DESC
    LIMIT 20`,
  id,
).catch(() => [] as { created_at: string; details: string }[]);
```

**Exploit:**
An operator investigating why an auto-responder fired (or did not fire) can never see match history
because the query silently fails. More broadly, the `.catch(() => [])` suppresses the SQL error from
ever surfacing, masking the bug in production logs.

**Fix:**
Change `FROM audit_log` to `FROM audit_logs` and `WHERE action =` to `WHERE event =`. Remove or narrow
the `.catch()` so the error is at least logged at `warn` level.

---

### MEDIUM — settingsExport history queries non-existent column `al.meta` (returns null, breaks tab filter)

**Where:** `packages/server/src/routes/settingsExport.routes.ts:416`

**What:**
The `/settings-ext/history` endpoint selects `al.meta` from `audit_logs`, but the `audit_logs` schema
(migration 022, unmodified in any later migration) has no `meta` column — the actual column is `details`.
SQLite returns `NULL` for unknown columns in a `SELECT` without raising an error. Because `meta` is
always `NULL`, the `tab` query-string filter at lines 426–439 never matches any row (the guard
`if (!r.meta) return true` always takes the `true` branch and keeps all rows regardless of `tab`),
making the `?tab=<name>` filter silently inoperative.

**Code:**
```typescript
// settingsExport.routes.ts:416-422
`SELECT al.id, al.event, al.user_id, al.meta, al.created_at
   FROM audit_logs al
   WHERE al.event LIKE 'settings_%'
      OR al.event IN ('store_updated','user_created','user_updated','user_deleted')
   ORDER BY al.created_at DESC
   LIMIT ?`
```

**Exploit:**
Functional bug: the `?tab=` filter is disabled, so all matching events are returned to every tab.
In combination with the missing `adminOnly` guard (finding above), an authenticated non-admin receives
unfiltered settings/user-management audit events.

**Fix:**
Change `al.meta` to `al.details` in the `SELECT` list and in the JavaScript `r.meta` references
(lines 428, 430) to `r.details`.

---

### LOW — Ticket creation, deletion, and status changes not written to audit_logs

**Where:** `packages/server/src/routes/tickets.routes.ts:2148`,
`packages/server/src/services/ticketStatus.ts:453`

**What:**
Ticket deletion (a destructive, inventory-restoring operation) calls `insertHistoryAsync(adb, ticketId, ...)` 
which writes to `ticket_history` (a per-ticket log that is soft-deleted with the ticket), but never calls 
`audit()` to write to `audit_logs`. Similarly, `applyTicketStatusChange` in `ticketStatus.ts` writes to 
`ticket_history` only. Ticket creation also does not appear in `audit_logs`. These are among the most
operationally significant events in the application. Only `ticket_merged` and `ticket_duplicated` reach
`audit_logs`.

**Code:**
```typescript
// tickets.routes.ts — DELETE handler ends here, no audit() call
  await insertHistoryAsync(adb, ticketId, userId, 'deleted', 'Ticket deleted');
  broadcast(WS_EVENTS.TICKET_DELETED, { id: ticketId }, req.tenantSlug || null);
  res.json({ success: true, data: { id: ticketId } });

// ticketStatus.ts:453-458 — status change writes ticket_history, not audit_logs
  await insertHistory(
    adb, ticketId, userId, 'status_changed',
    `Status changed from "${oldStatus?.name ?? '?'}" to "${newStatus.name}"`,
    oldStatus?.name ?? null, newStatus.name,
  );
```

**Exploit:**
A rogue admin deletes a ticket (soft-delete with stock restoration) or changes a ticket status; neither
event appears in the tamper-visible `audit_logs` table that admins search during investigations. The
`ticket_history` table is scoped per ticket and not visible in the global audit log viewer, making the
deletion invisible to compliance searches.

**Fix:**
Add `audit(db, 'ticket_deleted', userId, ip, { ticket_id: ticketId, order_id: ... })` after the
`claimedDelete` success check. Add `audit(db, 'ticket_status_changed', userId, ip, { ticket_id, from, to })`
in `applyTicketStatusChange`. Mirror the same for ticket creation.

---

### LOW — Invoice payment recording not written to audit_logs

**Where:** `packages/server/src/routes/invoices.routes.ts:780`,
`packages/server/src/routes/invoices.routes.ts:131` (`postPaymentSideEffects`)

**What:**
`POST /invoices/:id/payments` inserts into `payments`, updates `invoices`, and calls
`postPaymentSideEffects`. The side-effects helper writes to `activity_events` (via `logActivity`) and
fires a webhook, but never calls `audit()` to write to `audit_logs`. Invoice void does call
`audit(db, 'invoice_voided', ...)` at line 952, creating an asymmetry where voiding is in the audit
trail but the original payment record is not.

**Code:**
```typescript
// invoices.routes.ts — payment route ends without audit() call
  await postPaymentSideEffects({ adb, db, invoice, paymentId, paymentAmount, paymentMethod, userId });
  // ... overpayment handling ...
  res.status(201).json({ success: true, data: updated });
```

**Exploit:**
A manager can record a payment, cancel the investigation trail query (which searches `audit_logs`), and
the payment appears nowhere in the audit log. If `activity_events` is purged or the retention sweep
removes old rows, no forensic record of the payment remains in `audit_logs`.

**Fix:**
Add `audit(db, 'payment_recorded', userId, ip, { invoice_id, payment_id: paymentId, amount, method })`
at the end of `POST /invoices/:id/payments`, after `postPaymentSideEffects` returns successfully.

---

### LOW — Failed privileged operations never written to audit_logs (reconnaissance invisible)

**Where:** `packages/server/src/middleware/auth.ts:261`

**What:**
`requirePermission()` returns a 403 when an authenticated user lacks the required permission. The
rejection is not logged to `audit_logs` — there is no call to `audit()` on the 403 path. This means
a rogue insider probing for access (e.g. a cashier repeatedly trying to call `invoices.void` or
`customers.gdpr_erase` endpoints) leaves no trace in the audit log. Only login failures are tracked
(via `logTenantAuthEvent`); mid-session privilege probing is completely invisible.

**Code:**
```typescript
// auth.ts:261 — permission denied, no audit call
  res.status(403).json(errorBody(ERROR_CODES.ERR_PERM_INSUFFICIENT, 'Insufficient permissions', rid, { permission }));
  // no: audit(req.db, 'permission_denied', req.user.id, req.ip, { permission, path: req.path })
```

**Exploit:**
An insider with a low-privilege account systematically probes API endpoints for over-permissive holes;
no trace appears in audit_logs, making the reconnaissance phase invisible to the operator reviewing
the security log.

**Fix:**
In the 403 branch of `requirePermission`, call `audit(req.db, 'permission_denied', req.user!.id, req.ip || 'unknown', { permission, method: req.method, path: req.path })` — best-effort (wrapped in try/catch mirroring the existing audit helper pattern).

---

### INFO — Audit write and state mutation are not atomic (TOCTOU: crash between mutation and audit)

**Where:** `packages/server/src/utils/audit.ts:42`,
all callers in routes (e.g. `routes/invoices.routes.ts:952`, `routes/settings.routes.ts:526`)

**What:**
Every route calls `audit()` as a separate synchronous `INSERT` after the state-mutating `await adb.run(...)` 
completes. Both the mutation and the audit are in the same SQLite single-tenant connection, but they are
not wrapped in a `db.transaction(...)` block together. If the Node.js process is killed or crashes between
the mutation commit and the audit INSERT, the state change is permanent but the audit record is never
written — a "silent change" without a trace. For sync routes (`db.prepare().run()`) the two operations
happen synchronously in sequence but still outside a transaction.

**Code:**
```typescript
// example: invoices.routes.ts
await adb.run("UPDATE invoices SET status='void' ..."); // state committed
// << server crash here = no audit record >>
audit(db, 'invoice_voided', req.user!.id, req.ip || 'unknown', { invoice_id: ... });
```

**Exploit:**
A server OOM-kill or SIGKILL between mutation and audit is a low-probability but non-zero event. In
normal usage the gap is microseconds, but on a heavily loaded server it may be more. An attacker who
can induce a server crash at the right moment (e.g. by triggering memory exhaustion) could cause a
sensitive state change (role escalation, refund, void) to go unlogged.

**Fix:**
Wrap critical state mutations + audit calls in a `db.transaction(() => { ... })` block using the
better-sqlite3 synchronous transaction API. For async routes, serialize the audit INSERT into the same
async DB call chain using `adb.run` for the audit row before returning, and consider a helper that
accepts both the mutation SQL and the audit event so callers cannot accidentally split them.

---

### INFO — master_audit_log also has no DB-level append-only protection

**Where:** `packages/server/src/db/master-connection.ts:126`

**What:**
The `master_audit_log` table in the master database has the same schema as `audit_logs` — no triggers,
no constraints preventing UPDATE/DELETE. Any code path that obtains the `masterDb` handle can
`masterDb.prepare('DELETE FROM master_audit_log WHERE ...').run(...)` without obstruction. The automated
retention sweep in `index.ts:2798` correctly deletes rows older than 730 days, but there is no guard
preventing an earlier ad-hoc deletion.

**Code:**
```typescript
// master-connection.ts:126-135
CREATE TABLE IF NOT EXISTS master_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  super_admin_id INTEGER REFERENCES super_admins(id),
  action TEXT NOT NULL,
  ...
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
  -- no BEFORE DELETE/UPDATE trigger
);
```

**Exploit:**
A compromised super-admin account (or a bug in the management route layer) can delete recent
`master_audit_log` entries to cover privileged actions (tenant deletion, impersonation, JWT secret
rotation) without leaving a trace.

**Fix:**
Same as for `audit_logs`: add `BEFORE UPDATE` and `BEFORE DELETE` triggers on `master_audit_log`
in the master DB initialization that call `RAISE(ABORT, 'master_audit_log is immutable')`.
Legitimate retention deletes (the 730-day sweep) are already scoped by `created_at < datetime('now', '-730 days')`
and could be exempted via a dedicated SQLITE PRAGMA or by accepting one narrow delete path.

---
