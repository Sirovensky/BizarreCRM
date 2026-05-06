# S23 — PII Exposure: Customer / Search / Audit / Activity / Portal Endpoints

---

### [MEDIUM] portal_pin hash returned in customer detail and list API to all staff

**Where:** `packages/server/src/routes/customers.routes.ts:194` (list), `packages/server/src/routes/customers.routes.ts:1206` (GET /:id)

**What:**
Both `GET /api/v1/customers` and `GET /api/v1/customers/:id` execute `SELECT c.*` which includes the `portal_pin` column (bcrypt hash of customer's portal PIN, added in migration 041). The full `c.*` row is returned verbatim to any authenticated staff user regardless of role. Likewise, the customers table schema (migration 001, lines 97–100) includes `driving_license`, `license_image`, `id_type`, `id_number`, and `tax_number` columns that would be returned by `c.*` if populated.

**Code:**
```typescript
// GET /customers list — customers.routes.ts:194
const dataSql = `
  SELECT
    c.*,
    cg.name AS customer_group_name,
    ...
  FROM customers c
  ...
`;
// GET /customers/:id — customers.routes.ts:1206
const customer = await adb.get<AnyRow>(
  `SELECT c.*,
          ...
   FROM customers c
   WHERE c.id = ? AND c.is_deleted = 0`,
  id);
res.json({ success: true, data: { ...(customer as any), phones, emails, ... } });
```

**Exploit:**
A technician-role staff member sends `GET /api/v1/customers/42`. The JSON response includes `portal_pin: "$2b$12$..."` (bcrypt hash). While bcrypt is slow to crack, the hash is sufficient to confirm a PIN was set, and the hash can be taken offline for brute-force. For customers with `id_number` or `driving_license` populated, those identity document values are also exposed in the same response.

**Fix:**
Replace `SELECT c.*` with an explicit column allowlist that excludes `portal_pin`, `driving_license`, `license_image`, `id_type`, `id_number`, and `tax_number` from general list/detail endpoints. Expose `tax_number` only to admin/manager roles and gate any government-ID fields behind `requirePermission('customers.view_sensitive')`.

---

### [MEDIUM] GET /customers/repeat exposes email and phone to any authenticated user

**Where:** `packages/server/src/routes/customers.routes.ts:1172`

**What:**
The `GET /customers/repeat` endpoint returns a list of repeat customers including `email`, `phone`, and `mobile` columns. Unlike all write operations and the import endpoint, this read endpoint has no `requirePermission` call and no inline role check. Any authenticated user (including technician role) can enumerate every customer who visited 3+ times in the last 12 months with their contact details.

**Code:**
```typescript
router.get(
  '/repeat',
  asyncHandler(async (req, res) => {
    const customers = await adb.all<AnyRow>(`
      SELECT c.id, c.first_name, c.last_name, c.email, c.phone, c.mobile,
             c.organization, c.code,
             COUNT(t.id) AS ticket_count, ...
      FROM customers c
      ...
    `);
    res.json({ success: true, data: customers });  // no role gate
  }),
);
```

**Exploit:**
An authenticated technician with no `customers.view` permission calls `GET /api/v1/customers/repeat?months=120&min_tickets=1`, receiving a dump of all customer emails and phone numbers from the past 10 years.

**Fix:**
Add `requirePermission('customers.view')` (or equivalent admin/manager role check) to the `/repeat` route handler, matching the pattern used by `POST /import-csv` and `POST /merge`.

---

### [MEDIUM] GET /inbox/retry-queue exposes customer phone numbers and SMS text to all staff

**Where:** `packages/server/src/routes/inbox.routes.ts:733`

**What:**
`GET /inbox/retry-queue` returns up to 200 queued SMS records including `to_phone` (full customer phone number) and `body` (full SMS message text) with no role guard. The endpoint is mounted under `authMiddleware` but has no inline role check, unlike `POST /bulk-send` which calls `requireAdmin()`. Any technician can read every phone number and outbound message content queued for retry.

**Code:**
```typescript
router.get(
  '/retry-queue',
  asyncHandler(async (req, res) => {
    const rows = await adb.all<...>(
      `SELECT id, original_message_id, to_phone, body, retry_count, next_retry_at,
              last_error, status, created_at
         FROM sms_retry_queue
        WHERE status IN ('pending','failed')
        ORDER BY next_retry_at ASC
        LIMIT 200`,
    );  // No role check here or at route definition
    res.json({ success: true, data: safeRows });
  }),
);
```

**Exploit:**
A technician calls `GET /api/v1/inbox/retry-queue` and receives up to 200 customer phone numbers and the text of queued marketing/transactional SMS messages they are not authorized to see.

**Fix:**
Add `requireAdmin(req)` (or admin/manager role check) at the top of the `/retry-queue` GET handler and both `/retry-queue/:id/retry` and `/retry-queue/:id/cancel` handlers, matching the protection level of `POST /bulk-send`.

---

### [LOW] portal-enrich v2 auth skips 4-hour idle-timeout enforced by v1 portal

**Where:** `packages/server/src/routes/portal-enrich.routes.ts:65` vs `packages/server/src/routes/portal.routes.ts:126`

**What:**
The `portalAuth` in `portal.routes.ts` enforces a 4-hour idle timeout by checking `last_used_at` and evicts stale sessions by deleting the row. The `portalAuth` in `portal-enrich.routes.ts` only checks `expires_at > datetime('now')` and never updates `last_used_at`. A customer session that has been idle for over 4 hours will be rejected by v1 portal endpoints but accepted by all v2 portal-enrich endpoints (`/portal/api/v2/*`), including ticket timeline, photos, warranty PDF, and review submission.

**Code:**
```typescript
// portal-enrich.routes.ts:82 — no idle check, no last_used_at update
const session = await adb.get<AnyRow>(
  `SELECT customer_id, scope, ticket_id, token
     FROM portal_sessions
    WHERE token = ? AND expires_at > datetime('now')`,  // only expiry, no idle
  token,
);
// portal.routes.ts:141 — correctly evicts idle sessions
if (lastUsedMs === null || Date.now() - lastUsedMs > IDLE_LIMIT_MS) {
  await adb.run('DELETE FROM portal_sessions WHERE token = ?', token);
  res.status(401).json({ ... message: 'Session idle timeout. Please log in again.' });
```

**Exploit:**
A customer logs in from a shared computer, the session goes idle for 5 hours (browser closed). v1 portal rejects the session cookie. The attacker reuses the cookie to hit `GET /portal/api/v2/ticket/42/timeline` which succeeds, leaking ticket history including SMS transcripts and diagnostic notes.

**Fix:**
Mirror the idle-timeout check from `portal.routes.ts` into `portal-enrich.routes.ts` `portalAuth`, including the `last_used_at` update on every accepted request. Or extract a shared `portalAuthMiddleware` helper used by both files.

---

### [LOW] GET /inbox/conversations exposes bulk customer phone numbers to any authenticated user

**Where:** `packages/server/src/routes/inbox.routes.ts:157`

**What:**
`GET /inbox/conversations` returns up to 500 rows each containing a normalized customer phone number (`phone` field), assigned user ID, and conversation tags. There is no role gate; any authenticated staff member can call this endpoint. The intent is to let staff filter conversations, but the `all` filter returns every assigned phone number across the entire tenant.

**Code:**
```typescript
router.get(
  '/conversations',
  asyncHandler(async (req, res) => {
    // No role check
    const sql = `
      SELECT ca.phone, ca.assigned_user_id, ca.assigned_at, ...
        FROM conversation_assignments ca
       LIMIT 500
    `;
    res.json({ success: true, data: enriched });
  }),
);
```

**Exploit:**
A technician with no SMS access permission calls `GET /api/v1/inbox/conversations?assigned_to=all` and receives up to 500 customer phone numbers along with their conversation assignment history.

**Fix:**
Add at minimum a manager/admin role check (or a new `sms.view` permission check) on the `assigned_to=all` and `assigned_to=unassigned` filter paths, scoping technicians to only their own assigned conversations (`assigned_to=me` implicitly).

---

### [LOW] GET /leads and GET /leads/pipeline expose phone and email to unassigned technicians

**Where:** `packages/server/src/routes/leads.routes.ts:110` (pipeline), `packages/server/src/routes/leads.routes.ts:169` (list)

**What:**
Both the kanban pipeline endpoint (`GET /leads/pipeline`) and the paginated list (`GET /leads`) execute `SELECT l.*` which includes `l.phone` and `l.email`. There is no role gate and no assignment scoping: any authenticated user receives phone numbers and emails for all leads in the system. Unlike tickets (which respect `ticket_all_employees_view_all` and per-assignment filtering), leads have no equivalent visibility control.

**Code:**
```typescript
// leads.routes.ts:209
const leads = await adb.all<any>(`
  SELECT l.*,
    u.first_name AS assigned_first_name, ...
  FROM leads l
  WHERE l.is_deleted = 0
  ORDER BY l.${safeSortBy} ${sortOrder}
  LIMIT ? OFFSET ?
`);  // No role scope, no assignment filter
```

**Exploit:**
A technician calls `GET /api/v1/leads?pagesize=200` and receives the full name, email, and phone number of every prospective customer (lead) in the system including those assigned to other staff.

**Fix:**
For non-admin/manager roles, add an `assigned_to = ?` filter to scope technicians to their own leads (or introduce a `leads.view_all` permission), mirroring the ticket visibility pattern in `search.routes.ts:64–67`.

---

### [INFO] GET /portal/verify accepts session token in query string (logged in access logs)

**Where:** `packages/server/src/routes/portal.routes.ts:1060`

**What:**
The deprecated `GET /portal/verify?token=<token>` endpoint is still active. When the query-string path is used (no `Authorization` header), the bearer token appears in server access logs, browser history, Referer headers, and any CDN/proxy request logs. The endpoint already logs a deprecation warning but remains functional.

**Code:**
```typescript
router.get('/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const queryToken = req.query.token as string | undefined;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : queryToken;
  // token from query string → appears in all HTTP logs
  await verifySessionHandler(req, res, token);
}));
```

**Exploit:**
A customer visits `https://shop.example.com/portal/verify?token=abc123`. The full URL (including session token) is recorded in web server logs accessible to any log reader. The token grants full portal access for up to 24 hours.

**Fix:**
Remove the GET `/verify` route entirely; the `POST /verify` variant (which accepts token from `Authorization` header or POST body) is already the preferred path and is documented as such. If backwards compatibility is required for one more release, at least add a `max-age=0, no-store` `Cache-Control` header to prevent the response (and referrer) being cached with the token.

---
