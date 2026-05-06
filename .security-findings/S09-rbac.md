# S09 — Role-Based Access Control / Authorization

## Findings

---

### [MEDIUM] GET /roles/users/:userId/role — any authenticated user can query another user's custom-role assignment

- **File:** `packages/server/src/routes/roles.routes.ts:336-350`
- **Description:** The `GET /roles/users/:userId/role` endpoint has no role gate whatsoever. Any authenticated user (cashier, technician) can supply an arbitrary `userId` and learn which custom role that user carries (`role_name`, `description`). The sibling `PUT /roles/users/:userId/role` correctly calls `requireAdmin`, but the read endpoint was left open.
- **Exploit:** A cashier calls `GET /api/v1/roles/users/1/role` to confirm the owner's custom role assignment. Combined with `GET /roles/:id/permissions` (admin-only) a cashier cannot read the full matrix, but they can determine *which named role* any user has been assigned — useful for social engineering or confirming whether their own role has been changed after a revocation event.
- **Fix:** Add `requireAdmin(req)` at the top of this handler, consistent with all sibling handlers in the same file.

---

### [LOW] GET /team/payroll/periods — payroll period metadata readable by any authenticated user

- **File:** `packages/server/src/routes/team.routes.ts:847-856`
- **Description:** `GET /team/payroll/periods` has no role guard. Every authenticated user (including cashier) can list all payroll period records including names, date ranges, `locked_at`, and `locked_by_user_id`. The sibling `POST /team/payroll/periods` and `POST /team/payroll/lock/:periodId` are both properly gated (manager/admin and admin respectively). The CSV export and lock routes are admin-only. Only the list endpoint is open.
- **Exploit:** A cashier polls `GET /team/payroll/periods` to learn whether the current period is locked before attempting to manipulate a clock entry or commission (clock-in/out routes check `isCommissionLocked` independently, so this is informational rather than a bypass). More concretely it leaks organisational payroll calendar metadata to all staff.
- **Severity rationale:** Downgraded to LOW because no financial data is exposed; names and dates only. All mutation gates are intact.
- **Fix:** Add `requireAdminOrManager(req)` at the top of the `GET /team/payroll/periods` handler.

---

### [LOW] GET /team/payroll/lock-check — any authenticated user can probe lock state for an arbitrary timestamp

- **File:** `packages/server/src/routes/team.routes.ts:1002-1010`
- **Description:** `GET /team/payroll/lock-check?at=<timestamp>` is ungated. It was designed as an internal helper consumed by other routes (e.g. to check lock status before a write), but is accessible to any authenticated caller. A cashier can enumerate which date ranges are locked.
- **Exploit:** Low impact on its own — returns only `{ locked: true|false }`. Paired with the open periods list above it provides a complete picture of payroll locking state to all staff.
- **Fix:** Add `requireAdminOrManager(req)` or scope the endpoint to server-internal use only (e.g. use a direct function call rather than an HTTP sub-request).

---

### [LOW] GET /team/shifts — all employees' shift schedules visible to any authenticated user

- **File:** `packages/server/src/routes/team.routes.ts:83-113`
- **Description:** The shift list endpoint has no role guard. Any authenticated user can query the full shift schedule for all employees (with first name, last name, username JOIN) by omitting the `user_id` filter. POST/PUT/DELETE shifts are all gated with `requireAdminOrManager`. The list is open.
- **Exploit:** A cashier who wants to know when a manager will not be in-store calls `GET /team/shifts` with a future date range. This exposes full org scheduling data.
- **Fix:** Either (a) add `requireAdminOrManager(req)` to enforce manager-level access for the full list, or (b) allow self-read only — enforce `userId === req.user.id` when `user_id` query param is absent or supplied, calling `requireAdminOrManager` only when requesting another employee's shifts.

---

### [LOW] GET /team/time-off — all employees' time-off requests visible to any authenticated user

