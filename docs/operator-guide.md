# BizarreCRM Operator Guide

This guide is for the person responsible for installing, running, backing up, and updating BizarreCRM.

For the short version, start with the [README](../README.md). This file keeps the operational details out of the main README so the front page stays readable.

## Windows Setup

The normal install path is:

1. Install Node.js 22 LTS.
2. Download or clone the repository.
3. Run `setup.bat`.
4. Open `https://localhost`.
5. Log in with `admin` / `admin123`.
6. Change the default password and finish 2FA setup.

The setup script installs npm workspaces, creates `.env` when needed, generates local SSL certificates, builds the app, starts the server, and attempts to build the management dashboard.

## Data Location

Local runtime data lives under:

```text
packages/server/data/
```

That folder is the important one to protect during updates and backups. It contains local SQLite data, tenant data, uploaded files, generated files, and runtime state.

Do not delete it when replacing code from a fresh ZIP.

## Updating

Preferred update path:

1. Use the Management Dashboard update flow when Git is installed.
2. Let it pull the latest code, rebuild, and restart the service.
3. Confirm the web app loads and the health check passes.

Manual ZIP update path:

1. Stop the running CRM.
2. Keep the existing `packages/server/data/` folder.
3. Replace the code files with the new ZIP contents.
4. Run `setup.bat` again.
5. Open the CRM and verify login, tickets, POS, invoices, and settings.

## Domains And SSL

Local installs can use:

```text
https://localhost
```

Production installs should use a real domain and real certificates.

Typical production shape:

- `BASE_DOMAIN=example.com`
- wildcard DNS for tenant subdomains
- reverse proxy such as Nginx
- Let's Encrypt certificate for the apex and wildcard names
- HTTPS to the CRM server

Use `deploy/` as the starting point for generated Nginx and production helper files.

## Multi-Tenant Hosting

BizarreCRM supports multiple shop tenants. Each tenant has separate database storage and tenant-aware routing.

For a single shop, keep the setup simple and use the default local tenant behavior.

For multiple shops:

- Set `BASE_DOMAIN`.
- Configure wildcard DNS.
- Configure SSL for the domain.
- Use the super-admin or management tools to provision tenants.
- Verify each tenant has isolated login, settings, data, uploads, and provider credentials.

## JWT Secret Rotation

BizarreCRM signs every login + refresh token with `JWT_SECRET` / `JWT_REFRESH_SECRET` from your `.env`. Rotating these values is sound security hygiene — do it after any suspected leak, after staff with deploy access leave, and at least annually as a routine.

A naive rotation (replace `JWT_SECRET`, restart) kicks every logged-in user out the instant the server comes back up, because their access tokens were signed with the old secret. BizarreCRM ships a graceful-rotation path that avoids that.

### Graceful Procedure

1. **Generate a new secret.** Either:
   - Run `node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"`, or
   - If multi-tenant, `POST /super-admin/api/rotate-jwt-secret` (requires super-admin login) and copy the returned `nextJwtSecret` + `nextJwtRefreshSecret`.

2. **Edit `.env`.** Move the OLD value to `JWT_SECRET_PREVIOUS` and install the NEW value as `JWT_SECRET`. Same for refresh:

   ```text
   JWT_SECRET_PREVIOUS=<old value>
   JWT_SECRET=<new value>
   JWT_REFRESH_SECRET_PREVIOUS=<old refresh value>
   JWT_REFRESH_SECRET=<new refresh value>
   ```

3. **Restart the server.** All new logins sign with the new secret. Existing sessions verify against the new secret first, and fall back to the previous secret only on signature mismatch — so every already-issued token keeps working until it expires.

4. **Wait for the safety window.** Access tokens have a 1h TTL. Waiting roughly 90 minutes (1h TTL + 30min buffer for clock skew and in-flight refreshes) guarantees every access token signed with the previous secret has expired naturally. Refresh tokens live longer (30-90d), but the verified refresh-then-rotate handshake re-signs a replacement refresh token with the new secret on every refresh, so active users quietly migrate without noticing.

5. **Remove the `_PREVIOUS` entries and restart once more.** Any session that did not refresh during the window is now forced to re-authenticate. This is the intended behaviour of a rotation — dormant sessions should re-prove identity after a secret change.

### What the server does for you

At startup, the server logs a reminder whenever either `JWT_SECRET_PREVIOUS` or `JWT_REFRESH_SECRET_PREVIOUS` is still set — if you leave them set past the safety window, the nag reminds you on every restart. The app itself never writes to the env file; rotation is always operator-driven through whatever secrets mechanism your deploy already uses (`.env`, PM2 ecosystem vars, Docker env file, Kubernetes Secret, vault, etc.).

Every rotation call to the super-admin endpoint is recorded in the master audit log with `super_admin_rotate_jwt_secret` — the event records who performed it and when, but never the secret value itself.

## Backups

Backups should include:

- SQLite databases.
- Uploaded files.
- tenant data folders.
- configuration needed to restore the server.

Recommended operator habit:

- Keep one local backup.
- Keep one off-machine backup.
- Test restore before depending on a backup plan.
- Do not rely on code commits as data backups.

The backup panel and management tools can configure backup location, schedule, and retention.

## Management Login Recovery

The Management Dashboard super-admin login does not have self-service email password reset. That is intentional: recovery for this account requires local server or database administrator access.

During first-time 2FA enrollment, save any recovery codes shown by the dashboard. Current builds show that block only when the server response includes recovery codes; if no codes are shown, use the local recovery steps below.

Before changing the master database:

1. Stop BizarreCRM.
2. Back up `packages/server/data/master.db`.
3. Run the smallest reset needed.
4. Restart BizarreCRM.
5. Log in and immediately re-enroll 2FA or store the new password in the approved password manager.

### Lost Authenticator, Password Known

Clear only the super-admin TOTP fields and active sessions. Replace `admin` if your super-admin username is different.

```bash
sqlite3 packages/server/data/master.db "UPDATE super_admins SET totp_secret_enc = NULL, totp_secret_iv = NULL, totp_secret_tag = NULL, totp_enabled = 0, updated_at = datetime('now') WHERE username = 'admin'; DELETE FROM super_admin_sessions;"
```

After restart, log in with the existing password. The dashboard will require 2FA setup again.

### Forgot Super-Admin Password

Choose a strong replacement password first. Generate a bcrypt hash locally from the repo root:

```bash
node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync(process.argv[1], 14));" "replace-with-a-long-unique-password"
```

Stop BizarreCRM, back up `packages/server/data/master.db`, then update the password hash and clear 2FA so the recovered account must enroll a fresh authenticator. Replace both `admin` and `<bcrypt-hash-from-command>` as appropriate.

```bash
sqlite3 packages/server/data/master.db "UPDATE super_admins SET password_hash = '<bcrypt-hash-from-command>', password_set = 1, totp_secret_enc = NULL, totp_secret_iv = NULL, totp_secret_tag = NULL, totp_enabled = 0, failed_login_count = 0, locked_until = NULL, updated_at = datetime('now') WHERE username = 'admin'; DELETE FROM super_admin_sessions;"
```

Restart BizarreCRM, log in with the replacement password, and complete 2FA setup. Do not leave a shared temporary password in service; if you used a handoff password, repeat the offline password-hash update with the final owner-held password.

## SMS/MMS And Voice Providers

SMS and voice configuration is per shop. Configure it in the onboarding flow or Settings > SMS & Voice.

Supported providers:

- Console testing
- Twilio
- Telnyx
- Bandwidth
- Plivo
- Vonage

Use Console only for local testing. Real shops should configure a live provider and run the connection test before sending customer messages.

Sensitive provider secrets are encrypted at rest.

## Payments

BlockChyp terminal settings live in Settings > BlockChyp.

Before using payments with customers:

1. Enter the API key, bearer token, and signing key.
2. Confirm the terminal is paired.
3. Run a controlled test transaction.
4. Confirm the invoice, payment record, and receipt all match.

If Stripe billing features are used, configure Stripe values in `.env` and verify webhook behavior in a test environment before using live keys.

## Email

SMTP values are used for email receipts and account messages.

Common `.env` keys:

```text
SMTP_HOST
SMTP_PORT
SMTP_USER
SMTP_PASS
SMTP_FROM
```

After configuring email, send a test message and check both delivery and spam placement.

## RepairDesk Import

Use Settings > Data Import for RepairDesk migration.

Before importing:

- Back up the current CRM data.
- Run the import during a quiet period.
- Keep the RepairDesk import key available.
- Verify sample customers, tickets, invoices, inventory, and message history.

After importing, compare totals and spot-check important customers before going live.

## Linux Notes

Linux deployment is possible, but Windows is the smoothest path for the current shop setup and management dashboard.

For Linux:

1. Install Node.js 22 and npm 10.
2. Install native build prerequisites for SQLite, sharp, canvas, and related packages.
3. Run `npm install`.
4. Configure `.env`.
5. Run `npm run build`.
6. Start with `npm run start` or a process manager such as PM2.
7. Put a reverse proxy with HTTPS in front of the app.

## Health Watchdog

BizarreCRM ships a cross-platform PM2 watchdog (`bizarre-crm-watchdog`) that
runs alongside the main server. PM2 itself only catches process exits; the
watchdog catches a different failure mode — process alive but event loop
wedged (deadlock, infinite sync work, blocked GC). Without it, a wedged
server stays "online" in PM2's eyes while customers see timeouts.

### How it works

