# S19 — Money Endpoints: IDOR, Amount Tampering, Race Conditions, Sign Confusion

Auditor: slot 19 | Files: refunds, deposits, giftCards, installments, creditNotes, recurringInvoices, invoices, pos, paymentLinks, membership, tradeIns, loyalty, counters, commissions

---

### [HIGH] /pos/return allows unlimited repeat returns against the same line item

**Where:** `packages/server/src/routes/pos.routes.ts:2546`

**What:**
`POST /pos/return` compares the submitted `quantity` against `invoice_line_items.quantity` (the original sale quantity) but never sums previous returns against the same line item. An admin or manager can call the endpoint repeatedly for the same line item, each time receiving a new credit note and stock restoration, until inventory goes negative-infinite and the customer receives multiples of the original credit.

**Code:**
```typescript
if (itemQty > lineItem.quantity) {
  throw new AppError(`Return quantity (${itemQty}) exceeds invoiced quantity (${lineItem.quantity})`, 400);
}
// No check for previously processed returns on this line item
const returnAmount = roundCurrency(itemQty * (unitPrice + unitTax));
creditTotal += returnAmount;
// stock always restored unconditionally
if (lineItem.inventory_item_id) {
  await adb.run(
    'UPDATE inventory_items SET in_stock = in_stock + ? ...',
    itemQty, lineItem.inventory_item_id,
  );
}
```

**Exploit:**
A manager calls `POST /pos/return` twice for the same line item on invoice #1 (qty 1, $500 product). Each call passes the check (`1 <= 1`), issues a $500 credit note, and restores 1 unit of stock. The customer receives $1000 in credits for a $500 purchase; inventory grows by 2 for a single-unit sale.

**Fix:**
Before processing each line item, SUM the `quantity` column from existing credit-note line items (`RETURN: <description>`) linked to the same original `invoice_line_items.id`. Reject if `already_returned_qty + requested_qty > lineItem.quantity`. Alternatively track a `returned_quantity` column on `invoice_line_items`.

---

### [HIGH] /pos/return missing idempotency key — concurrent requests double-process returns

**Where:** `packages/server/src/routes/pos.routes.ts:2496`

**What:**
`POST /pos/return` does not use the `idempotent` middleware (unlike `/pos/transaction` and `/pos/sales` which do). Stock restoration and credit-note creation are executed as separate un-transacted `await adb.run()` calls. Two concurrent identical return requests will both read the same line-item record, both pass all checks, and both issue credit notes + restore stock before either commits.

**Code:**
```typescript
// Line 2496 — no 'idempotent' middleware, no Idempotency-Key guard
router.post('/return', asyncHandler(async (req, res) => {
  // ...
  // Non-atomic: stock restore + credit note are separate awaits
  await adb.run('UPDATE inventory_items SET in_stock = in_stock + ? ...', itemQty, ...);
  // ... then separately ...
  const creditResult = await adb.run('INSERT INTO invoices ... VALUES ...', ...);
```

**Exploit:**
A double-click from the manager UI (or a retry from the Android POS client on a slow connection) fires two simultaneous return requests. Both pass the `itemQty > lineItem.quantity` check because neither has committed yet. Both issue separate credit notes and restore stock, effectively doubling the refund value.

**Fix:**
Add the `idempotent` middleware: `router.post('/return', idempotent, asyncHandler(...))`. Also wrap the stock restoration + credit-note insert in a single `adb.transaction()` batch so partial completion is impossible.

---

### [HIGH] Duplicate `/:id/run-billing` route in membership — second registration (with force override) is dead code

**Where:** `packages/server/src/routes/membership.routes.ts:317` and `:452`

**What:**
The file registers `router.post('/:id/run-billing', ...)` twice. Express matches the first registration (line 317) on every request; the second (line 452) is unreachable dead code. The first handler lacks the `?force=1` override parameter that the second handler implements. This means the force-billing bypass is silently unavailable — but more critically, the idempotency guard in the first handler (`current_period_end > now` → 409) cannot be overridden, causing legitimate admin re-billing of past-due subscriptions to fail permanently once a period slips past due without advancing.

