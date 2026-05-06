# S21 — Stripe + Payment Webhook Handlers

**Auditor:** Claude Sonnet 4.6 (security-audit slot 21)
**Scope:** `packages/server/src/services/stripe.ts`, `services/webhooks.ts`, `routes/billing.routes.ts`, `routes/dunning.routes.ts`, `routes/voice.routes.ts`, `routes/blockchyp.routes.ts`, `index.ts` (mount order / rate limiting)

---

### HIGH — Stripe webhook endpoint has no rate limiting

**Where:** `packages/server/src/index.ts:1183` (global rate-limiter skip), `packages/server/src/index.ts:1212` (webhook mount), `packages/server/src/routes/billing.routes.ts:101` (webhookHandler)

**What:**
The global API rate limiter at `index.ts:1181–1207` unconditionally skips every request whose path contains the string `"webhook"` (line 1183: `req.path.includes('webhook')`). The Stripe webhook is mounted at `/api/v1/billing/webhook`, which matches. The per-tenant `billingRateLimit` middleware is only wired to `/checkout` and `/portal`, not to the exported `webhookHandler`. The `webhookRateLimit` helper (line 1538) is also not applied to the billing webhook. Result: the Stripe webhook endpoint receives zero rate limiting.

**Code:**
```typescript
// index.ts:1181-1184
app.use('/api/v1', (req, res, next) => {
  // Skip endpoints that have their own rate limiting
  if (req.path.startsWith('/auth') || req.path.includes('webhook') || ...) {
    return next(); // billing/webhook bypasses global limiter here
  }
  ...
});
// index.ts:1212 — no webhookRateLimit middleware added
app.post('/api/v1/billing/webhook', express.raw({ type: 'application/json', limit: '1mb' }), stripeWebhookHandler);
```

