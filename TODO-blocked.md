---
name: TODO blocked items
description: Auto-extracted [!] blocked items from TODO.md; loop reads this file, not TODO.md
type: project
---

> **AUTO-GENERATED.** Source of truth is `TODO.md`. Regenerate via `bash scripts/regen-blocked.sh`.
> When an item flips to `[x]`, edit both this file and `TODO.md`; the next regen will reconcile.


## Repair templates: device-keyed seeding with multi-tier parts (REPAIR-TEMPLATES-SEED)

- [!] REPAIR-TEMPLATES-SEED-2. **Hydrate parts_json from real inventory + supplier scrape.** BLOCKED 2026-05-10 — three blockers: (1) supplier scrape (Mobilesentrix/PLP) is external HTTP scraping with no auth/rate-limit story in repo; (2) device_model_templates has no tier_label column to disambiguate Original-OEM vs Soft-OLED at lookup time; (3) inventory_device_compatibility is just a model↔item link with no per-fault filtering. Auto-attach acceptance criteria cannot be met without (a) tier_label column migration on device_model_templates AND inventory_items, (b) scrape job worker. Needs design pass first. The 173 seed leaves `parts_json: '[]'` — templates apply labor + suggested_price but don't pre-attach the SKU. Wire a follow-up that joins device_models → inventory_device_compatibility → inventory_items by tier label, and falls back to live Mobilesentrix / PhoneLCDParts scrape when the shop doesn't yet stock the SKU. Acceptance: opening "iPhone 13 — Screen (Original OEM)" auto-attaches the matching inventory line on apply.
- [!] REPAIR-TEMPLATES-SEED-1. **Original Seed task — extend coverage beyond the top 15 devices.** PARTIAL 2026-05-12 — migration 194 adds 75+ templates covering iPhone SE 2nd/3rd gen, iPhone X/XS/XS Max/XR, Pixel 6/6a/7a/8a, Galaxy A14/A15/A54/A55, Note 20, S20, Galaxy Z Flip 5 / Z Fold 5, OnePlus 9/10 Pro, iPad 9th/10th gen, iPad Air 5, iPad Mini 6, iPad Pro 12.9" M2, Apple Watch Series 7/8/9, MacBook Air M1/M2. Hardcoded sensible per-tier defaults (cents), `parts_json: '[]'` like 173, idempotent via `WHERE NOT EXISTS (name)`. Still [!] for the auto-attach inventory leg — that part is gated on SEED-2's tier_label + scrape worker. Reported 2026-05-09 — current Repair Templates picker on the ticket detail shows "No templates yet" for the most common devices (e.g. iPhone 13). User wants every popular phone/tablet to come pre-seeded with templates such as "iPhone 13 — Screen replacement" with multiple part-tier options the tech can pick at intake:
  - Tier A: Original OEM panel
  - Tier B: Refurbished OEM ("Original FOG" — third-party assembled with original glass)
  - Tier C: Soft OLED (XO7 / QV8)
  - Tier D: Aftermarket LCD
  Templates should also exist for battery, charging port, back glass, camera, speaker.
  Prices must respect the shop's pricing-tier configuration (`store_config.pricing_tiers`, set during the setup wizard's Repair Pricing step) — i.e. the seeder fans defaults through `seedDefaults.ts` so the auto-margin + tier thresholds the owner already configured win. Inventory rows should link via `inventory_device_compatibility` so the template line can pre-fill the inventory item id.
  Sources to scrape and reconcile:
  - Mobilesentrix product catalogue (existing `scrape_jobs` infrastructure exists in catalog routes)
  - PhoneLCDParts (PLP)
  - iFixit BOM data for OEM identification
  Acceptance: opening Repair Templates picker on iPhone 13 / Galaxy S21 / Pixel 7 etc. shows ≥4 templates each with tier-tagged parts pre-attached, prices respect tier_a/b/c medians, no manual seeding required.


## Dashboard simplification (DASHBOARD-SIMPLIFY) — DONE 2026-05-09


## Demand Forecast / charts not pulling RD-imported data (CHARTS-RD-IMPORT)

- [!] CHARTS-RD-IMPORT-1. **Fix the RepairDesk import path so it populates ticket_device_parts + invoices.** BLOCKED 2026-05-10 — diagnosis confirms root cause is upstream CSV gap (RepairDesk export omits parts/invoices), not importer code. Reproducing requires the actual user RD export to inspect column names; fix is column-mapping configuration once we have it. Needs sample CSV from user. [services/repairDeskImport.ts:571](packages/server/src/services/repairDeskImport.ts) has the INSERT for `ticket_device_parts`; line 610 inserts `invoices`. Verify: does the user's RD export CSV include parts/invoice data, and if so why isn't the importer hydrating those rows? Check the CSV column mapping + reproduce the import locally with the same dataset.


## Nav restructure: separate Communications and Leads (NAV-COMMS-LEADS-SPLIT) — DONE 2026-05-09


## Sidebar Recents grouping (NAV-RECENTS-GROUPING) — DONE 2026-05-09


## Calendar UX: vertical timeline + appointment cancel X (CAL-TIMELINE-CANCEL) — DONE 2026-05-09


## Payroll periods readability (PAYROLL-CONTRAST) — DONE 2026-05-09


## POS held-cart switch returns 500 (POS-HELDCART-BUSY) — DONE 2026-05-09


## Messages page: broken / hidden buttons (MESSAGES-BROKEN-BUTTONS)


## Catalog tenancy access gating (CATALOG-TENANCY-GATE) — RESOLVED 2026-05-09


## POS / tickets phone-tap integrations (POS-PHONE-TAP)


## Ticket list status-change PATCH no-op investigation (TICKETS-STATUS-NOOP)


## Cookie consent / privacy compliance (LEGAL-COOKIE-CONSENT)


## Web unwired controls audit (WEB-UNWIRED)

- [!] WEB-UNWIRED-007. **Scaffolding shipped 2026-05-11; awaiting Affirm/Klarna sandbox credentials.** Provider abstraction + route + web wrapper landed: `packages/server/src/services/financingProvider.ts` exposes `classifyCheckoutRequest`, `createCheckoutSession`, `verifyWebhookSignature`, and `parseWebhookEvent` with provider-specific branches for Affirm (HMAC-SHA256 on raw body) and Klarna (ECDSA — left as TODO). `packages/server/src/routes/financing.routes.ts` mounts `POST /api/v1/financing/checkout-session` (staff-only via authMiddleware, audit-logged) and `POST /api/v1/financing/webhook/:provider` (unauth, signature-gated). Per-tenant config keys (`billing_financing_enabled`, `billing_financing_min_cents`, `billing_financing_provider`, `billing_financing_provider_key`, `billing_financing_webhook_secret`, `billing_financing_return_url`, `billing_financing_cancel_url`) added to `ALLOWED_CONFIG_KEYS`; the two credential keys also in `ENCRYPTED_CONFIG_KEYS` so a tenant-DB leak doesn't expose merchant secrets. Web: `financingApi.createCheckoutSession` in `endpoints.ts`; `FinancingButton` now calls it when given `invoiceId` and either redirects or surfaces a 503 / not_configured message inside the modal. To finish: drop sandbox API keys into Settings → Payments → Financing, implement the two TODO blocks in `financingProvider.ts` (real Affirm POST /api/v2/checkout + Klarna POST /payments/v1/sessions + Klarna ECDSA + event-shape parsing + invoice-payment recording on `authorized`/`captured`). Stays `[!]` because final money flow needs live sandbox QA, but the audit-blocker "no provider config surface" is now closed.


## BizarreSMS hosted-tier provider (HOSTED-SMS-1)


## Signup flow consolidation (SSW-CANON-SIGNUP)


## Dynamic repair-pricing index (DPI-PRICE-INDEX) — major feature

- [!] DPI-6. **Full arbitrary 2-5 tier rewrite is blocked.** Blocked 2026-05-06 — the practical 3-tier controls are implemented (owner-editable labels/colors, configurable A/B age windows, per-tier profit alert floors, impact preview, admin confirmation, audit, and admin email). The remaining 2-5 selectable-tier version requires a deliberate cross-app contract migration from the hardcoded `tier_a`/`tier_b`/`tier_c` API, seed data, wizard state, auto-margin rules, tests, and `repair_prices.tier_label` storage to a `pricing_tiers` / `repair_prices.tier_id` model. Doing that inline would create a high-risk schema/API break for POS, setup, and pricing automation.


## Web Audit Wave-WEB-2026-04-24 — secondary surfaces (search agent A3)


## Web Audit Wave-WEB-2026-04-24 — settings tabs + setup wizard (search agent A1)


## Web Audit Wave-WEB-2026-04-24 — core entity workflows (search agent A2)


## Web Audit Wave-WEB-2026-04-24 Search S6 — entity create + employee + comms + reports


## AUDIT CYCLE 1 — 2026-04-19 (shipping-readiness sweep, web + Android + management)

- [!] AUDIT-AND-012. **[P0 OPS] google-services.json is placeholder — FCM push dead.** Blocked 2026-05-06 — this is a real release blocker, but it is an operator/Firebase-console artifact, not code-side fixable. The Firebase project owner must generate the real `google-services.json` and place it in `android/app/`; editing fake IDs/API keys in source would only create another unverifiable broken config.
- [!] AUDIT-AND-017. **Virtually all user-facing strings hardcoded — no strings.xml coverage.** Blocked 2026-05-06 — product critique: this is valid for long-term accessibility/i18n, but not a safe single TODO closure. Current scan finds 3,136 obvious hardcoded user-facing string sites across 858 Kotlin files, with partial existing `strings.xml` coverage. A correct fix needs a dedicated Android localization pass, build/QA, locale policy, and translation workflow; doing a small automated extraction now would create false confidence and likely regress Compose/ViewModel string formatting.


## TENANT PROVISIONING HARDENING — 2026-04-10 (Forensic analysis)


## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10


## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)


## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)


## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)


## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)


## Executive Summary


## Low Priority / Usability Findings


## APRIL 14 2026 CODEBASE AUDIT ADDITIONS


## High Priority Findings


## Medium Priority Findings


## Low Priority / Audit Hygiene Findings


## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)


## Security Audit Findings (2026-04-16) — deduped against existing backlog

- [!] SEC-H34-money-refactor. **Convert money columns REAL → INTEGER (minor units)** across invoices/payments/refunds/pos_transactions/cash_register/gift_cards/deposits/commissions. (PAY-01) DEFERRED 2026-04-17 — scope is fleet-wide: schema migration across 8+ tables in every per-tenant DB, every SELECT/INSERT/UPDATE in server code that touches those columns (dozens of handlers in invoices/pos/refunds/giftCards/deposits/membership/blockchyp/stripe/reports routes + retention sweepers + analytics), web DTO + form handling (every money field in pages/invoices, pages/pos, pages/refunds, pages/giftCards, pages/deposits, pages/reports), and Android DTO + UI updates. Recipe: (1) add new `_cents` INTEGER columns alongside each existing REAL column; (2) dual-write period where both columns are kept in sync; (3) flip reads to the cents columns handler-by-handler; (4) reconcile any drift; (5) drop REAL columns. Each step must ship separately with its own verification; skipping this phasing risks silent rounding corruption on live invoices. Not safe as a single commit. Blocks SEC-H37 (currency column) — they should land as a joint cents+currency migration.
  - [!] BLOCKED 2026-05-11 (autoloop terminal): scope audit shows 99 REAL columns across `packages/server/src/db/migrations/*.sql` (43 in `001_initial.sql` alone). 13 newer migrations already use `_cents` INTEGER on new tables (installments, recurring invoices, billing, bookings, held carts) — partial precedent for the target schema. Remaining work is still fleet-wide across server + web + Android with live-money QA on each phase; the autoloop is the wrong tool. Tracked here as a deliberate non-attempt rather than a fixable item.
- [!] SEC-H40-needs-live-smoke. **Deposit DELETE processor refund code is implemented; live BlockChyp smoke remains.** CLOSED-FOR-CODE 2026-05-06 — BlockChyp refund wrapper, deposit `payment_id` linkage, deposit application payment rows, invoice paid/due reconciliation, processor refund claims, and reversal-state migration are implemented and covered by focused tests. Blocked only on live terminal/processor QA before production rollout.
- [!] SEC-H41-needs-live-webhook-spec. **BlockChyp `/void-payment` processor code is implemented; webhook receiver remains blocked on verified HMAC/live behavior.** DEFERRED 2026-05-06 — `voidCharge()` / `/blockchyp/void-payment` processor call, duplicate-void claim, local `capture_state='voided'`, invoice balance rollback, and `/blockchyp/capture-payment` are implemented and tested. Remaining blocker is the unauthenticated BlockChyp webhook receiver with verified HMAC/signature semantics and live terminal smoke-test.
  - [!] BLOCKED: `voidCharge()` / `/blockchyp/void-payment` processor call, duplicate-void claim, local `capture_state='voided'`, invoice balance rollback, and `/blockchyp/capture-payment` are implemented and tested. Remaining blocker is the unauthenticated BlockChyp webhook receiver + HMAC spec and live terminal smoke-test.
### MEDIUM

### Uncertain overlaps — verify before starting (human review)

- AZ-019 (SMS inbound-webhook forge) — verified.jsonl rejected as CRITICAL (drivers fail-closed). Latent: `getSmsProvider` not tenant-scoped. Possibly overlap AUD-M22/23/24 in DONETODOS.md.
- PROD12 (PIN 1234) ↔ BH-S006 / SEC-H15 — same default PIN. Keep one.
- PROD15 (rate limit signup / forgot-password) ↔ SEC-H85 CAPTCHA — both needed (rate limit + captcha complementary).
- PROD29 (SSRF audit) ↔ SEC-H92 / SEC-H93 — consolidate under PROD29 or split.
- PROD32/33/34 (HSTS, cookies, CSP) ↔ SEC-H89 — review merge.
- PROD44 (super-admin auth separate check) ↔ SEC-H105 — subtask.
- TS1/TS2 (tenant-owned Stripe) ↔ SEC-C3 / SEC-M36 — adjacent, keep separate.
- AUD-M19 (LRU pool eviction refcounting) ↔ SEC-H124 — dedupe.
- AUD-L19 (super-admin TOTP replay) ↔ SEC-M3/M4 — dedupe.
- SA1-2 (localStorage token storage) ↔ SEC-H61 — consolidate.
- AUD-20260414-H4 (Android cert pins) ↔ SEC-H99 — same placeholder-pin finding; dedupe.

### Phase 4 live-probe positive controls (no action — reference only)

Verified working. Not TODOs.

- JWT `algorithms:['HS256']` + iss/aud pinned on every verify.
- Stripe webhook signature + 300s replay window + INSERT OR IGNORE idempotency (forge rejected 400).
- Helmet HSTS `max-age=63072000 includeSubDomains preload` + CSP + Referrer-Policy + Permissions-Policy.
- bcrypt cost 12 users / 14 super-admins; constant-time password compare with dummy-hash + 100ms floor.
- DB-backed rate limits (migration 069) SURVIVE server restart (login 429 persisted 3 restarts). (LIVE-06)
- POS `/transaction` single `adb.transaction()` with `expectChanges` guards.
- Gift-card redeem guarded atomic UPDATE (no double-spend).
- Store-credit decrement guarded atomic UPDATE.
- `counters.allocateCounter` transactional `UPDATE...RETURNING`.
- `stripe_webhook_events` PK + `INSERT OR IGNORE` (+ SEC-C3 transaction-wrap still needed).
- requestLogger redacts Authorization/Cookie/CSRF/API-key/password/token/pin/auth.
- `/uploads` path traversal blocked 403 (`/uploads/%2e%2e%2f%2e%2e%2f.env` → 403).
- `.env` not HTTP-reachable (all enumerated paths serve SPA fallback).
- `/super-admin/*` localhostOnly fix shipped in commit 585a06c — BH-S002 / LIVE-03 mitigated, external requests 404 (see DONETODOS.md).


## Cross-platform scope decisions (surfaced by ios/ActionPlan.md review, 2026-04-20)