**Code:**
```typescript
// Line 317 — registered FIRST, always wins, no `force` support
router.post('/:id/run-billing', asyncHandler(async (req: Request, res: Response) => {
  // ...
  if (sub.current_period_end) {
    const periodEnd = new Date(sub.current_period_end).getTime();
    if (periodEnd > Date.now()) {
      throw new AppError('Subscription is not yet due for renewal ...', 409);
    }
  }
  // ...
}));

// Line 452 — dead code; never reached
router.post('/:id/run-billing', asyncHandler(async (req: Request, res: Response) => {
  const force = req.query.force === '1';
  if (!force && sub.current_period_end) { ... }
}));
```

**Exploit:**
A misconfigured subscription has `current_period_end` set to a future date even though the card failed. Admin calls `POST /:id/run-billing?force=1` to retry immediately — the request hits the first handler which ignores `?force`, returns 409, and the subscription is permanently stuck in `past_due` unless a developer manually patches the DB row.

**Fix:**
Remove the duplicate route. Merge the `force` parameter logic from the second handler into the first. The first handler should read `const force = req.query.force === '1'` and skip the period-end guard when `force` is true (admin-only action already gated by `requireAdmin`).

---

### [MEDIUM] `POST /api/v1/credit-notes/:id/apply` only decrements `amount_due`, does not update `amount_paid` or `status` — ledger desync

**Where:** `packages/server/src/routes/creditNotes.routes.ts:278–297`

**What:**
When a credit note is applied to an invoice, the handler decrements `invoices.amount_due` but never increments `invoices.amount_paid` or updates `invoices.status` (e.g., from `partial` to `paid`). The invoice's ledger row becomes inconsistent: `amount_paid + amount_due < total`, meaning reports that rely on `amount_paid` for revenue recognition (commission calculation, loyalty accrual, reconciliation) will under-count revenue even after the debt has been fully settled.

**Code:**
```typescript
const newAmountDue = Math.max(0, inv.amount_due - creditDollars);
req.db.transaction(() => {
  req.db.prepare(`
    UPDATE invoices
       SET amount_due = ?,         -- decremented
           updated_at = datetime('now')
     WHERE id = ?
  `).run(newAmountDue, invoiceIdNum);
  // amount_paid is NOT updated; status is NOT updated
  // ...
})();
```

**Exploit:**
Invoice total=$100, amount_paid=$0, amount_due=$100. A $100 credit note is applied: `amount_due` becomes 0 but `amount_paid` stays 0. The invoice status remains `unpaid`. Any cron or report that checks `status IN ('unpaid','partial')` to chase overdue payments will include this invoice. Commission and loyalty point accrual that trigger on `amount_paid` increments will never fire.

**Fix:**
Inside the transaction, also compute and apply `newAmountPaid = Math.min(inv.amount_paid + creditDollars, inv.total)` and update `status` using the same logic as `invoices.routes.ts:800` (`paid` / `partial` / `unpaid`). Mirror what `POST /:id/credit-note` in `invoices.routes.ts:1256` does correctly.

---

### [MEDIUM] `POST /api/v1/installments` — any authenticated user can create installment plans (no role gate)

**Where:** `packages/server/src/routes/installments.routes.ts:38`

**What:**
`POST /api/v1/installments` creates a payment plan binding a customer to pay `total_cents` split across N schedule rows. The only guards are `authMiddleware` (any logged-in user) and a per-user rate limit. A cashier or technician can create installment plans against any customer, setting arbitrary `acceptance_token` (customer name), `acceptance_signed_at`, schedule amounts, and frequency — without manager or admin approval. The cancel endpoint at `POST /:id/cancel` correctly requires admin/manager, but creation does not.

