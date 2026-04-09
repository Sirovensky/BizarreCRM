# Multi-Tenancy Implementation Plan

*Created: 2026-04-04*

## Architecture Decision

**Database-per-tenant** with subdomain routing. Each repair shop gets:
- A subdomain: `repairshop1.bizarrecrm.com`
- Its own SQLite database: `data/tenants/repairshop1.db`
- Complete data isolation

A master database tracks all tenants, billing, and super-admin users. The existing self-hosted single-tenant mode continues to work via a `MULTI_TENANT` env flag.

---

## CRITICAL: Variable/Field Naming Convention

**Every new field, parameter, column, and API response key MUST match existing naming conventions.**

Before writing ANY new code:
1. Check how the EXISTING codebase names similar things
2. Use `snake_case` for: DB columns, API request/response fields, config keys
3. Use `camelCase` for: TypeScript/Kotlin variables, function names
4. Use `@SerializedName("snake_case")` in Kotlin DTOs to bridge the gap
5. Cross-reference against `packages/server/src/db/migrations/` for column names
6. Cross-reference against `packages/web/src/api/endpoints.ts` for API field names
7. Cross-reference against `packages/android/app/src/main/java/.../dto/` for DTO field names

**Common past mistakes to avoid:**
| Wrong | Correct | Why |
|-------|---------|-----|
| `customer_name` | `c_first_name` + `c_last_name` (list) or nested `customer.first_name` (detail) | Server remaps SQL aliases into nested objects |
| `price` | `retail_price` | Column name in `inventory_items` table |
| `is_pinned: Int` | `is_pinned: Boolean` | Server casts with `!!` before returning |
| `has_pin: Boolean` | `has_pin: Int` | SQLite `IS NOT NULL` returns 0/1, not cast by server |
| `payment_method_id: Long` | `method: String` | Server expects string like "cash", not an ID |
| `token` | `accessToken` | Server's refresh endpoint returns `accessToken` |
| `/notifications/read-all` | `/notifications/mark-all-read` | Actual endpoint path |
| `msg_text` | `content` | Ticket notes field name on server |
| `pre_conditions: String` | `pre_conditions: Any` | Can be `[]` (array) or `{}` (object) |

---

## Phase 0: Decouple `db` from Global Scope

**Goal:** Replace every `import { db } from '../db/connection.js'` with `req.db` so the database connection is per-request, not per-process.

### 0.1: Add `req.db` type declaration

New file: `packages/server/src/types/express.d.ts`
```typescript
import type Database from 'better-sqlite3';

declare global {
  namespace Express {
    interface Request {
      db: Database.Database;
      tenantSlug?: string;
      tenantId?: number;
    }
  }
}
```

### 0.2: Add db-injection middleware

New addition to `packages/server/src/index.ts`:
```typescript
// Inject db into every request — single-tenant uses global db,
// multi-tenant uses tenant-resolved db (set by tenantResolver middleware)
app.use((req, res, next) => {
  if (!req.db) req.db = db; // global db fallback
  next();
});
```

### 0.3: Refactor route files (27 files)

Each route handler changes from:
```typescript
// BEFORE
import { db } from '../db/connection.js';
router.get('/', (req, res) => {
  const rows = db.prepare('SELECT ...').all();
});
```
to:
```typescript
// AFTER — no db import needed
router.get('/', (req, res) => {
  const db = req.db;
  const rows = db.prepare('SELECT ...').all();
});
```

**Files to modify** (each file: remove `db` import, add `const db = req.db;` in each handler):
1. `routes/auth.routes.ts`
2. `routes/tickets.routes.ts`
3. `routes/customers.routes.ts`
4. `routes/invoices.routes.ts`
5. `routes/inventory.routes.ts`
6. `routes/pos.routes.ts`
7. `routes/sms.routes.ts`
8. `routes/employees.routes.ts`
9. `routes/settings.routes.ts`
10. `routes/leads.routes.ts`
11. `routes/estimates.routes.ts`
12. `routes/notifications.routes.ts`
13. `routes/search.routes.ts`
14. `routes/blockchyp.routes.ts`
15. `routes/catalog.routes.ts`
16. `routes/import.routes.ts`
17. `routes/automations.routes.ts`
18. `routes/snippets.routes.ts`
19. `routes/tv.routes.ts`
20. `routes/tracking.routes.ts`
21. `routes/reports.routes.ts`
22. `routes/expenses.routes.ts`
23. `routes/repairPricing.routes.ts`
24. `routes/customFields.routes.ts`
25. `routes/loaners.routes.ts`
26. `routes/rma.routes.ts`
27. `routes/admin.routes.ts`
28. `routes/preferences.routes.ts`
29. `routes/giftCards.routes.ts`
30. `routes/tradeIns.routes.ts`
31. `routes/refunds.routes.ts`

