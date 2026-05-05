# Android App Functionality Audit

*Audit date: 2026-04-04*

## Executive Summary

The Android app is a native Kotlin/Jetpack Compose app with Retrofit API integration. The infrastructure (auth, networking, database, navigation) is solid, but **virtually every screen beyond login and dashboard is non-functional** — data lists are hardcoded empty, action buttons have TODO comments, and several API contract mismatches will cause silent failures.

**17 of 18 screens are broken or incomplete. 24+ buttons do nothing.**

---

## Category 1: API Response Shape Mismatches (CRITICAL)

The app's Retrofit API interfaces declare return types like `ApiResponse<List<TicketListItem>>`, but the server wraps list data in named keys. Gson deserialization will silently fail (return null) for every list endpoint.

| Endpoint | App Expects (Retrofit type) | Server Actually Returns | Fix Needed |
|----------|---------------------------|------------------------|------------|
| `GET /tickets` | `ApiResponse<List<TicketListItem>>` | `{ success, data: { tickets: [...], pagination } }` | App needs to expect `TicketListResponse` with `tickets` field |
| `GET /customers` | `ApiResponse<List<CustomerListItem>>` | `{ success, data: { customers: [...], pagination } }` | Same — needs wrapper DTO |
| `GET /invoices` | `ApiResponse<List<InvoiceListItem>>` | `{ success, data: { invoices: [...], pagination } }` | Same |
| `GET /inventory` | `ApiResponse<List<InventoryListItem>>` | `{ success, data: { items: [...], pagination } }` | Same |
| `GET /invoices/:id` | `ApiResponse<InvoiceDetail>` | `{ success, data: { invoice: {...} } }` | App needs `InvoiceDetailResponse` with `invoice` field |
| `GET /inventory/:id` | `ApiResponse<InventoryDetail>` | `{ success, data: { item: {...}, movements, group_prices } }` | App needs `InventoryDetailResponse` with `item` field |
| `GET /notifications` | `ApiResponse<Map<String, Any>>` | `{ success, data: { notifications: [...], pagination } }` | Need typed DTO |
| `GET /sms/conversations` | `ApiResponse<Map<String, Any>>` | `{ success, data: { conversations: [...] } }` | Need typed DTO |
| `GET /settings/statuses` | `ApiResponse<List<Map<String, Any>>>` | `{ success, data: { statuses: [...] } }` | Need wrapper |

**Endpoints that ARE correctly shaped (no wrapper):**
- `GET /customers/:id` — server spreads customer into data directly ✅
- `GET /tickets/:id` — server puts ticket object directly in data ✅
- `GET /employees` — server returns bare array in data ✅

---

## Category 2: Missing/Wrong Endpoint Paths

| App Calls | Server Has | Issue |
|-----------|-----------|-------|
| `GET /tickets/stats` | Does not exist | Dashboard will crash/fail |
| `POST /auth/register-device` | Does not exist | FCM push registration will fail |
| `POST /notifications/read-all` | `POST /notifications/mark-all-read` | Wrong path — 404 |
| `POST /voice/call` | Does not exist | No voice routes on server |
| `GET /voice/calls` | Does not exist | No voice routes on server |

---

## Category 3: Field Name Mismatches

| Context | App Uses | Server Uses | Impact |
|---------|---------|-------------|--------|
| Token refresh response | `token` | `accessToken` | Auth refresh silently fails → user gets logged out |
| Invoice payment request | `payment_method_id` (Long) | `method` (String like "cash") | Payment recording will 400 or be ignored |
| Invoice payment request | `idempotency_key` field name | `Idempotency-Key` HTTP header | Server checks header, not body field |
| Dashboard stats | `open_count` | `open_tickets` | Dashboard shows 0 for open tickets |
| Dashboard stats | `low_stock_count` → from `/tickets/stats` | Field exists on `/reports/needs-attention` | Wrong endpoint entirely |
| Ticket note request | Generic `Map<String, Any>` body | Expects `{ type, content, device_id?, is_flag? }` | Field names unknown without ViewModel |

---

## Category 4: Broken Screens (24+ TODO Buttons)

### Completely Non-Functional (hardcoded empty data, no API calls):