- **File:** `packages/server/src/routes/team.routes.ts:244-271`
- **Description:** Same gap as shifts. The read endpoint has no role gate; `user_id` filter is optional. Any cashier can list every time-off request org-wide (including reasons). PUT (approve/deny) and DELETE are gated. POST (request) correctly restricts non-managers to self-filing only.
- **Exploit:** A cashier enumerates all pending/approved time-off requests with reasons to learn colleagues' personal circumstances.
- **Fix:** Apply the same self-vs-privileged split as POST: when `user_id` !== `req.user.id`, call `requireAdminOrManager(req)`.

---

### [INFORMATIONAL] requireAdmin uses strict `=== 'admin'` — correctly resistant to weak gate

- **File:** `packages/server/src/routes/roles.routes.ts:82-86`, `packages/server/src/routes/team.routes.ts:54-58`
- **Description:** All `requireAdmin` helpers use `!== 'admin'` (strict equality), not truthy checks. `requireAdminOrManager` similarly uses `!== 'admin' && !== 'manager'`. No weak `if (user.role)` gates found.
- **Status:** CLEAN

---

### [INFORMATIONAL] Privilege escalation via role update — blocked

- **File:** `packages/server/src/routes/roles.routes.ts:289-334`, `packages/server/src/routes/settings.routes.ts:1572-1808`
- **Description:** Both role-assignment paths (`PUT /roles/users/:userId/role` and `PUT /settings/users/:id`) are admin-gated. The settings route additionally: (a) validates `role` against `VALID_ROLES` derived from the shared constants — no arbitrary role strings accepted; (b) requires `admin_confirm_password` + optional TOTP re-auth for any role change; (c) enforces a 24 h cooldown after backup-code recovery before a role can be changed; (d) prevents the last active admin from demoting themselves; (e) revokes the target's sessions immediately when demoted from admin.
- **Status:** CLEAN — no privilege escalation path found.

---

### [INFORMATIONAL] Default role on signup — 'admin' for tenant owner, 'technician' for staff

- **File:** `packages/server/src/routes/signup.routes.ts:448`, `packages/server/src/routes/settings.routes.ts:1514`
- **Description:** The tenant-provisioning flow creates exactly one `admin` user. Subsequent staff users created via `POST /settings/users` default to `'technician'` (least-privileged enumerated role) and are validated against `VALID_ROLES`. No path exists for an unauthenticated caller to choose their own role.
- **Status:** CLEAN

---

### [INFORMATIONAL] Permission cache — no stale-cache risk

- **File:** `packages/server/src/middleware/auth.ts:162-178`
- **Description:** Custom-role permissions are re-fetched from the DB on every authenticated request (inside `authMiddleware`). There is no in-process cache of permission sets. A role revocation takes effect on the next request, bounded by the session's `expires_at`. When a user is deactivated or their role is demoted from admin, their sessions are explicitly deleted (`DELETE FROM sessions WHERE user_id = ?`), so the JWT will fail session verification on the next call.
- **Status:** CLEAN — no stale permission cache risk.

---

### [INFORMATIONAL] Self-modification / chain-of-command — protected

- **File:** `packages/server/src/routes/employees.routes.ts:311,412`, `packages/server/src/routes/settings.routes.ts:1613-1640`
- **Description:** Clock-in/out restrict non-admins to self-only (checked by `req.user.id !== id`). Pay-rate edits are admin-only. Role changes require admin + re-auth + last-admin-guard. No employee can disable/delete another employee outside admin scope.
- **Status:** CLEAN

---

### [INFORMATIONAL] Knowledge-base CRUD — intentionally open to all authenticated staff

- **File:** `packages/server/src/routes/team.routes.ts:769-841`
- **Description:** `POST /team/kb` and `PUT /team/kb/:id` have no role gate — any authenticated user can create or edit articles. Only DELETE requires `requireAdminOrManager`. The code comment explicitly states this is intentional ("each shop can build their own"). This is a design choice, not a vulnerability, but it means a cashier could post misleading content visible to other staff.
- **Status:** BY DESIGN — flag for product team if staff-submitted content is a concern.

---

## PASS 2 — DEEP DIVE

### [MEDIUM] GET /employees/:id leaks pay_rate to any authenticated user

**Where:** `packages/server/src/routes/employees.routes.ts:252-268`

