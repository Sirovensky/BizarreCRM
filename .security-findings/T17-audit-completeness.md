# T17 — Audit Log Completeness Matrix

**Slot:** T17  
**Audited by:** Claude Sonnet 4.6 (subagent)  
**Date:** 2026-05-06  
**Files covered:** `packages/server/src/utils/audit.ts`, `utils/masterAudit.ts`, `routes/auth.routes.ts`, `routes/settings.routes.ts`, `routes/roles.routes.ts`, `routes/employees.routes.ts`, `routes/admin.routes.ts`, `routes/super-admin.routes.ts`, `routes/super-admin-management.routes.ts`, `routes/management.routes.ts`, `routes/refunds.routes.ts`, `routes/invoices.routes.ts`, `routes/creditNotes.routes.ts`, `routes/giftCards.routes.ts`, `routes/customers.routes.ts`, `routes/dataExport.routes.ts`, `routes/pos.routes.ts`, `middleware/auth.ts`, `db/master-connection.ts`, `db/migrations/022_audit_logs.sql`, `index.ts`

---

## Coverage Matrix

| Operation | Audited | Event Name | Notes |
|-----------|---------|------------|-------|
| Login success | ✅ | `login_success` | auth.routes.ts:853,1068 |
| Login failure | ✅ | `login_failed` | auth.routes.ts:761,806 |
| Logout | ❌ | — | POST /logout at 1418 deletes session, sets cookies, returns — no audit call |
| Password reset request | ✅ | `password_reset_requested` | auth.routes.ts:1707,1730 |
| Password reset complete | ✅ | `password_reset_completed` | auth.routes.ts:1888 |
| Password change (self) | ✅ | `password_changed` | auth.routes.ts:2314 |
| Password change (admin) | ✅ | `password_changed_by_admin` | settings.routes.ts:1205 |
| Email change (user) | ❌ | — | settings.routes.ts:1192–1200 UPDATE includes `email = COALESCE(?, email)`, no `email_changed` audit call |
| 2FA enroll (first verify) | ⚠️ | `login_success` (method=2fa_setup) | Enrollment is logged but as a login event, not a dedicated `2fa_enrolled` event |
| 2FA disable (self) | ✅ | `2fa_disabled` | auth.routes.ts:1981 |
| 2FA disable (admin) | ✅ | `2fa_force_disabled` | auth.routes.ts:2030 |
| 2FA recovery code use | ✅ | `backup_code_recovery_success` | auth.routes.ts:2185 |
| Trust device add | ⚠️ | `login_success` (method=2fa_trusted_device) | Implicit; no dedicated `device_trust_added` event |
| Role grant/revoke | ✅ | `user_role_changed` | settings.routes.ts:1211; roles.routes.ts:329 |
| Employee disable | ❌ | — | settings.routes.ts:1228–1230 revokes sessions but no `user_disabled` audit row |
| Employee hard-delete | N/A | — | No DELETE FROM users route found; only is_active=0 |
| Settings PUT (all keys) | ✅ | `setting_changed` | settings.routes.ts:526 (before/after with masking for sensitive keys) |
| Data export request | ✅ | `data_export` | dataExport.routes.ts:191 |
| Data export download | ✅ | `data_export` (combined) | Same event; request+stream combined |
| Tenant create | ✅ | `tenant_created` | super-admin.routes.ts:741 |
| Tenant repair | ✅ | `tenant_repaired` | super-admin.routes.ts:1134 |
| Tenant suspend/terminate | ✅ | `tenant_suspended`, `tenant_deleted` | super-admin.routes.ts:1118,1179 |
| Impersonate start | ✅ | `super_admin.impersonate_started` | Both master + tenant audit; 2665,2677 |
| Impersonate end | ✅ | `super_admin.impersonate_ended` | super-admin.routes.ts:2773,2783 |
| JWT rotate | ✅ | `super_admin_rotate_jwt_secret` | super-admin.routes.ts:604 |
| Refund issued | ✅ | `refund_created` | refunds.routes.ts:236 |
| Void | ✅ | `invoice_voided` | invoices.routes.ts:952 |
| Credit note created | ✅ | `credit_note.created` | creditNotes.routes.ts:221; invoices.routes.ts:1305 |
| Gift card load | ✅ | `gift_card_issued` | giftCards.routes.ts:312 |
| Gift card redeem | ✅ | `gift_card_redeemed` | giftCards.routes.ts:385 |
| Customer hard-delete / GDPR erase | ✅ | `customer_gdpr_erased` | customers.routes.ts:2244 |
| Audit log read | ❌ | — | GET /settings/audit-logs (settings.routes.ts:1913) has no meta-audit insert |
| Backup create (admin) | ❌ | — | POST /admin/backup (admin.routes.ts:454) calls runBackup() with no audit call |
| Backup restore | ✅ | `admin_backup_restore_start/success/failed` | admin.routes.ts:537,580,599 |
| Backup download | ✅ | `admin_backup_download` | admin.routes.ts:483 |
| Super-admin backup create | ✅ | `super_admin_tenant_backup_run` | super-admin.routes.ts:1436 |

