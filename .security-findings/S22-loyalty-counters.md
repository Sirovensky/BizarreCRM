# S22 — Loyalty, Store Credit, Counters, Commissions

Audit date: 2026-05-05
Files examined: `packages/server/src/utils/loyalty.ts`, `utils/counters.ts`, `utils/commissions.ts`,
`utils/currency.ts`, `utils/validate.ts`, `services/notifications.ts`, `routes/invoices.routes.ts`,
`routes/refunds.routes.ts`, `routes/pos.routes.ts`, `routes/giftCards.routes.ts`,
`routes/tradeIns.routes.ts`, `routes/portal-enrich.routes.ts`, `routes/team.routes.ts`,
`db/migrations/028_gift_cards.sql`, `089_portal_enrichment.sql`, `109_store_credits_unique_customer.sql`,
`111_commissions_unique_non_reversal.sql`, `119_commissions_unique_invoice_non_reversal.sql`,
`072_counters_and_constraints.sql`, `db/db-worker.mjs`, `db/worker-pool.ts`, `db/async-db.ts`.

---

### HIGH — Loyalty points earned per payment with no idempotency guard: same invoice can be credited twice

**Where:** `packages/server/src/services/notifications.ts:45–89` (accruePaymentPoints), called from
`packages/server/src/routes/invoices.routes.ts:142` and `routes/pos.routes.ts:878,1308`

**What:**
`accruePaymentPoints` inserts a row into `loyalty_points` every time it is called. There is no UNIQUE
constraint on `(reference_type, reference_id)` in the `loyalty_points` table (migration 089 only adds a
non-unique index). The idempotency middleware (`X-Idempotency-Key`) is optional and client-supplied, so
an unauthenticated retry or a client that does not send the header will POST to `/:id/payments` a second
time, triggering a second `accruePaymentPoints` call for the same `invoiceId` and earning duplicate
loyalty points. The `writeLoyaltyPoints` function itself has no "already earned for this reference_id"
check.

**Code:**
```typescript
// notifications.ts:66-75
const points = computeEarnedPoints(paymentAmount, rate);
if (points <= 0) return 0;

await writeLoyaltyPoints(adb, {
  customer_id: customerId,
  points,
  reason: reason || `Payment on invoice #${invoiceId}`,
  reference_type: 'invoice',
  reference_id: invoiceId,   // ← no UNIQUE index → second call inserts second row
});
```

**Exploit:**
A cashier (or the customer via portal) submits payment for an invoice twice (network error + retry without
an idempotency key, or a double-click). Each request passes the double-submit guard (10-second window)
and calls `accruePaymentPoints`, inserting two earn rows for the same invoice — doubling the customer's
loyalty balance at zero additional cost.

**Fix:**
Add a UNIQUE partial index on `loyalty_points(reference_type, reference_id)` WHERE
`reference_type = 'invoice'` (migration), and wrap the `writeLoyaltyPoints` insert in an
`INSERT OR IGNORE` (or catch `SQLITE_CONSTRAINT_UNIQUE` in the caller) so duplicate calls for the same
invoice silently no-op. Alternatively, require and validate the `X-Idempotency-Key` header on all
payment endpoints.

---

### HIGH — `reverseLoyaltyPoints` is exported but never called: refund/void paths do not claw back loyalty points

**Where:** `packages/server/src/services/notifications.ts:112–167` (definition), `routes/refunds.routes.ts`
(approve path, lines 241–395), `routes/invoices.routes.ts` (void path, lines 874–954), `routes/pos.routes.ts`
(return path, lines 2496–2636)

**What:**
`reverseLoyaltyPoints` was implemented to claw back earned points when a refund or void is processed.
However, a global grep for all callers shows it is ONLY declared — it is never imported or invoked anywhere
in the codebase. The refund approval path in `refunds.routes.ts` reverses commissions (`reverseCommission`)
but makes zero loyalty calls. The invoice void path similarly skips loyalty reversal. The POS return
(`/pos/return`) also writes no loyalty row. As a result, a customer can earn points on a payment, then
obtain a full refund and keep the points permanently.

**Code:**
```typescript
// notifications.ts:112 — exported but never imported by any route
export async function reverseLoyaltyPoints(
  input: ReversePointsInput,
): Promise<number> { ... }