### 0.4: Refactor services (accept `db` parameter)

Services called from route handlers need `db` passed in:
```typescript
// BEFORE
import { db } from '../db/connection.js';
export function sendNotifications(ticketId: number) {
  const ticket = db.prepare('...').get(ticketId);
}

// AFTER
import type Database from 'better-sqlite3';
export function sendNotifications(db: Database.Database, ticketId: number) {
  const ticket = db.prepare('...').get(ticketId);
}
```

**Files to modify:**
1. `services/notifications.ts`
2. `services/automations.ts`
3. `services/blockchyp.ts`
4. `services/catalogScraper.ts`
5. `services/email.ts`
6. `services/repairDeskImport.ts`
7. `services/scheduledReports.ts`
8. `services/smsProvider.ts`
9. `utils/audit.ts`
10. `utils/validate.ts`
11. `db/seed.ts`
12. `db/migrate.ts`
13. `db/device-models-seed.ts`
14. `db/device-models-seed-runner.ts`

### 0.5: Refactor middleware

`middleware/auth.ts` — needs `db` from `req.db`:
```typescript
// BEFORE
import { db } from '../db/connection.js';
export function authMiddleware(req, res, next) {
  const session = db.prepare('SELECT ...').get(token);
}

// AFTER
export function authMiddleware(req, res, next) {
  const db = req.db;
  const session = db.prepare('SELECT ...').get(token);
}
```

### 0.6: Testing

After Phase 0, the app runs identically in single-tenant mode. Every `req.db` resolves to the same global `db` via the injection middleware. No behavioral change.

**Test:** Start server, verify all existing functionality works.

---

## Phase 1: Master Database & Tenant Infrastructure

### 1.1: Config additions

Modify `packages/server/src/config.ts`:
```typescript
// New fields (from env vars)
multiTenant: process.env.MULTI_TENANT === 'true',       // Feature flag
masterDbPath: path.resolve(dataDir, 'master.db'),        // Master DB location
tenantDataDir: path.resolve(dataDir, 'tenants'),         // Tenant DB directory
baseDomain: process.env.BASE_DOMAIN || 'bizarrecrm.com', // For subdomain extraction
superAdminSecret: process.env.SUPER_ADMIN_SECRET || '',   // JWT secret for super-admins
```

**Naming note:** These match existing config patterns: `uploadsPath`, `jwtSecret`, etc. Use camelCase for config keys.

### 1.2: Master database schema

New file: `packages/server/src/db/master-schema.sql`

