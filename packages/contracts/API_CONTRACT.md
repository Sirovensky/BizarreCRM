# BizarreCRM API Contract Reference

This folder is the safe, human-readable API reference for BizarreCRM. It is documentation only: no generated clients, no runtime imports, and no build tooling are wired to it yet.

Use these files to keep server, web, and Android aligned when a shared request or response shape changes.

## Safety Rules

- Do not store secrets here.
- Do not copy values from `.env`.
- Do not include real customer, shop, tenant, token, password, JWT, hCaptcha, Cloudflare, database, or production data.
- Use fake examples only, such as `demo-shop`, `admin@example.com`, `5550101000`, and `https://demo-shop.example.com`.

## Shared Response Envelopes

Successful responses use:

```json
{
  "success": true,
  "data": {}
}
```

Error responses use:

```json
{
  "success": false,
  "message": "Human-readable error"
}
```

Paginated list responses should include pagination metadata inside `data`:

```json
{
  "success": true,
  "data": {
    "items": [],
    "pagination": {
      "page": 1,
      "per_page": 25,
      "total": 0,
      "total_pages": 1
    }
  }
}
```

## API Contract Files

| File | Covers |
|---|---|
| `auth.yaml` | Login, 2FA, backup codes, sessions, password reset, PIN checks. |
| `signup.yaml` | Public shop signup, signup config, email verification mode. |
| `public.yaml` | Public tracking, customer portal, customer pay, public payment links. |
| `customers.yaml` | Customer CRUD, assets, analytics, merge, customer subresources. |
| `tickets.yaml` | Tickets, notes, devices, parts, photos, status changes, queue filters. |
| `invoices.yaml` | Invoices, payments, voids, credit notes, invoice lists. |
| `inventory.yaml` | Inventory items, suppliers, stock movements, purchase orders, barcodes. |
| `pos.yaml` | POS products, register, cash in/out, checkout, transactions. |
| `communications.yaml` | SMS, inbox, voice, notifications, templates, media uploads. |
| `settings.yaml` | Store settings, users, statuses, tax classes, templates, preferences. |
| `reports.yaml` | Dashboard, KPI, tax, inventory, technician, BI, scheduled reports. |
| `estimates-leads.yaml` | Estimates, approvals, lead pipeline, reminders, appointments. |
| `catalog.yaml` | Device catalog, supplier catalog, parts search, order queue. |
| `payments.yaml` | BlockChyp, memberships, payment links, refunds, gift cards, deposits. |
| `crm-marketing.yaml` | CRM enrichment, segments, campaigns, automations. |
| `imports.yaml` | RepairDesk, RepairShopr, MyRepairApp, OAuth import, factory wipe. |
| `operations.yaml` | Employees, roles, team, bench workflow, onboarding, search. |
| `management.yaml` | Local management dashboard and super-admin/server operations. |

## Drift Prevention Rule

If a shared API shape changes, update all affected code in the same commit:

- Server route behavior in `packages/server/src/routes`
- Web API wrapper/types in `packages/web/src/api`
- Android Retrofit interface/DTOs in `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote`
- The matching file in `packages/contracts`

If a contract describes an endpoint that is intentionally planned but not mounted yet, mark that endpoint with `implementation_status: planned` and do not treat it as callable from web or Android until the server route exists.

## File Format

The YAML files are intentionally lightweight. They are not full OpenAPI specs yet. Each file uses this structure:

```yaml
area: tickets
status: reference-only
source:
  server_routes:
    - packages/server/src/routes/tickets.routes.ts
  web_client: packages/web/src/api/endpoints.ts
  android:
    api: packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/api/TicketApi.kt
    dto: packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/dto/TicketDto.kt
auth: bearer
endpoints:
  - method: GET
    path: /api/v1/tickets
    purpose: List tickets.
    query:
      page: number optional
    response:
      data:
        tickets: Ticket[]
```

If this folder later grows into generated clients or formal OpenAPI files, keep this index as the human entry point.
