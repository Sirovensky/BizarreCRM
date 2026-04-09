# BizarreCRM

Custom repair shop CRM for [Bizarre Electronics](https://bizarreelectronics.com) — replacing RepairDesk ($99+/mo) with a self-hosted, fully owned solution.

**57,000+ lines of code** across 213 files — full-stack TypeScript monorepo.

| Layer | Stack |
|-------|-------|
| Server | Node.js 20 + Express 4 + TypeScript (ESM) |
| Database | SQLite via better-sqlite3 (WAL mode) |
| Web | React 19 + Vite 6 + Tailwind CSS 3 |
| Dashboard | Electron 33 + React 19 + Vite (Windows EXE) |
| State | TanStack Query v5 (server) + Zustand v5 (client) |
| Auth | JWT + TOTP 2FA + bcrypt |
| Real-time | WebSocket (ws library) |
| Payments | BlockChyp terminal integration |
| SMS | 3CX WebSocket + protobuf |

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
- **Server Dashboard (EXE)** — Electron desktop app for server management, runs CRM as Windows Service, multi-tenant admin, crash monitoring, real-time stats
- **Security** — TOTP 2FA, rate limiting, CORS, CSP, audit logging (60 pen tests passing)
- **Print** — receipts (80mm/58mm thermal), labels (4x2), letter size
- **TV display** — public screen showing active tickets
- **Customer tracking** — public status page for customers

## Project Structure

```
bizarre-crm/
  packages/
    server/          # Express API + SQLite (104 files, ~17k LOC)
      src/
        db/          # Migrations (40), seeds, connection
        routes/      # 25+ route files
        services/    # BlockChyp, email, SMS, backup, import, scraper
        middleware/   # Auth, error handling, rate limiting, idempotency
        ws/          # WebSocket server
        admin/       # Backup admin panel (HTML)
    web/             # React SPA (82 files, ~37k LOC)
      src/
        pages/       # 30+ page components
        components/  # Shared UI (command palette, modals, skeleton, etc.)
        api/         # Axios client + typed endpoint functions
        stores/      # Zustand stores (auth, UI)
        hooks/       # Settings, WebSocket, drafts
    management/      # Electron Dashboard EXE
      src/
        main/        # Electron main process (IPC bridge, service control)
        preload/     # Secure context bridge
        renderer/    # React SPA (dashboard UI)
```

## Setup on a New Machine

### Prerequisites

- **Node.js 20+** — [download](https://nodejs.org/)
- **Git** — [download](https://git-scm.com/)
- **Windows recommended** (tested on Windows 11, Linux/Mac should work with minor path adjustments)

### 1. Clone the repo

```bash
git clone https://github.com/Sirovensky/BizarreCRM.git
cd BizarreCRM
```

### 2. Install dependencies

```bash
npm install
```

This installs both server and web dependencies (npm workspaces).

### 3. Create environment file

```bash
cp .env.example .env
```

Edit `.env` and set at minimum:

```env
# REQUIRED — generate random 64-byte hex strings for each:
JWT_SECRET=<run: node -e "console.log(require('crypto').randomBytes(64).toString('hex'))">
JWT_REFRESH_SECRET=<run the same command again for a different value>

# Optional — defaults work for development
PORT=443
```

### 4. Start the server

```bash
cd packages/server
npx tsx src/index.ts
```

On first start, the server will:
- Run all 40 database migrations (creates `packages/server/data/bizarre-crm.db`)
- Seed default statuses, tax classes, payment methods, device models
- Create default admin user: `admin` / `admin123`

### 5. Start the web frontend

In a separate terminal:

```bash
cd packages/web
npx vite --host
```

### 6. Access the CRM

- **CRM**: https://yourshop.localhost:443 (multi-tenant — use your shop slug as subdomain)
- **Landing page**: https://localhost:443 (bare domain, no slug)
- **Admin/Backup panel**: https://localhost:443/admin

Login with `admin` / `admin123`. You'll be prompted to set up 2FA (Google Authenticator) on first login.

### Vite Dev Server (optional)

A Vite HMR dev server on port 5174 is available for frontend development. It proxies `/api` to the Express server. Not needed for normal use — the Express server on 443 serves the built frontend directly.

```ts
server: {
  proxy: {
    '/api': { target: 'http://localhost:443' }
  }
}
```

## Optional Configuration

### RepairDesk Import

To import data from an existing RepairDesk account:

1. Get your API key from RepairDesk (Settings > Integrations > API)
2. Add to `.env`: `RD_API_KEY=your-key-here`
3. Go to Settings > Data Import in the CRM
4. Click "Test Connection", then "Full Import"

### BlockChyp Payment Terminal

1. Create a BlockChyp account and get sandbox/production API credentials
2. Go to Settings > BlockChyp in the CRM
3. Enter API Key, Bearer Token, Signing Key
4. Enable "Test Mode" for sandbox testing
5. Click "Test Connection" to verify

### SMS via 3CX

Add to `.env`:

```env
TCX_HOST=your-3cx-host
TCX_USERNAME=extension-username
TCX_PASSWORD=extension-password
TCX_EXTENSION=2380
TCX_STORE_NUMBER=+1XXXXXXXXXX
```

### Email (SMTP)

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM=Your Store <your-email@gmail.com>
```

### Backups

Access the admin panel at `http://localhost:443/admin` to:
- Configure backup location (local drive or network share)
- Set backup schedule (cron syntax, default: every 12 hours)
- Set retention count (default: 30 backups)
- Manually trigger backups

## Management Dashboard (Electron EXE)

The server is managed via a standalone Electron desktop app (`packages/management/`). It runs the CRM as a **Windows Service** completely independent of the dashboard process.

### Architecture

```
[Dashboard EXE]              [Windows Service: BizarreCRM]
  React UI (renderer)          Node.js CRM Server (port 443)
  IPC bridge (main)            Express + SQLite + WebSocket
  sc.exe (service ctrl)
       |                              |
       +--- REST API (localhost) -----+
       +--- sc.exe commands ----------+
```

- **Process isolation**: Dashboard crash/close does NOT affect the CRM server
- **Auto-start**: Service starts on Windows boot, runs without any user logged in
- **Emergency stop**: Force-kill button in dashboard (requires type "STOP" to confirm)

### Dashboard Features

| Page | Description |
|------|-------------|
| Overview | Live stats (memory, CPU, uptime, RPS, DB size, connections) |
| Tenant Management | Create/suspend/activate/delete tenants (multi-tenant mode) |
| Server Control | Start/stop/restart service, emergency stop, auto-start toggle |
| Backups | Drive browser, schedule config, manual backup, history |
| Crash Monitor | Crash log, auto-disabled routes, re-enable controls |
| Updates | One-click update (git pull + build + restart) |
| Audit Log | Admin actions with timestamps and IPs |
| Sessions | Active admin sessions with revoke |
| Settings | Theme, system info, service config, close dashboard |

### Build & Run

```bash
cd packages/management
npm install
npm run build     # Compiles main + preload + renderer
npm start         # Launches Electron
npm run package   # Builds Windows NSIS installer
```

### Setup Wizard

On first run, the dashboard detects missing prerequisites and walks through:
1. Node.js check (installs if missing)
2. Dependency installation
3. Database migrations
4. Frontend build
5. SSL certificate generation
6. Windows Service installation

## Production Deployment

### Quick Start (Windows — 3 steps)

1. Install **[Git](https://git-scm.com/download/win)** and **[Node.js 22 LTS](https://nodejs.org/)** (check "Automatically install necessary tools" during Node install — this adds Python + C++ build tools)

2. Clone the repo:
   ```cmd
   git clone https://github.com/Sirovensky/BizarreCRM.git
   cd BizarreCRM
   ```

3. Double-click **`setup.bat`**

That's it. The script installs dependencies, generates secrets, creates SSL certs, builds the frontend, and starts the server. Open `https://localhost:443` and log in with `admin` / `admin123`.

> **One-click updates:** The Management Dashboard has an Update button that runs `git pull` + rebuild + restart automatically.

### What setup.bat does

| Step | Action |
|------|--------|
| [1/6] | Verifies Node.js 20+ is installed |
| [2/6] | `npm install` — all workspaces, compiles native modules |
| [3/6] | Creates `.env` with cryptographically random JWT secrets |
| [4/6] | Generates self-signed SSL certs (via Git's bundled OpenSSL) |
| [5/6] | `npm run build` — compiles React frontend for production |
| [6/6] | Starts the server (PM2 if available, otherwise direct) |

### Manual Setup (Linux / advanced)

<details>
<summary>Click to expand step-by-step instructions</summary>

#### Prerequisites

- **Git**: `sudo apt install git`
- **Node.js 22+**: `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs`
- **Build tools**: `sudo apt install build-essential python3 libvips-dev libcairo2-dev libjpeg-dev`

#### Install & build

```bash
git clone https://github.com/Sirovensky/BizarreCRM.git
cd BizarreCRM
npm install
npm run build
```

#### Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```ini
PORT=443
NODE_ENV=production
MULTI_TENANT=true
BASE_DOMAIN=yourdomain.com
JWT_SECRET=<run: node -e "console.log(require('crypto').randomBytes(64).toString('hex'))">
JWT_REFRESH_SECRET=<run again for a different value>
SUPER_ADMIN_SECRET=<run: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))">
```

#### SSL certificates

Place real certs (or generate self-signed) in:

```
packages/server/certs/server.cert   # PEM certificate (+ chain)
packages/server/certs/server.key    # PEM private key
```

Self-signed: `openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.cert -days 3650 -nodes -subj "/CN=BizarreCRM"`

#### Start

```bash
# Direct
cd packages/server && npx tsx src/index.ts

# Or with PM2 (recommended — auto-restart on crash)
npm install -g pm2
pm2 start ecosystem.config.js
pm2 save && pm2 startup
```

On first start the server auto-runs migrations, seeds defaults, and creates the admin user (`admin` / `admin123`). Change the password immediately.

</details>

### Verify

```bash
curl -k https://localhost:443/api/v1/info
```

You should see the startup banner: `BizarreCRM Server — https://0.0.0.0:443`

### DNS for multi-tenant

If `MULTI_TENANT=true`, each tenant gets a subdomain (e.g., `myshop.yourdomain.com`). You need:

- **Wildcard A record**: `*.yourdomain.com` → your server IP
- **Wildcard SSL cert**: must cover `*.yourdomain.com` (Let's Encrypt supports this via DNS challenge)

### What to copy when migrating existing data

| Path | Contains | Copy? |
|------|----------|-------|
| `packages/server/data/tenants/*.db` | Customer, ticket, invoice databases | **Yes** — this IS your data |
| `packages/server/data/master.db` | Tenant registry (multi-tenant) | **Yes** if multi-tenant |
| `packages/server/uploads/` | Photo attachments | **Yes** |
| `packages/server/data/metrics.db` | Historical server metrics | Optional |
| `packages/server/data/bizarre-crm.db` | Single-tenant database | **Yes** if single-tenant |
| `node_modules/` | Dependencies | **No** — install fresh |
| `.env` | Secrets | Create new on server |
| `packages/server/certs/` | SSL certificates | Use real certs on server |

### Single-tenant mode

To disable multi-tenant subdomain routing:

```ini
# .env
MULTI_TENANT=false
```

All users share one database at `data/bizarre-crm.db`. No subdomain resolution needed — access directly via `https://yourdomain.com`.

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
