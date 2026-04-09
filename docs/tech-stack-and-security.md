# BizarreCRM — Tech Stack & Security Reference

## Technology Stack

### Server (packages/server)

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| Runtime | Node.js | 20 LTS | Server runtime |
| Framework | Express | 4.21 | HTTP/HTTPS API server |
| Language | TypeScript | 5.7 | Type-safe development (ESM) |
| Database | SQLite | via better-sqlite3 11.7 | Embedded database (WAL mode, 64MB cache) |
| Auth | JWT + bcrypt + TOTP | jsonwebtoken 9, bcryptjs 2.4, otplib 13 | Token auth, password hashing, 2FA |
| WebSocket | ws | 8.18 | Real-time client notifications |
| SMS | 3CX WebSocket | Custom protobuf integration | SMS/MMS/voice calls |
| Payments | BlockChyp | @blockchyp/blockchyp-ts 2.30 | Card terminal integration |
| Email | Nodemailer | 8.0 | SMTP email sending |
| Images | Sharp + Canvas | 0.34, 3.2 | Image processing, QR codes |
| Scheduling | node-cron | 3.0 | Backup scheduling, daily reports |
| HTML Scraping | Cheerio | 1.2 | Supplier catalog scraping (Magento 2) |

### Web Frontend (packages/web)

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| Framework | React | 19 | UI rendering |
| Build | Vite | 6.0 | Dev server, HMR, production builds |
| CSS | Tailwind CSS | 3.4 | Utility-first styling |
| State (server) | TanStack Query | 5.62 | API data fetching, caching |
| State (client) | Zustand | 5.0 | Auth, UI preferences |
| Routing | React Router | 7.1 | Client-side routing |
| Tables | TanStack Table | 8.20 | Data tables |
| Charts | Recharts | 2.15 | Report visualizations |
| HTTP | Axios | 1.7 | API client |
| Icons | Lucide React | 0.468 | Icon library |

### Management Dashboard (packages/management)

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| Desktop | Electron | 33 | Native Windows EXE |
| UI | React 19 + Vite 6 + Tailwind 3 | Same as web | Dashboard renderer |
| State | Zustand 5 | Same as web | Auth, server status, UI |
| Packaging | electron-builder | 25 | NSIS installer for Windows |
| Communication | REST API (localhost) | Express management routes | IPC bridge to CRM server |
| Service Control | sc.exe (Windows) | Native | Start/stop/restart service |

### Infrastructure

| Component | Technology | Purpose |
|-----------|-----------|---------|
| SSL | Self-signed certs (10yr) | HTTPS on localhost (TLS 1.2+) |
| Process Mgmt | Windows Service / PM2 | Server auto-start, crash recovery |
| Reverse Proxy | Nginx (optional) | Production with Let's Encrypt |
| Containerization | Docker (optional) | Multi-stage build, alpine runtime |

---

## Security Architecture

### Authentication Layers

| Layer | Mechanism | Session | TTL |
|-------|-----------|---------|-----|
| CRM Users | JWT + httpOnly refresh cookie | SQLite sessions table | 1h access / 30d refresh |
| CRM Admin | bcrypt token (in-memory) | In-memory map | 30 min |
| Super Admin | JWT + mandatory TOTP 2FA | SQLite master DB | 4 hours |
| Management API | bcrypt token (in-memory) | In-memory map | 1 hour |
| Management Dashboard | sc.exe (no auth needed) | N/A — localhost process | N/A |

### Verified Security Measures

