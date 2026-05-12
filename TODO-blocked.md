---
name: TODO blocked items
description: Auto-extracted [!] blocked items from TODO.md; loop reads this file, not TODO.md
type: project
---

> **AUTO-GENERATED.** Source of truth is `TODO.md`. Regenerate via `bash scripts/regen-blocked.sh`.
> When an item flips to `[x]`, edit both this file and `TODO.md`; the next regen will reconcile.


## Repair templates: device-keyed seeding with multi-tier parts (REPAIR-TEMPLATES-SEED)

- [!] REPAIR-TEMPLATES-SEED-2. **Hydrate parts_json from real inventory + supplier scrape.** BLOCKED 2026-05-10 — three blockers: (1) supplier scrape (Mobilesentrix/PLP) is external HTTP scraping with no auth/rate-limit story in repo; (2) device_model_templates has no tier_label column to disambiguate Original-OEM vs Soft-OLED at lookup time; (3) inventory_device_compatibility is just a model↔item link with no per-fault filtering. Auto-attach acceptance criteria cannot be met without (a) tier_label column migration on device_model_templates AND inventory_items, (b) scrape job worker. Needs design pass first. The 173 seed leaves `parts_json: '[]'` — templates apply labor + suggested_price but don't pre-attach the SKU. Wire a follow-up that joins device_models → inventory_device_compatibility → inventory_items by tier label, and falls back to live Mobilesentrix / PhoneLCDParts scrape when the shop doesn't yet stock the SKU. Acceptance: opening "iPhone 13 — Screen (Original OEM)" auto-attaches the matching inventory line on apply.
- [!] REPAIR-TEMPLATES-SEED-1. **Original Seed task — extend coverage beyond the top 15 devices.** BLOCKED 2026-05-10 — extending to "every popular phone/tablet" with per-tier prices requires curated catalogue data (Mobilesentrix/PLP/iFixit BOM) scraped + reconciled with shop pricing-tier medians; same dependencies as SEED-2. Cannot be done as a single seed migration without first wiring the scrape worker and tier_label storage. Reported 2026-05-09 — current Repair Templates picker on the ticket detail shows "No templates yet" for the most common devices (e.g. iPhone 13). User wants every popular phone/tablet to come pre-seeded with templates such as "iPhone 13 — Screen replacement" with multiple part-tier options the tech can pick at intake:
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











- [~] WEB-FF-014 (partial). **[MED] Most list pages use `key={i}` (array index) for skeletons + import-preview rows — re-render shifts state/animations onto wrong rows.** Found in CustomerListPage.tsx:830, EstimateListPage.tsx:47,501, TicketListPage.tsx:1308,1548,1648, LeadListPage.tsx:82,442, GiftCardsListPage.tsx:223, TvDisplayPage.tsx:104,168, InvoiceListPage.tsx:225,234,253,262, plus PortalInvoicesView.tsx:133 + PortalTicketDetail.tsx:141. Skeletons are mostly fine, but the import-preview rows (CustomerListPage:830) and chart `<Cell key={i}>` mappings flicker on data change. PARTIAL-Fixer-B9 2026-04-25 — flagship CustomerListPage import-preview row swapped from `key={i}` to a content-hash composite (`vals.join('|') + '#' + i`); inner `<td>` cells now keyed `${rowKey}:${j}`. Re-parses after edit-then-re-paste no longer shift focus/animations onto the wrong row. Remaining list pages + chart `<Cell key={i}>` still pending.
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



- [~] WEB-FE-013 (PARTIAL). **[MED] App-wide tables (`CustomerListPage`, `CustomerDetailPage`, `NotificationTemplatesTab`, `SettingsPage`, `AuditLogsTab`) have zero `scope="col"` / `scope="row"` / `<caption>` — screen readers can't associate cells to headers.** *(PARTIAL Fixer-OOO 2026-04-25 — `AuditLogsTab.tsx` table now ships `scope="col"` on all 5 `<th>` cells + an sr-only `<caption>`. CustomerListPage / CustomerDetailPage / NotificationTemplatesTab / SettingsPage still pending; same pattern applies (1 line per th + 1 caption).)*
  <!-- meta: scope=web/a11y; files=packages/web/src/pages/customers/CustomerListPage.tsx:705-710,packages/web/src/pages/settings/AuditLogsTab.tsx,packages/web/src/pages/settings/NotificationTemplatesTab.tsx; fix=add-scope=col-on-th+visually-hidden-caption -->



- [~] WEB-FE-016. **[MED] Components in `components/team/*` + `components/billing/*` use `text-gray-*` exclusively (zero `dark:` variants).** `CommissionPeriodLock.tsx` 7 hits, `TicketHandoffModal.tsx` 4 hits, `MentionPicker.tsx` 4 hits, `RefundReasonPicker.tsx` 5 hits, `FinancingButton.tsx` etc. — all unreadable in dark mode and diverge from the surface-* token ramp (§project_brand_surface_ramp). Same class as FC-003/FC-004 but in shared components. (Fixer-B5 2026-04-25: RefundReasonPicker.tsx migrated to surface-* + dark:* pairs; CommissionPeriodLock/TicketHandoffModal/MentionPicker/FinancingButton still pending.)
  <!-- meta: scope=web/components; files=packages/web/src/components/team/CommissionPeriodLock.tsx:97-177,packages/web/src/components/team/TicketHandoffModal.tsx:82-112,packages/web/src/components/team/MentionPicker.tsx:56-70,packages/web/src/components/billing/RefundReasonPicker.tsx:55-78,packages/web/src/components/billing/FinancingButton.tsx:76; fix=codemod-text-gray-N-to-text-surface-N+dark:text-surface-(1000-N) -->











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






- [~] WEB-FAD-006. **[MED] `KanbanBoard.tsx:131` polls `tickets-kanban` every 30s while WS already invalidates `['tickets']` on TICKET_CREATED/UPDATED/STATUS_CHANGED/NOTE_ADDED/DELETED — no prefix-match because the kanban key is `['tickets-kanban']` (hyphen) not `['tickets', 'kanban']`.** WS map at `useWebSocket.ts:57-77` invalidates `['tickets']` on 5 ticket events but the kanban query key is `['tickets-kanban']` so WS DOESN'T touch it. Either rename to `['tickets', 'kanban']` so WS prefix-match catches it, OR drop the 30s poll and explicitly add `tickets-kanban` to the invalidation map. Same pattern likely repeats for `[tv-display]` (`TvDisplayPage.tsx:61` 30s poll, no WS link) and `[my-queue]` (`MyQueuePage.tsx:58`). <!-- PARTIAL Fixer-B24 2026-04-25: KanbanBoard renamed `['tickets-kanban']` → `['tickets', 'kanban']` (all 6 sites: useQuery + cancelQueries + getQueryData + setQueryData ×2 + invalidateQueries). WS prefix-match on `['tickets']` now catches kanban automatically. Loosened poll 30s → 60s (kept as fallback for WS-down). `[tv-display]` + `[my-queue]` siblings still pending. -->
  <!-- meta: scope=web/pages/tickets+tv+team; files=packages/web/src/pages/tickets/KanbanBoard.tsx:128-132,packages/web/src/pages/tv/TvDisplayPage.tsx:58-62,packages/web/src/pages/team/MyQueuePage.tsx:58; fix=normalize-queryKeys-to-['tickets','kanban']/['tickets','tv']/['tickets','my-queue']+drop-explicit-refetchInterval+rely-on-WS-prefix-invalidation -->





### Wave-Loop Finder-AE run 2026-04-25 — tenant + role isolation

- [~] WEB-FAE-001 (PARTIAL). **[HIGH] `PermissionBoundary` component (`components/shared/PermissionBoundary.tsx:13`) is defined but has ZERO callsites in the entire `packages/web/src` tree — gating done by ad-hoc `user?.role === 'admin'` literals scattered across 9+ files instead.** Fixer-II 2026-04-25 — adopted `PermissionBoundary` for the Settings dropdown entry in `components/layout/Header.tsx:439` (replaced `(user?.role === 'admin' || user?.role === 'manager') &&` with `<PermissionBoundary roles={['admin', 'manager']}>`). Component is no longer orphan. Remaining ad-hoc role checks pending a follow-up sweep: `Sidebar.tsx:147` (used in nav-filter `.map` → boolean, harder to wrap as JSX — wants a `useHasRole(roles)` hook), `DashboardPage.tsx:1626,1684`, `DangerZoneTab.tsx:35`, `BulkSmsModal.tsx:18`, `SettingsPage.tsx:1656,1761`, `ReportsPage.tsx:632`. PARTIAL FIXED-by-Fixer-A20 2026-04-25: authored `packages/web/src/hooks/useHasRole.ts` (boolean counterpart to `<PermissionBoundary>`, same auth-store source-of-truth, supports `string | string[]`). Adopted in two of the listed sites: `DashboardPage.tsx` (`showFinancials = useHasRole(['admin', 'manager'])`, replaces `role === 'admin' || role === 'manager'`) + `DangerZoneTab.tsx` (`isAdmin = useHasRole('admin')`, drops the local `useAuthStore` import + `user?.role === 'admin'` literal). Hook is now available so the remaining `.map` filters in Sidebar + `disabled`-style boolean gates can adopt it without contortions.
  <!-- meta: scope=web/components/shared+pages; files=packages/web/src/components/shared/PermissionBoundary.tsx:13,packages/web/src/components/layout/Header.tsx:439,packages/web/src/components/layout/Sidebar.tsx:147,packages/web/src/pages/dashboard/DashboardPage.tsx:1626,1684,packages/web/src/pages/settings/DangerZoneTab.tsx:35; fix=replace-ad-hoc-role-checks-with-PermissionBoundary+author-useHasRole-hook+single-source-truth -->