// refunds.routes.ts:342 — only commission reversal, no loyalty reversal
const reversedCount = await reverseCommission(adb, {
  sourceType: 'invoice',
  sourceId: refund.invoice_id,
  fraction: refundFraction,
  at: now(),
});
// <-- no call to reverseLoyaltyPoints here
```

**Exploit:**
Customer pays invoice → earns 100 loyalty points → requests refund → refund is approved → customer
receives their money back but retains 100 loyalty points. This is a monetary loss for the merchant on
every refunded transaction where the customer has loyalty enabled.

**Fix:**
Import `reverseLoyaltyPoints` in `refunds.routes.ts`, `invoices.routes.ts` (void path), and
`pos.routes.ts` (return path). Call it (best-effort, post-transaction) with the same `fraction`
proportional logic used by `reverseCommission`. Mirror the pattern: catch errors and log rather than
propagating to avoid rolling back an already-committed refund.

---

### MEDIUM — Store credit overpayment in `invoices.routes.ts` uses SELECT-then-UPDATE without ON CONFLICT

**Where:** `packages/server/src/routes/invoices.routes.ts:828–844`

**What:**
When an invoice payment results in an overpayment, the code reads the `store_credits` row for the
customer (`SELECT id, amount`) and then either UPDATEs or INSERTs. Although migration 109 added a
`UNIQUE(customer_id)` constraint to `store_credits`, the code performs this as two separate async
operations (`adb.get` followed by `adb.run`) outside any transaction, leaving a TOCTOU window. If two
concurrent overpayment flows for the same customer race, both may execute the SELECT (both see
`existingCredit = null`), and both INSERT, causing the second INSERT to fail with
`SQLITE_CONSTRAINT_UNIQUE` — which is then caught by the outer `try/catch` and silently logged, dropping
one of the store-credit grants. The `refunds.routes.ts` path (line 385) uses `ON CONFLICT DO UPDATE` and
is safe, but this invoice path does not.

**Code:**
```typescript
// invoices.routes.ts:828-844
const existingCredit = await adb.get<{ id: number; amount: number }>(
  'SELECT id, amount FROM store_credits WHERE customer_id = ?',
  invoice.customer_id,
);
if (existingCredit) {
  await adb.run(
    "UPDATE store_credits SET amount = ?, updated_at = ...",  // ← SET to computed value, not += delta
    roundCents((existingCredit.amount || 0) + overpayment),  // ← stale read risk
    existingCredit.id,
  );
} else {
  await adb.run('INSERT INTO store_credits (customer_id, amount) VALUES (?, ?)', ...);
  // ← no ON CONFLICT → fails silently if concurrent insert wins race
}
```

**Exploit:**
Two simultaneous overpayment payments (e.g. network retry or bulk-mark-paid loop) for the same customer.
Both see no existing row. First INSERT commits. Second INSERT fails silently → second overpayment amount
is lost. Additionally, if `existingCredit` is read stale (another concurrent update between SELECT and
UPDATE), the SET overwrites the concurrent write.

**Fix:**
Replace the two-step SELECT+UPDATE/INSERT with a single atomic `INSERT INTO store_credits ... ON CONFLICT(customer_id) DO UPDATE SET amount = amount + excluded.amount` (as already done in `refunds.routes.ts:385`). This removes the race entirely and matches the pattern already used on the safe path.

---

### MEDIUM — `reverseCommission` runs multiple awaited `adb.run` calls outside a transaction: concurrent reversal can interleave

**Where:** `packages/server/src/utils/commissions.ts:213–263`

**What:**
`reverseCommission` iterates over existing commission rows and calls `await adb.run(INSERT ...)` for each
one in a plain `for` loop — one async DB call per reversal row, with no wrapping transaction. Each
`adb.run` dispatches to a Piscina worker thread, which means a concurrent request running between
iterations could read the commission table in a partially-reversed state, or a payroll-lock check could
flip between the `isCommissionLocked` call and the first INSERT. On a ticket with 3 commission rows, 3
separate worker messages are sent; another thread could INSERT a new commission row between messages 1
and 2, which would then not be reversed.

**Code:**
```typescript
// commissions.ts:244-260
const clampedFraction = Math.min(1, Math.max(0, fraction));
let written = 0;
for (const row of rows) {
  const reversalAmount = roundCents(-row.amount * clampedFraction);
  if (reversalAmount === 0) continue;
  await adb.run(         // ← individual async call per row, outside a transaction
    `INSERT INTO commissions ...`,
    ...
  );
  written++;
}
```

**Exploit:**
A ticket with two commission rows is partially reversed. Between reversal INSERTs, a concurrent ticket
re-open writes a new forward commission row. That row escapes reversal. On a refund, the technician
receives a commission they should not.

**Fix:**
Collect all reversal `INSERT` params into an `adb.transaction(queries)` batch so all reversals commit
atomically (or all roll back). This is already the pattern used in `writeLoyaltyPoints` for the spend path.

---

### MEDIUM — `computeEarnedPoints` uses float × float: points for high-value invoices accumulate float error

**Where:** `packages/server/src/utils/loyalty.ts:183–190`

**What:**
`computeEarnedPoints(amountPaid, pointsPerDollar)` returns `Math.floor(amountPaid * pointsPerDollar)`.
Both inputs are JS `number` (float64). `amountPaid` comes from `validatePositiveAmount` which returns a
float dollar amount (e.g. `123.45`). For a $9999.99 invoice at 10 pts/$, the product is
`9999.99 * 10 = 99999.90000000001` in IEEE-754, floored to `99999` — correct here, but at extreme values
(e.g. `amountPaid = 999999.99`, `pointsPerDollar = 1000`) the product is `999999990` which fits in a
JS integer safely, but at `pointsPerDollar = 9007199` the product overflows `Number.MAX_SAFE_INTEGER`
silently, producing an incorrect integer. No upper bound is enforced on `pointsPerDollar` (it comes from
`store_config` as a raw `parseFloat`).

**Code:**
```typescript
// loyalty.ts:189
return Math.floor(amountPaid * pointsPerDollar);
// amountPaid = max 999999.99 (validatePositiveAmount cap)
// pointsPerDollar = uncapped parseFloat from store_config
// product can exceed Number.MAX_SAFE_INTEGER (2^53 - 1) with no error
```

**Exploit:**
An admin sets `portal_loyalty_rate` to a very large value (e.g. `9007199254741`). The next payment
results in `Math.floor(1 * 9007199254741) = 9007199254741` points written in a single ledger row —
which overflows `Number.MAX_SAFE_INTEGER` for larger rates, producing silently wrong points values and
potential integer truncation in the SQLite `INTEGER` column (SQLite integers cap at 64-bit signed).

**Fix:**
Validate `portal_loyalty_rate` on write (admin settings route) to be a positive integer in a sane range
(e.g. 1–10000). In `computeEarnedPoints`, also cap `pointsPerDollar` to a maximum before multiplication.
Consider keeping the computation in integer space: `Math.floor((Math.round(amountPaid * 100) * pointsPerDollar) / 100)`.

---

### MEDIUM — Loyalty reversal TOCTOU: `reverseLoyaltyPoints` reads balance then calls `writeLoyaltyPoints` in separate async round-trips

**Where:** `packages/server/src/services/notifications.ts:120–145`

**What:**
`reverseLoyaltyPoints` reads the current balance with one `adb.get` (SELECT SUM), then calls
`writeLoyaltyPoints` (which itself runs a conditional INSERT). Between the SELECT and the INSERT, a
concurrent redemption (spend) could drain the balance to zero. The `writeLoyaltyPoints` spend path does
guard against going negative (atomic conditional INSERT), but the `reverseLoyaltyPoints` function
computes `toReverse = Math.min(current, Math.floor(points))` using the stale `current` value, then
calls the spend path with `points: -toReverse`. If the balance dropped to 0 between the read and the
write, the spend path's conditional INSERT rejects with `Insufficient loyalty balance` (throws an error),
which is caught and swallowed by the outer try/catch in `reverseLoyaltyPoints` — causing the reversal to
silently succeed (return 0 reversed) without actually reversing anything. The fix is moot since
`reverseLoyaltyPoints` is never called (see finding above), but documenting for when it is wired in.

**Code:**
```typescript
// notifications.ts:120-136
const balanceRow = await adb.get<...>(
  `SELECT COALESCE(SUM(points), 0) AS balance FROM loyalty_points WHERE customer_id = ?`,
  customerId,
);
const current = Number(balanceRow?.balance ?? 0);
// ... concurrent redemption can drain `current` to 0 here ...
const toReverse = Math.min(current, Math.floor(points));
await writeLoyaltyPoints(adb, { points: -toReverse, ... });  // may throw if balance changed
```

**Exploit:**
Customer earns 100 points. Refund is initiated. Simultaneously, customer redeems 100 points via portal.
The reversal reads balance=100, the redemption commits -100, the reversal then tries to write -100 (but
balance is now 0) → conditional INSERT rejects → reversal is silently dropped. Customer redeems their
earned points AND gets the refund, keeping both.

**Fix:**
Use the same atomic conditional INSERT approach already in `writeLoyaltyPoints` for the reversal path,
but clamp the reversal inside SQLite rather than in JS: `INSERT ... SELECT -MIN(SUM(points), ?) WHERE
SUM(points) > 0`. This makes the clamping and the write atomic.

---

### LOW — `tradeIns.routes.ts` comment incorrectly claims store_credits has no UNIQUE constraint; SELECT-then-INSERT outside transaction

**Where:** `packages/server/src/routes/tradeIns.routes.ts:296–337`

**What:**
The comment at line 296 states "store_credits has no UNIQUE(customer_id) constraint". This was true
before migration 109, which added `CREATE UNIQUE INDEX idx_store_credits_customer_unique ON
store_credits(customer_id)`. The actual code performs an `adb.get` to check for an existing row, then
queues either an UPDATE or INSERT into a transaction batch — a pattern that can still race if two
concurrent trade-in accepts fire for the same customer, both see no existing credit row, and both queue
an INSERT. The UNIQUE constraint introduced in migration 109 will cause the second INSERT to fail and
roll back the entire transaction, which is better than silent corruption but loses the credit for the
customer. Additionally, the UPDATE uses `amount + ?` (delta), not a SET-to-computed-value — so that
path is race-safe. Only the INSERT path is at risk.

**Code:**
```typescript
// tradeIns.routes.ts:305-321
const existingCredit = await adb.get<{ id: number }>(
  'SELECT id FROM store_credits WHERE customer_id = ?',
  existing.customer_id,
);
if (existingCredit) {
  tx.push({ sql: 'UPDATE store_credits SET amount = amount + ? ... WHERE id = ?', ... }); // safe
} else {
  tx.push({ sql: 'INSERT INTO store_credits (customer_id, amount, ...) VALUES (?, ?, ...)', ... });
  // ← will fail with UNIQUE violation under concurrent trade-in accepts; tx rolls back, credit lost
}
```

**Exploit:**
Two trade-in accept requests for the same customer race. Both see no existing row. Both queue an INSERT.
The second INSERT hits the UNIQUE constraint, rolling back the trade-in status update and the store
credit — leaving the trade-in in an inconsistent state.

**Fix:**
Replace the SELECT+INSERT/UPDATE pattern with `INSERT INTO store_credits ... ON CONFLICT(customer_id)
DO UPDATE SET amount = amount + excluded.amount`, mirroring `refunds.routes.ts:385`. Update the stale
comment to note the UNIQUE constraint added in migration 109.

---

### LOW — Commission `computeCommissionCents`: `rate` stored as float percentage (e.g. 10.5) is converted to bps with `Math.round(rate * 100)` — rounding hazard at high rate values

**Where:** `packages/server/src/utils/commissions.ts:126`

**What:**
`commission_rate` is stored in the DB as a float (`REAL`, migration 017). `computeCommissionCents`
converts the percentage to basis points with `Math.round(rate * 100)`. For `rate = 10.1`,
`10.1 * 100 = 1009.9999...` rounds to `1010 bps` (10.10%) rather than `1010 bps` — this is correct.
However, for `rate = 10.7`, `10.7 * 100 = 1070.0000000001` rounds correctly, but for some IEEE-754
edge cases (e.g. `rate = 49.9`, `49.9 * 100 = 4990.000000001`) the rounding is correct. The actual
residual risk is that there is no enforcement of an upper bound on `commission_rate` — a value > 100
(e.g. `commission_rate = 150`) produces `15000 bps` and `calcCommissionCents` would apply a 150%
commission rate, paying the technician more than the invoice total. There is no route that validates
`commission_rate <= 100` before writing it.

**Code:**
```typescript
// commissions.ts:126
const rateBps = Math.round(rate * 100);  // rate = DB float, no upper bound enforced
return calcCommissionCents(rateBps, Math.max(0, commissionableCents));
// If rate = 150.0, rateBps = 15000, commission = 1.5x the commissionable base
```

**Exploit:**
An admin (or a compromised admin account) sets a technician's `commission_rate` to 150. On a $1000
ticket, the technician earns $1500 in commissions. No server-side validation on the write path prevents
this. The DB column has no `CHECK(commission_rate BETWEEN 0 AND 100)` constraint.

**Fix:**
Add validation on the user-edit path (wherever `commission_rate` is written, which appears to be only
via direct DB update or future settings route) to reject values outside `[0, 100]`. Add a DB CHECK
constraint in a migration: `ALTER TABLE users ADD CHECK(commission_rate BETWEEN 0 AND 200)` (or a
tighter 0–100 range, noting flat rates are in dollars not percent). Add the check in
`computeCommissionCents`: if `type` is `percent_ticket/percent_service` and `rate > 100`, clamp or throw.

---

### INFO — `currency.ts` is a thin one-liner; arithmetic safety relies entirely on callers using `roundCents` from `validate.ts`

**Where:** `packages/server/src/utils/currency.ts:1–4`

**What:**
The `currency.ts` module exports only `roundCurrency(value)` (two-decimal round). The real arithmetic
safety helpers (`roundCents`, `toCents`, `fromCents`) live in `validate.ts`. Multiple call sites across
the codebase import from different places — `roundCurrency` from `currency.ts` in `giftCards.routes.ts`
and `roundCents` from `validate.ts` in commissions and invoices routes. Both do the same `Math.round(v *
100) / 100` computation. The split creates a risk that a new developer adds a currency operation using
`roundCurrency` (which operates on dollar floats) instead of keeping everything in integer cents.

**Code:**
```typescript
// currency.ts:1-4 — entire file
export function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}
```

**Fix:**
Consolidate `roundCurrency` into `validate.ts` (or vice versa) so there is a single canonical money
utility module. Mark `currency.ts` as deprecated and update callers. Consider adding a lint rule or
barrel export to enforce the single import point.

---

### INFO — No DB-level unique constraint on `loyalty_points(customer_id, reference_type, reference_id)` to prevent double-earn at DB layer

**Where:** `packages/server/src/db/migrations/089_portal_enrichment.sql:44–55`

**What:**
The `loyalty_points` table has only a non-unique composite index on `(reference_type, reference_id)`.
There is no uniqueness constraint preventing two earn rows with the same `(customer_id, reference_type,
reference_id)` tuple. Application-level guards (idempotency middleware) are optional. Commission rows
have UNIQUE partial indexes (migrations 111 and 119) protecting against double-write — no equivalent
protection exists for loyalty points.

**Fix:**
Add `CREATE UNIQUE INDEX IF NOT EXISTS idx_loyalty_points_reference_unique ON loyalty_points(customer_id, reference_type, reference_id) WHERE reference_type IN ('invoice', 'referral')` and update `writeLoyaltyPoints` to use `INSERT OR IGNORE` (earn path) so idempotent calls are no-ops rather than errors. Redemption and manual rows should remain unconstrained.

---