**Code:**
```typescript
// No requirePermission, no requireManagerOrAdmin
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  const rlResult = consumeWindowRate(db, 'installment_create', ...);
  if (!rlResult.allowed) throw new AppError('Too many plan creates — please slow down', 429);
  // ... proceeds to INSERT installment_plans
```

**Exploit:**
A cashier calls `POST /api/v1/installments` with `customer_id=42`, `total_cents=100000`, `installment_count=120`, `schedule=[...]`, `acceptance_token="John Smith"`. An unauthorized $1000/120-month plan is now on record, signed with an arbitrary customer name, which could be used to claim the customer agreed to a payment plan they never saw.

**Fix:**
Add `requirePermission('installments.create')` or an inline `requireManagerOrAdmin(req)` check as the first line of the handler, consistent with the cancel handler's pattern.

---

### [MEDIUM] `POST /pos/sales` (Android endpoint) — no POS PIN requirement unlike `/pos/transaction`

**Where:** `packages/server/src/routes/pos.routes.ts:941`

**What:**
`POST /pos/transaction` uses the `requirePosPinSale` middleware that checks `pos_require_pin_sale` store config and requires the `X-Pos-Pin-Verified: 1` header. `POST /pos/sales` (the Android POS endpoint that accepts cents-based line items) is registered as `router.post('/sales', idempotent, asyncHandler(...))` with no PIN middleware. Both routes complete sales and create invoices/payments. An attacker who obtains a valid JWT (e.g., from a compromised cashier session) can bypass the PIN requirement by calling the Android endpoint directly.

**Code:**
```typescript
// /pos/transaction — has PIN guard
router.post('/transaction', requirePosPinSale, idempotent, asyncHandler(async (req, res) => {

// /pos/sales — no PIN guard
router.post('/sales', idempotent, asyncHandler(async (req, res) => {
```

**Exploit:**
Store enables `pos_require_pin_sale`. Attacker has a stolen cashier JWT. They POST to `/api/v1/pos/sales` with a full cart. The sale completes, stock decrements, invoice is created — PIN check entirely bypassed.

**Fix:**
Add `requirePosPinSale` middleware to the `/sales` route: `router.post('/sales', requirePosPinSale, idempotent, asyncHandler(...))`.

---

### [MEDIUM] `/pos/sales` misc lines accept client-supplied `tax_rate` (0..1 fraction) — attacker can set tax to zero

**Where:** `packages/server/src/routes/pos.routes.ts:1086–1093`

**What:**
For misc/custom lines (no `item_id`) in `/pos/sales`, the server honors a client-supplied `tax_rate` field (expected to be a fraction 0..1 from the Android DTO). Any cashier can set `tax_rate: 0` for any misc line item, bypassing tax collection entirely. There is no allowlist of valid rates, no verification against `tax_classes`, and no role check on the field.

**Code:**
```typescript
} else {
  // No tax class on the inventory item OR misc line: honor client tax_rate
  const cliRate = Number(ln?.tax_rate);
  if (Number.isFinite(cliRate) && cliRate > 0 && cliRate < 1) {
    lineTax = roundCents(lineNet * cliRate);
  }
  // cliRate = 0 accepted silently → lineTax = 0
}
```

**Exploit:**
A cashier rings up a $500 labor charge as a misc line with `tax_rate: 0` (or simply omits `tax_rate`). No tax is collected. For a shop in a 10% sales-tax jurisdiction this is $50 in unpaid tax per transaction. The cashier could do this intentionally to discount a customer or accidentally, with no audit trail flagging the zero-tax sale.

**Fix:**
Remove client-supplied `tax_rate` from misc lines. Instead, require callers to pass a `tax_class_id` for taxable misc items and look up the rate server-side. If a legacy fallback is needed, restrict non-zero client rates to admin/manager roles and add an audit log entry whenever a client-supplied rate is used.

---

### [MEDIUM] `POST /pos/return` is not transactional — partial failure leaves orphaned stock movements

