# S04 — POS PIN Authentication

## Findings

---

### [HIGH] `/pos/sales` sale endpoint bypasses `requirePosPinSale` middleware

- File: `packages/server/src/routes/pos.routes.ts:941`
- Description: `POST /pos/transaction` (line 253) is gated by `requirePosPinSale`. `POST /pos/sales` (line 941) is a parallel sale-completion path — it creates invoices, processes payments, decrements stock, and records employee tips — but carries **no** `requirePosPinSale` middleware and no inline PIN check. When `pos_require_pin_sale` is enabled in `store_config`, the intended PIN gate is fully bypassed by calling `/pos/sales` instead of `/pos/transaction`.
- Exploit: An authenticated POS user (any role including cashier) calls `POST /pos/sales` directly. The `pos_require_pin_sale` flag has no effect on this path. PIN-protected POS sale controls are neutralized.
- Fix: Add `requirePosPinSale` as the first middleware on the `/sales` route, or consolidate both endpoints behind a single handler that always enforces the configured PIN policy.

---

### [MEDIUM] PIN rate limiter on `/auth/switch-user` is IP-only — shared POS terminal causes mutual lockout and enables cross-employee enumeration

- File: `packages/server/src/routes/auth.routes.ts:1438-1530`
- Description: `checkPinRateLimit` / `recordPinFailure` key exclusively on the client IP address (not on `(IP, targetUserId)` or any per-employee dimension). All employees at a shared POS terminal share the same IP. Consequence (a) **DoS**: five failed PIN attempts by any one employee (or a single bad actor at the terminal) trips a 15-minute lockout for the entire POS station — all staff cannot switch users. Consequence (b) **enumeration**: an attacker with a single valid session can submit 4 attempts for employee A, 1 success (which `clearPinFailures` resets the counter), then repeat for employee B, cycling through all employee PINs with only 5 net failures ever recorded per 15-minute window.
- Exploit: Attacker submits 4 wrong PINs, then 1 correct PIN for any employee. `clearPinFailures` resets the IP counter. Attacker rotates to the next employee's PIN space with a fresh 5-attempt budget — effectively unlimited brute-force.
- Fix: Key the rate limiter on `(IP, targetUserId)` per employee. A single correct match should clear failures only for that `(IP, userId)` pair, not for the whole IP. Consider a secondary per-IP cap as a defense-in-depth DoS protection rather than the sole mechanism.

---

### [MEDIUM] Admin-set PIN has no format constraint (any 1-32 char string); self-service PIN enforces 4-6 digits — inconsistency allows 1-digit PINs

- File: `packages/server/src/routes/settings.routes.ts:952,1010` vs `packages/server/src/routes/auth.routes.ts:2352`
- Description: `POST /settings/users` and `PUT /settings/users/:id` validate `pin.length <= 32` with no numeric or minimum-length requirement. An admin can set an employee PIN of `"1"`. The self-service `/auth/change-pin` endpoint validates `^\d{4,6}$`. The switch-user and clock-in/out paths accept any PIN of length 1-20. This creates a two-tier policy: admins can set trivially weak PINs that the self-service path would reject.
- Exploit: Admin sets employee PIN to `"1"` at account creation. Switch-user and clock-in succeed with a single-keystroke PIN; brute force is trivial (1 attempt).
- Fix: Enforce the same `^\d{4,6}$` regex on admin PIN create/update paths (settings.routes.ts lines 952 and 1010) so the format policy is uniform regardless of who sets the PIN.

---

### [LOW] `requirePosPin` enforced by a client-supplied header (`X-Pos-Pin-Verified: 1`) with no server-side session binding — "verified once, valid forever" within the HTTP request scope

