# BizarreCRM Tech Stack And Security

This file keeps technical stack and security details out of the main README.

## Stack Overview

| Area | Technology | Purpose |
|------|------------|---------|
| Server runtime | Node.js 22+ | API and background services |
| Server framework | Express 4 | HTTPS API server |
| Server language | TypeScript 5.7 | Type-safe backend development |
| Database | SQLite via better-sqlite3 12 | Local embedded storage |
| Web app | React 19 + Vite 6 | Browser CRM |
| Web styling | Tailwind CSS 3 | UI styling |
| Web state | TanStack Query + Zustand | Server cache and client state |
| Desktop management | Electron 39 + React 19 | Windows management dashboard |
| Android | Kotlin + Jetpack Compose | Native mobile app |
| Android data | Room + SQLCipher | Local encrypted storage |
| Android sync | Retrofit + WorkManager | API calls and background sync |
| Push | Firebase Messaging | Android notifications |
| Realtime | ws | WebSocket notifications |
| Payments | BlockChyp + Stripe libraries | Terminal payments and billing support |
| Communications | Console, Twilio, Telnyx, Bandwidth, Plivo, Vonage | SMS/MMS and voice provider layer |
| Email | Nodemailer | SMTP email |
| Images | Sharp, Canvas, CameraX, Coil | Server and mobile image handling |
| Scheduling | node-cron, WorkManager | Server and Android scheduled work |

## Repository Shape

```text
packages/server       Express API and backend services
packages/web          React CRM frontend
android      Native Android app
packages/management   Electron management dashboard
packages/shared       Shared TypeScript code
packages/contracts    API contract notes
```

## Database

BizarreCRM uses SQLite for local self-hosted storage.

Important characteristics:

- WAL mode for concurrent reads.
- Foreign keys enabled.
- Sequential SQL migrations.
- Per-tenant database support.
- Local file backups.
- Uploaded files stored alongside server runtime data.

Money should be stored as integer cents. Multi-step money and inventory changes should use transactions.

## Authentication And Sessions

The app uses JWT-based authentication with refresh/session support.

Important controls:

- bcrypt password hashing.
- TOTP 2FA support.
- session revocation.
- rate limits on sensitive routes.
- constant-time login behavior where practical.
- separate admin and tenant scopes where needed.

## Tenant Isolation

Tenant isolation is enforced through request routing, tenant-aware database access, per-tenant settings, and separate tenant data storage.

Production multi-tenant hosting should use a real domain, wildcard DNS, HTTPS, and strict host validation.

## Request And Browser Protection

Important protections include:

- Helmet security headers.
- CORS allowlist behavior.
- host header validation.
- WebSocket authentication.
- JSON-only state-changing route expectations where applicable.
- upload validation and randomized file names.
- path traversal protection.
- rate limiting for login, portal, signup, webhook, and other sensitive routes.

## Sensitive Configuration

Provider tokens and other sensitive shop settings are stored encrypted at rest where the settings system marks them sensitive.

Do not place live credentials in README examples, docs, screenshots, contract examples, or issue descriptions.

## Backups

Backups should include SQLite database files and uploaded files.

Recommended operator practice:

- keep one local backup,
- keep one backup off the CRM machine,
- test restore periodically,
- protect backup encryption material separately from normal login secrets.

## Known Operational Limits

- The Android app is active but not yet equal to the web app for every workflow.
- Some provider-specific voice capabilities depend on provider support and account configuration.
- Production SSL/domain setup still needs operator attention; local self-signed SSL is only for local installs.
- The safest deployment path today is Windows with the Management Dashboard; Linux is possible but more hands-on.

## Related Docs

- [README](../README.md)
- [Operator Guide](operator-guide.md)
- [Developer Guide](developer-guide.md)
- [Android Field App](android-field-app.md)