**What:**
`GET /employees/:id` fetches a user record that includes `pay_rate` at the SQL level, then applies a privilege fork at line 261 — but the `employee` object sent to non-privileged callers (line 266) already contains `pay_rate` from the `SELECT` that precedes the fork. The check gates the `clock_entries` and `commissions` arrays, not the base profile fields.

**Code:**
```typescript
const employee = await adb.get<any>(`
  SELECT id, username, email, first_name, last_name, role, avatar_url,
         is_active, pin IS NOT NULL AS has_pin, permissions, home_location_id,
         pay_rate, created_at, updated_at    -- pay_rate included here
  FROM users WHERE id = ?
`, id);
const isPrivileged = req.user?.role === 'admin' || req.user?.id === id;
if (!isPrivileged) {
  res.json({ success: true, data: employee }); // pay_rate leaks here
  return;
}
```

**Exploit:**
Any cashier calls `GET /api/v1/employees/3` where 3 is a manager's user ID. The response body contains `pay_rate: 28.50` (or equivalent). Competitor pay rates and internal compensation structure are exposed to all staff.

**Fix:**
Before the privilege fork, strip `pay_rate` from the `employee` object for non-privileged callers: `const { pay_rate: _pr, ...publicProfile } = employee;` and return `publicProfile`, or move `pay_rate` out of the base SELECT and into the privileged-only branch.

---

### [MEDIUM] GET /employees — all staff email + role + permissions blob readable by any authenticated user

**Where:** `packages/server/src/routes/employees.routes.ts:179-210`

**What:**
`GET /employees` has no role gate and returns `email`, `role`, `permissions` (the full JSON blob of per-user capability overrides), `home_location_id`, and current clock status for every active employee. This is a full staff directory with role enumeration and capability leak.

**Code:**
```typescript
router.get('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const employees = await adb.all(`
    SELECT u.id, u.username, u.email, u.first_name, u.last_name, u.role,
           u.avatar_url, u.is_active, u.pin IS NOT NULL AS has_pin,
           u.permissions, u.home_location_id, ...  -- no role gate
    FROM users u WHERE u.is_active = 1
  `);
  res.json({ success: true, data: employees });
}));
```

**Exploit:**
A cashier calls `GET /api/v1/employees` to enumerate all colleagues' work emails (useful for phishing or social engineering), their roles, and their exact `permissions` JSON which reveals which capabilities have been manually overridden from the role default. Combined with `GET /roles/users/:userId/role` (ungated — found in Pass 1) this fully maps the org's privilege landscape.

**Fix:**
(a) Add `requireAdminOrManager(req)` to gate the full list, or (b) allow any authenticated user to fetch a redacted list (first_name, last_name, role display only) and require manager+ for the full list including email and permissions.

---

### [MEDIUM] POST+GET /billing — any authenticated user can trigger Stripe Checkout and access Billing Portal

**Where:** `packages/server/src/routes/billing.routes.ts:46-97`  
**Also:** `packages/server/src/index.ts:1727`

**What:**
`POST /api/v1/billing/checkout` and `GET /api/v1/billing/portal` are mounted behind `authMiddleware` only — there is no role gate. Any authenticated user (cashier, technician) can initiate a Stripe Checkout session for the Pro plan upgrade or open the Stripe Billing Portal, which allows subscription management including plan changes and payment method updates.

**Code:**
```typescript
// index.ts:1727 — no requireAdmin before billingRoutes
app.use('/api/v1/billing', authMiddleware, billingRoutes);

// billing.routes.ts:46 — rate limit only, no role check
router.post('/checkout', billingRateLimit, async (req, res) => {
  // Any authenticated user reaches here
  const url = await createCheckoutSession(req.tenantId, req.tenantSlug, ...);
  res.json({ success: true, data: { url } });
});
router.get('/portal', billingRateLimit, async (req, res) => {
  // Any authenticated user can open Billing Portal
  const url = await createBillingPortalSession(stripe_customer_id, returnUrl);
  res.json({ success: true, data: { url } });
});
```