- File: `packages/server/src/middleware/requirePosPin.ts:46,71,106`
- Description: The middleware checks `req.headers['x-pos-pin-verified'] === '1'`. Any authenticated client that sets this header value bypasses the PIN gate — there is no server-side token, timestamp, or session state binding the header to a real `/auth/verify-pin` call. The security depends entirely on the client voluntarily calling `/auth/verify-pin` first and then (honestly) echoing the result as a header. A malicious or tampered client can set `X-Pos-Pin-Verified: 1` on every request without ever calling `/auth/verify-pin`.
- Exploit: An attacker with a valid JWT (e.g. stolen from localStorage or via XSS) adds `X-Pos-Pin-Verified: 1` to a `POST /pos/transaction` request. No PIN was entered; the gate passes.
- Fix: Issue a short-lived, server-signed, per-user PIN-verification token from `/auth/verify-pin` (e.g. a HMAC-signed opaque value stored in `sessions` with a 5-minute TTL). The middleware validates the token server-side rather than trusting the header value.

---

### [LOW] PIN brute-force lockout on `/auth/switch-user` is cleared on any successful PIN match — success for one employee unlocks attempts against all others

- File: `packages/server/src/routes/auth.routes.ts:1529`
- Description: `clearPinFailures(db, ip)` is called after any successful switch-user regardless of which employee's PIN matched. Because the failure counter is IP-keyed (see MEDIUM above), a single successful match resets the entire IP budget, allowing an attacker to make 4 attempts → succeed with a known PIN → reset → repeat indefinitely.
- Exploit: See MEDIUM finding above. Specifically: an attacker who knows one employee's PIN can always reset the counter and get 4 fresh attempts against the next employee in a 10-key PIN space.
- Fix: Addressed by fixing the MEDIUM issue (per-employee key). Once the key is `(IP, userId)`, clearing on success is safe because it only clears that user's counter.

---

### [LOW] `requirePosPin` middleware silently falls through when `db` is absent (`if (!db) { next(); return; }`)

- File: `packages/server/src/middleware/requirePosPin.ts:41,66,96`
- Description: All three exported guard functions call `next()` unconditionally when `req.db` is falsy. This is documented as a safety valve but means any misconfigured request context (e.g. during testing, misconfigured middleware order, or a future multi-DB routing change) will silently permit PIN-gated operations without PIN verification.
- Exploit: Low practical risk in production, but the pattern means a configuration error disables security rather than failing safe. A future middleware ordering change could expose this path.
- Fix: Fail closed: return 503 or 500 when `db` is absent rather than passing the request through. A missing DB handle is a configuration error, not a case where the PIN requirement should be waived.

---

### [INFO] Clock-in/clock-out PIN uses per-`(employeeId, IP)` rate limiter — correct and independent of the switch-user IP-only limiter

- File: `packages/server/src/routes/employees.routes.ts:327,427`
- Description: The clock-in and clock-out PIN verification use `checkWindowRate(req.db, 'clock_pin', \`${id}:${req.ip}\`, 5, 900_000)` — keyed on `(targetUserId, IP)`. This is the correct design and correctly scopes lockouts per employee per workstation.
- Exploit: N/A — behavior is correct.
- Fix: No action required. Note for the fix of the MEDIUM above: adopt this same key shape for switch-user.

---

### [INFO] PIN not present in any audit log detail payload or error message body

- Files reviewed: `packages/server/src/routes/auth.routes.ts`, `packages/server/src/routes/employees.routes.ts`, `packages/server/src/routes/posEnrich.routes.ts`
- Description: All audit calls pass structured objects that never include `pin` or `req.body.pin`. Error messages return "Invalid PIN" without echoing the submitted value. No plaintext PIN leakage found in logs or responses.
- Exploit: N/A.
- Fix: No action required.

---

### [INFO] Admin PIN reset requires `admin_confirm_password` (and TOTP if enabled) — no existing-PIN re-verify required, but re-auth is present

- File: `packages/server/src/routes/settings.routes.ts:1101-1153`
- Description: `PUT /settings/users/:id` requires the admin to supply their own current password to change another user's PIN (`sensitiveChange` guard). The target user's existing PIN is not required for the admin to overwrite it. This is correct admin-override behavior and is authenticated via the admin's own credentials. The audit trail records `pin_changed_by_admin`.
- Exploit: N/A — intended behavior.
- Fix: No action required.