**Exploit:**
An attacker who knows or guesses the webhook URL (it's a well-known path) can flood `/api/v1/billing/webhook` with thousands of requests per second. Each request triggers signature verification (CPU-bound HMAC), body buffering (up to 1 MB), and DB transaction overhead, potentially causing denial of service. Stripe's own webhook IP allowlist is not enforced by the server.

**Fix:**
Apply `webhookRateLimit` to the Stripe webhook mount, or add a separate IP allowlist for [Stripe's documented webhook IPs](https://stripe.com/docs/ips). At minimum: `app.post('/api/v1/billing/webhook', webhookRateLimit, express.raw({...}), stripeWebhookHandler)`.

---

### HIGH — `customer.subscription.updated` sets plan=pro without price ID validation

**Where:** `packages/server/src/services/stripe.ts:897–907`

**What:**
The `customer.subscription.updated` handler unconditionally sets `plan = 'pro'` whenever `sub.status === 'active'`, without inspecting `sub.items.data[*].price.id` against `STRIPE_PRO_PRICE_ID`. This means if Stripe ever fires a `subscription.updated` event for a tenant's subscription that is in `status: 'active'` but on a lower-priced or free plan (e.g. during a downgrade where Stripe marks the old subscription active briefly, or if the operator manually creates a $0 subscription in the Stripe dashboard for testing), the tenant will be granted pro-tier entitlements without actually paying the pro price.

**Code:**
```typescript
case 'customer.subscription.updated': {
  const sub = event.data.object as Stripe.Subscription;
  // ...tenant lookup by stripe_subscription_id...

  if (sub.status === 'active') {
    masterDb.prepare(`UPDATE tenants SET plan = 'pro', ...  WHERE id = ?`)
      .run(tenantWithSub.id);
    // Price ID never checked — any active sub = pro
  }
  ...
}
```

**Exploit:**
An operator creates a test $0 subscription in the Stripe dashboard for a tenant, linking it to the tenant's stripe_subscription_id. When Stripe fires `subscription.updated` with `status: 'active'`, the tenant is upgraded to pro regardless of price. In a forged-signature scenario (extremely unlikely if HMAC verified), it could also be triggered remotely.

**Fix:**
Before setting `plan = 'pro'`, verify `sub.items.data.some(item => item.price.id === config.stripeProPriceId || item.price.id === process.env.STRIPE_ENTERPRISE_PRICE_ID)`. If no matching price is found, skip the upgrade or log a discrepancy alert.

---

### MEDIUM — Outbound webhook secret stored in plaintext despite docstring claiming encryption

**Where:** `packages/server/src/services/webhooks.ts:7` (docstring), `packages/server/src/services/webhooks.ts:255–265` (storage), `packages/server/src/utils/configEncryption.ts:35–46` (ENCRYPTED_CONFIG_KEYS set)

**What:**
The module docstring states: "The secret is auto-generated on first use and stored encrypted via configEncryption." However, `getOrCreateWebhookSecret` directly reads and writes `store_config` via raw SQL without using `getConfigValue` / `encryptConfigValue`. The `'webhook_secret'` key is absent from `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. The secret is therefore stored in plaintext in the tenant SQLite database. If a tenant DB file is exfiltrated (e.g. via a backup or a file path traversal), the attacker obtains the signing key used to authenticate outbound webhook delivery signatures — allowing them to forge webhook deliveries to customers' webhook endpoints.

**Code:**
```typescript
// webhooks.ts:255-266
const existing = db
  .prepare("SELECT value FROM store_config WHERE key = 'webhook_secret'")
  .get() as { value?: string } | undefined;  // no decryption
if (existing?.value) return existing.value;
const candidate = crypto.randomBytes(32).toString('hex');
db.prepare(
  "INSERT OR IGNORE INTO store_config (key, value) VALUES ('webhook_secret', ?)"
).run(candidate);  // stored plaintext, not encryptConfigValue(candidate)
```

**Exploit:**
An attacker who exfiltrates any tenant's SQLite DB file can read `SELECT value FROM store_config WHERE key='webhook_secret'` and use it to forge HMAC-SHA256 signatures on any payload, convincing customer systems that the forged request is a legitimate webhook from BizarreCRM.

**Fix:**
Add `'webhook_secret'` to `ENCRYPTED_CONFIG_KEYS` in `configEncryption.ts`. Update `getOrCreateWebhookSecret` to use `encryptConfigValue(candidate)` on insert and `getConfigValue(db, 'webhook_secret')` on read. Run a one-time migration to re-encrypt existing plaintext values (the auto-encrypt boot sweep in `index.ts:330–338` already handles this for ENCRYPTED_CONFIG_KEYS members).

---

### MEDIUM — `voiceInstructionsHandler` lacks provider signature verification (IRSV/toll fraud risk)

**Where:** `packages/server/src/routes/voice.routes.ts:694–720`, `packages/server/src/index.ts:1562`

**What:**
The `voiceInstructionsHandler` endpoint (`GET /api/v1/voice/instructions/:action`) returns TwiML/TeXML/BXML/NCCO call instructions to the telephony provider. Unlike the four other public voice webhooks (status, recording, transcription, inbound — all at lines 441, 498, 647, 729 of voice.routes.ts), this handler performs **no** `provider.verifyWebhookSignature` check. It reads `req.query.to` — an attacker-supplied phone number — and injects it into a `<Dial>` element. The endpoint is rate-limited to 60/min/IP (via `webhookRateLimit`) but is otherwise unauthenticated.

**Code:**
```typescript
// voice.routes.ts:694-713
export async function voiceInstructionsHandler(req: Request, res: Response): Promise<void> {
  const action = (req.params.action as string) || 'connect';
  const to = (req.query.to as string) || '';  // attacker-controlled
  // No verifyWebhookSignature call
  if (!provider.generateCallInstructions) {
    res.type('text/xml').send(`<Response><Dial>${escapeXml(to)}</Dial></Response>`);
    return;
  }
  const instructions = provider.generateCallInstructions(action, { to, ... });
  res.type('text/xml').send(instructions);
}
```

**Exploit:**
An attacker can call `GET /api/v1/voice/instructions/connect?to=%2B1900XXXXXXX` (a premium-rate number) — if Twilio fetches this URL during a real call and receives TwiML with the attacker's premium number in `<Dial>`, the call is bridged to that number, incurring charges against the merchant's Twilio account. This is the classic IRSV (International Revenue Share Fraud) attack pattern.

**Fix:**
Add `provider.verifyWebhookSignature` to `voiceInstructionsHandler` using the same pattern as the other voice webhook handlers. Additionally, validate `to` against a E.164 phone number regex before embedding it in TwiML.

---

### MEDIUM — No event-type allowlist: unknown Stripe events claim idempotency slot silently

**Where:** `packages/server/src/services/stripe.ts:744–754` (INSERT OR IGNORE), `packages/server/src/services/stripe.ts:757–1074` (switch, no `default:` rejection)

**What:**
`handleWebhookEvent` claims every event — including unrecognized types — via `INSERT OR IGNORE INTO stripe_webhook_events` before dispatching to the switch statement. The switch has no `default:` case. This means any Stripe event type that passes signature verification is permanently claimed in the idempotency table and silently dropped, with no log warning for unknown types, and no opportunity to detect unintended event types sent by mis-configured webhook endpoints (e.g. `charge.succeeded`, `balance.available`, or future Stripe event types that may carry tenant-relevant data).

**Code:**
```typescript
// stripe.ts:744-753
const claimResult = masterDb.prepare(
  `INSERT OR IGNORE INTO stripe_webhook_events (stripe_event_id, event_type, tenant_id)
   VALUES (?, ?, NULL)`
).run(event.id, event.type);  // Claims ALL types before type-checking

if (claimResult.changes === 0) { return { skip: true, tenantId: null }; }

switch (event.type) {
  case 'checkout.session.completed': { ... }
  // ... known events ...
  // No default: case — unknown types silently claimed and dropped
}
```

**Exploit:**
If a new Stripe event type (`e.g. customer.subscription.paused`) is introduced and contains tenant-relevant state, it will be silently consumed. Additionally, operators cannot easily detect when a webhook endpoint is misconfigured to receive unexpected events. Low direct exploitability but creates an observation blindspot.

**Fix:**
Add an explicit allowlist before the INSERT: `const HANDLED_EVENT_TYPES = new Set(['checkout.session.completed', 'customer.subscription.deleted', ...])`. If `!HANDLED_EVENT_TYPES.has(event.type)`, log a warning and return without claiming the idempotency slot. Also add a `default:` case in the switch to log unhandled-but-claimed events.

---

### LOW — BL1 replay window is double-applied with inconsistent semantics

**Where:** `packages/server/src/services/stripe.ts:89` (`WEBHOOK_MAX_AGE_SECONDS = 300`), `packages/server/src/services/stripe.ts:528` (`WEBHOOK_TOLERANCE_SECONDS = 300`), `packages/server/src/services/stripe.ts:711–733`

**What:**
Stripe signature verification (`verifyWebhook`) enforces a 300-second tolerance (`WEBHOOK_TOLERANCE_SECONDS`) on the `t=` timestamp in the `Stripe-Signature` header — this rejects payloads with a signature timestamp older than 5 minutes. Then, `handleWebhookEvent` runs a second 300-second check against `event.created` (the event's Stripe-side creation time). The two checks are semantically different: the signature timestamp is the delivery time; `event.created` is when the event originated in Stripe. These can diverge by minutes for events that Stripe queues internally before delivering. If `event.created` is more than 300 seconds before the delivery attempt (e.g. Stripe retried after a transient server failure), the second check will reject a legitimately signed retry even though `verifyWebhook` accepted it.

**Code:**
```typescript
const WEBHOOK_MAX_AGE_SECONDS = 300;          // handleWebhookEvent age check
const WEBHOOK_TOLERANCE_SECONDS = 300;         // verifyWebhook signature tolerance

// handleWebhookEvent:
const ageSeconds = nowSeconds - eventCreated;  // event.created, not sig timestamp
if (ageSeconds > WEBHOOK_MAX_AGE_SECONDS) {
  logger.error('Rejecting stale Stripe webhook (replay protection)', ...);
  return;  // drops legitimate Stripe retries if event.created > 5 min ago
}
```

**Exploit:**
No direct security exploit; the second check is more restrictive than needed and causes legitimate Stripe webhook retries to fail silently (Stripe retries over hours/days). The real replay protection is the signature timestamp checked by `verifyWebhook` + the `stripe_webhook_events` idempotency table. The `event.created` check adds no security value (signature timestamp is already verified) but does cause service disruption when Stripe retries events.

**Fix:**
Remove the `event.created` age check from `handleWebhookEvent` — the BL2 idempotency table is the correct replay guard, and `verifyWebhook`'s tolerance parameter covers the signature timestamp. If a secondary freshness check is desired, use a much wider window (e.g. 24 hours) and only log rather than reject.

---

### LOW — Stripe webhook `handleWebhookEvent` is not awaited — DB errors return HTTP 200

**Where:** `packages/server/src/routes/billing.routes.ts:110`

**What:**
`handleWebhookEvent(event)` is synchronous (uses better-sqlite3 which is sync), so this is not a correctness issue today. However, the call is not `await`-ed and there is no surrounding try/catch in `webhookHandler` beyond the outer catch block. If `handleWebhookEvent` ever throws (e.g. the master DB is `null` and the null-check on line 706 of stripe.ts is hit — `if (!masterDb) return;`), the throw propagates into the outer try/catch in `webhookHandler`, which correctly returns HTTP 400. But when `masterDb` is null, `handleWebhookEvent` silently returns rather than throwing, and the route still returns HTTP 200 (`{ received: true }`), causing Stripe to believe the event was processed when it was silently dropped.

**Code:**
```typescript
// billing.routes.ts:108-111
try {
  const event = verifyWebhook(req.body, sig);
  handleWebhookEvent(event);    // silent return if masterDb is null
  res.json({ received: true }); // Stripe thinks event was processed
} catch (e) { ... res.status(400)... }
```

**Exploit:**
In single-tenant mode or when the master DB fails to initialize, all Stripe webhook events are silently dropped with HTTP 200. Stripe stops retrying because it received 200. Subscription upgrades, cancellations, and payment failure handling are all lost.

**Fix:**
In `handleWebhookEvent`, throw when `masterDb` is null instead of silently returning: `if (!masterDb) throw new Error('Master DB not available — webhook cannot be processed');`. This causes the outer catch to return HTTP 500, triggering Stripe's retry queue.

---

### INFO — `retryDeliveryFailure` uses original stale timestamp for signature; receivers with freshness windows will reject

**Where:** `packages/server/src/services/webhooks.ts:517–591`

**What:**
When the operator retries a dead-lettered outbound webhook, `retryDeliveryFailure` re-uses the original `payload.timestamp` from the stored failure row to compute the HMAC signature. The comment notes this is intentional so the receiver can verify against a cached original signature. However, if the receiver enforces a freshness window (e.g. "reject signatures older than 5 minutes" — a common pattern for inbound webhook security), the retry will always fail regardless of network conditions. The dead-letter row will keep accumulating retries with no chance of success.

**Code:**
```typescript
// webhooks.ts:537-554
const parsed = JSON.parse(row.payload) as { timestamp?: string };
timestamp = parsed.timestamp;  // could be hours/days old
const signedInput = `${timestamp}.${row.payload}`;
const signature = crypto.createHmac('sha256', secret).update(signedInput).digest('hex');
// Retry with stale timestamp — rejected by freshness-enforcing receivers
```

**Exploit:**
No security impact — this is a reliability/usability issue. Dead-lettered events may be permanently undeliverable after 5+ minutes even when retried manually.

**Fix:**
On retry, generate a fresh `timestamp = new Date().toISOString()`, rebuild the payload with the new timestamp, recompute the signature, and deliver. Document that receivers must not cache signatures for replay detection (the `stripe_event_id` idempotency pattern is the right dedup mechanism, not signature caching).

---

## SCOPE CLEARED — items checked and found safe

- **Raw body parser order:** `express.raw({ type: 'application/json' })` is mounted at `index.ts:1212` *before* `express.json()` at line 1228. The Stripe SDK's `constructEvent` receives an unmodified `Buffer`. Order is correct.
- **Stripe webhook secret in logs:** `billing.routes.ts:118-122` logs only `hasSignature: !!sig` and a generic error message — no secret or signature bytes are emitted. The E4 fix specifically prevents echoing verification details.
- **Stripe webhook secret committed in repo:** `.env` is gitignored; `.env.example` uses placeholder values (`sk_test_...`, `whsec_...`). No live secrets in repo.
- **Event idempotency race:** `INSERT OR IGNORE` + `result.changes === 0` check (BL2) is race-safe under concurrent Stripe retries. The `stripe_webhook_events.stripe_event_id` PRIMARY KEY is the final dedup guarantee.
- **Cross-tenant attack via customer_id:** `checkout.session.completed` uses `client_reference_id` (set at Checkout creation to `tenantId`) for tenant lookup, not the customer ID from the event. The BL12 collision check additionally guards against a forged customer_id pointing to a different tenant.
- **Dunning reading body without re-fetching:** `dunningScheduler.ts` reads from the local `invoices` table, not from Stripe webhook bodies. It is entirely decoupled from Stripe webhook delivery.
- **BlockChyp callback handler:** `blockchyp.routes.ts` has no inbound callback route — BlockChyp is terminal-initiated (outbound only). No unsigned inbound callback surface found.
- **Twilio/SMS webhook signature:** All four SMS/voice inbound handlers (`smsInboundWebhookHandler`, `voiceStatusWebhookHandler`, `voiceRecordingWebhookHandler`, `voiceTranscriptionWebhookHandler`, `voiceInboundWebhookHandler`) call `provider.verifyWebhookSignature` with timing-safe comparison. Exception: `voiceInstructionsHandler` (reported above as MEDIUM).
- **SSRF in outbound webhooks:** `webhooks.ts` implements a thorough `assertWebhookUrl` with DNS resolution of all returned IPs, private range blocking, credential-in-URL rejection, and `redirect: 'error'` on fetch.