- [!] **TEAM-CHAT-AUDIT-001. Team chat data-at-rest audit (server + clients).** **[AUTOLOOP-T0 BLOCKED: 7-item audit covering SQLCipher, retention, GDPR, redactor — multi-week design, not a fix.]**
  Surfaced from `ios/ActionPlan.md §47`. Server today stores message bodies in SQLite TEXT columns (`team_chat_messages.body TEXT NOT NULL`, migration `096_team_management.sql`). No column-level encryption, no hashing. Fine as a staff-chat MVP but needs a comprehensive review before scaling:
  1. **At-rest encryption.** Does the tenant server DB sit on an encrypted filesystem? For SQLite deployments, the file is plaintext-readable unless SQLCipher (or equivalent) is applied at the DB layer. Cloud-hosted tenants inherit our infra's disk encryption; self-hosted tenants are on their own.
  2. **In-transit.** HTTPS already covers this; verify no polling fallback ever lands HTTP.
  3. **Access control.** Current server reads require only auth; verify tenant-scoping on every `SELECT` (audit reports this is correct but re-confirm).
  4. **Retention policy.** No expiry today. Decide: forever / 1yr / 90d / per-tenant config. Add a purge job.
  5. **Export.** Tenant owner can currently query via admin UI only. GDPR / CCPA subject-request flow should be able to export a user's messages + @mentions on request (§139 in ActionPlan).
  6. **Moderation.** Admins can delete any message (§47.10); user own-delete window 5 min. Deleted messages retain body in audit log for manager review — check the audit blob doesn't also go plaintext into telemetry (§32.6 Redactor).
  7. **PII / secret risk.** Free-form chat can carry phone numbers, customer names, even tokens (via copy-paste). Apply §32.6 placeholder redactor when a message body is quoted in any telemetry / log / crash payload. Never redact the stored message itself (that's what users typed), only our observability copies.
  8. **HIPAA / PCI tenants.** If a tenant processes PHI or PAN-adjacent data, plaintext chat is a non-starter. Gate: tenants with HIPAA / PCI mode enabled must opt into column-level encryption on `team_chat_messages.body` (server-side, key derived from tenant secret) OR have team chat disabled for them entirely.
  9. **Search.** Currently index-free. Future FTS5 would index plaintext too. Audit before that ships.
  10. **Backup.** Tenant-server backups include the chat table; make sure backup encryption is at least as strong as the primary store.
  11. **Client cache.** Web + iOS + Android will locally cache messages (offline support). iOS/Android use SQLCipher — covered. Web uses IndexedDB / localStorage — needs its own review.
  Block wide rollout of team chat (iOS + Android) until findings close.

  Surfaced from `ios/ActionPlan.md §47`. Server + web both ship team chat today (`/api/v1/team-chat`, `/team/chat`). Android has zero references. Parity work for Android: list channels, thread view, compose + @mention, polling with `?after=<id>` cursor (matches server MVP), room for later WS upgrade. Shares schema with iOS once iOS ships; both should use the same shape so server doesn't grow per-client variants. Blocks iOS team-chat merge.

  Surfaced from `ios/ActionPlan.md §60` / §89. Server has `/api/v1/stocktake` (`stocktake.routes.ts`) and web has `pages/inventory/StocktakePage.tsx`. Android only references stocktake in a dashboard widget placeholder. Full Android parity: sessions list, per-session count UI, barcode-scan loop, variance resolution, adjust on commit. Follows same cursor-based pagination contract the other list surfaces use.

### Wave-Loop Finder-A run 2026-04-24 — web/pages auth+signup+landing+dashboard+settings+team+super-admin+setup+billing+subscriptions+employees
- [~] WEB-FA-013. **[MED] DashboardPage: Hard-coded supplier domains:** mobilesentrix.com, phonelcdparts.com — not configurable from Settings. Fixer-B14 2026-04-25 — partial: extracted to `SUPPLIER_BASE_URLS` lookup at the top of the missing-parts block (`packages/web/src/pages/dashboard/DashboardPage.tsx`) so adding a third supplier is a one-line map entry. True per-tenant Settings configurability still pending (server `store_config` key + Settings UI).
  <!-- meta: scope=web/pages/dashboard; files=packages/web/src/pages/dashboard/DashboardPage.tsx:174-177; fix=move-to-catalog-provider-config -->

### Finder-C web polish findings (2026-04-24) — pages/{tickets,loaners,leads,automations,marketing,communications,reports,reviews,photo-capture,portal,print,tracking,tv,voice,expenses}
- [~] WEB-FC-012. **[MED] `ReferralsDashboard` computes stats from only the first page of rows.** Server returns rows with no pagination metadata, and the page computes `total`, `converted`, `conversion_rate`, and the leaderboard from that array — totals understate reality as soon as there are >N referrals. No "showing X of Y" footer. — **Fixer-B23 2026-04-25 [PARTIAL-truth-in-UI]**: query now reads `meta.total` or `X-Total-Count` header when the server provides one; if `serverTotal > rows.length` the "Total referrals" stat renders as `N+`, an amber `role="note"` banner says "Showing N of Y. Totals/conversion rate/leaderboard computed from the loaded page only." Fully-correct stats still need either a `/reports/referrals/stats` endpoint or pagination iteration server-side; tracked open for that.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/ReferralsDashboard.tsx:52-75,98; fix=add-/reports/referrals/stats-endpoint-or-iterate-pagination-before-computing -->

### Finder-B web polish findings 2026-04-24 — web/pages pos+unified-pos+catalog+inventory+customers+invoices+estimates+gift-cards

























### Wave-Loop Finder-F run 2026-04-24 — deeper page audit (forms/mutations/perf/i18n/cents)



- [~] WEB-FF-003. **[HIGH] Web pages use zero `Intl.NumberFormat` / `Intl.DateTimeFormat` — every currency, percent, date is hand-formatted with hardcoded en-US locale + `$` symbol.** 98 `toLocaleString`/`toLocaleDateString` calls, 106 `toFixed(...)` calls in pages but **0** Intl uses. EUR/GBP/CAD tenants, RTL languages, and any non-en-US locale see broken formatting. Single-tenant settings already include a `locale` field that's never read. PARTIAL (Fixer-DD 2026-04-25): added `formatShortDateTime` + `formatNumber` to utils/format.ts; switched format.ts internals from `'en-US'` to module-level `_locale`; consolidated LeadDetailPage (3 sites), CustomerDetailPage (1), and CustomerPortalPage `formatWidgetDate` (1) onto the helper. PARTIAL (Fixer-MM 2026-04-25): consolidated SettingsChangeHistory (1), AuditLogsTab (1), AutomationsTab (2), StocktakePage (1), CampaignsPage (1), ZReportModal (2) onto `formatDateTime` — 8 more sites fixed. PARTIAL (Fixer-UUU 2026-04-25): swept 8 more files / ~16 sites — ReportsPage chart axes+tooltips (4 `$${...}` → `formatCurrency`), TechnicianHoursTab YAxis (1 `$${v}` → `formatCurrency`), InventoryListPage (4 `$${...toFixed(2)}` → `formatCurrency` for cost/retail/price-preview/catalog-match), CommunicationPage ticket-total tooltip (1 `$${Number(t.total).toFixed(2)}` → `formatCurrency`), GiftCardDetailPage local `formatCurrency`/`formatBalance` now delegate to shared `formatCurrency` (drops 2 hardcoded `$` literals while preserving the cents-vs-dollars normalisation), SettingsPage (6 bare `n.toLocaleString()` → `formatNumber`), CatalogPage (2 `n.toLocaleString()` → `formatNumber`), CashDrawerWidget toast (1 `$${...toLocaleString()}` → `formatCurrency`). PARTIAL FIXED-by-Fixer-A20 2026-04-25: DangerZoneTab — 3 `new Date(...).toLocaleString()` sites (token-expires + scheduled-at + permanent-delete-on) routed through `formatDateTime`, dropping the last hardcoded en-US datetime in the tenant-termination flow. Remaining: ~7 `toLocaleString` datetime sites in Marketing/Communications/SettingsPage line 2996 + portal datetime callsites; raw `${val.toFixed(2)}` still in MembershipSettings/RepairPricingTab/DeviceTemplatesPage (tracked as WEB-FF-022).
  <!-- meta: scope=web/all-pages; files=packages/web/src/pages/**/*.tsx; fix=create-utils/format.ts-formatCurrency/formatDate-using-Intl+respect-tenant-locale -->











- [~] WEB-FF-014 (partial). **[MED] Most list pages use `key={i}` (array index) for skeletons + import-preview rows — re-render shifts state/animations onto wrong rows.** Found in CustomerListPage.tsx:830, EstimateListPage.tsx:47,501, TicketListPage.tsx:1308,1548,1648, LeadListPage.tsx:82,442, GiftCardsListPage.tsx:223, TvDisplayPage.tsx:104,168, InvoiceListPage.tsx:225,234,253,262, plus PortalInvoicesView.tsx:133 + PortalTicketDetail.tsx:141. Skeletons are mostly fine, but the import-preview rows (CustomerListPage:830) and chart `<Cell key={i}>` mappings flicker on data change. PARTIAL-Fixer-B9 2026-04-25 — flagship CustomerListPage import-preview row swapped from `key={i}` to a content-hash composite (`vals.join('|') + '#' + i`); inner `<td>` cells now keyed `${rowKey}:${j}`. Re-parses after edit-then-re-paste no longer shift focus/animations onto the wrong row. Remaining list pages + chart `<Cell key={i}>` still pending. PARTIAL 2026-05-12 (autoloop): chart `<Cell key={i}>` arm closed — `ReportsPage.tsx` (popular_models / popular_services / revenue_by_model bars: `key={entry.name}`), `TechnicianHoursTab.tsx` (hours/revenue bars: `key={'hours:'+entry.name}` / `'revenue:'+entry.name`), `CustomerAcquisitionTab.tsx` (monthly bar: `key={entry.month}`). `grep -rn '<Cell key={i' packages/web/src` now zero. Remaining: skeleton + list-row `key={i}` sites in EstimateListPage / TicketListPage / LeadListPage / GiftCardsListPage / TvDisplayPage / InvoiceListPage / PortalInvoicesView / PortalTicketDetail. PARTIAL 2026-05-12 (autoloop tick 2): portal real-data row maps closed — `PortalInvoicesView` line-items now key on `${item.description}:${item.total}:${i}` (portal type has no id) and payments key on `${p.date}:${p.method}:${p.amount}:${i}`; `PortalTicketDetail` devices map keys on `d.id` (stable per portalApi.TicketDetail.devices[].id) and the timeline map keys on `${entry.type}:${entry.created_at}:${i}` so status-change + message + SMS rows don't shift animations on incremental refetch. Remaining sites are pure skeletons or positional grid cells (Calendar MonthView), where `key={i}` is correct.
  <!-- meta: scope=web/multiple; files=packages/web/src/pages/customers/CustomerListPage.tsx:830,packages/web/src/pages/portal/PortalInvoicesView.tsx:133,packages/web/src/pages/invoices/InvoiceListPage.tsx:225,253; fix=use-stable-id-or-content-hash-where-data-can-mutate -->

- [~] WEB-FF-015 (partial — ReportsPage TechWorkloadChart). **[MED] DashboardPage / NpsTrendPage / ReportsPage useQuery never check `isError` — any 401/500 keeps the skeleton or empties to "0" indefinitely.** DashboardPage.tsx has 12+ `useQuery` calls, every one only destructures `{ data, isLoading }`. A logged-out token shows pulsing skeletons forever; staff think dashboard is "loading slow" when it's actually 401-looped. ReportsPage same pattern (existing FC-011 covers Nps/Referrals). — Fixer-B17 2026-04-25: ReportsPage `TechWorkloadChart` now destructures `isError` and renders `<ErrorState />` so a 401/500 stops masquerading as "No technician workload data". Remaining DashboardPage useQuery calls (12+) still ungated.
  <!-- meta: scope=web/dashboard,web/reports; files=packages/web/src/pages/dashboard/DashboardPage.tsx:858,866,874,1182,1507,1629,1665,1673; fix=destructure-isError-and-render-error-state-or-bubble-to-ErrorBoundary -->




- [~] WEB-FF-019. **[LOW] CustomerDetailPage `${memberData.monthly_price.toFixed(2)}/mo` — float multiplication lurking.** Lines 920, 1016 (tier list), 1526 (ticket totals), 1615/1618 (invoice totals). All `.toFixed(2)` on numbers that are *probably* dollars-as-float from the server. If membership price is migrated to cents (matching POS migration), every value is 100× wrong silently — same risk as WEB-FB-001 gift card. (Fixer-C11 2026-04-25: dropped an `@audit-cents` flag-comment above the L960 active member badge call site so the next cents-migration sweep finds the call site without grep — full migration to `formatCents(monthly_price_cents)` still pending server schema change.)
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerDetailPage.tsx:920,1016,1526,1615,1618; fix=accept-cents-from-server+single-formatCurrency(cents)-helper -->

### Wave-Loop Finder-D run 2026-04-24 — components/hooks/stores/api/utils














- [!] WEB-FD-014. **[MED] `endpoints.ts` is 27k tokens / single-file mega-export — every page-level import drags the whole module graph.** Vite tree-shakes named exports but TypeScript declaration-merging across the file means a typo in one route forces a typecheck on every consumer. Split into `endpoints/{auth,ticket,customer,inventory,…}.ts` re-exported via `endpoints/index.ts`. Bundle and HMR cost: every chunk pulls every endpoint definition. **[AUTOLOOP-T0 BLOCKED: 2042-LOC file → 15+ domain modules + hundreds of import-site updates. Too broad.]**
  <!-- meta: scope=web/api; files=packages/web/src/api/endpoints.ts; fix=split-by-domain+re-export-via-barrel -->




  PARTIAL FIXED-by-Fixer-C12 2026-04-25 — partial US-shape inputs of 4-9 digits with no leading `+` now promote to a progressive canonical form (`+1 (303)-261-19`, `+1 (303)-26`, etc.) so display surfaces stop showing a mix of canonical and raw side-by-side. International (UK/AU/MX with `+` prefix) still echoes through unchanged — full E.164 normalisation needs a `libphonenumber-js` wrapper which is out of scope for this loop.
  <!-- meta: scope=web/utils; files=packages/web/src/utils/format.ts:118-131; fix=use-libphonenumber-js-or-document-non-US-skip-explicitly -->








### Wave-Loop Finder-E run 2026-04-24 — root configs + cross-cutting a11y










- [~] WEB-FE-010 (PARTIAL). **[MED] `<html lang="en">` is hard-coded — the app already i18n's currency in some pages (§FB-010) but never sets `lang` per tenant locale.** *(PARTIAL Fixer-OOO 2026-04-25 — `main.tsx` bootstrap now seeds `document.documentElement.lang` from `navigator.language` (BCP-47 sanity-checked), so es-MX/fr-CA browsers immediately get correct screen-reader pronunciation. Tenant-locale override surface is still pending — when settings.locale lands, callers can override via the same `documentElement.lang` setter.)*
  <!-- meta: scope=web/a11y; files=packages/web/index.html:2; fix=expose-tenant.locale-via-meta-and-update-document.documentElement.lang-on-mount -->



- [~] WEB-FE-013 (PARTIAL). **[MED] App-wide tables (`CustomerListPage`, `CustomerDetailPage`, `NotificationTemplatesTab`, `SettingsPage`, `AuditLogsTab`) have zero `scope="col"` / `scope="row"` / `<caption>` — screen readers can't associate cells to headers.** *(PARTIAL 2026-05-12 — `NotificationTemplatesTab.tsx` table now ships `scope="col"` on all 6 `<th>` cells + sr-only `<caption>` (autoloop tick). `AuditLogsTab.tsx` already done (Fixer-OOO 2026-04-25). CustomerListPage / CustomerDetailPage / SettingsPage still pending; same pattern (1 line per th + 1 caption).)*
  <!-- meta: scope=web/a11y; files=packages/web/src/pages/customers/CustomerListPage.tsx:705-710,packages/web/src/pages/settings/AuditLogsTab.tsx,packages/web/src/pages/settings/NotificationTemplatesTab.tsx; fix=add-scope=col-on-th+visually-hidden-caption -->




## Web Audit Wave-WEB-2026-04-24 Search S4 — auth + setup + portal


## Web Audit Wave-WEB-2026-04-24 Search S5 — cross-cutting UX


## Web Audit Wave-WEB-2026-04-24 Search S7 — data integrity + edge cases

- [!] DASH-ELEC-024-needs-licensed-fonts. **Web side self-hosted 2026-05-11 (Bebas Neue + Jost 400/500/700 + JetBrains Mono 400/500 fetched from Google Fonts; @font-face declarations land in `packages/web/src/styles/globals.css`). Tailwind `font-display` / `font-sans` / `font-mono` / `font-logo` tokens already chained correctly. Management dashboard self-hosted Jost 400/500/700 2026-05-12 — TTFs copied from `packages/web/public/fonts/` to `packages/management/src/renderer/src/assets/fonts/jost_{regular,medium,bold}.ttf`; `globals.css` adds `@font-face` declarations so Tailwind's `sans` chain (Futura → Jost → Inter) now resolves to repo-bundled Jost on the renderer. Inter assets retained as fallback. Exact Saved By Zero + Futura Medium remain pending licensed source files — Saved By Zero is donation-ware (free for personal, license for commercial), Futura is commercial-only; both fall back to Bebas Neue / Jost respectively until licensed copies are dropped under `packages/web/public/fonts/`.










































































- [!] DASH-ELEC-116. **[LOW][I18N] All 400+ user-facing strings hardcoded English — no i18n framework** — packages/management/src/renderer/src/ entire tree — no i18next/react-intl. Fix: adopt i18next with `en.json` namespace as foundation; literals become `t('key')` calls. **[AUTOLOOP-T0 BLOCKED: requires new i18next dep + extracting 400+ strings across 52 renderer files.]**

































































- [!] DASH-ELEC-269. **[LOW][DEBT] EnvFieldCategory union duplicated** — management-api.ts:145 + bridge.ts:203. — Fixer-C26 2026-04-25 (PARTIAL — drift-defense only): cross-reference comment added on both type declarations explaining that Electron main and renderer compile to separate bundles with no `packages/management/src/shared/` folder yet, so the union is intentionally duplicated; instructs future contributors to edit BOTH files in the same commit and points at the eventual cleanup path. Real dedup still requires creating a shared types file referenced by both tsconfigs. **[AUTOLOOP-T0 BLOCKED: tsconfig.node rootDir + tsconfig include block any shared/ import without build-config restructure.]**



---


## Web Audit Wave-WEB-2026-04-24 Search S8 — RBAC + backend route gaps

- [!] WEB-FM-012. **[MED] Six pages exceed 1,500 LOC + endpoints.ts at 1,287 LOC — page-as-monolith pattern blocks tree-shake / parallel TS check.** After SettingsPage (3,464): `CommunicationPage.tsx` (2,223), `CustomerDetailPage.tsx` (2,142), `DashboardPage.tsx` (2,112), `TicketWizard.tsx` (2,008), `TicketListPage.tsx` (1,817), `InventoryListPage.tsx` (1,780), `RepairsTab.tsx` (1,448), `ReportsPage.tsx` (1,396). Each contains 5-15 tightly-coupled inline subcomponents. The single `endpoints.ts` causes any tiny API tweak to invalidate the cached type-build for all pages — split per-domain (auth, billing, tickets, inventory, ...). **[AUTOLOOP-T0 BLOCKED: shared inline types/utils used across all subcomponents; even smallest extraction needs project-spanning refactor.]**
  <!-- meta: scope=web/pages+api; files=packages/web/src/pages/communications/CommunicationPage.tsx,packages/web/src/pages/customers/CustomerDetailPage.tsx,packages/web/src/pages/dashboard/DashboardPage.tsx,packages/web/src/pages/tickets/TicketWizard.tsx,packages/web/src/pages/tickets/TicketListPage.tsx,packages/web/src/pages/inventory/InventoryListPage.tsx,packages/web/src/api/endpoints.ts; fix=extract-inline-subcomponents-into-co-located-./components/+split-endpoints.ts-by-domain -->










### Wave-Loop Finder-Q run 2026-04-24 — visual polish + brand consistency












  <!-- meta: scope=web/pages; files=packages/web/src/pages/customers/CustomerListPage.tsx:577,804,packages/web/src/pages/customers/CustomerDetailPage.tsx:565,packages/web/src/pages/leads/LeadListPage.tsx:126,packages/web/src/pages/leads/CalendarPage.tsx:93,204; fix=elevation-tokens(button=shadow-sm,popover=shadow-md,modal=shadow-xl,toast=shadow-2xl)+codemod -->


- [!] WEB-FQ-014. **[MED] No EmptyState illustration — empty lists render plain `<p class="text-sm text-surface-400">No X yet</p>`, no icon, no CTA, on 18+ pages.** `NotificationTemplatesTab.tsx:280`, `CustomerDetailPage.tsx:980,993`, `SettingsPage.tsx:552`, `MembershipSettings.tsx:496`, `ReceiptSettings.tsx:187`, `AuditLogsTab.tsx:119`, `DeviceTemplatesPage.tsx:232,413`, `TicketNotes.tsx:302`, `RepairPricingTab.tsx:301,547`, `TicketDevices.tsx:86,519` — all single-line text. Shared `EmptyState` component exists (`shared/EmptyState.tsx`, used 5× in SettingsPage) but adoption is partial. New users see flat "no data" everywhere instead of guided illustrations. **BLOCKED 2026-05-10: 18+ site codemod, requires per-page icon/copy/CTA decisions; not safe in one pass.**
  <!-- meta: scope=web/pages; files=packages/web/src/components/shared/EmptyState.tsx,packages/web/src/pages/settings/NotificationTemplatesTab.tsx:280,packages/web/src/pages/customers/CustomerDetailPage.tsx:980,packages/web/src/pages/tickets/TicketNotes.tsx:302; fix=expand-EmptyState-to-take-icon+title+description+action-prop+codemod-inline-`<p>No X yet</p>`-instances -->

- [!] WEB-FQ-015. **[MED] Native browser `<select>` used 25× in pages while shared CommandPalette + custom dropdowns coexist — different a11y, hover, selection visuals.** `CustomerListPage.tsx:609,627`, `CustomerCreatePage.tsx:236`, all use raw `<select>` with `rounded-md` + Tailwind classes. Other surfaces (e.g. CustomerListPage:926 column-picker) hand-roll a custom `<div role="menu">` dropdown. Selects don't open to themed listbox; dropdowns don't follow native keyboard rules. No shared `<Select>` primitive. Date-picker landscape similar — 14 native `<input type="date">` only, no library; 0 themed pickers. (Memory says brand surface ramp drift.) **[AUTOLOOP-T0 BLOCKED: requires Radix/HeadlessUI + DatePicker deps + codemod 128 native selects. Too broad.]**
  <!-- meta: scope=web/pages+components; files=packages/web/src/pages/customers/CustomerCreatePage.tsx:236,packages/web/src/pages/customers/CustomerListPage.tsx:609,627,926; fix=add-shared/Select.tsx+shared/DatePicker.tsx-as-headless-radix/HeadlessUI-wrappers+codemod-25-native-selects -->

- [!] WEB-FQ-016. **[MED] Status-color usage uses raw amber/blue/green/red Tailwind colors with NO dark variants in 30+ spots — light-only badges.** `CustomerListPage.tsx:464` rounded-full badge; `DashboardPage.tsx:284,314,355,738,776` `text-amber-600 dark:text-amber-400` (dark variants present here) but `:1338,1873` only `text-red-500` / `text-green-600` (no dark:). Customer detail page `border-purple-200 text-purple-700 bg-purple-50 dark:border-purple-500/30 dark:text-purple-300 dark:bg-purple-500/10` (long), but other pages omit the `dark:` arm. Inconsistent dark-mode coverage = washed-out badges in dark mode. **STATUS: BLOCKED — codemod across 30+ badge sites + StatusBadge component design; multi-component, defer to design-system sprint**
  <!-- meta: scope=web/pages; files=packages/web/src/pages/dashboard/DashboardPage.tsx:1338,1873,packages/web/src/pages/customers/CustomerListPage.tsx:464; fix=define-StatusBadge-component-with-tone=success|warning|danger|info+full-light/dark-token-pairs -->

- [~] WEB-FQ-017. **[LOW] Button-label conventions inconsistent — "Add" / "Add Customer" / "Create" / "New" coexist for the same intent across pages.** `CustomerListPage.tsx:577` Link label "Add Customer"; `tickets/TicketListPage.tsx:632` form button ">Add<"; many settings pages use `>Create<`; some `>New<`. Microcopy convention should pick one verb per CRUD slot ("Add X" for list-page CTAs, "Save changes" for edit, "Create X" only for wizards) and document it in a copywriting guide.
  PARTIAL FIXED-by-Fixer-C12 2026-04-25 — disambiguated the bare ">Add<" in `tickets/TicketListPage.tsx:632` (the row-level quicknote form) to ">Add note<" so it stops colliding with the page-level "Add Ticket" / "Add Customer" CTAs. Microcopy doc + codemod across `>Create<` / `>New<` callsites still TODO.
  <!-- meta: scope=web/pages; files=packages/web/src/pages/customers/CustomerListPage.tsx:577,packages/web/src/pages/tickets/TicketListPage.tsx:632,packages/web/src/pages/leads/LeadListPage.tsx; fix=author-button-microcopy-doc+codemod->Create<-instances-where-list-page-CTA -->

- [~] WEB-FQ-018 (partial — KpiCard tooltip). **[LOW] Icon size inconsistency within single rows.** Fixer-C4 2026-04-25 — bumped the `KpiCard` tooltip glyph in `dashboard/DashboardPage.tsx:164` from `h-3 w-3` (12px, illegible at retina) to `h-3.5 w-3.5` (14px) so it scans alongside the 12px caption without dwarfing it. Other callsites (:284 AlertTriangle, :355/431 ShoppingCart/Package, :587-588 outer/inner) still need a coordinated `IconSize` token sweep — entry rephrased to track only the remaining surfaces.
  <!-- meta: scope=web/pages; files=packages/web/src/pages/dashboard/DashboardPage.tsx:164,284,355,431,587,588; fix=adopt-Icon-size-token-(xs/sm/md/lg)+lint-rule-flag-mismatched-sizes-in-same-row -->

- [~] WEB-FQ-019. **[LOW] Form-error styling per-page — login uses field-error red-500 border (LoginPage `border-red-500`), CustomerCreatePage applies `border-red-500 dark:border-red-500`, others use external error toast only, others render `<p class="text-sm text-red-600 mt-1">`.** Fixer-C10 2026-04-25 — added shared `<FormError>` primitive at `packages/web/src/components/shared/FormError.tsx` with three variants (`field` = canonical `mt-1 text-sm text-red-600` helper line, `banner` = top-of-form alert with `AlertCircle` icon + bordered red-50/red-950 background, `hint` = compact xs text), AA-contrast `red-600` light / `red-400` dark, `role="alert"` + optional `id` for `aria-describedby` wiring per audit recommendation. New code and page-touch refactors should consume this primitive; existing 200+ inline red-500/red-600 callsites left in place (mass migration out of scope for this loop). Leaving `[~]` until a sweep migrates LoginPage / CustomerCreatePage / SignupPage as the high-traffic forms.
  <!-- meta: scope=web/pages; files=packages/web/src/components/shared/FormError.tsx,packages/web/src/pages/auth/LoginPage.tsx,packages/web/src/pages/customers/CustomerCreatePage.tsx:219,packages/web/src/pages/signup/SignupPage.tsx; fix=primitive-shipped-pending-callsite-migration -->



- [~] WEB-FQ-022. **[LOW] Sidebar / CommandPalette / SpotlightCoach use `uppercase tracking-wider` for section labels (10+ uses); page bodies never do — visual rhythm only on chrome, not content.** `Sidebar.tsx:285,401`, `CommandPalette.tsx:257,375`, `UpgradeModal.tsx:101,117`, `SpotlightCoach.tsx:177`, `ShortcutReferenceCard.tsx:105`, `QuickSmsModal.tsx:157`. Brand display style ("DISPATCH", "TICKETS") could carry to page section headers (e.g. dashboard "Needs Attention") for cohesion. Currently each page invents its own h2/h3 styling.
  PARTIAL FIXED-by-Fixer-C12 2026-04-25 — added canonical `.section-eyebrow` utility class in `globals.css` (uppercase + 0.05em tracking + 0.75rem + AA-contrast `surface-500/400` light/dark) so page-body section labels can match the chrome rhythm with a single class. New code should consume `.section-eyebrow`; codemod of existing inline `text-xs uppercase tracking-wider` callsites still TODO. Once Bebas Neue display font loads (per `project_brand_fonts`), swap font-medium → font-display inside the rule for full brand voice.
  <!-- meta: scope=web/components+pages; files=packages/web/src/styles/globals.css,packages/web/src/components/layout/Sidebar.tsx:285,401,packages/web/src/components/shared/CommandPalette.tsx:257,375; fix=define-`section-eyebrow`-utility-class-and-apply-to-dashboard+settings-section-headers-once-Bebas-display-font-loads -->



### Wave-Loop Finder-W run 2026-04-24 — vite config + heavy imports + lazy routes









- [~] WEB-FW-010 (partial — overrides scaffold + comment). **[LOW] `package.json` has zero `peerDependencies` declared but consumes `@bizarre-crm/shared` (`*`).** Fixer-C4 2026-04-25 — added a top-level `"//"` doc field to `packages/web/package.json` documenting (a) why the `*` workspace pin is correct for npm-workspaces (sibling resolution from disk regardless of range — relevant after `aeb77812` fix(management): replace `workspace:*` with `*` for npm-on-Windows) and (b) where to add an `"overrides": { "<dep>": "<safe-range>" }` block when a transitive CVE force-pin lands (e.g. `"semver": "^7.5.4"` for CVE-2022-25883). Empty `overrides` skipped because npm rejects `{ "_comment": "…" }` keys that don't reference real packages. pnpm migration still TODO.
  <!-- meta: scope=web/package.json; files=packages/web/package.json:14-30; fix=switch-pkg-manager-to-pnpm-workspaces+pin-shared-to-workspace:*+add-overrides-block-for-known-CVE-transitive-deps -->



### Wave-Loop Finder-X run 2026-04-24 — aria + form a11y deeper








- [!] WEB-FX-008. **[MED] PinModal is the only well-built modal — has `role="dialog"` + `aria-modal` + `aria-labelledby="pin-modal-title"` + close-button `aria-label="Close"`. Its pattern should be the shared `<Modal>` primitive everyone migrates to.** `components/shared/PinModal.tsx:133-146`. Currently each modal hand-rolls its own backdrop + close button, often forgetting all four ARIA hooks (see WEB-FX-003). **[AUTOLOOP-T0 BLOCKED: codemod of 46 bare overlays — too broad for single-tick fix.]**
  <!-- meta: scope=web/components; files=packages/web/src/components/shared/PinModal.tsx:133-146,packages/web/src/components/shared/ConfirmDialog.tsx; fix=extract-shared/Modal.tsx-from-PinModal-pattern+add-focus-trap+ESC+codemod-46-bare-overlays-to-use-it -->






### Wave-Loop Finder-V run 2026-04-24 — error swallow + console.log + native modals









- [~] WEB-FV-009 (partial — console upgrade only). **[LOW] `SpotlightCoach.tsx:372,412,420` use `console.warn(...)` for tutorial-handler failures.** Fixer-C4 2026-04-25 — upgraded all three callsites from `console.warn('SpotlightCoach: …', err)` to `console.error('[spotlight] <tag>', err)` (`tutorial-complete` for the two complete-handler callsites + `dismissAllTutorials` for the third) so dev-tools default error filter surfaces them and a future Sentry shim can split breadcrumbs by tag. Sentry/captureException wiring still TODO (no SDK initialized in `main.tsx` yet) — entry rephrased to track only the SDK piece.
  <!-- meta: scope=web/components/onboarding; files=packages/web/src/components/onboarding/SpotlightCoach.tsx:372,412,420; fix=add-Sentry.captureException-and-eslint-rule-no-console-warn-in-src -->


- [~] WEB-FV-011. **[LOW] Inconsistent silent-catch error commentary — 30+ callsites have varied comments (`/* ignore */`, `/* swallow */`, `/* non-fatal */`, `/* storage unavailable */`, `/* best-effort */`) but same "do nothing" semantic — no shared `safeStorage` / `safeRun` helper.** `stores/confirmStore.ts:35` `/* best-effort */`, `tutorialFlows.ts:226` `/* storage unavailable — still proceed */`, `PrintPreviewModal.tsx:38,45,48` no comment. Standardize on a single helper `safeRun(() => ..., { tags: { ... } })` that logs to Sentry as breadcrumb + returns gracefully — eliminates 30+ ad-hoc try/catch trees and gives consistent ops visibility. (Fixer-C11 2026-04-25: helper authored at `packages/web/src/utils/safeRun.ts` exporting `safeRun` + `safeRunAsync` with provider-agnostic Sentry breadcrumb fallback; codemod of the 30 bare-catch sites still pending — landing the helper first so future fixers can adopt without inventing yet another shape.)
  <!-- meta: scope=web/stores+components; files=packages/web/src/stores/confirmStore.ts:35,packages/web/src/components/onboarding/tutorialFlows.ts:226,230,247,packages/web/src/components/shared/PrintPreviewModal.tsx:38,45,48; fix=author-utils/safeRun.ts+codemod-30-bare-catch-blocks-to-use-it -->

### Wave-Loop Finder-AC run 2026-04-25 — animations + reduced-motion





- [!] WEB-FAC-005. **[MED] Tooltips implemented as native `title="..."` attributes on 168 elements — no delay-in/out, OS-rendered (breaks brand), flickers on rapid mouse movement across icon clusters.** `Header.tsx:284,294,313`, `Sidebar.tsx:352`, `ImpersonationBanner.tsx:86`, etc. Native title shows after ~700ms with no fade, dismisses on movement, ignores keyboard focus (a11y gap). Build a shared `<Tooltip>` with `delayShow={300}` `delayHide={150}` + 150ms fade-in/out, focus-visible support, motion-reduce fallback to instant show. Replace all 168 `title=` callsites via codemod. **[AUTOLOOP-T1 BLOCKED: 168-site native title→Tooltip codemod, too broad.]**
  <!-- meta: scope=web/components; files=packages/web/src/components/layout/Header.tsx:284,294,313,packages/web/src/components/layout/Sidebar.tsx:352,packages/web/src/components/ImpersonationBanner.tsx:86; fix=author-shared/Tooltip.tsx+@radix-ui/react-tooltip+delay-300/150+motion-reduce:transition-none+codemod-title-attr -->

- [!] WEB-FAC-006. **[MED] No page-route transitions — `<Routes>` in `App.tsx:351,369` swap routes synchronously with zero crossfade, causing "white flash" between heavy pages (Dashboard -> CustomerList -> TicketDetail).** React Router v6 unmounts old route immediately. Wrap `<Routes location={location} />` in `framer-motion AnimatePresence` keyed on `location.pathname` with 150ms fade or short slide. Critical when Suspense fallback (Skeleton) chains multiple paint phases — currently looks broken instead of intentional. **STATUS: BLOCKED — needs new framer-motion dependency + AnimatePresence wiring across all routes; defer to motion sprint**
  <!-- meta: scope=web/App; files=packages/web/src/App.tsx:351,369; fix=AnimatePresence+motion.div-key=pathname+150ms-fade+motion-reduce:duration-0 -->





### Wave-Loop Finder-AD run 2026-04-25 — refetch storms + WS backoff







## Web UI/UX Audit (WEB-UIUX) — 2026-05-04

- [!] WEB-UIUX-1. **[MAJOR] Zero adoption of canonical `<Button>` component.** BLOCKED 2026-05-07 — valid design-system debt, but a 1240-site app-wide button migration is not a safe TODO item. It needs staged per-surface migration with visual regression checks because buttons carry different form submit, icon-only, destructive, disabled-tooltip, and responsive behaviors.
  <!-- meta: scope=web/all; files=all pages; fix=incremental-migration-to-Button-component -->

- [!] WEB-UIUX-2. **[MAJOR] Zero semantic color token adoption.** BLOCKED 2026-05-07 — valid systemic theming debt, but this is a full color-system migration across hundreds of status, warning, destructive, chart, and brand uses. A mechanical swap would erase intent; it needs token taxonomy and staged per-domain adoption.
  <!-- meta: scope=web/all; files=tailwind.config.ts:95-146 defines tokens; 0 callsites -->

- [!] WEB-UIUX-3. **[MAJOR] 67 `bg-white` without `dark:` partner.** BLOCKED 2026-05-07 — valid, but still an app-wide 30+ file dark-mode audit after several scoped fixes. Blindly appending `dark:bg-*` can break cards, print surfaces, public pages, and modal layering; remaining instances need per-surface visual review.
  <!-- meta: scope=web/all; fix=add-dark:bg-surface-800-or-dark:bg-surface-900 -->

- [!] WEB-UIUX-4. **[MAJOR] 109+ icon-only buttons missing `aria-label`.** BLOCKED 2026-05-07 — valid accessibility debt, but too broad for one TODO closure. Correct names depend on nearby entity/action context ("delete photo" vs "close modal" vs "print invoice"), so this needs a focused audit/codemod with per-callsite labels.
  <!-- meta: scope=web/all; fix=add-aria-label-to-icon-only-buttons -->

  <!-- meta: scope=web/all; files=components/shared/EmptyState.tsx; fix=migrate-existing-empty-states -->

- [!] WEB-UIUX-6. **[MINOR] 54 raw `teal-*` color references without semantic alias.** BLOCKED 2026-05-07 — valid brand-token debt, but the remaining teal uses mix legacy brand accent, success-ish status, POS action, and selected-state meanings. Needs semantic-token naming first, not a blind grep replace.
  <!-- meta: scope=web/all; fix=define-semantic-alias-or-migrate-to-primary -->

- [!] WEB-UIUX-8. **[MINOR] Shared `<Skeleton>` component has only 2 imports.** BLOCKED 2026-05-07 — valid design-system debt, but replacing dozens of page-specific skeletons requires preserving layout dimensions per page to avoid loading-state shift. Not safe as a single checklist item.
  <!-- meta: scope=web/all; files=components/shared/Skeleton.tsx; fix=migrate-loading-states -->

  <!-- meta: scope=web/all; fix=extract-useEscClose-hook-or-Modal-wrapper -->

- [!] WEB-UIUX-10. **[MINOR] `disabled:pointer-events-none` on buttons prevents tooltip display.** BLOCKED 2026-05-07 — valid pattern issue, but fixing it correctly needs tooltip wrappers/reasons at disabled callsites, not just removing a class. Broad button-state migration should handle this with per-control disabled reasons.
  <!-- meta: scope=web/all; fix=remove-pointer-events-none-keep-cursor-not-allowed -->

  <!-- meta: scope=web/all; fix=replace-with-formatDate-formatDateTime -->

- [!] WEB-UIUX-28. **[NIT] globals.css `.btn-*` class system duplicates the React `<Button>` component.** BLOCKED 2026-05-07 — true, but removing/deprecating these classes before the 1000+ raw/button-class migration would break existing screens. Track with WEB-UIUX-1 and retire after adoption, not before.
  `packages/web/src/styles/globals.css:272-331`
  <!-- meta: fix=deprecate-btn-classes-after-Button-migration -->

### Tier 1: Dashboard + POS

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:587,621,624,642...`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:441,446,451,455,473,623,661,667`
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:340,345`
  <!-- meta: fix=replace-dollar-literals-with-formatCurrency -->

  `packages/web/src/pages/dashboard/DashboardPage.tsx:1288`
  <!-- meta: fix=add-focus-trap -->

  `packages/web/src/pages/dashboard/DashboardPage.tsx:903,941,972`
  <!-- meta: fix=convert-to-button-or-add-role-tabindex-keydown -->

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:592,743,938`
  <!-- meta: fix=use-uncontrolled-input-with-onBlur-commit-pattern -->

  `packages/web/src/pages/unified-pos/BottomActions.tsx:457-488`
  <!-- meta: fix=swap-visual-hierarchy-checkout=primary -->

  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:707`, `BottomActions.tsx:459`
  <!-- meta: fix=migrate-to-primary -->

  `packages/web/src/pages/unified-pos/BottomActions.tsx:425,438,457,482`
  <!-- meta: fix=add-focus-visible:ring-2 -->

  `packages/web/src/pages/unified-pos/BottomActions.tsx:58-114`
  <!-- meta: fix=add-focus-trap -->

  `packages/web/src/pages/dashboard/DashboardPage.tsx:182-184`
  <!-- meta: fix=use-Link-or-a-element -->

  `packages/web/src/pages/dashboard/DashboardPage.tsx:1631`
  <!-- meta: fix=convert-to-button-or-link -->

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:921-979`
  <!-- meta: fix=add-onKeyDown-Enter-handler -->

- [!] WEB-UIUX-44. **[MINOR] DashboardPage fires 12 queries simultaneously on mount (AdminOrManagerDashboard).** Jitter only affects refetch, not initial load. Consider staggering or using Suspense boundaries. L15. **BLOCKED 2026-05-10: staggering needs careful per-widget priority + Suspense boundary placement; risks data races with manager-only widgets. Defer to perf sprint.**
  `packages/web/src/pages/dashboard/DashboardPage.tsx:1830-1914`
  <!-- meta: fix=stagger-initial-queries-or-add-suspense -->

  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:157-158`
  <!-- meta: fix=clearTimeout-in-cleanup -->

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:1057`

  `packages/web/src/pages/unified-pos/BottomActions.tsx:299-300`

### Tier 1: Tickets + Customers

  `packages/web/src/pages/tickets/TicketDevices.tsx:822-828,926-930`
  <!-- meta: fix=replace-with-InlinePriceEditor-component -->

  `packages/web/src/pages/tickets/TicketListPage.tsx:560-578`
  <!-- meta: fix=use-click-toggled-dropdown -->

  `packages/web/src/pages/tickets/KanbanBoard.tsx`
  <!-- meta: fix=add-dnd-kit-or-tap-to-move-fallback -->

  `packages/web/src/pages/tickets/TicketListPage.tsx:95-156,201`
  <!-- meta: fix=add-keyboard-nav-and-aria -->

  `packages/web/src/pages/tickets/TicketDevices.tsx:558-563,579,609,986-1012`
  <!-- meta: fix=add-focus-visible:opacity-100 -->

  `packages/web/src/pages/tickets/TicketDevices.tsx:1070-1072`
  <!-- meta: fix=make-visible-or-add-long-press-affordance -->

  `packages/web/src/pages/tickets/TicketSidebar.tsx:544`
  <!-- meta: fix=use-warranty-activation-or-completion-date -->

  `packages/web/src/pages/customers/CustomerCreatePage.tsx`
  <!-- meta: fix=add-beforeunload-or-confirm-on-navigate -->

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:398-438`
  <!-- meta: fix=collapse-infrequent-actions-into-More-dropdown -->

  `packages/web/src/pages/tickets/TicketListPage.tsx:1898`
  <!-- meta: fix=update-message-to-mention-undo-window -->

  `packages/web/src/pages/tickets/KanbanBoard.tsx:264-269`
  <!-- meta: fix=add-skeleton-columns -->

  `packages/web/src/pages/tickets/TicketListPage.tsx:636-664`
  <!-- meta: fix=add-aria-label -->

  `packages/web/src/pages/tickets/TicketNotes.tsx:282-287`
  <!-- meta: fix=add-aria-label -->

  `packages/web/src/pages/tickets/TicketSidebar.tsx:571-608`
  <!-- meta: fix=add-Escape-handler -->

  `packages/web/src/pages/customers/CustomerCreatePage.tsx:550`
  <!-- meta: fix=fallback-to-navigate('/customers') -->

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:303-305`
  <!-- meta: fix=render-Breadcrumb-outside-loading-guard -->

### Tier 1: Invoices + Inventory + Comms + CashRegister

### Tier 2: Leads + Estimates + Reports

  <!-- meta: fix=add-Edit-and-Cancel-buttons -->

- [!] WEB-UIUX-160. **[MINOR] Settings settings tabs use 4 different sub-tab visual languages.** RepairPricing solid pills, TicketsRepairs primary-100, ReceiptSettings bordered group, NotificationTemplates surface-100 pills. L4. **BLOCKED 2026-05-10: 4-tab visual unification requires design-token choice; defer to design-system sprint.**
  <!-- meta: fix=extract-Tabs-primitive -->

  `packages/web/src/pages/settings/DeviceTemplatesPage.tsx:109-117`

  `packages/web/src/pages/settings/RepairPricingTab.tsx:339-365, 385-413`

  `packages/web/src/pages/settings/MembershipSettings.tsx:130-137`
  <!-- meta: fix=compute-luminance-pick-text-color -->

  `packages/web/src/pages/settings/AutomationsTab.tsx:770-776`

  `packages/web/src/pages/settings/DangerZoneTab.tsx:484-495`

  `packages/web/src/pages/settings/DangerZoneTab.tsx:344-398`

  `packages/web/src/pages/settings/ConditionsTab.tsx:284`

  `packages/web/src/pages/settings/DangerZoneTab.tsx:73`

  `packages/web/src/pages/settings/AutomationsTab.tsx:633`

  `packages/web/src/pages/settings/AutomationDetailPage.tsx:207-223`

#### Super-Admin / Marketing / Billing

  `packages/web/src/pages/super-admin/TenantsListPage.tsx:401-405,325-326`

  `packages/web/src/pages/billing/CustomerPayPage.tsx:131-187`
  <!-- meta: fix=server-expose-tenant_name-tenant_logo-render-prominent -->

  `packages/web/src/pages/billing/AgingReportPage.tsx:154`

  `packages/web/src/pages/marketing/CampaignsPage.tsx:268-342`
  <!-- meta: fix=primary-CTA-plus-overflow-MenuButton -->

  `packages/web/src/pages/billing/PaymentLinksPage.tsx:309-318`

  `packages/web/src/pages/super-admin/TenantsListPage.tsx:517-542`

  `packages/web/src/pages/marketing/NpsTrendPage.tsx:115-146`

  `packages/web/src/pages/billing/DunningPage.tsx:235-270`

  `packages/web/src/pages/employees/EmployeeListPage.tsx:614-617`

  `packages/web/src/pages/billing/PaymentLinksPage.tsx:208-227`

  `packages/web/src/pages/billing/DepositCollectModal.tsx:52-61`
  <!-- meta: fix=multiply-to-int-cents-on-client -->

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:90-96`
  <!-- meta: fix=cap-at-5k-second-step-confirm-over-500 -->

  `packages/web/src/pages/billing/CustomerPayPage.tsx:89-96`

  `packages/web/src/pages/billing/CustomerPayPage.tsx:164`

  <!-- meta: fix=PageContainer-with-narrow-default-wide -->

- [!] WEB-UIUX-195. **[MINOR] Heading size inconsistency: text-xl vs text-2xl, font-bold vs font-semibold across pages.** L2. **BLOCKED 2026-05-10: app-wide heading codemod, needs typography-scale decision first. Defer.**
  Three weight+size combinations for same element role.

#### WCAG 2.2 + Online Research

  Pattern across: `pages/customers/CustomerListPage.tsx:731`, `pages/invoices/InvoiceListPage.tsx:435`, `pages/tickets/TicketListPage.tsx:1707`, `pages/dashboard/DashboardPage.tsx:1165,1726,2260`
  <!-- meta: fix=scrollMarginTop-on-focusable-rows-or-overflow-anchor -->

  `packages/web/src/pages/unified-pos/ZReportModal.tsx:120` (p-1 close button)
  Audit needed: `grep -rn 'className=".*p-1[^0-9]' --include="*.tsx" | grep "<button"`
  <!-- meta: fix=normalize-icon-button-padding-to-p-1.5-min -->

  `packages/web/src/pages/setup/SetupPage.tsx`
  <!-- meta: fix=audit-step-flow-pre-fill-from-prior-steps -->

  `packages/web/src/pages/billing/CustomerPayPage.tsx:194`
  <!-- meta: fix=use-surface-950-token-not-gray-900 -->

  All `animate-pulse` / `animate-spin` callsites.
  <!-- meta: fix=add-motion-reduce:animate-none-globally-via-Skeleton-component -->

  `packages/web/src/pages/unified-pos/`
  <!-- meta: fix=role-based-action-visibility -->

  `packages/web/src/pages/auth/LoginPage.tsx:766` ✓ `autoComplete="current-password"` confirmed; no onPaste handler present. WCAG 3.3.8 requirement fully satisfied; no code change required. Audit-verified-clean 2026-05-06.
  <!-- meta: status=audit-verified-clean -->

  `packages/web/src/stores/uiStore.ts`, `packages/web/index.html` (verified)
  <!-- meta: fix=ensure-dark-class-on-html-element -->

  `packages/web/src/pages/unified-pos/ProductsTab.tsx:163-175`
  <!-- meta: fix=normalize-POS-tap-targets-to-44px-min -->

#### Recommended Sequencing — Pass 2 Additions

**Phase 1 — Pass-2 blockers:**
WEB-UIUX-143 + 144 (settings clobber bugs), WEB-UIUX-145 (voice settings no save UI)

**Phase 2 — Trust + safety:**
WEB-UIUX-172-173 (CustomerPayPage merchant identity + button color)

**Phase 3 — A11y (WCAG 2.2):**
WEB-UIUX-149 (settings focus traps), WEB-UIUX-182-183 (chart + select labels),
WEB-UIUX-185 (row keydown), WEB-UIUX-196-200 (sticky obscure, target size, autocomplete, consistent help, redundant entry)

**Phase 4 — Component extraction:**
WEB-UIUX-151 (Switch component), WEB-UIUX-160 (Tabs primitive),
extracted Modal shell (cross-cutting)


### Web UI/UX Audit — Pass 3 (2026-05-05, brand+forms+toast research)

#### Brand & Identity

  `packages/web/index.html:64`
  `packages/web/tailwind.config.ts:157`
  <!-- meta: fix=add-Bebas+Neue-to-Google-Fonts-preload-or-self-host -->

  Recommendation: audit `grep -rn "<h[12]" --include="*.tsx"` and add `font-display` where appropriate.
  <!-- meta: fix=apply-font-display-class-to-h1-h2-page-titles -->

  `packages/web/index.html:64`
  <!-- meta: fix=remove-Inter-LeagueSpartan-Roboto-from-preload -->

  `packages/web/src/components/shared/SignatureCanvas.tsx:109,209`
  <!-- meta: fix=use-Jost-or-Futura-font-stack -->

  `packages/web/index.html:36`
  <!-- meta: fix=use-react-helmet-or-useEffect-to-set-document.title -->

  `packages/web/index.html:2`

#### Form Accessibility (WebAIM 2026 research: 33% of inputs unlabeled)

- [!] WEB-UIUX-214. **[MAJOR] 381 placeholder usages vs 107 `htmlFor=` pairs across all .tsx files.** BLOCKED 2026-05-07 — valid accessibility debt, but the current count spans 100+ files. Correct fixes require visible labels where layout allows, `aria-label` only for compact controls, and error/help linking; a blind placeholder codemod would create noisy or wrong labels.
  Pattern across many files. Audit needed: `grep -L 'htmlFor' files-with-input.tsx`
  <!-- meta: fix=add-explicit-label-or-aria-label-to-placeholder-only-inputs -->

- [!] WEB-UIUX-215. **[MAJOR] Only 38 `aria-invalid` callsites for ~750 toast.error firings.** BLOCKED 2026-05-07 — valid, but mapping toast errors back to fields requires per-form validation state and server error shape parsing. This cannot be solved safely by a global toast wrapper.
  <!-- meta: fix=mirror-toast.error-to-setError(field)+aria-invalid=true -->

  <!-- meta: fix=add-aria-describedby+id-pattern-to-FormError-component -->

  `packages/web/src/pages/customers/CustomerCreatePage.tsx:283` (and many others)
  <!-- meta: fix=verify-input-class-or-migrate-to-explicit-classes -->


#### Toast UX (LogRocket/Carbon/research)

  `packages/web/src/main.tsx:410-411`
  <!-- meta: fix=raise-default-to-5000-success-to-4000 -->

  `packages/web/src/main.tsx:404-415`

  `packages/web/src/pages/loaners/LoanersPage.tsx`

  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:365,397`
  <!-- meta: fix=render-inline-failure-state-in-modal -->

  `packages/web/src/main.tsx:13-82,315-317`
  <!-- meta: fix=deduplicate-by-id-instead-of-cap+drop -->

#### Loading & Feedback States



### Web UI/UX Audit — Pass 4 (2026-05-05, setup wizard + onboarding + components)

Setup wizard, onboarding, print, TV, photo-capture, reports sub-components, tickets components, team components.

#### Blockers/Trust

  `packages/web/src/pages/setup/steps/StepCashDrawer.tsx:84-88`

  `packages/web/src/pages/setup/steps/StepReview.tsx:115-122`
  <!-- meta: fix=iterate-by-key-not-label -->

  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:367-481`

  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:199-206`

  `packages/web/src/components/team/CommissionPeriodLock.tsx:158-175`
  <!-- meta: fix=two-step-or-modal-confirm -->

  `packages/web/src/components/tickets/QcSignOffModal.tsx:184-187`
  <!-- meta: fix=confirm-discard-if-touched -->

  `packages/web/src/components/tickets/QcSignOffModal.tsx:291-326,434-527`
  <!-- meta: fix=add-Failed-state-and-Reject-CTA -->

#### Setup Wizard A11y / Components

  `packages/web/src/pages/setup/SetupPage.tsx:362-373`

  `packages/web/src/pages/setup/components/WizardBreadcrumb.tsx:67-103`

  `packages/web/src/pages/setup/SkipToDashboard.tsx:21-46`

  `packages/web/src/pages/setup/steps/StepWelcome.tsx:48-59`

  `packages/web/src/pages/setup/steps/StepStoreInfo.tsx:36-53`

- [!] WEB-UIUX-301. **[MINOR] 237 `Loader2 animate-spin` callsites — most duplicate centered-loading pattern.** BLOCKED 2026-05-07 — critique: valid but too broad for a safe single tick. A real fix needs a shared loading/skeleton API plus gradual per-surface adoption so buttons, inline spinners, table skeletons, full-page loaders, and modal loaders do not all get flattened into one inappropriate component.
  <!-- meta: fix=extract-LoadingSpinner-component-or-Skeleton-defaults -->

  <!-- meta: fix=use-logger-with-environment-gate -->

- [!] WEB-UIUX-303. **[MAJOR] No layered error-boundary strategy per research best practice (2026).** BLOCKED 2026-05-07 — directionally valid, but layered boundaries need route/widget ownership decisions and fallback content per surface. A generic wrapper around every widget risks hiding failures and swallowing telemetry context.
  <!-- meta: fix=add-PageErrorBoundary-+-WidgetErrorBoundary-with-retry -->


#### Responsive Modern Techniques

  Pattern across web/src
  <!-- meta: fix=adopt-container-queries-for-widgets-that-render-in-multiple-contexts -->
  <!-- BLOCKED: requires-component-by-component-design-work -->

  `packages/web/src/pages/landing/LandingPage.tsx:374,377,399,429,458` (only file)

- [!] WEB-UIUX-306. **[MAJOR] Zero swipe gesture handlers across web app.** BLOCKED 2026-05-07 — critique: directionally valid, but unsafe as a blanket TODO. Ticket, customer, and invoice rows have different destructive/primary actions and accessibility requirements; adding swipe gestures app-wide needs per-list interaction design, undo/confirmation policy, and pointer/keyboard parity.
  <!-- meta: fix=add-swipe-handlers-on-list-rows-for-archive-quick-actions -->

- [!] WEB-UIUX-307. **[MINOR] Only 4 `xl:` callsites vs 100 `sm:`, 97 `md:`, 50 `lg:`.** Large desktop (1280px+) under-optimized. CRM dashboards on widescreen don't take advantage of horizontal space. L11. **[AUTOLOOP-T12 BLOCKED: xl: optimization requires per-page layout decisions across 30+ page dirs.]** Reconfirmed 2026-05-07: this is a page-by-page design sweep, not a safe global mechanical edit.
  <!-- meta: fix=audit-1280px-layouts-add-xl:-grid-cols-4-or-side-panels -->


### Web UI/UX Audit — Pass 6 (2026-05-05, hooks + utils + stores + api)

#### Trust + Security UX

- [!] WEB-UIUX-308. **[MAJOR] `accessToken` stored in `localStorage` — XSS exposes bearer.** BLOCKED 2026-05-07 — valid security architecture issue, but migration to in-memory access tokens plus httpOnly refresh cookies spans server auth routes, CSRF policy, refresh rotation, API client bootstrapping, logout, super-admin, Android/web parity, and deployment config.
  `packages/web/src/stores/authStore.ts:95-171`, `packages/web/src/api/client.ts:180`
  <!-- meta: fix=migrate-to-in-memory-token+httpOnly-refresh -->

- [!] WEB-UIUX-309. **[MAJOR] `useDraft` stores PII (customer notes/IMEIs/addresses) plaintext in localStorage.** Per-user namespace prevents cross-user bleed but value is plaintext. L16. **BLOCKED 2026-05-10: encrypting localStorage drafts needs per-user key derivation + storage migration + acceptance of key-loss = lost draft. Multi-component design.**
  `packages/web/src/hooks/useDraft.ts:201`
  <!-- meta: fix=AES-encrypt-with-per-session-key -->

  `packages/web/src/api/client.ts:450-494`

  `packages/web/src/utils/apiError.ts:96-103`
  <!-- meta: fix=add-formatApiErrorPublic-variant-with-auto-redact -->

  `packages/web/src/utils/apiError.ts:50,99`

  `packages/web/src/stores/authStore.ts:139-144`

#### Loading + Cache + Stale Data

  `packages/web/src/hooks/useSettings.ts:41`
  <!-- meta: fix=invalidate-on-settings-mutation -->

  `packages/web/src/hooks/useDefaultTaxRate.ts:29-35`
  <!-- meta: fix=expose-isError-flag-render-banner -->

  `packages/web/src/utils/format.ts:55-57`
  <!-- meta: fix=add-nullDisplay-param-default-emdash -->

  `packages/web/src/hooks/useWebSocket.ts:533-587`
  <!-- meta: fix=add-window-online-event-listener -->

  `packages/web/src/hooks/useDraft.ts:194-198`
  <!-- meta: fix=expose-isDraftTooLarge-flag-warn-user -->

#### Forms + Feedback

  `packages/web/src/hooks/useUndoableAction.tsx:217-242`
  <!-- meta: fix=toast-on-nav-Action-committed -->

  `packages/web/src/api/client.ts:364-370`
  <!-- meta: fix=use-formatApiError(error)-include-requestId -->

  `packages/web/src/hooks/useUndoableAction.tsx:129-158`

  `packages/web/src/utils/format.ts:184-188`
  `packages/web/src/utils/phoneFormat.ts:1-9`

  `packages/web/src/utils/format.ts:202-208`

  `packages/web/src/api/client.ts:382-394`
  <!-- meta: fix=dedupe-per-URL-not-global -->

  `packages/web/src/hooks/useUndoableAction.tsx:129-158`

  `packages/web/src/hooks/useWebSocket.ts:533-538`

#### Dark-Mode + Theme

  `packages/web/src/stores/uiStore.ts:59-62`
  Note: index.html:66-89 already has fallback script — verify it covers all paths

  `packages/web/src/stores/uiStore.ts:36-57`
  <!-- meta: fix=scope-transition-to-color-bg-only -->

  `packages/web/src/utils/safeColor.ts:16`

  `packages/web/src/stores/uiStore.ts:38-57`

#### Copy + Confirms

  `packages/web/src/stores/confirmStore.ts:13,27,62`

  `packages/web/src/stores/authStore.ts:300-302`

  `packages/web/src/hooks/useUndoableAction.tsx:127`

  `packages/web/src/api/client.ts:369`

  `packages/web/src/stores/confirmStore.ts:11-21`

#### Components / Duplicates

  <!-- meta: fix=consolidate-into-utils/jwt.ts -->

  `packages/web/src/api/endpoints.ts:278-283,287-292,712-722,740-748,753-761,1177-1180`

  `packages/web/src/hooks/useUndoableAction.tsx:131-156`

#### Performance

  `packages/web/src/utils/format.ts:46-66`
  <!-- meta: fix=memoize-by-code+locale-key -->

  `packages/web/src/hooks/useDraft.ts:17-31`, `packages/web/src/stores/authStore.ts:13-16,194-219`

  `packages/web/src/utils/format.ts:60-66`
  <!-- meta: fix=rate-limit-or-single-warning -->

  `packages/web/src/hooks/useWebSocket.ts:420-440`

  `packages/web/src/hooks/useWebSocket.ts:82-254,442`

  `packages/web/src/hooks/useDismissible.ts:35-72`

#### A11y + Misc

  `packages/web/src/utils/apiError.ts:96-103`


### Web UI/UX Audit — Pass 7 (2026-05-05, portal + voice + communications + billing components)

#### Portal — Customer-Facing

  `packages/web/src/pages/portal/components/LanguageSwitcher.tsx:27-29`
  <!-- meta: fix=use-document.documentElement.classList.toggle -->

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:386-390`
  <!-- meta: fix=compute-luminance-pick-text-color -->

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:320-322`

  `packages/web/src/pages/portal/components/LanguageSwitcher.tsx:116-166`

  `packages/web/src/pages/portal/components/PhotoGallery.tsx:128-148`

  `packages/web/src/pages/portal/components/StatusTimeline.tsx:59,69-91`

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:519-528`

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:73,88,93`
  <!-- meta: fix=use-server-supplied-correlation-id -->

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:269-294`

  `packages/web/src/pages/portal/components/FaqTooltip.tsx:20-29`
  <!-- meta: fix=add-focusin-document-listener -->

  `packages/web/src/pages/portal/components/FaqTooltip.tsx:50`

  `packages/web/src/pages/portal/components/PhotoGallery.tsx:138`
  <!-- meta: fix=encode-before-after+order+date-in-alt -->

  `packages/web/src/pages/portal/components/QueuePosition.tsx:22-26,71`

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:393-407`

  `packages/web/src/pages/portal/CustomerPortalPage.tsx:133-142,260-267`

  `packages/web/src/pages/portal/components/LanguageSwitcher.tsx:5-7,23-25`

#### Communications Components

  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx:104-123`

  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:142-164`

  `packages/web/src/pages/communications/components/ConversationAssignee.tsx:33-39`
  <!-- meta: fix=add-/inbox/conversation/:phone-or-prop-drill-list -->

  `packages/web/src/pages/communications/components/ConversationTags.tsx:34-40`

  `packages/web/src/pages/communications/components/SentimentBadge.tsx:22-27,61`
  <!-- meta: fix=use-actual-emoji-glyphs-or-remove-prefix-span -->

  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx:66-85`

  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:117,121`

  `packages/web/src/pages/communications/components/ConversationTags.tsx:124`

  `packages/web/src/pages/communications/components/FailedSendRetryList.tsx:94`

  `packages/web/src/pages/communications/components/FailedSendRetryList.tsx:109-111`

  `packages/web/src/pages/communications/components/OffHoursAutoReplyToggle.tsx:74-78`
  <!-- meta: fix=optimistic-update-with-onMutate-rollback-onError -->

  `packages/web/src/pages/communications/components/QuickSmsAttachmentButton.tsx:76-79,61`

  `packages/web/src/pages/communications/components/TeamInboxHeader.tsx:106-113`

  `packages/web/src/pages/communications/components/TemplateAnalyticsCard.tsx:67-105`

  `packages/web/src/pages/communications/components/ConversationAssignee.tsx:99-138`

#### Voice

  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:23-72`

- [!] WEB-UIUX-416. **[MINOR] Toast strings English-only across staff surfaces.** Portal has i18n; Communications/Billing/Super-admin don't translate. L14. **BLOCKED 2026-05-07: valid product gap, but not a safe single TODO patch. Staff-surface i18n requires adopting a staff i18n runtime, key namespaces, extraction policy, and hundreds of string migrations across Communications/Billing/Super-admin/Team/Tickets/Print/TV; small piecemeal translation would create mixed-language UX and false completion.**


  <!-- meta: fix=introduce-text-on-primary-semantic-token -->


  `packages/web/src/pages/portal/i18n.ts:152-154`

  `packages/web/src/pages/portal/i18n.ts:53,121`


#### Cross-Cutting (table a11y)

- [!] WEB-UIUX-434. **[MAJOR usability pattern] Many destructive flows label by ENGINEERING action, not USER intent.** "Void" = engineering noun. "Credit Note" = accounting noun. Users think in verbs: refund, cancel, undo. Audit all action labels for engineering-vs-user-intent mismatch. L14. **PARTIAL/BROAD 2026-05-07: valid pattern, but the requested audit spans destructive flows across invoices/POS/settings/imports. Scoped remaining invoice detail label changed from user-visible "Void" to "Cancel invoice" with cancel-oriented confirmation/toast copy while preserving the existing void API/status contract. Full product-copy audit remains open/broad.**
  Audit needed: search for buttons named: Void, Reverse, Reconcile, Reissue, Mutate, etc.

  Cross-cutting modal pattern. PARTIAL FIX: credit-note modal now shows dynamic outcome preview keyed to entered amount + payment method/detail. Note: last4 not stored in schema — "Visa ending 1234" precision requires schema change (tracked separately). WEB-UIUX-431 (post-success confirmation) is distinct and still open.


### Web UI/UX Audit — Pass 8 (2026-05-05, shared/layout/tickets/tv/print/team)

#### Shared Modal Primitives

  <!-- meta: fix=extract-Modal-with-portal+focus-trap+scroll-lock+restore-focus -->

  `packages/web/src/components/shared/CommandPalette.tsx:325-342,444-453`

- [!] WEB-UIUX-512. **[MAJOR] PhotoCapturePage strings English-only ("Take Photo", "Add more").** Customer-facing. L14. **CLOSED/BLOCKED 2026-05-07 — critique: valid but too broad for this scoped bundle. The live page has 20+ customer-facing strings across invalid/expired/success/upload/error states, toasts, status badges, controls, and instructions, and PhotoCapturePage does not currently import a local translator or share the portal i18n runtime. Implementing only two labels would leave mixed-language public UX; a dedicated PhotoCapture i18n pass should add the route-level string table first.**
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:185-256`

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:251-264`

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:45,65-68`
  <!-- meta: fix=add-canvas-downscale-before-upload -->

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:192-194`

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:154`

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:79-85`

#### Print Page

  `packages/web/src/pages/print/PrintPage.tsx:40-90`

  `packages/web/src/pages/print/PrintPage.tsx:204-441`

  `packages/web/src/pages/print/PrintPage.tsx:192,448`

  `packages/web/src/pages/print/PrintPage.tsx:165-185`

  `packages/web/src/pages/print/PrintPage.tsx:148-154`

  `packages/web/src/pages/print/PrintPage.tsx:204`

  `packages/web/src/pages/print/PrintPage.tsx:245-247`

  `packages/web/src/pages/print/PrintPage.tsx:250,515`

  `packages/web/src/pages/print/PrintPage.tsx:184`

  `packages/web/src/pages/print/PrintPage.tsx:102-113`
  <!-- meta: fix=allow-list-logo-host-or-relative-only -->

  `packages/web/src/pages/print/PrintPage.tsx:336-380`

#### Team Pages (TeamChat, ShiftSchedule, MyQueue, Payroll)

  `packages/web/src/pages/team/PayrollPage.tsx:1-10`

  `packages/web/src/pages/team/TeamChatPage.tsx:340-382`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:307-407`

  `packages/web/src/pages/team/TeamChatPage.tsx:287`

  `packages/web/src/pages/team/TeamChatPage.tsx:309-320,333-335`

- [!] WEB-UIUX-534. **[MAJOR] TeamChatPage 15 s polling with no WebSocket fallback — under poor network 1-min lag for new messages.** L15. **BLOCKED 2026-05-07: critique valid, but not a contained TeamChatPage-only fix. The server route explicitly documents "No WebSocket fan-out yet", `WS_EVENTS` has no team-chat event, and the shared web invalidation map cannot subscribe to messages the server never broadcasts. Keeping the bounded 15s visible-tab poll plus focus refetch is the safe fallback until a backend/shared-event contract is added.**
  `packages/web/src/pages/team/TeamChatPage.tsx:89-108`

  `packages/web/src/pages/team/TeamChatPage.tsx:129-131`
  <!-- meta: fix=detect-near-bottom-before-scroll -->

  `packages/web/src/pages/team/TeamChatPage.tsx:283-285`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:51-157`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:251-258`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:385-406`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:328-343,108-112`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:124,136,148`

  `packages/web/src/pages/team/MyQueuePage.tsx:34-48`

- [!] WEB-UIUX-545. **[MINOR] TeamChatPage channel list has no unread/badge indicator — operators must open each channel to spot new messages.** L8. **BLOCKED 2026-05-07: no existing TeamChat API/schema exposes per-channel unread counts or read receipts. `GET /team-chat/channels` returns only channel rows, `GET /channels/:id/messages` returns message rows, and `team_chat_channels`/`team_chat_messages` have no per-user read marker; `team_mentions.read_at` tracks only @mentions, not channel unread state.**
  `packages/web/src/pages/team/TeamChatPage.tsx:244-258`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:180-205`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:231`

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:268-303`

#### Gift Card Detail

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:41-44`
  <!-- meta: fix=server-canonicalize-cents-or-shared-amount-utility -->

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:233-244`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-294`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:90-95,127-131`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:63-69`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:304-329`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:178-186`

#### Cross-Cutting (Pass 8)


- [!] WEB-UIUX-566. **[MINOR] Rounded-corner inconsistency: `rounded-md`, `rounded-lg`, `rounded-xl`, `rounded-2xl` mixed within single page.** TicketDetailPage MergeDialog `rounded-xl`, FaqTooltip `rounded-md`, Pin `rounded-xl` but inputs `rounded-lg`. L11. **BLOCKED 2026-05-07: critique valid but too broad as written; this needs a per-surface radius pass or formal radius token adoption, not a blind repo-wide `rounded-*` codemod. No safe single shared-component change was identified beyond preserving existing `Button`/`Modal` radius defaults.**

  <!-- meta: fix=create-useEscapeStack+register-with-z-index-to-resolve-stacked-modals -->

- [!] WEB-UIUX-568. **[NIT] `disabled:pointer-events-none` cargo-culted alongside `disabled:opacity-50` on every button — disabled `<button>` already drops events; class is redundant.** L4. **PARTIAL/BLOCKED 2026-05-07: critique valid. The safe shared fix was to remove `pointer-events: none` from the global `.btn:disabled` rule so shared button classes no longer suppress tooltip/hover plumbing; removing every page-level `disabled:pointer-events-none` class is a broad codemod and remains inappropriate for this scoped bundle.**

### Web UI/UX Audit — Pass 9 (2026-05-05, shared components + inventory + gift-cards detail)

#### Blockers/Trust

  `packages/web/src/components/TrialBanner.tsx`
  <!-- meta: fix=delete-orphan-or-merge -->

  `packages/web/src/components/ImpersonationBanner.tsx:96-109`
  <!-- meta: fix=split-status-display-from-action-target-use-role=status+separate-button -->

- [!] WEB-UIUX-571. **[BLOCKER usability] InventoryListPage 1946 lines holds 7 inline modals + EmptyState + helpers.** No code splitting; every render parses 96kb of TSX. Maintenance + perf hit. L15. **BLOCKED 2026-05-07: critique valid, but a safe fix is a multi-file component split/lazy-load pass across the list table, 7 modals, scan receive flow, variance panel, import helpers, and empty states. Out of scope for this contained triage bundle; pairs with WEB-UIUX-598.**
  `packages/web/src/pages/inventory/InventoryListPage.tsx`
  <!-- meta: fix=split-into-VarianceModal+ReceiveModal+EmptyState+lazy-load-modals -->

#### Onboarding

  `packages/web/src/components/onboarding/SpotlightCoach.tsx:139,151-156`
  <!-- meta: fix=useLayoutEffect-measure-getBoundingClientRect -->

  `packages/web/src/components/onboarding/SpotlightCoach.tsx:107`

  `packages/web/src/components/onboarding/SpotlightCoach.tsx:234-241,408-410`
  <!-- meta: fix=rename-to-Next-or-Mark-as-done-different-color-from-Skip-tutorial -->

  `packages/web/src/components/onboarding/useMilestoneToasts.ts:13-17,107-123`

  `packages/web/src/components/onboarding/SpotlightCoach.tsx:33,322-345`
  <!-- meta: fix=use-MutationObserver-on-document.body -->

  `packages/web/src/components/onboarding/tutorialFlows.ts:189`

  `packages/web/src/components/onboarding/tutorialFlows.ts:223-239`

#### Shared Components

  Files: `components/shared/LoadingScreen.tsx:13-30,40-45,88-100`, `components/shared/PageErrorBoundary.tsx:142-160`, `components/ErrorBoundary.tsx:32-60`

  `packages/web/src/components/shared/OfflineBanner.tsx:45`
  <!-- meta: fix=z-[60]+ensure-banners-stack-above-modals -->

  `packages/web/src/components/shared/OfflineBanner.tsx:26-37`
  <!-- meta: fix=fire-toast.error-on-offline-toast.success-on-recovery -->

  `packages/web/src/components/shared/PageErrorBoundary.tsx:79-118`
  <!-- meta: fix=add-attempts-counter-bail-after-3 -->

  `components/ErrorBoundary.tsx:32-60` vs `components/shared/PageErrorBoundary.tsx:128-163`
  <!-- meta: fix=extract-ErrorFallback-shared -->

  `packages/web/src/components/shared/TrialBanner.tsx:55-72,84-105,108-127`

  `packages/web/src/components/ImpersonationBanner.tsx:101-106`

  `packages/web/src/components/shared/LoadingScreen.tsx:18`

  `packages/web/src/components/shared/LoadingScreen.tsx:80-85`

  `packages/web/src/components/shared/PermissionBoundary.tsx:13-25`

  `packages/web/src/components/shared/Timeline.tsx:28-34`

  <!-- meta: fix=define-banner-stack-impersonation-z-30-offline-z-25-trial-z-20 -->

#### Inventory Detail/Create

  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:346-382`

  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:127-131`

  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:144-159`
  <!-- meta: fix=if-printWindow-null-toast.error-allow-popups -->

  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:73`
  <!-- meta: fix=parseFloat>0-with-explicit-error -->

  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:70-86`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:330`
  <!-- meta: fix=use-pct<=-100-or-explicit-error-Use-Delete-instead -->

- [!] WEB-UIUX-598. **[MAJOR] InventoryListPage 7 inline modals reinvent backdrop+close boilerplate.** ~80 lines duplicated each. L3, L4. **BLOCKED 2026-05-07: critique valid, but replacing all inline modal shells with the canonical Modal primitive is the same broad InventoryListPage refactor as WEB-UIUX-571. This pass intentionally avoided a large modal churn while making the contained bulk-preview fix.**
  `packages/web/src/pages/inventory/InventoryListPage.tsx:947,1029,1109,1158,1244,1531,1750`
  <!-- meta: fix=extract-Modal-primitive-saves-~400-lines -->

  `packages/web/src/pages/inventory/InventoryListPage.tsx:1530-1690`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:425-470,492-502`

  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:195`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:712-720`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:998`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:1695-1708`

  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:402`

  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:76,116-122,188`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:66-67,170-174`

#### Gift Card Detail

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:237-243`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:235`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:304-328`

  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:159-167,199-211,301-302`


### Web UI/UX Audit — Edge-Case Pass A (2026-05-05, parallel agents)

#### ED1: Checkout → Mistake → Delete → Refund

  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:407-446`
  <!-- meta: fix=add-Issue-Refund-Cancel-sale-button-routes-to-credit-note-modal -->

  `packages/web/src/pages/tickets/TicketDetailPage.tsx:627-637,321-336`
  <!-- meta: fix=pre-compute-paidAmount+invoice.status-pass-server-403-verbatim -->

  `packages/web/src/pages/tickets/TicketDetailPage.tsx:503,TicketActions.tsx:171-174`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:807-817`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:416-420,687-698,839-845`

  `packages/web/src/pages/tickets/TicketDetailPage.tsx:630`

  `packages/web/src/pages/tickets/TicketDetailPage.tsx:633-634`

  `packages/web/src/pages/tickets/TicketDetailPage.tsx:327`

- [!] WEB-UIUX-621. **[MAJOR] No combined "Cancel Sale" wizard.** 4-step manual sequence: refund → navigate → delete → confirm. Each abandonable mid-flow → inconsistent intermediate state. L8, L4. **BLOCKED 2026-05-07: valid product gap, but this is a new multi-step cross-route wizard spanning POS success, invoice credit/void, and ticket delete. No nearby Cancel Sale flow exists in TicketList/TicketDetail/InvoiceDetail, so it is out of this narrow bundle.**

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:763-778`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-175`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:485,488`

#### ED2: Split-Tender Partial Refund

- [!] WEB-UIUX-627. **[BLOCKER] Credit-note never inserts payment-out row, never decrements gift-card balance, never calls BlockChyp reverse.** BLOCKED 2026-05-07 — still valid for the wired invoice path. `/invoices/:id/credit-note` creates a negative invoice, updates the original invoice balance, and writes overflow to `store_credits`; it never writes a negative `payments` row, never writes `cash_register`, never touches `gift_cards`, and never calls `processRefund()`. Important nuance: the separate `/api/v1/refunds/:id/approve` path now can call BlockChyp/Stripe processor refunds, but InvoiceDetailPage does not use it. L8, L13, L16.
  `packages/server/src/routes/invoices.routes.ts:1213-1257`

  `packages/server/src/routes/blockchyp.routes.ts`

  `packages/server/src/routes/blockchyp.routes.ts:482-543`

- [!] WEB-UIUX-630. **[BLOCKER] Web frontend never calls `giftCardApi.redeem` — gift cards cannot be used at POS checkout.** BLOCKED 2026-05-07 — valid. `giftCardApi.redeem` and server `POST /gift-cards/:id/redeem` exist, but Unified POS `PaymentMethod` is still only `'Cash' | 'Card' | 'Other'`, `PAYMENT_METHODS` renders only those three, and checkout payloads never carry a gift-card id/code. Needs lookup-by-code/card selector, split tender integration, redeem call/idempotency, and receipt/refund semantics. L1, L5.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:23-27`

- [!] WEB-UIUX-631. **[MAJOR] Cash refund never inserts `cash_register cash_out` event.** BLOCKED 2026-05-07 — valid. `POST /pos/cash-out` writes drawer events, but neither `/invoices/:id/credit-note` nor `/api/v1/refunds/:id/approve` inserts a `cash_register(type='cash_out')` row for `method='cash'`; approve only marks the refund completed and decrements invoice amount_paid. Needs a transactional cash-refund payout path with drawer permissions and audit/reconciliation semantics. L13, L16.
  `packages/server/src/routes/invoices.routes.ts:1162-1318`

- [!] WEB-UIUX-633. **[MAJOR] Card-leg failure mid-split can leave earlier card legs captured without a finish/reverse workflow.** BLOCKED 2026-05-07 — valid. CheckoutModal charges card legs sequentially after `posApi.checkoutWithTicket`; on a later leg failure it keeps the modal open with an error and invoice id, but it does not summarize already-captured legs, offer continue-with-remaining, or reverse captured legs. Server idempotency/recent-amount guards reduce immediate duplicate risk, but they do not create a durable split-session reconciliation model. L5, L8, L11.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:367-402`

- [!] WEB-UIUX-637. **[BLOCKER] PO Receive has no un-receive path.** Wrong items received → vanish into stock with no recovery. inventoryApi has no `un-receive`/`cancel-receipt`/`negative-receive`. L4, L16. **BLOCKED 2026-05-07: critique valid and backend-blocked. Web cannot safely fake un-receive because PO receive mutates purchase-order line quantities, inventory stock, and stock movement history; needs server API + audit semantics for reversing a receipt.**
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:64-80,138-146`

  `packages/web/src/pages/inventory/StocktakePage.tsx:336-348`

  `packages/web/src/pages/inventory/InventoryListPage.tsx:998`

  `packages/web/src/pages/inventory/ShrinkagePage.tsx:73-99,209-243`

- [!] WEB-UIUX-643. **[MAJOR] Stocktake quick-scan default = "current stock + 1" — silently increments.** Scanning twice = +2. No "confirm existing count" mode. L7, L8. **PARTIAL 2026-05-12 (autoloop): the "exact count" affordance was already wired in code (typing a Qty overwrites the running +1 tally) but the helper copy hid it. Helper text rewritten to surface both modes explicitly: blank Qty = +1 increment per scan (running tally), typed Qty = exact on-hand count that overwrites prior +1 rows for the same SKU. Closes the "silent increment" surprise without a UI toggle. A dedicated "confirm existing count" mode is still feature-scope; feature-scope.**
  `packages/web/src/pages/inventory/StocktakePage.tsx:174-181`

  `packages/web/src/pages/inventory/StocktakePage.tsx:378-400`

- [!] WEB-UIUX-653. **[MAJOR] No per-device pickup state — ticket-level "Ready for Pickup" all-or-nothing.** Multi-device ticket: device 1 done, device 2 waits parts → no UI for partial pickup. L5, L11. **[AUTOLOOP-T30 BLOCKED: per-device pickup state requires server schema (per-device status field) + multi-component UI.]**
  `packages/web/src/pages/tickets/TicketDevices.tsx:797-1149`

- [!] WEB-UIUX-660. **[MAJOR · BLOCKED] No abandoned-ticket workflow.** 90-day Ready-for-Pickup gets zero escalation lane (lumped with 7-day stale tickets in dashboard). No SMS cadence, no liability disclaimer, no auto-write-off. L5. **BLOCKED 2026-05-10: feature-scope — SMS cadence + liability template + write-off rule + dashboard lane.**
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

  `packages/web/src/pages/tickets/TicketDevices.tsx:820-823,927-930`

#### ED10: Search/Filter Weirdness

- [x] WEB-UIUX-667. **[MINOR] Sidebar NavLinks now restore filter state.** 2026-05-12 — new `useSidebarPathMemory` hook (mounted in AppShell) writes `pathname + search` to `sessionStorage` for tracked top-level list paths (/tickets, /customers, /invoices, /inventory, /leads, /memberships, /subscriptions, /refunds, /credit-notes, /reports, /gift-cards, /communications, /voice, /timesheets, /employees, /appointments). Sidebar's `<NavLink to={…}>` calls run through `resolveSidebarPath()` which swaps a bare prefix for the last-seen URL with query state. Only persists the list-view URL itself (not detail rows) so clicking "Tickets" never jumps to /tickets/123. sessionStorage scope = wipes on tab close so shared-kiosk users don't bleed filters.

  `packages/web/src/pages/tickets/TicketListPage.tsx:201-320`

  `packages/web/src/pages/invoices/InvoiceListPage.tsx:426-430`

- [!] WEB-UIUX-670. **[MINOR] No "Select all 4,832 matching" affordance like Gmail.** Bulk actions max at pagesize. L1. **[AUTOLOOP-T31 BLOCKED: requires server bulk-by-filter endpoints accepting filter criteria instead of explicit IDs.]**

  `packages/web/src/pages/customers/CustomerListPage.tsx:636-642`

  `packages/web/src/components/shared/DateRangePicker.tsx:109-115`

- [!] WEB-UIUX-673. **[MINOR] Old/invalid status param in URL silently passed to server.** "No items match" with no flag that filter value is invalid. L8, L14. **BLOCKED 2026-05-10: client can't know which statuses are valid without fetching status registry per entity; needs schema-driven validation table.**


  `packages/web/src/components/shared/CommandPalette.tsx:142-169`

#### ED11: Print/Receipt Failures

  `packages/web/src/pages/unified-pos/BottomActions.tsx:430-437`

  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:151-157`

- [!] WEB-UIUX-678. **[MAJOR · BLOCKED] No "if printer fails, still email" auto-fallback.** Three independent buttons, `handlePrintReceipt` calls `resetAll()` BEFORE navigation → loses access to email button. L4. **BLOCKED 2026-05-10: needs printer-status detection + post-print follow-up UI; depends on WEB-UIUX-683 (printer telemetry).**
  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:96-130,367-389`

- [!] WEB-UIUX-680. **[MAJOR] Mass label batch monolithic — one bad SKU = whole job fails or quietly truncates.** Server returns single blob, no per-item state, no "X succeeded Y failed". L8. **[AUTOLOOP-T31 BLOCKED: requires new server response shape (per-item status array) + client redesign of PrintResponse + UI.]**
  `packages/web/src/pages/inventory/MassLabelPrintPage.tsx:42-95`

- [!] WEB-UIUX-683. **[MAJOR] No printer-status telemetry anywhere — zero hits for printer.*offline / printer_status.** Cannot pre-disable Print buttons when no printer connected. L8, L11. **BLOCKED 2026-05-11: needs printer-status integration with the local hardware (CUPS/IPP poll, ESC/POS heartbeat, or USB enumeration). No telemetry agent in repo; printers vary by tenant. Cannot pre-disable Print buttons reliably without a deployment-side detector.**

  `packages/web/src/components/shared/PrintPreviewModal.tsx:16-21`

  `packages/web/src/pages/print/PrintPage.tsx:936-938`

  `packages/web/src/pages/print/PrintPage.tsx:993-998`

  `packages/web/src/components/billing/QrReceiptCode.tsx:20-60`

  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:144-148`

#### ED12: Notifications/Automations Gaps

- [!] WEB-UIUX-689. **[BLOCKER · BLOCKED] Template syntax fragmented — automations use `{var}`, campaigns use `{{var}}`, no client-side schema validator.** "first_nam" typo = 1000 SMS with literal text. L7, L16. **BLOCKED 2026-05-11: switching {{var}} bulk-SMS path to {var} or vice versa would invalidate every persisted template; needs a paired data migration to rewrite sms_templates.content. UIUX-690 server-side unknown-token validator now catches typos in {var}/{{var}} forms, removing the worst symptom.**
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/settings/AutomationsTab.tsx:59-69`
  `packages/web/src/pages/marketing/CampaignsPage.tsx:84,727`

  `packages/web/src/pages/settings/AutomationsTab.tsx:182-189`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/communications/components/OffHoursAutoReplyToggle.tsx`

  `packages/web/src/pages/settings/AutomationsTab.tsx:170-180`

  `packages/web/src/pages/marketing/CampaignsPage.tsx:81-88`

  `packages/web/src/pages/settings/AutomationsTab.tsx`

  `packages/web/src/pages/settings/AutomationsTab.tsx:606-612`

  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx:27-83`

  `packages/web/src/pages/communications/components/FailedSendRetryList.tsx:21-31`

- [!] WEB-UIUX-698. **[MAJOR] Segments have no concept of intersection / precedence.** Customer in "VIP" AND "High Risk" → which campaign wins? Undocumented. L5, L14. **BLOCKED 2026-05-11: segment intersection / precedence is a product decision (priority order vs explicit exclusion vs union) that affects campaign cadence semantics; needs design before encoding.**
  `packages/web/src/pages/marketing/SegmentsPage.tsx`

- [!] WEB-UIUX-699. **[MAJOR] Automation triggers don't include `customer_in_segment`.** Operator wanting "send VIP auto-reply" cannot express it. L5. **[AUTOLOOP-T32 BLOCKED: customer_in_segment trigger needs server segment evaluation engine + UI trigger config form; multi-component.]**
  `packages/web/src/pages/settings/AutomationsTab.tsx:42-48`

  `packages/web/src/pages/marketing/SegmentsPage.tsx:252-264`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/marketing/CampaignsPage.tsx:381-405`

  `packages/web/src/pages/marketing/SegmentsPage.tsx:172-189`

### Web UI/UX Audit — Pass 10 (2026-05-05, flow walk: process refund — server-vs-client gaps)

Re-walk of the "Process Refund" user flow, focusing on **server-side capability vs client wiring** rather than label/copy (already covered in Pass 8 #423-433). Key finding: server has TWO refund APIs (`refunds.routes.ts` with approval workflow + `creditNotes.routes.ts` collection) plus POS-return endpoint that web never calls. The Credit Note path on InvoiceDetail is the ONLY surfaced refund flow.

#### Blockers — Unwired server APIs

- [!] WEB-UIUX-710. **[MAJOR] Credit Note has no undo window; Void has 5s undo (`useUndoableAction`).** Same severity action, different recovery affordance. Operator-initiated mistake on credit note is permanent from web (server has POST /credit-notes/:id/void but unwired — see WEB-UIUX-704). L8. **PARTIAL 2026-05-11: server has POST /credit-notes/:id/void but credit_notes table is decoupled from the invoices.credit_note_for negative-invoice row that POST /invoices/:id/credit-note creates. A real undo needs the two tables reconciled first; defer to refunds reconciliation sprint.**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177,110-135`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`

- [!] WEB-UIUX-734. **[BLOCKER] No version/etag on any write — server is naive last-write-wins.** Two cashiers editing same ticket — one notes, one status — both succeed; later PUT wins for fields it sends. L11, L4. **[AUTOLOOP-T34 BLOCKED: cross-cutting optimistic concurrency — version columns + If-Match + UI conflict prompts; not safe to implement unilaterally.]**
  `packages/web/src/api/client.ts:372-394` (acknowledged)

  Multiple settings tabs share `['settings','config']` cache

- [!] WEB-UIUX-741. **[MINOR] No "stale data" age indicator anywhere.** Zero "edited X ago, refresh" badges. L11. **BLOCKED 2026-05-11: app-wide "edited X ago, refresh" badges need a uniform staleness contract per query key + per-page UI; designed-by-policy work, not a contained fix.**

#### ED5: Auth/Session/Permission Edges

- [!] WEB-UIUX-764. **[BLOCKER] Discount stacking has NO canonical order — single cart-wide `discount` slot.** No model for "10% off + $5 off + member 20%" with sequence/basis. Subtle base-vs-net errors. L7, L13. **[AUTOLOOP-T49 BLOCKED 2026-05-11: requires product decision on stacking order (% then $ vs $ then %), max-stack cap, and member-vs-promo precedence; multi-component model change across store/totals/server.]**
  `packages/web/src/pages/unified-pos/store.ts:101-103,235-237`

- [!] WEB-UIUX-768. **[MAJOR] No multi-jurisdiction tax breakdown — single `Tax (8.875%)` line.** Settings supports list but UI surfaces only one. CA/FL receipts require local rate broken out. L7, L9. **[AUTOLOOP-T49 BLOCKED 2026-05-11: tax_classes are per-category (parts/services), not per-jurisdiction. Adding state/county/city decomposition needs a tax_jurisdictions schema + per-line allocation in totals.ts/server pos.routes + receipt rendering — multi-component.]**
  `packages/web/src/pages/unified-pos/totals.ts:94`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:464-466`

- [!] WEB-UIUX-769. **[MAJOR] Refund line cannot be entered — clamp at parse hides use case.** Trade-in credits, returns can't be expressed at POS. L5, L7. **[AUTOLOOP-T35 BLOCKED: dedicated trade-in/return modal needed for refund lines; conflicts with returns flow if patched at stepper.]**
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:599-603`

- [!] WEB-UIUX-770. **[MAJOR] Tip/gratuity not implemented + no rounding-mode selector.** No tip-on-card flow, no Canada/Switzerland 5¢ rounding. L5, L7. **[AUTOLOOP-T49 BLOCKED 2026-05-11: tip handled on BlockChyp terminal hardware (UnifiedPosPage:6054); software tip-prompt + cash-rounding selector needs payment flow rewire + persisted setting + per-currency rule table.]**

  `packages/web/src/hooks/useDefaultTaxRate.ts:18-22`

- [!] WEB-UIUX-772. **[MAJOR] Bulk-price adjustment changes don't recompute existing cart lines.** Two cashiers add same item → different totals depending on add-time. L6, L11. **[AUTOLOOP-T36 BLOCKED: server emits no `inventory:price_changed` WS event; cannot signal cart for re-pricing without server-side event.]**
  `packages/web/src/pages/settings/RepairPricingTab.tsx:823-971`

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:756-771`

  `packages/web/src/pages/unified-pos/totals.ts:95`

  `packages/web/src/pages/unified-pos/store.ts:289-304`

  `packages/web/src/pages/unified-pos/totals.ts:79-85`

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:621,655,769,809`

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:881-887`

#### ED15: Time/Timezone/Scheduling

  `packages/web/src/utils/format.ts:101-144`

  `packages/web/src/pages/leads/CalendarPage.tsx:176-192,524,607,661,125-127`

  `packages/web/src/pages/leads/CalendarPage.tsx:179-192`

- [!] WEB-UIUX-782. **[MAJOR] DST fall-back ambiguity silently picks first occurrence.** Shift end 02:00 + start 01:00 on rollback day → undercount or silent overlap. Payroll bug. L7, L13. **[AUTOLOOP-T36 BLOCKED: DST fall-back ambiguity needs server-side TZ-aware duration math (dayjs/luxon with named TZ).]**

  `packages/web/src/pages/team/ShiftSchedulePage.tsx:108-113`

  `packages/web/src/pages/reports/ReportsPage.tsx:74-114`

  `packages/web/src/components/shared/DateRangePicker.tsx:26-34`

  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:67-78`

  `packages/web/src/pages/billing/PaymentLinksPage.tsx:135-148,238-241`

- [!] WEB-UIUX-797. **[MAJOR] ReceiveItemsModal scans NOT tied to any PO.** Scan-and-go restock looks like PO receive but creates ad-hoc unlinked stock. PO permanently "open". L5, L13. **[AUTOLOOP-T37 BLOCKED: ReceiveItemsModal needs PO picker UI + scan-validation + server purchase_order_id field; multi-component.]**
  `packages/web/src/pages/inventory/InventoryListPage.tsx:1318-1492`

- [!] WEB-UIUX-798. **[MAJOR] Four independent scan implementations with no shared abstraction — diverge in all behaviors.** Multi-match, in-flight guard, audio, no-match recovery, modal context — all different across 4 paths. L3, L4. **[AUTOLOOP-T49 BLOCKED 2026-05-11: requires extracting a `useBarcodeScanner` hook covering keystroke aggregation + multi-match modal + audio + retry; 4 callsites each with bespoke UX glue. Multi-day refactor with regression risk on every scan-driven flow.]**


  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:157-158`

#### ED17: Estimate→Ticket→Invoice Chain

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:127-136,289,403-409`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx`

  `packages/web/src/pages/estimates/EstimateListPage.tsx:587-601`


- [!] WEB-UIUX-808. **[MAJOR] Print on EstimateDetail uses `window.print()` of LIVE DOM.** Post-edit numbers + original `created_at` + `order_id` — customer can argue printout doesn't match what they signed. L13. **BLOCKED 2026-05-11: requires a server-rendered /print/estimate route (parallel to /print/invoice) to snapshot signed totals; needs an estimateprint.routes.ts file + EstimatePrintPage. Feature scope.**
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:248-254`

- [!] WEB-UIUX-809. **[MAJOR] PrintPreviewModal has no `estimateId` prop — operator can only print latest invoice/work-order, never original signed quote.** L5, L13. **[AUTOLOOP-T37 BLOCKED: PrintPage has no /print/estimate/:id route; adding estimateId prop has no target. Needs backend-rendered estimate print page.]**
  `packages/web/src/components/shared/PrintPreviewModal.tsx:100-120`

  `packages/web/src/pages/tickets/TicketPayments.tsx:114-123,270-274`

  `packages/web/src/pages/portal/PortalEstimatesView.tsx:22-51`

- [!] WEB-UIUX-826. **[BLOCKER] `subscribeMut` calls `membershipApi.subscribe` with NO `blockchyp_token` and NO `signature_file`.** Activation never captures card on file. Every nightly renewal will fail by definition. L5, L7, L16. **[AUTOLOOP-T38 BLOCKED: needs BlockChyp tokenize step + signature pad UI in CheckoutModal/CustomerDetailPage; multi-component.]**
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:891-902`

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:904-911`
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:113-124,155-168`

- [!] WEB-UIUX-831. **[MAJOR] InstallmentPlanWizard customer-default-on-3rd-payment story COMPLETELY ABSENT.** No payment status per row, no missed-payment marker, no transition to dunning, no auto-debit retry view. L5, L13. **[AUTOLOOP-T39 BLOCKED: per-installment payment status + missed-payment marker + dunning needs DB schema + API + cron; multi-component.]**
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:43-198`

  `packages/web/src/pages/settings/BillingTab.tsx:104-118`

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:913-920`

  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:135-139`

  `packages/web/src/pages/settings/BlockChypSettings.tsx:281-289`

- [!] WEB-UIUX-836. **[MAJOR] Subscription credit-note doesn't cancel future billing.** Goodwill refund → next cron charges again two weeks later. No "Also cancel subscription" checkbox. L5, L16. **BLOCKED 2026-05-11: subscription credit-note flow is not yet wired in the web UI; there is nothing to add a checkbox to. Defer to memberships refund sprint.**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311`

  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:81`

  `packages/web/src/pages/billing/DunningPage.tsx:64-68`

  `packages/web/src/pages/settings/MembershipSettings.tsx:434-440`


#### ED20: Error Recovery Patterns

  `packages/web/src/hooks/useWebSocket.ts:524-538`


  `packages/web/src/components/shared/OfflineBanner.tsx:1-51` (informational only)

  `packages/web/src/hooks/useUndoableAction.tsx:217-242`

  `packages/web/src/hooks/useDraft.ts:7,195-198`

  `packages/web/src/hooks/useDraft.ts:200-207`


  `packages/web/src/api/client.ts:355-369`


### Web UI/UX Audit — Edge-Case Pass C (2026-05-05, journeys + data flow + security + keyboard)

#### JOURNEY1: New Shop Owner Day 1

  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05). Do not address until email/SMTP system is ready.
  `packages/server/src/routes/signup.routes.ts:618`

  `packages/web/src/pages/setup/SetupPage.tsx:345`

  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:178,533-538`

  `packages/web/src/pages/tickets/TicketListPage.tsx:1750-1760`

  `packages/web/src/pages/setup/wizardTypes.ts:84-92`

  `packages/web/src/pages/setup/steps/StepMobileAppQr.tsx:38-80`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/setup/steps/StepSmsProvider.tsx:201-225`

  `packages/web/src/pages/setup/steps/StepPaymentTerminal.tsx:153-172`

  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx:153-212`

  `packages/web/src/pages/setup/steps/StepTax.tsx:38,56`

  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:236-240,370-481`

  `packages/web/src/pages/unified-pos/RepairsTab.tsx:154-200`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:51-53`

  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:175-179`

  `packages/web/src/components/onboarding/DailyNudge.tsx:37,47,55`

  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:194-237`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).