---

## PASS 2 — DEEP DIVE

### [HIGH] Manager PIN threshold (`pos_manager_pin_threshold`) not enforced server-side on sale completion

**Where:** `packages/server/src/routes/posEnrich.routes.ts:676-687` vs `packages/server/src/routes/pos.routes.ts:253,941,1384`

**What:**
The `pos_manager_pin_threshold` config (default $500) is checked exclusively inside `POST /pos-enrich/manager-verify-pin`, which returns `{ verified: true }` to the client. Neither `POST /pos/transaction`, `POST /pos/sales`, nor `POST /pos/checkout-with-ticket` query this threshold or verify that `/manager-verify-pin` was called before the sale was submitted. The enforcement is entirely client-side.

**Code:**
```typescript
// posEnrich.routes.ts:684-687 — only place threshold is checked:
if (sale > 0 && sale < threshold) {
  res.json({ success: true, data: { verified: true, threshold_cents: threshold, skipped: true } });
  return;
}
// pos.routes.ts:253 — sale completion has NO threshold check:
router.post('/transaction', requirePosPinSale, idempotent, asyncHandler(async (req, res) => {
  // ... no pos_manager_pin_threshold query or manager-pin-verified check
```

**Exploit:**
A cashier calls `POST /pos/transaction` directly with a $5,000 cart, skipping `/manager-verify-pin` entirely. The server completes the sale and creates the invoice. The $500 manager-approval gate is neutralized for all three sale paths.

**Fix:**
Add a server-side threshold check inside the `/pos/transaction` and `/pos/sales` handlers: read `pos_manager_pin_threshold` from `store_config`, compare the computed total, and if it exceeds the threshold reject the request unless a short-lived (30–60 second) server-issued manager-PIN token is present in the request header. The token should be created by `/manager-verify-pin` on success and validated (HMAC + expiry) on sale completion — not just a client-supplied header.

---

### [HIGH] `/pos/return` has no PIN gate and no per-line returned-quantity tracking — duplicate full-value returns

**Where:** `packages/server/src/routes/pos.routes.ts:2496-2637`

**What:**
`POST /pos/return` (admin/manager role required) checks only that `itemQty <= lineItem.quantity` (the original line quantity) before issuing a credit note. It does NOT track previously returned quantities: there is no `pos_return_line_items` table, no `returned_qty` column on `invoice_line_items`, and no query against the `refunds` table to accumulate prior credits for the same line. A manager can call `/pos/return` twice for the same `line_item_id` with `quantity: 1` against an original `quantity: 1` line and receive two full-value credit notes.

**Code:**
```typescript
// pos.routes.ts:2546-2548 — only guard is against original quantity, not previously returned qty:
if (itemQty > lineItem.quantity) {
  throw new AppError(`Return quantity (${itemQty}) exceeds invoiced quantity (${lineItem.quantity})`, 400);
}
// No query like: SELECT SUM(returned_qty) FROM refund_line_items WHERE line_item_id = ?
```

**Exploit:**
A compromised or colluding manager calls `POST /pos/return {invoice_id: X, items: [{line_item_id: 5, quantity: 1, reason: "damaged"}]}` and receives a $200 credit note. They call the same endpoint again immediately with the same payload and receive a second $200 credit note. Stock is also restored twice, creating phantom inventory.

**Fix:**
Add a `pos_return_line_items` table (or `returned_qty` column on `invoice_line_items`) tracking cumulative returned quantity per line item. In the return handler, sum previously returned quantities for each `line_item_id` and reject if `itemQty + already_returned_qty > lineItem.quantity`. Wrap the check and insert atomically.

---

### [MEDIUM] `pos_manager_pin_verified` audit log omits manager identity — approval cannot be attributed

**Where:** `packages/server/src/routes/posEnrich.routes.ts:715-717`