```sql
-- Tenant registry
CREATE TABLE IF NOT EXISTS tenants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  domain TEXT,
  plan TEXT NOT NULL DEFAULT 'free',
  status TEXT NOT NULL DEFAULT 'active',
  db_path TEXT NOT NULL,
  admin_email TEXT NOT NULL,
  max_users INTEGER NOT NULL DEFAULT 5,
  max_tickets_month INTEGER NOT NULL DEFAULT 500,
  storage_limit_mb INTEGER NOT NULL DEFAULT 500,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Super-admin users (separate from tenant users table)
CREATE TABLE IF NOT EXISTS super_admins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  totp_secret TEXT,
  totp_secret_iv TEXT,
  totp_secret_tag TEXT,
  totp_secret_version INTEGER DEFAULT 1,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Monthly usage tracking per tenant
CREATE TABLE IF NOT EXISTS tenant_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id INTEGER NOT NULL REFERENCES tenants(id),
  month TEXT NOT NULL,
  tickets_created INTEGER NOT NULL DEFAULT 0,
  sms_sent INTEGER NOT NULL DEFAULT 0,
  storage_bytes INTEGER NOT NULL DEFAULT 0,
  active_users INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(tenant_id, month)
);

-- Billing records
CREATE TABLE IF NOT EXISTS billing_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id INTEGER NOT NULL REFERENCES tenants(id),
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  stripe_invoice_id TEXT,
  stripe_customer_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Global announcements to all tenants
CREATE TABLE IF NOT EXISTS announcements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Audit log for super-admin actions
CREATE TABLE IF NOT EXISTS master_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  super_admin_id INTEGER REFERENCES super_admins(id),
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  details TEXT,
  ip_address TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

**Naming note:** Column names match existing patterns: `created_at`/`updated_at` (not `createdAt`), `is_active` (not `isActive`), `password_hash` (matches existing `users` table pattern).

### 1.3: Master database connection

New file: `packages/server/src/db/master-connection.ts`

Opens `master.db` only when `config.multiTenant` is true. Exports `getMasterDb()` which returns the connection or null.

### 1.4: Tenant database pool

New file: `packages/server/src/db/tenant-pool.ts`

LRU cache of open tenant DB connections (max 50). Functions:
- `getTenantDb(slug: string): Database.Database` — open or return cached
- `closeTenantDb(slug: string): void`
- `closeAllTenantDbs(): void`

Each tenant DB connection has: WAL mode, foreign keys ON, busy timeout 5000ms (matching existing `connection.ts` pragmas).

### 1.5: Template database builder

New file: `packages/server/src/db/template.ts`

On startup (multi-tenant mode):
1. Creates `data/template.db` if missing
2. Runs all 40+ migrations from `db/migrations/`
3. Runs seed data (statuses, tax classes, payment methods, device models)
4. Does NOT create admin user (that's per-tenant)
5. Closes connection

Used as the source for `fs.copyFileSync()` when provisioning new tenants.

---

## Phase 2: Tenant Resolution Middleware

New file: `packages/server/src/middleware/tenantResolver.ts`

```typescript
export function tenantResolver(req, res, next) {
  if (!config.multiTenant) { next(); return; }

  const host = req.hostname; // "repairshop1.bizarrecrm.com"
  const baseDomain = config.baseDomain; // "bizarrecrm.com"

  // Extract subdomain
  const slug = host.replace(`.${baseDomain}`, '');
  if (slug === host || slug === 'www' || slug === 'master' || slug === 'api') {
    next(); return; // Not a tenant request
  }

  // Look up tenant in master DB
  const tenant = masterDb.prepare(
    'SELECT id, slug, status, db_path FROM tenants WHERE slug = ? AND status != ?'
  ).get(slug, 'deleted');

  if (!tenant) { res.status(404).json({ success: false, message: 'Shop not found' }); return; }
  if (tenant.status === 'suspended') { res.status(403).json({ success: false, message: 'Account suspended. Contact support.' }); return; }

  req.tenantSlug = slug;
  req.tenantId = tenant.id;
  req.db = getTenantDb(slug); // Overrides the global db injection
  next();
}
```

Wire in `index.ts` BEFORE auth middleware:
```typescript
app.use(tenantResolver); // Sets req.db to tenant DB
```

---

## Phase 3: Tenant Provisioning Service

New file: `packages/server/src/services/tenant-provisioning.ts`

```typescript
export async function provisionTenant(opts: {
  slug: string;       // subdomain — validated: a-z, 0-9, hyphens, 3-30 chars
  name: string;       // "Joe's Phone Repair"
  adminEmail: string;
  adminPassword: string;
  plan?: string;      // 'free' | 'starter' | 'pro' | 'enterprise'
}): Promise<{ tenantId: number; slug: string }>
```

Steps:
1. Validate slug (regex + reserved words check)
2. Check uniqueness in `masterDb.tenants`
3. `fs.copyFileSync('data/template.db', 'data/tenants/{slug}.db')`
4. Open the new DB, create admin user with bcrypt hash + generate PIN
5. Insert tenant record into `masterDb.tenants`
6. Create `uploads/{slug}/` directory
7. Return tenant ID

New file: `packages/server/src/routes/signup.routes.ts`

Endpoints (public, no auth):
- `POST /api/v1/signup` — `{ slug, shop_name, admin_email, admin_password }`
- `GET /api/v1/signup/check-slug/:slug` — returns `{ available: boolean }`

**Field naming note:** Request body uses `shop_name` (snake_case) matching API conventions, not `shopName`.

---

## Phase 4: Master Admin Panel

### 4.1: Master auth

New file: `packages/server/src/middleware/masterAuth.ts`

Separate JWT secret (`config.superAdminSecret`), separate token prefix. Super-admin tokens have `{ superAdminId, role: 'super_admin' }` payload — distinct from tenant JWTs which have `{ userId, tenantSlug }`.

### 4.2: Master admin API

New file: `packages/server/src/routes/master-admin.routes.ts`

All routes under `/master/api/`:

| Method | Path | Description |
|--------|------|-------------|
| POST | /master/api/login | Super-admin login |
| GET | /master/api/dashboard | Aggregate stats: total tenants, users, tickets, revenue |
| GET | /master/api/tenants | List all tenants with usage stats |
| POST | /master/api/tenants | Create tenant (admin provisioning) |
| GET | /master/api/tenants/:slug | Tenant detail: db size, user count, ticket count, plan |
| PUT | /master/api/tenants/:slug | Update plan, limits, status |
| POST | /master/api/tenants/:slug/suspend | Suspend tenant |
| POST | /master/api/tenants/:slug/activate | Reactivate tenant |
| DELETE | /master/api/tenants/:slug | Soft-delete (set status='deleted') |
| POST | /master/api/tenants/:slug/impersonate | Generate temp JWT for tenant's admin |
| GET | /master/api/tenants/:slug/usage | Usage history by month |
| GET | /master/api/billing | Billing overview across tenants |
| GET | /master/api/health | System health: total DB size, memory, CPU, open connections |
| GET | /master/api/announcements | List announcements |
| POST | /master/api/announcements | Create announcement |
| PUT | /master/api/announcements/:id | Update announcement |
| DELETE | /master/api/announcements/:id | Delete announcement |
| GET | /master/api/audit-log | Super-admin audit log |

### 4.3: Master admin frontend

New file: `packages/server/src/admin/master-admin.html`

Single-page HTML panel (like existing `/admin` backup panel pattern). Served at `master.bizarrecrm.com` or `/master-admin/`.

Features:
- Login form (super-admin credentials)
- Dashboard with KPI cards (total tenants, total revenue, system health)
- Tenants table with search, filter by status/plan
- Create tenant dialog (slug, name, email, plan)
- Tenant detail view (usage, billing, impersonate button)
- Suspend/activate/delete actions with confirmation
- Announcements manager
- System health panel

---

## Phase 5: Auth Token Changes

Modify `packages/server/src/routes/auth.routes.ts`:

JWT payload changes (multi-tenant mode):
```typescript
// BEFORE
const payload = { userId: user.id, role: user.role };