**Exploit:**
A cashier logs in, calls `GET /api/v1/billing/portal`, receives a valid Stripe Billing Portal URL, and uses it to cancel the tenant's Pro subscription or change payment details. The portal session is authenticated to the tenant's Stripe customer and grants full subscription management rights. Alternatively, they open checkout to trigger billing flows without the owner's knowledge.

**Fix:**
Add `adminOnly` (or at minimum `requireManagerOrAdmin`) middleware to both the checkout and portal routes. The `billingRateLimit` middleware is not a substitute for authorization.

---

### [MEDIUM] GET /settings-ext/history — settings audit log readable by any authenticated user

**Where:** `packages/server/src/routes/settingsExport.routes.ts:401-446`

**What:**
`GET /settings-ext/history` returns filtered `audit_logs` rows for events including `user_created`, `user_updated`, `user_deleted`, and all `settings_*` events. The file header states "All endpoints require admin role" and `adminOnly` is applied to every other route in this file (GET export, POST import, POST templates/apply, POST bulk) — but `GET /history` was omitted from the gate.

**Code:**
```typescript
// No adminOnly in the handler chain:
router.get(
  '/history',
  asyncHandler(async (req, res) => {
    const rows = await adb.all<...>(
      `SELECT al.id, al.event, al.user_id, al.meta, al.created_at
       FROM audit_logs al
       WHERE al.event LIKE 'settings_%'
          OR al.event IN ('store_updated','user_created','user_updated','user_deleted')
       ORDER BY al.created_at DESC LIMIT ?`,
      limit
    );
    // ...
  })
);
```

**Exploit:**
A cashier calls `GET /api/v1/settings-ext/history` to learn which admin accounts were recently created or updated (via `user_created`/`user_updated` events), whether a role change happened (`user_updated`), and which payment/SMS provider credentials were last changed (`settings_config_updated`). The `meta` JSON often carries the changed key names, giving an attacker a map of configuration churn.

**Fix:**
Insert `adminOnly,` as the second argument to the route handler, consistent with every other route in this file: `router.get('/history', adminOnly, asyncHandler(...))`.

---

### [MEDIUM] GET /employees/performance/all — all employees' revenue figures readable by any authenticated user

**Where:** `packages/server/src/routes/employees.routes.ts:216-237`

**What:**
`GET /employees/performance/all` has no role gate and returns `total_revenue` and `avg_ticket_value` for every employee in the org. Revenue attribution per staff member is sensitive payroll/incentive data. The per-employee performance endpoint `GET /employees/:id/performance` is also ungated.

**Code:**
```typescript
router.get('/performance/all', asyncHandler(async (req, res) => {
  // No requireAdmin or requireAdminOrManager
  const employees = await adb.all(`
    SELECT u.id, u.first_name, u.last_name, u.role,
           COUNT(DISTINCT t.id) AS total_tickets,
           COALESCE(SUM(t.total), 0) AS total_revenue,   -- financial data
           COALESCE(AVG(t.total), 0) AS avg_ticket_value
    FROM users u LEFT JOIN tickets t ...
  `);
  res.json({ success: true, data: employees });
}));
```

**Exploit:**
A cashier calls `GET /api/v1/employees/performance/all` to learn every technician's revenue numbers. Combined with knowing their own commission rate (from `GET /employees/:id`), this reveals a close approximation of each colleague's take-home pay — creating workplace tension or being used as leverage in salary negotiations without management's consent.

**Fix:**
Add `requireAdminOrManager(req)` at the top of both `GET /performance/all` and `GET /:id/performance` handlers, or apply a self-only rule for the per-ID variant.

---

### [LOW] GET /roles/permission-keys — full capability manifest readable by any authenticated user

**Where:** `packages/server/src/routes/roles.routes.ts:116-121`

**What:**
`GET /roles/permission-keys` returns the full list of permission key strings (e.g., `refunds.create`, `invoices.void`, `customers.gdpr_erase`, `admin.full`) with no role gate. Every other endpoint in this file is admin-only. While the list doesn't reveal assignments, it exposes the complete privilege surface to any authenticated caller — useful for constructing targeted social-engineering attacks ("can you approve a `refunds.approve` action?").