**What:**
When a manager PIN is successfully matched in `/pos-enrich/manager-verify-pin`, the audit record logs the requesting cashier's user ID (`req.user!.id`) and the `sale_cents`, but not the manager's identity. The `match` object contains only `pin` and `role`; the manager's `id` and `username` are not fetched. The response leaks only `match.role` to the client, also without the manager's ID. No audit trail records which specific manager approved a high-value transaction.

**Code:**
```typescript
// posEnrich.routes.ts:689-717:
const managers = await adb.all<{ pin: string | null; role: string | null }>(
  `SELECT pin, role FROM users WHERE ...`  // no id or username selected
);
const match = managers.find(...);
audit(req.db, 'pos_manager_pin_verified', req.user!.id, req.ip || 'unknown', {
  sale_cents: sale,  // no match.id, no manager username
});
```

**Exploit:**
A manager repeatedly approves fraudulent high-value sales for a colluding cashier. The audit log shows "a manager approved it" but cannot identify which manager, blocking forensic attribution and accountability.

**Fix:**
Include `id` and `username` in the `SELECT` from `users` in `manager-verify-pin`. Add `manager_user_id: match.id, manager_username: match.username` to the audit detail payload. Return `manager_user_id` in the response so the client can display the approving manager's name on the receipt.

---

### [MEDIUM] `/auth/verify-pin` and `/auth/switch-user` share the same IP-keyed rate-limit bucket, enabling cross-endpoint reset

**Where:** `packages/server/src/routes/auth.routes.ts:246-255,1443,1529,1596,1626`

