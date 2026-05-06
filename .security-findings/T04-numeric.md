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
