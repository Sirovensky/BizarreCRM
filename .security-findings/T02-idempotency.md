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