**Code:**
```typescript
router.get(
  '/permission-keys',
  asyncHandler(async (_req, res) => {
    res.json({ success: true, data: PERMISSION_KEYS }); // no requireAdmin
  }),
);
```

**Exploit:**
A cashier calls `GET /api/v1/roles/permission-keys` to enumerate every privilege the system supports. Combined with the ungated `GET /roles/users/:userId/role` (Pass 1 finding), they can also confirm whether a coworker has been granted elevated roles. Low blast radius on its own.

**Fix:**
Add `requireAdmin(req)` at the top of the handler; the permission keys list is administrative metadata and there's no legitimate reason for non-admin users to query it.

---

### [LOW] GET /employees and GET /employees/:id — manager role has no cross-employee visibility gate

**Where:** `packages/server/src/routes/employees.routes.ts:490-529` (hours), `532-583` (commissions)

**What:**
`GET /employees/:id/hours` and `GET /employees/:id/commissions` use `req.user?.role === 'admin' || req.user?.id === id` as the gate — this blocks a cashier from reading a manager's hours, but a `manager` role is not included in the admin bypass. Managers need to view their team's hours for payroll purposes; the current gate forces them to be blocked or uses `=== 'admin'` strictly. This is not an escalation bug — it's an under-permissive gate — but it means managers cannot access payroll data for their reports without also being `admin`.

**Code:**
```typescript
// hours endpoint:
if (req.user?.role !== 'admin' && req.user?.id !== id) {
  throw new AppError('Forbidden — can only view your own hours', 403);
}
```

**Exploit:**
Low risk — managers who need to review team payroll must be granted admin role, unnecessarily expanding the admin pool. A manager assigned to approve payroll periods (which is a `requireAdminOrManager` gate) cannot actually view the underlying clock data to validate it without admin access. This creates an operational blind spot.

**Fix:**
Change the gate to `req.user?.role !== 'admin' && req.user?.role !== 'manager' && req.user?.id !== id` so managers can access any employee's hours and commissions within the tenant.

---

### [INFO] SETTINGS_ADMIN_ROLES admits 'owner' string — invisible role not in VALID_ROLES

**Where:** `packages/server/src/routes/settings.routes.ts:112`

**What:**
`SETTINGS_ADMIN_ROLES = new Set(['admin', 'owner'])` accepts the string `'owner'` as an admin-equivalent for settings mutations. However, `VALID_ROLES` (derived from `ROLE_PERMISSIONS`) contains only `admin`, `manager`, `technician`, `cashier` — not `owner`. No signup or user-creation path can produce a user with `role === 'owner'`. The `'owner'` entry is dead code from a legacy role rename but creates confusion during code review: a developer checking `VALID_ROLES` to assess the privilege surface would miss that `'owner'` is accepted here.

**Code:**
```typescript
const SETTINGS_ADMIN_ROLES = new Set(['admin', 'owner']);
// But VALID_ROLES = new Set(Object.keys(ROLE_PERMISSIONS))
// ROLE_PERMISSIONS does not include 'owner'
```

**Fix:**
Remove `'owner'` from `SETTINGS_ADMIN_ROLES`. Verify no legacy user rows in any production tenant carry `role = 'owner'` before deploying. If legacy compatibility is required, add a migration to rewrite `'owner'` → `'admin'`.

---

### [INFO] billing.routes.ts — no audit log on checkout or portal access

**Where:** `packages/server/src/routes/billing.routes.ts:46-97`

**What:**
Neither `POST /billing/checkout` nor `GET /billing/portal` calls `audit()`. Subscription events (upgrade, cancel, payment method changes) that flow through the Stripe Billing Portal leave no server-side audit trail — only Stripe's own event log. If a malicious employee triggers a checkout or opens the portal (see the MEDIUM finding above), the action is invisible in the tenant's `audit_log`.

**Fix:**
After fixing the role gate, add `audit(req.db, 'billing_checkout_initiated', req.user!.id, req.ip, { tenant_id: req.tenantId })` and a corresponding entry for portal access.
