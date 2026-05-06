# S20 — BlockChyp Payment Terminal Integration

Audited files:
- `packages/server/src/routes/blockchyp.routes.ts`
- `packages/server/src/services/blockchyp.ts`
- `packages/server/src/db/migrations/040_blockchyp.sql`
- `packages/server/src/db/migrations/080_payment_idempotency_and_signature.sql`
- `packages/server/src/db/migrations/099_payment_idempotency_user_scope.sql`
- `packages/server/src/routes/settings.routes.ts` (BlockChyp config GET/PUT)
- `packages/server/src/routes/paymentLinks.routes.ts` (callbackUrl construction)
- `packages/server/src/routes/membership.routes.ts` (chargeToken / enrollCard)
- `packages/server/src/utils/configEncryption.ts` (credential storage)
- `packages/server/src/utils/circuitBreaker.ts` (singleton breaker)

---

### [MEDIUM] Unbounded tip amount allows manager to charge arbitrary tip

**Where:** `packages/server/src/routes/blockchyp.routes.ts:287-306`

**What:**
The `tip` field in POST `/process-payment` is validated only as `typeof tip === 'number' && tip > 0` — there is no upper bound. The tip is added directly to `baseChargeAmount` and dispatched to BlockChyp. A manager (role `manager` or `admin`) can supply `tip: 999999.99` against an invoice with a $1.00 balance and instruct BlockChyp to charge the card $1,000,000.99.

**Code:**
```typescript
const tipAmount = tip && typeof tip === 'number' && tip > 0 ? tip : 0;
// ... no upper-bound check ...
const chargeAmount = baseChargeAmount + tipAmount;
// ...
result = await processPayment(db, chargeAmount, ticketRef, tipAmount > 0 ? tipAmount : undefined);
```

**Exploit:**
A rogue or compromised manager session sends `POST /api/v1/blockchyp/process-payment` with `{ invoiceId: X, tip: 999999.99 }`. BlockChyp receives the charge request for the full amount and, if the card limit allows, authorises it. The customer is billed far beyond the invoice total with no server-side guard.

**Fix:**
Cap `tip` server-side to a reasonable maximum (e.g. 2× `amountDue` or a hard dollar limit such as `$500`). Reject with 400 if `tipAmount > MAX_TIP`. Add a corresponding frontend warning for unusually large tip percentages.

---

### [MEDIUM] No role check on signature-capture endpoints — any authenticated user can trigger terminal T&C flow

**Where:** `packages/server/src/routes/blockchyp.routes.ts:66-116`

**What:**
`POST /capture-checkin-signature` and `POST /capture-signature` have no role guard — only an `isBlockChypEnabled` check. Any authenticated user of any role (including read-only `staff` or `technician`) can invoke these endpoints. `/capture-signature` additionally accepts a `ticketId` from the body and updates `tickets.signature_file` after a successful T&C capture, meaning any user can overwrite the signature record on any ticket they know the ID of.

**Code:**
```typescript
router.post('/capture-checkin-signature', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  if (!isBlockChypEnabled(db)) {           // no role check here
    throw new AppError('BlockChyp terminal is not enabled', 400);
  }
  // ... proceeds to push T&C to the physical terminal
  const result = await capturePreTicketSignature(db);
```

**Exploit:**
A technician-role user sends `POST /api/v1/blockchyp/capture-signature` with `{ ticketId: 999 }` for a ticket they do not own. BlockChyp pushes the configured T&C text to the physical terminal, captures the customer's signature, and the route overwrites `tickets.signature_file` with the new filename — silently replacing a legitimate signature.

**Fix:**
Add `if (req.user?.role !== 'admin' && req.user?.role !== 'manager')` guards on both routes, matching the role gate on `process-payment`. Scope the ticket UPDATE to also confirm ticket ownership/assignment if least-privilege is desired.

---

### [MEDIUM] No role check on `/adjust-tip` — any authenticated user can attempt tip adjustment

**Where:** `packages/server/src/routes/blockchyp.routes.ts:553-579`