**What:**
Both `/auth/switch-user` and `/auth/verify-pin` call the same `checkPinRateLimit` / `recordPinFailure` / `clearPinFailures` functions with `category='pin'` and `key=IP`. A successful `/auth/verify-pin` call (verifying the caller's own PIN) calls `clearPinFailures(db, ip)`, which resets the switch-user brute-force counter for every employee on that IP. An attacker can exhaust 4 switch-user attempts against employee A, call `verify-pin` with their own known PIN to reset the counter, then immediately get 4 more attempts against employee B — indefinitely cycling without ever triggering the 15-minute lockout.

**Code:**
```typescript
// auth.routes.ts:246-255 — shared bucket:
function checkPinRateLimit(db, ip) { return checkWindowRate(db, 'pin', ip, 5, 900000); }
function clearPinFailures(db, ip) { clearRateLimit(db, 'pin', ip); }
// switch-user line 1529: clearPinFailures(db, ip);  // resets ALL endpoints for this IP
// verify-pin line 1626: clearPinFailures(db, ip);   // same reset
```

**Exploit:**
Attacker sends 4 wrong PINs for employee A via `/switch-user` → calls `/verify-pin` with own correct PIN → counter resets → 4 more attempts for employee B. Repeats indefinitely with no lockout. Only needs a valid JWT session.

**Fix:**
Split the rate-limit bucket into separate categories: `'pin_switch'` for `/switch-user` and `'pin_verify'` for `/verify-pin`. Each should be keyed by `(userId, IP)` for per-employee isolation. Clearing on success should only clear the `(category, userId:IP)` tuple, not the entire IP.

---

### [LOW] `bcrypt.compareSync` in `/auth/switch-user` is called O(n) times (one per employee with a PIN) — timing side-channel exposes employee count

**Where:** `packages/server/src/routes/auth.routes.ts:1459-1463`

**What:**
`/auth/switch-user` fetches all active employees with bcrypt-hashed PINs and calls `bcrypt.compareSync` sequentially until a match is found. With bcrypt cost 12 (≈300ms per hash on modern hardware), a store with 10 employees takes ≈3 seconds to respond regardless of which PIN is submitted. An attacker with a valid JWT can infer how many employees have PINs set by measuring response time. This also means response time scales unboundedly as the employee roster grows.

**Code:**
```typescript
// auth.routes.ts:1459-1463:
const usersWithPins = await adb.all<any>(
  "SELECT id, ..., pin ... FROM users WHERE pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
);
const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));
```

**Exploit:**
Attacker submits PINs with different response-time measurements to infer employee PIN count. At scale, O(n) synchronous bcrypt blocks the Node event loop, degrading availability during busy POS periods.

**Fix:**
Move PIN comparison to an async worker-pool or use `bcrypt.compare` (async) in a Promise.all with early-exit. Consider adding a fixed minimum response delay (matching `enforceMinDuration` used on the login path). Alternatively, use a per-employee index: look up by PIN hash prefix or use a server-side session token approach that avoids scanning all employees.

---

### [LOW] Clock-in / clock-out PIN input has no length cap before `bcrypt.compareSync`

**Where:** `packages/server/src/routes/employees.routes.ts:331,429`

**What:**
`POST /:id/clock-in` and `POST /:id/clock-out` pass `pin || ''` directly to `bcrypt.compareSync` without checking the length. While `bcryptjs` (pure-JS) truncates inputs at 72 bytes per the BCrypt specification, the global body parser limit (1 MB) means a caller can submit a 1 MB PIN string that is buffered and parsed before truncation occurs. Compare to `/auth/switch-user` and `/auth/verify-pin` which cap input at 20 characters before the bcrypt call.

**Code:**
```typescript
// employees.routes.ts:331 — no length check:
if (!bcrypt.compareSync(pin || '', user.pin)) {
  recordWindowFailure(...); throw new AppError('Invalid PIN', 401);
}
// auth.routes.ts:1449 — correct pattern:
if (!pin || typeof pin !== 'string' || pin.length < 1 || pin.length > 20) {
  res.status(400).json(...); return;
}
```

**Exploit:**
Low practical risk: bcrypt truncates at 72 bytes and the body parser caps at 1 MB. However the inconsistency means if bcryptjs behavior changes or a different implementation is used, a 1 MB PIN string could stall the event loop during comparison.

**Fix:**
Add `if (!pin || typeof pin !== 'string' || pin.length > 20) throw new AppError('Valid PIN required', 400)` before the bcrypt call in both clock-in and clock-out handlers, matching the pattern in auth.routes.ts.

---

### [INFO] `/pos/return` has role gate (admin/manager) but no configurable PIN gate — inconsistent with sale PIN policy

**Where:** `packages/server/src/routes/pos.routes.ts:2504-2505` vs `packages/server/src/middleware/requirePosPin.ts`

**What:**
When `pos_require_pin_sale` is enabled, completing a sale requires PIN verification via `requirePosPinSale`. However, processing a return (which creates a credit note and restores stock — often higher risk than a sale) has only a role gate (admin/manager) with no configurable PIN requirement. There is no `pos_require_pin_return` config key. A manager session without recent PIN verification can process unlimited returns.

**Exploit:**
N/A — role gate is enforced. Low practical risk absent a stolen manager session.

**Fix:**
Consider adding a `pos_require_pin_return` store_config flag and a `requirePosPinReturn` middleware applied to `POST /pos/return`, consistent with the PIN-on-sale design.

---

### [INFO] `/auth/switch-user` has no `enforceMinDuration` — response time not normalized unlike login

**Where:** `packages/server/src/routes/auth.routes.ts:1438` vs `packages/server/src/routes/auth.routes.ts:702,714`

**What:**
The main login route enforces a minimum response time of 250ms (`enforceMinDuration`) to defeat timing-based enumeration. `POST /auth/switch-user` does not use `enforceMinDuration`. Combined with O(n) bcrypt comparison (see LOW finding above), both timing oracles (response time variance by employee count and by match position) are present.

**Exploit:**
N/A — requires valid JWT. Combined with the O(n) bcrypt side-channel, enables informed brute-force ordering.

**Fix:**
Wrap the switch-user handler body in an `enforceMinDuration` call with a minimum time proportional to the expected maximum number of employees (e.g., `N_employees * 300ms` or a fixed 3000ms cap). This is defense-in-depth against the O(n) timing leak.
