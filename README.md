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

1. Install **[Git](https://git-scm.com/download/win)** and **[Node.js 22 LTS](https://nodejs.org/)** (check "Automatically install necessary tools" during Node install — this adds Python + C++ build tools)

2. Clone the repo:
   ```cmd
   git clone https://github.com/Sirovensky/BizarreCRM.git
   cd BizarreCRM
   ```

3. Double-click **`setup.bat`**

That's it. The script installs dependencies, generates secrets, creates SSL certs, builds the frontend, and starts the server. Open `https://localhost:443` and log in with `admin` / `admin123`.

> **Updating:** The Management Dashboard has an Update button that runs `git pull` + rebuild + restart automatically.

### What setup.bat does

| Step | Action |
|------|--------|
| [1/6] | Verifies Node.js 20+ is installed |
| [2/6] | `npm install` — all workspaces, compiles native modules |
| [3/6] | Creates `.env` with cryptographically random JWT secrets |
| [4/6] | Generates self-signed SSL certs (via Git's bundled OpenSSL) |
| [5/6] | `npm run build` — compiles React frontend for production |
| [6/6] | Starts the server (PM2 if available, otherwise direct) |

### Production SSL & domain

For a real domain, replace the self-signed certs:

```
packages/server/certs/server.cert   # Your PEM certificate (+ chain)
packages/server/certs/server.key    # Your PEM private key
```

Edit `.env` and set `BASE_DOMAIN=yourdomain.com`. For multi-tenant, add a wildcard DNS record (`*.yourdomain.com`) and a wildcard SSL cert.

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

- TOTP 2FA mandatory for all users
- JWT access tokens (1h) + httpOnly refresh cookies (30d) with rotation
- Rate limiting on login, 2FA, PIN, SMS, admin endpoints
- Helmet security headers (CSP, HSTS, X-Frame-Options)
- CORS restricted to localhost + LAN IPs
- File upload MIME whitelist + randomized filenames
- Audit logging for security events
- 60+ penetration tests passed across auth, injection, XSS, access control, file attacks, DoS, and API abuse categories

## License

Private — Bizarre Electronics internal use.
