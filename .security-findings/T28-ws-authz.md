# T28 — WebSocket Per-Message-Type Authorization Matrix & Broadcast Scoping

**Scope:** `packages/server/src/ws/server.ts`, `routes/teamChat.routes.ts`,
`routes/notifications.routes.ts`, `services/notifications.ts`

---

### [HIGH] scrubSensitive() misses device.security_code in ticket broadcasts

**Where:** `packages/server/src/ws/server.ts:49–93` (scrubSensitive), `routes/tickets.routes.ts:390` (device shape), `routes/tickets.routes.ts:1281` (broadcast call)

**What:**
`scrubSensitive()` strips `SENSITIVE_CUSTOMER_FIELDS` from `payload.customer` and `SENSITIVE_PAYMENT_FIELDS` from `payload.payments`, but it does **not recurse into `payload.devices`**. The `getFullTicketAsync` helper embeds `security_code` (device PIN/passcode) directly in each device object (line 390). Because `scrubSensitive` only shallow-processes the top-level object and specifically handles `customer` and `payments`, the `devices[]` array passes through untouched. All `ticket:created`, `ticket:updated`, and `ticket:status_changed` broadcasts carrying a full ticket payload therefore deliver `security_code` to every non-finance role socket in the tenant bucket.

**Code:**
```typescript
// ws/server.ts — scrubSensitive only handles customer + payments, skips devices[]
const needsScrub =
  (p.customer && typeof p.customer === 'object') ||
  Array.isArray(p.payments) || ...;
if (!needsScrub) return payload;
const out: Record<string, unknown> = { ...p };
// out.devices is never touched — security_code, imei, serial pass through

// tickets.routes.ts getFullTicketAsync line 390:
{
  security_code: d.security_code,  // device PIN/passcode
  imei: d.imei,
  serial: d.serial,
  ...
}
```

**Exploit:**
A cashier role (or any non-finance staff) connects to WebSocket and receives a `ticket:updated` event when a technician updates a repair ticket. The event JSON includes `devices[0].security_code = "1234"` — the customer's device unlock PIN. The cashier did not need `invoices.view` or finance access to receive this field; they only need an active session.

**Fix:**
Extend `scrubSensitive` to recurse into `out.devices` (and any other nested arrays/objects). Either add `if (Array.isArray(p.devices)) { out.devices = p.devices.map(scrubDevice); }` with a `SENSITIVE_DEVICE_FIELDS = ['security_code']` list, or explicitly delete `security_code` from each device entry before broadcast.

---

### [MEDIUM] sms:received broadcast sends full SMS body and phone numbers to all tenant users regardless of sms.view permission

**Where:** `packages/server/src/routes/sms.routes.ts:1165`, `packages/server/src/ws/server.ts:674–698` (broadcast loop)

**What:**
When an inbound SMS arrives via webhook, the server broadcasts `sms:received` carrying `{ message: msg, customer }` where `msg = SELECT * FROM sms_messages` — including `from_number`, `to_number`, `conv_phone`, and the raw `message` body. The `broadcast()` function delivers this to every authenticated socket in the tenant bucket with no permission filter. A `cashier` role lacks `sms.view` in `ROLE_PERMISSIONS` but will still receive every inbound SMS in real time over WebSocket.

**Code:**
```typescript
// sms.routes.ts:1124–1165
const customer = await adb.get<any>(
  'SELECT id, first_name, last_name, sms_opt_in FROM customers WHERE ...'
);
// msg = SELECT * FROM sms_messages (includes from_number, message body, conv_phone)
broadcast(WS_EVENTS.SMS_RECEIVED, { message: msg, customer: customer || null },
  req.tenantSlug || null);
// broadcast() iterates entire tenant bucket — no role check
```

**Exploit:**
A cashier opens the WS connection, authenticates, and listens. Any inbound customer SMS — including personal messages ("my password is X", health details in the message body) — arrives in the cashier's WS stream even though the cashier tab has no SMS inbox UI. The `from_number` also exposes customer phone numbers to all staff.

**Fix:**
Add a role check inside `broadcast()` (or create a `broadcastToRole(roles, ...)` variant) so `sms:received` is only delivered to sockets where `ws.role` is in `['admin', 'manager', 'technician']` (roles that have `sms.view`). Alternatively use `sendToUser` for each user whose permissions include `sms.view`.

---

### [MEDIUM] voice:call_initiated and voice:inbound_call broadcast full call log (phone numbers, provider_call_id, transcription URL) to all tenant users

**Where:** `packages/server/src/routes/voice.routes.ts:162–164`, `voice.routes.ts:757`

