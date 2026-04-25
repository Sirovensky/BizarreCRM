---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## Web Audit Wave-WEB-2026-04-24 — secondary surfaces (search agent A3)

### P0
- [ ] WEB-W3-001. **Inventory stocktake barcode scan uses partial keyword search — wrong item selected on scan.** `pages/inventory/StocktakePage.tsx`. Fix: exact match by barcode/SKU first; only fall back to keyword if no exact hit.
- [ ] WEB-W3-002. **Stocktake quick-scan defaults to `in_stock+1` not absolute count — corrupts data.** `StocktakePage.tsx`. Fix: scan must record absolute count input or be a separate "increment" mode clearly labeled.
- [ ] WEB-W3-003. **Purchase order has no receive workflow — cannot mark items received or change status.** `pages/inventory/PurchaseOrdersPage.tsx`. Fix: add receive modal + `POST /purchase-orders/:id/receive` route to update line `received_qty`, set status to received/partial.
- [ ] WEB-W3-004. **POS split payments: Card leg does not trigger BlockChyp — card never charged.** `pages/pos/CashRegisterPage.tsx` / `unified-pos`. Fix: each card leg of split tender must call BlockChyp `charge` for that amount; only mark paid on terminal success.
- [ ] WEB-W3-005. **Billing payment-links page explicitly non-functional — in-page banner confirms.** `pages/billing/`. Fix: implement `POST /payment-links` with token, public `/pay/:token` page that runs BlockChyp Hosted Checkout.