#### JOURNEY2: Busy Saturday

  `packages/web/src/pages/unified-pos/store.ts:64-68,273-288`

  `packages/web/src/pages/unified-pos/CustomerSelector.tsx:58-77`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

- [!] WEB-UIUX-870. **[MAJOR] Tech context-switching between 5 tickets loses cart state — only ONE persisted cart per user.** Switching ticket via `?ticket=` calls `resetAll()`. Inactivity timer 10min silently `resetAll()`. L4, L5. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs the POS browser-tab pattern (per-ticket cart slots) — multi-cart Zustand store keyed by ticket_id + tab-bar UI + LRU eviction. Mockup pattern memo'd; implementation is a multi-day refactor.]**
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:240-251`

- [!] WEB-UIUX-871. **[MAJOR] Kanban no batch drag.** Tech with 5 "ready for pickup" tickets must drag each individually. Bulk-mode exists in List view but not Kanban. L1, L5. **[AUTOLOOP-T40 BLOCKED: requires-multi-select-batch-drag-feature; multi-select infrastructure missing.]**

- [!] WEB-UIUX-872. **[MAJOR] End-of-day flow scattered across 3 pages — no End-of-Day wizard.** CashDrawerWidget + CashRegisterPage + BottomActions. No unified close-shift sequence. L1, L4. **[AUTOLOOP-T49 BLOCKED 2026-05-11: new wizard route needs product spec for step order (count drawer → reconcile → Z-report → deposit → lock) + role gates + recovery flow; multi-component feature, no obvious right ordering without operator input.]**



#### JOURNEY3: Angry Customer Dispute

  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:160-217`

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:330-396`


  `packages/web/src/components/billing/RefundReasonPicker.tsx:17-24`

  **STATUS: BLOCKED** — deferred until messaging (email/SMS) infrastructure work begins (per user 2026-05-05).

  `packages/web/src/components/tickets/QcSignOffModal.tsx`
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:590-597`

  `packages/web/src/components/tickets/CustomerHistorySidebar.tsx:90-92`

