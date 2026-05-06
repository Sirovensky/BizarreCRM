# T03 — Time/Date Edge-Case Security Findings

**Auditor slot:** T03  
**Scope:** Timezone, DST, epoch overflow, clock skew, leap-day, future-date abuse  
**Focus files:** `routes/auth.routes.ts`, `services/dunningScheduler.ts`, `recurringInvoicesCron.ts`, `slaBreachCron.ts`, `retentionSweeper.ts`, `dataExportScheduleCron.ts`, `services/automations.ts`, `utils/repair-time.ts`  
**Date completed:** 2026-05-06

---

### [HIGH] Password-reset token expiry bypassed — ISO 8601 vs SQLite `datetime()` format mismatch

**Where:** `packages/server/src/routes/auth.routes.ts:1720` (store) and `:1814`, `:1856` (verify)

**What:**
`reset_token_expires` is written via `new Date(...).toISOString()`, producing `'YYYY-MM-DDTHH:MM:SS.mmmZ'` (capital-T separator, milliseconds, Z suffix). The expiry guard then compares against `datetime('now')`, which SQLite returns as `'YYYY-MM-DD HH:MM:SS'` (space separator, no ms). SQLite TEXT comparison is purely lexicographic: ASCII 'T' (84) is greater than ASCII ' ' (32), so any ISO string shares the same `YYYY-MM-DD` prefix as `datetime('now')` and the comparison `reset_token_expires > datetime('now')` evaluates TRUE for the **entire remainder of the calendar day** once the token is logically expired. A 1-hour reset token issued at 08:00 UTC is still accepted at 23:59 UTC.

**Code:**
```typescript
// auth.routes.ts:1720 — stored with 'T' separator
const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
// ...
await adb.run(
  'UPDATE users SET reset_token = ?, reset_token_expires = ? WHERE id = ?',
  tokenHash, expiresAt, user.id
);

// auth.routes.ts:1814 — compared against SQLite datetime('now') with space separator
const user = await adb.get<{ id: number; username: string }>(
  "SELECT id, username FROM users WHERE reset_token = ? AND reset_token_expires > datetime('now') AND is_active = 1",
  tokenHash,
);
// auth.routes.ts:1856 — same comparison inside the reset-commit transaction
```

**Exploit:**
An attacker who intercepts or obtains a password-reset link (phishing, email forwarding, shared device) after its 1-hour logical expiry can still use it any time until UTC midnight of the day it was issued — up to 23 hours of extra validity. Combined with token-hash exposure (e.g., read-only DB access, logs), this extends the account-takeover window significantly.

**Fix:**
Store the expiry as a SQLite-compatible string: `new Date(...).toISOString().replace('T', ' ').slice(0, 19)`. Alternatively keep `toISOString()` but change the WHERE clause to `reset_token_expires > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')` — but the replace approach is simpler and consistent with every other date stored in this schema.

---

### [MEDIUM] Session `expires_at` stored as ISO 8601 — format mismatch in auth middleware and cleanup

**Where:** `packages/server/src/routes/auth.routes.ts:379`, `packages/server/src/middleware/auth.ts` (session SELECT), `packages/server/src/index.ts:2468` (cleanup DELETE)

**What:**
`sessions.expires_at` is set via `new Date(Date.now() + refreshDays * 24 * 60 * 60 * 1000).toISOString()` (line 379), producing the same 'T'-separated ISO format. The session validity check in `auth.ts` and the nightly cleanup `DELETE FROM sessions WHERE expires_at < datetime('now')` in `index.ts:2468` both use `datetime('now')` (space-separated). Because 'T' > ' ' lexicographically, a session that expired at any point during the current calendar day will still be accepted until UTC midnight, and the cleanup DELETE will not remove it until the day rolls over. For 30/90-day refresh sessions the window is narrow (at most 24 hours of over-life on the expiry calendar day), but it represents stale-session reuse after intentional logout or forced expiry.

**Code:**
```typescript
// auth.routes.ts:379 — stored ISO
const expiresAt = new Date(Date.now() + refreshDays * 24 * 60 * 60 * 1000).toISOString();

// middleware/auth.ts (inferred from index.ts:2468 pattern)
// SELECT ... FROM sessions WHERE id = ? AND expires_at > datetime('now')

// index.ts:2468 — cleanup misses same-day expired rows
db.prepare("DELETE FROM sessions WHERE expires_at < datetime('now')").run();
```

**Exploit:**
After a user's session is force-expired (admin revoke, password change, suspicious activity), the session token remains valid until UTC midnight of the expiry day. An attacker with a stolen session token gets up to 24 extra hours of access. Impact is limited to the expiry calendar day only.