| Measure | Status | Implementation |
|---------|--------|----------------|
| TOTP 2FA | ENFORCED | Mandatory for all users on first login (otplib + AES-256-GCM encrypted secrets) |
| JWT Token Rotation | WORKING | Access tokens (1h) + httpOnly refresh cookies (30d) with one-time rotation |
| Password Hashing | WORKING | bcrypt with cost factor 12 (admin) / 14 (super admin) |
| Rate Limiting | WORKING | 300 req/min global, 5 attempts/15min on login, 60 req/min on webhooks |
| CORS | WORKING | Restricted to localhost + RFC1918 private IP ranges (LAN only) |
| CSP Headers | WORKING | Helmet v8 — Content-Security-Policy, HSTS, X-Frame-Options, etc. |
| CSRF Protection | WORKING | Rejects non-JSON state-changing requests (POST/PUT/PATCH/DELETE) |
| SQL Injection | PREVENTED | All queries use parameterized prepared statements (better-sqlite3) |
| XSS Prevention | WORKING | HTML entity escaping on all dynamic content in admin panels |
| File Upload Security | WORKING | MIME type whitelist + randomized filenames + path traversal prevention |
| Audit Logging | WORKING | Security events logged with timestamps, IPs, user agents |
| Idempotency | WORKING | X-Idempotency-Key on ticket/invoice creation + 5-sec payment dedup |
| Session Management | WORKING | Revokable sessions, auto-cleanup every hour |
| Account Lockout | WORKING | 5 failed logins = 15min lockout (CRM), 3 = 30min (super admin) |
| Symlink Protection | WORKING | Real path resolution prevents directory traversal via symlinks |

### Crash Resilience

| Mechanism | Status | Details |
|-----------|--------|---------|
| Auto-disable broken routes | WORKING | 3 consecutive crashes = route disabled, protected routes (auth, health, admin) exempt |
| Crash persistence | WORKING | JSON file (survives DB corruption), max 500 entries |
| Graceful shutdown | WORKING | SIGTERM/SIGINT handlers close DB connections cleanly |
| Windows Service recovery | CONFIGURED | Auto-restart on failure: 5s, 30s, 60s delays |
| Dashboard isolation | WORKING | Electron dashboard is a separate process — crash doesn't affect server |

### Network Security

| Measure | Details |
|---------|---------|
| HTTPS Only | TLS 1.2 minimum, self-signed cert for localhost |
| Management API | Localhost-only (checks `req.socket.remoteAddress`, not `req.ip`) |
| WebSocket Auth | JWT verification required within 5 seconds of connection |
| Webhook Routing | Subdomain-based tenant isolation for inbound SMS/voice |

### Penetration Testing

60 security tests across 3 phases:
```bash
bash security-tests.sh          # Phase 1: Auth, CORS, headers
bash security-tests-phase2.sh   # Phase 2: Injection, traversal, rate limiting
bash security-tests-phase3.sh   # Phase 3: Business logic, session management
```

---

## Database

- **Engine**: SQLite 3 (embedded, zero-configuration)
- **Mode**: WAL (Write-Ahead Logging) for concurrent reads
- **Cache**: 64MB journal + 64MB page cache
- **Busy Timeout**: 5 seconds (prevents SQLITE_BUSY under load)
- **Foreign Keys**: Enabled
- **Migrations**: 53+ sequential SQL files (source of truth for schema)
- **Backups**: Full SQLite copy + uploads folder, configurable schedule + retention
- **Multi-tenant**: Per-tenant SQLite databases with connection pooling (max 50)

---

## What We Know Works (Verified)

- Login with 2FA (Google Authenticator)
- Ticket create/edit/delete/bulk actions
- Customer CRUD with FTS search
- POS checkout flow with BlockChyp terminal
- Invoice generation + payments + void with stock restore
- SMS send/receive via 3CX WebSocket
- Inventory management with stock tracking
- Supplier catalog scraping (Mobilesentrix, PhoneLcdParts)
- Admin backup panel (schedule, manual, retention)
- Management dashboard (stats, crashes, updates, service control)
- Multi-tenant CRUD (create/suspend/activate/delete shops)
- Super admin with mandatory 2FA
- All 60 security tests passing
- RepairDesk data import (customers, tickets, invoices, inventory, SMS)
- Print (thermal 80mm/58mm, labels 4x2, letter size)
- TV display + customer tracking portal