- [!] WEB-UIUX-911. **[MAJOR] 30+ `role="dialog"` sites lack focus-restore on close.** Only ConfirmDialog implements lastFocused capture/restore. PinModal, UpgradeModal, QuickSmsModal, CheckoutModal, WidgetCustomizeModal, SwitchUserModal, ReviewPromptModal, 5 InventoryListPage modals — focus drops to body. L12. **PARTIAL 2026-05-12 (autoloop): focus-restore wired in `ReviewPromptModal` (useFocusTrap), `PinModal` (inline capture/restore in mount effect), `QcSignOffModal` (useFocusTrap), and InventoryListPage's dismiss-low-stock modal (useFocusTrap; bulk-price + import already had it). `UpgradeModal` + `QuickSmsModal` already restore via inline `previouslyFocused.focus()` patterns. Remaining sites (CheckoutModal / WidgetCustomizeModal / SwitchUserModal / 4 remaining InventoryListPage modals + long tail) still pending; same one-line hook call per site.**

  TicketDevices.tsx:559,581,611,988,1008; TicketSidebar.tsx:232; KanbanBoard.tsx:114; DashboardPage.tsx:860; RepairsTab.tsx:1366,1372; ConditionsTab.tsx:337

  `packages/web/src/main.tsx:404-415`