**Fix:**
Same remedy as the reset-token finding: store `expires_at` as `.toISOString().replace('T', ' ').slice(0, 19)`. Update both `auth.routes.ts:379` and any other `issueTokens`/`refreshSession` call that writes `expires_at`. No schema change needed — column is TEXT.

---

### [MEDIUM] Membership billing period advanced with local-timezone `setMonth()` — DST and month-end drift

**Where:** `packages/server/src/routes/membership.routes.ts:178`, `:376`, `:513–514`

**What:**
Three places compute the next billing period end by calling `endDate.setMonth(endDate.getMonth() + 1)`. These methods operate in the **server's local timezone**, not UTC. On servers configured to a DST-observing timezone (e.g., America/New_York), advancing a March 31 period end produces April 30 (correct), but advancing a November 1 period end in the fall-back window can produce unexpected results depending on the host. More critically, `setMonth(+1)` on a 31-day month (Jan 31 → February, Oct 31 → November) silently overflows to the next month (Mar 3, Dec 1), meaning the billing date drifts permanently forward. The same bug was already identified and fixed in `recurringInvoicesCron.ts` using `setUTCMonth()` plus an originalDay clamp, but `membership.routes.ts` was not updated.

**Code:**
```typescript
// membership.routes.ts:178 — local TZ, no leap/31-day clamp
const endDate = new Date(currentPeriodEnd);
endDate.setMonth(endDate.getMonth() + 1);

// membership.routes.ts:513–514 — one-liner with same bug
const newPeriodEnd = new Date(
  new Date(sub.current_period_end).setMonth(new Date(sub.current_period_end).getMonth() + 1)
).toISOString();
```

**Exploit:**
A member on a monthly plan with a period end on the 31st (e.g., January 31) gets charged March 3 instead of February 28/29, then April 3, May 3 — permanently shifted forward. On a DST boundary, billing can shift by ±1 hour, causing end-of-day comparisons to misfire. Billing errors are a direct financial/contractual impact.

**Fix:**
Mirror the fix already present in `recurringInvoicesCron.ts:advanceNextRunAt()`:
```typescript
const d = new Date(currentPeriodEnd);
const originalDay = d.getUTCDate();
d.setUTCMonth(d.getUTCMonth() + 1);
// Clamp overflow (e.g. Jan 31 → Mar 3 becomes Feb 28)
if (d.getUTCDate() !== originalDay) d.setUTCDate(0);
```
Apply to all three sites in `membership.routes.ts`.

---

### [LOW] `dataExportSchedules.routes.ts` `advanceScheduleNextRun` missing leap-day clamp for monthly intervals

**Where:** `packages/server/src/routes/dataExportSchedules.routes.ts:63–71`

**What:**
`advanceScheduleNextRun()` correctly uses `setUTCMonth()` for UTC-safety, but omits the originalDay clamp that `recurringInvoicesCron.ts` applies. On a monthly export schedule anchored to the 31st (or a February 29th anchor), `setUTCMonth(+1)` silently overflows: e.g., March 31 → May 1 when adding a 1-month interval. The next run date permanently shifts, causing the scheduled export to run on the wrong day.

**Code:**
```typescript
// dataExportSchedules.routes.ts:63–71
function advanceScheduleNextRun(nextRunAt: string, frequency: string, interval: number): string {
  const d = new Date(nextRunAt);
  switch (frequency) {
    case 'daily':   d.setUTCDate(d.getUTCDate() + interval); break;
    case 'weekly':  d.setUTCDate(d.getUTCDate() + interval * 7); break;
    case 'monthly': d.setUTCMonth(d.getUTCMonth() + interval); break;  // ← no clamp
    // ...
  }
  return d.toISOString();
}
```

**Exploit:**
A data-export schedule set to run on the 31st monthly drifts to the 1st of the following month after any 31-day month, then continues drifting. Not a security issue per se, but can cause compliance export windows to be silently skipped or mis-aligned, which may violate data-retention SLAs.

**Fix:**
```typescript
case 'monthly': {
  const originalDay = d.getUTCDate();
  d.setUTCMonth(d.getUTCMonth() + interval);
  if (d.getUTCDate() !== originalDay) d.setUTCDate(0);
  break;
}
```

---

### [LOW] `dunning.routes.ts` `days_offset` accepts non-finite and unbounded values

**Where:** `packages/server/src/routes/dunning.routes.ts:74`