### P1 (silent no-op)
- [ ] WEB-W3-006. **Auto-reorder uses raw item ID input — no search, no enable/disable toggle.** `pages/inventory/AutoReorderPage.tsx`. Fix: replace ID input with item picker (autocomplete by SKU/name); add per-item enabled toggle.
- [ ] WEB-W3-007. **Bin locations: no edit/rename for existing bins.** `BinLocationsPage.tsx`. Fix: add inline rename + `PUT /bin-locations/:id`.
- [ ] WEB-W3-008. **Inventory age buckets capped at 100, no pagination.** `InventoryAgePage.tsx`. Fix: add pagination params + load-more.
- [ ] WEB-W3-009. **Mass label "PDF" format downloads ZPL/text not PDF.** `MassLabelPrintPage.tsx`. Fix: add real PDF render via `pdfkit` or label-template route returning `application/pdf`.
- [ ] WEB-W3-010. **No line-item view for POs.** `PurchaseOrdersPage.tsx`. Fix: detail page or expandable row showing PO lines + receive status.
- [ ] WEB-W3-011. **Serial numbers page uses raw item ID input; no cross-item serial search.** `SerialNumbersPage.tsx`. Fix: item picker + `GET /inventory/serials?serial=` global search.
- [ ] WEB-W3-012. **Shrinkage page uses raw item ID input.** `ShrinkagePage.tsx`. Fix: item picker.
- [ ] WEB-W3-013. **Inventory CSV export is current-page-only; advanced filters may be ignored by backend.** `InventoryListPage.tsx`. Fix: dedicated `/inventory/export.csv` server-streaming route honoring all filters.
- [ ] WEB-W3-014. **`wholesale_price` missing from inventory edit form.** `InventoryDetailPage.tsx`. Fix: add field; route already accepts column.
- [ ] WEB-W3-015. **POS "Other" payment has no reference capture.** `CashRegisterPage.tsx`. Fix: add reference field on Other tender (e.g. check #, voucher code).
- [ ] WEB-W3-016. **POS Z-report Print prints full page not modal.** `pages/pos/`. Fix: `window.print()` after wrapping report in print-only stylesheet, or open new window with z-report HTML.
- [ ] WEB-W3-017. **Aging report checkboxes are dead; no per-row "Send Reminder".** `pages/billing/`. Fix: wire bulk-select + `POST /invoices/send-reminder` per row.
- [ ] WEB-W3-018. **Payment-links page uses raw Customer/Invoice ID inputs.** `pages/billing/`. Fix: pickers.
- [ ] WEB-W3-019. **Dunning steps entered as raw JSON textarea.** `pages/billing/`. Fix: structured editor — list of steps with day-offset + channel + template selector.
- [ ] WEB-W3-020. **Subscriptions "Run billing now" is no-op toast.** `pages/subscriptions/`. Fix: implement `POST /subscriptions/:id/run-billing` that creates invoice + charges saved card via BlockChyp tokenized CNP.
- [ ] WEB-W3-021. **Expenses create form has no receipt upload.** `pages/expenses/`. Fix: add file upload wired to `expenseReceipts.routes.ts`.
- [ ] WEB-W3-022. **Gift cards: no balance-adjustment UI.** `pages/gift-cards/`. Fix: add adjust modal calling existing balance-adjust route, or add route if missing.
- [ ] WEB-W3-023. **Voice recording playback opens raw URL without auth token.** `pages/voice/`. Fix: serve recordings via signed URL or behind JWT-protected proxy route.
- [ ] WEB-W3-024. **Team shift-schedule: no conflict detection for overlapping shifts.** `pages/team/`. Fix: server validation rejects overlapping shifts for same employee; UI shows error.

### P2 (cosmetic / missing UI)
- [ ] WEB-W3-025. **ABC analysis: no export; clearance suggestions have no action.** `AbcAnalysisPage.tsx`. Fix: add CSV export + "Mark for clearance" button.
- [ ] WEB-W3-026. **Inventory age: no date-range filter; cost shows per-unit not total.** `InventoryAgePage.tsx`.
- [ ] WEB-W3-027. **Shrinkage: no filter by reason/date; no export.** `ShrinkagePage.tsx`.
- [ ] WEB-W3-028. **Print Barcode hidden when no SKU/UPC.** `InventoryDetailPage.tsx`. Fix: generate UUID-based barcode fallback or show disabled with tooltip.
- [ ] WEB-W3-029. **Unified POS F-key shortcuts have no legend.** `pages/unified-pos/`.
- [ ] WEB-W3-030. **Subscriptions Cancel has no end-date display.** `pages/subscriptions/`.
- [ ] WEB-W3-031. **Expenses list has no category/date filter.** `pages/expenses/`.
- [ ] WEB-W3-032. **Reports: no PDF export anywhere; CSV only on sales tab; non-admin date cap silent.** `pages/reports/`. Fix: PDF route + surface date-cap message.
- [ ] WEB-W3-033. **Marketing NPS trend errors swallowed, empty chart shown.** `pages/marketing/`. Fix: surface error toast / empty state.
- [ ] WEB-W3-034. **Marketing campaigns preview shows count only, not rendered message.** `pages/marketing/`. Fix: render template with sample variable substitution.
- [ ] WEB-W3-035. **Loaners list: no search / status filter.** `pages/loaners/`.
- [ ] WEB-W3-036. **Catalog device-filter: 2-char minimum with no visible hint.** `pages/catalog/`. Fix: add hint text.
- [ ] WEB-W3-037. **Team goals: only 3 hardcoded metric types.** `pages/team/`. Fix: load metrics from server enum or expand list.

## Web Audit Wave-WEB-2026-04-24 — settings tabs + setup wizard (search agent A1)

### P0
- [ ] WEB-W1-001. **`pos_require_pin_sale` / `pos_require_pin_ticket` — PIN gate frontend-only; direct API bypass.**
  - File: `packages/web/src/pages/settings/PosSettings.tsx:220-236`
  - Fix: enforce server-side. POS routes should require a PIN-validation header on tendering / ticket actions when these flags are true. Add middleware `requirePosPin` reading store_config + `pos_pin_hash`.

### P1 (silent no-op)
- [ ] WEB-W1-002. **`ticket_show_closed` stored but never read by backend.** — `TicketsRepairsSettings.tsx`. Fix: tickets list route filters out closed tickets when false (`statuses NOT IN (closed, canceled)`).
- [x] WEB-W1-003. **`ticket_show_empty` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-008.
- [ ] WEB-W1-004. **`ticket_default_view` client-only, `kanban` option unimplemented but marked live.** — flip to `coming_soon` until kanban default works, or add server-side default-view persistence.
- [ ] WEB-W1-005. **`ticket_default_filter` — date-range value assigned to `statusFilter` variable (type mismatch).** — `TicketsRepairsSettings.tsx`. Fix: split into `ticket_default_date_filter` + `ticket_default_status_filter`.
- [ ] WEB-W1-006. **`ticket_default_pagination` key-name drift between save and read.** — verify save key matches consumed key in `tickets.routes.ts`.
- [ ] WEB-W1-007. **`ticket_auto_status_on_reply` no badge + backend never reads.** — wire: when customer replies via portal/SMS, ticket status flips to configured value.
- [x] WEB-W1-008. **`repair_default_input_criteria` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-010 (autoFocus IMEI/Serial in RepairsTab).
- [x] WEB-W1-009. **`ticket_default_sort_order` / `ticket_default_date_sort` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-009.
- [ ] WEB-W1-010. **POS keys `pos_show_repairs/products/miscellaneous` vs backend's `pos_show_devices/services/etc.` — different key sets.** — `PosSettings.tsx` + `pos.routes.ts`. Pick one set, drop the other, write migration to map old → new.
- [x] WEB-W1-011. **`pos_show_out_of_stock` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-005.
- [x] WEB-W1-012. **`pos_show_invoice_notes` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-007.
- [x] WEB-W1-013. **`pos_show_outstanding_alert` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-006.
- [ ] WEB-W1-014. **`pos_show_images` dead.** — wire into POS catalog tile render.
- [ ] WEB-W1-015. **`pos_show_discount_reason` dead.** — wire into POS discount modal (require reason input when true).
- [ ] WEB-W1-016. **`receipt_default_size` value drift (`receipt80` saved, `thermal_80` expected).** — `ReceiptSettings.tsx` + print route. Pick canonical value; migrate stored.
- [ ] WEB-W1-017. **8x `receipt_cfg_*_page` variants — 2 of 8 wired (security_code_page + po_so_page) per WEB-WA-003/004; remaining 6 still saved-but-not-read.** Identify the other 6 keys + wire each into letter renderer.
- [x] WEB-W1-018. **`receipt_cfg_line_price_incl_tax_thermal` wired.** CLOSED 2026-04-24 — see DONETODOS WEB-WA-002.
- [ ] WEB-W1-019. **Invoice branding keys client-side only; server-sent invoices unbranded.** — `InvoiceSettings.tsx`. Fix: server-side PDF/email render must read same branding keys.
- [ ] WEB-W1-020. **`invoice_payment_terms` no runtime consumer.** — wire into invoice create + PDF render.
- [ ] WEB-W1-021. **Voice inputs uncontrolled (`defaultChecked`/DOM query) — brittle save.** — `SmsVoiceSettings.tsx`. Convert to controlled inputs with React state.
- [ ] WEB-W1-022. **`POST /settings/sms/reload` endpoint existence unverified.** — `SmsVoiceSettings.tsx`. Verify route in `settings.routes.ts`; if missing, add (re-init Twilio client from updated creds) or remove button.
- [x] WEB-W1-023. **`lead_auto_assign` + `estimate_followup_days` registry trim verified.** CLOSED 2026-04-24 — verified absent from settingsDeadToggles.ts post-commit a0a81865.
- [ ] WEB-W1-024. **`blockchyp_tc_enabled` read not confirmed in `blockchyp.ts`.** — verify; if not read, wire terminal-capture toggle.

### P2 (cosmetic / missing UI)
- [ ] WEB-W1-025. **`checkin_default_category` hardcoded option list.** — `PosSettings.tsx`. Fix: load options from `categories` table.
- [ ] WEB-W1-026. **`receipt_header` / `receipt_footer` written by two separate forms — last-write-wins.** — `ReceiptSettings.tsx`. Fix: single source of truth form.
- [ ] WEB-W1-027. **`theme_primary_color` requires page refresh to apply after save.** — wire `useEffect` listener on store_config update; re-run AppShell color setter.
- [ ] WEB-W1-028. **Webhook event list hardcoded in UI.** — load from server (`/webhooks/events` enum).
- [ ] WEB-W1-029. **`auto_reply_enabled` / `auto_reply_message` missing from SmsVoiceSettings UI** (already wired backend in WEB-WB-001). — add inputs to surface.
- [ ] WEB-W1-030. **3CX keys (`tcx_*`) missing from SmsVoiceSettings.** — these are intentionally dead; either hide or render with Coming Soon badge.
- [ ] WEB-W1-031. **`notification_digest_mode` / `notification_digest_hour` missing from NotificationsSettings.** — render with Coming Soon badge until digest dispatcher exists.
- [ ] WEB-W1-032. **`settingsSearchIndex` includes `coming_soon` entries pointing to tabs with no UI controls.** — filter coming_soon-without-UI from index.
- [ ] WEB-W1-033. **`findMetadataOnlyDeadKeys()` never called — drift goes undetected.** — call in dev-only banner inside SettingsPage to surface drift.
- [ ] WEB-W1-034. **Setup wizard StepEmailSmtp: no test-connection before advancing.** — `pages/setup/`. Add `POST /setup/test-smtp` route + button on step.
- [ ] WEB-W1-035. **Setup wizard: no "back" navigation between sub-steps.** — add Back button reading wizard step state.

## Web Audit Wave-WEB-2026-04-24 — core entity workflows (search agent A2)

### P0 (blocks workflow / data loss)
- [ ] WEB-W2-001. **Bulk "Send Reminders" only sets DB timestamp, no email/SMS sent.**
  - File: `packages/web/src/pages/invoices/` (list, bulk action handler)
  - Symptom: button reports success; customer never contacted.
  - Fix: in invoices route, on reminder action enqueue notification via `services/notifications.ts` (email + SMS per customer prefs) before timestamping.
- [ ] WEB-W2-002. **`InstallmentPlanWizard` posts to `/installments` — route does not exist (404).**
  - File: `packages/web/src/pages/invoices/` (InstallmentPlanWizard component)
  - Fix: add `packages/server/src/routes/installments.routes.ts` with create/list/cancel handlers + migration for `installment_plans` table OR remove wizard until built.
- [ ] WEB-W2-003. **Ticket "Clone as Warranty" calls unverified route — likely 404.**
  - File: `packages/web/src/pages/tickets/TicketDetailPage.tsx` or `TicketActions.tsx`
  - Fix: confirm endpoint in `tickets.routes.ts`; if missing, add `POST /tickets/:id/clone-warranty` that copies ticket with `is_warranty=true` and parent reference.
- [ ] WEB-W2-004. **Ticket merge dialog calls unverified route — likely 404.**
  - File: `packages/web/src/pages/tickets/TicketDetailPage.tsx` (merge dialog)
  - Fix: implement `POST /tickets/merge` that consolidates devices/notes/payments under target ticket id and soft-deletes source.

### P1 (silent no-op / broken feature)
- [x] WEB-W2-005. **Overview-bar status buttons send string group names, not numeric IDs.** CLOSED 2026-04-24 — 1233b978
  - File: `packages/web/src/pages/tickets/TicketListPage.tsx`
  - Fix: map group label → status_id before query param.
- [ ] WEB-W2-006. **Bulk "Assign" missing from UI although backend supports it.**
  - File: `packages/web/src/pages/tickets/TicketListPage.tsx` (bulk action menu)
  - Fix: add Assign action wired to existing bulk endpoint.
- [ ] WEB-W2-007. **Saved filter presets not persisted — lost on reload.**
  - File: `packages/web/src/pages/tickets/TicketListPage.tsx`
  - Fix: persist via `preferences.routes.ts` (per-user JSON blob) or `localStorage` keyed by user.
- [ ] WEB-W2-008. **Ticket duplicate feature absent — no route, no UI.**
  - Fix: add `POST /tickets/:id/duplicate` server route + button in TicketActions.
- [x] WEB-W2-009. **Unassign sends `null as any` — type-unsafe.** CLOSED 2026-04-24 — 1233b978
  - File: `packages/web/src/pages/tickets/TicketSidebar.tsx`
  - Fix: type assignee field as `number | null`; route accepts null.
- [x] WEB-W2-010. **Appointment note field name mismatch (`note` saved vs `notes` displayed).** CLOSED 2026-04-24 — 42e9b254
  - File: `packages/web/src/pages/tickets/TicketSidebar.tsx`
  - Fix: normalize to `notes` in DB + payload + display.
- [ ] WEB-W2-011. **Activity filter tabs are client-side only — incomplete if backend paginates.**
  - File: `packages/web/src/pages/tickets/TicketNotes.tsx`
  - Fix: pass filter as query param to activity endpoint; rebuild filtering server-side.
- [x] WEB-W2-012. **DeviceEditForm silently drops `device_type`, `color`, `network`, `pre_conditions`.** CLOSED 2026-04-24 — 3062bde3
  - File: `packages/web/src/pages/tickets/TicketDevices.tsx`
  - Fix: include these fields in PUT payload; verify route accepts them.
- [x] WEB-W2-013. **Price editing uses `prompt()` — blocked on iOS Safari.** CLOSED 2026-04-24 — 2f381cdc
  - File: `packages/web/src/pages/tickets/TicketPayments.tsx`
  - Fix: replace `prompt()` with inline modal/input.
- [ ] WEB-W2-014. **`repairPricingApi` import — backend route unverified.**
  - File: `packages/web/src/pages/tickets/TicketWizard.tsx`
  - Fix: confirm `repairPricing.routes.ts` shape matches client; align if not.
- [x] WEB-W2-015. **Wallet pass `window.open(blob)` blocked by popup policies.** CLOSED 2026-04-24 — 5699cb5e
  - File: `packages/web/src/pages/customers/CustomerDetailPage.tsx`
  - Fix: trigger anchor download with `download` attr instead of `window.open`.
- [ ] WEB-W2-016. **Invoice "Financing" button is explicit stub showing "coming soon".**
  - File: `packages/web/src/pages/invoices/`
  - Fix: hide button until partner integration exists, or wire to real provider.
- [ ] WEB-W2-017. **BlockChyp `adjustTip` always returns NOT_SUPPORTED.**
  - File: `packages/server/src/routes/blockchyp.routes.ts`
  - Fix: implement adjustTip per BlockChyp SDK or remove tip-adjust UI button.
- [ ] WEB-W2-018. **Credit note `code`/`note` fields may not exist in DB schema.**
  - File: `packages/web/src/pages/invoices/` + `packages/server/src/routes/creditNotes.routes.ts`
  - Fix: add columns via migration if missing or drop fields from form.
- [ ] WEB-W2-019. **Estimate line items display-only after creation — can't edit.**
  - File: `packages/web/src/pages/estimates/`
  - Fix: add inline edit + PUT `/estimates/:id/line-items/:lineId`.
- [ ] WEB-W2-020. **No "Reject" button on estimate detail — `rejected` status unreachable from UI.**
  - File: `packages/web/src/pages/estimates/`
  - Fix: add Reject action calling existing status route.
- [x] WEB-W2-021. **Lead appointment note field mismatch (same as WEB-W2-010).** CLOSED 2026-04-24 — 42e9b254
  - File: `packages/web/src/pages/leads/`
  - Fix: same normalization to `notes`.
- [ ] WEB-W2-022. **Invoice list stats widget always shows global totals, ignores active filters.**
  - File: `packages/web/src/pages/invoices/`
  - Fix: pass active filter params to stats endpoint OR compute from filtered result set.
- [ ] WEB-W2-023. **Overdue count computed from current page only — inaccurate.**
  - File: `packages/web/src/pages/invoices/`
  - Fix: dedicated `/invoices/stats?overdue=1` query independent of pagination.

### P2 (cosmetic / minor UX)
- [x] WEB-W2-024. **Dead `_unusedMut` mutation variable.** CLOSED 2026-04-24 — 1233b978 — `pages/tickets/TicketListPage.tsx` — remove.
- [ ] WEB-W2-025. **Calendar view: can't create ticket from day click.** — `pages/tickets/TicketListPage.tsx` — wire day-click → create-modal with prefilled date.
- [x] WEB-W2-026. **QC sign-off button always visible regardless of status.** CLOSED 2026-04-24 — 3e278dda — `pages/tickets/TicketDetailPage.tsx` — gate visibility on status === ready_for_qc.
- [x] WEB-W2-027. **Appointment `end_time` uses locale-pinned `toLocaleTimeString`.** CLOSED 2026-04-24 — 42e9b254 — `pages/tickets/TicketSidebar.tsx` — use app date helper.
- [x] WEB-W2-028. **`outstanding_balance` column not sortable.** CLOSED 2026-04-24 — a67ec4cb — `pages/customers/CustomerListPage.tsx` — add sort param.
- [ ] WEB-W2-029. **No bulk delete of customers.** — `pages/customers/CustomerListPage.tsx` — add bulk action + route.
- [x] WEB-W2-030. **Membership date uses `toLocaleDateString()` not app helper.** CLOSED 2026-04-24 — 5699cb5e — `pages/customers/CustomerDetailPage.tsx`.
- [ ] WEB-W2-031. **Merge search dual-path response shape handling is fragile.** — `pages/customers/CustomerDetailPage.tsx` — pin to single shape.
- [ ] WEB-W2-032. **No sortable columns on invoice table.** — `pages/invoices/`.
- [ ] WEB-W2-033. **No sortable columns; no bulk actions on estimates list.** — `pages/estimates/`.
- [ ] WEB-W2-034. **Estimate print uses `window.print()` — no clean estimate template.** — add print stylesheet or PDF route.
- [ ] WEB-W2-035. **No sortable columns; no bulk actions on leads list.** — `pages/leads/`.
- [ ] WEB-W2-036. **`converted` lead status has no allowed outbound transitions.** — leads route status machine.
- [x] WEB-W2-037. **MissingPartsCard supplier links use `window.open` — popup blocker risk.** CLOSED 2026-04-24 — b0801919 — `pages/dashboard/` — use anchor with `target="_blank" rel="noopener"`.

### Wave-75 scan-loop findings (2026-04-24) — customer GDPR re-auth (blocked on user WIP)
- [ ] SCAN-1183. **[HIGH] `DELETE /customers/:id/gdpr-erase` admin re-auth has no rate limit + no password length cap — sibling gap of SCAN-1178/1179/1181/1182 + SCAN-1108.**
  <!-- meta: scope=server/routes; files=packages/server/src/routes/customers.routes.ts:1870-1890; fix=checkWindowRate('customer_gdpr_reauth',userId:ip,5,3600_000)+cap-password<=72+recordWindowFailure-on-mismatch; BLOCKED: file is user WIP (never touch per project rule) -->

### POS mockup session findings (2026-04-24) — per-line notes + receipt portal linking + SMS receipt endpoint
- [x] POS-NOTES-001. **POS route does not persist per-line-item `notes`** — `invoice_line_items` table HAS `notes TEXT` column (`packages/server/src/db/migrations/001_initial.sql:616`) and `invoices.routes.ts:498,506,510` reads/writes it with a 1000-char cap. ~~But `pos.routes.ts:605-615` INSERT omits `notes` entirely.~~ FIXED 2026-04-24 — `ResolvedLine` type extended with `notes: string|null`, input validation 1000-char cap, INSERT now writes `notes` param.
- [x] POS-RECEIPT-001 (email). **`/notifications/send-receipt` (email) now embeds public tracking URL** — FIXED 2026-04-24 — notification receipt HTML now includes `View this receipt online:` line. Resolves linked ticket's `tracking_token` → `${host}/track?token=<token>` (direct public access). Falls back to `${host}/track/<orderId>` (phone-last-4 lookup) when no tracking token exists. Uses `req.protocol + req.get('host')` so self-hosted LAN and tenanted subdomains both work.


### Web cycle 2 (packages/web) — 24 findings

### Android cycle 2 (android) — 20 findings

### Management cycle 2 (packages/management) — 16 findings

## AUDIT CYCLE 1 — 2026-04-19 (shipping-readiness sweep, web + Android + management)

### Web (packages/web)
- [ ] AUDIT-WEB-009. **estimate_followup_days + lead_auto_assign settings unwired** — `pages/settings/settingsDeadToggles.ts:82-91`. No backend cron reads them. Fix: mark with visible "Coming Soon" badge in all UI paths (not just the dead-toggle list), or remove inputs.
  - [ ] BLOCKED: listed as not-wired in `settingsDeadToggles.ts` registry; operators can see the dead-toggle indicator when enabled via debug flag. Real fix requires building the follow-up + auto-assign crons (new `services/estimateFollowupCron.ts` + `services/leadAutoAssignCron.ts` + migration linking lead assignment policy), which is ticket-worthy feature scope. Revisit when lead/estimate automation sprint starts.
- [ ] AUDIT-WEB-010. **3CX credentials (tcx_host/username/extension) accepted but never sent** — `pages/settings/settingsDeadToggles.ts:62-76`, marked not-wired but in dev render without badge. Fix: remove fields entirely until 3CX integration exists, or ensure hidden in all environments.
  - [ ] BLOCKED: 3CX PBX integration is a significant new feature (Call Manager API, inbound screen-pop, click-to-dial, presence sync) — not a quick fix. The dead-toggle registry already marks them not-wired. Either remove the inputs in a UI cleanup pass or build the integration as a dedicated sprint. Revisit when VoIP integration is scoped.

### Android (android)
- [ ] AUDIT-AND-010. **Notification preferences device-local only** — `AppPreferences.kt:117-138` 6 notification toggles never sync to server. Fix: `PATCH /api/v1/users/me/notification-prefs` on change (debounced); read back on login.
  - [ ] BLOCKED: requires a server-side endpoint (`PATCH /api/v1/users/me/notification-prefs`) that does not exist yet; needs a DB schema migration adding notification-pref columns to the users table AND a preferences schema decision (per-user vs per-device). Not a pure-Android fix — backend work must land first.
- [ ] AUDIT-AND-012. **[P0 OPS] google-services.json is placeholder — FCM push dead** — `project_number:"000000000000"`, fake API key. `FcmService.onNewToken()` never called. Fix: replace with real `google-services.json` from Firebase console before any release build.
  - [ ] BLOCKED: operator infra task — the owner of the Firebase project must generate a real `google-services.json` from the Firebase console and drop it into `android/app/`. Not code-side fixable; no source-code change resolves this.
- [ ] AUDIT-AND-017. **Virtually all user-facing strings hardcoded — no strings.xml coverage** — `res/values/strings.xml` only 7 entries. i18n + RTL blocked. Fix: extract to strings.xml incrementally; at minimum cover all ContentDescription + error messages before ship.
  - [ ] BLOCKED: multi-week extraction task spanning 100+ screens and 500+ literal strings. Requires a design decision on initial i18n locales, a QA review cycle, and a translation vendor contract. Not a quick-fix batch item. Can ship without for launch locale EN-US; revisit when i18n scope is approved.

### Management (packages/management)
- [ ] AUDIT-MGT-009. **electron-builder.yml forceCodeSigning:false** — `electron-builder.yml:34`. Windows SmartScreen blocks/warns; no integrity guarantee. Fix: treat `forceCodeSigning:true` as release gate; CI check `WIN_CERT_SUBJECT`/`WIN_CERT_FILE` before release build.
  - [ ] BLOCKED: requires purchasing an Authenticode signing certificate from a CA (Sectigo/DigiCert, ~$400/yr). Operator procurement task, not code. Once cert acquired, flip `forceCodeSigning:true` + set `WIN_CERT_SUBJECT`/`WIN_CERT_FILE` env in CI. Re-open post-cert.

## NEW 2026-04-18 (user reported)

- [ ] POSSIBLE-MISSING-CUSTOM-SHOP. **Possible issue: "Create Custom Shop" button missing on self-hosted server** — reported by user 2026-04-18. Investigation needed to confirm why the button is not visible on self-hosted instances. Possible causes: (a) default credentials (admin/admin123) might trigger a different UI state; (b) config flat/env mismatch; (c) logic in `TenantsPage.tsx` or signup entry points hiding it. NOT 100% sure if it's a bug or intended behavior for certain roles/credentials.
  - [ ] BLOCKED: Investigation 2026-04-19 found two candidate "Create Shop" surfaces: (1) `/super-admin` HTML panel at `packages/server/src/index.ts:1375-1384` is gated by BOTH `localhostOnly` middleware AND `config.multiTenant` — if self-hosted deployment runs with `MULTI_TENANT=false` (or unset) the panel 404s; if it runs with `MULTI_TENANT=true` but user accesses it from a non-loopback IP (e.g. Tailscale / LAN / WAN) the `localhostOnly` guard rejects. (2) `packages/management/src/renderer/src/pages/TenantsPage.tsx:162-168` renders a "New Tenant" button (NOT "Create Custom Shop") reachable only through the Electron management app super-admin flow. Cannot reproduce or fully diagnose without access to the user's self-hosted instance — need to know: which panel they're looking at, MULTI_TENANT env value, and the IP they're connecting from. Low-risk / possibly intended behavior; recommend closing once user confirms their deployment mode.

## NEW 2026-04-16 (from live Android verify)


- [x] **POS-SALES-001. Android `pos/sales` endpoint shipped 2026-04-24.** `router.post('/sales', idempotent, ...)` lives in `packages/server/src/routes/pos.routes.ts` (after `/transaction`). Accepts the Android `PosCartLineDto`-shaped cents-based payload natively: customer + walk-in fallback, mixed inventory + misc lines (POS1 server-priced for inventory_item_id, client-priced for misc), tax-class lookup OR client `tax_rate` fallback, optional `linked_ticket_id` for Ready-for-pickup attaches, optional `payments[]` split-tender (max 20, payment_method whitelist), $0.005 underpay tolerance, atomic `adb.transaction` writing `invoices + invoice_line_items + stock_movements + pos_transactions + payments` with guarded stock decrements. Returns `{ invoice_id, order_id, change_cents, approval_code, last_four }`. Android `PosTenderViewModel.finalizeSale` updated to send `payments[]` from the AppliedTender list + `linked_ticket_id` from the coordinator session so split-tender + ready-for-pickup sales link correctly. Server tsc + Android `:app:compileDebugKotlin` clean. Closes the POS finalize 404 path; cart sales now persist end-to-end.

## DEBUG / SECURITY BYPASSES — must harden or remove before production

## CROSS-PLATFORM


- [ ] CROSS9c-needs-api. **Customer detail addresses card (Android, DEFERRED)** — parent CROSS9 split. Investigated 2026-04-17: there is **no `GET /customers/:id/addresses` endpoint** and the server schema stores a **single** address per customer (`address1, address2, city, state, country, postcode` columns on `customers` — see `packages/server/src/routes/customers.routes.ts:861` INSERT and the `CustomerDto` single-address shape). Rendering a dedicated "Addresses" card with billing + shipping rows therefore requires a server-side schema change first: either split into a separate `customer_addresses(id, customer_id, type, street, city, state, postcode)` table with `type IN ('billing','shipping')`, or promote existing columns to a billing address and add parallel `shipping_*` columns. The CustomerDetail "Contact info" card already renders the single address via `customer.address1 / address2 / city / state / postcode` (see `CustomerDetailScreen.kt:757-779`), which covers the data we actually have today. Leaving deferred until the web app commits to one-vs-two address pattern and the server migration lands.
  - [ ] BLOCKED: requires upstream product decision (one vs two customer addresses) + server schema migration BEFORE Android work. Not actionable from client-only.

- [ ] CROSS9d. **Customer detail tags chips (Android)** — parent CROSS9 split. Current Tags card renders the raw comma-separated string; upgrade to proper chip layout once the web tag-chip component pattern is stable.
  - [ ] BLOCKED: Android Compose client work + waits on web tag-chip component pattern to stabilize (still in flux as of 2026-04-19). Re-open when web ships a canonical `TagChip` variant suitable to port.

- [ ] CROSS31-save. **"No pricing configured" manual-price: save-as-default (DEFERRED, schema-shape mismatch with original spec):** confirmed 2026-04-16 — picking a service in the ticket wizard shows "No pricing configured. Enter price manually:" with a Price text field. Option (b) of CROSS31 (save the manual price as a default) was attempted 2026-04-17 but **deferred** because the original task assumed a `repair_services.price` column that **does not exist**. The schema (migration `010_repair_pricing.sql`) stores pricing in `repair_prices(device_model_id, repair_service_id, labor_price)` — a composite key, not a per-service default. Persisting a manual price as "default for this service" therefore requires a `repair_prices` upsert keyed on BOTH the selected device model AND the service (plus a decision on grade/part_price semantics and active flag). Server shape: `POST /api/v1/repair-pricing/prices` with `{ device_model_id, repair_service_id, labor_price }` already exists (see `packages/server/src/routes/repairPricing.routes.ts:171`). Android work needed: (1) add `RepairPricingApi.createPrice` wrapper, (2) add `saveAsDefault: Boolean = false` to wizard state, (3) add Checkbox below the manual-price field, (4) on submit when `saveAsDefault && selectedDevice.id != null && selectedService.id != null`, fire the upsert before `createTicket`. Estimated 45-60 min; out of the 30-min spike budget, so deferring. Options (a) seed baseline prices per category and (c) Settings→Pricing link remain part of first-run shop setup wizard scope.
  - [ ] BLOCKED: Android wizard + repair-pricing API plumbing (4 discrete steps, ~45-60 min) requires working Android device build to verify UI flow. Needs Android dev loop; separate work slice.


- [ ] CROSS35-compose-bump. **Android login Cut action performs Copy instead of Cut — root cause is a Compose regression, NOT app code:** reported by user 2026-04-16. Long-press → Cut inside the Username or Password TextField on the Sign In screen copies the selection to the clipboard but does NOT remove it from the field (should do both). Diagnosed 2026-04-17 — `LoginScreen.kt` uses a vanilla `OutlinedTextField` with no custom `TextToolbar`, `LocalTextToolbar`, or `onCut` override (grep on LoginScreen.kt and the entire `app/src/main` tree confirms zero hits for `TextToolbar` / `LocalTextToolbar` / `onCut` / `ClipboardManager` / `LocalClipboardManager`). Compose BOM is already `2025.03.00` per `app/build.gradle.kts:126` — far past the 2024.06.00+ fix for the earlier reported Cut regression — so the original "upgrade BOM" remediation doesn't apply. There's nothing to patch in user code; this is a deeper framework or device-level regression. Next steps: (a) bump BOM to the latest GA when a newer release is available and re-test; (b) if it still repros post-bump, file a Compose issue with a minimal repro and add a TextToolbar wrapper that re-implements cut = copy + clearSelection as a workaround. Deferred with no code change; kept visible in TODO so a future BOM bump can close it out. (Renamed from CROSS35 → CROSS35-compose-bump to make the dependency explicit.)
  - [ ] BLOCKED: upstream Jetpack Compose framework regression; no code fix in this repo reproducible without the newer Compose BOM being published. Revisit on next BOM bump cycle.

- [ ] CROSS50. **Android Customer detail: redesign layout to separate viewing from acting (accident-prone Call button):** discussed with user 2026-04-16. Current layout puts a HUGE orange-filled Call button at the top plus an orange tap-to-dial phone number in Contact Info — two paths to accidentally dial the customer. On a VIEW screen the top third is wasted on ACTION buttons. Proposed redesign: **(a)** header: big avatar initial circle + name + quick-stats row (ticket count, LTV, last visit date) — informational only; **(b)** Contact Info card displays phone/email/address/org as DISPLAY ONLY, tap each row → action sheet (Call / SMS / Copy / Open Maps) — deliberate two-tap intent for destructive actions like Call; **(c)** body scrolls through ticket history, notes, invoices (CROSS9 content); **(d)** FAB bottom-right (matching CROSS42 pattern) with speed-dial: Create Ticket (primary), Call, SMS, Create Invoice. Rationale: Call has real-world consequences (phone bill, surprised customer), warrants two-tap intent. FAB puts action at thumb reach without eating prime real estate. Frees top half for customer STATE, not ACTION.
  - [ ] BLOCKED: Android-only Compose redesign requiring UX sign-off + device testing on physical hardware. Not code-library-only; needs design iteration. Re-open when Android team has bandwidth for the CustomerDetail layout pass.



- [ ] CROSS57. **Web-vs-Android parity audit — surface advanced web features on Android under a "Superuser" (advanced) tab:** 2026-04-16 audit comparing `packages/web/src/pages/` (≈150 files) vs `android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/` (39 files). Web has many features missing entirely from Android. User directive: "if too advanced for Android, put under Superuser tab so people know it's advanced". Break into **CORE** (must ship on Android, everyday workflows) and **SUPERUSER** (advanced, acceptable in Settings → Superuser). NOT in scope: customer-facing portal (`portal/*`), landing/signup (`signup/SignupPage`, `landing/LandingPage`), tracking public page, TV display — these are non-admin surfaces that don't belong in the admin app.
  - [ ] BLOCKED: 100+ screen parity audit — multi-week scope needing Android team capacity. Can't batch via sub-agent since each screen needs design + implementation + QA pass. Re-open as a dedicated Android parity sprint.

  **Consolidation caveat (verified via code read 2026-04-16):** several Android screens roll multiple web pages into one scrollable detail. When auditing parity, check for consolidation before declaring a feature "missing":
  - Android `TicketDetailScreen.kt` (932 lines) has Customer card + Info row + Devices + Notes + Timeline/History + Photos sections inline. This covers web's `TicketSidebar`, `TicketDevices`, `TicketNotes`, `TicketActions` — NOT missing. Only web-exclusive here is `TicketPayments.tsx` (payments likely route through Invoice in Android).
  - Android `InvoiceDetailScreen.kt` (660 lines) has Status + customer + Line items + Totals + Payments sections inline. Covers `InvoiceDetailPage`. Payment dialog is inline.
  - Android `CustomerDetailScreen.kt` (676 lines) renders email, address, organization, tags, notes SECTIONS CONDITIONALLY — only when data is non-empty. I saw only Phone on Testy McTest because email/address/etc. were all blank. CROSS51 was WRONG: the fields DO display when filled. CROSS9 still valid because **no ticket history, no invoice history, no lifetime value** is rendered regardless of data.
  - Android `SmsThreadScreen.kt` (441 lines) is bare conversation UI — genuinely missing every communications-advanced feature (templates inline, scheduled, assign, tags, sentiment, bulk, attachments, canned responses, auto-reply).

  **A. CORE — must add to Android (everyday workflows):**
  - **Unified POS cart/checkout**: `web/unified-pos/*` (14 files). Android currently has POS landing ("Quick Sale: Coming soon" — CROSS14). Needs full cart, product picker, discount, payment, receipt.
  - **Ticket Kanban board**: `web/tickets/KanbanBoard.tsx`. Android parity = alternate view mode on Tickets list (swipe between list/kanban).
  - **Ticket Payments panel**: `web/tickets/TicketPayments.tsx`. Either add a Payments section to TicketDetailScreen or route a "Take payment" action to a new screen.
  - **Communications advanced (genuinely missing on Android)**: in SmsThreadScreen add inline template picker, scheduled-send modal, assign-to-tech, conversation tags, attachment button, canned-response hotkeys; in SmsListScreen add bulk-SMS modal, failed-send retry list, off-hours auto-reply toggle, team-inbox header, sentiment badges.
  - **Lead pipeline (Kanban)**: `leads/LeadPipelinePage.tsx`.
  - **Lead calendar view**: `leads/CalendarPage.tsx`.
  - **Customer LTV/health badges**: `customers/components/HealthScoreBadge.tsx`, `LtvTierBadge.tsx`. Attach to CustomerDetailScreen quick-stats (fits CROSS50 redesign).
  - **Customer photos wallet**: `customers/components/PhotoMementosWallet.tsx`.
  - **Customer ticket/invoice history sections on CustomerDetailScreen**: genuinely missing — add a Tickets section (recent 5 tickets) and Invoices section (recent 5) that tap through to detail screens. Code already has `onNavigateToTicket` callback wired but never renders a list.
  - **Reports tabs**: Web has CustomerAcquisition, DeviceModels, PartsUsage, StalledTickets, TechnicianHours, WarrantyClaims, PartnerReport, TaxReport. Android ReportsScreen has 3 tabs (Dashboard / Sales / Needs Attention — CROSS36). Port the 8 additional report tabs.
  - **SMS templates**: Android HAS SmsTemplatesScreen — verify parity against web `SmsVoiceSettings` (separate audit task).
  - **Photo capture wiring**: Android has `PhotoCaptureScreen` — verify it's wired into TicketDetailScreen photo-add flow and InventoryDetail barcode/photo flow.
  - **Team features**: `team/MyQueuePage` (Android shows "My Queue" card on dashboard but taps "View All" — verify where it lands), `team/ShiftSchedulePage`, `team/TeamChatPage`, `team/TeamLeaderboardPage`. MyQueue + TeamChat highest value on mobile.

  **B. SUPERUSER — put under Settings → Superuser (advanced, power-user):**
  - **Billing & aged receivables**: `billing/AgingReportPage`, `DunningPage`, `PaymentLinksPage`, `CustomerPayPage`, `DepositCollectModal`. Owner/bookkeeper concerns, not day-to-day tech.
  - **Advanced inventory ops**: `AbcAnalysisPage`, `AutoReorderPage`, `BinLocationsPage`, `InventoryAgePage`, `MassLabelPrintPage`, `PurchaseOrdersPage`, `SerialNumbersPage`, `ShrinkagePage`, `StocktakePage`. Ship under Inventory → Advanced or Superuser. Stocktake especially benefits from mobile (barcode + on-floor counting).
  - **Marketing suite**: `marketing/CampaignsPage`, `NpsTrendPage`, `ReferralsDashboard`, `SegmentsPage`. Owner-level, not tech-level.
  - **Team admin**: `team/GoalsPage`, `PerformanceReviewsPage`, `RolesMatrixPage` (permissions matrix). Manager-only.
  - **Settings — 15 tabs missing**: AuditLogsTab, AutomationsTab, BillingTab, BlockChypSettings, ConditionsTab, DeviceTemplatesPage, InvoiceSettings, MembershipSettings, NotificationTemplatesTab, PosSettings, ReceiptSettings, RepairPricingTab (**fixes CROSS31 no-pricing bug**), SmsVoiceSettings, TicketsRepairsSettings, SetupProgressTab. Android Settings is bare (CROSS38: only 3 toggles). All these tabs should be accessible on Android — at minimum RepairPricingTab, ReceiptSettings, TicketsRepairsSettings as CORE, the rest under Superuser.
  - **Catalog browser**: `catalog/CatalogPage.tsx` — supplier device catalog. Useful during ticket intake when tech needs parts price/availability.
  - **Cash register**: `pos/CashRegisterPage.tsx` — open/close shift, cash counts. Ship as CORE if tenant uses cash (most repair shops do).
  - **Setup wizard**: `setup/SetupPage.tsx` + steps. First-run only — lives on SSW1 (existing TODO). Not needed as Settings tab, but Android should respect the `setup_wizard_completed` flag and show the wizard on first login.

  **C. Recommended Android Settings information architecture:**
  ```
  Settings
    ├─ Profile (existing ProfileScreen)
    ├─ Device preferences (haptic, dark mode — existing)
    ├─ Store
    │   ├─ Store info (hours, address, phone) — maps to web StepStoreInfo
    │   ├─ Receipts — maps to ReceiptSettings
    │   ├─ Tax — maps to StepTax
    │   └─ Repair pricing — maps to RepairPricingTab (fixes CROSS31)
    ├─ Communications
    │   ├─ SMS templates (existing SmsTemplatesScreen)
    │   ├─ SMS/Voice provider — maps to SmsVoiceSettings
    │   └─ Notification templates — maps to NotificationTemplatesTab
    ├─ Tickets & Repairs — maps to TicketsRepairsSettings
    ├─ Team
    │   ├─ Employees (existing)
    │   ├─ Clock in/out (existing ClockInOutScreen)
    │   └─ Roles & permissions — maps to RolesMatrixPage (superuser)
    ├─ Integrations
    │   ├─ BlockChyp / Stripe — maps to BlockChypSettings
    │   └─ Memberships — maps to MembershipSettings (superuser)
    └─ Superuser (advanced)
        ├─ Audit logs — AuditLogsTab
        ├─ Automations — AutomationsTab
        ├─ Billing / subscription — BillingTab
        ├─ Conditions / warranty — ConditionsTab
        ├─ Device templates — DeviceTemplatesPage
        ├─ Invoice settings — InvoiceSettings
        ├─ POS settings — PosSettings
        ├─ Inventory advanced (ABC, auto-reorder, bins, aging, labels, POs, serials, shrinkage, stocktake)
        └─ Marketing (campaigns, NPS, referrals, segments)
    ├─ Data sync (existing)
    └─ Log out (NEW — fixes CROSS38)
  ```
  Superuser tab must be HIDDEN behind a tap-the-logo-5-times-style easter egg OR visible to users with role=owner only, so regular techs don't get lost in power-user surfaces. Toast on first reveal: "Superuser settings unlocked — advanced options may change app behavior."

  **D. Icons / cross-surface notes:**
  - Missing QR/barcode scanner entry from POS and Ticket Detail (intake by barcode). Android has BarcodeScanScreen — wire additional entry points.
  - Missing Z-report / end-of-day report on Android POS (web has ZReportModal).
  - Missing "Training mode" flag on Android POS (web has TrainingModeBanner).
  - Missing Cash Drawer integration on Android POS.

## TENANT-OWNED STRIPE + SUBSCRIPTION CHARGING

- [ ] TS1. **Per-tenant Stripe integration for tenant → customer payments:** the env `STRIPE_SECRET_KEY` is PLATFORM-only (CRM subscription billing). Tenants currently rely on BlockChyp for their customer card payments and have no Stripe option. Add tenant-owned Stripe creds (`stripe_secret_key`, `stripe_publishable_key`, `stripe_webhook_secret`) to `store_config`, expose a Settings → Payments UI for the tenant admin to paste them, and route all customer-facing Stripe calls (POS card, payment links, refunds) through the tenant's keys — never env. Webhook dispatcher must identify tenant from the Stripe account ID or dedicated subdomain path (`/api/v1/webhooks/stripe/tenant/:slug`) so each tenant's events land on their own DB. Liability: tenant owns their Stripe account, chargebacks hit their merchant balance, not platform's.
  - [ ] BLOCKED: large feature — per-tenant creds table / store_config additions, tenant-aware Stripe client factory, UI for tenant admin, webhook dispatcher rework. Not a single-commit change.

- [ ] TS2. **Recurring subscription charging for tenant memberships:** `membership.routes.ts` supports tier periods (`current_period_start`, `current_period_end`, `last_charge_at`) and enrolls cards via BlockChyp `enrollCard`, but there is NO scheduled worker that actually re-charges stored tokens when a period ends. Today a tenant must manually run a charge each cycle. Add a cron-driven renewal worker: for every active membership where `current_period_end <= now()` and `auto_renew = 1`, invoke `chargeToken(stored_token_id, tier_price)`, extend the period, and record `last_charge_*`. On failure: retry schedule (day 1, 3, 7), dunning email, suspend membership after final failure. Must work for both BlockChyp stored tokens AND (once TS1 lands) Stripe subscriptions.
  - [ ] BLOCKED: depends on TS1 for Stripe path; BlockChyp-only partial would work today but still needs a durable retry schedule + dunning email design. Multi-commit feature.



## TENANT PROVISIONING HARDENING — 2026-04-10 (Forensic analysis)

Root-cause investigation after a `bizarreelectronics` signup on 2026-04-10 got stuck in `status='provisioning'` for hours until manual repair via `scripts/repair-tenant.ts`. Two parallel Explore agents traced the failure. Verdict: **Node 24 / better-sqlite3 Node-22 ABI crash** (libuv assertion `!(handle->flags & UV_HANDLE_CLOSING)`, exit code 3221226505) fired during STEP 3 of `provisionTenant()` — most likely inside `new Database(dbPath)` or the `bcrypt.hash()` worker-thread call. The native module abort killed the process instantly, so the `cleanup()` closure (defined locally inside `provisionTenant`) was never reached. The master row survived at `status='provisioning'`, the filesystem was left half-written, and the HTTP client got a TCP RST with no response body.

Critical gaps found in the current codebase:

- **`cleanupStaleProvisioningRecords()` exists but is never invoked.** Defined at `packages/server/src/services/tenant-provisioning.ts:348`. Grep confirms zero call sites. It would have recovered the stuck row on the next restart if it had been wired into startup.
- **No HTTP request / header / keep-alive timeouts.** `httpsServer.requestTimeout`, `.headersTimeout`, `.keepAliveTimeout` are all default (effectively infinite). A stalled provisioning request can hang indefinitely without abort.
- **Crash was invisible to `crash-log.json`.** Native-module aborts don't produce JavaScript exceptions, so `process.on('uncaughtException')` at `index.ts:1503` never fired and `recordCrash()` was never called. The only evidence of the failure was the stuck row itself.
- **`migrateAllTenants()` silently skips `provisioning` rows.** It queries `WHERE status = 'active'` (see `migrate-all-tenants.ts:45`), so stuck tenants fall through every startup without notice.
- **`cleanup()` is a local closure, not an event handler.** Closures die with the process. The design assumes the process stays alive; it has no recovery story for mid-flow crashes.

All items below MUST respect the project rule: **never delete tenant DB files.** Anything that would auto-`fs.unlinkSync` a tenant artifact is a non-starter.

### TPH — Tenant Provisioning Hardening










## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10

Self-serve signup on 2026-04-10 with slug `dsaklkj` completed successfully and the user was able to log in, but the shop then dropped them straight into the dashboard without asking for any of the info that `store_config` needs: store name (we set it from the signup form, but only that one key), phone, address, business hours, tax settings, receipt header/footer, logo, and — critically — whether they want to import existing data from RepairDesk / RepairShopr / another system. Result: the shop boots with mostly empty defaults and the user has to hunt through Settings to fill everything in. Poor first-run UX.

- [ ] SSW1. **First-login setup wizard gate:** on first login after signup, if `store_config.setup_completed` is `'true'` but a new `setup_wizard_completed` flag is missing (or `'false'`), show a full-screen modal wizard instead of the dashboard. Wizard collects all the fields currently buried in Settings → Store, Settings → Receipts, and Settings → Tax. Dismissal is only possible via "Complete setup" (all required fields filled) or "Skip for now" (sets a `setup_wizard_skipped_at` timestamp so we can nag on subsequent logins). After completion, set `setup_wizard_completed = 'true'`.
  - [ ] BLOCKED: feature spanning web React modal + server store_config flag + skip-nag tracker. Single-commit unsafe; tracks best as its own PR. SSW1-5 form one feature.

- [ ] SSW2. **Import-from-existing-CRM step in the wizard:** the existing import code lives at `packages/server/src/services/repairDeskImport.ts` and similar. Expose it as a wizard step: "Do you have data from another CRM?" → show RepairDesk, RepairShopr, CSV options. For RepairDesk/RepairShopr, ask for their API key + base URL inline, validate it, then kick off a background import with a progress indicator. User can come back to it later if it takes a while. On skip, just move on.
  - [ ] BLOCKED: depends on SSW1; also needs live RepairDesk / RepairShopr API creds for round-trip validation. Multi-day feature.

- [ ] SSW3. **Comprehensive field audit:** enumerate every `store_config` key referenced by the codebase and the whole `Settings → Store` page. For each one, decide:
  - Is it REQUIRED for a functioning shop? (name, phone, email, address, business hours, tax rate, currency) → wizard must collect it
  - Is it OPTIONAL but affects visible UX from day 1? (logo, receipt header/footer, SMS provider creds) → wizard offers it with "skip" option
  - Is it ADVANCED / power-user only? (BlockChyp keys, phone, webhooks, backup config) → wizard skips entirely, user configures later in Settings
  The audit output should drive which fields appear in the wizard, in what order, and with what defaults.
  - [ ] BLOCKED: audit is a one-off research task that feeds SSW1. Should happen alongside SSW1 scoping, not in isolation.

- [ ] SSW4. **RepairDesk API typo compatibility reminder:** per `CLAUDE.md`, RepairDesk uses typo'd field names (`orgonization`, `refered_by`, `hostory`, `tittle`, `createdd_date`, `suplied`, `warrenty`). Any new import wizard code must preserve these exactly. Add a test that round-trips a fixture through the import to catch anyone who "fixes" a typo.
  - [ ] BLOCKED: test-infrastructure work tied to SSW2. Trivial once test harness lands, blocked without it.

- [ ] SSW5. **Test plan for first-run wizard:** after SSW1-4 are implemented, add an E2E test that signs up a brand-new shop via `POST /api/v1/signup`, logs in, and asserts:
  - Wizard modal appears (not the dashboard)
  - Each required field blocks "Complete setup" when empty
  - "Complete setup" actually writes every field to `store_config` with the correct key names
  - Subsequent logins do NOT show the wizard
  - "Skip for now" sets the timestamp but re-shows the wizard on next login
  - [ ] BLOCKED: depends on SSW1-4 shipping; e2e harness + Playwright needed.

## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)

### Agent 1: Authentication & Session Management
- [ ] SA1-2. **Session Storage:** Authentication tokens stored in `localStorage` in the frontend are theoretically vulnerable. Migration to `httpOnly` secure cookies for the `accessToken` is recommended (currently only `refreshToken` uses cookies).
  - [ ] BLOCKED: full auth refactor — every web API call in `packages/web/src/api/**` sends the token from localStorage via axios interceptor; the server expects `Authorization: Bearer ...` and supports CSRF via double-submit. Migrating accessToken to httpOnly requires (1) server reads cookie OR header, (2) CSRF double-submit header on every mutating route, (3) web axios interceptor removes bearer header, (4) SW token refresh path still works over cookie, (5) Android app unaffected (keeps bearer). Too large for a single-item commit; should ship as its own PR with security-reviewer pass. Overlaps D3-6.

### Agent 2: Database Integrity & Queries
### Agent 3: Input Validation & Mass Assignment

### Agent 4: Frontend XSS Vulnerabilities

### Agent 5: Backend API Endpoint Abuse

### Agent 6: Component Rendering & React State

### Agent 7: Background Jobs & Crons

### Agent 8: Desktop/Electron App Constraints

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt

## DEEP AUDIT ESCALATION - Advanced Security & Technical Debt (April 12, 2026)

### 1. Incomplete File Upload Constraints (Path Traversal/DoS)

### 2. File Corruptions via Non-Atomic Writes

### 3. Synchronous CPU Event-Loop Locks

### 4. Cryptographic Defaults

### 5. SQLite Parameter Array Bounds Execution Halt 

### 6. Idempotency Skips in Financial Bridging

### 7. Global Socket Scope Leakage

### 8. Hardcoded Secret Entanglements 

### 9. Cookie Parsing Signing Exclusions

### 10. Floating Promises in Database Interfacing

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 1. Remote Code Execution (RCE) via Backup Paths

### 2. Missing Database Concurrency Locks

### 3. Server OOM via Unbounded Image Streams

### 4. Horizontal Privilege Escalation (IDOR)

### 5. Regular Expression Denial of Service (ReDoS)

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely. — **Partial mitigation in place:** refreshToken is already `httpOnly + secure + sameSite: 'strict'` (auth.routes.ts:269), so XSS cannot rotate a session. AccessToken is short-lived. Full migration to httpOnly access cookie + CSRF header is a larger auth refactor — tracked but deferred.
  - [ ] BLOCKED: dup of SA1-2 — same auth refactor. Consolidate under SA1-2.

### 7. Global Socket Scopes via Offline Maps

### 8. Null-Routing on Background Schedulers

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
_See DONETODOS.md for D4-1 closure._

### 2. Form Input Hindrances on Mobile/Touch

### 3. Flash of Skeleton Rows (Flicker)

### 4. Poor Error Boundary Granularity

### 5. Infinite Undo/Redo Voids
_See DONETODOS.md for D4-5 closure._

### 6. Modal Focus Traps (WCAG Violation)

### 7. WCAG "aria-label" Screen-Reader Blindness

### 8. FOUC (Flash of Unstyled Content) on Dark Mode

### 9. HCI Touch Target Ratios
_See DONETODOS.md for D4-9 closure._

### 10. Indefinite Stacking Toasts

## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)

### 1. Complete TalkBack Annihilation

### 2. Missing Compose List Keys (Jank)
_See DONETODOS.md for D5-2 closure._

### 5. Infinite Snackbar Queues
_See DONETODOS.md for D5-5 closure._

### 8. Viewport Edge Padding Overlaps

## FUNCTIONALITY AUDIT - MOVED FROM functionalityaudit.md

# Functionality Audit

Scope: static audit of the BizarreCRM web/server codebase for user-visible usability bugs, disconnected buttons, TODO/stub behavior, and partially implemented enrichment features. This pass read `CLAUDE.md`, `README.md`, and used parallel code-review agents plus manual verification of the highest-risk findings.

## Executive Summary

- Highest risk area: public/customer-facing payment and messaging flows. Several buttons look live but either hit missing routes or mark payment state without a real provider checkout.
- Main staff-facing risk: settings and workflow controls are sometimes rendered as normal live controls even when metadata or code says the behavior is only planned.
- Most valuable quick wins: hide or badge incomplete controls, wire missing backend routes for customer-facing CTAs, and add navigation/entry points for pages/components that already exist.

## Medium Priority Findings

## Low Priority / Usability Findings

  - `packages/web/src/components/shared/CommandPalette.tsx` searches entities only (tickets, customers, inventory, invoices), not static app pages.

## Second Pass Additions

These items were found in a fresh second pass and are not duplicates of the findings above.

## Medium Priority Findings

## Low Priority / Usability Findings

## APRIL 14 2026 CODEBASE AUDIT ADDITIONS

Static audit scope: global deploy config, server authorization/business logic, reachable web UI, Electron management IPC, Android sync/storage/networking, and shared permission contracts. No source-code changes were made; these items capture follow-up work only.

## High Priority Findings


  Evidence:

  - `docker-compose.yml:7` maps `"443:443"` and `docker-compose.yml:16` sets `PORT=443`.
  - `packages/server/Dockerfile:84` says containerized runs should set `PORT=8443`, while `packages/server/Dockerfile:89` switches to `USER node` and `packages/server/Dockerfile:92` still exposes `443`.

  User impact:

  The default container path can fail at boot because a non-root Linux process cannot bind privileged port 443 without extra capabilities.

  Suggested fix:

  Align the container contract around an unprivileged internal port: set compose to `443:8443`, set `PORT=8443`, expose `8443`, and update any health checks or docs that still assume in-container 443.


  Evidence:

  - `packages/server/src/middleware/auth.ts:167` authorizes requests from the shared hardcoded `ROLE_PERMISSIONS[req.user.role]` map plus `users.permissions`.
  - `packages/server/src/routes/roles.routes.ts:228-236` reads the editable `role_permissions` matrix for display/update flows.
  - `packages/server/src/routes/roles.routes.ts:316-320` assigns roles by writing `user_custom_roles`, but the auth middleware never reads `user_custom_roles` or `role_permissions`.

  User impact:

  Admins can edit and assign custom roles that look real in the management UI but do not change route authorization. Staff may keep access they were supposed to lose, or lose access that the custom role appears to grant.

  Suggested fix:

  Resolve effective permissions in one server-side place: join the user to `user_custom_roles`/`role_permissions`, keep the default role fallback for legacy users, and align the permission key list with `@bizarre-crm/shared`.



## Medium Priority Findings


  Evidence:

  - `packages/server/src/middleware/masterAuth.ts:14-18` pins `algorithms`, `issuer`, and `audience`, and `packages/server/src/middleware/masterAuth.ts:36` applies those options.
  - `packages/server/src/routes/super-admin.routes.ts:169` and `packages/server/src/routes/super-admin.routes.ts:475` call `jwt.verify(token, config.superAdminSecret)` without verify options.
  - `packages/server/src/routes/super-admin.routes.ts:447-450` signs the active super-admin token with only `expiresIn`, and `packages/server/src/routes/management.routes.ts:231` verifies management tokens without issuer/audience/algorithm options.

  User impact:

  Super-admin JWT handling is inconsistent across master, super-admin, and management APIs. Tokens signed with the same secret are not scoped by audience/issuer, and future algorithm/config regressions would only be caught in one middleware path.

  Suggested fix:

  Centralize super-admin JWT sign/verify helpers with explicit `HS256`, issuer, audience, and expiry, then use them in super-admin login/logout, management routes, and master auth.




## Low Priority / Audit Hygiene Findings

_(AUD-20260414-L1 — closed 2026-04-17, see DONETODOS.md.)_

---

# APRIL 14 2026 ANDROID FOCUSED AUDIT ADDITIONS

## High Priority / Android Workflow Breakers




## Medium Priority / Android UX and Navigation Gaps



## Low Priority / Android Polish

## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

### Phase 0 — Pre-flight inventory







### Phase 1 — Secrets sweep (post-init verification)





### Phase 2 — JWT, sessions, auth hardening







### Phase 3 — Input validation & injection












### Phase 4 — Transport, headers, CORS






### Phase 5 — Multi-tenant isolation





### Phase 6 — Logging, monitoring, errors




### Phase 7 — Backups, data, recovery



### Phase 8 — Dependencies & supply chain







### Phase 9 — Build & deploy hygiene











### Phase 10 — Repo polish for public release



















### Phase 11 — Operational





- [ ] PROD103. **Log rotation on `bizarre-crm/logs/`:** prevent unbounded growth.
  - [ ] BLOCKED: canonical rotation is host-supervisor concern (PM2 `pm2-logrotate`, journald + `systemd-journal`, Docker log-driver `max-size`) — already documented in ecosystem.config.js. Operator infra task, not app code. Same blocker class as SEC-M28-pino-add. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.



### Phase 12 — Final pre-publish checklist (gate before flipping public)

- [ ] PROD106. **Phase 1–6 (all PROD items above) complete and clean.**
  - [ ] BLOCKED: meta-gate — depends on PROD102-105 and human-smoke items PROD109-112 being closed. Vacuously BLOCKED until every predecessor is either migrated or has its own BLOCKED note.

- [ ] PROD107. **All security tests pass:** `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests, 3 phases per CLAUDE.md).
  - [ ] BLOCKED: the three security-tests shell scripts require a running server on port 443 with seeded tenant DB. No live server in this worktree; cannot invoke. Operator must run post-deploy.


- [ ] PROD109. **Server starts cleanly with fresh `.env`** (only `JWT_SECRET`, `JWT_REFRESH_SECRET`, `PORT`).
  - [ ] BLOCKED: post-SEC-H105 this now also requires `SUPER_ADMIN_SECRET` in production. Human smoke-test step — spin up a fresh `.env`, boot server, confirm no fatal. Not reproducible in the worktree without a port-443 bind + live PM2/systemd context.

- [ ] PROD110. **Manual smoke: login as default admin → change password → 2FA flow.**
  - [ ] BLOCKED: manual multi-step UI smoke (login → change password → 2FA). Needs live server + browser session. Can't be reliably scripted without Playwright + running preview, out of the current loop scope.

- [ ] PROD111. **Manual smoke: signup new tenant → tenant DB created → data isolation verified.**
  - [ ] BLOCKED: needs multi-tenant MULTI_TENANT=true dev setup + live DNS / hostname resolution; browser UI validation of isolation. Operator smoke-test only.

- [ ] PROD112. **Backup → restore on scratch dir → data round-trips.**
  - [ ] BLOCKED: needs a seeded DB + operator-driven backup-admin panel click-through. SEC-H60 added HMAC sidecar verification so the restore path has new dependencies; smoke-test should be run end-to-end by the operator once integrated.

- [ ] PROD113. **`git status` clean, `git log` reviewed for embarrassing commit messages.**
  - [ ] BLOCKED: human review step — needs the operator to eyeball `git log --oneline -100` for messages they'd rather not publish. Not a scripted fix.

- [ ] PROD114. **Push to PRIVATE GitHub repo first → verify CI passes → no secret-scanning alerts → THEN flip public.**
  - [ ] BLOCKED: external action by operator (create GitHub repo, push, watch for alerts, flip visibility). Cannot be automated from inside the repo.

- [ ] PROD115. **Post-publish: subscribe to GitHub secret scanning + Dependabot alerts.**
  - [ ] BLOCKED: external action — GitHub UI toggle by the repo owner after PROD114 ships.

### Phase 99 — Findings (open decisions/risks from executor)



## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

### CRITICAL

### HIGH — auth

### HIGH — authz

### HIGH — payment

- [ ] SEC-H34-money-refactor. **Convert money columns REAL → INTEGER (minor units)** across invoices/payments/refunds/pos_transactions/cash_register/gift_cards/deposits/commissions. (PAY-01) DEFERRED 2026-04-17 — scope is fleet-wide: schema migration across 8+ tables in every per-tenant DB, every SELECT/INSERT/UPDATE in server code that touches those columns (dozens of handlers in invoices/pos/refunds/giftCards/deposits/membership/blockchyp/stripe/reports routes + retention sweepers + analytics), web DTO + form handling (every money field in pages/invoices, pages/pos, pages/refunds, pages/giftCards, pages/deposits, pages/reports), and Android DTO + UI updates. Recipe: (1) add new `_cents` INTEGER columns alongside each existing REAL column; (2) dual-write period where both columns are kept in sync; (3) flip reads to the cents columns handler-by-handler; (4) reconcile any drift; (5) drop REAL columns. Each step must ship separately with its own verification; skipping this phasing risks silent rounding corruption on live invoices. Not safe as a single commit. Blocks SEC-H37 (currency column) — they should land as a joint cents+currency migration.
  - [ ] BLOCKED: fleet-wide 5-step rollout (dual-write, per-handler flip, drift reconciliation, REAL-column drop) spanning server + web + Android. Not safe as a single commit; each step needs its own verification pass and live-money QA. Needs: dedicated multi-week workstream separate from the todo loop. Not attempted this run.
- [ ] SEC-H40-needs-sdk. **Deposit DELETE must call processor refund;** link to originating `payment_id`; update invoice amount_paid/amount_due on apply. `deposits.routes.ts:218-245, 165-215`. (PAY-19, 20) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `refund()` wrapper today (only processPayment, adjustTip, enrollCard, chargeToken, createPaymentLink). Recipe: (1) add `refundCharge(transactionId, amount)` wrapping the SDK's refund endpoint with idempotency-key bookkeeping matching the processPayment pattern (BL13 style); (2) link `deposit.payment_id` on the apply-to-invoice path so DELETE knows which transaction to reverse; (3) call `refundCharge()` from DELETE /:id BEFORE flipping `refunded_at`, storing the processor refund id on the deposit row; (4) on apply, update the linked `invoices.amount_paid` / `amount_due` so the invoice reconciles. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit. Same SDK dependency class as SEC-H41-needs-sdk / SEC-H45-needs-sdk — batch together.
  - [ ] BLOCKED: requires adding BlockChyp SDK `refund()` wrapper (`services/blockchyp.ts`) + live terminal smoke-test. No SDK access in this environment. Batch with SEC-H41 / SEC-H45.
- [ ] SEC-H41-needs-sdk. **BlockChyp `/void-payment` must call `client.void()`** at processor + add BlockChyp webhook receiver. `blockchyp.routes.ts:359-397`. (trace-pos-005 / trace-webhook-002) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `void()` wrapper today. Recipe: (1) add voidCharge(transactionId) wrapping the SDK's void endpoint, (2) call it from /void-payment before signature cleanup, (3) record processor-side errors back to the payment row, (4) add /webhooks/blockchyp receiver with HMAC verify. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit.
  - [ ] BLOCKED: needs BlockChyp SDK `void()` wrapper + HMAC-verified webhook receiver + live terminal smoke-test. No SDK / hardware access here. Batch with SEC-H40 / SEC-H45.
- [ ] SEC-H45-needs-sdk. **Membership `/subscribe` verify `blockchyp_token` with processor** before activating subscription. `membership.routes.ts:140-203`. (LOGIC-024) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no token-validation helper. Recipe: add `verifyCustomerToken(token)` wrapping the SDK customerLookup/tokenMetadata endpoint, call before INSERT, reject 400 if token not found processor-side, record audit. Same SDK dependency as SEC-H41-needs-sdk — batch together.
  - [ ] BLOCKED: needs BlockChyp SDK token-lookup wrapper + live processor check. Batch with SEC-H40 / SEC-H41.
- [ ] SEC-H47-refactor. **Bulk `mark_paid` route through `POST /:id/payments`** (currently hardcodes cash, skips dedup/webhooks/commissions). `invoices.routes.ts:695-725`. (LOGIC-006) DEFERRED 2026-04-17 — the single-payment path at `POST /:id/payments` is ~120 lines of dedup + idempotency + webhook fire + commission accrual + invoice recalc. Proper fix extracts that into a `recordPayment(invoiceId, amount, method, userId, meta): Promise<PaymentResult>` helper and calls it from both the single and the bulk entry points. Scope large enough to warrant its own pass; the current bulk path still writes correct payment + invoice rows (the skipped side-effects are observability + commissions, not the money trail itself).
  - [ ] BLOCKED: needs a dedicated `recordPayment(...)` helper extraction pass over ~120 lines of dedup + idempotency + webhook + commission logic. Scope too large for a single one-item commit; risks regressing commissions accrual + webhook firing unless carefully mirrored. Keep as a separate work-slice.

### HIGH — pii


### HIGH — concurrency


### HIGH — reliability


### HIGH — public-surface


### HIGH — electron + android


### HIGH — crypto


### HIGH — supply-chain + tests


### HIGH — logic


### HIGH — ops (additional)


### MEDIUM

- [ ] SEC-M21-captcha. **Portal register/send-code CAPTCHA on first new IP** — DEFERRED 2026-04-17. The 24h per-phone hard cap (10/day) shipped in the same commit that closed the main SEC-M21 entry. CAPTCHA-on-first-new-IP remains open because it requires a CAPTCHA provider integration (hCaptcha / reCAPTCHA / Turnstile) — recipe: (1) pick a provider + bake site key into env, (2) front-end widget on portal registration step, (3) server-side `verifyCaptcha(token, remoteIp)` before consuming rate buckets, (4) bypass for already-seen IPs (new table, 30-day TTL), (5) audit failures.
  - [ ] BLOCKED: needs product decision on CAPTCHA provider + account signup + env-var wiring + public-portal JS widget integration. Not code-only.
- [ ] SEC-M28-pino-add. **Rotating logger** (pino/winston file transport + max size). `utils/logger.ts`. (REL-015) DEFERRED 2026-04-17 — adding pino/winston is a dependency + build change (neither is currently in `packages/server/package.json`). Meanwhile `utils/logger.ts` already emits structured JSON on stdout/stderr with PII redaction + level gating. The canonical rotation path for production deployments is the host supervisor, NOT the app:
    - PM2: `pm2-logrotate` module handles size/time-based rotation (already documented in ecosystem.config.js).
    - systemd: `journald` with `SystemMaxUse=` + `MaxFileSec=` in `journald.conf`.
    - Docker / Kubernetes: the container log driver (`json-file max-size`, `max-file`; or a cluster aggregator like Loki/Fluent Bit).
    - Bare metal: `logrotate` + a `>>` redirect wrapper.
  App-level rotation is a secondary concern — it can duplicate work the supervisor already does and introduces a new failure mode (log disk-full handling inside the Node process). Revisit only if ops reports a scenario where host rotation is not available.
  - [ ] BLOCKED: intentionally deferred — host-supervisor rotation (PM2 / journald / Docker) is the canonical path and already documented. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.
- [ ] SEC-M36. **Tenant-owned Stripe + recurring charge worker** [uncertain — overlap TS1/TS2]
  - [ ] BLOCKED: same scope as TS1 + TS2 (tenant-owned Stripe integration + recurring billing worker) — both BLOCKED on product decision about whether tenants use their own Stripe account vs. platform-relay model. Do not implement until TS1/TS2 unblocks.
- [ ] SEC-M61. **user_permissions fine-grained capability table** (replace role='admin' grab-bag). (LOGIC-017)
  - [ ] BLOCKED: partially addressed 2026-04-19 by SEC-H25 — 17 new permission constants + role matrix (`ROLE_PERMISSIONS` in middleware/auth.ts) + `requirePermission` gates on 72 mutating handlers. Remaining for full SEC-M61: schema migration for `user_permissions` table (user_id, permission, granted_at, granted_by), UI for admin to toggle per-user overrides, and `hasPermission()` check that consults both role matrix AND user overrides. Defer as a follow-up — the role matrix is the authoritative path today and covers the common case; per-user overrides can be added incrementally without a schema break.
### LOW

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

- [ ] **IMAGE-FORMAT-PARITY-001. Cross-platform image-format support (HEIC / TIFF / DNG).**
  Surfaced from `ios/ActionPlan.md §29.3`. iOS photo captures default to HEIC since iOS 11; DNG comes from "pro" cameras and iPhone ProRAW; TIFF from scanners and multi-page documents. iOS Image I/O decodes all of these natively. Parity unknowns:
  - `packages/server/src/` uploads endpoint — confirm it accepts `image/heic`, `image/heif`, `image/tiff`, `image/x-adobe-dng`. Today likely JPEG/PNG only; needs audit. File-size limits must be re-evaluated because DNG + multi-page TIFF are much larger than JPEG.
  - `packages/web/src/` — `<img>` HEIC support is Safari-only; Chrome + Firefox still don't render HEIC client-side. Server must transcode to JPEG for web display OR web must reject uploads in those formats. Decision: pick one (transcode preferred).
  - `android/` — Android 9+ handles HEIC; older devices do not. Android DNG + TIFF is uneven. Same transcode-on-upload or reject path.
  - iOS: confirms formats decode locally, uploads honor whatever server accepts, surfaces "Your shop's server doesn't accept X — convert or attach different file" when rejected.
  Recommend server-side transcoding to JPEG on ingestion so all clients see a consistent format; keep original on server for download. Block iOS implementation of TIFF / DNG / HEIC upload until this is decided.

- [ ] **TEAM-CHAT-AUDIT-001. Team chat data-at-rest audit (server + clients).**
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

- [ ] **TEAM-CHAT-ANDROID-PARITY-001. Android team-chat client missing.**
  Surfaced from `ios/ActionPlan.md §47`. Server + web both ship team chat today (`/api/v1/team-chat`, `/team/chat`). Android has zero references. Parity work for Android: list channels, thread view, compose + @mention, polling with `?after=<id>` cursor (matches server MVP), room for later WS upgrade. Shares schema with iOS once iOS ships; both should use the same shape so server doesn't grow per-client variants. Blocks iOS team-chat merge.

- [ ] **STOCKTAKE-ANDROID-PARITY-001. Android stocktake missing.**
  Surfaced from `ios/ActionPlan.md §60` / §89. Server has `/api/v1/stocktake` (`stocktake.routes.ts`) and web has `pages/inventory/StocktakePage.tsx`. Android only references stocktake in a dashboard widget placeholder. Full Android parity: sessions list, per-session count UI, barcode-scan loop, variance resolution, adjust on commit. Follows same cursor-based pagination contract the other list surfaces use.

### Wave-48 scan-loop findings (2026-04-23) — web/api + web/stores

### Wave-49 scan-loop findings (2026-04-23) — web/components

### Wave-50 scan-loop findings (2026-04-23) — web/pages

### Wave-52 scan-loop findings (2026-04-23) — web/layout + web/auth

### Wave-51 scan-loop findings (2026-04-23) — web/pages dashboard+reports+settings+customers

### Wave-53 scan-loop findings (2026-04-23) — web/pages inventory+estimates + shared

### Wave-57 scan-loop findings (2026-04-24) — web/components/shared + web/api + web/utils

### Wave-54 scan-loop findings (2026-04-23) — web/pages catalog+employees+billing+marketing+gift-cards+expenses+loaners

### Wave-55 scan-loop findings (2026-04-23) — web/pages communications+reviews+expenses + shared API types
### Wave-60 scan-loop findings (2026-04-24) — server/ws + utils + db


### Wave-56 scan-loop findings (2026-04-24) — web/pages pos+print+setup+photo-capture+loaners+landing
### Wave-58 scan-loop findings (2026-04-24) — server routes + middleware

### Wave-59 scan-loop findings (2026-04-24) — server services + shared + automations

### Wave-70 scan-loop findings (2026-04-24) — confirmStore/migrations/stripe/sla/giftCard/dunning/index

### Wave-69 scan-loop findings (2026-04-24) — client CSV/dashboard tz/pin/signature/portal

### Wave-68 scan-loop findings (2026-04-24) — idempotency/auth/audit/notifications/metrics

### Wave-67 scan-loop findings (2026-04-24) — auth/layout/migrations/public-api

### Wave-66 scan-loop findings (2026-04-24) — reports/locations/retention/autoreorder/webhooks/notifications/sla/dunning/tenantExport/worker-pool

### Wave-65 scan-loop findings (2026-04-24) — tv + pos + recurring + ws + gift/deposits/bench/search

### Wave-64 scan-loop findings (2026-04-24) — team-chat + automations + roles + web components

### Wave-63 scan-loop findings (2026-04-24) — routes + services + authStore

### Wave-62 scan-loop findings (2026-04-24) — hooks + middleware + routes

### Wave-61 scan-loop findings (2026-04-23) — server middleware + migrations + routes + web stores

### Wave-Loop Finder-A run 2026-04-24 — web/pages auth+signup+landing+dashboard+settings+team+super-admin+setup+billing+subscriptions+employees
- [ ] WEB-FA-001. **[HIGH] LoginPage: Unhandled error in session restore:** setupStatus() throws but catch block silently drops error — could leave user in inconsistent auth state.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/LoginPage.tsx:109-112; fix=add-error-logging-and-retry -->
- [x] WEB-FA-003. **[HIGH] SignupPage: Unsafe error type casting:** `(err as any)?.response?.data?.message` — no type narrowing. Define ApiError interface. FIXED 2026-04-24 by Fixer-C — replaced `(err as any)` with typed `{ response?: { data?: { message?: string; error?: string } } }` shape + Error fallback.
  <!-- meta: scope=web/pages/signup; files=packages/web/src/pages/signup/SignupPage.tsx:215-216; fix=define-typed-error-handler -->
- [x] WEB-FA-004. **[MED] LoginPage: Null-unsafe refreshToken assertion:** `completeLogin(data.accessToken, data.refreshToken!, data.user!)` — could undefined on partial 2FA response. FIXED 2026-04-24 by Fixer-C — replaced non-null assertions with explicit null-check that surfaces a "Login response was incomplete" server error before completeLogin.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/LoginPage.tsx:184-186; fix=add-null-check-before-assertion -->
- [x] WEB-FA-005. **[MED] ResetPasswordPage: Information leak in error message:** "The link may have expired" reveals token validity. Generic error preferred. FIXED 2026-04-24 by Fixer-C — generic "Failed to reset password. Please request a new reset link." default; only surface server message on explicit 400 validation error.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/ResetPasswordPage.tsx:73; fix=use-generic-error-message -->
- [ ] WEB-FA-007. **[MED] TeamChatPage: Unsafe error typing:** `e: any` in onError handlers — no type narrowing for API response.
  <!-- meta: scope=web/pages/team; files=packages/web/src/pages/team/TeamChatPage.tsx:91,110; fix=define-tanstack-error-type -->
- [ ] WEB-FA-008. **[MED] DunningPage: Unvalidated JSON parse in mutation:** `JSON.parse(stepsText)` throws but no try/catch — bad input crashes mutation.
  <!-- meta: scope=web/pages/billing; files=packages/web/src/pages/billing/DunningPage.tsx:66-72; fix=wrap-json-parse-with-error-handling -->
- [ ] WEB-FA-009. **[MED] LoginPage: Field errors not cleared on edit:** fieldErrors state persists after user clears input — confusing UX.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/LoginPage.tsx:466-481; fix=clear-field-errors-on-change -->
- [ ] WEB-FA-010. **[MED] SignupPage: hCaptcha script injected without CSP nonce:** Dynamic script append bypasses CSP if nonce required.
  <!-- meta: scope=web/pages/signup; files=packages/web/src/pages/signup/SignupPage.tsx:169-174; fix=add-csp-nonce-or-defer -->
- [ ] WEB-FA-012. **[MED] LandingPage: Direct DOM mutation in event handlers:** `onMouseEnter/Leave` mutate `.style.color` — anti-pattern, triggers reflow, not memoized.
  <!-- meta: scope=web/pages/landing; files=packages/web/src/pages/landing/LandingPage.tsx:477-480; fix=use-css-pseudo-classes-or-classname-toggle -->
- [ ] WEB-FA-013. **[MED] DashboardPage: Hard-coded supplier domains:** mobilesentrix.com, phonelcdparts.com — not configurable from Settings.
  <!-- meta: scope=web/pages/dashboard; files=packages/web/src/pages/dashboard/DashboardPage.tsx:174-177; fix=move-to-catalog-provider-config -->
- [ ] WEB-FA-014. **[MED] LoginPage: Session restore not cached:** authApi.me() called on every page load, no staleTime. Multi-tab = N requests.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/LoginPage.tsx:145-157; fix=add-staleTime-to-query -->
- [ ] WEB-FA-015. **[MED] SubscriptionsListPage: Missing loading skeleton:** TableSkeleton defined but never used while first query loads.
  <!-- meta: scope=web/pages/billing; files=packages/web/src/pages/billing/SubscriptionsListPage.tsx:63-70; fix=conditionally-render-skeleton -->
- [ ] WEB-FA-016. **[MED] SignupPage: Slug check not cancelled:** Debounced checkSlug() no abort — fast typing creates race conditions.
  <!-- meta: scope=web/pages/signup; files=packages/web/src/pages/signup/SignupPage.tsx:81-114; fix=add-abort-controller-to-requests -->
- [ ] WEB-FA-017. **[LOW] SettingsPage: UnsavedChangesGuard partially wired:** Provider imported but Settings tabs may not all consume useUnsavedChanges hook.
  <!-- meta: scope=web/pages/settings; files=packages/web/src/pages/settings/SettingsPage.tsx:46-48; fix=audit-all-tab-components-for-hook -->
- [ ] WEB-FA-018. **[LOW] DunningPage: Hard-coded template IDs:** Default stepsText includes `template_id: "overdue_1"` — no enum validation.
  <!-- meta: scope=web/pages/billing; files=packages/web/src/pages/billing/DunningPage.tsx:52-54; fix=fetch-templates-list-server-side -->
- [ ] WEB-FA-019. **[LOW] ResetPasswordPage: Unsafe button type:** "Back to login" button without `type="button"` in form — defaults to submit.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/ResetPasswordPage.tsx:156-159; fix=add-type-button-attribute -->
- [ ] WEB-FA-020. **[LOW] TeamChatPage: Mention regex allows invalid patterns:** UI accepts patterns server rejects.
  <!-- meta: scope=web/pages/team; files=packages/web/src/pages/team/TeamChatPage.tsx:117; fix=sync-regex-with-server-username-rules -->
- [x] WEB-FA-021. **[LOW] DashboardPage: Untyped parameter:** `queueSummary: any` — no schema, makes contract opaque. FIXED 2026-04-24 by Fixer-C — added `OrderQueueSummary` + `OrderQueueItem` interfaces, swapped `any` props + `any[]` queueItems decl, removed redundant `as number` cast on estimated_cost render.
  <!-- meta: scope=web/pages/dashboard; files=packages/web/src/pages/dashboard/DashboardPage.tsx:202; fix=define-type-for-queueSummary -->
- [ ] WEB-FA-022. **[LOW] TenantsListPage: Super-admin token not refreshed:** localStorage token persists without refresh flow.
  <!-- meta: scope=web/pages/super-admin; files=packages/web/src/pages/super-admin/TenantsListPage.tsx:67; fix=implement-token-refresh-interceptor -->
- [ ] WEB-FA-023. **[LOW] LoginPage: Auto-redirect ignores onboarding state:** Redirects to '/' but no check if user completed onboarding wizard.
  <!-- meta: scope=web/pages/auth; files=packages/web/src/pages/auth/LoginPage.tsx:119; fix=check-wizard_completed-before-redirect -->
- [ ] WEB-FA-024. **[LOW] SignupPage: Brand font duplicated import:** Google Fonts import in style tag — should be in global CSS to dedupe across pages.
  <!-- meta: scope=web/pages/signup; files=packages/web/src/pages/signup/SignupPage.tsx:249-251; fix=move-to-shared-global-css -->

### Finder-C web polish findings (2026-04-24) — pages/{tickets,loaners,leads,automations,marketing,communications,reports,reviews,photo-capture,portal,print,tracking,tv,voice,expenses}
- [ ] WEB-FC-001. **[HIGH] TicketPayments / TicketDevices edit price uses browser `prompt()`.** Inline-edit of labor + part prices calls `window.prompt()` — jarring, non-stylable, blocks the event loop, can't be validated (rejects empty/NaN silently), and is often disabled on mobile browsers — staff cannot edit prices on iOS Safari.
  <!-- meta: scope=web/pages/tickets; files=packages/web/src/pages/tickets/TicketPayments.tsx:85,105 packages/web/src/pages/tickets/TicketDevices.tsx:702,809; fix=replace-prompt-with-inline-numeric-input-or-small-modal-dialog -->
- [x] WEB-FC-002. **[HIGH] Marketing campaign "Run now" and "Delete" fire immediately with no confirm.** One click on `Run now` dispatches the full segment (SMS + email) to potentially thousands of recipients with no confirmation, recipient-count preview requirement, or undo. `Delete` also immediately destroys the campaign row without ConfirmDialog.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/CampaignsPage.tsx:229,261; fix=wrap-both-in-ConfirmDialog-with-recipient-count-shown-for-runNow -->
  FIXED 2026-04-24 by Fixer-D — Run-now opens a danger ConfirmDialog that fetches recipient count via campaignsApi.preview() and shows it in the message. Delete opens a danger ConfirmDialog with the campaign name. Both block dispatch/destruction until explicit confirmation.
- [ ] WEB-FC-003. **[HIGH] Customer-facing tracking portal has no dark-mode styles.** `TrackingPage.tsx` uses only `text-slate-*`, `bg-white`, `border-slate-*` etc. with zero `dark:` variants. On a customer phone set to dark mode the entire portal is bright-white and the status badge text becomes unreadable on some color values.
  <!-- meta: scope=web/pages/tracking; files=packages/web/src/pages/tracking/TrackingPage.tsx:288-770; fix=add-dark-variants-or-force-light-scheme-with-color-scheme-CSS -->
- [ ] WEB-FC-004. **[HIGH] Portal uses `text-gray-*` exclusively — no dark mode and diverges from surface-* tokens.** Every portal top-level screen (`PortalLogin`, `PortalRegister`, `PortalDashboard`, `PortalEstimatesView`, `PortalInvoicesView`, `PortalTicketDetail`, `CustomerPortalPage`) ships `bg-gray-*` / `text-gray-*` instead of the `surface-*` + `dark:` ramp used elsewhere — customer sees an inconsistent brand and no dark-mode support.
  <!-- meta: scope=web/pages/portal; files=packages/web/src/pages/portal/PortalLogin.tsx packages/web/src/pages/portal/PortalDashboard.tsx packages/web/src/pages/portal/PortalEstimatesView.tsx packages/web/src/pages/portal/PortalInvoicesView.tsx packages/web/src/pages/portal/PortalTicketDetail.tsx packages/web/src/pages/portal/PortalRegister.tsx; fix=swap-gray-*-for-surface-*-tokens-with-dark-variants -->
- [ ] WEB-FC-005. **[HIGH] Modals in this scope lack `role="dialog"` + `aria-modal="true"` + focus trap.** `LoanersPage.ReturnDialog`, `ReviewsPage.ReplyModal`, `CampaignsPage.CreateCampaignModal`/`PreviewModal`, `SegmentsPage.CreateSegmentModal`/`MembersModal`, `CalendarPage` new-appointment, and `ExpensesPage` inline form all render as plain `<div>` overlays. Keyboard users can Tab past the modal into the obscured page, and Esc does nothing. Only `portal/components/ReviewPromptModal.tsx` sets the pair.
  <!-- meta: scope=web/pages; files=packages/web/src/pages/loaners/LoanersPage.tsx:39 packages/web/src/pages/reviews/ReviewsPage.tsx:72 packages/web/src/pages/marketing/CampaignsPage.tsx:335 packages/web/src/pages/marketing/SegmentsPage.tsx:235,330 packages/web/src/pages/leads/CalendarPage.tsx:203; fix=shared-Modal-primitive-with-role-dialog+aria-modal+focus-trap+Esc-close -->
- [x] WEB-FC-006. **[HIGH] Lead pipeline: only way to move a card is a button hidden by `opacity-0 group-hover:opacity-100` — unreachable on touch + keyboard.** `LeadPipelinePage.tsx` LeadCard's "move" affordance is invisible until mouse hover, so touch devices (tablet kiosk, phone) and keyboard-only users cannot progress leads through the pipeline. Also the `fixed inset-0 z-10` backdrop is not a real dismissible popover (no Esc, no focus trap).
  <!-- meta: scope=web/pages/leads; files=packages/web/src/pages/leads/LeadPipelinePage.tsx:101; fix=always-visible-move-button-or-focus-within-reveal-plus-keyboard-nav -->
  FIXED 2026-04-24 by Fixer-D — Removed opacity-0 hover trap on the move button; it is now always visible and tappable on touch. Added aria-haspopup/aria-expanded/aria-label, role="menu" on the popover, Esc-to-dismiss with focus return to the trigger, and auto-focus of the first menu option when opened.
- [ ] WEB-FC-007. **[MED] Segment delete button has no confirm dialog — destructive single-click.** `SegmentsPage.tsx:171` `remove.mutate(s.id)` deletes the segment immediately; a mis-click destroys a hand-built customer segment that may be referenced by running campaigns.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/SegmentsPage.tsx:171; fix=add-ConfirmDialog-and-check-for-campaigns-referencing-segment -->
- [ ] WEB-FC-008. **[MED] Loaners page has no "Add loaner device" CTA — page is viewer-only.** `LoanersPage.tsx` renders devices + a return dialog, but offers zero way to register a new loaner, edit one, or assign one to a customer. Page is only useful if loaners are seeded elsewhere (no such UI exists in scope); staff must hit the API directly.
  <!-- meta: scope=web/pages/loaners; files=packages/web/src/pages/loaners/LoanersPage.tsx; fix=add-Create+Edit+Assign-UI-and-status-filters -->
- [x] WEB-FC-009. **[MED] TV display publicly shows customer first names — PII leak on a screen in the shop lobby.** `TvDisplayPage.tsx:159` renders `ticket.customer_first_name || 'Walk-in'` alongside device + repair status and a short `T-1042` order ID. Any passerby can correlate a customer with their device and pickup time.
  <!-- meta: scope=web/pages/tv; files=packages/web/src/pages/tv/TvDisplayPage.tsx:159; fix=show-initials-like-J.-or-gate-behind-store_config.tv_show_names-toggle-default-off -->
  FIXED 2026-04-24 by Fixer-D — TV ticket card now renders only the first-name initial followed by a period (e.g. "J.") instead of the full first name; "Walk-in" fallback preserved.
- [ ] WEB-FC-010. **[MED] `NpsTrendPage` monthly chart ignores sign — negative NPS looks identical to positive NPS.** Bar height is `Math.max(4, Math.abs(m.nps))` at NpsTrendPage.tsx:96, so nps=-60 renders the same tall bar as nps=+60. Owners viewing a crisis month see a reassuring chart.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/NpsTrendPage.tsx:94-105; fix=center-axis-at-0+position-bars-above-or-below-baseline-by-sign+red-below-zero -->
- [ ] WEB-FC-011. **[MED] `NpsTrendPage` + `ReferralsDashboard` swallow all query errors into empty-state.** Both `queryFn` wrap the call in `try/catch` and return a fabricated "zeros / unavailable" payload on ANY failure — 401 (session expired), 500 (server bug), and CORS errors all render identically to "no data yet". Owners cannot distinguish "I have no reviews" from "the server is broken".
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/NpsTrendPage.tsx:42-52 packages/web/src/pages/marketing/ReferralsDashboard.tsx:86-94; fix=let-react-query-surface-the-error-or-distinguish-status-codes-before-rendering-empty -->
- [ ] WEB-FC-012. **[MED] `ReferralsDashboard` computes stats from only the first page of rows.** Server returns rows with no pagination metadata, and the page computes `total`, `converted`, `conversion_rate`, and the leaderboard from that array — totals understate reality as soon as there are >N referrals. No "showing X of Y" footer.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/ReferralsDashboard.tsx:52-75,98; fix=add-/reports/referrals/stats-endpoint-or-iterate-pagination-before-computing -->
- [ ] WEB-FC-013. **[MED] Portal `PhotoGallery` uses `window.confirm()` and silently swallows delete errors.** `PhotoGallery.tsx:41` shows browser-native confirm (unstylable, Safari-on-iOS can block), and the hide mutation catch is `/* swallow */` — if the server rejects the delete the photo reappears on next load but the customer thinks it was deleted.
  <!-- meta: scope=web/pages/portal; files=packages/web/src/pages/portal/components/PhotoGallery.tsx:41,47; fix=replace-confirm-with-shared-ConfirmDialog+toast-on-error+refetch-immediately -->
- [ ] WEB-FC-014. **[MED] `TaxReportPage` and `PartnerReportPage` open server-rendered HTML via `window.open(..., '_blank', 'noopener')` with no loading/auth-fail fallback.** Date range has no validation — `from > to` still opens a blank report. A logged-out session opens the server's 401 HTML in a new tab, which looks like the feature is broken rather than "please log in".
  <!-- meta: scope=web/pages/reports; files=packages/web/src/pages/reports/TaxReportPage.tsx:20-28 packages/web/src/pages/reports/PartnerReportPage.tsx:15-18; fix=validate-from<=to+HEAD-preflight-or-fetch+blob+open-with-revocation-or-inline-iframe-preview -->
- [ ] WEB-FC-015. **[MED] Voice recording playback opens an auth-bearing URL via `window.open` — fails if session token is an axios header interceptor rather than a cookie.** `VoiceCallsListPage.tsx:48` opens recordings in a new tab relying on credentials being present on the new-tab request; if only the axios interceptor carries the bearer, the new tab gets 401. Also no filters (date, direction, caller), so the list is linear-only.
  <!-- meta: scope=web/pages/voice; files=packages/web/src/pages/voice/VoiceCallsListPage.tsx:47-49,115-124; fix=fetch-recording-as-blob-via-api-client-then-URL.createObjectURL+add-filters -->
- [ ] WEB-FC-016. **[MED] `PhotoCapturePage` passes a bearer token via `?t=<token>` query string — exposes token in browser history, referrer headers, and server access logs.** `PhotoCapturePage.tsx:10,72` reads `t` from search params and uses it as `Authorization: Bearer ${token}`; the token lingers in history even after upload. Shoulder-surf + shared-device risk for the photo-upload token.
  <!-- meta: scope=web/pages/photo-capture; files=packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:10,72; fix=single-use-short-TTL-token+scrub-from-URL-on-mount-via-history.replaceState -->
- [ ] WEB-FC-017. **[MED] Aggressive `any` leaks across ticket + communications + calendar + campaigns surfaces.** 40+ `: any` annotations in `TicketDetailPage`, `TicketListPage`, `TicketWizard`, `TicketDevices`, `CommunicationPage`, `CalendarPage`, `CampaignsPage`, etc. — e.g. `const smsMessages: any[]`, `const grades: any[] = pricingData?.grades || []`, `mutationFn: (data: any) => ticketApi.create(data)`. Invalidates compile-time guards on mutation payloads and list renders.
  <!-- meta: scope=web/pages; files=packages/web/src/pages/tickets/TicketDetailPage.tsx:91,140,222,242,379 packages/web/src/pages/tickets/TicketWizard.tsx:180,324,408,420,435,910,1901 packages/web/src/pages/communications/CommunicationPage.tsx:680,767,793,1107,2141 packages/web/src/pages/leads/CalendarPage.tsx:191 packages/web/src/pages/marketing/CampaignsPage.tsx:106,139,314,329; fix=share-types-via-@bizarre-crm/shared-and-tighten-mutation-payload-types -->
- [ ] WEB-FC-018. **[MED] `ExpensesPage` renders edit form inline above the table instead of as a modal — loses scroll position on edit.** `ExpensesPage.tsx:156-184` the "Add/Edit Expense" form appears between filters and the table, pushing data below the fold. Editing an expense on page 3 scrolls the user up to the form and loses row context; on mobile the form takes the full viewport with no dim overlay.
  <!-- meta: scope=web/pages/expenses; files=packages/web/src/pages/expenses/ExpensesPage.tsx:156-184; fix=promote-to-modal-with-role-dialog+aria-modal-or-drawer-on-mobile -->
- [ ] WEB-FC-019. **[MED] `CampaignsPage` + `SegmentsPage` read `err?.response?.data?.error` where server actually returns `message`.** Toasts "Failed to create campaign" when the server sent a descriptive 400 payload under `.message`. Campaigns then look mysteriously broken to the owner.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/CampaignsPage.tsx:329-330 packages/web/src/pages/marketing/SegmentsPage.tsx:229-231; fix=standardize-on-err.response.data.message-fallback-to-err.message -->
- [ ] WEB-FC-020. **[LOW] `TvDisplayPage` has no error state — a dead API keeps the skeleton pulsing forever.** `TvDisplayPage.tsx:58-70` ignores `isError`/`error`; a wall-mounted TV sits on loading skeletons indefinitely during a server outage.
  <!-- meta: scope=web/pages/tv; files=packages/web/src/pages/tv/TvDisplayPage.tsx:58-135; fix=render-error-state-with-timestamp+auto-retry-countdown -->
- [ ] WEB-FC-021. **[LOW] `CalendarPage` new-appointment form uses 24-hour hour selects (00-23) with no AM/PM — mismatches US shop convention.** `CalendarPage.tsx:256,274` drops raw "14" into the select; US operators expect 2 PM. `formatTime` on line 57 already uses en-US 12-hour elsewhere.
  <!-- meta: scope=web/pages/leads; files=packages/web/src/pages/leads/CalendarPage.tsx:256,274; fix=display-12h-label-with-am/pm-indicator-keep-24h-value-internally -->
- [ ] WEB-FC-022. **[LOW] `downloadCsv` helper revokes object URL synchronously after `.click()` — race on Firefox/Safari can cancel the download.** `ReportsPage.tsx:115-131` calls `URL.revokeObjectURL(url)` immediately; some browsers have not yet started the download when revoke fires.
  <!-- meta: scope=web/pages/reports; files=packages/web/src/pages/reports/ReportsPage.tsx:115-131; fix=defer-revoke-via-setTimeout(...,0)-or-remove-anchor-on-next-tick -->
- [ ] WEB-FC-023. **[LOW] `AutomationsListPage` is a 28-line pass-through wrapper around `AutomationsTab` — two URLs for one feature hurts navigation memory.** `AutomationsListPage.tsx:4-8` explicitly flags the duplication; also reachable via `/settings/automations`. Pick one canonical route and redirect the other.
  <!-- meta: scope=web/pages/automations; files=packages/web/src/pages/automations/AutomationsListPage.tsx:1-28; fix=pick-one-canonical-route-and-redirect-the-other -->
- [ ] WEB-FC-024. **[LOW] `PortalLogin` + `TrackingPage` rate-limit messages don't read server `Retry-After` header.** `PortalLogin.tsx:42,68` and `TrackingPage.tsx:179-181` say "wait a minute… try again later" with no countdown. Customer retries immediately, gets rejected again, gives up.
  <!-- meta: scope=web/pages/portal,tracking; files=packages/web/src/pages/portal/PortalLogin.tsx:42,68 packages/web/src/pages/tracking/TrackingPage.tsx:179-181; fix=read-Retry-After-from-429-response+countdown-timer-before-next-attempt -->
- [ ] WEB-FC-025. **[LOW] TrackingPage `InvoiceStatusBadge` uses slate/green/amber/red with no `dark:` variants — near-invisible on dark-mode UA.** `TrackingPage.tsx:758-770` `colors` map is light-only (`bg-slate-100 text-slate-600` etc.); customer on a dark-themed phone opening `/track` sees nearly-illegible status chips against the already-unstyled dark viewport.
  <!-- meta: scope=web/pages/tracking; files=packages/web/src/pages/tracking/TrackingPage.tsx:756-770; fix=add-dark:bg-*-text-*-variants-or-force-color-scheme-light -->

### Finder-B web polish findings 2026-04-24 — web/pages pos+unified-pos+catalog+inventory+customers+invoices+estimates+gift-cards

- [ ] WEB-FB-001. **[HIGH] Gift-card list `formatCurrency` mislabels param as `cents` but treats it as dollars.** `GiftCardsListPage.tsx` `formatCurrency(cents)` is `` `$${cents.toFixed(2)}` `` — no `/100`. Detail page uses the same signature but clearly treats the input as dollars. If server migrates to storing cents (the rest of POS already does), every balance shown is 100x wrong and silently breaks.
  <!-- meta: scope=web/gift-cards; files=packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:46-48,262,347; fix=rename-param-to-dollars-and-consume-utils/format-formatCurrency -->

- [ ] WEB-FB-002. **[HIGH] CheckoutModal tax calc rounds each line then re-rounds total — float drift on multi-item sales.** `useCheckoutTotals` accumulates float-dollar `subtotal`/`taxableAmount`, then does `Math.round(taxableAmount * rate * 100) / 100` and `Math.round((subtotal + tax - discountAmount) * 100) / 100`. `BottomActions.cartTotalCents` correctly runs cents-pure — so the customer-facing total in CheckoutModal can diverge from the cents-accurate server total by ±1¢ on 3+ item carts.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/CheckoutModal.tsx:33-74; fix=accumulate-in-cents-like-BottomActions.cartTotalCents-and-/100-only-for-display -->

- [ ] WEB-FB-003. **[HIGH] RepairsTab is a 30-site `any`-soup — type-safety black hole.** Every models/services/grades/tickets/customers/checks payload is `any[]` or `as any`. A server rename (`is_default` → `default`) never fails at build, goes silent at runtime. Same pattern in UnifiedPosPage hydrate, LeftPanel iconMap, etc.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/RepairsTab.tsx:76,184,196,251,281,349,359,374,380,387,395,431,444,492,639,648,917,932,957,983,984,1007,1015,1031,1038,1064,1067,1100,1220; fix=add-shared-DeviceModel/RepairService/Grade/Ticket/Customer-types -->

- [x] WEB-FB-004. **[HIGH] CatalogPage CSV parser uses naive `split(',')` — any quoted field with a comma corrupts the row.** Supplier CSVs routinely have `"OLED Assembly, Black, Grade A"`. The result: SKU becomes `OLED Assembly`, name becomes `Black`, price `NaN`. Also only splits on `\n`, breaks on CRLF.
  <!-- meta: scope=web/catalog; files=packages/web/src/pages/catalog/CatalogPage.tsx:188-205; fix=use-papaparse-or-a-proper-tokenizer-with-quote-and-CRLF-support -->
  FIXED 2026-04-24 by Fixer-D — Replaced naive split-based parsing with an inline RFC-4180-style tokenizer (parseCsvRows) that correctly handles quoted fields containing commas, escaped quotes ("" inside quoted strings), CR/LF/CRLF row terminators, and embedded newlines inside quoted values. No new dependency added.

- [ ] WEB-FB-005. **[HIGH] InventoryListPage "Order All on Supplier Sites" loop fires up to 20 `window.open` in one click — browsers block all but the first.** Popup-blockers enforce a 1-per-gesture quota. Toast claims "Opened 20 supplier pages" but only 1 tab opens in Chrome/Safari/Firefox.
  <!-- meta: scope=web/inventory; files=packages/web/src/pages/inventory/InventoryListPage.tsx:591-616; fix=open-first-tab-inline-then-queue-rest-behind-sequential-user-clicks-or-render-staging-page-with-manual-links -->

- [ ] WEB-FB-006. **[MED] InvoiceDetailPage print windows bypass axios auth.** `window.open('/print/ticket/<id>?...', '_blank')` can't attach `Authorization: Bearer`. If the print route is behind normal auth (localStorage token), tab 401s with no UX. Mirror the `FA-M26` wallet-pass blob-URL pattern instead.
  <!-- meta: scope=web/invoices; files=packages/web/src/pages/invoices/InvoiceDetailPage.tsx:305,625; fix=fetch-HTML-with-axios-then-open-blob-URL -->

- [ ] WEB-FB-007. **[MED] Native `window.confirm` vs async `confirm(...)` from `@/stores/confirmStore` used inconsistently across inventory/invoices.** StocktakePage, BinLocationsPage, AutoReorderPage, InvoiceListPage drop into blocking native dialog (ignores dark mode + brand fonts). Estimates/pos/customers/tickets all use the themed `await confirm(...)`.
  <!-- meta: scope=web/inventory+invoices; files=packages/web/src/pages/inventory/AutoReorderPage.tsx:148,290,packages/web/src/pages/inventory/BinLocationsPage.tsx:206,packages/web/src/pages/inventory/StocktakePage.tsx:332,343,packages/web/src/pages/invoices/InvoiceListPage.tsx:171; fix=swap-native-confirm-for-await-confirm -->

- [ ] WEB-FB-008. **[MED] EstimateList create-modal asks for per-line `tax_amount` as a flat dollar — no rate, no taxability flag.** Creates estimates that can't round-trip through CheckoutModal's tax engine (which applies `useDefaultTaxRate * taxableAmount`). Converting estimate → ticket drops or double-counts tax.
  <!-- meta: scope=web/estimates; files=packages/web/src/pages/estimates/EstimateListPage.tsx:70-71,109,128-130; fix=replace-tax_amount-with-per-line-taxable:boolean-apply-store-rate-on-submit -->

- [ ] WEB-FB-009. **[MED] CheckoutModal split-payment "covers total" check compares floats.** `splitTotal < totals.total` — both floats. Combined with WEB-FB-002 drift, a cashier can hit a phantom under-by-a-cent error or, worse, pass a sale a cent short. Compare ints in cents.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/CheckoutModal.tsx:181-186,321; fix=compare-splitTotalCents<totalCents-both-ints -->

- [ ] WEB-FB-010. **[MED] SuccessScreen SMS receipt hardcodes `$` symbol + en-US format.** `Receipt for Invoice #...: Total $${total.toFixed(2)}. Paid: $${total.toFixed(2)}.` Tenants in EUR/GBP/CAD send wrong symbol to customers.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/SuccessScreen.tsx:101; fix=use-utils/format-formatCurrency -->

- [ ] WEB-FB-011. **[MED] CustomerDetailPage wallet-pass blob open breaks on Safari iPad.** `window.open(blobUrl, '_blank')` — Safari rewrites to `about:blank` on iPad (documented POS platform), pass never renders. .pkpass content-type should trigger an `<a download>` anchor fallback.
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerDetailPage.tsx:198-220; fix=if-pkpass-mime-use-anchor-download-else-blob-open -->

- [ ] WEB-FB-012. **[MED] CustomerDetailPage tickets/invoices/communications renderers all `any`-typed.** `sorted: any[]`, `communications: any[]`, `(msg: any, i: number)`, `(inv: any)`, `(ticket: any)`, `updateField(key: string, value: any)`. Server field rename goes silent.
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerDetailPage.tsx:855,1110,1464,1479,1596,1640,1654; fix=consume-shared-Customer/Ticket/Invoice/Communication-types -->

- [ ] WEB-FB-013. **[MED] Manager-PIN form allows unlimited retries with no visible lockout UX.** 4-digit PIN (10k combos, trivially brute-forceable from an in-store tablet) with generic "Invalid manager PIN" error, no disabled cooldown, no audit-log surface. `/pos-enrich/manager-verify-pin` may rate-limit server-side but the UI never shows it.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/BottomActions.tsx:488-570; fix=surface-server-lockout+exponential-backoff+6-8-digit-PIN-minimum -->

- [ ] WEB-FB-014. **[MED] InventoryListPage bulk filters type items as `any`.** `items.filter((i: any) => i.supplier_url && i.supplier_source === 'phonelcdparts')` etc. — any backend field rename silently yields empty filters.
  <!-- meta: scope=web/inventory; files=packages/web/src/pages/inventory/InventoryListPage.tsx:593-594; fix=introduce-InventoryItem-type -->

- [ ] WEB-FB-015. **[LOW] ShrinkagePage `safeHref` accepts protocol-relative URLs.** `raw.startsWith('/')` matches `//attacker.example.com/foo` which browsers treat as absolute cross-origin. Rare (server-stored data) but trivially fixed by rejecting `startsWith('//')` first.
  <!-- meta: scope=web/inventory; files=packages/web/src/pages/inventory/ShrinkagePage.tsx:18-26; fix=reject-startsWith('//')-before-returning -->

- [ ] WEB-FB-016. **[LOW] LeftPanel `iconMap: Record<string, any>` silences missing-icon cases.** Unknown `type` renders nothing instead of failing at build.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/LeftPanel.tsx:152; fix=type-as-Record<SuggestionType,LucideIcon>-exhaustive-keys -->

- [ ] WEB-FB-017. **[LOW] RepairsTab CustomerStep search error shows toast but UI still renders "no results".** `catch { setResults([]); console.warn(...); toast.error(...) }` — the empty list state lies as "no matches". Cashier may miss the toast while focused on the form.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/RepairsTab.tsx:1003-1010; fix=track-searchState='error'-render-retry-button-in-results-area -->

- [ ] WEB-FB-018. **[LOW] EstimateDetailPage versions typed `any[]` — diff-field drift goes silent.** `const versions: any[] = versionsData?.data?.data || [];` — ENR-LE6 versioning needs a shared `EstimateVersion` shape.
  <!-- meta: scope=web/estimates; files=packages/web/src/pages/estimates/EstimateDetailPage.tsx:49,86; fix=add-EstimateVersion-to-shared-package -->

- [ ] WEB-FB-019. **[LOW] GiftCardDetailPage strips sign from redemption amounts — only color distinguishes from purchases.** `formatCurrency(Math.abs(amount))` for a redemption of $25 renders "$25.00" in red — same visual as any other transaction. Explicit `-$25.00` prefix matches POS convention and helps colorblind users.
  <!-- meta: scope=web/gift-cards; files=packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:36-38,44-49; fix=prefix-"-"-for-redemption-or-drop-Math.abs -->

- [ ] WEB-FB-020. **[LOW] BinLocationsPage heatmap colors have no dark-mode variants — invisible on dark theme.** `bg-yellow-200`, `bg-surface-100`, `bg-surface-50` have no `dark:` partners — breaks brand-surface-ramp alignment (§project_brand_surface_ramp).
  <!-- meta: scope=web/inventory; files=packages/web/src/pages/inventory/BinLocationsPage.tsx:111-118; fix=add-dark:bg-yellow-900/30+dark:text-yellow-200-etc -->

- [ ] WEB-FB-021. **[LOW] StocktakePage / BinLocationsPage / AutoReorderPage `bg-white`+`border-surface-200` cards have no `dark:` partner — pure white in dark theme.** Same brand-surface-ramp gap.
  <!-- meta: scope=web/inventory; files=packages/web/src/pages/inventory/StocktakePage.tsx:279,302,355,packages/web/src/pages/inventory/BinLocationsPage.tsx:145,199,packages/web/src/pages/inventory/AutoReorderPage.tsx:180; fix=batch-add-dark:bg-surface-900+dark:border-surface-700 -->

- [ ] WEB-FB-022. **[LOW] RepairsTab `ticketApi.list({ status_id: 'active' as any })` — enum cast hides server contract.** Works today because backend coerces, breaks silently if coercion tightens.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/RepairsTab.tsx:1064; fix=add-status-filter-enum-to-ticketApi-types-or-filter-client-side -->

- [ ] WEB-FB-023. **[LOW] InvoiceListPage bulk action has no partial-success reporting.** User selects 5 unpaid invoices; a colleague voids one mid-click; server fails on the void, bulk mutation reports generic "Bulk action failed". Surface per-invoice results.
  <!-- meta: scope=web/invoices; files=packages/web/src/pages/invoices/InvoiceListPage.tsx:153-174; fix=server+client-return-per-row-success/failure-map -->

- [ ] WEB-FB-024. **[LOW] Repair labor price input silently coerces non-numeric to 0.** `parseFloat(manualPrice) || 0`. Cashier typos `12o.50` (letter o), labor charged $0 with no visual feedback.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/RepairsTab.tsx:415; fix=validate-on-blur+red-border-on-NaN-block-submit -->

- [ ] WEB-FB-025. **[LOW] UnifiedPos hydration from `?ticket=` hardcodes `taxable:false` on labor + `taxable:true` on parts with no cashier indicator.** Jurisdictions that tax labor need a visible toggle indicator per repair line.
  <!-- meta: scope=web/unified-pos; files=packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:255,283; fix=honor-tax-class-from-ticket-record+badge-on-labor-line -->

### Wave-Loop Finder-F run 2026-04-24 — deeper page audit (forms/mutations/perf/i18n/cents)

- [ ] WEB-FF-001. **[HIGH] DeviceTemplatesPage cents math floors fractional cents — saved labor cost / suggested price loses ¢ on float-input.** `Math.round(form.est_labor_cost_dollars * 100)` and `Math.round(form.suggested_price_dollars * 100)` — entering `19.99` gets `Math.round(1998.9999999998) = 1999` today but `0.1 + 0.2`-style inputs (e.g. computed defaults) silently drop ¢. Should round via cents-pure helper (parse string → bigint cents) like the rest of POS.
  <!-- meta: scope=web/settings; files=packages/web/src/pages/settings/DeviceTemplatesPage.tsx:106-107; fix=use-cents-pure-helper-from-utils/money.ts -->

- [ ] WEB-FF-002. **[HIGH] PortalEstimatesView optimistic approval has no rollback — customer sees "approved" forever even when server rejects.** `handleApprove` does `setEstimates(prev => prev.map(...))` synchronously after `await api.approveEstimate(id)`. The `catch` block only sets `error` text; the optimistic UI state is never reverted. Customer reads "Approved 2026-04-24" while shop side sees no approval — payment dispute risk.
  <!-- meta: scope=web/portal; files=packages/web/src/pages/portal/PortalEstimatesView.tsx:21-33; fix=apply-optimistic-update-before-await+revert-in-catch -->

- [ ] WEB-FF-003. **[HIGH] Web pages use zero `Intl.NumberFormat` / `Intl.DateTimeFormat` — every currency, percent, date is hand-formatted with hardcoded en-US locale + `$` symbol.** 98 `toLocaleString`/`toLocaleDateString` calls, 106 `toFixed(...)` calls in pages but **0** Intl uses. EUR/GBP/CAD tenants, RTL languages, and any non-en-US locale see broken formatting. Single-tenant settings already include a `locale` field that's never read.
  <!-- meta: scope=web/all-pages; files=packages/web/src/pages/**/*.tsx; fix=create-utils/format.ts-formatCurrency/formatDate-using-Intl+respect-tenant-locale -->

- [ ] WEB-FF-004. **[HIGH] LeadPipelinePage `updateMut` (drag-to-status) has no optimistic update + rollback — UI lags the server every move on slow 3G.** `mutationFn: leadApi.update(id, {status})` only does `invalidateQueries` on success. On a 1.5s mobile request the lead card stays in the OLD column for ~2s, so staff frequently click "move" again, accidentally double-moving past the intended stage.
  <!-- meta: scope=web/leads; files=packages/web/src/pages/leads/LeadPipelinePage.tsx:239-247; fix=onMutate-cancel+setQueryData(pipeline)+rollback-in-onError-mirroring-TicketListPage:891 -->

- [ ] WEB-FF-005. **[HIGH] CampaignsPage `updateStatus` mutation has no `onError` handler — pause/resume failures are silent.** `updateStatus = useMutation({ mutationFn, onSuccess: invalidate })` — if the server rejects (rate-limited, segment deleted, validation error) the user sees no feedback, just a stale list. CampaignsPage has 5 mutations, only 4 handle errors.
  <!-- meta: scope=web/marketing; files=packages/web/src/pages/marketing/CampaignsPage.tsx:129-136; fix=add-onError-toast.error-and-rollback-status-pill -->

- [ ] WEB-FF-006. **[HIGH] CustomerCreatePage validation doesn't clear `errors[field]` when user types into the offending field — error message stays red even after correction.** `updateField` only updates `form`, not `errors`. User submits with empty `first_name`, types John, the red border + "First name is required" stay until next blur or re-submit. Same gap on email field.
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerCreatePage.tsx:140-181,217; fix=clear-errors[key]-on-each-updateField-call -->

- [ ] WEB-FF-007. **[HIGH] All form pages use ZERO `aria-invalid` / `aria-describedby` — screen readers cannot announce field errors.** Verified across LoginPage (`fieldErrors.username/password`), CustomerCreatePage (`errors.first_name/email`), TicketCreatePage (validation toasts only), ExpensesPage (validation via toast.error), DeviceTemplatesPage. Visual border + sub-label exists, but blind users get no programmatic hint that the field failed validation. WCAG 4.1.2 / 3.3.1 violation across the app.
  <!-- meta: scope=web/all-forms; files=packages/web/src/pages/auth/LoginPage.tsx:475-488,packages/web/src/pages/customers/CustomerCreatePage.tsx:213-221; fix=add-aria-invalid={!!errors.x}+aria-describedby="x-error"+id-on-error-paragraph -->

- [ ] WEB-FF-008. **[HIGH] Detail pages have NO `@media print` stylesheet — Ctrl+P from /invoices/:id, /tickets/:id, /estimates/:id, /customers/:id prints sidebar nav + filters + buttons, not the document.** Only `/print/*` routes have `@page`+`@media print` rules. Owners reflexively Ctrl+P a TicketDetailPage and waste paper. The print CSS lives only at `PrintPage.tsx:993-1007` + `globals.css:65`.
  <!-- meta: scope=web/all-detail-pages; files=packages/web/src/pages/{invoices,tickets,estimates,customers}/*DetailPage.tsx,packages/web/src/styles/globals.css:65; fix=add-shared-@media-print-{sidebar,filters,actions:hidden}-or-redirect-Ctrl+P-to-/print -->

- [ ] WEB-FF-009. **[MED] InventoryListPage receive-scan commits run `for (item of ...) await api.create(item)` — 50-row sessions take 50× round-trip latency.** Sequential awaits at lines 1203-1228 for `receiveScanFromCatalog` + `receiveScanQuickAdd`. Should be `Promise.allSettled(items.map(i => api.x(i)))` so 50 items take 1× RTT instead of 50×. Visible 5-15s spinner on busy days.
  <!-- meta: scope=web/inventory; files=packages/web/src/pages/inventory/InventoryListPage.tsx:1203-1228; fix=Promise.allSettled+aggregate-toasts-by-success/failure-bucket -->

- [ ] WEB-FF-010. **[MED] RepairPricingTab `gradesQuery` does sequential `getPrices()` then `api.get('/grades')` — waterfall + dynamic `import('@/api/client')` per render.** First `await repairPricingApi.getPrices()` is unused (result discarded), then `await import('@/api/client')` then `await api.get(...grades)`. Three serial awaits where one would do; comment in code admits the workaround.
  <!-- meta: scope=web/settings; files=packages/web/src/pages/settings/RepairPricingTab.tsx:471-476; fix=add-getGrades(priceId)-to-repairPricingApi+drop-dynamic-import -->

- [ ] WEB-FF-011. **[MED] CalendarPage hardcodes `'en-US'` locale on every date/time format helper.** `formatTime(iso).toLocaleTimeString('en-US', ...)`, `formatDateShort.toLocaleDateString('en-US', ...)`, plus same hardcoding in TicketListPage:1267 (`.toLocaleString('en-US', {month:'long'})`). Self-flagged at file:51 with `@audit-flag` comment but not fixed. Tenants in non-US locales see Apr 24 instead of 24 Apr.
  <!-- meta: scope=web/leads,web/tickets; files=packages/web/src/pages/leads/CalendarPage.tsx:51-62,packages/web/src/pages/tickets/TicketListPage.tsx:1267; fix=use-shared-utils/format.ts+respect-navigator.language-or-tenant.locale -->

- [ ] WEB-FF-012. **[MED] ExpensesPage form default date uses UTC midnight slice — entering an expense at 7pm PST shows tomorrow's date.** `new Date().toISOString().slice(0, 10)` returns the UTC YYYY-MM-DD; in any timezone west of UTC after ~4-5pm local the picker pre-fills the wrong day. Same pattern in CustomerListPage:327, SettingsPage:791, others using `toISOString().slice(0,10)` for display.
  <!-- meta: scope=web/expenses; files=packages/web/src/pages/expenses/ExpensesPage.tsx:46,72,103; fix=use-toLocaleDateString('sv-SE')-or-Intl.DateTimeFormat-with-tenant-tz -->

- [ ] WEB-FF-013. **[MED] Many `<img>` tags in lists/detail screens missing `loading="lazy"` — long inventory/dashboard scrolls fetch all images upfront.** `CatalogPage.tsx:501,601` (catalog grid, can be 100+ items), `DashboardPage.tsx:335` (popular products row), `TicketDevices.tsx:943,962,1038,1057` (pre/post repair photo grid, often 8+ per ticket), `InventoryDetailPage.tsx:370` (barcode), `setup/StepLogo.tsx:75` (preview). Only Communications + Portal + Landing have `loading="lazy"`.
  <!-- meta: scope=web/multiple; files=packages/web/src/pages/catalog/CatalogPage.tsx:501,601,packages/web/src/pages/dashboard/DashboardPage.tsx:335,packages/web/src/pages/tickets/TicketDevices.tsx:943,962,1038,1057; fix=add-loading="lazy"-decoding="async"-to-non-fold-imgs -->

- [ ] WEB-FF-014. **[MED] Most list pages use `key={i}` (array index) for skeletons + import-preview rows — re-render shifts state/animations onto wrong rows.** Found in CustomerListPage.tsx:830, EstimateListPage.tsx:47,501, TicketListPage.tsx:1308,1548,1648, LeadListPage.tsx:82,442, GiftCardsListPage.tsx:223, TvDisplayPage.tsx:104,168, InvoiceListPage.tsx:225,234,253,262, plus PortalInvoicesView.tsx:133 + PortalTicketDetail.tsx:141. Skeletons are mostly fine, but the import-preview rows (CustomerListPage:830) and chart `<Cell key={i}>` mappings flicker on data change.
  <!-- meta: scope=web/multiple; files=packages/web/src/pages/customers/CustomerListPage.tsx:830,packages/web/src/pages/portal/PortalInvoicesView.tsx:133,packages/web/src/pages/invoices/InvoiceListPage.tsx:225,253; fix=use-stable-id-or-content-hash-where-data-can-mutate -->

- [ ] WEB-FF-015. **[MED] DashboardPage / NpsTrendPage / ReportsPage useQuery never check `isError` — any 401/500 keeps the skeleton or empties to "0" indefinitely.** DashboardPage.tsx has 12+ `useQuery` calls, every one only destructures `{ data, isLoading }`. A logged-out token shows pulsing skeletons forever; staff think dashboard is "loading slow" when it's actually 401-looped. ReportsPage same pattern (existing FC-011 covers Nps/Referrals).
  <!-- meta: scope=web/dashboard,web/reports; files=packages/web/src/pages/dashboard/DashboardPage.tsx:858,866,874,1182,1507,1629,1665,1673; fix=destructure-isError-and-render-error-state-or-bubble-to-ErrorBoundary -->

- [ ] WEB-FF-016. **[MED] CustomerListPage importMutation invalidates AFTER server returns but never optimistically inserts rows — UI feels frozen for ~1s on Import-N.** Big CSV imports run server-side; the toast appears with count but `customers` cache only refreshes after `invalidateQueries`. Optimistic insert of `importPreview` rows would be immediate.
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerListPage.tsx:228-239; fix=onMutate-prepend-importPreview-to-cache+rollback-in-onError -->

- [ ] WEB-FF-017. **[MED] InvoiceListPage uses `new Date(inv.due_on) < new Date()` for "overdue" — string-without-Z is parsed as local time vs UTC depending on browser.** Line 378 + 47 + 501. Server-stored `due_on` strings sometimes lack the `Z` suffix; Safari treats `2026-04-24T00:00:00` as local, Chrome as UTC. A bill due "today" appears overdue on iOS Safari for tenants east of UTC.
  <!-- meta: scope=web/invoices; files=packages/web/src/pages/invoices/InvoiceListPage.tsx:47,378,501; fix=normalize-due_on-server-side-to-Z+use-shared-isoToDate-helper -->

- [ ] WEB-FF-018. **[MED] CustomerCreatePage email validator regex `/^[^\s@]+@[^\s@]+\.[^\s@]+$/` accepts `a@b.c` but rejects valid `user+tag@example.co.uk` is fine yet `用户@例子.广告` (IDN) is rejected.** The regex is also missing length cap (RFC 5321 = 254 chars) so a 5KB string passes. Pair with WEB-FF-007 — no aria-invalid means SR users get no feedback either way.
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerCreatePage.tsx:148; fix=use-shared-isValidEmail-helper-with-length-cap+IDN-allowance-or-let-server-be-source-of-truth -->

- [ ] WEB-FF-019. **[LOW] CustomerDetailPage `${memberData.monthly_price.toFixed(2)}/mo` — float multiplication lurking.** Lines 920, 1016 (tier list), 1526 (ticket totals), 1615/1618 (invoice totals). All `.toFixed(2)` on numbers that are *probably* dollars-as-float from the server. If membership price is migrated to cents (matching POS migration), every value is 100× wrong silently — same risk as WEB-FB-001 gift card.
  <!-- meta: scope=web/customers; files=packages/web/src/pages/customers/CustomerDetailPage.tsx:920,1016,1526,1615,1618; fix=accept-cents-from-server+single-formatCurrency(cents)-helper -->

- [ ] WEB-FF-020. **[LOW] PortalInvoicesView + PortalTicketDetail + PortalEstimatesView use `i > 0 ? 'border-t border-gray-50' : ''` row-zebra — no `<tbody>` keying improvement and no zebra in dark mode.** `border-gray-50` is light-only. Combined with WEB-FC-004 (no dark variants on portal) — invisible row separators on dark phones.
  <!-- meta: scope=web/portal; files=packages/web/src/pages/portal/PortalInvoicesView.tsx:133,packages/web/src/pages/portal/PortalTicketDetail.tsx:141,packages/web/src/pages/portal/PortalEstimatesView.tsx:80; fix=add-dark:border-gray-800+stable-keys-by-line-id -->

- [ ] WEB-FF-021. **[LOW] InvoiceListPage Recharts `<Cell key={i}>` re-keys on every data refresh — slice colors flicker on poll-driven refresh.** Lines 225, 253 — `key={i}` is fine for static datasets but the queries refetch on `staleTime` expiry; React reconciles wrong cell→color pairings on data length change, making slices visually jump.
  <!-- meta: scope=web/invoices; files=packages/web/src/pages/invoices/InvoiceListPage.tsx:225,253; fix=key-by-entry.name-or-method-id -->

- [ ] WEB-FF-022. **[LOW] MembershipSettings + RepairPricingTab + DeviceTemplatesPage display prices via raw `${price.toFixed(2)}` template — locale + currency symbol assumed USD.** Same root cause as WEB-FF-003; specifically MembershipSettings.tsx:120,569 + RepairPricingTab.tsx:568,569,767,924,927,930. Tenant-onboarding wizard already collects locale but it never reaches these surfaces.
  <!-- meta: scope=web/settings; files=packages/web/src/pages/settings/MembershipSettings.tsx:120,569,packages/web/src/pages/settings/RepairPricingTab.tsx:568-930; fix=replace-template-strings-with-formatCurrency(amount,tenant.currency) -->

- [ ] WEB-FF-023. **[LOW] LeadDetailPage timeline mixes `new Date(r.remind_at) < new Date()` overdue check inside a memoized list — re-evaluates only when deps change, so a reminder ticking past "now" while the page is open never flips to "Overdue" until next refetch.** `useMemo` deps are `[appointments, reminders, lead]`; clock advancing alone won't re-render. Edge case but visible during shift change-overs.
  <!-- meta: scope=web/leads; files=packages/web/src/pages/leads/LeadDetailPage.tsx:274-298; fix=add-1-min-tick-state-as-useMemo-dep-or-compute-status-at-render-time -->

- [ ] WEB-FF-024. **[LOW] Dashboard / DeviceTemplatesPage / GoalsPage use `(numerator / denominator) * 100` for progress bars without guarding NaN — division by zero when `total_entities=0` or `target_value=0` produces `NaN%` in the inline style.** `SettingsPage.tsx:2694` + `team/GoalsPage.tsx:142` already guard with `Math.min(100, ...)` but not `isNaN`. Renders as `width: NaN%` (browsers ignore, bar shows 0). Cosmetic but flags broken telemetry.
  <!-- meta: scope=web/multiple; files=packages/web/src/pages/settings/SettingsPage.tsx:2694,packages/web/src/pages/team/GoalsPage.tsx:142,packages/web/src/pages/tickets/TicketListPage.tsx:1232-1238; fix=guard-Number.isFinite(pct)-or-fall-to-0 -->

- [ ] WEB-FF-025. **[LOW] CalendarPage month grid filters all appointments per cell (`appointments.filter(...)` × 42 cells) on every render — O(N×42).** Light at 50 appts (still 2100 isSameDay calls per render), but on a busy month with 500 appts that's 21k Date constructions per render. Build a `Map<day, Appointment[]>` once with `useMemo`.
  <!-- meta: scope=web/leads; files=packages/web/src/pages/leads/CalendarPage.tsx:378-382; fix=useMemo-bucketed-by-yyyy-mm-dd -->

### Wave-Loop Finder-D run 2026-04-24 — components/hooks/stores/api/utils

- [ ] WEB-FD-001. **[HIGH] Sidebar `RecentViews` does not validate the `type` field, only `path` — `type` flows into the React `key` and (label) is shown in collapsed-mode.** `Sidebar.tsx:255-277` accepts any string for `type`/`label` from `localStorage.recent_views`. While `path` is restricted to `startsWith('/')`, an attacker who can write to localStorage (XSS in another sub-app, malicious browser extension) controls the visible text rendered in the truncated collapsed sidebar (`item.label.slice(0, 6)`). The entry can be used as a phishing surface ("Settings"-spoofed link to a `/normal/path`).
  <!-- meta: scope=web/components/layout; files=packages/web/src/components/layout/Sidebar.tsx:255-277; fix=whitelist-type-against-known-set+cap-label-length+strip-control-chars -->

- [ ] WEB-FD-002. **[HIGH] `CustomerHistorySidebar` renders attacker-controllable `photoUrl` straight into `<img src>` with no protocol allow-list.** `tickets/CustomerHistorySidebar.tsx:39-45,121-122` reads `photos[0].url || photos[0].path` from server payload. Server is trusted today, but a tenant-scoped DB-row poison or unsanitised CSV import that lets a customer-controlled string land as `data:image/svg+xml,<svg onload=…>` IS rendered (most browsers block `javascript:` in img — but `data:` SVG with embedded script is the live vector). Mirror `getIFixitUrl`'s allow-list (only http/https + restricted MIME prefixes).
  <!-- meta: scope=web/components/tickets; files=packages/web/src/components/tickets/CustomerHistorySidebar.tsx:39-45,121-122; fix=safeImageUrl-helper-rejecting-javascript:+restrict-data:-to-png/jpeg/webp -->

- [ ] WEB-FD-003. **[HIGH] `useWebSocket` sends bearer token in WebSocket `auth` payload over plaintext `ws:` when running on `http:` origin.** `useWebSocket.ts:27-45,247-249` derives protocol from `loc.protocol === 'https:' ? 'wss:' : 'ws:'`. On a same-origin HTTP dev/staging deploy the access token is shipped in `JSON.stringify({ type: 'auth', token })` over an unencrypted socket — token is then valid for the full refresh window if intercepted. Either refuse to connect on non-HTTPS origins (production) or use a short-lived ws-only nonce instead of the bearer JWT.
  <!-- meta: scope=web/hooks; files=packages/web/src/hooks/useWebSocket.ts:27-45,247-249; fix=guard-loc.protocol==='https:'-in-prod+swap-to-ws-nonce-from-server -->

- [ ] WEB-FD-004. **[HIGH] `client.ts` `forceLogout()` posts `Authorization: Bearer <oldToken>` to `/auth/logout` AFTER clearing localStorage; concurrent refresh in another tab can race.** `client.ts:155-180` reads `accessToken` from localStorage, removes it, then asynchronously calls `logoutClient.post('/auth/logout', …, { headers: { Authorization: 'Bearer <token>' } })`. If a parallel tab refreshed the token between read and post, this fires a logout against an already-invalidated token (server may 401 silently) AND the in-flight token sits in a closure for the duration of the request. Read+invalidate atomically, or use the cookie session for logout.
  <!-- meta: scope=web/api; files=packages/web/src/api/client.ts:155-180; fix=use-cookie-session-for-logout+drop-Authorization-header -->

- [ ] WEB-FD-005. **[HIGH] `usePosKeyboardShortcuts` swallows F1-F6 and `AppShell` independently rebinds F2/F3/F4/F6 — same key fires two handlers and order is undefined.** `usePosKeyboardShortcuts.ts:59-69` calls `event.preventDefault()` for every key in `KEY_MAP`. `AppShell.tsx:104-110` has a separate window listener for F2/F3/F4/F6. While POS is mounted, F2 = "Products tab" AND `navigate('/pos')` (idempotent, but masks bugs). F5 (Refresh) is also stolen by usePosKeyboardShortcuts as "Complete sale" with no opt-out — cashier expecting F5 to refresh during a frozen POS gets a checkout-modal pop instead.
  <!-- meta: scope=web/hooks+web/components/layout; files=packages/web/src/hooks/usePosKeyboardShortcuts.ts:28-69,packages/web/src/components/layout/AppShell.tsx:100-115; fix=pick-one-binding-per-Fkey+document-deviation-from-browser-defaults -->

- [ ] WEB-FD-006. **[MED] `useDraft` writes to `localStorage` under caller-supplied key with no namespace prefix — collision risk with library/3p keys.** `useDraft.ts:13,40,73,88` stores `localStorage[key] = value`. Any caller passing `key='auth'`, `'theme'`, `'token'` collides with app keys. Mirror `useDismissible`'s `bizarrecrm:dismiss:` prefix (e.g. `bizarrecrm:draft:`) — also makes auth-clear teardown trivial (regex sweep on logout).
  <!-- meta: scope=web/hooks; files=packages/web/src/hooks/useDraft.ts:13,40,73,88; fix=add-bizarrecrm:draft:-prefix+iterate-keys-on-auth-cleared -->

- [ ] WEB-FD-007. **[MED] `useUndoableAction` unmount-fire path runs `actionRef.current(runArgs)` AFTER cleanup with no guard against the user's auth being cleared during the 5-second window.** `useUndoableAction.tsx:196-216`: a destructive deletion scheduled, user clicks "Logout" within 5s, AppShell unmounts the host component, the cleanup fires the action against the now-stale token (best case: 401 + a console error; worst case: the request was queued before logout-cleanup so it runs as the previous user). Skip the unmount fire when `useAuthStore.getState().isAuthenticated === false`.
  <!-- meta: scope=web/hooks; files=packages/web/src/hooks/useUndoableAction.tsx:196-216; fix=guard-on-isAuthenticated+visibilityState -->

- [ ] WEB-FD-008. **[MED] `CommandPalette` `recentSearches` is captured ONCE at mount via lazy `useState(getRecentSearches)` — newly saved searches do not appear when the palette is reopened in the same session.** `CommandPalette.tsx:131,205,378-388`: `saveRecentSearch()` writes to sessionStorage, but `[recentSearches]` state never re-reads. Open palette, search "iPhone 14", select a result; close; reopen — "iPhone 14" still does not appear under Recent until full page reload. Either re-read on `commandPaletteOpen=true` or move the recent list to a Zustand store synced to sessionStorage.
  <!-- meta: scope=web/components/shared; files=packages/web/src/components/shared/CommandPalette.tsx:131,205,378; fix=re-read-on-open+useEffect[commandPaletteOpen] -->

- [ ] WEB-FD-009. **[MED] `BalanceBadge` shows non-localised "due" suffix even when `cents < 0` (credit balance) — confusing label.** `billing/BalanceBadge.tsx:23,40`: `Math.abs(cents)` is used for thresholds + display, so a $50 CREDIT renders as "$50.00 due" in green-ish gray. Distinguish credit vs debit: if `cents > 0` → "due"; `cents < 0` → "credit"; or hide the badge entirely on credit.
  <!-- meta: scope=web/components/billing; files=packages/web/src/components/billing/BalanceBadge.tsx:23,40; fix=branch-on-sign-of-cents+separate-label -->

- [ ] WEB-FD-010. **[MED] `ConfirmDialog` focus trap never restores focus on close — keyboard users land on `<body>` after dismissing.** `shared/ConfirmDialog.tsx:32-72`: opens, focuses confirm button, but `onCancel/onConfirm` never re-focuses the originating element. A staff member tabbing through a list, hitting a delete button, dismissing the dialog — keyboard focus is dropped to `<body>` and they have to Tab from the start. Capture `document.activeElement` in `useEffect(() => …, [open])` and restore on close.
  <!-- meta: scope=web/components/shared; files=packages/web/src/components/shared/ConfirmDialog.tsx:32-72; fix=save-prevFocus-on-open+restore-on-close -->

- [ ] WEB-FD-011. **[MED] `Header` polls `notificationApi.unreadCount()` + `smsApi.unreadCount()` on a 30s interval that runs even after auth-cleared — fires 401 storms during logout race.** `layout/Header.tsx:97-123`: the polling effect depends only on the two memoised callbacks; it does not subscribe to `bizarre-crm:auth-cleared`. After logout, the next 30-second tick sends both counts with the (now-cleared) Authorization header → both 401 → response interceptor tries the refresh path → fails → emits another logout-required event. Listen for `auth-cleared` to clearInterval, or short-circuit the fetch when `isAuthenticated === false`.
  <!-- meta: scope=web/components/layout; files=packages/web/src/components/layout/Header.tsx:97-123; fix=add-auth-cleared-listener+gate-on-isAuthenticated -->

- [ ] WEB-FD-012. **[MED] `BenchTimer` and several other tickets components use `(res: any) =>` in mutation `onSuccess` for response unwrapping.** `tickets/BenchTimer.tsx:144,146`, `tickets/DeviceTemplatePicker.tsx:88-90`, `tickets/DefectReporterButton.tsx:61-66` reach into `res.data.data.<x>` with `any`-cast — server contract drift goes silent. Define typed response shapes (e.g. `BenchStopResponse { total_seconds, labor_cost_cents }`) and have `benchApi.timer.stop` return them.
  <!-- meta: scope=web/components/tickets+api; files=packages/web/src/components/tickets/BenchTimer.tsx:142-151,packages/web/src/components/tickets/DeviceTemplatePicker.tsx:85-99,packages/web/src/components/tickets/DefectReporterButton.tsx:51-77; fix=type-bench/template/defect-responses-in-api/endpoints.ts -->

- [ ] WEB-FD-013. **[MED] `AppShell` global keydown handler captures F2/F3/F4/F6 with no opt-out — collides with `usePosKeyboardShortcuts` and any modal/dialog that wants F-keys.** `AppShell.tsx:100-115`: the only guard is `isTypingInField()`, but a focused dialog (`ConfirmDialog`, `UpgradeModal`, `PinModal`, etc.) with no input still steals F2-F6 navigations away from the user. Skip handling when `document.querySelector('[role="dialog"][aria-modal="true"]')` is present.
  <!-- meta: scope=web/components/layout; files=packages/web/src/components/layout/AppShell.tsx:100-115; fix=skip-when-modal-open-or-when-pos-mounted -->

- [ ] WEB-FD-014. **[MED] `endpoints.ts` is 27k tokens / single-file mega-export — every page-level import drags the whole module graph.** Vite tree-shakes named exports but TypeScript declaration-merging across the file means a typo in one route forces a typecheck on every consumer. Split into `endpoints/{auth,ticket,customer,inventory,…}.ts` re-exported via `endpoints/index.ts`. Bundle and HMR cost: every chunk pulls every endpoint definition.
  <!-- meta: scope=web/api; files=packages/web/src/api/endpoints.ts; fix=split-by-domain+re-export-via-barrel -->

- [ ] WEB-FD-015. **[MED] `SuccessCelebration`/`useMilestoneToasts`/`GettingStartedWidget` each inject their own `<style>` keyframes via DOM injection — three separate confetti CSS rule-sets stacked.** `onboarding/SuccessCelebration.tsx:78-114`, `onboarding/useMilestoneToasts.ts:55-86`, `onboarding/GettingStartedWidget.tsx:158-194` all build a fresh `<style>` per fire and rely on `host.remove()` 3-4 seconds later. Two milestones in flight at once = two `<style>` blocks added to `<body>`. Move the keyframes to global CSS (`index.css`) once and reuse.
  <!-- meta: scope=web/components/onboarding; files=packages/web/src/components/onboarding/SuccessCelebration.tsx:78-114,packages/web/src/components/onboarding/useMilestoneToasts.ts:55-86,packages/web/src/components/onboarding/GettingStartedWidget.tsx:158-194; fix=share-keyframes-via-global-css+reuse-host-element -->

- [ ] WEB-FD-016. **[MED] `Header` renders `user.role` raw without translation — non-English users see "admin"/"manager"/"technician" English strings.** `Header.tsx:394` `{user?.role ?? 'Unknown'}`. The roles are i18n keys server-side but the UI never maps them. Mirror `FEATURE_NAMES` shared constant with `ROLE_LABELS`.
  <!-- meta: scope=web/components/layout; files=packages/web/src/components/layout/Header.tsx:394; fix=add-ROLE_LABELS-shared-map+lookup -->

- [ ] WEB-FD-017. **[MED] `client.ts` request interceptor calls `scheduleTokenRefresh()` on every authenticated request — the JWT base64 payload is decoded + JSON.parsed every time then bails on `refreshScheduled` flag.** `client.ts:135-148`: not catastrophic but wasteful — N requests/page = N decodes. Cache the parsed `exp` claim on the token's first decode and skip the work until a different token string is observed.
  <!-- meta: scope=web/api; files=packages/web/src/api/client.ts:135-148,82-132; fix=memoise-decoded-exp-by-token-string -->

- [ ] WEB-FD-018. **[LOW] `formatPhone` returns input unchanged for any string of length ≠ 10/11 starting digits — UK +44, AU +61, MX +52 callers see whatever they typed, no normalisation.** `utils/format.ts:118-131`: comment claims "preserve user formatting"; in practice a half-formatted "(303) 261-19" returns `"(303) 261-19"` raw with no `+1` prefix or fix. CROSS13 canonical format only kicks in at exactly 10 or 11 digits.
  <!-- meta: scope=web/utils; files=packages/web/src/utils/format.ts:118-131; fix=use-libphonenumber-js-or-document-non-US-skip-explicitly -->

- [ ] WEB-FD-019. **[LOW] `confirmStore`'s `confirm()` cancels the previous resolver with `false` synchronously inside the new `confirm` call — caller's `await confirm(...)` chain may run before the new dialog is mounted.** `stores/confirmStore.ts:33-44`: `prev(false)` runs in the same microtask as `set({ open: true, … })`. If the previous awaiter then triggers another `confirm()` synchronously (e.g. a chained "are you sure? are you really sure?"), the second `confirm` overwrites the slot before React renders the first.
  <!-- meta: scope=web/stores; files=packages/web/src/stores/confirmStore.ts:33-44; fix=defer-prev(false)-via-queueMicrotask-or-setTimeout(0) -->

- [ ] WEB-FD-020. **[LOW] `safeColor` rejects all non-hex colors (no rgb/hsl/named) — utility is intentional but unflagged: callers passing `currentColor` or CSS vars silently fall back to grey.** `utils/safeColor.ts:6-11`: the regex matches only `#hex`. A theme-aware color like `var(--brand-500)` or `currentColor` returns the fallback `#6b7280`. Either expand the allow-list to safe non-script forms, or rename to `safeHexColor` for clarity.
  <!-- meta: scope=web/utils; files=packages/web/src/utils/safeColor.ts:6-11; fix=rename-to-safeHexColor+document-non-hex-rejection -->

- [ ] WEB-FD-021. **[LOW] `CommissionPeriodLock` opens server CSV export via `window.open('/api/v1/team/payroll/export.csv?period=…','_blank')` — bypasses axios auth interceptor.** `team/CommissionPeriodLock.tsx:88-93`: the new tab carries cookies but no `Authorization: Bearer` header. If the server is bearer-only (no cookie session for tenant auth), the export link 401s. Same pattern flagged in WEB-FB-006 for InvoiceDetailPage prints; reuse blob-fetch download instead of `window.open`.
  <!-- meta: scope=web/components/team; files=packages/web/src/components/team/CommissionPeriodLock.tsx:88-93; fix=axios-blob-fetch+createObjectURL+anchor-download -->

- [ ] WEB-FD-022. **[LOW] `MentionPicker` fetches the full `/employees` list with `staleTime: 60_000` — no name filter, returns every employee row including inactive/terminated ones.** `team/MentionPicker.tsx:26-34`: the picker shows everyone returned by `/employees`. A 50-employee shop renders 50 buttons in a 64px-tall dropdown. Add `?active=true&search=<typed>` and an input for filtering inside the picker.
  <!-- meta: scope=web/components/team; files=packages/web/src/components/team/MentionPicker.tsx:26-73; fix=add-active=true+typed-search-filter -->

- [ ] WEB-FD-023. **[LOW] `PageErrorBoundary` reload-loop sentinel uses `sessionStorage` keyed on `window.location.href` — query strings or hashes flip the URL and bypass the loop guard.** `shared/PageErrorBoundary.tsx:69-100`: a chunk that errors at `/tickets?status=open` then redirects to `?status=closed` would each get a fresh "first reload" pass. Strip query+hash before comparing or use `window.location.pathname`.
  <!-- meta: scope=web/components/shared; files=packages/web/src/components/shared/PageErrorBoundary.tsx:69-100; fix=use-pathname-for-sentinel-url -->

- [ ] WEB-FD-024. **[LOW] `phoneFormat.formatStorePhoneAsYouType` returns raw value when digits >11 — allows 11+ digits to pass through with no `+` prefix when the user typed a non-US country code without one.** `utils/phoneFormat.ts:48`: `if (digits.length > 11) return value` — a user pasting "447911123456" (UK without +) gets the raw 12-char string back, not the canonical international form. Tighten to require `+` for non-US.
  <!-- meta: scope=web/utils; files=packages/web/src/utils/phoneFormat.ts:40-54; fix=require-leading-plus-for-non-US-or-document-the-pass-through -->

- [ ] WEB-FD-025. **[LOW] `BulkActionBar` uses `animate-in slide-in-from-bottom` Tailwind class — no `prefers-reduced-motion` opt-out.** `shared/BulkActionBar.tsx:31-39`: WCAG 2.3.3 (Animation from Interactions) requires user-controlled disable for any non-essential animation. Wrap in `motion-safe:` or honour `motion-reduce:` to disable the slide.
  <!-- meta: scope=web/components/shared; files=packages/web/src/components/shared/BulkActionBar.tsx:31-39; fix=motion-safe:slide-in-from-bottom -->

### Wave-Loop Finder-E run 2026-04-24 — root configs + cross-cutting a11y

- [ ] WEB-FE-001. **[HIGH] No Content-Security-Policy meta nor any other security headers in index.html.** `index.html` ships only `referrer=no-referrer` + `theme-color`; no `Content-Security-Policy`, no `X-Content-Type-Options`, no frame-ancestor lockdown. SaaS app accepts third-party Google-Fonts CSS already (`fonts.googleapis.com`) so a strict CSP is overdue. Static-host fallback (Vite preview, raw S3) ships zero header policy and `SignupPage` injects hCaptcha script dynamically (§FA-010) — both go unconstrained.
  <!-- meta: scope=web/root; files=packages/web/index.html:3-15; fix=add-meta-http-equiv-Content-Security-Policy+X-Content-Type-Options-nosniff+belt-and-suspenders-with-server-helmet -->

- [ ] WEB-FE-002. **[HIGH] No skip-to-main-content link anywhere in the app shell — keyboard users tab through the full sidebar (~30 links) on every page nav.** `AppShell.tsx:172` jumps straight to `<main>` with no `<a href="#main-content">Skip to content</a>` and no `id="main-content"` target. Grep across all of `packages/web/src` returns zero hits for skip-link patterns. WCAG 2.4.1 Bypass Blocks fails for every internal page.
  <!-- meta: scope=web/a11y; files=packages/web/src/components/layout/AppShell.tsx:127-176; fix=insert-sr-only-focus-visible-skip-link-as-first-child-of-body+id=main-content-on-<main> -->

- [ ] WEB-FE-003. **[HIGH] Tailwind config + Google-Fonts link still ship Inter + Fredoka One — diverges from canonical Saved By Zero / Bebas Neue / Futura per §project_brand_fonts.** `index.html:18` loads `Fredoka+One` + `Inter`, `tailwind.config.ts:58` declares `sans: ['Inter', …]`. MEMORY explicitly lists "Web (Fredoka One) … all wrong; needs alignment". Brand drift visible site-wide.
  <!-- meta: scope=web/root; files=packages/web/index.html:18,packages/web/tailwind.config.ts:57-60; fix=swap-Google-Fonts-href-to-Bebas+Jost+JetBrains+self-host-Saved-By-Zero+Futura+update-tailwind-fontFamily.sans -->

- [ ] WEB-FE-004. **[HIGH] Manifest theme_color (`#bc398f` magenta) doesn't match index.html theme-color (`#FBF3DB` cream) — chrome address-bar flickers between colors on PWA install.** `manifest.json:8` sets `theme_color: #bc398f`, `index.html:15` sets `theme-color: #FBF3DB`, brand cream is `#fdeed0` (tailwind primary.200). Three different "primary" colors.
  <!-- meta: scope=web/root; files=packages/web/public/manifest.json:7-8,packages/web/index.html:15,packages/web/tailwind.config.ts:21; fix=unify-on-#fdeed0-cream-or-document-rationale -->

- [ ] WEB-FE-005. **[HIGH] Vite build has no `manualChunks` strategy — recharts + lucide-react + react-query risk bundling into the main page chunk.** `vite.config.ts:58-61` only sets `outDir` + `sourcemap:false`. recharts is imported by 4 pages (~120 KB); 154 lucide-react imports across the app — without `optimizeDeps.include` + `manualChunks: { recharts, lucide }` the chunk graph is opaque.
  <!-- meta: scope=web/root; files=packages/web/vite.config.ts:58-61; fix=add-rollupOptions.output.manualChunks-for-vendor-react-recharts-lucide+verify-with-rollup-plugin-visualizer -->

- [ ] WEB-FE-006. **[HIGH] Forms across `packages/web/src/pages` ship 197 `outline-none` / `focus:outline-none` declarations with no replacement focus ring on a large fraction of them.** `globals.css:50-54` defines a global `*:focus-visible` ring, but Tailwind utilities applied to a wrapper `<button>` like `focus:outline-none` strip it without `focus-visible:ring-*` replacement on many sites — keyboard navigation goes invisible. WCAG 2.4.7.
  <!-- meta: scope=web/a11y; files=packages/web/src/pages/**/*.tsx,packages/web/src/components/**/*.tsx; fix=codemod-replace-focus:outline-none-with-focus-visible:ring-2+focus-visible:ring-primary-500 -->

- [ ] WEB-FE-007. **[HIGH] `globals.css` `.btn-primary` is hard-coded green (`#16a34a`/`#15803d`/`#22c55e`) — diverges from brand cream (`primary-200=#fdeed0` per tailwind.config.ts) and from Android `LightColorScheme.primary=#a66d1f`.** Every `.btn-primary` button on the web is green-on-white while the brand surface ramp (project memo) is Zinc + cream. Visible color mismatch with mockups.
  <!-- meta: scope=web/styles; files=packages/web/src/styles/globals.css:104-111; fix=swap-btn-primary-to-bg-primary-600+text-primary-900-OR-delete-and-use-tailwind-utilities-only -->

- [ ] WEB-FE-008. **[MED] Global `*:focus-visible` outline color (`#22c55e` green) clashes with new cream brand and is hard to perceive on dark-mode green-on-zinc focused surfaces.** `globals.css:50-54` hard-codes the legacy green. Should reference `--ring` token tied to `primary-600` or `accent-500`.
  <!-- meta: scope=web/styles; files=packages/web/src/styles/globals.css:50-54; fix=replace-with-CSS-var-+update-tailwind-theme.ringColor.DEFAULT -->

- [ ] WEB-FE-009. **[MED] Global queryClient + axios singletons in `main.tsx` / `api/client.ts` are module-scoped — bfcache restore (Safari/Firefox) reuses the in-memory cache populated by the previous user session.** `main.tsx:95` `const queryClient = new QueryClient(...)`; logout `clear()` runs only on the originating tab. A bfcached tab will show previous user data for one frame before any refetch — and never refetches if `staleTime` hasn't elapsed.
  <!-- meta: scope=web/root; files=packages/web/src/main.tsx:95-103,packages/web/src/api/client.ts:42; fix=listen-pageshow-event.persisted+force-clear+full-router-replace-to-/login -->

- [ ] WEB-FE-010. **[MED] `<html lang="en">` is hard-coded — the app already i18n's currency in some pages (§FB-010) but never sets `lang` per tenant locale.** Screen-reader pronunciation for non-English tenants (es-MX, fr-CA on the roadmap) is wrong; WCAG 3.1.1 Language of Page.
  <!-- meta: scope=web/a11y; files=packages/web/index.html:2; fix=expose-tenant.locale-via-meta-and-update-document.documentElement.lang-on-mount -->

- [ ] WEB-FE-011. **[MED] No global error boundary `componentDidCatch` reporting — uncaught render errors only `console.error()`, never reach a server crash endpoint.** `main.tsx:64-67` swallows the error info into the browser console. Production has no Sentry equivalent — operators only learn about white-screens via customer complaints.
  <!-- meta: scope=web/root; files=packages/web/src/main.tsx:64-67; fix=POST-to-/api/client-errors-with-message+stack+componentStack+tenant+release -->

- [ ] WEB-FE-012. **[MED] `globals.css` `.input` focus ring also hard-codes green (`#22c55e`/`#4ade80`) — divergent from brand cream + matches the rest of the legacy palette.** Inputs across forms have green-on-cream focus accents that fight the new visual language.
  <!-- meta: scope=web/styles; files=packages/web/src/styles/globals.css:148-160; fix=swap-input-focus-color-to-primary-600+ring-primary-200 -->

- [ ] WEB-FE-013. **[MED] App-wide tables (`CustomerListPage`, `CustomerDetailPage`, `NotificationTemplatesTab`, `SettingsPage`, `AuditLogsTab`) have zero `scope="col"` / `scope="row"` / `<caption>` — screen readers can't associate cells to headers.** `grep -l 'scope="col"' packages/web/src/pages` returns 2 matches against ~20+ table sites. WCAG 1.3.1.
  <!-- meta: scope=web/a11y; files=packages/web/src/pages/customers/CustomerListPage.tsx:705-710,packages/web/src/pages/settings/AuditLogsTab.tsx,packages/web/src/pages/settings/NotificationTemplatesTab.tsx; fix=add-scope=col-on-th+visually-hidden-caption -->

- [ ] WEB-FE-014. **[MED] Forms across pages have only 3 `aria-invalid` / `aria-describedby` hits total — 99 % of inputs render error text in a sibling `<p>` with no programmatic association.** Screen readers don't announce "required, error: phone number invalid" alongside the field. WCAG 3.3.1, 4.1.2.
  <!-- meta: scope=web/a11y; files=packages/web/src/pages/auth/LoginPage.tsx,packages/web/src/pages/signup/SignupPage.tsx,packages/web/src/pages/customers/CustomerCreatePage.tsx; fix=wire-aria-invalid+aria-describedby=field-name-error-id-for-every-validated-input -->

- [ ] WEB-FE-015. **[MED] `CashRegisterPage` cash in/out form has two unlabeled `<input>` (only `placeholder=`) — placeholder-as-label is a known WCAG 1.3.1 + 3.3.2 fail and breaks autofill.** `CashRegisterPage.tsx:128-131` Amount + Reason inputs have no `<label htmlFor>` nor `aria-label`. Same pattern across many search bars.
  <!-- meta: scope=web/a11y; files=packages/web/src/pages/pos/CashRegisterPage.tsx:128-131; fix=add-visually-hidden-label+for-attr-or-aria-label -->

- [ ] WEB-FE-016. **[MED] Components in `components/team/*` + `components/billing/*` use `text-gray-*` exclusively (zero `dark:` variants).** `CommissionPeriodLock.tsx` 7 hits, `TicketHandoffModal.tsx` 4 hits, `MentionPicker.tsx` 4 hits, `RefundReasonPicker.tsx` 5 hits, `FinancingButton.tsx` etc. — all unreadable in dark mode and diverge from the surface-* token ramp (§project_brand_surface_ramp). Same class as FC-003/FC-004 but in shared components.
  <!-- meta: scope=web/components; files=packages/web/src/components/team/CommissionPeriodLock.tsx:97-177,packages/web/src/components/team/TicketHandoffModal.tsx:82-112,packages/web/src/components/team/MentionPicker.tsx:56-70,packages/web/src/components/billing/RefundReasonPicker.tsx:55-78,packages/web/src/components/billing/FinancingButton.tsx:76; fix=codemod-text-gray-N-to-text-surface-N+dark:text-surface-(1000-N) -->

- [ ] WEB-FE-017. **[MED] `index.html` viewport tag missing `viewport-fit=cover` — iOS Safari notch/home-indicator areas not respected, content clipped at the bottom of `/customer-portal` on iPhone.** `index.html:5` is the bare `width=device-width,initial-scale=1.0`. Customer-portal already runs on iPhone Safari per FC-003.
  <!-- meta: scope=web/root; files=packages/web/index.html:5; fix=append-viewport-fit=cover+adopt-env(safe-area-inset-*)-in-AppShell+portal-pages -->

- [ ] WEB-FE-018. **[MED] `index.html:18` Google Fonts CSS loaded synchronously without `preload` + `media=print` swap — render-blocks first paint by 200-400 ms on cold load.** `<link href="…fonts.googleapis.com…" rel="stylesheet">` is the canonical render-blocking pattern. Combined with FE-003 (wrong fonts) the fix is one PR: swap fonts + change strategy.
  <!-- meta: scope=web/root; files=packages/web/index.html:16-18; fix=preconnect+rel=preload-as=style+onload="this.rel='stylesheet'"+noscript-fallback -->

- [ ] WEB-FE-019. **[MED] `App.tsx` route table mounts `<TrackingPage>`, `<CustomerPortalPage>`, `<PrintPage>` outside the `<PageErrorBoundary>` wrapper used for the auth'd shell.** Lines 374-378: `print/ticket/:id`, `track`, `customer-portal/*` render naked — a render error in any of these (signed-in customer view, kiosk TV, print preview) crashes the whole React tree. Only `/tv` + `/photo-capture` get `<PageErrorBoundary>`.
  <!-- meta: scope=web/root; files=packages/web/src/App.tsx:374-378; fix=wrap-each-public-route-in-PageErrorBoundary -->

- [ ] WEB-FE-020. **[MED] No `<Route>`-level error boundary on `/login`, `/setup`, `/reset-password/:token` — auth pages crash the whole app instead of degrading.** Same diff as FE-019 but on auth surface (lines 368-371). Reset-password is opened from email — a stale token causing a render exception today shows the global ErrorBoundary's hard-coded inline-styles screen with no "Back to login" path.
  <!-- meta: scope=web/root; files=packages/web/src/App.tsx:368-371; fix=wrap-auth-routes-in-PageErrorBoundary-with-recovery-CTA -->

- [ ] WEB-FE-021. **[LOW] `LoadingScreen`, `PageLoader`, `NotFoundPage`, `SetupFailedScreen` all live inside `App.tsx` (~270 lines) — bloat the Suspense root chunk and fight code-splitting because they ride along with the router rather than the lazy pages.** Move to `components/shared/` so the single non-lazy entry stays minimal.
  <!-- meta: scope=web/root; files=packages/web/src/App.tsx:93-265; fix=extract-LoadingScreen+PageLoader+NotFoundPage+SetupFailedScreen-to-components/shared/-and-import -->

- [ ] WEB-FE-022. **[LOW] `NotFoundPage` uses `text-gray-800/600` (no dark variants) and `bg-primary-600` button (legacy primary, will look orange-on-cream after FE-007 swap).** `App.tsx:96-103` — already diverges from brand surface ramp + green-vs-cream confusion.
  <!-- meta: scope=web/root; files=packages/web/src/App.tsx:93-105; fix=text-surface-*+dark:text-surface-*+btn-primary-class -->

- [ ] WEB-FE-023. **[LOW] `ErrorBoundary` fallback in `main.tsx:71-87` uses hard-coded inline styles — ignores dark theme, fonts, and brand entirely.** Even if the rest of the app is dark-mode + cream, a render error drops the user into a white card with `#f9fafb` background + `#2563eb` blue button. Replace with Tailwind classes so the boundary at least respects `prefers-color-scheme`.
  <!-- meta: scope=web/root; files=packages/web/src/main.tsx:71-87; fix=swap-inline-styles-for-tailwind-classes-with-dark:-variants -->

- [ ] WEB-FE-024. **[LOW] `globals.css:13-15` `html { transition: background-color 0.2s ease, color 0.2s ease }` causes a flash on every theme change AND adds 200 ms of paint cost on every navigation.** Browsers can't skip the transition for class-list flips so the dark-mode toggle visibly fades — also slows initial-paint metrics by triggering a transition on first mount when the dark class lands.
  <!-- meta: scope=web/styles; files=packages/web/src/styles/globals.css:13-15; fix=scope-transition-to-html.theme-transitioning-class+toggle-class-around-the-flip-only -->

- [ ] WEB-FE-025. **[LOW] `public/sw.js` self-unregisters but is still served — every page load fetches `/sw.js`, registers, then unregisters; one wasted request + one wasted SW lifecycle per cold load.** The unregister loop in `index.html:48-59` already kills any cached SW; serving `sw.js` at all is now redundant. Manifest still lists `start_url:/` so PWA installs will succeed but find no SW.
  <!-- meta: scope=web/root; files=packages/web/public/sw.js:1-11,packages/web/index.html:47-60; fix=delete-public/sw.js+remove-unregister-script-after-N-weeks-of-deploy -->