---

## Findings

### MEDIUM — Logout not audited: session termination leaves no trail

**Where:** `packages/server/src/routes/auth.routes.ts:1418`

**What:**
The POST `/logout` route deletes the session row from the DB and clears the `refreshToken`, `csrf_token`, and `deviceTrust` cookies, then returns `{success: true}`. There is no call to `audit()` or `logTenantAuthEvent()`. Every other auth transition (login, refresh, 2FA, pin-switch) writes an audit row, but logout is entirely invisible in the audit trail. In an incident investigation it is impossible to determine from the audit log whether a user proactively logged out or was terminated by session expiry/revocation.

**Code:**
```typescript
router.post('/logout', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  await adb.run('DELETE FROM sessions WHERE id = ?', req.user!.sessionId);
  res.clearCookie('refreshToken', { path: '/' });
  res.clearCookie('csrf_token', { path: '/' });
  res.clearCookie('deviceTrust', { path: '/' });
  res.json({ success: true, data: { message: 'Logged out' } });
  // ← no audit() or logTenantAuthEvent() call
}));
```

**Exploit:**
An insider threat or compromised account logs out after exfiltrating data. The audit trail shows the data access events but no termination event, making it harder to construct a timeline and confirm the session was explicitly ended rather than stolen.

**Fix:**
Add `audit(req.db, 'logout', req.user!.id, req.ip || 'unknown', { sessionId: req.user!.sessionId })` and `logTenantAuthEvent('logout', req, req.user!.id, req.user!.username)` immediately before the `res.json()` call, mirroring the pattern used at `login_success`.

---

### MEDIUM — User disable (is_active=0) not audited

**Where:** `packages/server/src/routes/settings.routes.ts:1228`

**What:**
The `PUT /settings/users/:id` endpoint handles password change (`password_changed_by_admin`), role change (`user_role_changed`), and PIN change (`pin_changed_by_admin`) — each with a dedicated audit call. However, setting `is_active = 0` (disabling a user account) only triggers `DELETE FROM sessions` but writes no audit row. An admin can silently lock out a user and there is no recoverable audit trail of the deactivation event, actor, or timestamp.

**Code:**
```typescript
if (pin) {
  audit(db, 'pin_changed_by_admin', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId });
}
// If user was deactivated, invalidate all their sessions
if (is_active === 0 || is_active === false) {
  await adb.run('DELETE FROM sessions WHERE user_id = ?', req.params.id);
  // ← no audit call here
}
```

**Exploit:**
A rogue admin disables a whistleblower's or auditor's account. No audit row is written; the only evidence is the `is_active` column value and the `updated_at` timestamp, neither of which records who performed the action.

**Fix:**
Add `audit(db, 'user_disabled', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId, previous_role: targetBefore.role })` inside the `if (is_active === 0 || is_active === false)` block. Similarly add `user_reactivated` when transitioning to `is_active = 1`.

---

### MEDIUM — Email change not audited

**Where:** `packages/server/src/routes/settings.routes.ts:1192`

**What:**
The `PUT /settings/users/:id` handler issues a single `UPDATE users SET email = COALESCE(?, email), ...` that can change a user's email address (an account-takeover vector). Auditing fires only for password, role, or PIN changes — not for email mutations. A changed email redirects future password-reset links, making this one of the highest-value account mutations.

**Code:**
```typescript
await adb.run(`
  UPDATE users SET
    email = COALESCE(?, email), first_name = COALESCE(?, first_name),
    ...
  WHERE id = ?
`, email ?? null, ...);

if (password) {
  audit(db, 'password_changed_by_admin', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId });
}
// ← no audit for email change
```

**Exploit:**
An admin or compromised admin session silently changes a target user's login email to an attacker-controlled address, then requests a password reset to take over the account. No audit event is written; the only forensic evidence is the `updated_at` column.

**Fix:**
Before the UPDATE, read `targetBefore.email` (already fetched at line 1036 if the SELECT is expanded). After the UPDATE, if `email !== null && email !== targetBefore.email`, emit `audit(db, 'user_email_changed', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId, old_email_hash, new_email_hash })` with SHA-256-truncated hashes instead of plaintext emails.

---

### MEDIUM — Audit log reads not meta-audited

**Where:** `packages/server/src/routes/settings.routes.ts:1913`