The watchdog polls `/api/v1/health/live` every 30 seconds. If liveness fails
3 times in a row (90 seconds), the watchdog calls `pm2 restart bizarre-crm`.
If liveness keeps failing after the restart, the watchdog escalates to
`pm2 stop bizarre-crm` and surfaces a fatal alarm in the dashboard. A
cascade-failure cap (default: 3 watchdog-triggered restarts in 1 hour)
prevents the watchdog from becoming a restart-loop accelerator.

The server can declare known long-running operations (tenant migrations,
RepairShopr/RepairDesk/MyRepairApp imports, catalog scrapes) to the
watchdog via the in-memory `longTaskRegistry`. While a long task is
registered, the watchdog extends its wedge-failure threshold to
`expectedDurationMs * 1.5` (capped at 30 minutes). Operators do not need
to configure anything for this — long tasks self-register.

### Dashboard surface

ServerControlPage shows a Watchdog Status card with four states:

- **Healthy** (green) — recent polls all returned 200.
- **Extended grace** (blue) — server appears active in a long task or has
  recent log activity; no destructive action.
- **Recent restart** (amber) — the watchdog restarted the server in the
  last 10 minutes. The server is presumably back online; this is
  informational.
- **FATAL / cascade-abort / cert-expired** (red) — server stopped.
  Operator must investigate and click "I've investigated" to clear the
  alarm before the card returns to healthy.

### Tunables

All tunables are environment variables read by the watchdog at startup.
Defaults are conservative; only override if the defaults misbehave for
your shop's workload.

| Variable | Default | Meaning |
| --- | --- | --- |
| `WATCHDOG_POLL_INTERVAL_MS` | 30000 | Time between liveness probes. |
| `WATCHDOG_FAILURE_THRESHOLD` | 3 | Consecutive failures before action. |
| `WATCHDOG_LONG_TASK_MULTIPLIER` | 1.5 | Threshold extension during long tasks. |
| `WATCHDOG_LONG_TASK_MAX_MS` | 1800000 | Cap on extended threshold (30 min). |
| `WATCHDOG_LOG_CORROBORATION_WINDOW_MS` | 60000 | Window to check log activity before destructive action. |
| `WATCHDOG_CASCADE_WINDOW_MS` | 3600000 | Rolling window for cascade cap (1 hour). |
| `WATCHDOG_CASCADE_MAX_RESTARTS` | 3 | Max watchdog-triggered restarts in window. |
| `WATCHDOG_CERT_ERROR_THRESHOLD` | 5 | Consecutive TLS handshake failures before cert-expired alarm. |
| `WATCHDOG_REQUEST_TIMEOUT_MS` | 5000 | Per-probe HTTPS timeout. |
| `WATCHDOG_TARGET_APP` | bizarre-crm | PM2 app name to supervise. |

### Logs

- `logs/bizarre-crm.out.log` — server stdout when supervised by PM2.
- `logs/bizarre-crm.err.log` — server stderr when supervised by PM2.
- `logs/bizarre-crm-watchdog.out.log` — watchdog stdout (state transitions, decisions).
- `logs/bizarre-crm-watchdog.err.log` — watchdog stderr (PM2 spawn errors, crashes).
- `logs/watchdog-events.jsonl` — structured event log read by the dashboard.

Preferred production rotation stays at the host/supervisor layer: PM2
`pm2-logrotate`, Docker log-driver `max-size` / `max-file`, journald
retention, or OS `logrotate`. For self-hosted installs that cannot rely on
those controls, the server also has an opt-in app-level rotating JSON/text
file sink. Set `LOG_FILE_ENABLED=true`; optionally set `LOG_FILE_PATH`
(default `logs/bizarre-crm.app.log` from the repo root), `LOG_FILE_MAX_SIZE`
(default `50M`), and `LOG_FILE_MAX_FILES` (default `10`, including the active
file). Stdout/stderr remain enabled for PM2/Docker, and file-sink failures
disable only the sink, not the server.

### Operator commands

```bash
# Start both apps (server + watchdog) from ecosystem.config.js
pm2 start ecosystem.config.js

# Tail watchdog decisions
pm2 logs bizarre-crm-watchdog

# Stop only the watchdog (server keeps running)
pm2 stop bizarre-crm-watchdog

# Verify watchdog is running
pm2 list
```

### Boot autostart

PM2 boot autostart on Windows is currently a manual step — see the
"Deferred operational items" section in `TODO.md` for the planned
cross-platform `setup.mjs` migration. On Linux/macOS, run `pm2 startup`
followed by `pm2 save` to install the platform-native init unit; both the
server and the watchdog will resurrect on boot.

## Operational Checklist

Before using BizarreCRM for a live shop day, verify:

- You can log in with a non-default password.
- 2FA is configured.
- Store information and tax settings are correct.
- Payment methods are correct.
- BlockChyp terminal payments work if used.
- SMS provider test passes if customer messaging is used.
- Backup location is configured.
- A test ticket can become an invoice.
- A test payment produces the expected receipt.
- Inventory stock changes as expected after a sale.