- [!] WEB-UIUX-914. **[MAJOR] Focus lost after destructive delete.** Optimistic row removal → button unmounts → focus drops to body. No "next/prev row" target. L12, L4. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs a reusable `useFocusAfterRemove(rowRefs, removedId)` hook applied to every paginated list with optimistic delete — multi-callsite refactor (CustomerList, Tickets, Invoices, Inventory, Sequences, Roles, etc).]**

  `packages/web/src/pages/settings/SettingsPage.tsx:2285-2313`

  `packages/web/src/pages/customers/CustomerCreatePage.tsx:186-208`


- [!] WEB-UIUX-918. **[MINOR] Esc behavior inconsistent across search inputs.** Some clear, some close parent modal, some no-op. No documented policy. L4, L12. **STATUS: BLOCKED — cross-flow Esc-policy design touching ~12 search inputs; needs documented policy first; defer to design-system sprint**


  `packages/web/src/pages/portal/components/ReviewPromptModal.tsx:86-108`

  `packages/web/src/components/shared/SignatureCanvas.tsx`

#### ED22: Reports Data Accuracy

  `packages/web/src/pages/reports/ReportsPage.tsx:98-101`


  `packages/web/src/pages/reports/ReportsPage.tsx:993-1000`

- [!] WEB-UIUX-927. **[MAJOR] Chart fills "0" for missing days — no distinction between "no sales", "shop closed", "data not yet computed".** L8, L11. **[AUTOLOOP-T49 BLOCKED 2026-05-11: requires per-chart audit (revenue/tickets/repairs/AR/refunds/etc) to switch fill-zero arrays to nullable and teach each Recharts series how to render the gap (line: connectNulls=false; bar: drop entry). Also needs a `business_closed_days` source so "shop closed" can be styled distinctly from "no sales". Multi-callsite + data model.]**

  `packages/web/src/pages/reports/ReportsPage.tsx:1274-1282`

  `packages/web/src/pages/dashboard/DashboardPage.tsx:2120`



  `packages/web/src/pages/billing/AgingReportPage.tsx:46-52`

  `packages/web/src/components/shared/DateRangePicker.tsx:236,252-253`

  `packages/web/src/utils/format.ts:55-57`

