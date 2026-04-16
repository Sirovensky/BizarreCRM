[Skip to Quick Start](#quick-start)

# BizarreCRM

BizarreCRM is a self-hosted repair shop system for Bizarre Electronics. It replaces rented point solutions with one app for customer intake, repair tickets, POS, invoices, inventory, messaging, reports, and shop administration.

The goal is simple: keep the shop running from one place, keep shop data local, and make the daily repair workflow fast enough for the front counter and the bench.

The system has three main surfaces:

- A browser CRM for daily shop work.
- A native Android app for technicians and counter devices.
- A Windows management dashboard for running and updating the server.

It is built as a private monorepo with Node.js, React, Kotlin/Jetpack Compose, Electron, SQLite, and shared API contracts.

The app is private to the shop. It assumes the business wants local control, readable operations, and practical repair workflows more than a generic SaaS-style dashboard. That affects the choices throughout the repo: SQLite over a hosted database, self-hosting over subscriptions, and explicit provider setup over hidden vendor lock-in.

In practice, that means the first questions are:

- Can the counter create the ticket quickly?
- Can the technician find the right work next?
- Can the customer get a clear update?
- Can the shop take payment and preserve history?
- Can the owner back up and restore the data?

If a document does not help answer those questions, it belongs in a deeper reference file rather than on the front page.

That keeps the README useful during a real shop day.

## Who It Is For

BizarreCRM is written for a small repair business that wants practical control over its software and data.

It should be useful to:

- front-counter staff checking in devices and taking payments,
- technicians updating tickets and looking up parts,
- managers reviewing invoices, reports, stock, and team activity,
- the shop owner keeping the system local and self-hosted,
- the person responsible for backups, updates, users, and devices.

It is not trying to be a public SaaS product for every industry. The center of the app is repair-shop work: customers, devices, tickets, parts, invoices, messages, payments, and follow-up.

## What It Is Not

BizarreCRM is not a lightweight note-taking app, a generic ecommerce site, or a public customer-support portal by itself.

It is also not meant to hide unfinished work behind polished wording. If a workflow is complete, the docs should say so. If a workflow is still being tightened, the docs should point to the current status instead of overselling it.

For that reason, the main README gives the practical overview and links out to deeper docs. The detailed status of mobile work, provider setup, deployment, and developer contracts lives outside the front page.

## Daily Workflow

A normal day in the app looks like this:

1. Find or create the customer.
2. Create the ticket and capture the device details.
3. Assign the work or put it in the queue.
4. Add notes, photos, parts, and status changes as the repair moves.
5. Text the customer when something changes.
6. Convert the work into an invoice or sale.
7. Take payment and print or send the receipt.
8. Review daily reports, stock movement, and open work before closing.

The README stays focused on that human workflow. Deeper engineering details live in the docs linked near the bottom.

## What It Does

BizarreCRM is organized around the work a repair shop does every day.

### Customers

- Store customer profiles, contact details, notes, and repair history.
- Search customers quickly with full-text search.
- Track lifetime value, visit history, referrals, and communication preferences.
- Keep SMS and email opt-in status visible for campaigns and service updates.

### Tickets And Repairs

- Create and manage repair tickets from intake through pickup.
- Assign work to technicians and follow ticket status.
- Store notes, photos, history, device details, and customer-visible updates.
- Use bench workflow tools for timers, checklists, common device jobs, and quality checks.

### POS And Checkout

- Run repair, product, and miscellaneous sales through a unified POS.
- Attach sales to customers and tickets.
- Collect deposits, final payments, and invoice payments.
- Support cash, card, and other payment methods, including BlockChyp terminal flows.

### Invoices And Money

- Generate invoices from repair tickets and sales.
- Record payments, void invoices, and preserve stock integrity.
- Track deposits, payment links, aging, dunning, and outstanding balances.
- Keep money values as integer cents in the backend to avoid rounding drift.

### Inventory

- Manage products, parts, and services.
- Track stock, low-stock alerts, suppliers, barcode labels, bin locations, stocktakes, serialized parts, and reorder workflows.
- Import and enrich supplier catalog data where useful.

### Communications

- Use provider-based SMS/MMS instead of a single hardcoded phone vendor.
- Supported providers: Console testing, Twilio, Telnyx, Bandwidth, Plivo, and Vonage.
- Use the shared team inbox for conversations, assignments, tags, templates, retry handling, and off-hours responses.
- Voice hooks are available for providers that support calling, recording, or transcription.

### Reports

- Review sales, tax, tickets, inventory, employees, customer trends, and daily shop activity.
- Export reports where the shop needs spreadsheets for accounting or operations.
- Use dashboards for quick views and detailed pages for deeper analysis.

### Customer Portal

- Give customers a public status page for repair tracking.
- Share payment links, receipts, review requests, loyalty/referral information, and selected repair photos.

### Team Management

- Manage employees, roles, shifts, permissions, goals, performance, and payroll-period locks.
- Keep manager-only actions guarded while technicians and cashiers see the tools they need.

### Settings And Setup

- Configure store profile, taxes, receipts, payment methods, users, notifications, and provider credentials.
- Use setup progress and searchable settings to find the important configuration without digging through every tab.
- Keep unfinished or optional switches clearly labeled so the shop knows what is active.

## App Surfaces

### Web CRM

The browser app is the main daily workspace. It is where the front counter and managers handle tickets, customers, POS, invoices, inventory, communications, settings, reports, and admin tasks.

Use it when you are at a desktop, laptop, or counter terminal.

### Android Field App

The Android app is the mobile and bench companion. It uses Kotlin, Jetpack Compose, Room with SQLCipher, Retrofit, WorkManager, Firebase Messaging, CameraX, ML Kit, and Material 3.

It has native foundations for offline-friendly shop work, including local storage, sync queues, push notifications, scanner/media dependencies, dashboard routes, tickets, customers, invoices, inventory, SMS, reports, employees, leads, appointments, estimates, expenses, and settings.

Some Android workflows are still being tightened, especially deep links, launcher shortcuts, notification routing, checkout, photo upload navigation, and a few placeholder actions. See [Android Field App](docs/android-field-app.md) and [TODO.md](TODO.md) for the current mobile status.

### Management Dashboard

The management dashboard is a Windows Electron app for server operations. It can run BizarreCRM as a Windows Service, show server health, manage tenants, monitor crashes, and handle update/restart flows without opening a terminal.

Use it when you need to manage the server itself rather than do shop work.

### Which Surface Should I Use?

| Need | Best Surface |
|------|--------------|
| Create tickets, run POS, manage invoices | Web CRM |
| Search customers, update tickets, use mobile/bench tools | Android app |
| Restart the server, package updates, monitor health | Management Dashboard |
| Configure providers, payment methods, receipts, users | Web CRM |
| Provision tenants or inspect service health | Management Dashboard |

The web app should be treated as the complete shop workspace. Android should be treated as the mobile companion. The management dashboard should be treated as the server control panel.

## Quick Start

The fastest setup path is Windows with `setup.bat`.

### 1. Install Node.js

Install [Node.js 22 LTS](https://nodejs.org/). During install, enable the option to install required native build tools if prompted.

You also need npm 10 or newer. Node 22 normally includes a compatible npm version.

**Supported range:** Node 22.x–24.x. Node 25+ is NOT yet supported. Upgrading Node across a major version? Run `npm rebuild` in `packages/server` afterward to recompile native modules (`better-sqlite3`, `sharp`, `canvas`) against the new ABI. Skipping this produces silent exit-code 3221226505 crashes at runtime.

### 2. Download The App

Download the latest source ZIP from GitHub:

[Download BizarreCRM](https://github.com/Sirovensky/BizarreCRM/archive/refs/heads/main.zip)

Extract it somewhere permanent, for example:

```text
C:\BizarreCRM
```

Avoid running it from inside a temporary Downloads extraction folder if this will be the real shop install.

### 3. Run Setup

Open the extracted folder and double-click:

```text
setup.bat
```

The setup script installs dependencies, creates an `.env` file, generates local SSL certificates, builds the web app, builds the server, attempts to package the management dashboard, and starts the CRM.

### 4. Open The CRM

After setup, open:

```text
https://localhost
```

Default first login:

```text
Username: admin
Password: admin123
```

Change the default password immediately. Set up 2FA when prompted.

### 5. First Login Checklist

Before using the app with real customers:

- Change the default admin password.
- Set up 2FA.
- Create named accounts for real staff.
- Enter store profile details.
- Confirm tax classes and payment methods.
- Configure receipt text and print sizes.
- Configure SMS/MMS if the shop will text customers.
- Configure BlockChyp if the shop will take terminal payments.
- Configure backups.
- Create a test customer, ticket, invoice, and payment.
- Void or clean up test records before opening the counter for the day.

### 6. Know Where Your Data Lives

Shop data is stored locally under:

```text
packages/server/data/
```

Uploads, generated files, tenant databases, backups, and local runtime files live under the server package. Do not delete that folder during updates.

### Updating

If Git is installed, the Management Dashboard can update the app by pulling the latest code, rebuilding, and restarting the service.

Without Git, download a fresh ZIP and run `setup.bat` again. Existing data under `packages/server/data/` should be preserved.

For SSL, production domains, Linux deployment, backups, imports, and multi-tenant setup, read the [Operator Guide](docs/operator-guide.md).

### If Setup Fails

Start with these checks:

- Confirm Node.js 22 is installed.
- Confirm the repo is not inside a temporary ZIP extraction folder.
- Confirm another app is not already using port 443.
- Re-run `setup.bat` from a normal user folder or a permanent install folder.
- Check `logs/` and the terminal output for the first actual error, not just the final failure message.

For deeper operational troubleshooting, use the [Operator Guide](docs/operator-guide.md).

## Common Setup

Most shops should configure these items after the first login.

### Store Profile

Go to Settings and enter the shop name, phone number, address, tax setup, receipt details, business hours, and default service preferences.

These values affect receipts, invoices, customer-facing pages, reminders, reports, and some automation rules.

### Team Members

Create real employee accounts instead of sharing the default admin login.

Use roles and permissions so technicians, cashiers, managers, and admins have the right access for their work.

### Taxes And Payment Methods

Set up tax classes and payment methods before ringing up real invoices.

These settings affect POS totals, invoice balances, reports, and receipts. A test sale is the easiest way to confirm that tax, payment recording, and receipt output all match shop expectations.

### Receipts And Printing

Configure receipt header, footer, terms, paper size, and label/thermal preferences before a live sales day.

The app supports common receipt sizes such as 80mm, 58mm, labels, and letter output. Test the actual printer that will be used at the counter.

### SMS/MMS And Voice Providers

Go to the onboarding wizard's SMS step or Settings > SMS & Voice.

Supported providers:

- Console testing
- Twilio
- Telnyx
- Bandwidth
- Plivo
- Vonage

The selected provider is saved as `sms_provider_type`. Provider credentials are stored per shop in `store_config`, and sensitive tokens are encrypted at rest.

Use Console only for development or testing. For a real shop, configure a real provider and run the settings screen's connection test.

### BlockChyp Payments

Go to Settings > BlockChyp and enter the API key, bearer token, and signing key for the terminal account.

After configuration, test a small controlled transaction before relying on the terminal during a live sales day.

### Email

SMTP settings are used for email receipts, account messages, and future email-based workflows.

Add the SMTP values in `.env` or configure them through the appropriate settings area when the UI supports the flow:

```text
SMTP_HOST
SMTP_PORT
SMTP_USER
SMTP_PASS
SMTP_FROM
```

### RepairDesk Import

Use Settings > Data Import to bring over existing RepairDesk customers, tickets, invoices, inventory, and SMS history.

Run imports during a quiet period, keep a backup, and verify a sample of customers, tickets, invoices, and stock counts afterward.

### Backups

Backups should include SQLite data and uploaded files. Use the admin backup panel or the Management Dashboard to configure backup location, schedule, and retention.

Keep at least one backup copy outside the CRM machine.

### Android Devices

For Android devices, make sure the device can reach the CRM URL, trust the local or production certificate, and sign in with a real staff account.

Use Android first for mobile-friendly work: lookup, ticket updates, photos, scanner workflows, queues, and notifications. Use the web app for dense setup, reports, and admin-heavy tasks.

### Multi-Tenant Hosting

BizarreCRM supports multiple shops through tenant provisioning and per-tenant databases.

For local use, `localhost` is enough. For production, use a real domain, DNS wildcard, SSL certificates, and the tenant provisioning flow described in the [Operator Guide](docs/operator-guide.md).

### Production Readiness

Before using a production domain:

- Set `BASE_DOMAIN`.
- Configure DNS.
- Use real SSL certificates.
- Confirm backups.
- Confirm restore procedure.
- Confirm SMS provider credentials.
- Confirm payment provider credentials.
- Confirm staff accounts and permissions.
- Confirm the Management Dashboard can restart the service.

## Development Setup

Development uses npm workspaces for the TypeScript packages. The Android app is a separate Gradle project under `packages/android`.

### Requirements

- Node.js 22 or newer.
- npm 10 or newer.
- Git.
- Android Studio for Android work.
- Java 17 for Android builds.
- Windows if you are packaging or controlling the Windows service/dashboard.

### Install

```bash
npm install
```

### Environment

Create `.env` from `.env.example` and adjust local values as needed:

```bash
copy .env.example .env
```

For local development, `BASE_DOMAIN=localhost` is fine.

### Run The Server And Web App

```bash
npm run dev:server
npm run dev:web
```

Or run both from the root:

```bash
npm run dev
```

### Build

```bash
npm run build
```

This builds the shared package, web app, and server.

### Health Check

```bash
npm run health
```

### Management Dashboard

```bash
cd packages/management
npm run dev:electron
```

To package the Windows app:

```bash
cd packages/management
npm run build
npm run package
```

### Android

Open `packages/android` in Android Studio, or build with Gradle from that package.

The Android app reads the base domain from Gradle properties, environment variables, or the repo `.env`. By default it points to `https://localhost` for local work.

More detail for contributors is in the [Developer Guide](docs/developer-guide.md).

### Before Changing Shared Behavior

If a change touches a request or response shape, update the server, web API wrapper, Android DTOs, and contract docs together.

If a change touches money, inventory, tenant routing, auth, provider credentials, or offline sync, treat it as high-risk and test the full workflow, not just the edited screen.

## Project Map

```text
bizarre-crm/
  setup.bat              Windows setup script
  package.json           npm workspace root
  packages/
    server/              Express API, SQLite data, migrations, services
    web/                 React browser CRM
    android/             Native Android app
    management/          Electron Windows management dashboard
    shared/              Shared TypeScript code
    contracts/           Human-readable API contracts for shared behavior
  docs/                  Operator, product, Android, developer, and security docs
  deploy/                Deployment helpers
  scripts/               Maintenance and health scripts
```

### Server

The server owns authentication, tenant resolution, migrations, business rules, background jobs, provider integrations, file uploads, WebSocket events, and public/customer-facing endpoints.

SQLite is the primary database. Tenant data is stored in local database files so the shop keeps control of its data.

### Web

The web app is the main CRM interface. It uses React, Vite, Tailwind CSS, React Query, React Router, Zustand, charts, tables, and shared request/response types where practical.

### Android

The Android app is native Kotlin and Compose. It is not just a web wrapper. It has its own local database, sync system, navigation, and mobile-specific integrations.

### Management

The management package builds the desktop dashboard used to run, update, monitor, and control the CRM service on Windows.

### Contracts

The contracts package documents shared API behavior so server, web, and Android changes do not drift apart.

When a request or response shape changes, update the server route, web API wrapper, Android Retrofit/DTO code, and the related contract in the same change.

### Docs

The `docs/` folder is where detailed operator, product, Android, developer, and security information belongs.

The README should stay readable. If a section starts turning into a migration list, endpoint table, changelog, or implementation diary, move that detail into `docs/` and link to it.

## Security & Data Safety

BizarreCRM is designed for private self-hosted shop use.

Important protections include:

- Mandatory 2FA support for users.
- JWT authentication with refresh sessions.
- Password hashing with bcrypt.
- Rate limits on sensitive routes.
- Helmet security headers.
- CORS and host validation.
- WebSocket authentication.
- File upload validation.
- Per-tenant database separation.
- Encrypted sensitive configuration values.
- Local backup support.
- Privileged action history for admin changes.

Security details, stack versions, and operational notes are in [Tech Stack And Security](docs/tech-stack-and-security.md).

### Data Safety Habits

Good operating habits matter as much as code controls:

- Change default credentials.
- Use individual staff accounts.
- Keep 2FA enabled.
- Keep backups off the CRM machine.
- Test restore before a real emergency.
- Keep payment and provider credentials limited to admins.
- Do not paste live secrets into screenshots, tickets, docs, or chat logs.

## Further Reading

- [Operator Guide](docs/operator-guide.md) - deployment, SSL, backups, imports, providers, and production operation.
- [Product Overview](docs/product-overview.md) - feature-by-feature overview in human language.
- [Android Field App](docs/android-field-app.md) - current Android capabilities, mobile gaps, and implementation notes.
- [Developer Guide](docs/developer-guide.md) - local development, package responsibilities, and API contract workflow.
- [Tech Stack And Security](docs/tech-stack-and-security.md) - stack versions, data storage, security controls, and known operational limits.
- [API Contracts](packages/contracts/API_CONTRACT.md) - shared API reference for server, web, and Android work.
- [Open Work](TODO.md) - active known issues and follow-up tasks.

## License

Private - Bizarre Electronics internal use.