// AFTER
const payload = {
  userId: user.id,
  role: user.role,
  tenantSlug: req.tenantSlug || null, // null in single-tenant mode
};
```

Modify `packages/server/src/middleware/auth.ts`:

In multi-tenant mode, verify `decoded.tenantSlug` matches `req.tenantSlug` (prevents using a token from tenant A on tenant B's subdomain).

---

## Phase 6: WebSocket Tenant Isolation

Modify `packages/server/src/ws/server.ts`:

Client tracking changes from:
```typescript
Map<userId, WebSocket>
```
to:
```typescript
Map<tenantSlug, Map<userId, WebSocket>>
```

Broadcast functions gain tenant scope:
```typescript
export function broadcast(tenantSlug: string | null, event: string, data: unknown)
export function sendToUser(tenantSlug: string | null, userId: number, event: string, data: unknown)
```

All route files calling `broadcast()` pass `req.tenantSlug`:
- `tickets.routes.ts` (ticket_created, ticket_updated, ticket_status_changed)
- `sms.routes.ts` (sms_received)
- `notifications.routes.ts` (notification_new)
- `invoices.routes.ts`
- `pos.routes.ts`

---

## Phase 7: File Upload Isolation

Modify upload path logic:

```typescript
// In multi-tenant mode, uploads go to uploads/{slug}/
const uploadDir = config.multiTenant && req.tenantSlug
  ? path.join(config.uploadsPath, req.tenantSlug)
  : config.uploadsPath;