- [~] WEB-FAE-003 (PARTIAL). **[HIGH] `localStorage` keys are NOT user/tenant-scoped — survive logout and bleed across accounts on the same browser.** Fixer-II 2026-04-25 — fixed the highest-PII key (`recent_views`, the only one carrying customer/ticket labels): exported `recentViewsKey(userId)` from `components/layout/Sidebar.tsx` returning `recent_views:u${userId}`, switched the Sidebar reader + both writers (`pages/customers/CustomerDetailPage.tsx:120-137`, `pages/tickets/TicketDetailPage.tsx:362`) to the namespaced key, and added a module-level `bizarre-crm:auth-cleared` listener in `Sidebar.tsx` that wipes the legacy unscoped `recent_views` key plus every `recent_views:*` entry on logout/switchUser/forced-logout. The User type has no `tenant_id` (`packages/shared/src/types/employee.ts:1`), so per-`user.id` is the strongest scope expressible client-side; cross-tenant follows for free since one user.id can't span tenants. Still pending the same treatment: `useDismissible.ts:34` per-banner flags, `uiStore.ts:39` `sidebarCollapsed`, `ImpersonationBanner.tsx:17` IMPERSONATION_KEY (lower-PII but same isolation concern). PARTIAL FIXED-by-Fixer-A20 2026-04-25: extended the `bizarre-crm:auth-cleared` sweep in `packages/web/src/main.tsx` to wipe every `tutorial.*` localStorage key (covers `tutorial.all.dismissed` + `tutorial.<flowId>.dismissed`); a previous user's "skip all" decision no longer suppresses onboarding for the next sign-in on a shared kiosk PC. Same listener already nukes `recent_views` + `draft_*` so this co-locates the tutorial-flag cleanup with the existing PII purge.
  <!-- meta: scope=web/components+hooks+stores; files=packages/web/src/components/layout/Sidebar.tsx:259,packages/web/src/components/onboarding/tutorialFlows.ts:225,packages/web/src/hooks/useDismissible.ts:34,packages/web/src/components/ImpersonationBanner.tsx:17; fix=add-auth-cleared-listener-purges-non-allowlist-keys+OR-namespace-keys-by-tenant_id+user_id -->



- [!] WEB-FAE-006. **[MED] Hardcoded role lists drift from server's canonical `shared/constants/permissions` — comment at `Sidebar.tsx:141` literally says "shared ROLE_PERMISSIONS grants manager every permission except a handful" but the client doesn't import that constant; it just reproduces `userRole === 'admin' || userRole === 'manager'` inline.** `Header.tsx:439` checks `'admin' || 'manager'`, `DashboardPage.tsx:1626` checks `'admin' || 'manager'`, `DangerZoneTab.tsx:35` checks only `'admin'`, `BulkSmsModal.tsx:18` says "backend enforces req.user.role === 'admin'" (only one consistent), `SettingsPage.tsx:1762` lists `'manager'`+`['Tickets', 'Customers', 'POS']`+`'technician'` — all hand-rolled. If server adds an `'owner'` or `'kiosk'` role, every callsite drifts silently. Import `ROLE_PERMISSIONS` from `@bizarre-crm/shared` and derive role gates from a single map. **[AUTOLOOP-T1 BLOCKED: 15-file role-check codemod, exceeds limit.]**
  <!-- meta: scope=web/components+pages; files=packages/web/src/components/layout/Header.tsx:439,packages/web/src/components/layout/Sidebar.tsx:147,packages/web/src/pages/settings/SettingsPage.tsx:1761-1762,packages/web/src/pages/dashboard/DashboardPage.tsx:1626; fix=import-ROLE_PERMISSIONS-from-shared+derive-isAdminOrManager-from-canonical-map+add-eslint-rule-no-hardcoded-role-string-literal -->





---


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

- [!] WEB-UIUX-241. **[MINOR] StepShopType "Skip" advances without recording intent.** BLOCKED 2026-05-07 — critique: valid, but no safe existing client/server write path exists inside the allowed ownership. `POST /onboarding/set-shop-type` records/audits real selections only, `PATCH /onboarding/state` audits only unrelated boolean flags, and `PUT /settings/config` can audit `shop_type` but that key is consumed by repair-pricing seed logic, so storing a synthetic `skipped` value would corrupt a real contract. Needs a server-owned onboarding skip event/field before the UI can record this honestly while remaining non-blocking.
  `packages/web/src/pages/setup/steps/StepShopType.tsx:106-109`

  `packages/web/src/pages/setup/steps/StepImportHandoff.tsx:62-70`

  `packages/web/src/pages/setup/steps/StepFirstLogin.tsx:78-86`

  `packages/web/src/pages/setup/steps/StepForcePassword.tsx:25-33`
  <!-- meta: fix=use-zxcvbn-or-length-bonus -->

  Files: StepSignup.tsx:37-50 vs StepForcePassword.tsx:25-33
  <!-- meta: fix=extract-shared-gradePassword-helper -->

  `packages/web/src/pages/setup/steps/StepSignup.tsx:88-125`

  `packages/web/src/pages/setup/steps/StepSignup.tsx:73-118,132-145,356-361`

  `packages/web/src/pages/setup/steps/StepSignup.tsx:152-159`

  `packages/web/src/pages/setup/steps/StepTwoFactorSetup.tsx:125-131`

  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:181-194`

  `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx:214-218,388-396`

  `packages/web/src/pages/setup/ExtrasHub.tsx`
  <!-- meta: fix=delete-or-document-as-fallback -->

#### Onboarding

  `packages/web/src/components/onboarding/SpotlightCoach.tsx:422-429`
  <!-- meta: fix=add-Re-enable-toggle-in-Settings-confirm-before-nuking -->

  `packages/web/src/components/onboarding/SpotlightCoach.tsx:99-112`
  <!-- meta: fix=use-svg-mask-with-rect-cutout -->

  `packages/web/src/components/onboarding/DailyNudge.tsx:130-132`

  `packages/web/src/components/onboarding/DailyNudge.tsx:100-103`

  `packages/web/src/components/onboarding/GettingStartedWidget.tsx:166-205`

#### Print / TV / Photo Capture

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:127-287`

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:127-287`

  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:14-27`
  <!-- meta: fix=migrate-to-per-action-JWT -->

  `packages/web/src/pages/print/PrintPage.tsx:1051-1063`

  `packages/web/src/pages/print/PrintPage.tsx:231,402,429,672,712,902`

  `packages/web/src/pages/print/PrintPage.tsx:1022-1038`

  `packages/web/src/pages/tv/TvDisplayPage.tsx:128-133`

  `packages/web/src/pages/tv/TvDisplayPage.tsx:191-214`
  <!-- meta: fix=add-config-toggle-or-show-device-class-only -->

  `packages/web/src/pages/tv/TvDisplayPage.tsx:78-84`

#### Reports Sub-Components

  `packages/web/src/pages/reports/components/*.tsx`
  <!-- meta: fix=define-chart-CSS-vars-in-design-system -->

  <!-- meta: fix=extract-useReportQuery-hook -->

  `packages/web/src/pages/reports/components/DeviceModelsTab.tsx:75`

  `CustomerAcquisitionTab.tsx:81`, `TechnicianHoursTab.tsx:86`

#### Tickets Components

  `packages/web/src/components/tickets/BenchTimer.tsx:218-263`

  `packages/web/src/components/tickets/DefectReporterButton.tsx:94-99`

  `packages/web/src/components/tickets/QcSignOffModal.tsx:289-301`
  <!-- meta: fix=multiply-backing-store-by-devicePixelRatio -->

#### Team Components

  `packages/web/src/components/team/CommissionPeriodLock.tsx:126,182-244`

  `packages/web/src/components/team/CommissionPeriodLock.tsx:183-243`

  `packages/web/src/components/team/MentionPicker.tsx:78-83`

  `packages/web/src/components/team/TicketHandoffModal.tsx:84-90`

  `packages/web/src/components/team/MentionPicker.tsx:91-99`

  `packages/web/src/components/team/TicketHandoffModal.tsx:114-125`

  Cache: `['employees','simple']` vs `['employees','simple-mention']`

#### Cross-Cutting (Pass 4)

  <!-- meta: fix=canonical-Modal-or-adopt-Radix-or-HeadlessUI -->

  StepWelcome:105, StepStoreInfo:200, StepShopType:215 + many more


### Web UI/UX Audit — Pass 5 (2026-05-05, keyboard shortcuts + error boundary + z-index)

#### Keyboard Shortcuts (WCAG 2.1.4)

  `packages/web/src/components/layout/AppShell.tsx:108-128`
  `packages/web/src/components/layout/Header.tsx:286`
  <!-- meta: fix=add-shortcut-toggle-in-Settings-Accessibility-tab -->

  <!-- meta: fix=add-aria-keyshortcuts=F2-on-POS-link-etc -->

  `packages/web/src/pages/settings/components/SettingsGlobalSearch.tsx:55-67` vs `components/layout/Header.tsx:281`
  <!-- meta: fix=stop-propagation-or-coordinate-via-uiStore -->

#### Error Boundary Coverage

  `packages/web/src/main.tsx:364`, `packages/web/src/App.tsx:443`
  <!-- meta: fix=wrap-each-lazy-route-in-PageErrorBoundary -->

#### Z-Index Stacking War

  Pattern across web/src
  <!-- meta: fix=define-z-index-scale-in-design-tokens-modal:50-toast:60-banner:40 -->

#### Cross-Cutting Pass 5

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

- [!] WEB-UIUX-433. **[MINOR usability] No way to refund directly from POS sale — operator must navigate to Invoices → find invoice → open detail → click Credit Note.** ~5 clicks for what should be 2-tap operation in-store. L1, L5. **[AUTOLOOP-T18 BLOCKED: ReturnModal exists + hotkeybound, but surfacing button on SuccessScreen requires prop-threading across SuccessScreen+UnifiedPosPage; exceeds single-file edit.]**
  Cross-reference: `packages/web/src/pages/unified-pos/` no refund affordance from past-sales view
  <!-- meta: fix=add-Refund-button-to-recent-sales-list-in-POS -->

#### Cross-Cutting (Pass 8)

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

- [!] WEB-UIUX-643. **[MAJOR] Stocktake quick-scan default = "current stock + 1" — silently increments.** Scanning twice = +2. No "confirm existing count" mode. L7, L8. **BLOCKED 2026-05-10: quick-scan increments counted_qty by 1 per scan, which is the documented behavior (`counted = existingCount.counted_qty + 1` at StocktakePage.tsx:239). Adding a "confirm-existing" mode requires a new UI toggle + mutation variant + cashier-training; feature-scope.**
  `packages/web/src/pages/inventory/StocktakePage.tsx:174-181`

  `packages/web/src/pages/inventory/StocktakePage.tsx:378-400`