| Screen | File | Issues |
|--------|------|--------|
| **TicketListScreen** | tickets/TicketListScreen.kt | `emptyList<TicketListItem>()` hardcoded. Refresh button = `/* TODO */` |
| **CustomerListScreen** | customers/CustomerListScreen.kt | `emptyList<CustomerListItem>()` hardcoded |
| **InvoiceListScreen** | invoices/InvoiceListScreen.kt | `emptyList<InvoiceListItem>()` hardcoded |
| **InventoryListScreen** | inventory/InventoryListScreen.kt | `emptyList<InventoryListItem>()` hardcoded. Barcode scan = TODO |
| **SmsListScreen** | communications/SmsListScreen.kt | `emptyList<SmsConversation>()` hardcoded. New message = TODO |
| **EmployeeListScreen** | employees/EmployeeListScreen.kt | `emptyList<EmployeeListItem>()` hardcoded |
| **ReportsScreen** | reports/ReportsScreen.kt | All zeros/placeholders, no API calls |
| **PosScreen** | pos/PosScreen.kt | Entirely TODO comments. New Repair, Quick Sale = TODO |

### Stubbed Detail Pages (parameter ignored, dummy data or loading forever):

| Screen | Broken Buttons | Details |
|--------|---------------|---------|
| **TicketDetailScreen** | Edit, Change Status, Add Note, Send SMS, Print (5 buttons) | ticketId param ignored, hardcoded loading |
| **CustomerDetailScreen** | Edit (1 button) | customerId param ignored, hardcoded dummy |
| **InvoiceDetailScreen** | Record Payment (1 button) | invoiceId param ignored, hardcoded dummy |
| **InventoryDetailScreen** | Edit, Adjust Stock (2 buttons) | itemId param ignored |
| **SmsThreadScreen** | Send, Flag, View Customer, Templates (4 buttons) | phone param ignored, send clears text but doesn't send |
| **NotificationListScreen** | Mark Read, Mark All Read (2 buttons) | Uses mock data, marks locally but no API call |
| **ClockInOutScreen** | Clock In/Out (1 button) | Toggles local boolean, no PIN verification API call |
| **ProfileScreen** | Change Password, Change PIN (2 buttons) | Hardcoded user data, buttons = TODO |
| **SettingsScreen** | Sync Now (1 button) | TODO comment |

### Partially Working:

| Screen | Status | Issues |
|--------|--------|--------|
| **LoginScreen** | WORKS | Multi-step auth flow implemented correctly |
| **DashboardScreen** | PARTIAL | Has ViewModel, loads data. But calls non-existent `/tickets/stats`, uses wrong field names for stats |

---

## Category 5: Data Type Mismatches

| Field | App Type | Server Type | Risk |
|-------|---------|-------------|------|
| `is_active` | Kotlin Int | SQLite INTEGER (0/1) | OK — compatible |
| `is_pinned`, `is_starred` | Kotlin Int | SQLite INTEGER (0/1) | OK |
| `is_flagged`, `is_pinned` (SMS) | DTO expects Boolean | Server returns INTEGER 0/1 | Gson may fail to deserialize |
| `email_opt_in`, `sms_opt_in` | Int in CreateRequest | Server stores as INTEGER | OK |
| `total`, `subtotal`, prices | Double | Server returns as number | OK |

---

## Fix Priority Plan

### P0 — Blocking (app is unusable without these)

1. **Fix response wrapper DTOs** — Create `TicketListResponse`, `CustomerListResponse`, `InvoiceListResponse`, `InventoryListResponse` etc. that have the named fields (`tickets`, `customers`, `invoices`, `items`) and `pagination`. Update Retrofit interfaces.

2. **Fix token refresh** — `RefreshResponse.token` must be renamed to `accessToken` (or add `@SerializedName("accessToken")`).

3. **Fix notification mark-all-read path** — Change from `/read-all` to `/mark-all-read`.

4. **Remove/stub non-existent endpoints** — Remove `tickets/stats`, `auth/register-device`, `voice/*` calls. Replace dashboard stats with `reports/dashboard` endpoint which exists.

### P1 — Core Screens (make list views show data)

5. **Wire up list screens with ViewModels** — Each list screen needs:
   - A ViewModel that calls the API
   - Correct response parsing (using the fixed wrapper DTOs)
   - Loading/error/empty states
   - Pull-to-refresh

   Screens: TicketList, CustomerList, InvoiceList, InventoryList, SmsList, EmployeeList, NotificationList