**Where:** `packages/server/src/routes/pos.routes.ts:2558–2636`

**What:**
The return handler iterates line items and for each one issues an `UPDATE inventory_items` and an `INSERT stock_movements` as separate `await adb.run()` calls outside any transaction. The credit note INSERT and refund INSERT are also separate calls. If the server crashes or a later line item lookup fails mid-loop, some items will have had their stock restored without a matching credit note or refund record, permanently inflating inventory without any financial record.

**Code:**
```typescript
for (const item of items) {
  // ...
  if (lineItem.inventory_item_id) {
    await adb.run('UPDATE inventory_items SET in_stock = in_stock + ? ...', ...); // not in tx
    await adb.run('INSERT INTO stock_movements ...', ...);                         // not in tx
  }
  returnDetails.push(...);
}
// only AFTER the loop:
const creditResult = await adb.run('INSERT INTO invoices ...', ...);  // not in tx
await adb.run('INSERT INTO refunds ...', ...);
```

**Exploit:**
A return is submitted for 3 line items. Item 2 causes a DB error mid-loop. Item 1's stock has been restored and its movement recorded; items 2 and 3 have not. No credit note was created. The shop's inventory is now over by 1 unit with no matching financial record.

**Fix:**
Build all stock restoration UPDATEs, movement INSERTs, credit note INSERT, and refund INSERT as a `TxQuery[]` batch and execute via `adb.transaction()` once, mirroring the pattern in `/pos/transaction`.

---

### [MEDIUM] Overpayment store-credit upsert in `POST /invoices/:id/payments` is not atomic — race condition

**Where:** `packages/server/src/routes/invoices.routes.ts:828–843`

**What:**
When a payment results in an overpayment, the handler does a `SELECT` on `store_credits` followed by either an `UPDATE` or `INSERT` as two separate `await adb.run()` calls. Two concurrent overpayment payments on the same invoice can both read the same SELECT (no row → INSERT path), then both INSERT a store_credits row for the same customer, violating the expected one-row-per-customer model. The UPSERT pattern already used correctly in `refunds.routes.ts:385` is not applied here.

**Code:**
```typescript
const existingCredit = await adb.get<...>('SELECT id, amount FROM store_credits WHERE customer_id = ?', ...);
if (existingCredit) {
  await adb.run("UPDATE store_credits SET amount = ?, ...", roundCents(...), existingCredit.id);
} else {
  await adb.run('INSERT INTO store_credits (customer_id, amount) VALUES (?, ?)', ...);
}
```

**Exploit:**
Two simultaneous payments on the same invoice both trigger the overpayment path. Both read no existing store_credits row. Both INSERT a new row. The customer now has two store_credits rows; subsequent balance reads with `SUM` would work but the UNIQUE constraint (if present) would explode with an unhandled 500.

**Fix:**
Replace the SELECT+INSERT/UPDATE pattern with the same atomic UPSERT already used in `refunds.routes.ts:385`:
```sql
INSERT INTO store_credits (customer_id, amount, ...)
VALUES (?, ?, ...)
ON CONFLICT(customer_id) DO UPDATE SET amount = amount + excluded.amount, ...
```

---

### [LOW] `POST /api/v1/credit-notes` (standalone table) — any authenticated user can create credit notes for unlimited amounts

**Where:** `packages/server/src/routes/creditNotes.routes.ts:163`

**What:**
`POST /api/v1/credit-notes/` creates credit note records in the `credit_notes` table (as opposed to the negative-invoice credit notes in `invoices.routes.ts`). The create handler uses `writeRateLimit()` but has no role gate — any authenticated user can create credit notes of any `amount_cents`. The `GET` and apply/void endpoints require manager/admin, but the creation endpoint does not.