**What:**
`GET /settings/audit-logs` is protected by `adminOnly` but reading audit logs is not itself logged. Any admin can silently page through the entire audit history — including other admins' actions, refunds, role changes, GDPR erasures — with no record that the audit data was accessed. Compliance frameworks (SOC 2 CC7, PCI-DSS 10.3) require auditing access to audit records themselves (meta-audit).

**Code:**
```typescript
router.get('/audit-logs', adminOnly, async (req, res) => {
  // ... builds query, fetches rows ...
  res.json({ success: true, data: { logs, ... } });
  // ← no audit() call
});
```

**Exploit:**
An attacker who gains admin credentials reviews the audit trail to understand what is monitored, identify coverage gaps, and time their attack to avoid detection — with no evidence the audit log was ever consulted.

**Fix:**
Add `audit(req.db, 'audit_log_accessed', req.user!.id, req.ip || 'unknown', { page, pageSize, filters: { event, user_id, from_date, to_date } })` before the response. This creates a lightweight breadcrumb that is itself queryable without creating a feedback loop (the access event need not be returned in the same query).

---

### LOW — Backup creation (admin-triggered) not audited

**Where:** `packages/server/src/routes/admin.routes.ts:454`

**What:**
`POST /admin/backup` calls `runBackup(db)` and returns the result. No actor is captured in the audit trail — not `req.user` (if any), not the IP, and not the event. Backup restoration and download are audited (lines 537, 580, 483), creating an asymmetry: it is possible to determine when a backup was downloaded or restored but not when it was created or who triggered it.

**Code:**
```typescript
router.post('/backup', async (req, res) => {
  const db = req.db;
  if (isTenantBackupRunning()) {
    res.status(429).json(...);
    return;
  }
  const result = await runBackup(db);
  res.json({ success: result.success, data: result });
  // ← no audit() call
});
```

**Exploit:**
An attacker with admin access creates a fresh backup (exfiltration precursor) without leaving an audit trail. The download event is logged, but if the attacker uses an out-of-band path to retrieve the file (direct filesystem access, S3 sync), only the creation is relevant.

**Fix:**
Add `audit(db, 'admin_backup_created', req.user?.id ?? null, req.ip || 'unknown', { success: result.success, filename: result.filename ?? null })` after `runBackup()` returns, mirroring the pattern used for restore and download.

---

### LOW — Impersonated-session actions use tenant user_id as actor in tenant audit_log

**Where:** `packages/server/src/routes/super-admin.routes.ts:2677`, `middleware/auth.ts:198`

**What:**
When a super-admin impersonates a tenant user, the issued JWT carries `impersonated: true` (line 2656). However, the `authMiddleware` (middleware/auth.ts) does not read or propagate this flag — `req.user` contains only `{ id, username, role, ... }` of the *target* user. All subsequent `audit()` calls from tenant routes use `req.user!.id` as the actor. In the tenant's `audit_logs` table, actions taken by the super-admin appear to have been taken by the target user, not the impersonator. The master-level `super_admin.impersonate_started` row records the intent, but all subsequent mutations carry the wrong actor.

**Code:**
```typescript
// auth.ts — never reads impersonated from JWT payload
req.user = {
  ...user,   // target user's id, username, role
  permissions: parsedPermissions,
  sessionId: payload.sessionId,
  customRolePermissions,
};

// Later in any route:
audit(db, 'refund_created', req.user!.id, ...);  // records target user, not super-admin
```

**Exploit:**
A super-admin impersonates a tenant admin, issues a large refund, and ends the session. The tenant's `audit_logs.user_id` shows the tenant admin as the refund actor. In a dispute, the tenant admin is blamed; the super-admin's involvement is only recoverable from `master_audit_log` if the investigator knows to look there.

**Fix:**
Propagate `impersonated: true` and `super_admin_id` from the JWT payload into `req.user` (add optional fields to `AuthUser`). In `audit.ts`, add an optional `impersonatedBy` parameter. All routes that call `audit()` during an impersonated session should pass `{ ..., impersonated_by: req.user.superAdminId }` so the tenant audit trail accurately reflects the real actor.

---

### LOW — POS direct INSERT INTO audit_logs bypasses 16 KB cap and event sanitizer

**Where:** `packages/server/src/routes/pos.routes.ts:2396`, `2626`, `2663`

**What:**
Three POS audit writes use raw `adb.run('INSERT INTO audit_logs ...', ..., JSON.stringify(...))` instead of the shared `audit()` helper in `utils/audit.ts`. The helper enforces a 16 KB cap (`MAX_AUDIT_DETAILS_BYTES`) and strips control characters from the event name. The direct INSERTs bypass both protections. The `pos_return` row at line 2628 serializes `returnDetails` (an array of line items with user-supplied `reason` strings) with no length bound.

