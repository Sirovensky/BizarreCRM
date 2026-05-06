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
