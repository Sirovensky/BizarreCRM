# BizarreCRM Developer Guide

This guide is for engineers working in the repository.

## Requirements

- Node.js 22 or newer.
- npm 10 or newer.
- Git.
- Android Studio and Java 17 for Android work.
- Windows when packaging or testing the management dashboard's Windows service behavior.

## Install

```bash
npm install
```

## Root Scripts

```bash
npm run dev:server
npm run dev:web
npm run dev
npm run build
npm run health
npm run start
```

`npm run build` builds the shared package, web app, and server.

## Package Responsibilities

```text
packages/server       Express API, SQLite, migrations, auth, services, providers
packages/web          React browser CRM
android      Kotlin/Jetpack Compose Android app
packages/management   Electron Windows management dashboard
packages/shared       Shared TypeScript code
packages/contracts    Human-readable API contracts
```

## Server

Server code lives in `packages/server/src`.

Important areas:

- `routes/` for API behavior.
- `services/` for business and integration services.
- `providers/` for SMS/MMS and voice provider adapters.
- `db/` for migrations, seeds, connection code, and worker support.
- `middleware/` for auth, tenant resolution, error handling, rate limits, and request protection.

The server is the final authority for business rules. Frontends should not be trusted to enforce money, permissions, inventory, or tenant boundaries.

## Web

Web code lives in `packages/web/src`.

Important areas:

- `pages/` for route-level screens.
- `components/` for shared UI.
- `api/` for API wrappers and request/response typing.
- settings metadata for settings labels, defaults, status, and validation hints.

React Query is used for server state. Keep cache invalidation explicit after mutations that affect visible lists, totals, or detail pages.

## Android

Android code lives in `android`.

Important areas:

- Retrofit APIs and DTOs for server communication.
- Room database entities and DAOs for local state.
- WorkManager jobs for background sync.
- Compose screens and navigation for mobile UI.
- Firebase Messaging for push notifications.

When changing server shapes used by Android, update the Retrofit interface, DTO, local mapping, and contracts at the same time.

## Management Dashboard

Management code lives in `packages/management`.

The dashboard is an Electron app. The renderer is React; the main process owns desktop integration and service control.

Use the management package for server operations, update/restart flows, tenant admin, and health views. Do not put normal shop workflow features there.

## API Contract Workflow

When an API request or response changes:

1. Update the server route and validation.
2. Update the web API wrapper/types.
3. Update Android Retrofit/DTO code if Android uses the endpoint.
4. Update `packages/contracts/API_CONTRACT.md` or the relevant YAML contract.
5. Add or update focused tests where the behavior is risky.

Contracts should not include real secrets, customer data, production tokens, or live credentials.

## Data And Migrations

SQLite migrations live under `packages/server/src/db/migrations`.

Guidelines:

- Prefer additive migrations.
- Preserve existing tenant data.
- Store money as integer cents.
- Use transactions for multi-step money, inventory, and invoice changes.
- Avoid hard deletes for business records that may be needed for history.

## Documentation Expectations

Keep the README human-readable. Put long technical notes in `docs/`.

Useful locations:

- `docs/operator-guide.md` for running the app.
- `docs/product-overview.md` for feature explanation.
- `docs/android-field-app.md` for Android status.
- `docs/tech-stack-and-security.md` for stack and security detail.
- `TODO.md` for active open work.