- [!] WEB-UIUX-645. **[MAJOR] Serial number status flip has zero side effects.** `sold→returned` doesn't increment in_stock, no invoice back-link enforced, no warning. L13, L16. **BLOCKED 2026-05-10: side-effect chain needs server transaction (status flip + in_stock increment + invoice link check) — schema + endpoint redesign.**
  `packages/web/src/pages/inventory/SerialNumbersPage.tsx:74-81,186-198`

- [!] WEB-UIUX-653. **[MAJOR] No per-device pickup state — ticket-level "Ready for Pickup" all-or-nothing.** Multi-device ticket: device 1 done, device 2 waits parts → no UI for partial pickup. L5, L11. **[AUTOLOOP-T30 BLOCKED: per-device pickup state requires server schema (per-device status field) + multi-component UI.]**
  `packages/web/src/pages/tickets/TicketDevices.tsx:797-1149`

- [!] WEB-UIUX-660. **[MAJOR · BLOCKED] No abandoned-ticket workflow.** 90-day Ready-for-Pickup gets zero escalation lane (lumped with 7-day stale tickets in dashboard). No SMS cadence, no liability disclaimer, no auto-write-off. L5. **BLOCKED 2026-05-10: feature-scope — SMS cadence + liability template + write-off rule + dashboard lane.**
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

  `packages/web/src/pages/tickets/TicketDevices.tsx:820-823,927-930`

#### ED10: Search/Filter Weirdness

- [!] WEB-UIUX-667. **[MINOR] Filter persistence inconsistent — survives back-button but resets on side-nav menu click.** L5. **[AUTOLOOP-T30 BLOCKED: app-wide — every list page uses URL search params; sidebar NavLinks use bare paths stripping query state. Cross-cutting fix needed.]**

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

- [!] WEB-UIUX-704. **[BLOCKER] No web UI for `creditNotes.routes.ts` collection endpoints.** Server exposes GET `/credit-notes`, GET `/credit-notes/:id`, POST `/credit-notes/:id/apply` (use credit), POST `/credit-notes/:id/void`. Web only calls invoice-scoped POST `/invoices/:id/credit-note`. No list page, no detail page, no apply-to-future-invoice flow, no void path for mistaken credit notes. L3, L8. **BLOCKED 2026-05-11: requires new web pages (list/detail/apply) — multi-page feature scope. Server endpoints are stable. Defer to credit-notes UI sprint.**
  `packages/server/src/routes/creditNotes.routes.ts:63,135,237,318`
  <!-- meta: fix=add-creditNotesApi+CreditNotesListPage+apply-modal+void-mutation -->

  `packages/web/src/api/endpoints.ts:749-761`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`
  <!-- meta: fix=wrap-button-in-PermissionBoundary+invoices.credit_note -->

#### Major — State visibility, recovery, integration

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:474-548`
  <!-- meta: fix=add-Credit-Notes-section-below-Payment-Timeline+invoice.credit_notes-from-server -->

  `packages/web/src/pages/invoices/InvoiceListPage.tsx:33,41` `packages/web/src/pages/customers/CustomerDetailPage.tsx:1685`
  `packages/server/src/services/repairShoprImport.ts:773-774` `packages/server/src/services/repairDeskImport.ts:1290`
  <!-- meta: fix=either-set-refunded-on-original-when-fully-credited-OR-remove-dead-color -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:807-817` (Void) vs `737-805` (CreditNote)
  <!-- meta: fix=ConfirmDialog-with-requireTyping-amount-OR-add-undoableAction-window -->

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

- [!] WEB-UIUX-882. **[MAJOR] Communications tab on customer page strips call affordances — no duration, no recording-play, no transcript link.** 200% regression vs standalone CommunicationPage. L11, L4. **[AUTOLOOP-T41 BLOCKED: customer Communications call affordances need server SQL + client type+render; multi-component.]**
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1740-1785`



  **STATUS: BLOCKED** — deferred until messaging (email/SMS) infrastructure work begins (per user 2026-05-05).

- [!] WEB-UIUX-886. **[MINOR] Note-taking is slow — customer-level notes via `comments` textarea (free-form string), no "+ Add Note", no timestamp/author.** L7, L13. **[AUTOLOOP-T41 BLOCKED: structured customer notes (timestamp+author+append) need new customer_notes server table + routes; schema migration required first.]**

#### DATA1: Data Flow Consistency

  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:228-230`

  `packages/web/src/pages/unified-pos/ProductsTab.tsx:40`

  `packages/web/src/pages/inventory/StocktakePage.tsx:141-145`

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:553-555`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/communications/CommunicationPage.tsx:50,68,91,1440,1651-1655`

  `packages/web/src/pages/portal/portalApi.ts:194-195`

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1154-1157`


- [!] WEB-UIUX-895. **[MAJOR] Print page renders LIVE customer/store data on re-print of historical receipts.** Renamed customer "J Doe" → "Jane Doe-Smith" → reprint of 6-month-old receipt now says new name. Tax/legal expects point-in-time snapshots. L13, L16. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs an invoice point-in-time snapshot (customer_name/address/store_name/tax_jurisdiction) populated at invoice creation + migration + read-fallback to live row for legacy invoices. Multi-component schema change across pos.routes/print + new migration.]**
  `packages/web/src/pages/print/PrintPage.tsx:195-241,451-549,763-810,910-941`



#### SEC1: Security UX

  `packages/web/src/pages/communications/CommunicationPage.tsx:1546-1554`

  `packages/web/src/pages/unified-pos/store.ts:126-127,253-254,268,290-303`

  `packages/web/src/components/layout/Header.tsx:642-728`

  `packages/web/src/pages/customers/CustomerListPage.tsx:308-354,586-589`


  `packages/web/src/api/client.ts:294-313,361-370`


  `packages/web/src/pages/settings/DangerZoneTab.tsx:32-83`

  `packages/web/src/pages/settings/AuditLogsTab.tsx:60-70,161`

- [!] WEB-UIUX-911. **[MAJOR] 30+ `role="dialog"` sites lack focus-restore on close.** Only ConfirmDialog implements lastFocused capture/restore. PinModal, UpgradeModal, QuickSmsModal, CheckoutModal, WidgetCustomizeModal, SwitchUserModal, ReviewPromptModal, 5 InventoryListPage modals — focus drops to body. L12. **STATUS: BLOCKED — codemod across 30+ dialog sites; useFocusTrap hook already capture/restores so fix is calling it everywhere**

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

- [!] WEB-UIUX-937. **[BLOCKER] `/blockchyp/status` reports configured-state, NEVER reachability.** No "online/last-heartbeat" field. Configured-but-offline terminal silently passes gate, fails during charge. L8, L11. **STATUS: BLOCKED — needs server reachability heartbeat field on /blockchyp/status; backend infra change, defer to terminal sprint**
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:170-178`

  `packages/web/src/pages/settings/BlockChypSettings.tsx:282-296`

  `packages/web/src/pages/catalog/CatalogPage.tsx:27-42`

  `packages/web/src/pages/catalog/CatalogPage.tsx:660-676`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).


  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/settings/SmsVoiceSettings.tsx:235-262`

  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).


### Web UI/UX Audit — Pass 11 (2026-05-05, flow walk: approve estimate — server-vs-client gaps + customer e-sign)

Walk of the "Approve Estimate" flow: staff create → send-by-SMS → customer (or staff) approves → optional convert-to-ticket. Cross-checked server `estimates.routes.ts` + `estimateSign.routes.ts` (sign-URL + signature-capture) + `portal.routes.ts /estimates/:id/approve` against client `EstimateListPage`, `EstimateDetailPage`, `PortalEstimatesView`. Largest gap: server has full e-sign infra (`estimate_signatures` table, sign-token issuance, public signer UI) **mobile-only** — desktop flow flips `status='approved'` with zero name/IP/UA capture. Compliance/audit gap.

#### Blockers — Status drift, missing audit trail, unwired endpoints

  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:16-22`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:17-24`
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:158-164`
  <!-- meta: fix=add-signed-color-everywhere+filter-pill+detail-badge -->

  `packages/server/src/routes/portal.routes.ts:1437-1478`
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:132-139`
  <!-- meta: fix=portal-Approve-must-route-through-signed-token-flow-OR-capture-signer-name-+-IP-+-UA-server-side -->

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

- [!] WEB-UIUX-979. **[NIT] Approve mutation loading state coexists with Reject loading state via shared `anyMutationPending` — clicking Approve disables Reject too, fine — but no per-button skeleton cue beyond `<Loader2>` icon swap. Reject button visually identical mid-Approve.** L11. **[AUTOLOOP-T49 BLOCKED 2026-05-11: nit-level polish; per-button skeleton cue requires deciding a button-level skeleton design pattern (subtle stripe vs reduced opacity vs disabled-with-progress) and applying it consistently across the action button row.]**
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

- [!] WEB-UIUX-988. **[MAJOR] IssueModal collects no `customer_id` — server accepts it, list endpoint LEFT-JOINs customers, both wasted.** `giftCards.routes.ts:128` joins `customers c ON c.id = gc.customer_id`, returns `c.first_name, c.last_name`. UI's `IssueFormState` has only amount/recipient_name/recipient_email/expires_at. Operator selling to existing customer with full profile must retype name. Card never appears on customer's profile. L1, L4. **STATUS: BLOCKED — needs new CustomerPicker component + customer_id wiring on issue + customer link on list/detail; defer to gift-card hardening sprint**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:38-43,86-91,104-109`
  <!-- meta: fix=add-CustomerPicker-component+pass-customer_id+show-customer-link-on-list+detail -->

  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:177-227`

