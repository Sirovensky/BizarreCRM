# BizarreCRM

Custom repair shop CRM for [Bizarre Electronics](https://bizarreelectronics.com) — replacing RepairDesk ($99+/mo) with a self-hosted, fully owned solution.

**57,000+ lines of code** across 213 files — full-stack TypeScript monorepo.

| Layer | Stack |
|-------|-------|
| Server | Node.js 20 + Express 4 + TypeScript (ESM) |
| Database | SQLite via better-sqlite3 (WAL mode) |
| Web | React 19 + Vite 6 + Tailwind CSS 3 |
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
PORT=3020
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

- **CRM**: https://yourshop.localhost:3020 (multi-tenant — use your shop slug as subdomain)
- **Landing page**: https://localhost:3020 (bare domain, no slug)
- **Admin/Backup panel**: https://localhost:3020/admin

Login with `admin` / `admin123`. You'll be prompted to set up 2FA (Google Authenticator) on first login.

### Vite Dev Server (optional)

A Vite HMR dev server on port 5174 is available for frontend development. It proxies `/api` to the Express server. Not needed for normal use — the Express server on 3020 serves the built frontend directly.

```ts
server: {
  proxy: {
    '/api': { target: 'http://localhost:3020' }
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

Access the admin panel at `http://localhost:3020/admin` to:
- Configure backup location (local drive or network share)
- Set backup schedule (cron syntax, default: every 12 hours)
- Set retention count (default: 30 backups)
- Manually trigger backups

## Production Deployment

```bash
# Build the frontend
cd packages/web && npx vite build

# The server serves the built frontend from packages/web/dist/
# Start with PM2:
pm2 start ecosystem.config.js

# Or directly:
NODE_ENV=production node --loader ts-node/esm packages/server/src/index.ts
```

An nginx config is provided in `deploy/nginx.conf` for reverse proxy setup.

## Security

- TOTP 2FA mandatory for all users
- JWT access tokens (1h) + httpOnly refresh cookies (30d) with rotation
- Rate limiting on login, 2FA, PIN, SMS, admin endpoints
- Helmet security headers (CSP, HSTS, X-Frame-Options)
- CORS restricted to localhost + LAN IPs
- File upload MIME whitelist + randomized filenames
- Audit logging for security events
- 60 penetration tests across 3 test suites:

```bash
bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh
```

## License

Private — Bizarre Electronics internal use.