**What:**
`POST /adjust-tip` accepts `transaction_id` and `new_tip` from any authenticated user without a role check. The `audit` call on line 569 uses `req.user?.id ?? null`, meaning the audit log can record a null user_id, silently accepting anonymous-looking entries. Although the underlying `adjustTip()` currently returns `NOT_SUPPORTED`, when tip-adjust support is added to the SDK the endpoint will immediately be exploitable by any role.

**Code:**
```typescript
router.post('/adjust-tip', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const { transaction_id, new_tip } = req.body || {};
  if (!isBlockChypEnabled(db)) { /* only gate */ }
  // no role check before calling adjustTip
  const result = await adjustTip(db, transaction_id, new_tip);
  audit(db, 'blockchyp_tip_adjust_attempt', req.user?.id ?? null, ...);
```

**Exploit:**
When BlockChyp SDK ships tip-adjust support and the route body is uncommented, a cashier-level user can call this endpoint with any `transaction_id` and inflate/deflate a tip on a completed transaction without admin approval.

**Fix:**
Add an `admin` or `manager` role check identical to the one on `process-payment`. Fix the audit call to use `req.user!.id` (guarded after the role check) so the event is always attributed to an authenticated user.

---

### [MEDIUM] Host-header injection poisons BlockChyp payment-link callback URL

**Where:** `packages/server/src/routes/paymentLinks.routes.ts:386-388`

**What:**
The public `POST /:token/pay` endpoint (no authentication) constructs the BlockChyp `callbackUrl` by concatenating `req.headers['x-forwarded-host'] || req.headers.host`. Express's `trust proxy` allowlist controls X-Forwarded-For IP attribution but does NOT validate `x-forwarded-host`. An unauthenticated attacker can set this header to an arbitrary hostname, causing BlockChyp to register the callback against an attacker-controlled URL. When the customer completes payment BlockChyp will POST the completion event to the attacker's host, leaking the payment status notification (and any payload fields BlockChyp includes).

**Code:**
```typescript
// public endpoint — no auth
const protocol = req.headers['x-forwarded-proto'] || (req.secure ? 'https' : 'http');
const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
const callbackUrl = `${protocol}://${host}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;
// callbackUrl sent to BlockChyp.sendPaymentLink(request)
```

**Exploit:**
Attacker knows a valid payment-link token (obtained legitimately or via token prediction). They send `POST /api/v1/public/payment-links/<token>/pay` with `X-Forwarded-Host: evil.com`. The registered `callbackUrl` becomes `https://evil.com/…/paid-callback`. On customer payment, BlockChyp fires the webhook to the attacker's server, leaking the completion event.

**Fix:**
Derive the callback host from a server-side config value (`config.baseUrl` or `config.baseDomain`) rather than from a request header. Never trust `x-forwarded-host` from unauthenticated callers.

---

### [MEDIUM] Global BlockChyp circuit breaker is a module-level singleton — cross-tenant DoS in multi-tenant mode

**Where:** `packages/server/src/services/blockchyp.ts:16-20`

**What:**
`blockchypBreaker` and `reconcileBreaker` are created once at module import time and shared across all tenant requests in the same Node process. In multi-tenant mode (`MULTI_TENANT=true`) a single tenant that drives 5 consecutive BlockChyp failures (network issues, bad credentials, or deliberate load) opens the circuit for 60 seconds, causing all other tenants' BlockChyp calls to fast-fail with `CircuitBreakerOpenError`.

**Code:**
```typescript
// module-level singletons — one instance per Node process, not per tenant
const blockchypBreaker = createBreaker('blockchyp');
const reconcileBreaker = createBreaker('blockchyp_reconcile');
// used for ALL tenant charges:
const response = await blockchypBreaker.run(() => client.charge(request));
```

**Exploit:**
An attacker with a legitimate tenant account repeatedly calls `POST /process-payment` using invalid or expired BlockChyp credentials, triggering 5 failures in quick succession. The shared breaker opens and every other tenant on the same server receives payment failures for up to 60 seconds, disabling payment processing for all stores.

**Fix:**
Key the circuit breaker by tenant slug (or by credential hash, since different tenants use different terminals). Create breaker instances lazily in a `Map<string, CircuitBreaker>` indexed by tenant identifier, so one tenant's failures cannot trip another's.

---

