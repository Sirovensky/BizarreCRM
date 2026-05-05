# BizarreCRM

**Open-source repair-shop CRM replacing RepairDesk.**

Self-hosted point-of-sale, ticketing, invoicing, inventory, messaging, and reporting for independent electronics repair shops. Built to give shops local control of their data and a practical daily workflow at the counter and the bench.

---

## Alpha Software

BizarreCRM is **alpha software**. Self-host at your own risk. Data-handling features are evolving — back up tenant DBs regularly, keep a copy off the CRM machine, and test a restore before you depend on one. See [Restore Drill](#restore-drill-run-once-before-launch) below.

---

## Architecture

Node.js + Express + SQLite (better-sqlite3) + React 19 + Vite + TypeScript. Multi-tenant SQLite with one database file per tenant. Android field app in Kotlin + Jetpack Compose. Electron management panel for Windows operators. A single Node process serves the REST API, the static web bundle, and WebSocket events — one port, one service, one file tree to back up.

Monorepo under `packages/`: `server` (Express API + migrations + services), `web` (React CRM), `android` (field app), `management` (Electron dashboard), `shared` (common types + zod schemas), `contracts` (API contract docs).

---

## Setup

```bash
# 1. Clone
git clone https://github.com/Sirovensky/BizarreCRM.git
cd BizarreCRM

# 2. Install
npm install

# 3. Copy env template and generate secrets
cp .env.example .env
# Then generate JWT_SECRET + JWT_REFRESH_SECRET (64-byte hex each):
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
# Paste into .env

# 4. Build the web bundle
npm --workspace=packages/web run build

# 5. Start the server
cd packages/server && npx tsx src/index.ts
```

Open `https://localhost` (self-signed cert — accept the browser warning for local dev). For a shortcut path on Windows, `setup.bat` at the repo root runs install + build + first boot in one step.

### Environment variables

Every configurable value lives in [`.env.example`](./.env.example) with inline comments. The minimum required for boot is `JWT_SECRET`, `JWT_REFRESH_SECRET`, and `PORT`. Production deployments should also set `NODE_ENV=production`, `BASE_DOMAIN`, and `BACKUP_ENCRYPTION_KEY` — see [Operator Guide](docs/operator-guide.md) for the production checklist.

### Default credentials

| | |
|---|---|
| Username | `admin` |
| Password | `admin123` |
| PIN | `1234` |

2FA setup is **forced on first login** — the server will not let the admin account skip enrollment. Change the password and PIN before adding staff accounts.

---

## Node version

Supported: **Node 22.x–24.x**. Node 25+ is not yet supported. If you upgrade Node across a major version, run `npm rebuild` in `packages/server` afterward to recompile native modules (`better-sqlite3`, `sharp`, `canvas`) against the new ABI. Skipping this produces silent exit-code 3221226505 crashes at runtime.

---

## App surfaces

- **Web CRM** (`packages/web`) — the main daily workspace. Tickets, POS, invoices, inventory, communications, settings, reports, admin.
- **Android field app** (`android`) — Kotlin + Compose. Room + SQLCipher for offline storage, WorkManager for sync, Firebase Messaging for push, CameraX + ML Kit for scanning.
- **Management dashboard** (`packages/management`) — Electron app for Windows shop operators. Runs the server as a Windows Service, shows health, manages tenants, handles update/restart flows.

---

## Contributing

PRs welcome. Before submitting:

1. Run the security tests: `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests across 3 phases).
2. Confirm `npm run build` succeeds from the repo root.
3. Confirm `npx tsc --noEmit` is clean in `packages/server` and `packages/web`.
4. If your change touches a request or response shape, update the server route, the web API wrapper, the Android Retrofit/DTO code, and the related contract doc in `packages/contracts/` in the same PR.

Bugs, security disclosures, and proposal discussions: open an issue or contact the address in [`SECURITY.md`](./SECURITY.md).

---

## License

[MIT](./LICENSE) — see `LICENSE` at the repo root.

Third-party open-source dependencies and their licenses are enumerated in [`LICENSES.md`](./LICENSES.md).

---

## What it does

BizarreCRM is organized around the work a repair shop does every day.

- **Customers** — profiles, contact details, repair history, lifetime value, SMS/email opt-in.
- **Tickets and repairs** — intake → assignment → bench workflow → pickup, with notes, photos, device details, and customer-visible updates.
- **POS and checkout** — unified POS for repair, product, and misc sales. Cash, card, deposits, invoice payments, BlockChyp terminal flows.
- **Invoices** — generation from tickets or standalone sales, payment recording, void with stock preservation, deposits, payment links, aging, dunning.
- **Inventory** — products, parts, services, stock tracking, low-stock alerts, suppliers, barcode labels, bin locations, stocktakes, serialized parts, reorder workflow, supplier catalog import.
- **Communications** — provider-based SMS/MMS (Twilio, Telnyx, Bandwidth, Plivo, Vonage, Console for testing), shared team inbox, templates, retry handling, voice hooks.
- **Reports** — sales, tax, tickets, inventory, employees, customer trends, exports to spreadsheet.
- **Customer portal** — public repair status page, payment links, receipts, review requests, loyalty/referral information, selected repair photos.
- **Team management** — employees, roles, shifts, permissions, goals, payroll-period locks.

---

## Daily workflow

```
1. Find or create customer
2. Create ticket, capture device details
3. Assign or queue the work
4. Add notes, photos, parts, status changes
5. Text the customer on change
6. Convert to invoice / sale
7. Take payment, print or send receipt
8. Close the day: reports, stock movement, open work
```

---

## First-login checklist

Before using the app with real customers:

- Change the default admin password.
- Finish 2FA setup (forced on first login).
- Create named accounts for real staff, replace the shared admin login.
- Enter store profile (name, phone, address, hours).
- Confirm tax classes and payment methods.
- Configure receipt text and print sizes.
- Configure SMS/MMS provider if texting customers.
- Configure BlockChyp if taking terminal payments.
- Configure backups + test a restore.
- Create a test customer, ticket, invoice, payment — void or clean up before opening the counter.

---

## Development

Dependencies: Node 22+, npm 10+, Git, Android Studio + Java 17 for Android work.

```bash
npm install                        # root — installs all workspaces
npm run dev                        # server + web in parallel
npm run dev:server                 # server only
npm run dev:web                    # web only (Vite dev server on 5173, proxies /api to 443)
npm run build                      # full build: shared → web → server
npm run health                     # health check script
```

Management dashboard:

```bash
cd packages/management
npm run dev:electron               # dev build + electron launch
npm run build && npm run package   # package Windows installer
```

Android: open `android` in Android Studio, or build with Gradle from that package.

More detail for contributors: [Developer Guide](docs/developer-guide.md).

---

## Production TLS (required)

The self-signed cert under `packages/server/certs/server.{key,cert}` is **DEV ONLY**. Browsers, Android clients, and card terminals will reject it in production. Before running on a public hostname:

1. Obtain a real certificate. Options: Cloudflare origin cert (15-year, auto-rotation), Let's Encrypt via `certbot` or an ACME-enabled reverse proxy (Caddy / Traefik), or a commercial CA for paid attestation.
2. Replace `packages/server/certs/server.key` and `server.cert` with the real cert + key. Keep the filenames — the server refuses to boot if missing.
3. Set `NODE_ENV=production` so HSTS, secure cookies, and the HTTPS-only redirect engage.
4. Verify with `curl -I https://<your-domain>` — no cert warnings, `Strict-Transport-Security` header with `max-age=15552000; includeSubDomains`.
5. Point Android clients at the new HTTPS host. The app pins trust to the host, not a specific cert, so a cert swap does not require an app rebuild.

---

## Restore Drill (run once before launch)

Backups are useless until a restore works. Before your first real shop day, run this end-to-end:

1. **Stop the server.** Ctrl+C the process or stop the service wrapper.
2. **Pick a backup.** Backups live under `backup_path` as `bizarre-crm-<timestamp>-<rand>.db.enc` plus a matching `uploads-<timestamp>-<rand>/` dir. Grab the most recent pair.
3. **Decrypt the DB.** From `packages/server/`:
   ```bash
   npx tsx -e "import { decryptFile } from './src/services/backup.js'; await decryptFile('<path>/<file>.db.enc', './data/bizarre-crm.db');"
   ```
   Ensure `BACKUP_ENCRYPTION_KEY` in `.env` matches the one that encrypted this backup — the wrong key fails with a GCM auth error.
4. **Restore uploads.** Copy `uploads-<timestamp>-<rand>/` contents over the `uploads/` dir.
5. **Restart the server.** Log in, confirm recent tickets/invoices match expectations, confirm photos render.
6. **Note the restore window.** The stop-to-restart delta is your real RTO — log it.

Repeat at least every 6 months. A backup that hasn't been restored is a hope, not a plan.

---

## Further reading

- [Operator Guide](docs/operator-guide.md) — deployment, SSL, backups, imports, providers, production operation.
- [Product Overview](docs/product-overview.md) — feature-by-feature overview.
- [Android Field App](docs/android-field-app.md) — current Android capabilities, gaps, implementation notes.
- [Developer Guide](docs/developer-guide.md) — local development, package responsibilities, API contract workflow.
- [Tech Stack And Security](docs/tech-stack-and-security.md) — stack versions, data storage, security controls, operational limits.
- [API Contracts](packages/contracts/API_CONTRACT.md) — shared API reference for server, web, Android.
- [Open Work](TODO.md) — active known issues and follow-up tasks.
- [Completed Work](DONETODOS.md) — historical record of landed fixes and features.
- [Security Policy](SECURITY.md) — private disclosure address and response process.
