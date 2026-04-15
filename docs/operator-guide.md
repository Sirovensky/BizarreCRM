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
