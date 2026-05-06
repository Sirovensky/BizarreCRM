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