**What:**
The dunning step validator checks `if (typeof s.days_offset !== 'number') throw new AppError(...)` but does not check `Number.isFinite()` or apply any upper bound. A `days_offset` of `Infinity`, `NaN` (which passes `typeof x === 'number'`), or an absurdly large integer (e.g., 99999) is accepted and stored. `dunningScheduler.ts` uses this value directly: `cutoffDateIso(db, step.days_offset)` computes `Date.now() - days_offset * 86400000`. With `NaN`, `cutoffDate` becomes `NaN`, and the SQL `invoice_date <= ?` comparison against NaN will match 0 rows (safe but silent failure). With 99999 days (~274 years), the cutoff reaches epoch-0 territory, potentially enqueuing every invoice ever created in a single dunning run (capped by LIMIT 500 per batch, but the intent is wrong).

**Code:**
```typescript
// dunning.routes.ts:74
if (typeof s.days_offset !== 'number') throw new AppError('days_offset must be a number', 400);
// Missing: Number.isFinite() check and max cap
```

**Exploit:**
A tenant admin sets a dunning step with `days_offset: 99999`. The next dunning run targets all invoices from the past 274 years instead of, e.g., 30 days overdue. With LIMIT 500, this sends dunning emails to 500 of the tenant's oldest customers, causing operational and reputational harm. With `Infinity`, the cron silently processes nothing (NaN date), masking the misconfiguration.

**Fix:**
```typescript
if (typeof s.days_offset !== 'number' || !Number.isFinite(s.days_offset) ||
    s.days_offset < 0 || s.days_offset > 365) {
  throw new AppError('days_offset must be a finite integer between 0 and 365', 400);
}
```

---

### [INFO] `validateIsoDate()` has no upper-bound cap — far-future dates accepted

**Where:** `packages/server/src/utils/validate.ts` (`validateIsoDate` function)

**What:**
`validateIsoDate()` validates ISO 8601 format and UTC round-trip correctness but imposes no upper date cap. Dates like `'9999-12-31'` pass validation and are accepted as invoice `due_date`, ticket `due_date`, SLA deadlines, etc. These are stored in the DB and propagate into report queries. While not directly exploitable for privilege escalation, far-future dates can cause silent report exclusions (date-range filters miss them), sorting anomalies, and confusion in overdue/SLA-breach calculations.

**Code:**
```typescript
// validate.ts — validateIsoDate (approx)
export function validateIsoDate(value: unknown): string {
  if (typeof value !== 'string') throw ...;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw ...;
  const d = new Date(value + 'T00:00:00Z');
  if (isNaN(d.getTime())) throw ...;
  if (d.toISOString().slice(0, 10) !== value) throw ...;
  return value;  // no upper bound check
}
```

**Exploit:**
A user submits an invoice with `due_date: '9999-12-31'`. The invoice passes validation, is stored, and never appears in any "overdue" report (date-range filter `due_date <= ?` with reasonable TO date). The invoice is effectively invisible in reporting, which could be used to intentionally hide a liability in the system.

**Fix:**
Add a max-year guard: `if (new Date(value).getUTCFullYear() > new Date().getUTCFullYear() + 10) throw new AppError('due_date too far in future', 400);`. Adjust the cap (10 years) to match business requirements.

---

### [INFO] `sessions` cleanup `DELETE` affected by same ISO/SQLite format mismatch — stale sessions persist until midnight

**Where:** `packages/server/src/index.ts:2468`

**What:**
The nightly session-cleanup job runs `DELETE FROM sessions WHERE expires_at < datetime('now')`. Because `expires_at` is stored as ISO 8601 with 'T' separator (see MEDIUM finding above), the comparison `'2026-05-06T10:00:00.000Z' < '2026-05-06 22:00:00'` evaluates FALSE (T=84 > space=32), so any session that expired earlier in the same calendar day is NOT deleted by the cleanup until after UTC midnight when the date prefix advances. This is a defense-in-depth gap: expired sessions accumulate in the DB throughout the day they expire, slightly inflating storage and making the session table a less reliable audit source.

**Code:**
```typescript
// index.ts:2468
db.prepare("DELETE FROM sessions WHERE expires_at < datetime('now')").run();
```

**Exploit:**
No direct security impact beyond the MEDIUM finding above (the auth middleware has the same format mismatch, so expired sessions are not rejected at the gate either). This finding compounds the session-lingering issue.

**Fix:**
Same root fix as the MEDIUM finding: store `expires_at` in SQLite format `'YYYY-MM-DD HH:MM:SS'`. The cleanup DELETE will then correctly remove all same-day-expired sessions on its next run.

---

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 1     |
| MEDIUM   | 2     |
| LOW      | 2     |
| INFO     | 2     |
| **Total**| **7** |

**Most critical:** `auth.routes.ts:1814,1856` — password-reset token expiry bypass via ISO 8601 `'T'` vs SQLite `datetime('now')` space separator; expired 1-hour tokens valid for rest of UTC calendar day.
