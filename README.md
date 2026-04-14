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

## CRM & Marketing

Audit §49 CRM/marketing enrichment ships a full customer-relationships layer on
top of the core shop workflow. All twelve ideas from the audit are implemented
as part of the wave-2 enrichment sweep. Backing migration: `092_crm_marketing.sql`.

### Customer enrichment

- **Health score (0-100)** — RFM model combining recency (40 pts), frequency
  (30 pts), and monetary (30 pts). Tiered as **Champion** (80+), **Healthy**
  (50-79), or **At-Risk** (<50). Renders as a colored badge on the customer
  detail page. Recalculated daily via cron helper + on-demand via the UI
  (`POST /api/v1/crm/customers/:id/health-score/recalculate`).
- **Lifetime-value tier badges** — Bronze / Silver / Gold / Platinum, derived
  from `customers.lifetime_value_cents` and displayed next to the name on the
  profile header.
- **Photo mementos wallet** — horizontal scrolling gallery of the customer's
  last 12 months of repair photos, clickable through to the original ticket.
- **Wallet pass (Apple / Google)** — dynamic HTML card with loyalty points,
  referral code, and tier (`GET /api/v1/crm/customers/:id/wallet-pass`).
  Signed `.pkpass` generation is stubbed and falls back to HTML until the
  owner wires Apple Developer certs in `store_config`.
- **Referral code generator** — short per-customer share code (e.g. `MIKE-A1B2`)
  tracked in the portal-owned `referrals` table. Both referrer and referee
  earn credit when the portal enrichment layer closes the loop.

### Marketing automations

- **Birthday SMS campaigns** — stored `birthday` column (MM-DD), daily cron
  helper `POST /api/v1/campaigns/birthday/dispatch` targets the "Birthday
  this week" segment with a warm template + offer.
- **Win-back campaigns** — the built-in "Inactive 6+ months" auto-segment
  powers one-click bulk SMS to dormant customers.
- **Review request automation** — fired on ticket pickup via
  `POST /api/v1/campaigns/review-request/trigger`. High ratings funnel to
  Google Reviews; low ratings go to private feedback (coordinated with the
  customer portal `customer_reviews` flow from migration 089).
- **Churn warning on unpaid invoices** — daily cron scans invoices with
  balance > 0 and age ≥ 14 days, then sends a dunning SMS with a payment-plan
  link. Exposed as `POST /api/v1/campaigns/churn-warning/dispatch`.
- **Smart auto-segments** — rule engine over health score, LTV, ticket
  frequency, last-interaction days, and birthday window. Seeded segments:
  `VIP $5K+`, `Inactive 6mo+`, `At-risk`, `Champions`, `Birthday this week`.
- **NPS trend page** — 0-10 promoter/detractor chart fed by the reports-owned
  `nps_responses` table from migration 090.
- **Service subscriptions** — recurring $5/mo screen protection, $10/mo
  battery replacement, etc. Stored in `service_subscriptions`; billing loop
  is wave-2 (BlockChyp / Stripe integration).

### TCPA compliance

Every SMS campaign honors `customers.sms_opt_in`. Email campaigns honor
`customers.email_opt_in`. When the SMS provider silently falls back to the
console transport (see critical audit §1 L1-L4), `dispatchCampaign()`
records a `failed` campaign send with `response` set to
`SMS provider not configured (console fallback)` — the UI never lies about
delivery.

### Pages

| Route | Page | Purpose |
|-------|------|---------|
| `/marketing/campaigns` | `CampaignsPage` | Campaign CRUD + preview + run-now + stats |
| `/marketing/segments` | `SegmentsPage` | Rule builder + member drill-down |
| `/marketing/referrals` | `ReferralsDashboard` | Leaderboard + conversion rate |
| `/marketing/nps` | `NpsTrendPage` | Monthly NPS trend + recent responses |

### Key endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/crm/customers/:id/health-score` | Current score + tier |
| POST | `/api/v1/crm/customers/:id/health-score/recalculate` | Recompute + persist |
| GET | `/api/v1/crm/customers/:id/ltv-tier` | Lifetime-value tier + cents |
| GET | `/api/v1/crm/customers/:id/photo-mementos` | Last 12 months of photos |
| GET | `/api/v1/crm/customers/:id/wallet-pass` | HTML pass (or .pkpass with `?format=pkpass`) |
| POST | `/api/v1/crm/customers/:id/referral-code` | Mint (or re-use) referral code |
| POST | `/api/v1/crm/customers/:id/subscription` | Create service subscription |
| GET/POST/PATCH/DELETE | `/api/v1/crm/segments[/…]` | Segment CRUD |
| POST | `/api/v1/crm/segments/:id/refresh` | Re-evaluate segment rule |
| GET/POST/PATCH/DELETE | `/api/v1/campaigns[/…]` | Campaign CRUD |
| POST | `/api/v1/campaigns/:id/run-now` | Dispatch to segment immediately |
| POST | `/api/v1/campaigns/:id/preview` | Dry-run: count + sample rendered body |
| GET | `/api/v1/campaigns/:id/stats` | Sent/reply/convert counts |

## Communications Team Inbox

Audit section 51 — the shared team-inbox enrichment layer that sits on top of the existing `sms_messages` / `sms_templates` / `conversation_*` tables. Migration `094` adds assignment, tagging, retry queue, sentiment log, template analytics, and inbox-scoped store config keys without modifying any existing route file.

### What ships today

- **Shared assignment** — each conversation can be claimed by one user via a pill on the thread header. `PATCH /inbox/conversation/:phone/assign` writes to `conversation_assignments`. The left-panel header shows a "Mine / All" filter so technicians can focus on their own queue.
- **Per-user unread badges** — `conversation_read_receipts` tracks each user's `last_read_at` separately, so "unread for Mike" differs from "unread for Sarah". `GET /inbox/unread-count` returns a fresh count scoped to the caller.
- **Conversation tags** — manual tags (v1) rendered as removable pills beside the assignee. Presets: `waiting-for-parts`, `repair-complete`, `follow-up`. Filter the inbox via `GET /inbox/conversations?tags=...`. Auto-tagging is v2 and requires NLP.
- **Canned-response hotkeys** — `Ctrl+1 / Ctrl+2 / Ctrl+3` insert the first three SMS templates into the compose textarea. Hotkeys respect strict rules: they **never autosend**, **never overwrite free-typed text**, and a preset can only replace another preset (tracked in an internal ref). Disabled unless the compose textarea is focused.
- **Bulk SMS with double-submit protection** — admin-only modal. Step 1: preview count + request confirmation token. Step 2: re-submit with the token to enqueue. Tokens are HMAC-derived from `segment | template_id | user_id | 5-min-bucket` so they expire after 5 minutes and cannot be forged. Segments supported: `open_tickets`, `all_customers`, `recent_purchases`.
- **SMS delivery retry UI** — red "Failed Sends" card on the empty state. `sms_retry_queue` tracks `retry_count` + `next_retry_at` with exponential backoff (1m / 5m / 15m / 1h / 3h / 12h / 24h). Each row has Retry / Cancel buttons.
- **Customer sentiment detection** — `useSentimentDetect` hook classifies inbound text via keyword matching. `angry` (terrible / broken / scam / awful / worst), `happy` (thanks / great / awesome / perfect / love it), `urgent` (asap / urgent / emergency / right now / immediately). Pure client-side — no external AI. Server mirror at `POST /inbox/sentiment/analyze` logs to `sms_sentiment_history` for future reporting.
- **Template analytics** — `GET /inbox/template-analytics` aggregates `sms_template_analytics` counter rows. Surfaced as a dashboard card on the empty state: "Phone ready — sent 847x — 12% reply rate". The `/inbox/template-analytics` rows are not yet auto-incremented from sms.routes (file ownership restriction); the table + endpoint are ready for a follow-up hook that trips the counters on template-based sends and inbound replies within 24h.
- **Off-hours auto-reply toggle** — switchable flag stored in `store_config` (`inbox_off_hours_autoreply_enabled` + `inbox_off_hours_autoreply_message`). Admin-only, scoped through `PATCH /inbox/config` so it does not touch the global settings whitelist. Wires into the existing business-hours logic already in the automations engine.
- **SLA tracking dashboard** — `GET /inbox/sla-stats?days=30` computes average first-response time (seconds between an inbound and the next outbound on the same `conv_phone`) over a rolling window. Shown as "2.3m avg" in the team-inbox header.
- **Scheduled send modal** — richer alternative to the inline datetime popover. Presets ("In 1 hour", "Tomorrow 9am") plus a full datetime picker. `Alt+click` on the existing schedule button opens it.
- **Quick SMS attachment button** — standalone component that wraps the existing MMS upload backend (`/sms/upload-media`). Currently mounted invisibly so it can replace the inline paperclip button in a follow-up PR without re-wiring compose state.