### [LOW] No rate limiting on any BlockChyp endpoint

**Where:** `packages/server/src/routes/blockchyp.routes.ts` (all handlers)

**What:**
None of the six BlockChyp route handlers (`/test-connection`, `/capture-checkin-signature`, `/capture-signature`, `/process-payment`, `/void-payment`, `/adjust-tip`) apply `checkWindowRate` or any rate-limiter middleware. The 30-second same-amount dedup window on `process-payment` partially mitigates double-clicks but does not prevent rapid charges of varying amounts on the same invoice, or rapid triggering of T&C signature flows.

**Code:**
```typescript
// No rate limit call before any handler:
router.post('/capture-checkin-signature', asyncHandler(async ...
router.post('/process-payment', asyncHandler(async ...
```

**Exploit:**
A manager with a compromised session can send hundreds of `/capture-checkin-signature` requests per second, tying up the physical terminal and blocking legitimate customer interactions for the duration. For `/process-payment`, varying the `tip` amount each time bypasses the 30-second dedup check.

**Fix:**
Apply `consumeWindowRate` (already used in other sensitive routes) on at minimum `/process-payment` and `/capture-checkin-signature`, with per-user limits (e.g. 10 payment attempts per minute per user_id).

---

### [LOW] T&C signature can be bypassed — sale recorded without terms_audit entry when tcEnabled=true

**Where:** `packages/server/src/routes/blockchyp.routes.ts:131-471` (process-payment), `packages/server/src/db/migrations/` (no migration 159)

**What:**
When `blockchyp_tc_enabled = true`, the intent is to capture customer T&C acceptance before payment. However, `POST /process-payment` contains no check that a T&C signature was previously captured for the ticket. A manager can call `/process-payment` directly, skipping `/capture-checkin-signature` entirely. There is also no `blockchyp_terms_audit` table (migration 159 referenced in the audit plan does not exist), so there is no per-transaction record linking the terms text (`tcContent`) to the signature file at the moment of signing.

**Code:**
```typescript
// process-payment: no check for prior T&C signature
router.post('/process-payment', asyncHandler(async (req: Request, res: Response) => {
  // ... reads invoiceId, tip, amount ...
  // tcEnabled is never consulted here
  result = await processPayment(db, chargeAmount, ticketRef, ...);
```

**Exploit:**
In a dispute, the shop cannot prove the customer accepted the repair terms because: (a) the T&C step was silently skipped, and (b) there is no database record binding the terms text version to the signature file. A customer can credibly claim they never consented.

**Fix:**
When `tcEnabled` is true, `process-payment` should verify that `tickets.signature_file IS NOT NULL` for the associated ticket (or that a `blockchyp_terms_audit` row exists) before dispatching the charge. Separately, create the `blockchyp_terms_audit` table to record `(ticket_id, tc_name, tc_content_hash, signature_file, captured_at, transaction_id)` at T&C capture time.

---

### [INFO] Signature file written from BlockChyp response has no size cap

**Where:** `packages/server/src/services/blockchyp.ts:222-228`

**What:**
`saveSignatureFile` writes `Buffer.from(sigFileHex, 'hex')` to disk without any size validation. A compromised or spoofed BlockChyp gateway response could return a multi-megabyte `sigFile` hex string, consuming arbitrary disk space. No maximum hex length or decoded byte limit is enforced before the `writeFileSync` call.

**Code:**
```typescript
function saveSignatureFile(sigFileHex: string, format: string): SavedSignature {
  const buffer = Buffer.from(sigFileHex, 'hex');  // no length check
  const filename = `sig-${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
  fs.writeFileSync(absolutePath, buffer);          // unbounded write
  return { filename, absolutePath };
}
```

**Exploit:**
An attacker who can MITM or compromise the BlockChyp gateway can return an oversized `sigFile` value, filling the server's disk and causing a DoS for all tenants sharing the same filesystem.

**Fix:**
Add a size guard before writing: `if (sigFileHex.length > MAX_SIG_HEX_LEN) throw new Error(...)` where `MAX_SIG_HEX_LEN` corresponds to a reasonable decoded image size (e.g. 2 MB = 4,000,000 hex chars).

---