#### ED23: External Integrations

  `packages/web/src/api/endpoints.ts:1177-1209`

  `packages/web/src/api/client.ts:65`

- [!] WEB-UIUX-957. **[MAJOR] No fallback channel when SMS fails — operator gets toast, no "Try email/portal-link instead" branch.** `estimates.routes.ts` returns `sent: false, warning, sms_error` but web just shows the warning toast. Customer with no phone or bad number = dead end; operator must navigate elsewhere to send by alternate means (and there is no alternate means in web). L4, L8. **STATUS: BLOCKED — needs SMS infrastructure work (deferred per user 2026-05-05); fallback channel UI pairs with that sprint**
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:75-80`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:219-231`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:222`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:772`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:102`
  <!-- meta: fix=use-formatApiError(err)+err.response.data.message-fallback -->

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:190-255`
  <!-- meta: fix=primary-action=solid-fill-by-status(Approve-when-sent-or-Send-when-draft-or-Convert-when-approved)+collapse-rest-into-overflow-menu -->

  `packages/web/src/pages/estimates/EstimateListPage.tsx:580-608`
  <!-- meta: fix=add-Convert-Selected-button-using-estimateApi.bulkConvert -->

  `packages/web/src/pages/estimates/EstimateListPage.tsx:588-596`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:237`
  <!-- meta: fix=either-enforce-server-side-rejected-as-terminal-OR-soften-copy-to-Reject-this-estimate? -->

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:177`
  <!-- meta: fix=mirror-breadcrumb-fallback -->

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:461-507`

- [!] WEB-UIUX-967. **[MAJOR] Inline line-item editor exposes raw `tax_amount` cell with no `tax_class_id` picker.** `EstimateDetailPage:345-350`. Modal create at `EstimateListPage:287-296` has tax-class dropdown that auto-computes. Editor forces operator to do mental math + paste cents into tax field. Inconsistent within same flow. L4, L7. **STATUS: BLOCKED — inline editor needs tax_class_id picker mirroring CreateEstimateModal; multi-component refactor + auto-compute logic, defer to estimates sprint**
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:323-359`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:309`

#### Minor — Polish, edge cases

  `packages/web/src/pages/estimates/EstimateListPage.tsx:171-203`

  `packages/server/src/routes/estimates.routes.ts:944,953-954`

  `packages/web/src/pages/estimates/EstimateListPage.tsx:619-625`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:399-431`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:530-549`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:127-136,437-457`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:209,222`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:16-22`

  `packages/web/src/pages/estimates/EstimateListPage.tsx:651-663`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:99-101`

- [x] WEB-UIUX-979. **[NIT] Sibling-pending state surfaced via text + cursor cue.** 2026-05-12 — PortalEstimatesView Approve/Decline buttons now: (a) swap the sibling button's label to "Waiting…" while one is mid-flight, (b) flip the sibling's cursor to `cursor-wait`, (c) carry `aria-busy` on the active button. Combined with the existing opacity-50 disabled state, the two buttons are no longer visually identical. Pattern works for the in-flight signal without committing to a broader skeleton-stripe design system change.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:160`

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:209`


### Web UI/UX Audit — Pass 12 (2026-05-05, flow walk: Issue Gift Card — sell, redeem, reload, recover)

Walk of "Issue Gift Card" end-to-end: cashier issues card → must sell to customer → customer presents card at POS → cashier redeems → balance reloads later. Cross-checked server `giftCards.routes.ts` (issue/lookup/redeem/reload + 128-bit hashed codes + brute-force rate limit + audit) against client `GiftCardsListPage.tsx`, `GiftCardDetailPage.tsx`, `unified-pos/CheckoutModal.tsx`, `App.tsx`, `Sidebar.tsx`, `CommandPalette.tsx`. Largest gap: server has full lookup + redeem infra (admin-side enumerated by `giftCardApi.lookup`/`redeem`) but **no POS UI ever calls it**. Cards can be issued and reloaded; cannot be spent.

#### Blockers — Cannot redeem, silent currency corruption, no recovery, no nav

- [!] WEB-UIUX-981. **[BLOCKER] POS has no Gift Card tender — `PaymentMethod = 'Cash' | 'Card' | 'Other'`.** `CheckoutModal.tsx:16` literal union does not include gift card; `PAYMENT_METHODS` array (`:23-27`) only Cash/Card/Other. Operator finishes sale → customer hands physical card → no UI path to apply balance. `giftCardApi.lookup` + `giftCardApi.redeem` declared in `endpoints.ts:1274-1276` and never called anywhere in `packages/web/src`. Entire feature half-built. L1, L8, L4. **STATUS: BLOCKED — multi-component blocker feature: new GiftCard tender + lookup-redeem modal + invoice gift_card_id linkage + receipt updates; needs design review**
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:16-27`
  `packages/web/src/api/endpoints.ts:1274-1276`
  <!-- meta: fix=add-GiftCard-tender+code-input-modal+lookup→redeem-flow+update-PaymentMethod-union -->

- [!] WEB-UIUX-982. **[BLOCKER] Currency render heuristic silently 100x-divides $1000–$10000 cards.** `formatCurrency` in both list + detail pages: `Number.isInteger(amount) && Math.abs(amount) >= 1000 ? amount / 100 : amount`. Server `GIFT_CARD_MAX_AMOUNT = 10_000` (dollars). Issue $1500 corp card → server stores `1500` (integer) → list/detail render `$15.00`. Comment claims "no real-world gift-card balance reaches $1000 in float-dollars outside corporate gifting" — corporate gifting is exactly the cohort that uses $1000+ cards. Reload to round amount has same defect. L7, L13, L8. **BLOCKED 2026-05-10: real fix is server-side schema normalization (REAL→INTEGER cents) tracked by SEC-H34-money-refactor; cannot be removed unilaterally without breaking pages that DO pass cents.**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:57-63`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:41-49`
  <!-- meta: fix=remove-cents-heuristic+pin-server-to-one-representation+migrate-callsites -->