```

Files to modify:
- `routes/tickets.routes.ts` (photo uploads)
- `routes/sms.routes.ts` (MMS uploads)
- `routes/settings.routes.ts` (logo upload)
- `index.ts` (static file serving)

---

## Phase 8: Migration Runner for All Tenants

New file: `packages/server/src/db/migrate-all-tenants.ts`

```typescript
export function migrateAllTenants(): { succeeded: string[]; failed: { slug: string; error: string }[] }
```

Iterates all active tenants, runs pending migrations on each. Also refreshes template.db. Called:
- On server startup (multi-tenant mode)
- Via master admin API: `POST /master/api/migrate-all`

---

## Phase 9: Per-Tenant Backup Changes

Modify `packages/server/src/services/backup.ts`:

- Single-tenant: existing behavior (backup one DB)
- Multi-tenant tenant admin: backs up only that tenant's DB
- Master admin: can trigger backup of all tenants or a specific one

Master admin API:
- `POST /master/api/tenants/:slug/backup` — backup single tenant
- `POST /master/api/backup-all` — backup all tenant DBs

---

## Phase 10: Interval Tasks

Modify `packages/server/src/index.ts` scheduled tasks:

In multi-tenant mode, iterate all active tenants:
```typescript
if (config.multiTenant) {
  const tenants = masterDb.prepare("SELECT slug FROM tenants WHERE status = 'active'").all();
  for (const t of tenants) {
    const tdb = getTenantDb(t.slug);
    // Session cleanup, appointment reminders, etc.
  }
}
```

Tasks affected:
- Session cleanup (hourly)
- Appointment reminders (15-min cron)
- Catalog price sync (startup)
- Backup cron

---

## Phase 11: Signup & Landing Page

### 11.1: Landing page

Modify `packages/web/src/App.tsx`:

When on the bare domain (no subdomain), show a landing page instead of the CRM:
```typescript
const isBareDomain = !window.location.hostname.includes('.') ||
  window.location.hostname === 'bizarrecrm.com' ||
  window.location.hostname === 'www.bizarrecrm.com';

if (isBareDomain) return <LandingPage />;
```

New files:
- `packages/web/src/pages/landing/LandingPage.tsx` — marketing page
- `packages/web/src/pages/landing/SignupPage.tsx` — signup form

### 11.2: Tenant-aware login

The existing login page at `repairshop1.bizarrecrm.com/login` works as-is — the tenant resolver maps the subdomain to the right DB, and auth works within that DB.

---

## Phase 12: Nginx Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name *.bizarrecrm.com bizarrecrm.com;

    # Wildcard SSL via Let's Encrypt DNS challenge
    ssl_certificate     /etc/letsencrypt/live/bizarrecrm.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/bizarrecrm.com/privkey.pem;

    # Pass Host header so Express can extract subdomain
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # All requests go to the same Node.js backend
    location / {
        proxy_pass http://127.0.0.1:443;
    }

    # WebSocket upgrade
    location /ws {
        proxy_pass http://127.0.0.1:443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## Phase 13: Android App

**No code changes required.** The Android app already supports dynamic server URLs via login screen. Users enter `https://myshop.bizarrecrm.com` and the app works.

Future enhancement: "Find My Shop" — user types shop name, app constructs URL automatically.

---

## Implementation Order

```
Phase 0  → DB decoupling (43 files, mechanical, no behavior change)
Phase 1  → Master DB + tenant pool (5 new files)
Phase 2  → Tenant resolver middleware (1 new file)
Phase 5  → Auth token changes (2 files)
Phase 3  → Provisioning + signup (3 new files)
Phase 6  → WebSocket isolation (8 files)
Phase 7  → Upload isolation (4 files)
Phase 8  → Migration runner (1 new file)
Phase 10 → Interval tasks (1 file)
Phase 4  → Master admin panel (5 new files)
Phase 9  → Backup changes (1 file)
Phase 11 → Landing page (2 new files)
Phase 12 → Nginx config (1 file)
```

Total: ~16 new files, ~50 modified files.

---

## File Impact Summary

| Category | New Files | Modified Files |
|----------|-----------|----------------|
| DB/infrastructure | 6 | 4 |
| Middleware | 2 | 2 |
| Routes | 2 | 31 |
| Services | 1 | 10 |
| WebSocket | 0 | 1 |
| Frontend | 2 | 1 |
| Config/deploy | 0 | 3 |
| **Total** | **~16** | **~50** |

---

## Pricing Model (Suggestion)

| Plan | Price | Tickets/mo | Users | SMS | Storage |
|------|-------|-----------|-------|-----|---------|
| Free | $0 | 50 | 1 | 0 | 100 MB |
| Starter | $29/mo | 200 | 3 | 100 | 500 MB |
| Pro | $59/mo | Unlimited | 10 | 500 | 2 GB |
| Enterprise | $99/mo | Unlimited | Unlimited | Unlimited | 10 GB |

All cheaper than RepairDesk ($99+/store for Essential).

---

## Backwards Compatibility

The `MULTI_TENANT` env flag controls everything:

| Mode | Behavior |
|------|----------|
| `MULTI_TENANT=false` (default) | Exactly the same as today. No master DB, no subdomain resolution, global `db` used for everything. Self-hosted single shop. |
| `MULTI_TENANT=true` | Master DB created, tenant resolver active, subdomain routing enabled. Signup available. Master admin panel accessible. |

No existing functionality is broken in either mode.