- [!] WEB-UIUX-1009. **[MINOR] List status filter chip not visually grouped with keyword search — separate `<select>` is plain styled, no chip pattern.** Most filter UIs in this app use chip toggles (LeadPipelinePage etc). Inconsistency. L9. **[AUTOLOOP-T49 BLOCKED 2026-05-11: chip refactor needs a shared FilterChipGroup component to avoid duplicating LeadPipelinePage's bespoke styling across all list pages. Not a one-page change.]**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:321-330`

- [!] WEB-UIUX-1013. **[MINOR] Lookup endpoint rate-limit error 429 never surfaced to operator UI** — `giftCardApi.lookup` not called, but if/when wired, generic-onError handlers won't translate "Too many lookup attempts" into a meaningful "wait 60s" countdown. Pre-emptive: lookup UI should special-case 429 + show retry-after. L8. **[AUTOLOOP-T49 BLOCKED 2026-05-11: pre-emptive item — giftCardApi.lookup has 0 callers (per the audit note); no real UI to retrofit until the lookup flow itself ships.]**
  `packages/server/src/routes/giftCards.routes.ts:188-197`

- [!] WEB-UIUX-1015. **[NIT] Issue success modal Done button color `bg-primary-600 text-primary-950` — relies on tenant theme; in dark theme on mobile, `text-primary-950` (very dark) on `bg-primary-600` may have <3:1 contrast depending on primary hue.** L12. **[AUTOLOOP-T49 BLOCKED 2026-05-11: contrast verification needs sampled tenant primary hues + WCAG audit; same pattern appears on every primary-styled button. App-wide pass, not a per-page nit.]**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:147`

  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:138-144`


### Web UI/UX Audit — Pass 13 (2026-05-05, flow walk: Process Refund — issue, approve, return, store credit)

Walk of "Process Refund" end-to-end. Server `/api/v1/refunds` (mounted at `index.ts:1603`) exposes a full pending→completed/declined refund state-machine with idempotency, role gates, atomic capture-state checks, commission reversal, and store-credit upsert. Client surface: zero. `endpoints.ts` declares 46 `*Api` namespaces; **no `refundApi` exists**. Three parallel write paths (`POST /refunds`, `POST /invoices/:id/credit-note`, `POST /pos/return`) — only path #2 wired to UI (the InvoiceDetail "Credit Note" button). The pending-refund approval queue is invisible. Cross-checked `refunds.routes.ts`, `pos.routes.ts:2492-2637`, `invoices.routes.ts:1159-1318`, `InvoiceDetailPage.tsx`, `RefundReasonPicker.tsx`, `endpoints.ts`, `Sidebar.tsx`, `CommandPalette.tsx`, `App.tsx`, `UnifiedPosPage.tsx`, `CustomerDetailPage.tsx`.

#### Blockers — Refund flow non-existent in UI; approval workflow defeated

  `packages/web/src/api/endpoints.ts:35-1492 (no refundApi exported)`
  `packages/server/src/routes/refunds.routes.ts:73-546`
  `packages/server/src/index.ts:1603`
  <!-- meta: fix=add-refundApi-namespace+wire-list+approve+decline+create+credits-endpoints -->

- [!] WEB-UIUX-1020. **[BLOCKER] POS has no return / refund flow despite `posApi.return` declared with idempotency.** `endpoints.ts:753-761` exposes `posApi.return` with X-Idempotency-Key headers. `grep "posApi.return" packages/web/src` → 0 callers. Server `/pos/return` (`pos.routes.ts:2492-2637`) creates negative invoice + restores stock + writes refund row at status='completed'. Cashier with returning customer must (a) navigate to invoice detail, (b) click Credit Note (different flow!), (c) manually open drawer, (d) hand back cash — no scan-returned-item, no per-line-item return UI. L1, L4, L8. **[AUTOLOOP-T49 BLOCKED 2026-05-11: full return-flow UI in POS (scan-original-invoice → per-line-item return picker → restock/no-restock toggle → refund method selector → drawer-open trigger) is a multi-step modal feature. Server `/pos/return` ready; needs UX pass on the cashier flow.]**
  `packages/web/src/api/endpoints.ts:749-761`
  `packages/server/src/routes/pos.routes.ts:2492-2637`

- [!] WEB-UIUX-1021. **[BLOCKER] `/pos/return` writes refund row directly at `status='completed'` — bypasses dual-control approval entirely.** `pos.routes.ts:2618-2621` `INSERT INTO refunds ... status='completed'`. Refunds.routes.ts `POST /` always inserts `status='pending'` then requires admin approve. The cashier path (when wired) skips that gate. Defeats the entire SEC-H28 atomic-approve design + SEC-H29 idempotency + EM1 commission reversal that fires only on `/approve`. Manager dual-control becomes opt-in based on which write path the cashier happens to take. L16, L4. **STATUS: BLOCKED — server pos.routes.ts dual-control policy change requires audit + role-gate review; defer to refunds sprint**
  `packages/server/src/routes/pos.routes.ts:2618-2621`
  `packages/server/src/routes/refunds.routes.ts:107,229-234`
  <!-- meta: fix=force-pos-return-to-status=pending-OR-require-elevated-role-at-route-level -->

  `packages/server/src/routes/invoices.routes.ts:1162-1317`
  `packages/server/src/routes/pos.routes.ts:2496-2637`
  <!-- meta: fix=invoke-reverseCommission-from-credit-note-and-pos-return-paths-with-original-invoice-fraction -->

  `packages/web/src/pages/customers/CustomerDetailPage.tsx`
  `packages/server/src/routes/refunds.routes.ts:439-525`

- [!] WEB-UIUX-1025. **[BLOCKER] No way to issue a CASH refund — the only wired path ("Credit Note") creates a negative invoice but does not move money out.** Customer wants a $50 cash refund from till. Operator clicks "Credit Note" on InvoiceDetail → server creates `CRN-####` invoice with `amount_paid=0`, decrements original invoice's amount_due. No drawer pop, no `cash_register` row written, no `payments` row showing $-50 paid out. Cashier hands back $50 from drawer with no system record of the cash leaving. End-of-day Z-report won't reconcile. L1, L4, L8, L16. **STATUS: BLOCKED — Cash Refund tender requires drawer-pop + cash_register row + payments row writes; multi-component, server change; defer to refunds sprint**
  `packages/server/src/routes/invoices.routes.ts:1162-1317`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311,737-805`
  <!-- meta: fix=add-Cash-Refund-tender-on-credit-note-modal+post-cashRegister-row+open-drawer -->

#### Major — Truthfulness, hierarchy, recovery, mismatch with server

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377-380`
  <!-- meta: fix=server-must-also-INSERT-INTO-refunds-on-credit-note-OR-rename-button-to-Issue-Credit-Note-(no-money-back) -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311`
  `packages/server/src/routes/invoices.routes.ts:1186-1202`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:776-778`
  <!-- meta: fix=fetch-invoice.related_credit_notes-and-subtract-from-displayed-cap -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-176`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:393-588`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:328-423`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-177`
  `packages/server/src/routes/invoices.routes.ts:1259-1302`

  `packages/web/src/components/billing/RefundReasonPicker.tsx:42-50`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-167`

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1685`

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:768,776-778`

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

- [!] WEB-UIUX-1047. **[MINOR] Z-Report (`ZReportModal.tsx:204`) shows "Refunds" total in cents, but no drill-down link to refund detail and no per-tender breakdown (cash refunds vs card refunds).** End-of-day reconciliation is summary-only. L8, L1. **[AUTOLOOP-T49 BLOCKED 2026-05-11: server Z-Report needs per-tender refund SUM (GROUP BY method) + drill-down route /refunds?date=... — depends on UIUX-1018 (no /refunds route exists yet).]**
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:204`

- [!] WEB-UIUX-1048. **[MINOR] BlockChyp settings page references "refund" but no card-refund-back-to-original-tender flow is wired in any UI.** `blockchypApi` likely has no `refund(transactionId)` method despite the processor supporting it. Card customers expecting refund back to card get cash or "credit on file" instead. L8. **STATUS: BLOCKED — needs new server-side card-refund route (BlockChyp refund API call) + audit-log + 5+ files; defer to refunds sprint**
  `packages/web/src/pages/settings/BlockChypSettings.tsx`

- [!] WEB-UIUX-1063. **[MAJOR] Header label "Memberships" but route+filename "subscriptions"; CommandPalette aliases both.** `SubscriptionsListPage.tsx:180` reads "Memberships". Route `/subscriptions` (`App.tsx:540`). CommandPalette entry `display: 'Subscriptions'` with aliases `['memberships','recurring']` (`CommandPalette.tsx:72`). Three names for one feature. Customer-profile card uses third term "Membership" (singular). Support tickets ambiguous; new admins searching for the wrong word miss it. Pick one (industry: Stripe → Subscriptions; Shopify/Recharge → Subscriptions; Squarespace/Wix → Memberships when consumer-facing). For repair-shop B2C this is consumer-facing → Memberships, then rename URL/file/component. L2. **STATUS: BLOCKED — file/route/component rename across many files + 301 redirect needs design review; defer to memberships sprint**
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:180`
  `packages/web/src/App.tsx:540`
  <!-- meta: fix=rename-route-to-/memberships+keep-/subscriptions-as-301-redirect+rename-file+update-CommandPalette-display -->

  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:199-206`
  <!-- meta: fix=change-CTA-to-link-to-/customers-with-text="Open-a-customer-profile-and-tap-Enroll-in-Membership"-also-add-Configure-Tiers-secondary-link -->

  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:257-286`
  <!-- meta: fix=add-Pause/Resume-buttons-to-row-action-cell+row-level-state+optional-bulk-pause-checkbox-selection -->

  `packages/web/src/pages/customers/CustomerDetailPage.tsx:913-920,990-997`
  <!-- meta: fix=replace-pauseMut.mutate()-with-prompt(reason)-or-modal-with-preset-reasons[customer-request|payment-fail|seasonal|other]+pass-as-body -->

- [!] WEB-UIUX-1075. **[MINOR] Subscription list missing primary "Add subscription / Enroll customer" action.** Page is the recurring-revenue dashboard yet has no entry-point to enrolment workflow — admin must remember "go to a customer profile". Industry baseline: Stripe Dashboard → Subscriptions → Create subscription opens customer-picker first. L1, L8. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs a customer-picker → plan-picker → confirm modal that reuses CustomerSelector + plansApi.list. Spec needs to nail whether "Add subscription" should also seed a first invoice or wait for the cycle.]**
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:175-189`
  <!-- meta: fix=add-primary-button-New-subscription-opens-modal-CustomerPicker+TierPicker+CardOnFile-or-PaymentLink -->

  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:130-134`
  <!-- meta: fix=destructure-only-the-args-actually-used -->

#### Nit — visual contrast

  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:47,201`
  <!-- meta: fix=upgrade-to-text-surface-400-icon+text-surface-600-badge-text -->

### Web UI/UX Audit — Pass 15 (2026-05-05, flow walk: QC Sign-Off — bench QC modal, server gates, admin surfaces)

Walked end-to-end: tech finishes repair → opens TicketDetail → clicks green "QC sign-off" button → fills checklist + photo + signature + signs → ticket status moves on. Cross-checked `packages/web/src/components/tickets/QcSignOffModal.tsx`, `packages/web/src/pages/tickets/TicketDetailPage.tsx:32,390,591-597,649-658`, `packages/server/src/routes/bench.routes.ts:255-275,596-910`, `packages/server/src/db/migrations/088_bench_timer_qc_defects.sql`, `packages/server/src/services/ticketStatus.ts`, `packages/web/src/api/endpoints.ts:1355-1375`, `packages/web/src/pages/settings/` (no Bench/QC page exists).

#### Blocker — broken contract, unwired status, missing admin surfaces

- [!] WEB-UIUX-1089. **[MAJOR] Signed sign-off is not printable / emailable / PDF-exportable — customer never receives a copy.** Migration 088 stores signature + photo + checklist results, but no `/qc/sign-off/:id/pdf` route, no print template, no `Email customer` button on TicketDetail post-sign. Customer who was promised "we'll send you the QC certificate" gets nothing. L1, L4, L8. **STATUS: BLOCKED — needs new /qc/queue page + Sidebar badge + LEFT-JOIN-IS-NULL query; multi-component, defer to QC sprint**
  `packages/server/src/routes/bench.routes.ts:703-910`
  <!-- meta: fix=add-GET-/qc/sign-off/:id/pdf-uses-existing-pdf-pipeline+after-success-toast-render-button-Send-to-customer-emails-PDF -->

- [!] WEB-UIUX-1090. **[MAJOR] Photo `accept` excludes HEIC/HEIF — iPhone Safari users blocked from camera roll.** `QcSignOffModal.tsx:255` `accept="image/jpeg,image/png,image/webp"`. iOS default capture is HEIC. Tech opens picker, sees photos greyed out, has no in-app guidance to convert. `ALLOWED_MIMES` server-side likely also rejects HEIC (verify in `bench.routes.ts:130-132`). L1, L8. **[AUTOLOOP-T49 BLOCKED 2026-05-11: client accept already includes image/heic,image/heif; server `IMAGE_UPLOAD_MIME_TYPES` (imageUploadPolicy.ts:1) still rejects them and the error copy says "HEIC/HEIF need server-side conversion first". Real fix needs sharp/libheif HEIC → JPEG transcode in the upload pipeline before persistence. Multi-component.]**
  `packages/web/src/components/tickets/QcSignOffModal.tsx:252-258`
  <!-- meta: fix=add-image/heic+image/heif-to-accept+verify-server-ALLOWED_MIMES-or-add-client-side-heic-to-jpeg-conversion-via-heic2any -->

  `packages/web/src/components/tickets/QcSignOffModal.tsx:252-258`
  <!-- meta: fix=add-capture="environment"-attr+keep-fallback-to-picker-when-no-camera -->

- [!] WEB-UIUX-1092. **[MAJOR] Single working-photo only; no before/after, no defect-marker overlay, no multi-photo.** Repair shops universally document "before" + "after" — small claims / warranty disputes hinge on the pair. `working_photo_path` column is scalar (`088_bench_timer_qc_defects.sql:79`); UI has one slot. Operator who wants to document multiple angles or attach a video can't. L1, L4. **[AUTOLOOP-T49 BLOCKED 2026-05-11: requires new `qc_sign_off_photos` table (qc_sign_off_id, path, ord, label) + migration + multi-file upload + UI gallery + retain `working_photo_path` as legacy single-slot fallback. Multi-component schema change.]**
  `packages/web/src/components/tickets/QcSignOffModal.tsx:248-285`
  <!-- meta: fix=schema-add-qc_sign_off_photos-table-(sign_off_id,path,kind:before|after|other)+UI-multi-upload+server-multipart-array -->

- [!] WEB-UIUX-1127. **[MAJOR] "New Ticket" link from TicketListPage routes to POS surface, not a ticket-creation form.** `TicketListPage.tsx:1205-1211` `<Link to="/tickets/new">New Ticket</Link>` → `App.tsx:483` `<Route path="/tickets/new" element={<UnifiedPosPage />} />`. User clicks "New Ticket", lands on Unified POS — three tabs (Repairs / Products / Misc), Cash Drawer widget, "Open Drawer" button, Cash In/Out controls, Z-Report — none of which a user creating a ticket needs. Tab defaults to `repairs` (`store.ts:247`) but URL/intent mismatch is unfixed: bookmarking `/tickets/new` always lands in cash-drawer chrome. Consider either a dedicated ticket-creation route that hides POS-only chrome OR rename the button + URL to "New Sale / Repair". L3 route correctness, L6 discoverability. **STATUS: BLOCKED — needs route restructure (/tickets/new on dedicated stripped POS shell vs full POS); design decision; defer to POS sprint**
  `packages/web/src/pages/tickets/TicketListPage.tsx:1205-1211`
  `packages/web/src/App.tsx:483`
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:375-422`
  <!-- meta: fix=`/tickets/new`-renders-stripped-shell:LeftPanel+RepairsTab+`Create-Ticket`-only;-no-Products/Misc-tabs;-no-Cash-Drawer-Widget;-no-Open-Drawer-button -->

  `packages/web/src/pages/unified-pos/BottomActions.tsx:174-181,215-221,280,402-416,528-531`
  <!-- meta: fix=gate-bypass-behind-PinModal('manager'-or-'pos_require_pin_signature_skip')+audit-log-the-skip-with-userId+ticketId -->

  `packages/web/src/pages/unified-pos/BottomActions.tsx:448-464`
  <!-- meta: fix=disabled+={!customer}+title='Select-a-customer-first'+onClick-fallback-scrollIntoView-on-customer-search-input -->

  `packages/web/src/pages/unified-pos/BottomActions.tsx:429-443`
  <!-- meta: fix=add-pos_require_pin_drawer-setting+gate-onClick-behind-PinModal-when-set+server-side-log-cash_drawer_opens(user_id,reason,opened_at) -->

  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:48-58`
  <!-- meta: fix=if-cart.length>0||customer-non-null-then-confirm('Leave-and-discard-current-ticket?')-or-stash-draft-in-localStorage+restore-on-return -->

  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:184-296`
  <!-- meta: fix=add-Send-Drop-off-Confirmation-(SMS+Email)-buttons-in-the-isTicketOnly-branch+wire-to-existing-smsApi.send/notificationApi.sendReceipt(entity_type:'ticket',entity_id) -->

  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:143-165`
  <!-- meta: fix=window.open(url,'_blank')-for-print-routes;-keep-resetAll-only-for-`New-Check-in`-and-`View-Ticket`(navigate-only,no-reset) -->

#### Major — feedback / state-transition mismatch

  `packages/web/src/pages/unified-pos/BottomActions.tsx:366-372`
  `packages/server/src/middleware/idempotent.ts` (cache header)
  <!-- meta: fix=server-emit-`X-Idempotent-Replay:1`+UI-toast('Already-saved-as-{order_id}','info')-instead-of-2nd-success-screen -->

  `packages/web/src/pages/unified-pos/RepairsTab.tsx:1149-1162`
  `packages/web/src/utils/phoneFormat.ts` (`stripPhone`)
  <!-- meta: fix=setQuery(stripPhone(newForm.phone))+verify-customerApi.search-handles-digit-string-or-add-search-by=phone-param -->

#### Minor — copy + hierarchy polish

  `packages/web/src/pages/unified-pos/BottomActions.tsx:298-303`
  <!-- meta: fix=if(sourceTicketId)-confirm(`Discard-changes-to-${sourceTicketOrderId}?`)-else-existing-string -->

  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:55-67,231-234,256-260`
  <!-- meta: fix=AbortController+8s-timeout+show-Retry-link-on-timeout-or-show-fallback-staff-app-instructions -->

  `packages/web/src/pages/unified-pos/RepairsTab.tsx:795`
  <!-- meta: fix=toast.success(...,{icon:'✓'})+briefly-pulse-the-Create-Ticket-button-via-store-flag+ring-2-ring-primary-500-for-1.5s -->

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

- [!] WEB-UIUX-1160. **[BLOCKER] Two parallel cash-tracking systems coexist with no UI signposting that they're disconnected — operators routinely use both.** Sidebar exposes "Cash Register" page (`/pos/cash-in`,`/pos/cash-out`, `cash_register` table, dollars REAL) AND POS BottomActions exposes "Start/Close Shift" (cents INTEGER, `cash_drawer_shifts` table, with Z-report). Neither page mentions the other. Same operator clicks "Cash In" on Cash Register page during a `pos_drawer_shift` and assumes it'll appear in the shift's Z-report — it doesn't (see WEB-UIUX-1159). Architectural drift surfaces as a usability failure: operator's mental model is "one drawer", reality is "two ledgers". L1 finds two cash buttons; L2 "Cash In" label means different things in different places; L7 feedback never indicates the parallel state. L1, L2, L4, L7, L13. **[AUTOLOOP-T49 BLOCKED 2026-05-11: ledger unification (deprecate `cash_register` REAL or fold it into `cash_drawer_shifts` cents) is a migration-scale call requiring data-migration plan + transitional UI. Multi-component product decision.]**
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

- [!] WEB-UIUX-1191. **[MAJOR] No "Send PO to Supplier" action — created PO sits in `draft` forever with no email/PDF/print path.** Procurement workflow normally: create PO → email supplier → mark `pending` (awaiting confirm) → mark `ordered` (supplier acknowledged). This UI has neither send action nor PDF render. Real-world cashier creates PO and then has to retype it into a separate email client. L4 flow completion, L6 discoverability. **STATUS: BLOCKED — needs new server endpoint POST /purchase-orders/:id/email + PDF render via existing print pipeline; multi-component**
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx` (entire file — no send action)
  <!-- meta: fix=add-"Send-to-Supplier"-button-on-PO-row+server-endpoint-POST-/purchase-orders/:id/email+optional-pdf-render-via-existing-print-pipeline -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:286, 293-297, 363-374`
  `packages/server/src/routes/inventory.routes.ts:1347-1378`
  <!-- meta: fix=add-status-pill-filter-row+search-input-debounced-by-PO-#-or-supplier-name+server-extends-LIST-with-q-LIKE-clause -->

- [!] WEB-UIUX-1193. **[MAJOR] No barcode-scan receive path surfaced from PO page.** Server has `POST /inventory/receive-scan` (`inventory.routes.ts:1716`) for barcode receiving — but no link from `PurchaseOrdersPage`. Operator with a hand scanner has to manually find the line item and type qty. Faster, less error-prone path is hidden. L6 discoverability, L4 flow. **STATUS: BLOCKED — needs scan modal + scanner-input wiring to /inventory/receive-scan + permission gates; multi-component**
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx` (no scan entry point)
  `packages/server/src/routes/inventory.routes.ts:1713-1716`
  <!-- meta: fix=add-"Scan-to-Receive"-button-on-PoDetailRow-(canReceive)+open-modal-with-scanner-input-bound-to-receive-scan-endpoint -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:85, 92, 135-137`
  <!-- meta: fix=if-any-receive_qty-differs-from-default-show-confirm("Discard-counted-quantities?")-on-cancel/✕ -->

#### Minor — copy + hierarchy + discoverability

  `packages/web/src/components/layout/Sidebar.tsx:76, 80`
  <!-- meta: fix=swap-PO-icon-to-Truck-or-ClipboardList -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:268-273`
  <!-- meta: fix=show-hint-when-!canReceive&&status!=='received'&&status!=='cancelled' -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:181-186`
  <!-- meta: fix=remove-text-primary-600-from-PO#-cell-OR-add-/purchase-orders/:id-detail-route -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:438-446`
  <!-- meta: fix=warn-on-submit-if-any-line-cost_price===0+confirm("Submit-with-$0-line-items?") -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:72-76`
  <!-- meta: fix=use-react-hot-toast-custom-toast-with-link-to-stock-movements-or-the-first-affected-inventory-item -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:461-463`
  <!-- meta: fix=cancel-handler-also-calls-setNewPo({supplier_id:'',notes:'',items:[{...EMPTY_ITEM}]}) -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:187-189`
  <!-- meta: fix=supplier_name||"(Supplier-removed)"+add-FK-ON-DELETE-RESTRICT-or-soft-delete-suppliers -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:138-145`
  <!-- meta: fix=2-step-confirm-on-Receive-when-totalToReceive>0+show-summary-"Receive-N-units-of-M-items?-This-cannot-be-undone." -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:92-94`
  <!-- meta: fix=replace-✕-with-<X-className="h-4-w-4"-/>-from-lucide-react -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:84-150`
  <!-- meta: fix=useEffect-keydown-listener-on-mount+if-key=Escape+confirm-if-dirty-then-onClose -->

  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:299-314, 383-392, 409-429`
  <!-- meta: fix=if(suppliersLoading||inventoryLoading)-show-skeleton-or-spinner-inside-select+disable-Create-button -->


### Web UI/UX Audit — Pass 21 (2026-05-05, flow walk: Process Refund / Credit Note — invoice detail entry, picker, server effects, recovery)

Flow under test (Invoice detail → "Credit Note" button → reason picker → submit): operator wants to give a customer their money back after a defective sale. Walked entry point on `InvoiceDetailPage.tsx`, the `RefundReasonPicker` component, the `POST /invoices/:id/credit-note` server handler, and the entire `refunds.routes.ts` parallel approval-workflow (which exists end-to-end on the server but has zero UI). Mismatch between the operator's mental model ("refund the card") and what the system actually does ("create a credit note that zeros the invoice and possibly mints store credit") is the dominant theme.

#### Blocker — semantic mismatch + dead workflow

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

- [!] WEB-UIUX-1220. **[MINOR] Reason picker labels "Defective product / Duplicate charge / Wrong item" all imply REFUND semantics (money back to card). The chosen action (Credit Note) does not refund the card. Either the picker is wrong here or the action is wrong — they don't match.** `RefundReasonPicker.tsx:17-24` was authored as a refund picker (component name + comments confirm — see line 2 "for partial refunds"); reusing it on a credit-note modal mis-leads operators. L2 truthful labels. **STATUS: BLOCKED — split CreditNoteReasonPicker from RefundReasonPicker requires component-level refactor + caller updates; defer to refunds sprint**
  `packages/web/src/components/billing/RefundReasonPicker.tsx:1-10`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:783-789`
  <!-- meta: fix=split-CreditNoteReasonPicker-(price_adjustment+goodwill+billing_correction+other)-from-RefundReasonPicker-(defective+wrong_item+duplicate_charge+dissatisfaction+other)+each-paired-with-its-correct-action -->

  `packages/server/src/routes/invoices.routes.ts:1180-1182`
  <!-- meta: fix=validateEnum(req.body.code,['defective','dissatisfaction','wrong_item','duplicate_charge','price_adjustment','other','billing_correction','goodwill'],'code')+share-the-list-with-RefundReasonPicker -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:753-755`
  <!-- meta: fix=conditional-copy-based-on-invoice.amount_due:amount_due>0?Reduces-balance-by-X:Adds-to-customer's-store-credit-balance -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:791-794`
  <!-- meta: fix=cancel-handler:setShowCreditNote(false)+setCreditNoteForm({amount:'',reason:null,note:''})+also-Esc-handler-and-✕-handler -->

#### Nit — visual polish

  `packages/web/src/components/billing/RefundReasonPicker.tsx:62`
  <!-- meta: fix=grid-cols-1-sm:grid-cols-2 -->

- [!] WEB-UIUX-1225. **[NIT] Credit-note `notes` field on the new invoice row stores `"Credit note: ${reason}"` (`invoices.routes.ts:1224`) — duplicates `credit_note_code` + `credit_note_note` columns. Three places store the reason; report queries that read `notes` get the legacy composed string while reports reading `credit_note_code` get the enum value.** Risk of divergence as new credit notes are issued. L13 schema dup. **STATUS: BLOCKED — server invoices.routes.ts notes-column dedup needs read/write migration; backend, defer to refunds sprint**
  `packages/server/src/routes/invoices.routes.ts:1213-1224`
  <!-- meta: fix=stop-writing-Credit-note-prefix-into-notes+OR-derive-notes-display-from-code+note-on-read+single-source-of-truth -->

### Web UI/UX Audit — Pass 22 (2026-05-05, flow walk: Apply Discount at POS — line item, order-wide, member, manager-PIN gate, server enforcement)

Flow under test (LeftPanel cart → click `Add discount` pill → enter amount + optional reason → Apply → checkout): operator wants to give a customer money off their cart at the register. Walked the cart-wide `DiscountEditor` (`LeftPanel.tsx:864-981`), the orphaned `LineItemDiscountMenu` component, the auto-applied member discount on `CustomerSelector.tsx`, the manager-PIN threshold logic in `BottomActions.tsx:244-270`, and the server's `POST /pos/checkout-with-ticket` discount validation (`pos.routes.ts:1869-1889`). Recurring theme: cart-wide is dollar-only with zero policy (no max, no manager gate, no percent), per-line is ghost-coded, member discount silently overrides instead of stacking, and reason capture is best-effort and partially dropped on the invoice path.

#### Blocker — missing primitives + dead UI

- [!] WEB-UIUX-1226. **[BLOCKER] `LineItemDiscountMenu` (164 lines, complete chip-picker with 5 reason codes + percent input + portal positioning) is NEVER imported anywhere in the codebase — per-line discount UI does not exist for operators.** `LineItemDiscountMenu.tsx:1-164`. Verified by `grep -rn "LineItemDiscountMenu"` — only matches are inside its own file. `RepairsTab.tsx:790` always inits `lineDiscount: 0`, `LeftPanel.tsx:148/399` and `UnifiedPosPage.tsx:318` only read `device.line_discount` from a server-loaded ticket — there is no client write path. The cart row at `LeftPanel.tsx:585-589` displays a per-line discount line item if non-zero, but no UI lets the operator set one. Server (`pos.routes.ts:1630-1668`) accepts `line_discount` per device, validates and applies it, so backend is fully wired — only the client UI is missing. Operator wanting "10% off labor on this device only" has to (a) edit `laborPrice` directly to fake it (loses the audit reason, breaks reports that group by `line_discount`), or (b) apply a cart-wide discount that hits everything. L3 destination correctness (no entry point), L6 discoverability, L4 flow completion. **STATUS: BLOCKED — wiring LineItemDiscountMenu requires RepairRow integration + types extension + payload thread; multi-component, defer to discount sprint**
  `packages/web/src/pages/unified-pos/LineItemDiscountMenu.tsx:1-164` (dead component)
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:585-608` (display path with no editor)
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:790` (init only, never updated)
  <!-- meta: fix=wire-LineItemDiscountMenu-into-RepairRow-(LeftPanel.tsx:574-)+anchor-on-click-of-the-laborPrice-cell-or-add-a-Percent-icon-button+onApply=updateCartItem(item.id,{lineDiscount:laborPrice*p/100,lineDiscountReason:reason})+extend-types.ts-RepairCartItem-with-lineDiscountReason+include-in-buildTicketPayload+server-already-accepts -->

- [!] WEB-UIUX-1243. **[MINOR] `manualDiscount` validation in `pos.routes.ts:1874` allows zero but not via the same code path as the rest — `ticketData?.discount ? validatePrice(...) : 0`.** Edge: a client sending the literal string `"0.00"` (truthy) goes through validatePrice (fine), but `0` (falsy) skips. Inconsistent with `tip` handling on the same form. L13 input contract. **STATUS: BLOCKED — server pos.routes.ts manualDiscount input contract change; backend, defer to discount sprint**
  `packages/server/src/routes/pos.routes.ts:1874-1876`
  <!-- meta: fix=use-rawDiscount!=null?validatePrice(rawDiscount,'discount'):0+match-existing-tip-style -->

  `packages/web/src/pages/unified-pos/LeftPanel.tsx:921-981`
  <!-- meta: fix=on-resetAll-also-reset-DiscountEditor-(via-effect-listening-on-cartItems.length===0)+OR-key-the-component-on-cartId-so-it-remounts-clean -->

- [!] WEB-UIUX-1276. **[BLOCKER] `/pos/return` (line-item return + stock restoration) is an orphan endpoint. Built `pos.routes.ts:2496` with admin-only gate, per-line quantity/reason, automatic inventory restoration via `stock_movements`, and credit-note generation — and ZERO web callers (`grep posApi.return` returns only the wrapper definition).** Manager who returns "1 of the 3 chargers from invoice INV-44" has no UI: forced to use the full-amount Credit Note modal which does NOT restore stock. Inventory shrinkage hidden, COGS skewed. L3, L4, L13 inventory integrity. **STATUS: BLOCKED — needs ReturnItemsModal with line-item checkboxes + per-line qty + posApi.return wiring; multi-component, defer to refunds sprint**
  `packages/server/src/routes/pos.routes.ts:2492-2637`
  `packages/web/src/api/endpoints.ts:753-761` (wrapper exists, no caller)
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx` (only Credit Note path)
  <!-- meta: fix=add-ReturnItemsModal-on-InvoiceDetailPage-with-line-item-checkboxes+per-line-quantity-input+RefundReasonPicker-shared+wire-posApi.return-with-idempotencyKey+gate-on-invoice.line_items.some(inventory_item_id) -->

  `packages/server/src/routes/invoices.routes.ts:1213-1230`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805` (modal hides this fact)
  <!-- meta: fix=server-derive-credit-tax-proportionally-(amount/total*total_tax)+credit-line-net+tax-separately+OR-explicit-toggle-Refund-tax-too-default-on+update-modal-summary-Net/Tax/Total -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177,795-801`
  <!-- meta: fix=wrap-handleCreditNote-in-useUndoableAction-(same-as-void)+OR-ConfirmDialog-with-amount-display-when-amount>$500+OR-typed-confirm-with-amount-string-for-amount>=invoice.total -->

#### Major — labels, routing, mental model

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`
  <!-- meta: fix=relabel-button-Refund-(keep-Credit-Note-as-modal-doc-name)+OR-split-into-two-CTAs-Refund-(cash-back)-vs-Issue-Credit-(store-credit) -->

- [!] WEB-UIUX-1284. **[MAJOR] No print/email/SMS handoff for the credit-note customer copy. Compare the Receipt prompt that fires after Record Payment (`InvoiceDetailPage.tsx:676-734`) — Print / SMS / Email. Credit note has zero customer-facing artifact path. Customer leaves the counter with nothing in hand showing the refund.** L4 flow completion, L7 feedback. **[AUTOLOOP-T49 BLOCKED 2026-05-11: needs a credit-note print/SMS/email receipt template + delivery hooks akin to the Receipt prompt path; depends on a customer-facing artifact spec (legal text varies by state).]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177`
  <!-- meta: fix=after-credit-note-success-fire-CreditNoteReceiptPrompt-with-Print/SMS/Email-mirroring-payment-prompt-but-credit-note-template -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:756-779`
  <!-- meta: fix=add-Refund-full-amount-($amount_paid)-button-below-the-amount-input+matches-Pay-full-balance-style -->

- [!] WEB-UIUX-1291. **[MAJOR] Reason composed as `${code}: ${note}` AND sent both as `reason` AND structured `code`/`note` (`InvoiceDetailPage.tsx:158-167`). Server stores all three (`invoices.routes.ts:1180-1185,1224`). Reports keying on `reason` get pre-FA-L8 free-text rows AND new "code: note" rows mixed; reports keying on `code` lose pre-FA-L8 rows entirely. No back-fill migration. Reporting cardinality is still split.** L13 reporting integrity. **STATUS: BLOCKED — needs server migration back-fill of credit_note_code from legacy reason field; backend change, defer to data-cleanup sprint**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-168`
  `packages/server/src/routes/invoices.routes.ts:1180-1230`
  <!-- meta: fix=migration-back-fill-credit_note_code-from-reason-where-prefix-matches-known-code+drop-reason-or-derive-it-server-side-from-code+note -->

- [!] WEB-UIUX-1295. **[MAJOR] Card-method routing missing. When the original payment was on a BlockChyp terminal (`processor_transaction_id` set, `InvoiceDetailPage.tsx:203-205`), the natural refund path is to send the credit BACK to the original card. UI offers no terminal-refund button; operator with a $300 card sale + customer in front of them has no way to push the refund through the terminal. They click Credit Note → ledger only. Customer leaves with no money on the card.** L1 findability, L4 flow completion. **STATUS: BLOCKED — needs new server blockchypApi.processRefund route + UI Refund-to-Card branch; multi-component, defer to terminal sprint**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:203-205,376-380`
  <!-- meta: fix=if-cardPaymentWithTxn-add-Refund-to-Card-($amount-on-card-XXXX)-button+wire-blockchypApi.processRefund-(stub-if-not-yet-implemented)+otherwise-warn-Card-refund-not-available -->

- [!] WEB-UIUX-1296. **[MAJOR] No partial-line-item picker — credit-note modal accepts only a free-form total amount. To return 1 of 3 phone cases ($25 each on a $75 line), operator types $25, but the line items table still shows "qty 3"; stock untouched; no reference to the specific item being returned. Compare orphan `/pos/return` (per-line, with stock restoration).** L1 findability of the right primitive, L4 flow completion. **[AUTOLOOP-T49 BLOCKED 2026-05-11: per-line-item picker = significant flow change; depends on UIUX-1020 (POS return flow with line-item picker). Defer until /pos/return UI ships.]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:425-450` (line items table is read-only)
  <!-- meta: fix=checkboxes+qty-spinners-on-line-items-table-when-modal-open+derive-amount-from-selection+post-to-/pos/return+amount-only-mode-fallback-for-non-product-invoices -->

#### Minor — modal copy, validation, focus

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:753-755`
  <!-- meta: fix=conditional-copy-amount_due>0-current-text+amount_due===0-"This-will-be-recorded-as-store-credit-on-the-customer's-account." -->

- [!] WEB-UIUX-1309. **[NIT] Header has Print/Void/Credit Note/Payment Plan/Financing — a 5+ button row that crowds on smaller viewports. Rare actions (Credit Note, Void) should live in a `…` overflow menu; common-and-frequent (Record Payment) front-and-centre.** L5 hierarchy, L1 primary action. **[AUTOLOOP-T49 BLOCKED 2026-05-11: header overflow menu (Credit Note + Void into ) needs the consistent primary-CTA-vs-overflow pattern across estimate UIUX-961, invoice UIUX-1039. App-wide pass.]**
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:342-389`
  <!-- meta: fix=keep-Record-Payment+Print-in-header+wrap-Void+Credit-Note+Payment-Plan-into-Kebab-More-actions-menu -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:172`
  <!-- meta: fix=mount-aria-live=polite-region-rendering-last-toast-text+OR-verify-react-hot-toast-emits-role=status -->

- [!] WEB-UIUX-1324. **[MAJOR] `existingAppointments` passed to overlap check (`CalendarPage.tsx:200-206,256-271`) is the current viewport only (month/week/day window from `dateRange` query). Booking on the last day of viewed month against an appt on the first day of next month: client says all clear. Server warning catches some, but #1319 throws that away anyway. False sense of safety on every cross-window booking.** L7 feedback meaning. **[AUTOLOOP-T49 BLOCKED 2026-05-11: cross-viewport overlap requires a server endpoint like /appointments/overlaps?assigned_to=&start=&end= that scans outside the viewport. Adding a fetch on every booking submit is heavy; needs UX trade-off.]**
  `packages/web/src/pages/leads/CalendarPage.tsx:256-271,727-733`
  <!-- meta: fix=fetch-±1-week-buffer-around-target-time-on-modal-open-(or-on-time-change)+server-side-precondition-check-already-correct,-just-surface-warning-(see-WEB-UIUX-1319) -->

  `packages/web/src/pages/leads/CalendarPage.tsx:396-405`
  <!-- meta: fix=add-No-show-option+also-expose-via-edit-modal-(WEB-UIUX-1316)+server-PUT-already-supports-no_show-flag -->

- [!] WEB-UIUX-1328. **[MAJOR] No click-to-create on calendar grid. MonthView day cells (`483-538`), WeekView slots (`588-613`), DayView slots (`641-672`) ignore clicks. Every booking flows through "New Appointment" button → form pre-filled 9:00–10:00 → user manually re-types date+time. Industry-standard calendar UX (Google/Outlook/Cal.com) is click-an-empty-slot-to-create. Forced friction on the most common action.** L1 findability, L4 flow completion, L6 discoverability. **[AUTOLOOP-T49 BLOCKED 2026-05-11: click-to-create on calendar grid requires onClick handlers on Month/Week/Day cells that compute the slot start time + open CreateAppointmentModal with prefilled defaults — multi-view refactor.]**
  `packages/web/src/pages/leads/CalendarPage.tsx:483-538,557-617,621-674`
  <!-- meta: fix=onClick-on-empty-cell-opens-CreateAppointmentModal-with-pre-filled-date-(month)-or-date+hour-(week/day)+drag-to-select-range-for-end-time -->

  `packages/web/src/pages/leads/CalendarPage.tsx:830-869`
  <!-- meta: fix=replace-grid-when-month-view-and-0-appts+OR-keep-grid-but-make-empty-msg-an-overlay-banner-with-"+ Schedule one"-CTA -->

  `packages/web/src/pages/leads/CalendarPage.tsx:340-378`
  <!-- meta: fix=onChange-of-start-fields-set-end-=-start+60min-when-end-is-still-default-or-<=-start -->

  `packages/web/src/api/types.ts:436-442`
  `packages/web/src/pages/leads/CalendarPage.tsx:227-234,309-316`
  <!-- meta: fix=extend-CreateAppointmentInput+UpdateAppointmentInput-to-include-title?+status?+customer_id?+recurrence?+location_id?+no_show? -->

  `packages/web/src/pages/leads/LeadDetailPage.tsx:723`
  <!-- meta: fix=apply-`a.title || 'Untitled'`-fallback-everywhere-OR-make-server-reject-empty-title-(currently-defaults-to-''-`leads.routes.ts:595`) -->

  `packages/web/src/pages/leads/CalendarPage.tsx:122-128,765-771`
  <!-- meta: fix=show-current-tz-abbrev-(e.g.-PST)-in-header+show-on-appt-detail-row+future-add-location-tz-override-when-location_id-supports-it -->

  `packages/web/src/pages/leads/CalendarPage.tsx:749,801-806`
  <!-- meta: fix=Today-resets-date-only-(current-behavior-OK)+add-aria-current="date"-when-relevant+OR-click-Today-twice-toggles-to-day-view -->

  `packages/web/src/pages/leads/CalendarPage.tsx:132-137`
  <!-- meta: fix=STATUS_LABELS-map-(scheduled→Scheduled,no-show→No-Show)+drop-capitalize-class -->

- [!] WEB-UIUX-1336. **[NIT] No SMS/email confirmation toggle on create. If server auto-sends confirmation (per location settings), staff has no way to opt out for internal-only blocks. If server doesn't, staff has no way to send. Either way, opaque.** L7 feedback, L6 discoverability. **STATUS: BLOCKED — needs server flag in /leads/appointments + SMS infrastructure (deferred per user 2026-05-05); defer to messaging sprint**
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

- [!] WEB-UIUX-1385. **[BLOCKER] `posApi.return` (`endpoints.ts:753`) POSTs `/pos/return` with idempotency key — never called from any UI. Cashier with a returning customer holding receipt #12345 has no "Process Return" path through POS. UnifiedPosPage has no return tab/mode; CashRegisterPage has only cash in/out (drawer events, not sales-returns). The endpoint is documented as "Cash refund on an existing sale" but is dead.** L4 flow, L6 discoverability. **[AUTOLOOP-T49 BLOCKED 2026-05-11: depends on /pos return-flow UI (UIUX-1020). posApi.return is ready server-side.]**
  `packages/web/src/api/endpoints.ts:749-761`
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx`
  <!-- meta: fix=add-Returns-tab-to-UnifiedPosPage+receipt-lookup-by-order_id-or-scan+select-line-items-to-return+method-picker-(cash|card|store-credit)+POST-/pos/return-with-idempotency -->

#### Major — credit-note flow ergonomics + truthfulness

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

- [!] WEB-UIUX-1392. **[MAJOR] Credit-note creates ledger entry but never adjusts customer's `store_credits` row when a refund-to-credit method is desired. Server only credits `store_credits` for *overflow* (credit > remaining due, `invoices.routes.ts:1259-1283`). Operator who wants "$50 credit note → put $50 on customer's store credit" with the invoice fully unpaid has no way to do this from credit-note flow. Refund route handles it (`refunds.routes.ts:383-396`) but refund route has no UI (WEB-UIUX-1382).** L4 flow, L6 discoverability. **[AUTOLOOP-T49 BLOCKED 2026-05-11: depends on /refunds UI (UIUX-1018/1207). refunds.routes already credits store_credits for the "refund-to-credit" path.]**
  `packages/server/src/routes/invoices.routes.ts:1259-1283`
  `packages/server/src/routes/refunds.routes.ts:383-396`
  <!-- meta: fix=add-method-picker-to-credit-note-modal-(refund-cash|refund-card|store-credit|ledger-only)+route-to-refund-route-when-money-actually-leaves -->

  `packages/web/src/pages/invoices/InvoiceListPage.tsx:33,41`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1685`
  `packages/server/src/routes/refunds.routes.ts:253-412`
  <!-- meta: fix=on-refund-approve-set-invoice.status='refunded'-when-cumulative-refunds>=amount_paid+OR-remove-the-status-colour-decoration -->

- [!] WEB-UIUX-1397. **[MAJOR] Reports do not surface refund detail. Dashboard KPI shows aggregate (`kpis.refunds`); `/reports` page (linked from KPI siblings) has no per-refund breakdown — server's `GET /refunds` returns paginated detail with customer name + invoice order_id + creator, but the data is unread by any frontend.** L6 discoverability, L4 flow. **STATUS: BLOCKED — Reports refund detail tab needs server pagination + UI table; multi-component, defer**
  `packages/server/src/routes/refunds.routes.ts:74-95`
  `packages/web/src/pages/dashboard/DashboardPage.tsx:2120`
  <!-- meta: fix=add-Refunds-Detail-tab-to-/reports+table-with-date+invoice+customer+amount+reason+method+approver -->

- [!] WEB-UIUX-1398. **[MAJOR] Card-method refund cap exists in server (`refunds.routes.ts:177-202` — `cardCollected - cardAlreadyRefunded`) but no UI surface ever sends `method:'card'`. The whole branch is dead defence-in-depth. Once UI is added, the method picker must default to the *original payment method* of the invoice (lookup last payment.method) — otherwise operator hand-picks "cash" and bypasses card cap.** L4 flow, L7 feedback. **[AUTOLOOP-T49 BLOCKED 2026-05-11: depends on the /refunds list/inbox UI (UIUX-1018/1207) shipping. Default-method-to-original-payment requires a method picker in that future modal.]**
  `packages/server/src/routes/refunds.routes.ts:177-202`
  <!-- meta: fix=NewRefundModal-prefill-method-from-invoice.payments[0].method+disable-non-card-options-when-original-was-card+show-card-cap-inline-($X-card-collected,-$Y-already-refunded) -->

- [!] WEB-UIUX-1399. **[MAJOR] Capture-state precondition (`refunds.routes.ts:140-153` — refunds blocked while any payment is `authorized` or `voided` not yet captured) — no UI hint. Operator on an invoice with an auth-only BlockChyp payment will hit a 400 "Cannot refund — N payment(s) on this invoice are not captured" with no path to "Capture or void the authorization first" the error tells them to do. Capture flow itself buried/nonexistent.** L4 flow dead-end, L7 feedback unactionable. **STATUS: BLOCKED — depends on WEB-UIUX-1382 (refund UI not yet shipped); capture-state hint pairs with that sprint**
  `packages/server/src/routes/refunds.routes.ts:133-153`
  <!-- meta: fix=Refund-button-disabled-with-tooltip-"Capture-pending-authorization-first"-when-any-payment.capture_state!='captured'+CTA-link-to-capture-flow -->

  `packages/server/src/routes/refunds.routes.ts:439-454`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx`
  <!-- meta: fix=at-customer-select-fetch-credits.balance+show-pill-"Store-credit:-$X"+payment-method-includes-store_credit-with-cap-at-balance+POST-/refunds/credits/:id/use-on-apply -->

#### Major — recovery + concurrency surfacing

- [!] WEB-UIUX-1427. **[BLOCKER] No POS payment method for gift cards. CheckoutModal `PaymentMethod = 'Cash' | 'Card' | 'Other'` (`CheckoutModal.tsx:16,23-27`). Server's `/gift-cards/lookup/:code` + `POST /gift-cards/:id/redeem` (`giftCards.routes.ts:172,328`) cannot be reached from any sale UI. Recipient walks in with the code → cashier rings up sale → no "Gift Card" tile in payment methods → cashier hand-codes "Other" → no balance check, no redemption row written → server gift-card balance never decremented → physical card stays at full balance forever, customer can spend it again at next visit.** L1 primary action findability, L4 flow completion (entire redemption loop dead), L6 discoverability. **STATUS: BLOCKED — needs PaymentMethod GiftCard tile + lookup→balance pill + redeem POST chain + invoice gift_card_id linkage; multi-component, defer to gift-card sprint**
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:16,23-27,530-575`
  `packages/server/src/routes/giftCards.routes.ts:172-245,328-392`
  <!-- meta: fix=add-PaymentMethod='GiftCard'+tile-with-Gift-icon+on-select-show-code-input+lookup→show-balance-pill-"$45.00-available"+confirm-amount-(cap-at-min(due,balance))+POST-/gift-cards/:id/redeem-with-invoice_id-on-checkout-success+include-in-split-payments -->

- [!] WEB-UIUX-1454. **[NIT] `formatCurrency` cents/dollars heuristic (`GiftCardsListPage.tsx:57-63`, mirrored on Detail `:41-44`) treats integers >=1000 as cents. A $999.99 card stored as float 999.99 renders as $999.99 (correct); a $10.00 card stored as integer 1000 cents renders as $10.00 (correct); but a $10 card mistakenly stored as integer 10 (dollars, not cents) renders as $10 — looks fine until you hit edge case $1500 → 1500 dollars vs 1500 cents=15 ambiguity. Comment acknowledges fragility ("if it does, it'll still render correctly because 1000.5...") but it's a ticking interpretation bomb. Drop the heuristic the moment server picks one representation.** L11 consistency. **[AUTOLOOP-T49 BLOCKED 2026-05-11: heuristic resolution must follow a server-side picks-one-representation change (cents OR dollars) + migration on stored balances. Single-page fix risks regressions until the server commits.]**
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:46-63`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:38-53`
  <!-- meta: fix=spike-server-→-emit-cents-only-on-/gift-cards-routes+remove-heuristic+single-formatCurrencyShared(amountCents/100) -->

- [!] WEB-UIUX-1499. **[MINOR] No proration / refund logic on immediate cancel. Server immediately flips status + nulls active_subscription_id (`membership.routes.ts:229-232`); customer paid for month, loses access today, receives no refund. Either the cancel flow should offer "Cancel at period end" (preferred default — see -1485) or trigger a prorated credit-note. Currently there is no automatic refund and the UI shows no refund affordance after cancel.** L8 recovery, L1 truthfulness. **[AUTOLOOP-T49 BLOCKED 2026-05-11: immediate-cancel proration / refund flow needs a server `/membership/:id/cancel` flag + automatic credit-note path keyed to days remaining. Multi-component finance change.]**
  `packages/server/src/routes/membership.routes.ts:222-239`
  <!-- meta: fix=on-immediate-cancel-compute-prorated-amount=last_charge*(remaining_days/period_days)+offer-refund-or-credit-note+OR-default-to-cancel-at-period-end -->


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

- [!] WEB-UIUX-1533. **[MAJOR] Invoice list has no inline "Record Payment" — collections workflow loses scroll/filter on every row. `InvoiceListPage.tsx:533-538` action column shows "View" only; the row is also clickable as a whole, so selection or quick action requires `e.stopPropagation()` plumbing already in place. A cashier reviewing the overdue tab (50 rows) and calling each customer in turn must click row → land on detail → click Record Payment → record → navigate back → scroll back to position. Add a small "$" / "Pay" icon button beside View on rows with `amount_due > 0`, opening the same payment modal in-list (or via a side drawer).** L4 flow integrity, L6 discoverability. **STATUS: BLOCKED — needs RecordPaymentModal extracted into shared component + InvoiceListPage row action; multi-component, defer**
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:483-540`
  <!-- meta: fix=add-quick-pay-button-on-rows-with-amount_due>0;-mount-shared-PaymentModal-component-with-invoiceId-+-onClose;-extract-modal-from-InvoiceDetailPage.tsx-into-components/billing/RecordPaymentModal.tsx -->

#### Minor — clarity / consistency

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:603-617`
  <!-- meta: fix=placeholder=formatCurrency(invoice.amount_due);-remove-hardcoded-$-prefix-OR-derive-from-tenant.currency_symbol -->

  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:602-622`
  <!-- meta: fix=primary-CTA="Pay-{full}";-secondary-toggle-"Custom-amount"-reveals-input;-existing-link-replaced-by-button -->

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