6. **Wire up detail screens** — Each detail screen needs:
   - Load data using the ID parameter
   - Display real data instead of dummies

   Screens: TicketDetail, CustomerDetail, InvoiceDetail, InventoryDetail, SmsThread

### P2 — Actions (make buttons work)

7. **Ticket actions** — Change status (PATCH), add note (POST), pin/star
8. **Invoice payment** — Fix field name (`method` string, not `payment_method_id` long)
9. **Inventory stock adjust** — Wire up `adjustStock` API
10. **SMS send** — Wire up `sms/send` endpoint
11. **Customer edit** — Wire up `PUT /customers/:id`
12. **Notification mark read** — Wire up `PATCH /notifications/:id/read`
13. **Clock in/out** — Wire up `POST /employees/:id/clock-in` and `clock-out`

### P3 — New Features

14. **POS screen** — Full implementation needed
15. **Reports** — Wire up `reports/dashboard`, `reports/sales`, `reports/needs-attention`
16. **Barcode scanner** — Wire up `inventory/barcode/:code`
17. **Customer create** — Wire up `POST /customers`
18. **Ticket create** — Wire up `POST /tickets`
19. **Profile** — Load from auth state, wire change password/PIN
20. **Sync** — Implement SyncWorker background sync

---

## Server Endpoints the App Should Use (Corrected Reference)

```
AUTH:
  POST /auth/login                    → { challengeToken, ... }
  POST /auth/login/2fa-verify         → { accessToken, refreshToken, user }
  POST /auth/login/2fa-setup          → { qr, challengeToken }
  POST /auth/login/set-password       → { challengeToken }
  POST /auth/refresh                  → { accessToken }  ← NOT "token"
  POST /auth/logout
  GET  /auth/me                       → { user }

TICKETS:
  GET    /tickets                     → { tickets: [...], pagination }
  GET    /tickets/:id                 → ticket object (flat in data)
  POST   /tickets                     → ticket object
  PUT    /tickets/:id                 → ticket object
  DELETE /tickets/:id
  POST   /tickets/:id/notes           → { type, content, device_id?, is_flag? }
  PATCH  /tickets/:id/status          → { status_id }
  PATCH  /tickets/:id/pin
  PATCH  /tickets/:id/star

CUSTOMERS:
  GET    /customers                   → { customers: [...], pagination }
  GET    /customers/:id               → customer object (flat in data)
  GET    /customers/search?q=         → [customers] (bare array)
  POST   /customers                   → customer object
  PUT    /customers/:id               → customer object

INVOICES:
  GET    /invoices                    → { invoices: [...], pagination }
  GET    /invoices/:id                → { invoice: {...} }  ← WRAPPED
  POST   /invoices/:id/payments       → { method: "cash", amount, notes? }  ← STRING not ID
  POST   /invoices/:id/void

INVENTORY:
  GET    /inventory                   → { items: [...], pagination }
  GET    /inventory/:id               → { item, movements, group_prices }
  POST   /inventory/:id/adjust-stock  → { quantity, type, notes? }
  GET    /inventory/barcode/:code     → { item }

SMS:
  GET    /sms/conversations           → { conversations: [...] }
  GET    /sms/conversations/:phone    → { messages, customer, recent_tickets }
  POST   /sms/send                    → { to, message }

NOTIFICATIONS:
  GET    /notifications               → { notifications: [...], pagination }
  GET    /notifications/unread-count  → { count }  ← field is "count"
  PATCH  /notifications/:id/read
  POST   /notifications/mark-all-read  ← NOT /read-all

EMPLOYEES:
  GET    /employees                   → [employees] (bare array)
  POST   /employees/:id/clock-in
  POST   /employees/:id/clock-out

REPORTS:
  GET    /reports/dashboard           → { open_tickets, revenue_today, status_counts, ... }
  GET    /reports/needs-attention     → { stale_tickets, missing_parts_count, overdue_invoices, low_stock_count }
  GET    /reports/sales?from=&to=     → sales data

SETTINGS:
  GET    /settings/config             → { key: value, ... }
  GET    /settings/statuses           → { statuses: [...] }  ← WRAPPED
```