**What:**
`voice:call_initiated` sends `{ call: callLog }` where `callLog = SELECT * FROM call_logs`, containing `from_number`, `to_number`, `conv_phone`, `provider_call_id`, `recording_url`, and `transcription`. `voice:inbound_call` sends `{ from: event.from, callId: event.providerCallId }` exposing the raw caller phone number. Both go to every socket in the tenant bucket with no voice/call permission check. There is no `voice.*` permission defined in `ROLE_PERMISSIONS`; the routes are gated by `authMiddleware` only.

**Code:**
```typescript
// voice.routes.ts:162
const callLog = await adb.get<AnyRow>('SELECT * FROM call_logs WHERE id = ?', ...);
broadcast('voice:call_initiated', { call: callLog }, req.tenantSlug || null);

// voice.routes.ts:757 — inbound webhook
broadcast('voice:inbound_call', { from: event.from, callId: event.providerCallId },
  req.tenantSlug || null);
```

**Exploit:**
A cashier's browser receives every outbound call event including who was called (`to_number`), the Twilio `provider_call_id` (correlatable with Twilio console), and later via a second broadcast, any recording URL. A cashier with no business reason to see call logs can build a list of every customer phone number dialed from the shop.

**Fix:**
Add a `settings.view` or a new `calls.view` permission and filter recipients in the WS broadcast path. For voice events that originate from unauthenticated webhooks (inbound/recording/transcription), the broadcast should use `broadcastToRole(['admin', 'manager', 'technician'], ...)`.

---

### [MEDIUM] management:stats, management:crash, and management:update_available leak server internals to all users in single-tenant mode

**Where:** `packages/server/src/index.ts:2380`, `index.ts:3886`, `services/githubUpdater.ts:337`

**What:**
All three broadcasts call `broadcast(event, data)` without a `tenantSlug` argument (default `null`). The `broadcast()` function routes to the `clientsByTenant` bucket keyed `'null'`. In **single-tenant mode** (`MULTI_TENANT !== 'true'`), every authenticated user's JWT has `tenantSlug = null`, so all users (including cashiers) are registered in the `'null'` bucket. They therefore receive: (a) process memory (RSS, heap), uptime, and request rate every 5 seconds via `management:stats`; (b) fatal crash entries including error message, route path, and redacted-but-partial stack trace via `management:crash`; (c) pending GitHub commit SHAs and commit messages via `management:update_available`.

**Code:**
```typescript
// index.ts:2380 — no tenantSlug, defaults to null → 'null' bucket → all single-tenant users
broadcast('management:stats', {
  uptime: process.uptime(), memory: { rss, heapUsed, heapTotal },
  activeConnections: allClients.size, requestsPerSecond, requestsPerMinute,
});
// index.ts:3886
try { broadcast('management:crash', entry); } catch { ... }
```

**Exploit:**
A cashier in a single-tenant shop opens DevTools, observes `management:stats` frames arriving every 5 seconds with exact heap usage, and `management:update_available` frames revealing the git commit SHA and commit message of the next pending update. If a crash occurs, they see the internal route path and error message — useful for reconnaissance before an attack.

**Fix:**
Pass an explicit `tenantSlug` of `'__management__'` (a never-issued JWT tenant) so the bucket is always empty for regular users, and deliver management events only to sockets where `ws.role === 'admin'` (or via a dedicated Electron IPC channel rather than the shared WS bus).

---

### [MEDIUM] TeamChat ticket channels readable/writable by any authenticated user — no ticket-access check

**Where:** `packages/server/src/routes/teamChat.routes.ts:58–66`, `index.ts:1779`

**What:**
`GET /api/v1/team-chat/channels/:id/messages` and `POST /api/v1/team-chat/channels/:id/messages` call `assertChannelAccess(ch, req)` which immediately returns for `kind === 'ticket'` (line 59). The routes are mounted behind `authMiddleware` only — no `requirePermission`. Any authenticated user (including a cashier who does not work repair tickets) can read or post to the internal discussion channel of any ticket, including channels for tickets they are not assigned to. Ticket channels are listed in `GET /channels` without filtering by ticket assignment.

**Code:**
```typescript
// teamChat.routes.ts:58–66
function assertChannelAccess(ch: ChannelRow, req: any): void {
  if (ch.kind === 'general' || ch.kind === 'ticket') return; // no check for 'ticket'
  ...
}
// index.ts:1779
app.use('/api/v1/team-chat', authMiddleware, teamChatRoutes); // no requirePermission
```

**Exploit:**
A cashier who knows (or guesses) a `channelId` can `GET /api/v1/team-chat/channels/42/messages` to read all internal technician notes for ticket #42 — including device security codes discussed in chat, internal pricing, or escalation notes. They can also `POST` to inject messages into the channel under their own name, potentially misdirecting the technician.

**Fix:**
For `kind === 'ticket'`, verify the caller has `requirePermission('tickets.view')` (add as a middleware on the message sub-routes), or check that `ticket_id` is accessible to the user via the standard tickets ACL. Add `requirePermission('tickets.view')` to the team-chat channel messages routes, or gate the entire `/channels/:id/messages` path with it.