**Code:**
```typescript
await adb.run(
  'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
  'pos_return', userId, ip,
  JSON.stringify({ invoice_id: invId, ..., items: returnDetails }),  // unbounded
);
```

**Exploit:**
A cashier processing a return with hundreds of line items or very long `reason` strings can insert a multi-megabyte `details` value into `audit_logs`, bloating the SQLite file and potentially causing the nightly incremental vacuum to stall. Not a direct confidentiality risk but can degrade availability and fill disk.

**Fix:**
Replace all three direct INSERTs with calls to `audit(db, event, userId, ip, details)` from `utils/audit.ts` so the 16 KB cap and event sanitizer apply uniformly.

---

### LOW — Tenant audit_logs lacks user_agent column; master_audit_log also missing UA

**Where:** `packages/server/src/db/migrations/022_audit_logs.sql:1`, `packages/server/src/db/master-connection.ts:126`

**What:**
The tenant `audit_logs` table schema (migration 022) has columns: `id, event, user_id, ip_address, details, created_at`. There is no `user_agent` column. The `audit()` helper signature (`event, userId, ip, details`) also does not accept a UA parameter. By contrast, `tenant_auth_events` (master DB) does store `user_agent`. For post-incident forensics it is frequently necessary to correlate an IP with a browser/client to distinguish human from automated abuse; missing UA makes this impossible in the tenant audit trail. `master_audit_log` likewise has no UA column.

**Code:**
```sql
-- migration 022_audit_logs.sql
CREATE TABLE IF NOT EXISTS audit_logs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    event      TEXT NOT NULL,
    user_id    INTEGER,
    ip_address TEXT,
    details    TEXT,          -- UA would need to go in here as a JSON key, not a column
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

**Exploit:**
After a breach, investigators cannot determine whether actions attributed to a user IP were performed from the user's known browser (legitimate) or a headless script/botnet IP that matched (credential-stuffed session). Forensic reconstruction is severely limited.

**Fix:**
Add a `user_agent TEXT` column to `audit_logs` via a new migration. Extend the `audit()` function signature to accept an optional `ua` string parameter (sourced from `req.headers['user-agent']`). Update call sites for high-sensitivity events (auth, role change, refund, GDPR erase). SQLite TEXT columns have no storage overhead when null, so this is safe to add retroactively.

---

### INFO — 2FA enrollment uses `login_success` event rather than a dedicated `2fa_enrolled` event

**Where:** `packages/server/src/routes/auth.routes.ts:1068`

**What:**
When a user completes 2FA setup for the first time, `audit(db, 'login_success', userId, ip, { method: '2fa_setup' })` is written. This correctly records the login but conflates enrollment with authentication. Querying `SELECT * FROM audit_logs WHERE event = '2fa_enrolled'` returns zero rows; there is no way to list all users who have enrolled 2FA via the audit log alone. This complicates compliance reporting (e.g., "what percentage of users have enrolled 2FA and when?").

**Fix:**
Emit a separate `audit(db, '2fa_enrolled', userId, ip, {})` immediately after line 1054 where `totp_enabled` is set to 1. The existing `login_success` row can remain; the additional row adds precision without removing coverage.

---

### INFO — Audit log retention controlled by env var without an audit-of-change

**Where:** `packages/server/src/index.ts:733`, `2507`

**What:**
`AUDIT_LOG_RETENTION_DAYS` (default 730) is read at startup. Changing this env var silently shortens or extends the retention window. There is no audit row written when the retention window is changed, and no minimum floor is enforced (any integer ≥ 1 is accepted, so `AUDIT_LOG_RETENTION_DAYS=1` would purge 729 days of history on the next 2 AM cron tick). The purge itself (`DELETE FROM audit_logs WHERE created_at < datetime('now', ?)`) leaves no breadcrumb in the audit table.

**Fix:**
Enforce a minimum of 90 days (or a configurable compliance floor). Log a `log.warn` at startup if the configured value is below the minimum. Optionally write an `audit_log_retention_changed` row to the tenant DB at startup when the value differs from the previously-persisted value, creating a record that the window was modified.

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH     | 0 |
| MEDIUM   | 4 |
| LOW      | 3 |
| INFO     | 2 |

**Most significant gap:** Logout is not audited (`packages/server/src/routes/auth.routes.ts:1418`), user disable is not audited (`settings.routes.ts:1228`), and email changes are not audited (`settings.routes.ts:1192`) — three privilege-relevant mutations in the same update endpoint with inconsistent coverage. During impersonation, the tenant audit trail records the *target user* as actor for all subsequent actions, requiring cross-reference with `master_audit_log` to recover the real super-admin identity.