**Code:**
```typescript
router.post('/', asyncHandler(async (req, res) => {
  if (!req.user) throw new AppError('Not authenticated', 401);
  writeRateLimit(req);
  // ... no requireManagerOrAdmin check
  const safeCents = typeof amount_cents === 'number' ? amount_cents : parseInt(...);
  if (!Number.isInteger(safeCents) || safeCents <= 0) { throw ... }
  // INSERT credit_notes with safeCents
```

**Exploit:**
A cashier creates a $10,000 credit note for any customer with one API call. While the credit note itself isn't immediately redeemable (apply requires manager/admin), its existence in the system could mislead reconciliation reports or be used as social engineering evidence.

**Fix:**
Add `requireManagerOrAdmin(req)` as the first line of `POST /` handler, consistent with the apply and void endpoints.

---

### [LOW] `POST /membership/subscribe` records `last_charge_amount = tier.monthly_price` without actually charging — inflated billing history

**Where:** `packages/server/src/routes/membership.routes.ts:191–210`

**What:**
The subscribe endpoint sets `last_charge_at = start` and `last_charge_amount = tier.monthly_price` at INSERT time, without triggering any actual payment. A subscription payment row is inserted with `status = 'success'` even though no charge occurred. This corrupts the billing history: the first genuine charge via `run-billing` will appear as a *second* charge of `monthly_price`, making the customer's receipt history show they were charged twice for the first period.

**Code:**
```typescript
result = await adb.run(
  `INSERT INTO customer_subscriptions (..., last_charge_at, last_charge_amount)
   VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?)`,
  customer_id, tier_id, blockchyp_token, start, end, signature_file, start, tier.monthly_price
);
// Then immediately:
await adb.run(
  'INSERT INTO subscription_payments (subscription_id, amount, status) VALUES (?, ?, ?)',
  result.lastInsertRowid, tier.monthly_price, 'success'  // no actual charge
);
```

**Exploit:**
Customer subscribes at $29.99/mo. Subscription row created with `last_charge_amount=29.99`, and a `subscription_payments` row with `status='success'` and `amount=29.99`. No money moves. One month later, `run-billing` charges $29.99 and inserts another `subscription_payments` row. Customer's portal shows two "$29.99 success" entries; they dispute the double charge.

**Fix:**
On initial subscribe, only insert the subscription row. Omit `last_charge_amount`/`last_charge_at` (or set them to NULL). Do not insert a `subscription_payments` row unless `blockchyp_token` is present and a real charge is actually attempted. Record the enrollment separately with a distinct `type='enrollment'` column.

---

### [INFO] Installments schedule sum vs. total_cents uses integer equality — float drift possible

**Where:** `packages/server/src/routes/installments.routes.ts:83–89`

**What:**
The schedule sum validation uses `scheduleSum !== total_cents` (strict equality on JavaScript numbers). Both values come from `Number(row.amount_cents)` conversions. If a client sends floats (e.g., `amount_cents: 33.33`), `Number()` preserves the float and the sum may drift by a fraction of a cent, causing legitimate plans to be rejected or (if the caller rounds differently) accepted with a 1-cent shortfall.

**Code:**
```typescript
const scheduleSum = schedule.reduce(
  (acc: number, row: any) => acc + (Number(row.amount_cents) || 0), 0
);
if (scheduleSum !== total_cents) {
  throw new AppError(`schedule amounts sum to ${scheduleSum} but total_cents is ${total_cents}...`, 400);
}
```

**Exploit:**
Low severity — mainly an API usability issue. No financial impact since amounts are stored as-is and the mismatch guard rejects the request. However, a rounding-aware client could bypass the check by sending `amount_cents: 33.333...` repeated, summing to `total_cents: 99.999`, which `Number()` may round identically or differently depending on JS engine float representation.

**Fix:**
Add `Math.floor()` or `Math.round()` to each `amount_cents` in the reduce, and compare `Math.round(scheduleSum)` to `Math.round(total_cents)`. Also add an explicit integer check on each schedule row: `if (!Number.isInteger(amountCents)) throw AppError(...)` before summing.

---