### v2 and out-of-scope items

Audit section 51 lists ideas 7, 8, 9, 10, and 14 as product decisions rather than code bugs — they ship as documentation in this release:

- **Missed call -> voicemail transcription** — out of scope. STT is handled by the voice provider (Twilio, Telnyx, Bandwidth); the backend hook points already exist at `voice.routes.ts`. The missed-call row in the call log is a "call back" button that dials through the existing `POST /voice/call` endpoint.
- **Compliance archive toggle** — a `store_config` key (`inbox_compliance_archive_years`) exists so regulated shops can document their 7-year retention intent. No cron job runs today. A future `services/backup.ts` job should honor the flag and move aged rows to `sms_messages_archive`.
- **WhatsApp / iMessage integration** — v2. Requires provider-specific adapters in `providers/sms/`. Migration 094 keeps the existing `provider` column open-ended (`TEXT`) so those providers can be added without schema churn.
- **Translation micro-service (EN/ES toggle)** — v2. Requires an external API (DeepL, Google Translate, OpenAI). Not wired because the project rule is zero external AI calls.

### API endpoints

All mounted at `/api/v1/inbox` with `authMiddleware`. Bulk send and off-hours config additionally require `req.user.role === 'admin'` inline (same pattern as `automations.routes.ts`).

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/inbox/conversations?assigned_to=me\|all\|unassigned&tags=...` | List conversations with assignment + tags |
| PATCH | `/inbox/conversation/:phone/assign` | Claim / unclaim a conversation |
| POST | `/inbox/conversation/:phone/tag` | Add a tag |
| DELETE | `/inbox/conversation/:phone/tag/:tag` | Remove a tag |
| POST | `/inbox/conversation/:phone/mark-read` | Update per-user read receipt |
| GET | `/inbox/unread-count` | Per-user unread count |
| POST | `/inbox/bulk-send` | Admin-only two-step bulk dispatch |
| GET | `/inbox/retry-queue` | List pending / failed retries |
| POST | `/inbox/retry-queue/:id/retry` | Schedule the next attempt |
| POST | `/inbox/retry-queue/:id/cancel` | Cancel a retry |
| GET | `/inbox/template-analytics` | Sent + reply-rate per template |
| POST | `/inbox/sentiment/analyze` | Server-logged sentiment classification |
| GET | `/inbox/sla-stats?days=30` | Average first-response time |
| GET | `/inbox/config` | Inbox-scoped store config keys |
| PATCH | `/inbox/config` | Admin-only update of `inbox_*` store config |

## Onboarding & Day-1 Experience

When a brand-new shop finishes the setup wizard and lands on the dashboard, BizarreCRM does not leave them staring at a row of "$0" KPIs. The Day-1 feature set (migration `086`, routes `/api/v1/onboarding/*`) turns the empty state into a guided tour that the owner can follow step-by-step — or skip at any point.

### What ships today

- **Getting-Started checklist widget** (`GettingStartedWidget.tsx`) — a sticky card above the KPIs that walks the owner through Create customer -> Open ticket -> Send estimate -> Generate invoice -> Record payment. Completion is tracked server-side via milestone timestamps (`first_customer_at`, `first_ticket_at`, `first_invoice_at`, `first_payment_at`) so the client cannot fake progress. Every step is a direct deep-link to the relevant page. A progress bar shows the trackable milestones at a glance.
- **Skippable at any point** — the audit is adamant about this. The widget has a "Skip for now" button (dismisses for the session) and a "Don't show again" button (persists `checklist_dismissed = true` via `PATCH /onboarding/state`). When all trackable milestones are done, the widget fades to a congratulations message and self-hides.
- **Sample data toggle** (`SampleDataCard.tsx`, `services/sampleData.ts`) — one click creates 5 demo customers, 10 tickets, and 3 invoices, all tagged visibly with `[Sample]`. A matching "Remove sample data" button deletes exactly the rows that were inserted (not "anything containing the word Sample") by tracking the `{type, id}` pairs in `onboarding_state.sample_data_entities_json`. The card only shows when the shop has no real customers yet.
- **Shop-type picker** (`StepShopType.tsx`, new wizard phase) — Phone repair / Computer repair / Watch repair / General electronics. Picking a type calls `POST /onboarding/set-shop-type`, which writes the type to `onboarding_state.shop_type` and installs a small bundle of starter SMS templates tailored to that shop type. **Richer starter content (repair pricing catalog, device library, intake checklists) is deliberately v2** — the original audit note requests that we populate one DB with known good historical data first and curate a seed before shipping rich templates. For now the picker is useful and non-blocking: you can skip it entirely and change it later in Settings.
- **Success celebrations** (`SuccessCelebration.tsx`) — confetti burst + toast when a new milestone timestamp is set. Fires at most once per session per milestone via a `sessionStorage` diff, so refreshing the page doesn't re-trigger. Respects `prefers-reduced-motion`.
- **Keyboard shortcut reference card** (`ShortcutReferenceCard.tsx`) — the header gets a `?` button (and a global `?` keyboard shortcut suppressed while typing) that opens a popover listing `Ctrl+K`, `Esc`, `F2`, `F3`, `F4`, `Ctrl+Enter`, `Ctrl+S`. One source of truth lives in the component — update it when global shortcuts change.
- **Feature-discovery nudge flags** — the backend tracks `nudge_day3_seen`, `nudge_day5_seen`, `nudge_day7_seen`. The schema and PATCH allowlist exist today; the UI surface that fires them (Day 3 bulk SMS, Day 5 repair pricing, Day 7 automations) can be layered on top without another migration.
- **Progressive settings unlock flag** — `onboarding_state.advanced_settings_unlocked` is persisted so settings pages can hide advanced tabs until the owner flips the toggle. Same PATCH allowlist as above; no new endpoints needed to enable per-tab gating.
- **Intro-video dismissible flag** — `intro_video_dismissed` in `onboarding_state` lets a dashboard card be shown once and then dismissed forever.

### API surface

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/onboarding/state` | Return the single `onboarding_state` row (lazily seeded). |
| `PATCH /api/v1/onboarding/state` | Allowlisted boolean flag updates. Unknown keys return 400 instead of silently no-op'ing. |
| `POST /api/v1/onboarding/sample-data` | Insert 5 customers + 10 tickets + 3 invoices, tag them, persist entity list. Idempotent. |
| `DELETE /api/v1/onboarding/sample-data` | Delete exactly the sample rows via the stored entity list. |
| `POST /api/v1/onboarding/set-shop-type` | Record shop type + install starter SMS templates. |

All endpoints require `authMiddleware`, follow the `{ success: true, data: ... }` envelope, and are audited via `utils/audit.ts`.

### Improvements over the raw audit suggestions

- The **checklist progress is server-authoritative** (milestone timestamps), not client-side. The audit asked for a checklist; making it tamper-proof was a free upgrade with one extra column per milestone.
- **Sample-data removal is byte-for-byte reversible** via tracked entity IDs, not a blind `WHERE name LIKE '%Sample%'`. A real user who genuinely types the word "Sample" into a tag won't lose anything.
- **Shop-type bundle is idempotent** — re-running `POST /set-shop-type` with the same type is safe because the starter template installer uses `INSERT OR IGNORE` on the `sms_templates.name` natural key.
- **Success celebrations use `sessionStorage`, not `localStorage`** — a one-time celebration should still fire when the owner comes back the next morning, but not on every tab-switch. The audit didn't specify, but this is the right call.
- **Shortcut card has a dedicated `?` keyboard shortcut** in addition to the header button, with a guard to avoid capturing the key while the user is typing in an input.

### What is intentionally deferred

- **Curated repair-pricing and device-model seeds per shop type** — requires the ops team to hand-pick a "known good" production DB to extract from, per the audit's own v2 note. Schema hooks exist (`onboarding_state.shop_type`) so this is a drop-in later.
- **Bulk-SMS / automations / repair-pricing feature-discovery toasts** — the `nudge_day*_seen` flags exist; wiring the client-side effects that fire them is a separate small PR.
- **Embedded 2-min intro video card** — the dismissible-card mechanism ships today (`intro_video_dismissed` flag); the actual video URL + card placement on the dashboard is a follow-up UI commit.
- **Mobile-first iPad view** (audit idea 12) — orthogonal to the rest of the Day-1 set; belongs with the responsive-layout pass.

## Settings UX

The settings page used to be a 21-tab horizontal scroll where 65 of 70 toggles silently did nothing — the critical pre-launch audit (section 50) flagged that as the single biggest trust problem in the app. The Configuration UX enrichment ships an honest, searchable, guided settings surface that fixes that.

### Setup Progress (first tab)

- **`SetupProgressTab.tsx`** lives at the front of the page now — before Store Info, before Billing — so brand-new shops immediately see what's still missing instead of getting lost in 21 tabs of toggles. It pulls from `GET /onboarding/state`, `GET /settings/store`, `GET /settings/tax-classes`, `GET /settings/payment-methods`, and `GET /settings/users` and shows a tracked checklist: store info, shop type, tax classes, payment methods, team members, first ticket, first invoice, SMS provider.
- Each item has a **"Go" button that jumps to the relevant tab** — no more "where do I configure that?" hunting. Critical items get a red `Critical` pill so admins know which gaps will break invoices or notifications.
- **Server-authoritative completion** — checks like "first ticket created" come from `onboarding.first_ticket_at`, not a local flag. The user cannot fake progress.
- A live progress bar (`completedCount / totalCount`) sits in the hero card. When everything is done it turns green.

### Honest "Coming Soon" badges (the trust fix)

- **`settingsMetadata.ts`** is the single source of truth for every setting in the app. Each entry has a `status` of `live`, `beta`, or `coming_soon` and a tooltip explaining what the toggle does and who should enable it. Currently 30+ POS / receipt / notifications / 3CX toggles are honestly marked `coming_soon` instead of pretending to work.
- **`ComingSoonBadge.tsx`** renders next to those toggles so users see *exactly* which switches are still aspirational. The audit was explicit: "make the lie visible so users stop trusting silence."
- The settings page header now shows **"X live, Y coming soon"** as a hard count drawn from the metadata. Whenever a backend wires a toggle up, flipping the status to `live` decrements that number automatically — no second source of truth to keep in sync.

### Search across all tabs (`SettingsSearch.tsx`)

- The old header search only filtered the tab list. The new search runs against label, tooltip, tab name, and per-setting keywords from `SETTINGS_METADATA`. Type "passcode" and you get every setting in any tab that mentions it, with status pills (`Live` / `Beta` / `Soon`).
- Picking a result navigates to the correct tab and **scrolls to the matched setting with a 2-second ring-pulse highlight** (via `data-setting-key` markers on the actual DOM rows).
- Keyboard friendly — `↑/↓` to move, `Enter` to pick, `Esc` to close.

### Unsaved-changes guard (`UnsavedChangesGuard.tsx`)

- Settings tabs register their dirty state via the `useUnsavedChanges()` context. Switching tabs (or even closing the browser tab) prompts a confirm modal: "You have unsaved changes. Discard?"
- Wires up a `beforeunload` listener for browser-level guard, an `Escape`/`Enter` keymap on the modal, and the new `setActiveTab` becomes async — `await confirmNavigate()` short-circuits the navigation when the user picks "Stay."

### Live receipt preview (`ReceiptLivePreview.tsx`)

- The Receipts tab now has a sticky preview pane that mirrors the structure of the printed receipt: store title, header, line items (demo data), totals, terms, footer, barcode. Editing any of those fields updates the preview instantly — no more printing test receipts to verify a typo.
- Switches between letter / 58mm / 80mm preview widths to match the receipt-default-size dropdown.

### Other quality-of-life pieces

- **`ResetDefaultsButton.tsx`** — per-tab "Reset to defaults" with a confirm prompt. Defaults come straight from `settingsMetadata.ts` so there is one source of truth.
- **`SettingsChangeHistory.tsx`** — in-tab audit log slice (admins only) reading from `GET /settings/audit-logs` filtered to settings_* events.
- **`BulkActionsBar.tsx`** — one-click bulk operations like "Enable all notifications", "Enable all safety requirements", "Hide coming-soon toggles". Each action whitelists the keys it touches.
- **`SettingsTooltip.tsx`** — small `?` icon next to obscure settings; reads from `settingsMetadata.ts` tooltip strings on hover/click. Touch-friendly.

### Backend support — `settingsExport.routes.ts` (mounted at `/api/v1/settings-ext`)

A new route file owned by the configuration-UX agent — it deliberately does NOT touch the existing `settings.routes.ts` (owned by an earlier agent), so the two surfaces can evolve independently.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/v1/settings-ext/export.json` | Sanitized JSON dump of all `store_config` rows. Strips secrets via `EXPORT_BLACKLIST`. Decrypts encrypted values for portability. Sends `Content-Disposition` so browsers download as `bizarrecrm-settings-YYYY-MM-DD.json`. Audited as `settings_exported`. |
| POST | `/api/v1/settings-ext/import` | Validated JSON import. Accepts both `{ settings: {...} }` (new) and a flat `{ key: value }` map (old export format). Rejects unknown keys against the same allow-list as `settings.routes.ts`, returns `{ imported, skipped, total }`. |
| GET | `/api/v1/settings-ext/templates` | Lists shop-type templates (`phone_repair`, `computer_repair`, `watch_repair`, `general_electronics`) with descriptions and setting counts. Coordinates with the onboarding agent's shop-type picker. |
| POST | `/api/v1/settings-ext/templates/apply` | Applies a shop-type template — bulk-updates safe defaults without wiping unrelated settings. Validated via `validateEnum`. |
| GET | `/api/v1/settings-ext/history` | Settings-only audit log slice (`event LIKE 'settings_%'`) for the in-tab change history card. Optional `tab` filter via meta JSON. |
| POST | `/api/v1/settings-ext/bulk` | Bulk update with a 100-key cap and a labeled audit entry. Used by the BulkActionsBar component. |

All endpoints require `authMiddleware` plus an explicit `adminOnly` middleware for writes; reads are admin-only too except `/templates`. Every mutation is audited. Encrypted keys round-trip through `configEncryption.ts` so secrets stay sealed in the DB.

### Files added or touched

| File | Purpose |
|------|---------|
| `packages/web/src/pages/settings/settingsMetadata.ts` | **Single source of truth**. Honest status flag, tooltips, defaults, validation bounds, role gates per setting. |
| `packages/web/src/pages/settings/tabs/SetupProgressTab.tsx` | First-tab onboarding checklist. |
| `packages/web/src/pages/settings/components/SettingsSearch.tsx` | Cross-tab setting-level search with highlight-on-arrival. |
| `packages/web/src/pages/settings/components/UnsavedChangesGuard.tsx` | Context provider, dirty tracking, navigation guard, beforeunload. |
| `packages/web/src/pages/settings/components/ReceiptLivePreview.tsx` | Live preview pane for the Receipts tab. |
| `packages/web/src/pages/settings/components/ResetDefaultsButton.tsx` | Per-tab reset with confirm prompt. |
| `packages/web/src/pages/settings/components/SettingsChangeHistory.tsx` | In-tab audit log card. |
| `packages/web/src/pages/settings/components/BulkActionsBar.tsx` | Predefined multi-toggle bulk actions. |
| `packages/web/src/pages/settings/components/ComingSoonBadge.tsx` | Honest UI badge for non-functional toggles. |
| `packages/web/src/pages/settings/components/SettingsTooltip.tsx` | `?` icon resolving tooltip text from metadata. |
| `packages/web/src/pages/settings/SettingsPage.tsx` | Minimal edit — wraps in `UnsavedChangesProvider`, swaps the old tab-only search for `SettingsSearch`, injects `setup-progress` as the first tab. |
| `packages/server/src/routes/settingsExport.routes.ts` | New backend support routes — export, import, templates, history, bulk. Mounted at `/api/v1/settings-ext`. |
| `packages/server/src/index.ts` | Registers the new route under `authMiddleware`. |

### Why the metadata file is the keystone

When the audit said "65 of 70 toggles do nothing" the immediate fix is to be honest about it — not to invent 65 new backend features overnight. By centralizing the *truth* about which settings are wired in `settingsMetadata.ts`, we get five things at once:

1. The `Coming Soon` badges in the UI are automatic and never lie — flip a `status: 'coming_soon'` to `'live'` and the badge disappears.
2. The header counts (`30 live, 18 coming soon`) come from the same metadata so the user can see the trust ratio at a glance.
3. The search results show the same status pills as the inline badges — consistent everywhere.
4. The reset-to-defaults flow reads defaults from the metadata so we never have to maintain a second copy.
5. Future agents adding a setting MUST register it in metadata or the `Coming Soon` badge silently shames them — peer pressure as a code-quality tool.

## Business Intelligence Reports

The reports and dashboard surface is built as two layers: the legacy 12-tab `/reports` page (sales, tickets, employees, inventory, tax, etc.) and a newer **Business Intelligence layer** that surfaces the numbers an owner actually looks at on Monday morning. The BI layer lives in `packages/web/src/components/reports/` and is rendered first on the Dashboard (above the date-range picker) for admin and manager roles.

**Hero KPI — gross margin with zones**

- **Profit hero card** sits at the top of the dashboard. 30-day gross margin shown as a single big number with a color: green (`>= 50%` by default), amber (`>= 30%`), red below. The label under the number tells you *why* the zone matters. Clicking the gear opens an in-place editor to move the green/amber cutoffs; the new thresholds are saved in `store_config.profit_threshold_green / _amber`. Endpoint: `GET /reports/profit-hero` (+ `PATCH /reports/profit-hero/thresholds`).
- **Trend vs. average** — `GET /reports/trend-vs-average` returns 12 weeks of daily revenue plus a this-week-vs-average delta so "am I up or down" is one number.

**Operational signals**

- **Cash trapped in inventory** — the dollar value tied up in items that have not moved in 90+ days, plus the top 5 offenders by name. Endpoint: `GET /reports/cash-trapped`.
- **Churn detection** — customers who have not been seen in 90+ days, sorted by lifetime value so you win back the biggest first. Endpoint: `GET /reports/churn?days_inactive=90`.
- **Busy-hours heatmap** — a 7x24 grid colored by ticket volume, used to right-size staffing. Endpoint: `GET /reports/busy-hours-heatmap?days=30`.
- **Overstaffing hours** — inverse of the heatmap. Any (day, hour) slot where ticket volume is less than half the active tech count is flagged. Endpoint: `GET /reports/overstaffing`.
- **Repair-fault statistics** — which categories drive the most tickets. Endpoint: `GET /reports/fault-statistics`.
- **Inventory turnover by category** — trailing 90-day turns per category with healthy / slow / stagnant labels. Endpoint: `GET /reports/inventory-turnover`.
- **Demand forecast** — 12-month unit history by category with a simple trend (vs. prior 3 months) and a next-month projection. Endpoint: `GET /reports/demand-forecast?months=12`.

**People**

- **Technician leaderboard** — tickets closed, revenue, and CSAT (from the NPS table) over week/month/quarter. Endpoint: `GET /reports/tech-leaderboard?period=month`.
- **Top-10 repeat customers** — ranked by lifetime spend with per-customer share of total revenue and a combined headline. Endpoint: `GET /reports/repeat-customers?limit=10`.
- **Most-profitable day of week** — rolling 90-day revenue grouped by weekday to guide scheduling. Endpoint: `GET /reports/day-of-week-profit`.
- **NPS survey + trend** — post-pickup survey entries stored in `nps_responses`. Submitted via `POST /reports/nps`; monthly trend at `GET /reports/nps-trend`.

**PDF / email delivery**

- **Tax report one-click** — `GET /reports/tax-report.pdf?from=...&to=...&jurisdiction=...` returns an HTML report with a Print-to-PDF button. Opens from `packages/web/src/pages/reports/TaxReportPage.tsx`.
- **Partner / lender report** — `GET /reports/partner-report.pdf?year=...` returns a YTD summary with revenue, gross profit, margin, outstanding receivables, and inventory value. Served by `packages/web/src/pages/reports/PartnerReportPage.tsx`.
- **Weekly auto-summary email** — every Monday at 08:07 local the `services/reportEmailer.ts` loop sends a summary of the last 7 days to each row in `scheduled_email_reports` with `report_type = 'weekly_summary'`. Metrics: revenue, tickets closed, new customers, average ticket, top 5 parts, top 5 technicians.
- **Scheduled delivery** — owners schedule arbitrary recurring reports via `POST /reports/schedule-email` (body: `{ name, recipient_email, report_type, cron_schedule }`). Listed at `GET /reports/scheduled`, removed at `DELETE /reports/scheduled/:id`.

**Schema** — backing tables live in `packages/server/src/db/migrations/090_reports_bi_enhancements.sql`: `nps_responses`, `scheduled_email_reports`, `report_snapshots`. The two profit-hero thresholds are inserted into `store_config` by the same migration.

**Access control** — every endpoint in this layer goes through `requireAdminOrManager`. Technicians see the simplified `TechDashboard` instead.

## Customer Portal Enhancements

The customer portal ships with a repair-tracking layer above the base ticket view. The goal is "the customer opens the portal, sees exactly where their repair is, and leaves without calling." Most items are switchable from store settings so shops can turn off anything that doesn't fit their workflow.

**Live repair story**

- **Status timeline** — "Checked in 10:30 -> Diagnosed 12:15 -> Parts ordered -> Ready for pickup". Built from the existing `ticket_history` table, so every status change the tech makes already flows through with no extra input. Rendered as a vertical list with ARIA semantics for screen readers.
- **Queue position** — "You're 4th in line; estimated wait 4-5h". Switchable from store settings: `none` (hide it), `phones` (show only for phone repairs, where ETAs are reliable), or `all` (show for every device). Config key: `portal_queue_mode`.
- **Tech photo + first name** — "John is handling your repair" with an optional avatar. Two gates: a global `portal_show_tech` toggle and a per-user `portal_tech_visible` opt-in so no tech is displayed without their consent.
- **Before / after photos** — techs mark which photos are customer-visible via the `ticket_photos_visibility` table. The customer scrolls a before row and an after row. Accidentally-uploaded "after" photos can be removed from the portal view for a configurable window (`portal_after_photo_delete_hours`, default 24h). Deletes are soft — the backend flips `customer_visible` to 0 so the internal audit trail stays intact.

**Pay, prove, and pick up**

- **Pay Now** — Stripe-hosted checkout with Apple Pay and Google Pay. Falls back to "call the shop" if the billing module has not been configured yet.
- **Receipt download** — on-demand print-friendly HTML generated server-side (browsers can "Save as PDF" from the print dialog). No pdfkit / puppeteer dependency.
- **Warranty certificate** — downloadable proof of repair with a unique certificate number, coverage period, and terms snapshot. Persisted in `warranty_certificates` so the same PDF link always returns the same certificate.
- **Pickup reminder SMS** — handled by the existing status-change notification flow (configured in Settings > Notifications), not by a separate portal feature.

**Marketing hooks (schema only — marketing module owns the UI)**

- **Review prompt** — 5-star modal shown after pickup. Ratings at or above `portal_review_threshold` (default 4) are forwarded to the shop's Google Reviews URL; ratings below are stored privately in `customer_reviews` so owners can respond without public damage. Schema is shared with the marketing module.
- **Loyalty points + referrals** — `loyalty_points` ledger (append-only, balance = SUM) and `referrals` (unique code per referrer, reward on conversion). Switchable via `portal_loyalty_enabled`. The portal shows the balance and a "copy your referral code" button; the marketing agent owns the campaign UI, email templates, and automatic reward application.

**Trust, clarity, access**

- **Trust badges + shop info** — encrypted-connection and secure-payments badges, plus the shop's address, phone, and hours prominently above the fold.
- **SLA guarantee banner** — customizable and switchable: "Standard repairs ready within 2 business days." Config keys `portal_sla_enabled` and `portal_sla_message`.
- **FAQ tooltips** — inline "What does *Awaiting Parts* mean?" popovers attached to status labels.
- **Spanish + browser auto-detect** — lightweight in-file dictionary (`packages/web/src/pages/portal/i18n.ts`) with `en` and `es` translations. Respects `navigator.language` on first load and remembers the customer's explicit choice in `localStorage`. No heavy i18next dependency.
- **Dark mode + a11y toolbar** — font size +/- (persisted), high-contrast toggle, dark mode toggle, ARIA labels on every interactive element, keyboard-focusable controls.

**Intentionally skipped**

- **In-portal live chat widget** — not implemented. The existing SMS thread + "Text Us" button already gives customers a way to reach the shop; a separate chat channel would only create a second source of truth for conversations.

### Portal API (v2)

Mounted at `/portal/api/v2/` in `packages/server/src/routes/portal-enrich.routes.ts`. All endpoints require a valid portal session cookie or `Authorization: Bearer <token>`; ticket-scoped sessions may only read the ticket they were issued for.

| Endpoint | Purpose |
|---|---|
| `GET /ticket/:id/timeline` | Ordered status history |
| `GET /ticket/:id/queue-position` | Respects `portal_queue_mode` |
| `GET /ticket/:id/tech` | Tech name + avatar (if opted in) |
| `GET /ticket/:id/photos` | Customer-visible before/after photos |
| `DELETE /ticket/:id/photos` | Soft-hide an "after" photo within the delete window |
| `GET /ticket/:id/receipt.pdf` | Print-friendly receipt HTML |
| `GET /ticket/:id/warranty.pdf` | Print-friendly warranty certificate HTML |
| `POST /ticket/:id/review` | 1-5 star + optional comment, routes to Google Reviews funnel if rating >= threshold |
| `GET /customer/:id/loyalty` | Points balance + recent history |
| `POST /customer/:id/referral-code` | Get-or-create a unique referral code |
| `GET /config` | Portal switches for the UI (queue mode, SLA, loyalty, etc.) |

### Migration

Schema lives in `packages/server/src/db/migrations/089_portal_enrichment.sql`:

- `warranty_certificates` — one per closed ticket, append-only
- `customer_reviews` — shared schema with the marketing module
- `loyalty_points` — append-only ledger
- `referrals` — unique codes, conversion tracking
- `ticket_photos_visibility` — per-photo customer-visible flag with before/after tagging
- `users.portal_tech_visible` — per-tech opt-in for the tech card
- `store_config` defaults for every switchable feature above

## Technician Bench Workflow

The "bench" is where a repair actually happens — a tech with a screwdriver, a customer's phone in pieces, and five other tickets waiting. Every extra click, every re-typed model number, every forgotten QC check is wasted minutes. This section is the set of features that sit directly on top of the existing ticket flow to compress those minutes away. They are all **additive and per-store switchable** — a shop that wants the classic free-form ticket experience can disable every one of them and keep working exactly as before.

**Device repair templates** — a shop's most common jobs (iPhone 13 screen, MacBook battery, Samsung S22 back glass) are saved once as reusable templates under **Settings > Device Templates**. Each template captures parts (with quantities pulled from inventory), labor minutes, labor cost, suggested customer-facing price, warranty days, and a diagnostic checklist. On any open ticket, the **Repair Templates** sidebar card lets a tech browse or search templates filtered to the current device category, then one-click apply — the parts flow onto the ticket, the labor estimate is logged, and the checklist items are appended to the ticket's open checklist. This is the cross-cutting feature that also powers POS walk-in repair pricing and inventory usage reporting, so there is exactly one source of truth for "what does an iPhone 13 screen job contain?".

**Parts-per-repair live stock** — each template part displays a live stock badge (green = enough, yellow = some, red = out of stock) pulled at render time from `inventory_items.in_stock`. When any part is red, the template card surfaces an inline "parts out of stock" hint so the tech knows, *before* applying, that the ticket will need to park at "Awaiting parts". No more applying a template and then discovering mid-repair that the screen is back-ordered.

**Pre-flight intake checklist** — the existing ticket checklist feature is preserved. Templates now pre-seed it with diagnostic steps (inspect cracks, check water damage, test power, capture IMEI) so every repair starts with a consistent pre-flight pass. Tenant-specific items can still be added by the tech on the fly.

**Bench timer** — optional per-store (`bench_timer_enabled` in `store_config`, OFF by default). When enabled, the sidebar shows a live HH:MM:SS counter with **Start / Pause / Resume / Stop** controls. Starting a timer on a new ticket while another is running auto-stops the old one on the server — a tech can only be in one place at a time. Stopping logs total duration minus paused time, multiplies by the store's labor rate (`bench_labor_rate_cents`), and records a `bench_timers` row that aggregates into payroll reports. Every start and stop writes to the audit log.

**Customer history sidebar** — a new card on the ticket detail page shows the customer's last 5 previous repairs with thumbnails, dates, and totals. When a previous repair's device matches the current ticket's device, the row is highlighted amber and a **Repeat Fault** badge appears at the top of the card — giving the tech an instant warranty-risk signal before they start work.

**QC sign-off modal** — optional per-store (`qc_required` flag). Admin-editable checklist lives under **Settings > Bench & QC**: each item is scoped to a device category ("phone", "tv", etc.) or global. Before marking a ticket complete the tech opens the **QC Sign-Off** modal, ticks every active checklist item, attaches a photo of the working device, and draws a signature on a canvas pad. The server refuses sign-off unless every item is `passed=true` and both images are present. A `qc_sign_offs` row is recorded for audit and warranty claims.

**Parts defect reporter** — a one-click **Report defect** button on any installed part opens a modal for defect type (DOA / intermittent / cosmetic / wrong spec), optional description, and optional photo. The server logs the report to `parts_defect_reports`, counts the last 30 days of defects for that SKU, and if the count crosses the configured threshold (`defect_alert_threshold_30d`, default 4) fires a `defect_alert` notification to the procurement queue — "LCD model X has 4 defects in 30 days". A `GET /bench/defects/stats?days=30` endpoint returns the top defective parts for the procurement dashboard.

**Concurrent-bench multi-device support** — the ticket detail page already supports multiple devices per ticket via `ticket_devices`. Bench timer, template picker, and QC sign-off all accept an optional `ticket_device_id` so a tech working on a 3-phone ticket can time and sign-off each device independently.

**Scanner-ready endpoints** — the new routes are scoped so an Android barcode scanner (ML Kit, roadmap) can hit `POST /bench/timer/start` with a scanned ticket ID and auto-start the clock. Likewise, `POST /bench/defects/report` accepts multipart form data suitable for a phone camera upload.

**Voice notes** — explicitly deferred. The audit flagged it as "really hard to do, add last". The route file (`bench.routes.ts`) contains a TODO for a future `POST /bench/voice-note` endpoint that would accept an audio blob and return transcribed text from a local/server-side model.

**Where it lives** — server-side in `packages/server/src/db/migrations/087_device_model_templates.sql`, `088_bench_timer_qc_defects.sql`, `routes/deviceTemplates.routes.ts`, and `routes/bench.routes.ts`. Client-side in `packages/web/src/components/tickets/` (BenchTimer, DeviceTemplatePicker, CustomerHistorySidebar, QcSignOffModal, DefectReporterButton) and `pages/settings/DeviceTemplatesPage.tsx`. Mounted at `/api/v1/device-templates` and `/api/v1/bench` in `packages/server/src/index.ts`.

## Android Field Use

The companion Android app in `packages/android` is the "off the desk" surface for technicians — the tablet on the bench, the phone on the sales floor, the Samsung Tab with the S Pen sitting on the counter for customer drop-off signatures. It mirrors the desktop CRM's core flows (tickets, customers, POS, inventory, SMS) with offline-first sync and a set of Android-specific enrichments aimed at reducing friction during a repair day.

**Quick-in / quick-out**

- **Biometric quick-unlock** — optional fingerprint / face prompt on launch using `BiometricPrompt`. Falls back to device PIN. Off by default; enable it under **Settings > Device Preferences**. Permission `USE_BIOMETRIC` is already declared.
- **Front-facing dashboard FAB** — one-tap menu for the day's most common actions: New ticket, New customer, Log sale (POS), Scan barcode / IMEI. Built as an expandable `ExtendedFloatingActionButton` cluster so it never hides content.
- **Quick Settings tile** (Android 7+) — "New ticket" tile directly from the notification shade. No unlocking the app, no navigating menus.
- **Launcher shortcuts + Google Assistant App Actions** — long-press the launcher icon or say *"Hey Google, create a ticket in BizarreCRM"* to land straight on the ticket-create screen. Registered via `res/xml/shortcuts.xml` and wired through a `bizarrecrm://` deep link scheme in `MainActivity`.
- **Barcode / QR quick-add** — the camera scanner (ML Kit) is accessible from the dashboard FAB, launcher shortcut, and pull-down tile. Pairs with the existing `BarcodeScanScreen`.

**On the job**

- **Home-screen widget** — 4x1 glanceable widget showing revenue today + open tickets + low stock count. Tap anywhere to open the app. Pulls from cached dashboard values so it works even when the device is offline. Implemented with classic `RemoteViews` (no `androidx.glance` dependency required).
- **Live Activity-style "Repair in progress" notification** — a foreground service (`RepairInProgressService`) posts a pinned lock-screen notification with the active ticket title while a repair is ongoing. Starts when a ticket enters `in_repair`, stops when it closes or ships. Uses the `dataSync` foreground-service type (Android 14+).
- **Sync badge per screen** — every screen that uses the shared scaffold can render a `SyncStatusBadge` showing "Synced" / "Syncing…" / "N unsynced". Tap-to-force-sync bypasses the 15-minute WorkManager schedule. Backed by `SyncManager.isSyncing` + `SyncQueueDao.getCount()` as a read-only StateFlow stream.
- **Haptic feedback** — short vibration on save, scan, payment success, and form errors via a centralised `HapticFeedback` helper. User-toggleable in **Settings > Device Preferences** and defaults ON.
- **Lock-screen "today's schedule" card** — roadmap. The notification channel is already wired through `FcmService`; the morning-digest push will land in a later release.

**Tablet & foldable**

- **Split-pane layout** — `SplitPaneScaffold` renders lists on the left and detail on the right when the viewport is ≥ 600 dp wide, and collapses to single-pane navigation below that. Designed for Samsung Tab A / Fold series at the bench.
- **Material You dynamic theming** — the app already pulls the system wallpaper palette via `dynamicColorScheme` on Android 12+, falling back to the brand blue on older devices.
- **S Pen signature capture** — existing capture flow for invoice sign-off on Samsung pen tablets. Check-in and pickup screens surface the signature pad automatically when an S Pen hover event is detected.

**Android Auto** — intentionally stubbed. The Auto SDK is a heavy dependency and the use cases ("view today's revenue while driving") are limited. A manifest service placeholder can be added once a concrete workflow is approved.

**Build dependencies** — the biometric helper requires `androidx.biometric:biometric:1.2.0-alpha05` in `packages/android/app/build.gradle.kts`. A TODO banner at the top of `BiometricAuth.kt` surfaces this loudly at compile time so the feature can't ship in a broken state. The home widget uses classic `RemoteViews` and does **not** require `androidx.glance`.

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

## Project Structure And API Source Of Truth

```
bizarre-crm/
  setup.bat              # One-click Windows deployment
  packages/
    server/              # Backend API, tenant provisioning, business rules, SQLite
      src/
        routes/          # Server route behavior and API source of truth
        services/        # Provisioning, email, SMS, payments, imports, metrics
        db/              # Migrations, seeds, connections, worker pool
        middleware/      # Auth, tenant resolution, errors, rate limits
    web/                 # Browser CRM frontend
      src/
        api/             # Web API wrappers and TypeScript request/response types
        pages/           # Browser routes and page components
        components/      # Shared browser UI
    android/             # Native Android app
      app/src/main/java/com/bizarreelectronics/crm/data/remote/
        api/             # Retrofit API interfaces
        dto/             # Kotlin request/response DTOs
    shared/              # TypeScript-only shared types/constants for web + server
    contracts/           # Safe internal API reference; no secrets, no runtime imports
      API_CONTRACT.md    # Human-readable shared endpoint shapes and examples
    management/          # Electron server management dashboard
      src/
        main/            # Electron main process (IPC bridge, service control)
        renderer/        # React SPA (dashboard UI)
```

Server routes in `packages/server/src/routes` are the source of truth for API behavior. `packages/contracts/API_CONTRACT.md` is the lightweight human reference for important shared request/response shapes so web and Android do not drift apart.

When a shared API shape changes, update the affected server route, web API wrapper/type, Android Retrofit interface/DTO, and `packages/contracts/API_CONTRACT.md` in the same commit. Do not put real secrets, `.env` values, customer data, tenant data, tokens, passwords, hCaptcha secrets, Cloudflare values, JWTs, or production examples in README or contract examples.

Signup is currently intended to use immediate tenant creation until platform email is configured. Future email verification can be enabled once SMTP/platform email exists. The relevant signup files are `packages/server/src/routes/signup.routes.ts`, `packages/web/src/pages/signup/SignupPage.tsx`, and `packages/web/src/api/endpoints.ts`.

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

### Latest Audit Hardening

Additional audit follow-up work now keeps the highest-risk findings closed:

- Marketing campaign HTML email interpolation escapes customer-controlled values before rendering, while preserving plain-text SMS/email fallbacks.
- Invoice payment webhooks use the strictly validated payment amount instead of reparsing raw request input.
- Ticket routes share positive-integer route ID validation instead of relying on partial `parseInt()` coercion.
- Inventory update/delete flows keep soft-deleted items out of normal mutation paths and return a clear "already deleted" response.
- `TODO.md` now stays focused on open work only. Completed checklist items live in `DONETODOS.md`, and `scripts/move_todos.js` can repeat that cleanup safely from the repo root.

## Inventory Enhancements

Follow-up to `criticalaudit.md` section 48. Adds a dozen parts-management
workflows that replace the "export to spreadsheet, come back Monday" loop:

- **Stocktake count mode** (`/inventory/stocktake`) — open a session, scan
  items on the shop floor, see live variance per SKU, commit in a single
  transaction that adjusts `inventory_items.in_stock` and writes per-line
  entries to `stock_movements` with `type='stocktake'`. Cancel abandons
  without touching stock.
- **Bin-location registry + heatmap** (`/inventory/bin-locations`) — CRUD
  for explicit bins with aisle/shelf/bin attributes, plus a 90-day pick-
  activity heatmap that flags hot shelves and suggests re-layout. Items
  are attached via the `inventory_bin_assignments` junction so the bulky
  `inventory_items` table stays untouched.
- **Auto-reorder UI** (`/inventory/auto-reorder`) — surfaces the previously
  hidden `POST /inventory/auto-reorder` endpoint with a "Run now" button
  plus per-item rule storage (min qty, reorder qty, preferred supplier,
  lead time) in `inventory_auto_reorder_rules`.
- **Serialized parts** (`/inventory/serials`) — bulk-paste serials per
  item, per-unit status lifecycle (`in_stock` / `sold` / `returned` /
  `defective` / `rma`). Consumption flows should mark the oldest
  in-stock serial sold on invoice/ticket fulfilment.
- **Shrinkage log** (`/inventory/shrinkage`) — explicit stock-movement type
  with constrained reason (`damaged` / `stolen` / `lost` / `expired` /
  `other`), optional photo upload, guarded decrement that never lets
  `in_stock` go negative. Every event writes a matching `stock_movements`
  row with `type='shrinkage'`.
- **ABC analysis** (`/inventory/abc-analysis`) — classifies items A/B/C by
  cumulative 80/15/5 revenue over a configurable window (30/90/180/365
  days); DEAD bucket for zero-sale items with clearance suggestions and
  tied-up-cost calculation.
- **Inventory age report** (`/inventory/age-report`) — 0-3 / 3-12 / 12+
  month buckets by oldest inbound stock movement, with per-bucket tied-
  up cost in cents. Fallback to `created_at` when the item has no inbound
  movement history.
- **Supplier price comparison** — `POST /inventory-enrich/:id/supplier-prices`
  + `GET /:id/supplier-comparison` for storing the same part at multiple
  suppliers and picking the cheapest on replenishment. All money is
  stored as integer cents.
- **Supplier returns / RMA** — `POST /inventory-enrich/supplier-returns`
  with credit tracking (`credit_amount_cents`) and status lifecycle
  (`pending` → `approved` → `shipped` → `credited` | `rejected`).
- **Parts compatibility** — many-to-many tagging of parts with supported
  device models via `POST /inventory-enrich/compatibility`; ready for
  POS to surface compatible accessories.
- **Lot warranty tracking** — `inventory_lot_warranty` table stores a
  per-lot `warranty_end_date` so POS can skip expired stock. Schema is
  ready; POS integration is left to the POS agent.
- **Mass barcode label printing** (`/inventory/labels`) — select up to
  500 items, pick ZPL (Zebra) or plain-text format, configurable copies
  per item (1-10), single-job download as `.zpl` or `.txt`.
- **Rapid quick-add** — `<QuickAddInput>` component in
  `packages/web/src/components/inventory/` parses "name @ price" into a
  minimal `inventory_items` row via `POST /inventory-enrich/quick-add`.
  Meant for rapid spew-new-parts-into-stock flows where the tech doesn't
  want the 11-field create form.

What is explicitly NOT added (per audit §48 observations): a supplier-
catalog browser as an add-to-inventory flow. The MobileSentrix /
PhoneLcdParts scraper stays a bulk-import tool for cost + photo
enrichment — nothing more.

**Schema**: `packages/server/src/db/migrations/091_inventory_enrichment.sql`
**Server routes**: `packages/server/src/routes/stocktake.routes.ts`,
`packages/server/src/routes/inventoryEnrich.routes.ts`
**Frontend pages**: `packages/web/src/pages/inventory/*Page.tsx` (8 new)
**Shared component**: `packages/web/src/components/inventory/QuickAddInput.tsx`

## POS Daily Flow

Addresses criticalaudit.md §43 (Cashier — POS Daily Flow). Adds the
cashier-workflow primitives on top of the existing unified POS:

- **Today's Top 5 quick-add tiles** — one tap adds the 5 most-sold products
  today. Data comes from a SUM(quantity) over today's `invoice_line_items`.
- **Cash drawer shifts + Z-report** — opening float, closing count,
  expected vs counted variance, payment-method breakdown, gross/refund/net
  totals. Cached on shift close so reprints don't re-query.
- **Shift clock-in/out** — the same drawer shift backs the cashier's
  workday. Close Shift triggers the Z-report immediately.
- **Manager PIN on high-value sales** — sales >= `pos_manager_pin_threshold`
  (default $500) require an admin/manager/owner PIN before checkout.
  Configurable per shop; 0 disables.
- **Training / sandbox mode** — banner + per-user training session. Fake
  sales never hit `inventory_items` or `payments`. Hit
  `/pos-enrich/training/submit` which no-ops and just counts drills.
- **Upsell prompts** — "Customer bought a screen -> suggest a case".
  Gated by `store_config.pos_upsell_enabled`.
- **Inline line-item discount** — popover with loyalty/bulk/employee/
  damaged/custom reason codes. Applied on the cart row locally.
- **Inactivity chip** — visible in the last 2 minutes of the 10-min idle
  reset so cashiers know when POS will roll back to default.
- **F-key quick tabs** — F1 Repairs, F2 Products, F3 Misc, F4 Customer
  search, F5 Complete sale, F6 Returns. Memoized handlers live in
  `usePosKeyboardShortcuts`.

**Migration**: `packages/server/src/db/migrations/093_pos_enrichment.sql`
(adds `cash_drawer_shifts`, `pos_training_sessions`, four `store_config`
flags).

**Routes**: `packages/server/src/routes/posEnrich.routes.ts` mounted at
`/api/v1/pos-enrich`.

**Frontend components** (all in `packages/web/src/pages/unified-pos/`):
`TopFiveTiles.tsx`, `CashDrawerWidget.tsx`, `ZReportModal.tsx`,
`TrainingModeBanner.tsx`, `LineItemDiscountMenu.tsx`, `InactivityTimer.tsx`,
`UpsellPrompt.tsx`, plus the shared hook
`packages/web/src/hooks/usePosKeyboardShortcuts.ts`.

Endpoints:

- `GET /api/v1/pos-enrich/top-five`
- `GET /api/v1/pos-enrich/drawer/current`
- `POST /api/v1/pos-enrich/drawer/open`
- `POST /api/v1/pos-enrich/drawer/:id/close`
- `GET /api/v1/pos-enrich/drawer/:id/z-report`
- `POST /api/v1/pos-enrich/training/start`
- `POST /api/v1/pos-enrich/training/:id/end`
- `POST /api/v1/pos-enrich/training/submit`
- `POST /api/v1/pos-enrich/manager-verify-pin`

## Settings UX

Per the pre-launch critical audit (§50), the 21-tab settings area was
audited and hardened against the "65 of 70 toggles do nothing" trust
problem called out in `CLAUDE.md`. All changes are UI-side — no new
server routes or migrations.

**What shipped:**

- **Setup Progress tab** (first position) — checklist of critical
  settings with jump-to-section links. Backed by the existing
  `onboarding.routes.ts` progressive-unlock logic.
- **Global Ctrl/Cmd+K search palette** (`SettingsGlobalSearch.tsx`) —
  modal command bar that searches across every tab, reading from a
  pre-lowered static index (`settingsSearchIndex.ts`). The existing
  inline `SettingsSearch.tsx` dropdown remains for mouse users.
- **Setting-level search index** — `settingsSearchIndex.ts` builds a
  flat, O(1) search haystack from `settingsMetadata.ts`.
- **Coming-Soon badges & dead-toggle list** —
  `settingsDeadToggles.ts` is the curated list of UI toggles that don't
  yet affect backend behaviour. `DeadToggleAnnotation.tsx` decides
  whether to hide them entirely (production default) or show them with
  an amber "Coming Soon" badge (dev default, controlled by
  `shouldHideDeadToggles()`).
- **Per-toggle help tooltips** (`SettingsTooltip.tsx`) — reusable `?`
  icon that resolves help text from `settingsMetadata.ts`.
- **Live receipt preview** (`ReceiptLivePreview.tsx`) — scaled-down
  thermal / letter receipt that updates in real time as the user edits
  the Receipts tab. Mounted beside the form.
- **Unsaved-changes guard** (`UnsavedChangesGuard.tsx`) — context
  provider that intercepts tab navigation and browser close when any
  registered section is dirty. Integrated into `SettingsPage.tsx` via
  `useUnsavedChanges().confirmNavigate()`.
- **Reset to defaults** — compact `ResetDefaultsButton.tsx` for a
  single-click restore, plus the expanded `SettingsResetToDefaults.tsx`
  panel that renders a per-key diff before running the reset.
- **Shop-type starter templates** (`SettingsTemplatePicker.tsx`) —
  picker for phone / computer / watch / general-electronics bundles.
  Delegates to the onboarding agent's `POST /onboarding/set-shop-type`
  endpoint; safe to re-run (server uses `INSERT OR IGNORE` on name).
- **Settings export / import** — `settingsExport.routes.ts` already
  ships a JSON export/import endpoint. UI is wired through the existing
  Data Import section.
- **In-tab change history** (`SettingsChangeHistory.tsx`) — pulls from
  existing `audit_logs` filtered to settings_* events.
- **Bulk actions bar** (`BulkActionsBar.tsx`) — one-click operations
  (enable/disable all notifications, enable all safety requirements,
  hide Coming-Soon toggles).
- **Mobile accordion-friendly layout** — on `<768px` the horizontal
  tab strip is replaced with a large single-select dropdown that calls
  the same `setActiveTab`. Desktop behaviour is unchanged. A dedicated
  `MobileAccordionWrapper.tsx` component is available for tabs that
  want a true accordion layout (opt-in; not applied globally to keep
  the diff minimal).
- **Inline numeric validation** — numeric fields with `min` / `max` in
  `settingsMetadata.ts` surface their bounds in their associated
  tooltip.

**Deferred to v2** (intentionally skipped as too invasive for the v1
launch): tab reordering by role / importance. Technicians currently see
the full 21-tab surface.

**Source of truth:** `settingsMetadata.ts` is the single source for
tooltip text, default values, validation bounds, and `status`
('live' | 'beta' | 'coming_soon'). When a backend is wired for a
previously dead setting, flip its `status` to `'live'` AND remove it
from `settingsDeadToggles.ts` in the same commit.

**File map:**

```
packages/web/src/pages/settings/
  settingsMetadata.ts            # Single source of setting definitions
  settingsSearchIndex.ts         # Flat search haystack
  settingsDeadToggles.ts         # Curated "dead" UI toggle list
  components/
    SettingsGlobalSearch.tsx     # Ctrl/Cmd+K command palette
    SettingsSearch.tsx           # Inline dropdown search
    SettingsTooltip.tsx          # Reusable ? helper
    ComingSoonBadge.tsx          # Amber status pill
    DeadToggleAnnotation.tsx     # Hides or annotates dead toggles
    ReceiptLivePreview.tsx       # Real-time receipt render
    UnsavedChangesGuard.tsx      # Dirty-state navigation guard
    ResetDefaultsButton.tsx      # Compact reset control
    SettingsResetToDefaults.tsx  # Expanded reset panel w/ diff
    SettingsTemplatePicker.tsx   # Shop-type starter template installer
    SettingsChangeHistory.tsx    # In-tab audit-log snippet
    BulkActionsBar.tsx           # One-click multi-key operations
    MobileAccordionWrapper.tsx   # Accordion layout for mobile (opt-in)
```

## Billing & Money Flow

Enrichment for audit §52. All money stored as INTEGER cents. Schema lives in
migration `095_billing_enrichment.sql` and is purely additive — existing
invoices/POS/refund tables are untouched.

### Features

- **Payment-link portal** (`/billing/payment-links`) — generate tokenized
  hosted Stripe or BlockChyp checkout URLs, track click count + last click.
  Cancel with a single button. Copy-to-clipboard ships day 1; SMS/email
  send goes through the existing channels.
- **Customer pay page** (`/pay/:token`) — public, no auth. Shows amount +
  invoice ref, opens the provider-hosted flow. On failure, "Please call the
  shop" card — never hangs. Mounted at `/api/v1/public/payment-links` so the
  authMiddleware does not intercept it.
- **Installment plan wizard** (`InstallmentPlanWizard` component) — split
  a total into N payments at configurable frequency. Computes schedule
  client-side, server writes it in a transaction. **BlockChyp safety:**
  plans require an `acceptance_token` + `acceptance_signed_at` before any
  auto-debit fires.
- **Dunning sequences** (`/billing/dunning`) — configurable steps
  (`[{days_offset, action, template_id}]`). The scheduler in
  `services/dunningScheduler.ts` walks them and inserts into `dunning_runs`.
  A UNIQUE constraint on (invoice_id, sequence_id, step_index) makes the
  run idempotent — restarts and duplicate cron ticks cannot double-send.
  **The cron itself is not wired from `index.ts` yet** — trigger manually
  via `POST /api/v1/dunning/run-now` (admin only) until the operator wires
  a daily `trackInterval` in `index.ts`.
- **Aging report** (`/billing/aging`) — 0-30 / 31-60 / 61-90 / 90+ buckets
  with totals + per-invoice drill-down.
- **Deposit workflow** — collect at drop-off via `DepositCollectModal`,
  apply to final invoice via `POST /api/v1/deposits/:id/apply-to-invoice`.
  Deposits are never hard-deleted; refunds are marked via `refunded_at`.
- **QR receipt code** (`QrReceiptCode` component) — zero-dep inline SVG.
  The current implementation renders a deterministic visual card; swap for
  a real QR encoder once a dep decision is made (stub documented inline).
- **Refund reason picker** (`RefundReasonPicker` component) — 6 canonical
  reason codes + free-form note. The existing `/api/v1/refunds` endpoint
  is **not** edited by this agent; consumers pass the reason through from
  the frontend.
- **Balance badge** (`BalanceBadge` component) — outstanding-balance pill
  for customer lists. Pure presentational, accepts a cents value.
- **Financing button** (`FinancingButton` component) — Affirm/Klarna stub
  shown on orders ≥ `billing_financing_min_cents` (default $500) when
  `billing_financing_enabled` is on. Opens an explanation modal. Real
  integration requires live API keys — marked with a TODO.

### API endpoints

| Route                                     | Auth  | Purpose                          |
|-------------------------------------------|-------|----------------------------------|
| `GET/POST/DELETE /api/v1/payment-links`   | Yes   | CRUD for staff                   |
| `GET /api/v1/public/payment-links/:token` | No    | Customer-facing lookup           |
| `POST .../:token/click`                   | No    | Click tracking                   |
| `POST .../:token/pay`                     | No    | Mark as paid after provider flow |
| `GET/POST/PUT/DELETE /api/v1/dunning/sequences` | Yes | Sequence CRUD             |
| `GET /api/v1/dunning/invoices/aging`      | Yes   | Aging report                     |
| `POST /api/v1/dunning/run-now`            | admin | Manual scheduler trigger         |
| `GET/POST/DELETE /api/v1/deposits`        | Yes   | Deposits                         |
| `POST /api/v1/deposits/:id/apply-to-invoice` | Yes | Apply deposit to final invoice |

### Not owned by this agent

- **Membership / auto-debit** — already handled by `membership.routes.ts`;
  a "link existing subscription" button lives in the payment-links UI.
- **Partial refund endpoints** — `refunds.routes.ts` is untouched. The
  reason picker integrates purely from the frontend.
- **Stripe billing sync** — already in `services/stripe.ts`.
- **Tax-time CSV export** — owned by the reports agent.
- **POS / invoice mutations** — `pos.routes.ts` and `invoices.routes.ts`
  are not edited; deposits hang off their own table and are read-joined.

## Team Management

Team enrichment layer (criticalaudit.md §53). Migration `096_team_management.sql`
adds 11 tables; three new route files mount under `/api/v1/team`,
`/api/v1/roles`, and `/api/v1/team-chat`. Touches **none** of the existing
employees, auth, or tickets routes.

| Page | Route | What it does |
|------|-------|--------------|
| **My queue** | `/team/my-queue` | Tickets assigned to me, sorted by due date and age. Auto-refreshes every 30s. |
| **Shift schedule** | `/team/shifts` | Weekly day-grid with shift CRUD plus a sidebar for pending time-off requests (one-click approve/deny for managers). |
| **Leaderboard** | `/team/leaderboard` | Reads `/reports/tech-leaderboard` (owned by the reports agent), falls back to `/employees/performance/all`. Top three get medals. |
| **Roles & permissions** | `/team/roles` | Custom roles list plus a checkbox matrix per role. Admin role's `admin.full` bit is server-guarded against accidental lockout. |
| **Team chat** | `/team/chat` | Channels (general, ticket, direct) with polling-based messages and an `@username` mention picker that writes to `team_mentions`. |
| **Performance reviews** | `/team/reviews` | Admin-only notes + 1-5 star ratings per employee. |
| **Goals** | `/team/goals` | Per-tech weekly targets ("close 15 tickets this week") with live progress bars computed from the existing tickets table. |

### Schema (migration 096)

`shift_schedules`, `time_off_requests`, `ticket_handoffs`, `team_mentions`,
`team_chat_channels`, `team_chat_messages`, `payroll_periods`,
`performance_reviews`, `team_goals`, `custom_roles`, `role_permissions`,
`user_custom_roles`, `knowledge_base_articles`. The 4 default roles
(admin / manager / technician / cashier) are seeded; their permission rows
are lazy-seeded on first GET so the canonical key list lives in code, not in
the migration. The general chat channel is the only seeded chat row. **No
knowledge-base articles are seeded** — the audit explicitly forbids it (each
shop builds their own SOPs).

### Components for cross-cutting use

- `components/team/MentionPicker.tsx` — drop-in `@username` autocomplete used
  by the chat page; ready to be reused by ticket-note editors.
- `components/team/TicketHandoffModal.tsx` — required-reason hand-off modal.
  Posts to `/team/handoff/:ticketId` and reassigns `tickets.assigned_to` in
  one shot. Importable from any page that wants the action.
- `components/team/CommissionPeriodLock.tsx` — payroll-period CRUD card with
  Lock buttons and CSV export links (`/team/payroll/export.csv?period=`).

### Payroll period lock

Once a `payroll_periods` row has `locked_at`, the helper
`isCommissionLocked(adb, ts)` (in `routes/_team.payroll.ts`) reports true for
any timestamp inside that range. The audit-flagged hole — commissions edited
after payout — is now plumbable: any commission-mutating route can require
this check before writing.

### Sandbox / training mode

Already shipped by the POS agent. Toggle from Settings -> POS to spin a tech
into a fake-cart sandbox so they can practice without touching real inventory
or commissions.

### What this PR deliberately does NOT touch

- `employees.routes.ts`, `auth.routes.ts`, `settings.routes.ts`,
  `tickets.routes.ts` — owned by other agents.
- The handoff modal and mention picker are exported but not yet wired into
  `TicketDetailPage` — that's the tickets agent's call.
- Ticket-channel auto-creation on the first message and WebSocket fan-out
  for `/team-chat` are TODOs; the polling endpoint is good enough for v1.

## License

Private — Bizarre Electronics internal use.