---

### [LOW] voice:recording_ready leaks server filesystem path to all tenant users

**Where:** `packages/server/src/routes/voice.routes.ts:633`

**What:**
When a voice recording webhook fires, the recording is saved to disk and its absolute local path stored in `call_logs.recording_local_path`. The subsequent WS broadcast sends `{ callId: call.id, localPath }` where `localPath` is the actual server filesystem path (e.g. `/var/www/bizarrecrm/data/uploads/recordings/1746123456-a1b2.mp3`). This path reveals the server's directory structure and deployment layout to every connected tenant user.

**Code:**
```typescript
// voice.routes.ts:633
broadcast('voice:recording_ready', { callId: call.id, localPath }, req.tenantSlug || null);
```

**Exploit:**
An attacker with a cashier account receives `localPath = '/home/ubuntu/app/uploads/recordings/1746000000-c3d4.mp3'` — they learn the server's home directory, the app's upload path, and the fact that the service runs as `ubuntu`. This assists path traversal attempts on other endpoints.

**Fix:**
Strip `localPath` from the WS broadcast payload entirely; only emit `callId` and a relative public URL (if applicable). The client can fetch the recording via `GET /api/v1/voice/calls/:id/recording` which already enforces ownership.

---

### [LOW] pos.routes.ts broadcasts INVOICE_CREATED without tenantSlug — event silently dropped for all tenant users in multi-tenant mode

**Where:** `packages/server/src/routes/pos.routes.ts:1323`

**What:**
`broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id, order_id })` is called without a `tenantSlug` argument, so it defaults to `null` and routes to the `'null'` bucket (super-admin / management sockets only). In multi-tenant mode, all tenant users have a non-null `tenantSlug` and are in their own bucket — they never receive `invoice:created` events from POS checkout. This is a **functional gap** (missing real-time POS updates) that also implies there is no RBAC pressure being exerted on this broadcast path even though POS sales involve financial data.

**Code:**
```typescript
// pos.routes.ts:1323
broadcast(WS_EVENTS.INVOICE_CREATED, { invoice_id: inv.id, order_id: invoiceOrderId });
// missing third arg — req.tenantSlug || null
```

**Exploit:**
In multi-tenant mode a tenant's dashboard never refreshes when a POS sale completes — operators must manually reload. More importantly: if this is "fixed" by adding `req.tenantSlug || null`, that broadcast will start reaching cashiers, who would then also receive the associated `invoice:payment` event carrying payment details — confirming the broadcast-scope review is necessary before fixing the missing tenantSlug.

**Fix:**
Pass `req.tenantSlug || null` as the third argument. Before doing so, verify the payload (`{ invoice_id, order_id }`) contains no PII; it appears safe currently as it only carries IDs.

---

### [INFO] Binary WebSocket frames silently accepted and processed as UTF-8 text

**Where:** `packages/server/src/ws/server.ts:369`

**What:**
The `message` handler converts binary frames to UTF-8 strings unconditionally: `const raw = typeof data === 'string' ? data : data.toString('utf8')`. Binary frames are then parsed and handled exactly like text frames (auth, rate-limit checks, etc.). While no binary-specific logic exists, WAFs, IDS systems, and logging pipelines that inspect the WebSocket stream as UTF-8 text frames may miss binary-encoded auth attempts or obfuscated payloads.

**Code:**
```typescript
// ws/server.ts:369
const raw = typeof data === 'string' ? data : data.toString('utf8');
```

**Exploit:**
An attacker sends a binary WebSocket frame containing `{ "type": "auth", "token": "..." }`. The server accepts and processes it identically to a text frame. WAFs configured to inspect WS text frames only may miss this path.

**Fix:**
Explicitly reject binary frames before processing: `if (typeof data !== 'string') { ws.close(1003, 'text frames only'); return; }`. The current `ws` library passes `isBinary` as the second argument to `data`; check it.

---

### [INFO] sendToUser exported but never called anywhere in the codebase

**Where:** `packages/server/src/ws/server.ts:704`

**What:**
`sendToUser(userId, event, data, tenantSlug)` is exported but no module imports or calls it. All targeted delivery is done via `broadcast()` which sends to all users in a tenant bucket. The absence of per-user delivery means there is no mechanism for sending user-specific notifications (e.g. `notification:new`) over WebSocket — the `NOTIFICATION_NEW` WS event defined in `WS_EVENTS` is similarly never broadcast server-side.

**Fix:**
Either wire `sendToUser` to the notifications flow (route `notifications.routes.ts` DB inserts to `sendToUser` after write), or remove the dead export to reduce the attack surface review burden for future auditors.

---