- [!] WEB-UIUX-987. **[BLOCKER] POS has no "sell gift card" line item.** Operator selling a $50 gift card to a walk-in customer must (a) leave POS, (b) navigate to /gift-cards, (c) Issue card, (d) save code, (e) return to POS, (f) add a generic "Gift Card" misc product line, (g) checkout. Sale is never linked to gift_card_id; receipt doesn't show issued code; `gift_card_transactions` row says `notes='Initial load'` instead of `'Sold via invoice #N'`. Walk-in flow broken. L1, L4, L8. **STATUS: BLOCKED — multi-component POS rewrite: new line-item type + invoice gift_card_transactions linkage + receipt; deferred to gift-card hardening sprint**
  `packages/web/src/pages/unified-pos/`
  `packages/server/src/routes/giftCards.routes.ts:303-307`
  <!-- meta: fix=add-Sell-Gift-Card-button-in-POS-Misc-section+create-invoice-line+POST-issue-with-invoice_id-link -->

#### Major — Truthfulness, label/hierarchy, recovery

- [!] WEB-UIUX-1009. **[MINOR] List status filter chip not visually grouped with keyword search — separate `<select>` is plain styled, no chip pattern.** Most filter UIs in this app use chip toggles (LeadPipelinePage etc). Inconsistency. L9. **[AUTOLOOP-T49 BLOCKED 2026-05-11: chip refactor needs a shared FilterChipGroup component to avoid duplicating LeadPipelinePage's bespoke styling across all list pages. Not a one-page change.]**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:321-330`

- [x] WEB-UIUX-1013. **[MINOR] Gift-card lookup 429 retry-after countdown shipped.** 2026-05-12 — `GiftCardsListPage` RedeemModal `handleLookup` now reads `retry_after_seconds` from the 429 body, stores it in `lookupRetryIn`, and a tick effect counts down each second. While >0 the Look-up button is disabled and shows "Retry in Ns"; the error message appends "Retry in **Ns**." live. Closes the silent-throttle dead-end where a cashier would re-spam the locked endpoint and look like abuse traffic.
  `packages/server/src/routes/giftCards.routes.ts:188-197`

- [!] WEB-UIUX-1021. **[BLOCKER] `/pos/return` writes refund row directly at `status='completed'` — bypasses dual-control approval entirely.** `pos.routes.ts:2618-2621` `INSERT INTO refunds ... status='completed'`. Refunds.routes.ts `POST /` always inserts `status='pending'` then requires admin approve. The cashier path (when wired) skips that gate. Defeats the entire SEC-H28 atomic-approve design + SEC-H29 idempotency + EM1 commission reversal that fires only on `/approve`. Manager dual-control becomes opt-in based on which write path the cashier happens to take. L16, L4. **STATUS: BLOCKED — server pos.routes.ts dual-control policy change requires audit + role-gate review; defer to refunds sprint**
  `packages/server/src/routes/pos.routes.ts:2618-2621`
  `packages/server/src/routes/refunds.routes.ts:107,229-234`
  <!-- meta: fix=force-pos-return-to-status=pending-OR-require-elevated-role-at-route-level -->

  `packages/server/src/routes/invoices.routes.ts:1162-1317`
  `packages/server/src/routes/pos.routes.ts:2496-2637`
  <!-- meta: fix=invoke-reverseCommission-from-credit-note-and-pos-return-paths-with-original-invoice-fraction -->

  `packages/web/src/pages/customers/CustomerDetailPage.tsx`
  `packages/server/src/routes/refunds.routes.ts:439-525`

- [!] WEB-UIUX-1037. **[MAJOR] Credit Note modal has no recovery: no "Preview", no "Save Draft", no Undo window.** Void has 5s undo (`useUndoableAction` at `:110-135`); credit-note creation is fire-and-forget. Operator who fat-fingers $200 instead of $20 must manually issue a $180 reverse credit note and reconcile. Pattern asymmetry inside same page. L8, L16. **[AUTOLOOP-T49 BLOCKED 2026-05-11: 5s undo for credit-notes is risky — the action writes to invoices + refunds + store_credits + reverses commission in one transaction; undo would need to reverse all four side-effects (or pre-stage as draft). Server-side draft endpoint missing. Multi-component.]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177`

- [!] WEB-UIUX-1039. **[MINOR] InvoiceDetail header has 5 buttons in a row (Record Payment, Payment Plan, Financing, Print, Credit Note, Void) — no clear primary CTA on a partially-paid invoice.** Same finding as WEB-UIUX-961 (estimates). Six similar-height pills crowd the header on tablet (768) and wrap. Highest-leverage action depends on status but UI doesn't reflect that. L1, L11. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs a primary-vs-secondary action policy (e.g. Record Payment is primary while amount_due>0; Print is primary when paid; Void is destructive secondary). Pattern decision should align with estimate UIUX-961 + apply across detail pages.]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:342-389`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377-388`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:791-802`

  `packages/web/src/components/billing/RefundReasonPicker.tsx:18-23`

  `packages/web/src/components/billing/RefundReasonPicker.tsx:88`

  `packages/web/src/components/billing/RefundReasonPicker.tsx:91`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:744`

- [!] WEB-UIUX-1048. **[MINOR] BlockChyp settings page references "refund" but no card-refund-back-to-original-tender flow is wired in any UI.** `blockchypApi` likely has no `refund(transactionId)` method despite the processor supporting it. Card customers expecting refund back to card get cash or "credit on file" instead. L8. **STATUS: BLOCKED — needs new server-side card-refund route (BlockChyp refund API call) + audit-log + 5+ files; defer to refunds sprint**
  `packages/web/src/pages/settings/BlockChypSettings.tsx`

- [!] WEB-UIUX-1089. **[MAJOR] Signed sign-off is not printable / emailable / PDF-exportable — customer never receives a copy.** Migration 088 stores signature + photo + checklist results, but no `/qc/sign-off/:id/pdf` route, no print template, no `Email customer` button on TicketDetail post-sign. Customer who was promised "we'll send you the QC certificate" gets nothing. L1, L4, L8. **STATUS: BLOCKED — needs new /qc/queue page + Sidebar badge + LEFT-JOIN-IS-NULL query; multi-component, defer to QC sprint**
  `packages/server/src/routes/bench.routes.ts:703-910`
  <!-- meta: fix=add-GET-/qc/sign-off/:id/pdf-uses-existing-pdf-pipeline+after-success-toast-render-button-Send-to-customer-emails-PDF -->

- [!] WEB-UIUX-1139. **[MINOR] "Photo reminder" amber strip in DetailsStep tells the cashier to take photos but offers no in-flow capture button — the QR/photo widget is on the next-screen success view.** `RepairsTab.tsx:980-985` "Remember to take device photos after check-in for pre-repair documentation." — passive copy, no link or trigger. By the time the success screen renders, the device may already be on the bench. Inline "Capture now (camera)" or "Email me the link" would complete the loop. L6 discoverability. **STATUS: BLOCKED — needs new PhotoCaptureModal opened pre-create OR success-screen QR promoted into details step; multi-component, defer to POS sprint**
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:980-985`
  <!-- meta: fix=replace-static-strip-with-button-that-opens-PhotoCaptureModal-pre-create-OR-promotes-the-success-screen-QR-into-this-step -->

### Web UI/UX Audit — Pass 18 (2026-05-05, flow walk: Lock Commission Period — list, lock, CSV, server gates)

Flow walked: Sidebar → Team → "Payroll" → `PayrollPage` → `<CommissionPeriodLock />`. Server: `/team/payroll/periods` (GET/POST), `/team/payroll/lock/:id` (POST), `/team/payroll/export.csv` (GET), `/team/payroll/lock-check` (GET).

#### Blocker — irreversible action with no guardrails

  `packages/web/src/components/team/CommissionPeriodLock.tsx:163-174`
  <!-- meta: fix=window.confirm(`Lock ${p.name}? This is permanent — commissions and time entries in ${p.start_date}→${p.end_date} can never be edited again.`)+show-typed-confirm-modal-with-name-echo+optionally-add-server-side-/payroll/unlock-admin+24h-window -->

  `packages/web/src/components/team/CommissionPeriodLock.tsx:164`
  <!-- meta: fix=use-bg-red-600-hover:bg-red-700+ShieldAlert-icon-or-keep-amber-only-if-paired-with-confirmation-modal-(WEB-UIUX-1140) -->

#### Major — role gates, missing context, feedback gaps

  `packages/web/src/components/layout/Sidebar.tsx:120`
  <!-- meta: fix=either-restrict-sidebar-to-admin-only(role==='admin')-OR-conditionally-render-Lock+Download-with-role-tooltip-OR-relax-server-gate-to-admin-or-manager -->

  `packages/web/src/components/team/CommissionPeriodLock.tsx:125-145`
  <!-- meta: fix=add-helper-line-under-section-heading:-Locking-prevents-edits-to-commissions,-tips,-and-clock-entries-in-the-period-range. -->

  `packages/web/src/components/team/CommissionPeriodLock.tsx:158-161`
  <!-- meta: fix=resolve-locked_by_user_id-via-team-roster-lookup-(or-server-pre-join)-and-render-`Locked by ${name} · ${formatDate(locked_at)}`-as-secondary-text -->

- [!] WEB-UIUX-1160. **[BLOCKER] Two parallel cash-tracking systems coexist with no UI signposting that they're disconnected — operators routinely use both.** Sidebar exposes "Cash Register" page (`/pos/cash-in`,`/pos/cash-out`, `cash_register` table, dollars REAL) AND POS BottomActions exposes "Start/Close Shift" (cents INTEGER, `cash_drawer_shifts` table, with Z-report). Neither page mentions the other. Same operator clicks "Cash In" on Cash Register page during a `pos_drawer_shift` and assumes it'll appear in the shift's Z-report — it doesn't (see WEB-UIUX-1159). Architectural drift surfaces as a usability failure: operator's mental model is "one drawer", reality is "two ledgers". L1 finds two cash buttons; L2 "Cash In" label means different things in different places; L7 feedback never indicates the parallel state. L1, L2, L4, L7, L13. **PARTIAL 2026-05-12: CashRegisterPage now renders an amber discoverability banner when `/pos-enrich/drawer/current` reports an open shift, explaining that Cash In/Out here is the legacy drawer-pop ledger and does NOT post to the open shift's Z-report, with an inline link to Unified POS. Closes the signposting gap; full ledger unification (deprecate `cash_register` REAL or fold into `cash_drawer_shifts` cents) remains BLOCKED — migration-scale call needing data-migration plan + transitional UI.**
  `packages/web/src/pages/pos/CashRegisterPage.tsx`
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx`
  <!-- meta: fix=consolidate-into-single-cash-drawer-domain:-make-/pos/cash-in-/pos/cash-out-also-write-to-cash_drawer_shifts.adjustments+OR-deprecate-CashRegisterPage-and-add-an-In-shift-Cash-Adjustments-section-on-CashDrawerWidget-modal -->

- [!] WEB-UIUX-1179. **[MINOR] Counting input is single text field — no denomination breakdown (1s/5s/10s/20s/50s/100s + coins). Cashiers ALWAYS count by stack; UI forces them to do mental sum on calculator first, type total, then pray.** `CashDrawerWidget.tsx:262-273`. Industry-standard EOD UI is grid of denomination × count cells with auto-sum. Single-field gives an answer with no audit of how the count was obtained — high-fraud surface. L1 finding right tool, L13 trust/correctness. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs a DenominationGrid component + cash_drawer_shifts.closing_count_json schema for the per-denomination audit + Z-report integration. Multi-component feature.]**
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:257-292`
  <!-- meta: fix=add-toggle-Count-by-denomination+grid-(1,5,10,20,50,100,coin-buckets)+sum-into-counted_cents+persist-breakdown-as-cash_drawer_shifts.count_breakdown_json-for-audit -->

  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:77`
  <!-- meta: fix=render-skeleton-button-(<button-disabled>Loading…</button>)-while-isLoading -->

  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:164-209, 246-296`
  <!-- meta: fix=mirror-ZReportModal-pattern:-role=dialog-aria-modal-true-aria-labelledby=open/close-shift-title+id-on-h3+focus-trap-or-trap-within-modal -->

- [!] WEB-UIUX-1208. **[MAJOR] Credit-note silently inflates `amount_paid` on the original invoice by the credit amount — invoice flips to "paid" status with no actual money movement.** `invoices.routes.ts:1245-1257` `cappedAmountPaid = Math.min(prevAmountPaid + amount, total)` then UPDATE. So a $100 invoice with $50 collected, after a $50 credit note, reads `amount_paid=$100, amount_due=$0, status=paid` — but the customer paid only $50 cash. Reconciliation between AR ledger and bank deposits will silently disagree by $50 forever. The accounting-correct shape is: original invoice's `amount_paid` stays at $50 (real cash), and the new credit-note row's negative total is what brings net AR to zero. L13 trust/correctness, L7 honest feedback (status reads "paid" while customer was not refunded). **STATUS: BLOCKED — server invoices.routes.ts amount_paid mutation behavior change needs accounting review; backend, defer**
  `packages/server/src/routes/invoices.routes.ts:1245-1257`
  <!-- meta: fix=do-not-mutate-original.amount_paid-on-credit-note+let-the-negative-credit-note-row-cover-the-AR-reduction+OR-introduce-amount_credited-column-distinct-from-amount_paid -->

  `packages/server/src/routes/invoices.routes.ts:234-283`
  `packages/web/src/pages/invoices/InvoiceListPage.tsx`
  <!-- meta: fix=add-?type=invoice|credit_note|all-query-param+default-to-invoice+UI-tab-toggle-Invoices/Credit-Notes/All+badge-on-CN-rows-when-mixed-view -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380, 384-388`
  `packages/server/src/routes/invoices.routes.ts:1162`
  <!-- meta: fix=client-fetch-permissions-via-existing-/me-or-/permissions-call+conditionally-render-Credit-Note-and-Void-buttons+show-disabled-tooltip-Need-manager-permission-when-user-lacks-it -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-801`
  `packages/server/src/routes/invoices.routes.ts:1162-1316` (no reverse endpoint exists)
  <!-- meta: fix=ConfirmDialog-with-requireTyping=order_id+danger-styling+server-add-DELETE-/invoices/:cn_id/credit-note-(admin-only)-or-POST-/invoices/:id/credit-note/reverse -->

- [!] WEB-UIUX-1309. **[NIT] Header has Print/Void/Credit Note/Payment Plan/Financing — a 5+ button row that crowds on smaller viewports. Rare actions (Credit Note, Void) should live in a `…` overflow menu; common-and-frequent (Record Payment) front-and-centre.** L5 hierarchy, L1 primary action. **[AUTOLOOP-T49 BLOCKED 2026-05-11: header overflow menu (Credit Note + Void into ) needs the consistent primary-CTA-vs-overflow pattern across estimate UIUX-961, invoice UIUX-1039. App-wide pass.]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:342-389`
  <!-- meta: fix=keep-Record-Payment+Print-in-header+wrap-Void+Credit-Note+Payment-Plan-into-Kebab-More-actions-menu -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:172`
  <!-- meta: fix=mount-aria-live=polite-region-rendering-last-toast-text+OR-verify-react-hot-toast-emits-role=status -->

- [!] WEB-UIUX-1336. **[NIT] No SMS/email confirmation toggle on create. If server auto-sends confirmation (per location settings), staff has no way to opt out for internal-only blocks. If server doesn't, staff has no way to send. Either way, opaque.** L7 feedback, L6 discoverability. **PARTIAL 2026-05-12: closed the "opaque" half — `CreateAppointmentModal` (CalendarPage.tsx) now surfaces an inline notice "No automatic confirmation is sent. Booking the appointment does not message the customer — copy the date and time over manually until automated reminders ship." so staff aren't left guessing. The auto-send + opt-out toggle still waits on SMS infrastructure (deferred per user 2026-05-05); defer to messaging sprint.**
  `packages/web/src/pages/leads/CalendarPage.tsx:288-440`
  <!-- meta: fix=checkbox-"Send-SMS-confirmation-to-customer"-(default-on-when-customer-selected)+wire-server-to-honor-flag -->

### Web UI/UX Audit — Pass 26 (2026-05-05, flow walk: Convert Lead to Ticket — detail button, status pill, pipeline drop, reminders, dedupe)

Walk: lead detail "Convert to Ticket" green CTA → confirm() → POST /leads/:id/convert (creates customer + ticket + flips status) → toast → navigate /tickets/:id. Parallel paths: (a) status-pill picker on detail page sets `status='converted'` via PUT /:id, (b) pipeline kanban "Move to Converted" menu also calls PUT /:id. Server PUT only checks transition legality (`proposal → converted` allowed) — DOES NOT call the convert handler. Both bypass paths leave the lead orphan-converted with NO ticket, NO customer, NO audit. Confirm-copy hides the customer-creation side effect. Detail-page error handler swallows server messages (tier-limit upgrade nudge, bad email, missing customer info → all collapse to "Failed to convert"). Reminders pinned to lead never migrate to the new ticket. Convert silently dupes customers when phone/email already exist.

  `packages/web/src/pages/leads/LeadDetailPage.tsx:358-379`
  `packages/web/src/pages/leads/LeadPipelinePage.tsx:20-27,148-161,283-293`
  `packages/server/src/routes/leads.routes.ts:36,818-903,1001-1136`
  <!-- meta: fix=server-side-PUT-/:id-must-reject-status='converted'-(force-callers-to-use-/convert-handler)+detail-pill-picker-and-pipeline-move-menu-special-case-'converted'-like-'lost'-(open-confirm/route-to-convert-mut)+remove-'converted'-from-PIPELINE_STAGES-OR-make-the-drop-trigger-the-real-convert-handler -->

  `packages/web/src/pages/leads/LeadDetailPage.tsx:197-206`
  `packages/server/src/routes/leads.routes.ts:1013,1015,1044-1054,1068-1069,1082`
  <!-- meta: fix=copy-LeadListPage-onError-pattern-(extract-formatApiError)+special-case-upgrade_required:true-to-route-user-to-/billing-with-CTA-button-in-toast -->

  `packages/server/src/routes/leads.routes.ts:1063-1080`
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:64,371-378`
  <!-- meta: fix=convert-handler-SELECT-customers-WHERE-email=?-OR-phone=?-LIMIT-1-before-INSERT+if-match-return-{found:true,customer_id,name}+UI-presents-link-or-create-new-choice -->

- [!] WEB-UIUX-1386. **[MAJOR] Credit-note client cap mismatched to server cap. Client caps amount at `Number(invoice.amount_paid) || 0` (`InvoiceDetailPage.tsx:298,763,777`). Server caps at `original.total - alreadyCreditedSoFar` (`invoices.routes.ts:1186,1197-1201`). Unpaid $200 invoice that legitimately needs a $200 ledger write-off (e.g. uncollectible debt to be written off as discount-after-the-fact) cannot be credited via UI — client throws "Amount cannot exceed amount paid ($0)" before request leaves browser. Server would accept the $200 credit. Two divergent rules; client is more restrictive than necessary.** L4 flow, L11 consistency. **STATUS: BLOCKED — credit-note client/server cap mismatch needs accounting policy decision (write-off semantics); defer to refunds sprint**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:298-303,763,776-778`
  `packages/server/src/routes/invoices.routes.ts:1186,1197-1201`
  <!-- meta: fix=decide-policy:-(a)-write-off-flow-needs-server+client=invoice.total-prior_credits+OR-(b)-document-credit-note-as-refund-only-and-keep-amount_paid-cap+server-aligns-to-amount_paid -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:475-548`
  <!-- meta: fix=GET-/invoices/:id-payload-include-credit_notes:[{order_id,amount,reason,created_by,created_at}]+render-as-Credit-Notes-section-or-merge-into-timeline-with-distinct-icon -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-802 vs 807-817`
  <!-- meta: fix=switch-creditNoteMutation-to-ConfirmDialog-with-requireTyping=true+confirmText=invoice.order_id+danger=true -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:176`
  `packages/server/src/routes/invoices.routes.ts:1192-1201`
  <!-- meta: fix=server-returns-{message,already_credited,max_remaining}-structured+UI-special-cases-and-pre-fills-input-with-max_remaining+banner-"Already-credited:-$50.-Remaining:-$150" -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311`
  <!-- meta: fix=track-fieldErrors:Record<string,string>+render-text-red-500-text-xs-mt-1-under-each-field+disable-Create-button-when-any-fieldError-set -->

- [!] WEB-UIUX-1427. **[BLOCKER] No POS payment method for gift cards. CheckoutModal `PaymentMethod = 'Cash' | 'Card' | 'Other'` (`CheckoutModal.tsx:16,23-27`). Server's `/gift-cards/lookup/:code` + `POST /gift-cards/:id/redeem` (`giftCards.routes.ts:172,328`) cannot be reached from any sale UI. Recipient walks in with the code → cashier rings up sale → no "Gift Card" tile in payment methods → cashier hand-codes "Other" → no balance check, no redemption row written → server gift-card balance never decremented → physical card stays at full balance forever, customer can spend it again at next visit.** L1 primary action findability, L4 flow completion (entire redemption loop dead), L6 discoverability. **STATUS: BLOCKED — needs PaymentMethod GiftCard tile + lookup→balance pill + redeem POST chain + invoice gift_card_id linkage; multi-component, defer to gift-card sprint**
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:16,23-27,530-575`
  `packages/server/src/routes/giftCards.routes.ts:172-245,328-392`
  <!-- meta: fix=add-PaymentMethod='GiftCard'+tile-with-Gift-icon+on-select-show-code-input+lookup→show-balance-pill-"$45.00-available"+confirm-amount-(cap-at-min(due,balance))+POST-/gift-cards/:id/redeem-with-invoice_id-on-checkout-success+include-in-split-payments -->

- [!] WEB-UIUX-1454. **[NIT] `formatCurrency` cents/dollars heuristic (`GiftCardsListPage.tsx:57-63`, mirrored on Detail `:41-44`) treats integers >=1000 as cents. A $999.99 card stored as float 999.99 renders as $999.99 (correct); a $10.00 card stored as integer 1000 cents renders as $10.00 (correct); but a $10 card mistakenly stored as integer 10 (dollars, not cents) renders as $10 — looks fine until you hit edge case $1500 → 1500 dollars vs 1500 cents=15 ambiguity. Comment acknowledges fragility ("if it does, it'll still render correctly because 1000.5...") but it's a ticking interpretation bomb. Drop the heuristic the moment server picks one representation.** L11 consistency. **[AUTOLOOP-T49 BLOCKED 2026-05-11: heuristic resolution must follow a server-side picks-one-representation change (cents OR dollars) + migration on stored balances. Single-page fix risks regressions until the server commits.]**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:46-63`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:38-53`
  <!-- meta: fix=spike-server-→-emit-cents-only-on-/gift-cards-routes+remove-heuristic+single-formatCurrencyShared(amountCents/100) -->


## Deferred operational items

- [!] OPS-DEFERRED-001. **Multi-platform setup migration (`setup.bat` → `setup.mjs`) + cross-platform auto-startup adapter.** **STATUS: BLOCKED — operational migration deferred (Phase 2 awaits Windows host smoke test); not a UI fix item**
  - [x] **Phase 0 LANDED 2026-05-05**: per-OS gateway shims (`setup.bat` + `setup.command` + `setup.sh`) verify Node v22-24 and best-effort install via winget / Homebrew / apt-dnf-yum-pacman-zypper-apk-NodeSource, falling back to opening `https://nodejs.org/en/download/` on any failure.
  - [x] **Phase 1 LANDED 2026-05-05**: `setup.mjs` is now a full cross-platform 12-step install/update flow (preflight → git pull → pm2 stop → npm install → .env → certs → build → Android APK conditional → dashboard build → pm2 start+save → autostart register → open browser). Cross-platform autostart adapter at `scripts/autostart/{index,linux,darwin,win32}.mjs` with one entrypoint and three OS-specific implementations (Linux: `pm2 startup systemd` + `pm2 save`; macOS: `pm2 startup launchd` + `pm2 save`; Windows: Task Scheduler XML via `schtasks` — NO vendored binaries, NO PowerShell scripts). Single transitional Windows-only branch in setup.mjs for the Electron-package step (electron-builder is `--win`-flagged in packages/management/package.json); goes away when [dashboard-migration-plan.md](./docs/dashboard-migration-plan.md) Phase E ships. `scripts/setup-windows.bat` retained as escape hatch + reference; no longer invoked by setup.mjs.
  - Verified: bash -n + node --check pass on all 7 setup files; partial smoke run on macOS (preflight → pm2 stop → npm install) reaches step 4 cleanly; autostart adapter exports verified via direct module import + status() call.
  - [!] **Phase 2** (when unblocked): delete `scripts/setup-windows.bat`. AUDIT 2026-05-11: grep across the entire repo (`*.bat *.mjs *.cjs *.js *.ts *.md *.sh *.json`, minus node_modules + TODO files) finds zero callers. The only reference was a stale comment at `setup.bat:14` which was rewritten 2026-05-11 to clarify that setup.mjs no longer delegates back to it. The file is genuinely unreferenced; safe to delete from a static-call-graph standpoint. The remaining gate is purely operator-pinned shortcuts: if any Windows operator has a desktop shortcut or scheduled task pointing at `scripts/setup-windows.bat` directly, deletion breaks them. Cannot verify that without a Windows host. Conservative path: keep until a Windows operator confirms no direct invocations, then delete.
  - Acceptance when fully unblocked: fresh boot on Linux/macOS/Windows brings CRM online without user login; zero `process.platform === 'win32'` branches outside the three adapter files (pending Electron-package transition); `scripts/setup-windows.bat` deleted.
  - Related: [dashboard-migration-plan.md](./docs/dashboard-migration-plan.md) Phase C-pre — `setup.mjs` also drops the Electron build/launch from this script and replaces with `vite build` of the static dashboard + open-in-browser to `https://localhost/super-admin/`. Once that lands, the only Windows-only branch in setup.mjs disappears.

- [!] OPS-DEFERRED-002. **Browser-served super-admin dashboard (deprecate Electron `packages/management/`).** **STATUS: BLOCKED — operational migration deferred (4-week implementation gated on team capacity); not a UI fix item**
  - [!] BLOCKED 2026-05-11: planning doc complete at [dashboard-migration-plan.md](./docs/dashboard-migration-plan.md) 2026-05-05; implementation gated on team capacity (~4 weeks for one engineer). Replaces ~4500 lines of Electron main + ~89 IPC handlers + Chromium binary + per-OS code-signing pipeline with: server-side `/super-admin/api/management/*` REST routes + static SPA at `/super-admin/` + a tiny `bizarre-crm-rescue` PM2 app for the crashed-server case. Promoted from `[ ]` to `[!]` so the autoloop stops re-picking — this is a deliberate non-attempt.
  - Pairs with `OPS-DEFERRED-001` — Phase C-pre of this plan modifies `setup.bat`/`setup.mjs` to drop Electron build/launch and open browser instead. Independent of (3)/(4) of dashboardplan can start any time; (5)/(6)/(8) gate on multi-OS setup migration.
  - Acceptance: `packages/management/` deleted, fresh `setup.mjs` opens default browser to `https://localhost/super-admin/`, phone/tablet remote management works on LAN, Rescue Agent at `http://localhost:7474/rescue` handles crashed-main-server case.

### Web UI/UX Audit — Pass 33 (2026-05-05, flow walk: Send Bulk SMS — segment pick, preview token, confirm, partial-fail visibility)

#### Blocker — feedback mismatch / wording invisibility

  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:91-98`
  `packages/server/src/routes/inbox.routes.ts:693-703`
  <!-- meta: fix=update-onSuccess-handler-to-read-{attempted,sent,failed}+show-failure-aware-toast+keep-modal-open-when-failed>0-with-link-to-/inbox-retry-queue -->

  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:167-196`
  <!-- meta: fix=add-message-body-preview-block-with-variable-substitution-rendered-against-first-segment-row+character-count+segment-count-(SMS=160-chars-per-segment) -->

#### Major — usability / recovery / hierarchy

  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:29-33`
  `packages/server/src/routes/inbox.routes.ts:377-380,396-397,404-405,415-416`
  <!-- meta: fix=update-SEGMENTS-hints-to-mention-marketing-opt-in-+-consent;-add-tiny-help-line-"recipients-filtered-to-marketing-SMS-consent" -->

  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:117`
  <!-- meta: fix=disable-backdrop-onClose-when-preview-non-null;-or-route-backdrop-click-through-confirmation-"Discard-this-send?" -->

- [!] WEB-UIUX-1516. **[MINOR] No scheduling option in BulkSmsModal. `ScheduledSendModal.tsx` already exists in the same `components/` folder for 1:1 scheduled sends. Bulk SMS is send-now only — admin who wants to blast Tuesday 10am has to set a personal reminder and re-build the campaign. Wire a "Schedule for later" checkbox; defer to existing scheduler infra.** L6 discoverability. **STATUS: BLOCKED — needs new scheduled-bulk-send endpoint integration with ScheduledSendModal infra; multi-component, defer**
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:198-224`
  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx`
  <!-- meta: fix=add-"Schedule-for-later"-toggle+datetime-picker;-on-confirm-route-to-scheduled-bulk-send-endpoint-instead-of-immediate-/inbox/bulk-send -->

- [!] WEB-UIUX-1536. **[MINOR] Method `<button>` highlight depends on a normalize that breaks on rename. `InvoiceDetailPage.tsx:629,631` matches `paymentForm.method === pm.name.toLowerCase().replace(/\s+/g, '_')`. Admin renames "Credit Card" → "Credit" in Settings → method string becomes `credit` not `credit_card` → all historical reports keyed on `credit_card` lose continuity. The `payment_methods` table has a stable `id` column (`settings.routes.ts:849`); use that as the wire value, with `name` only for display. Same fix unblocks WEB-UIUX-1524.** L11 consistency, L10 trust (reports). **[AUTOLOOP-T49 BLOCKED 2026-05-11: switching the payload from name-slug to payment_method id is a contract change — server `payments.method` column stores the normalized name today; migrating requires schema work + import-job audit.]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:626-639`
  `packages/server/src/routes/settings.routes.ts:838-851`
  <!-- meta: fix=submit-pm.id-(or-canonical-slug)-as-method;-server-resolves-to-display-name;-historical-reports-keep-stable-key-across-renames -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:43,77-92`
  <!-- meta: fix=useEffect-once-pmData-loads-{setPaymentForm(p=>({...p,method:paymentMethods[0]?.id||'cash'}))} -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:94-105`
  `packages/server/src/routes/invoices.routes.ts:820-823`
  <!-- meta: fix=add-queryClient.invalidateQueries({queryKey:['customer',invoice.customer_id]});-also-on-credit-note-success-+-void -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:591-672`
  <!-- meta: fix=use-shared-Modal-primitive-OR-react-focus-lock;-trap-focus-within-card;-restore-focus-to-Record-Payment-button-on-close -->

#### Nit — copy / polish

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:642-644`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:679-685`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:625`

### Web UI/UX Audit — Pass 35 (2026-05-05, flow walk: Issue Gift Card — entry, reveal-once, code reveal truthfulness, recipient delivery, end-to-end redeem path)

#### Blocker — broken end-to-end flow / lying copy / missing controls


## PASS 2 — DEEP DIVE


## Findings


## PASS 2 — DEEP DIVE


## Findings


## Summary


## PASS 2 — DEEP DIVE


## Summary — Pass 2 additions


## Findings


## PASS 2 — DEEP DIVE


## FINDING S05-01 — MEDIUM


## FINDING S05-02 — LOW


## FINDING S05-03 — LOW


## FINDING S05-04 — INFO


## FINDINGS SUMMARY


## PASS 2 — DEEP DIVE


## PASS 2 ADDITIONAL VERIFIED CLEAN


## PASS 2 FINDINGS SUMMARY


## VERIFIED CLEAN (no findings)


## Findings


## NOT FOUND (explicitly checked, clean)


## Summary


## PASS 2 — DEEP DIVE


## Pass 2 Summary


## NO FURTHER FINDINGS


## PASS 2 — DEEP DIVE


## Findings


## Summary


## PASS 2 — DEEP DIVE


## Findings


## PASS 2 — DEEP DIVE


## FINDING S10-01 — MEDIUM — Plaintext Password Stored in In-Memory Pending Signup Map


## FINDING S10-02 — MEDIUM — Hardcoded Default PIN "1234" Created for Every Admin User


## FINDING S10-03 — LOW — Tenant Uploads Directory Not Cleaned Up on Termination or Grace-Period Archive


## FINDING S10-04 — LOW — `repairTenant` Can Flip Any Non-Active Tenant to "active" Status


## FINDING S10-05 — INFO — Archived DB Files Have No Explicit Filesystem Permissions Set


## FINDING S10-06 — INFO — Token Reference Logged in Plain Text for Operator Recovery (SCAN-743)


## Summary


## PASS 2 — DEEP DIVE


## PASS 2 — Summary


## FINDING S11-01 — LOW — Internal Filesystem Path Leaked in Schedule-Run API Response


## FINDING S11-02 — LOW — `dataExportGenerator` EXCLUDED_TABLES Missing Two Entries vs `tenantExport`


## FINDING S11-03 — LOW — Backup Cron Expression Accepts Second-Precision `* * * * * *` (Resource Exhaustion)


## NO FINDINGS — items verified clean


## PASS 2 — DEEP DIVE


## Summary


## MEDIUM — Missing `ESCAPE` clause on escapeLike-protected LIKE patterns


## LOW — `tracking.routes.ts` phone last-4 LIKE without `ESCAPE` (line 273)


## INFO — Patterns that look risky but are safe


## Positive findings (defence-in-depth already in place)


## PASS 2 — DEEP DIVE


## Pass 2 — Extended Safe Patterns Verified


## Summary


## Scope cleared — with one MEDIUM access-control finding


## Full scope cleared — what was checked


## Scope


## SCOPE CLEARED


## Scope Coverage Summary


## SCOPE CLEARED — items checked and found safe


## Summary


## Scope investigated


## SCOPE CLEARED — checklist of what was verified safe


## Summary


## Checklist Results


## Trust Proxy / req.ip Verification


## In-Memory vs Persistent Limiters


## Multi-Process Note


## Items verified clean


## Scope


## Summary


## Middleware Execution Order (confirmed good)


## Cross-cutting observations (from holistic read)


## Middleware baseline (verified sound)


## COVERED (not vulnerable)


## Summary


## Summary


## Scope Cleared


## Scope-cleared checklist


## Summary of Findings


## Scope Cleared — Confirmed-Safe Checks


## IP-Pinning Verification


## SCOPE CLEARED — Items verified safe


## SCOPE CLEARED — Patterns confirmed safe


## SCOPE CLEARED — remaining vectors investigated


## SCOPE CLEARED — items investigated and found safe


## Summary


## Coverage Matrix


## Findings


## Summary


## Summary


## Scope


## SCOPE CLEARED — Areas verified safe


## Summary


## SCOPE CLEARED


## Scope


## Summary


## Cleared / Not Vulnerable


## Scope Cleared


## Scope


## SCOPE CLEARED — No CDN/SRI issues found


## SCOPE CLEARED — items verified safe


## Summary Table


## FEATURE — Dashboard "Price list" button → spreadsheet view (web/android/iOS) — 2026-05-05

- [!] FEAT-PRICELIST-001. **[FEATURE] Dashboard "📋 Price list" button opens an Excel-like spreadsheet of every device + repair price the admin has configured, with full search.** Admin sets prices once in Settings → cashier/technician hits one button on Dashboard to see the live price grid during a customer call or in-person visit. No need to dig into Settings → Repair pricing every time. Server already exposes the data via `routes/repairPricing.routes.ts` (`/api/v1/repair-pricing/prices`) and `services/repairPricing/*`; what's missing is a fast, focused, read-mostly grid surface usable from the dashboard. **STATUS: BLOCKED — full feature build requires new PriceListPage (web) + PriceListActivity (Android) + PriceListView (iOS) + virtualized grid + edit + audit + CSV export; multi-platform multi-week effort, defer to feature sprint**
  **Scope:**
  1. **Dashboard button** — added in mockups already (web header, android phone top app bar, android tablet toolbar, ios iphone greeting card, ios ipad capsule). Wire to a new route/screen `/price-list` (web), `PriceListActivity` (Android), `PriceListView` (iOS).
  2. **Spreadsheet view** — virtualized grid (web: TanStack Table or AG Grid Community; Android: Compose `LazyColumn` × `LazyRow` or RecyclerView; iOS: SwiftUI `LazyVGrid`/`Table`). Columns: Brand · Model · Repair · Tier1 · Tier2 · Tier3 · Updated. Sticky header row + first column.
  3. **Search** — top-bar input with debounce (250 ms). Match against brand, model, repair name, tier name. Live-filter rows. Optional column-filter chips (Brand, Repair type).
  4. **Read-only by default** — admin can toggle "Edit mode" (only owner+admin role) to inline-edit a cell; saves via `PUT /api/v1/repair-pricing/prices/:id` with optimistic update.
  5. **Empty state** — "No prices configured yet" with link to Settings → Repair pricing.
  6. **Permissions** — gated by `requireRole(['owner','admin','manager'])` for read; `requireRole(['owner','admin'])` for edit.
  7. **Performance** — server returns paginated chunks (100 rows) with cursor pagination on `(brand_id, model_id, repair_id)`.
  8. **Audit** — log every cell edit to `audit_logs` (actor, before, after, field, row_id).
  9. **Export** — "Export CSV" button in toolbar (admin only).
  10. **Accessibility** — keyboard navigation arrow keys + Enter to open edit + Esc to cancel. Screen reader announces row context.
  L4 flow completion, L6 discoverability, L8 staff productivity.
  **Mockups touched (button only — spreadsheet screen mockups still TODO):**
  `mockups/dashboard/web.html` (dark + light themes — added 📋 Price list pill before ⚙ Customize)
  `mockups/dashboard/android-phone.html` (dark + light — added 📋 icon circle in top app bar)
  `mockups/dashboard/android-tablet.html` (dark + light — added 📋 Price list pill in toolbar)
  `mockups/dashboard/ios-iphone.html` (dark + light — added 📋 Price list pill in greeting glass card)
  `mockups/dashboard/ios-ipad.html` (dark + light — added 📋 Price list capsule beside ⚙ Customize)
  **Server already exists:**
  `packages/server/src/routes/repairPricing.routes.ts`
  `packages/server/src/services/repairPricing/{tierResolver,autoMargin,marginAlerts,seedDefaults}.ts`
  `packages/server/src/db/migrations/153_repair_pricing_dynamic_index.sql`
  `packages/server/src/db/migrations/163_seed_repair_prices.sql`
  **Web client work:**
  - new file `packages/web/src/pages/price-list/PriceListPage.tsx` (virtualized grid)
  - new route in `packages/web/src/App.tsx` `/price-list`
  - new endpoint binding in `packages/web/src/api/endpoints.ts`: `priceListApi.list`, `priceListApi.search`, `priceListApi.update`
  - dashboard header wires button (already mocked) → `useNavigate('/price-list')`
  **Android client work:**
  - new screen in Compose under `android/app/src/main/java/.../pricelist/PriceListScreen.kt`
  - nav graph entry from `DashboardScreen` top-app-bar action icon
  - data layer: Retrofit interface `PriceListApi`, Room cache for offline read
  **iOS client work:**
  - new SwiftUI view `ios/.../PriceList/PriceListView.swift` using `Table` for iPad, custom `LazyVGrid` for iPhone
  - nav from `DashboardView` toolbar capsule / greeting card pill
  - data: `PriceListService` against existing `/api/v1/repair-pricing/prices`
  **Mockup spreadsheet view (still to draft):**
  `mockups/Other mockups&files/price-list-web.html` (canonical desktop view)
  `mockups/Other mockups&files/price-list-android-phone.html`
  `mockups/Other mockups&files/price-list-android-tablet.html`
  `mockups/Other mockups&files/price-list-ios-iphone.html`
  `mockups/Other mockups&files/price-list-ios-ipad.html`
  <!-- meta: scope=dashboard+price-list; depends=server/repairPricing.routes.ts (exists); fix=add-route+grid+search+edit-mode+csv-export+a11y+pagination -->

---


## POS-REWRITE-FOLLOWUPS


## AUDIT WAVE 2026-05-10 — cross-surface critical/high bug hunt (BUGHUNT-2026-05-10)

- [!] BUGHUNT-2026-05-10-05. **[HIGH] File upload quota mutex is in-memory only.** `packages/server/src/middleware/fileUploadValidator.ts:49-68` — quota counter mutex lives in process memory. Server restart or PM2 cluster mode loses state; two workers can both pass quota check and overflow tenant disk allowance. Fix: persist quota counter in SQLite with `UPDATE … WHERE used + ? <= cap` guard. **[AUTOLOOP-T49 BLOCKED 2026-05-11: persisting file-upload quota counter in SQLite needs a new file_upload_quota table or store_config row + UPDATE-with-guard pattern; mutex map in-memory survives single-process today. Multi-component infrastructure change.]**
- [!] BUGHUNT-2026-05-10-12. **[HIGH] POS card-capture happens before local stock decrement transaction completes.** `packages/server/src/routes/pos.routes.ts:600-728` — payment INSERT inside `adb.transaction()` happens after the processor charge has already been captured externally. If the embedded stock-decrement guard fails (concurrent oversale), the local transaction rolls back but the processor charge stands. Need post-rollback compensating refund or pre-flight stock reservation before charging. **[AUTOLOOP-T49 BLOCKED 2026-05-11: pre-flight stock reservation OR post-rollback compensating refund is a multi-step BlockChyp + stock workflow change touching pos.routes, refunds.routes, and the terminal integration. Holds.]**
- [!] BUGHUNT-2026-05-10-46. **[HIGH] CustomerListPage paginates by offset — rows inserted mid-browse shift pages.** `packages/web/src/pages/customers/CustomerListPage.tsx:187-188` — duplicate or missing rows on concurrent INSERT during paging. Audit-relevant when CSV-exporting page-by-page. Move to cursor (id-keyset) pagination. **[AUTOLOOP-T49 BLOCKED 2026-05-11: cursor (keyset) pagination must replace offset across the customer list query + server-side cursor field. Multi-component query refactor; defer pending a shared list-pagination helper.]**

### Inventory / Tickets / Print / Misc

