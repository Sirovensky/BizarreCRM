# BizarreCRM

Custom repair shop CRM for [Bizarre Electronics](https://bizarreelectronics.com) — replacing RepairDesk ($99+/mo) with a self-hosted, fully owned solution.

**57,000+ lines of code** across 213 files — full-stack TypeScript monorepo.

| Layer | Stack |
|-------|-------|
| Server | Node.js 22 + Express 4 + TypeScript (ESM) |
| Database | SQLite via better-sqlite3 (WAL mode, async worker threads) |
| Web | React 19 + Vite 6 + Tailwind CSS 3 |
| Dashboard | Electron 39 + React 19 + Vite (Windows EXE) |
| Auth | JWT + TOTP 2FA + bcrypt |
| Real-time | WebSocket (ws library) |
| Payments | BlockChyp terminal integration |
| SMS | 3CX WebSocket + protobuf |

## Deploy (Windows — 3 steps)

1. Install **[Node.js 22 LTS](https://nodejs.org/)** — check **"Automatically install necessary tools"** when prompted (adds Python + C++ build tools)

2. **[Download the latest release](https://github.com/Sirovensky/BizarreCRM/archive/refs/heads/main.zip)** and extract it

3. Open the extracted folder and double-click **`setup.bat`**

That's it. The script installs dependencies, generates secrets, creates SSL certs, builds the frontend and dashboard, and starts the server. Your browser opens automatically to `https://localhost:443` — log in with `admin` / `admin123`.

> **Updating:** Install **[Git](https://git-scm.com/download/win)** for one-click updates. The Management Dashboard has an Update button that runs `git pull` + rebuild + restart automatically. Without Git, re-download the ZIP and run `setup.bat` again (your data in `packages/server/data/` is preserved).

### What setup.bat does

| Step | Action |
|------|--------|
| [1/7] | Verifies Node.js 20+ is installed |
| [2/7] | `npm install` — all workspaces, compiles native modules |
| [3/7] | Creates `.env` with cryptographically random JWT secrets |
| [4/7] | Generates self-signed SSL certs (via Git's bundled OpenSSL) |
| [5/7] | `npm run build` — compiles React frontend for production |
| [6/7] | Builds + packages Management Dashboard EXE |
| [7/7] | Starts server, waits for ready, opens browser + dashboard |

### Production SSL & domain

For a real domain, replace the self-signed certs:

```
packages/server/certs/server.cert   # Your PEM certificate (+ chain)
packages/server/certs/server.key    # Your PEM private key
```

Edit `.env` and set `BASE_DOMAIN=yourdomain.com`. For multi-tenant setup, see the **Self-Hosting (Multi-Tenant)** section below.

#### Automated Let's Encrypt wildcard cert (recommended for multi-tenant)

<details>
<summary>Click to expand — one script sets it up, auto-renews every 60 days</summary>

Multi-tenant installs should use a **wildcard SSL cert** covering `*.yourdomain.com` + the apex. Combined with a wildcard DNS record (grey cloud on free Cloudflare), this eliminates a subtle UX issue: if a user's browser ever queries a subdomain before the shop is provisioned (manual typing, following a stale link, etc.), Windows caches the `NXDOMAIN` response for up to 30 minutes. When the shop is then created, the user still sees "Server Not Found" until they flush DNS — which is not a production-acceptable experience.

With a wildcard cert + wildcard DNS, **every possible subdomain resolves to your origin and is served over valid HTTPS**. Un-provisioned subdomains get a clean HTTP 404 "Shop not found" from the server's tenant resolver. No NXDOMAIN ever reaches any browser.

**Prerequisites:**
- Cloudflare account with your domain
- `.env` on the server with `CLOUDFLARE_API_TOKEN` (scoped to `Zone.DNS:Edit`), `CLOUDFLARE_ZONE_ID`, `SERVER_PUBLIC_IP`, and `BASE_DOMAIN` already set
- PowerShell 5.1+ (built into Windows 10/11/Server 2016+)

**Setup — one time:**

1. **Add a wildcard DNS A record in Cloudflare** — DNS → Records → Add record:
   | Type | Name | IPv4 | Proxy |
   |---|---|---|---|
   | A | `*` | your server public IP | **DNS only (grey cloud)** |

   Wildcard proxying requires a paid CF plan; grey cloud is what we want anyway (the wildcard is a safety net, not a performance layer). Specific per-shop orange-cloud records created by the CF API integration take precedence over the wildcard.

2. **Run the setup script** as Administrator from the project root:
   ```powershell
   cd C:\path\to\bizarre-crm
   powershell.exe -ExecutionPolicy Bypass -File scripts\setup-wildcard-cert.ps1
   ```

   The script:
   - Installs the `Posh-ACME` PowerShell module (from PSGallery, trusted scope)
   - Creates a Let's Encrypt account for `admin@yourdomain.com`
   - Requests a wildcard cert via DNS-01 challenge using your `CLOUDFLARE_API_TOKEN` (writes `_acme-challenge` TXT records, waits for propagation, retrieves the signed cert)
   - **Backs up** the existing `server.cert`/`server.key` to `.selfsigned.bak` files (preservation rule — nothing is deleted)
   - Installs the new cert at `packages/server/certs/server.cert` + `server.key`
   - Registers a daily Windows Scheduled Task named `BizarreCRM-LE-Renew` that runs `scripts/renew-wildcard-cert.ps1` at 03:17 to handle renewals

3. **Restart the server** to pick up the new cert:
   ```powershell
   pm2 restart bizarre-crm
   ```

**Verification:**

```powershell
# Cert SAN should list your wildcard + apex
& "C:\Program Files\Git\usr\bin\openssl.exe" x509 -in packages\server\certs\server.cert -noout -text | Select-String "DNS:"

# Un-provisioned subdomain should return HTTP 404 with valid LE cert (not "Server Not Found")
curl.exe -v https://totally-fake-shop-xyz.yourdomain.com/

# Scheduled task should be Ready
Get-ScheduledTask -TaskName "BizarreCRM-LE-Renew" | Format-List TaskName, State, Triggers
```

**Renewals:**

LE certs are valid 90 days. The scheduled task runs daily and checks if the cert is within 30 days of expiry (Posh-ACME's default window). When it renews, it copies the new files to `packages/server/certs/` and restarts pm2 automatically. Most days the task is a fast no-op. All activity is logged to:

```
packages\server\data\logs\le-renew.log
```

**If something goes wrong**, roll back to the self-signed cert:
```powershell
Copy-Item packages\server\certs\server.cert.selfsigned.bak packages\server\certs\server.cert -Force
Copy-Item packages\server\certs\server.key.selfsigned.bak  packages\server\certs\server.key  -Force
pm2 restart bizarre-crm
```

**Security note:** all cert files (`*.cert`, `*.key`, `*.pem`, `.bak` copies in `packages/server/certs/`) are gitignored and will never be committed. Posh-ACME's state (account keys, cached cert orders) lives in `$env:LOCALAPPDATA\Posh-ACME\` outside the repo.

</details>

### Self-Hosting (Multi-Tenant)

<details>
<summary>Click to expand — full setup for hosting multiple shops on subdomains</summary>

Multi-tenant mode gives each shop its own subdomain and isolated database: `shopname.yourdomain.com`. All configuration flows from **one file** (`.env`).

#### 1. Set your domain in `.env`

```env
MULTI_TENANT=true
BASE_DOMAIN=yourdomain.com

# Cloudflare DNS auto-provisioning (recommended — see step 2A)
CLOUDFLARE_API_TOKEN=
CLOUDFLARE_ZONE_ID=
SERVER_PUBLIC_IP=
```

`BASE_DOMAIN` is the single source of truth — the setup script reads it to generate nginx config. The three `CLOUDFLARE_*` / `SERVER_PUBLIC_IP` vars are optional but enable automatic subdomain provisioning (no more manual DNS work per shop).

#### 2. DNS — pick one of two paths

##### Option A — Cloudflare API auto-provisioning (recommended)

With a Cloudflare API token in `.env`, BizarreCRM creates one proxied A record per shop automatically on signup. Cloudflare's free-plan Universal SSL covers every first-level subdomain, so there's nothing to manage per shop — no wildcards, no cert rotation, no nginx server_name edits.

**One-time DNS record** — add just the apex:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `yourdomain.com` | your server public IP | Proxied (orange cloud) |

**Create a scoped API token:**

1. Cloudflare dashboard > top-right profile > **My Profile** > **API Tokens** > **Create Token**
2. Use **Custom token**. Name it `bizarrecrm-dns-provisioning`
3. **Permissions**: `Zone` > `DNS` > `Edit` (single row, nothing else)
4. **Zone Resources**: `Include` > `Specific zone` > your domain
5. **Continue to summary** > **Create Token** > copy the token (shown once)

**Find your Zone ID:** Cloudflare dashboard > your domain > right sidebar > **API** section > **Zone ID**.

**Paste all three values into `.env`** (from step 1 above).

When a new tenant is provisioned — via self-serve signup, the super-admin panel, or `POST /super-admin/api/tenants` — the server calls the Cloudflare API and creates `shopname.yourdomain.com` → `SERVER_PUBLIC_IP`, proxied. Deletion removes the record. Suspension leaves it alone (so reactivating is instant).

**Backfilling existing tenants** — if you already have shops that were created before enabling auto-provisioning, run the idempotent backfill:

```bash
cd bizarre-crm && npx tsx scripts/backfill-cloudflare-dns.ts
```

It reuses any records that already exist for a slug and only creates missing ones.

##### Option B — Manual wildcard (any DNS provider)

If you're not using Cloudflare or don't want to grant the server API access, add a wildcard record instead:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `yourdomain.com` | your server IP | Proxied (if Cloudflare) |
| A | `*.yourdomain.com` | your server IP | DNS only (free plan) or Proxied (paid plan) |

The wildcard makes `shopname.yourdomain.com` resolve. Without it (and without Option A configured), browsers show "Server Not Found" even though the bare domain works.

**Cloudflare free plan:** Wildcard DNS-only (grey cloud) works fine. Wildcard proxying (orange cloud) requires a paid plan — with DNS-only, your origin handles SSL directly and you'll need a wildcard cert (see step 3).

#### 3. SSL — Cloudflare Origin Certificate (recommended)

If using Cloudflare, skip certbot entirely. Create an Origin Certificate that covers the wildcard:

1. Cloudflare dashboard > **SSL/TLS** > **Origin Server** > **Create Certificate**
2. Add hostnames: `yourdomain.com` and `*.yourdomain.com`
3. Save the certificate and key to your server:
   ```bash
   sudo mkdir -p /etc/ssl/cloudflare
   sudo nano /etc/ssl/cloudflare/origin.pem       # paste certificate
   sudo nano /etc/ssl/cloudflare/origin-key.pem    # paste private key
   sudo chmod 600 /etc/ssl/cloudflare/origin-key.pem
   ```
4. Set SSL mode to **Full (Strict)** in Cloudflare > SSL/TLS

Origin certs are free, valid for 15 years, and auto-trusted by Cloudflare's edge. No renewal needed.

<details>
<summary>Not using Cloudflare? Use Let's Encrypt instead</summary>

```bash
sudo certbot certonly --manual --preferred-challenges dns \
  -d 'yourdomain.com' -d '*.yourdomain.com'
```

Update the cert paths in `deploy/nginx.conf.template` to point to `/etc/letsencrypt/live/yourdomain.com/`.

</details>

#### 4. Generate and install nginx config

```bash
# Generate deploy/nginx.conf from .env
bash deploy/setup.sh

# Install it
sudo cp deploy/nginx.conf /etc/nginx/sites-available/bizarrecrm
sudo ln -sf /etc/nginx/sites-available/bizarrecrm /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

The `deploy/setup.sh` script reads `BASE_DOMAIN` from `.env` and generates `deploy/nginx.conf` from `deploy/nginx.conf.template`. Re-run it any time you change the domain.

#### 5. Start the server

```bash
cd packages/server && npx tsx src/index.ts
```

#### 6. Create a tenant

Open the Management Dashboard or use the super-admin API:

```bash
# Via super-admin API
curl -k -X POST https://yourdomain.com/super-admin/api/tenants \
  -H "Authorization: Bearer YOUR_SUPER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"slug": "myshop", "name": "My Shop", "adminEmail": "admin@myshop.com", "plan": "pro"}'
```

If you set up **Option A** in step 2, the DNS record for `myshop.yourdomain.com` is created automatically during provisioning — the shop is accessible the moment the API call returns. Check the server logs for `[CloudflareDNS] Created A record for myshop.yourdomain.com → ...` to confirm. If DNS creation fails, the entire provisioning is rolled back so you never end up with an orphaned tenant row.

If you chose **Option B** (manual wildcard), the shop is accessible as soon as the tenant row exists — no per-shop DNS work needed because the wildcard covers it.

#### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Server Not Found" in browser on a new shop | Neither Option A nor Option B configured | Pick one: add Cloudflare token (A) or wildcard DNS record (B) |
| Signup returns "Failed to configure subdomain" | Cloudflare API token invalid, missing `Zone.DNS:Edit`, or scoped to wrong zone | Verify the token in Cloudflare > My Profile > API Tokens; re-test with `curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records` |
| Auto-DNS works but shop shows cert warning | Record is grey-cloud (DNS only) instead of orange | Confirm records in CF dashboard show the orange proxy icon; delete + re-provision if needed |
| Existing tenants still 404 after enabling Option A | Records weren't backfilled | Run `npx tsx scripts/backfill-cloudflare-dns.ts` from `bizarre-crm/` |
| SSL error / cert mismatch (Option B only) | Origin cert doesn't cover the wildcard | Get a wildcard cert (step 3) or switch to Option A |
| "Shop not found" JSON response | `BASE_DOMAIN` mismatch or tenant not created | Check `.env` matches your domain; create tenant (step 6) |
| Works on bare domain, 404 on subdomain (Option B only) | Nginx `server_name` not wildcarded | Re-run `bash deploy/setup.sh` and reload nginx |

</details>

### Migrating existing data

| Path | Contains | Copy? |
|------|----------|-------|
| `packages/server/data/tenants/*.db` | Customer, ticket, invoice data | **Yes** — this IS your data |
| `packages/server/data/master.db` | Tenant registry (multi-tenant) | **Yes** if multi-tenant |
| `packages/server/uploads/` | Photo attachments | **Yes** |
| `node_modules/` | Dependencies | **No** — install fresh |

### Deploy on Linux

<details>
<summary>Click to expand</summary>

```bash
# Prerequisites
sudo apt install git build-essential python3 libvips-dev libcairo2-dev libjpeg-dev
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs

# Install
git clone https://github.com/Sirovensky/BizarreCRM.git && cd BizarreCRM
npm install && npm run build
cp .env.example .env   # then edit with real secrets + domain

# SSL (self-signed or place real certs)
openssl req -x509 -newkey rsa:2048 -keyout packages/server/certs/server.key -out packages/server/certs/server.cert -days 3650 -nodes -subj "/CN=BizarreCRM"

# Run with PM2
npm install -g pm2
pm2 start ecosystem.config.js && pm2 save && pm2 startup
```

</details>

## Features

- **POS / Check-in kiosk** — customer lookup, device selection, repair pricing, cart, checkout
- **Ticket management** — statuses, assignments, notes, photos, history, calendar, kanban
- **Customer management** — multiple phones/emails, FTS search, lifetime analytics
- **Invoice & payments** — generate from tickets, record payments, void with stock restore
- **Inventory** — products/parts/services, stock tracking, low stock alerts, supplier catalog scraping
- **SMS communications** — threaded conversations, templates, flags/pins
- **BlockChyp terminal** — signature capture at check-in, card payments, tip prompts
- **Supplier catalog** — scrape Mobilesentrix/PhoneLcdParts, import parts, order queue
- **Reports** — sales, tickets, employees, inventory, tax, CSV export, period comparison
- **RepairDesk import** — full migration of customers, tickets, invoices, inventory, SMS
- **Admin backup panel** — scheduled SQLite backups + uploads folder, drive browser
- **Server Dashboard (EXE)** — Electron desktop app for server management, runs CRM as Windows Service, multi-tenant admin, crash monitoring, real-time stats with historical metrics
- **Security** — TOTP 2FA, rate limiting, CORS, CSP, audit logging (60+ pen tests passing)
- **Print** — receipts (80mm/58mm thermal), labels (4x2), letter size
- **TV display** — public screen showing active tickets
- **Customer tracking** — public status page for customers

## Management Dashboard (Electron EXE)

The server is managed via a standalone Electron desktop app (`packages/management/`). It runs the CRM as a **Windows Service** completely independent of the dashboard process.

```
[Dashboard EXE]              [Windows Service: BizarreCRM]
  React UI (renderer)          Node.js CRM Server (port 443)
  IPC bridge (main)            Express + SQLite + WebSocket
  sc.exe (service ctrl)
       |                              |
       +--- REST API (localhost) -----+
       +--- sc.exe commands ----------+
```

| Page | Description |
|------|-------------|
| Overview | Live stats (memory, CPU, uptime, RPS, DB size, connections), historical request rate graph (1h–6m) |
| Tenant Management | Create/suspend/activate/delete tenants (multi-tenant mode) |
| Server Control | Start/stop/restart service, emergency stop, auto-start toggle |
| Backups | Drive browser, schedule config, manual backup, history |
| Crash Monitor | Crash log, auto-disabled routes, re-enable controls |
| Updates | One-click update (git pull + build + restart) |
| Audit Log | Admin actions with timestamps and IPs |
| Sessions | Active admin sessions with revoke |

Build: `cd packages/management && npm run build && npm run package`

## Development Setup

<details>
<summary>Click to expand</summary>

### Prerequisites

- **Node.js 20+** — [download](https://nodejs.org/)
- **Git** — [download](https://git-scm.com/)

### 1. Clone and install

```bash
git clone https://github.com/Sirovensky/BizarreCRM.git
cd BizarreCRM
npm install
```

### 2. Create environment file

```bash
cp .env.example .env
```

### 3. Start the server

```bash
cd packages/server
npx tsx src/index.ts
```

On first start: runs migrations, seeds defaults, creates admin user (`admin` / `admin123`).

### 4. Start the frontend dev server

```bash
cd packages/web
npx vite --host
```

### 5. Access

- **CRM**: https://yourshop.localhost:443
- **Admin panel**: https://localhost:443/admin

Login with `admin` / `admin123`. Set up 2FA on first login.

</details>

## Optional Configuration

<details>
<summary>BlockChyp, SMS, Email, RepairDesk Import</summary>

### BlockChyp Payment Terminal

Go to Settings > BlockChyp in the CRM. Enter API Key, Bearer Token, Signing Key.

### SMS via 3CX

Add to `.env`: `TCX_HOST`, `TCX_USERNAME`, `TCX_PASSWORD`, `TCX_EXTENSION`, `TCX_STORE_NUMBER`

### Email (SMTP)

Add to `.env`: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`

### RepairDesk Import

Go to Settings > Data Import. Enter your RepairDesk API key and click "Full Import".

### Backups

Access the admin panel at `https://localhost:443/admin` to configure backup location, schedule, and retention.

</details>

## Project Structure

```
bizarre-crm/
  setup.bat              # One-click Windows deployment
  packages/
    server/              # Express API + SQLite (104 files, ~17k LOC)
      src/
        db/              # Migrations (40+), seeds, connection, worker pool
        routes/          # 25+ route files (async worker threads)
        services/        # BlockChyp, email, SMS, backup, import, scraper, metrics
        middleware/       # Auth, error handling, rate limiting, idempotency
    web/                 # React SPA (82 files, ~37k LOC)
      src/
        pages/           # 30+ page components
        components/      # Shared UI (command palette, modals, skeleton, etc.)
    management/          # Electron Dashboard EXE
      src/
        main/            # Electron main process (IPC bridge, service control)
        renderer/        # React SPA (dashboard UI)
```

## Security

- TOTP 2FA mandatory for all users, plus user self-service disable (password + TOTP) and admin force-disable for incident response
- JWT access tokens signed with pinned HS256 + issuer + audience claims, idle-session timeout (14 d), concurrent-session cap (5 per user)
- Constant-time login path that accepts username OR email with no timing oracle
- PIN-switch-user requires 2FA re-verification when the target has 2FA enabled
- Password history (last 5) + session revocation on every password reset; backup-code-based lost-phone recovery flow
- Persistent rate limiting (SQLite) on login, 2FA, PIN, portal, signup, tracking, imports — survives restarts
- Helmet security headers (CSP, HSTS, X-Frame-Options, Referrer-Policy, nosniff), WebSocket origin allowlist, strict Host header validation
- File upload magic-byte validation (not just Content-Type), ClamAV-ready scan hook, per-tenant file-count quota
- Audit logging on every privileged action with old/new values for tenant mutations, 2-year retention by default
- Stripe webhook event-age + idempotency enforcement, BlockChyp transaction-ref uniqueness via atomic counters, per-invoice payment idempotency keys
- Backups encrypted with dedicated key (not JWT secret) + version header + integrity-check + disk-space guard + per-tenant locks
- Tenant DB files are sacred: deletion archives instead of unlinking, 30-day grace period, data-export helper
- 60+ penetration tests passed across auth, injection, XSS, access control, file attacks, DoS, and API abuse categories

### Pre-Production Audit

A comprehensive pre-production audit (`criticalaudit.md`) identified 150+ bugs across 41 sections — correctness, security, multi-tenant isolation, money handling, race conditions, and data integrity. Every CRITICAL/HIGH/MEDIUM finding was addressed in a single sweep via parallel focused fixes covering:

- **Lies about success** — SMS, email, automations, webhooks now surface real failures instead of fake `success: true`
- **ID generation** — atomic `counters` table (migration 072) replaces race-prone `MAX(...)+1` on tickets, invoices, POs, SKUs, BlockChyp refs
- **Money** — integer-cents arithmetic on Android entities, `validatePrice`/`validatePositiveAmount`/`validateSignedAmount` helpers, refund caps, credit note overflow to store credit
- **Inventory** — atomic guarded stock decrement (`in_stock >= ?`), PO receive in a transaction, CSV import all-or-nothing, kit expansion helper
- **Multi-tenant** — no more cross-tenant automation fires, WSS origin allowlist, strict Host header validation, tenant-scoped sync scripts
- **SQL injection** — whitelist-only dynamic table/trigger names, LIKE wildcard escaping
- **Android** — removed negative temp IDs (`OFFLINE-{n}`), Room money → `Long` cents + FK cascades, SyncManager dead-letter, TLS cert pinning (release) + hostname-restricted dev trust, SQLCipher integration path documented
- **Web** — DOMPurify on all user-editable print content, single-flight token refresh, `rememberSaveable`-style effect cleanup, stale pagination guard
- **Billing** — Stripe webhook age check, payment-failure grace period + downgrade, BlockChyp idempotency via `(invoice_id, client_request_id)` uniqueness
- **Backups** — encrypted restore endpoint with integrity check + safety copy, per-tenant mutex, versioned file header
- **Reports** — real COGS / margin / tax (no more hardcoded 100% margin lies), export-all path, LEFT JOIN instead of dropping rows

See `criticalaudit.md` for the full finding-by-finding mapping.

## License

Private — Bizarre Electronics internal use.
