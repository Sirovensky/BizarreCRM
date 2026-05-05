---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## Web unwired controls audit (WEB-UNWIRED)

- [ ] WEB-UNWIRED-001. **Persist POS checkout customer signatures end-to-end.** `packages/web/src/pages/unified-pos/CheckoutModal.tsx:138,166-168,45-120,686-695` captures a signature data URL and changes the button to "Signature captured", but `buildPayload()` never includes that signature in the checkout payload. Add ticket/invoice/receipt signature storage, payload mapping, receipt rendering, and retrieval so captured signatures are durable.

- [ ] WEB-UNWIRED-002. **Fix the Communications "Off-hours auto-reply" toggle so it drives the SMS auto-reply engine.** `packages/web/src/pages/communications/components/OffHoursAutoReplyToggle.tsx:11-18,74-82` saves `inbox_off_hours_autoreply_enabled/message` and shows "Saved"; `packages/server/src/routes/sms.routes.ts:1167-1174` actually reads `auto_reply_enabled/message`. Create one canonical off-hours auto-reply config contract, make the UI save it, and make inbound SMS consume it.

- [ ] WEB-UNWIRED-003. **Wire setup email verification and resend before advancing.** `packages/web/src/pages/setup/steps/StepVerifyEmail.tsx:42-55,156-178` lets any 6 digits proceed via `onNext()` and only toasts for "Verify" / "Resend code". Hook both buttons to real verification/resend endpoints, block progression on failed verification, and keep the dev-skip path dev-only until `WIZARD-EMAIL-1` is removed.

- [ ] WEB-UNWIRED-004. **Make setup "Send test" for notification templates send a real test message.** `packages/web/src/pages/setup/steps/StepNotificationTemplates.tsx:181-183,350-361` shows a "Send test" button that only toasts. Once SMTP/SMS credentials are present, send a real email/SMS test for the selected template, return provider success/failure, and record enough detail for setup troubleshooting.

- [ ] WEB-UNWIRED-005. **Replace fake setup hardware test buttons with real service calls.** These controls look actionable but only show placeholder toasts: BlockChyp "Test connection" in `packages/web/src/pages/setup/steps/StepPaymentTerminal.tsx:153-172`, receipt printer "Print test receipt" in `packages/web/src/pages/setup/steps/StepReceiptPrinter.tsx:154-158,321-334`, cash drawer "Pop drawer (test)" in `packages/web/src/pages/setup/steps/StepCashDrawer.tsx:84-88,185-197`, and backup "Run test backup" in `packages/web/src/pages/setup/steps/StepBackupDestination.tsx:120-122,365-376`. Wire each to the real endpoint/service and show success/failure from the backend.

- [ ] WEB-UNWIRED-006. **Complete setup Repair Pricing preview modes.** `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:236-280,367-480` lets users select "Per-device matrix" and "Auto-margin rules", but both render placeholder/disabled controls including "Open full matrix (coming soon)" and "Enable auto-margin (coming soon)". Implement both editors end-to-end, including persistence, validation, preview calculations, and handoff into runtime repair pricing.

- [ ] WEB-UNWIRED-007. **Replace the financing CTA stub with a real provider flow.** `packages/web/src/components/billing/FinancingButton.tsx:56-95` shows "Pay over time with Affirm/Klarna" when provider config is present, but the click opens a modal titled "financing (stub)" instead of redirecting to a hosted checkout/status flow. Wire provider checkout, return handling, status polling, cancellation, and failure states.

- [ ] WEB-UNWIRED-008. **Wire advertised keyboard shortcuts to the advertised actions.** `packages/web/src/components/onboarding/ShortcutReferenceCard.tsx:40-56` advertises F6 Returns, Ctrl+Enter "Save and continue", and Ctrl+S "Save without closing"; `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:103-121` handles F6 with only a "Returns flow coming soon" toast, and no matching Ctrl+Enter/Ctrl+S save handlers were found in the audited web paths. Implement the shortcut handlers wherever the reference card advertises them.

- [ ] WEB-UNWIRED-009. **Wire the Getting Started "Try sandbox mode" checklist item.** `packages/web/src/components/onboarding/GettingStartedWidget.tsx:116-123,321-325` defines sandbox mode with `route: ''`, `doneKey: null`, and `comingSoon: true`, so the checklist renders a non-action badge. Build sandbox launch, routing, state isolation, and completion tracking so the checklist item can be completed.

- [ ] WEB-UNWIRED-010. **Apply saved "Primary Accent Color" globally.** `packages/web/src/pages/settings/SettingsPage.tsx:633-646` lets the user save `theme_primary_color`; `packages/web/src/pages/settings/settingsDeadToggles.ts:55-59` says the UI stores the color but only a handful of components honor it. Drive the app theme tokens from this setting across the runtime UI.

- [ ] WEB-UNWIRED-011. **Wire role permission checkboxes to persisted permissions and enforcement.** `packages/web/src/pages/settings/SettingsPage.tsx:1763-1795` renders a permission matrix with checkboxes, but non-admin cells are computed constants and `readOnly`; the footer says granular permissions are coming soon. Persist and enforce per-module/per-action permissions across the web app and server authorization checks.

- [ ] WEB-UNWIRED-012. **Wire disabled Settings controls that have live-looking labels.** Current known disabled/unwired controls: `Estimate Follow-Up Days`, `Auto-Assign Leads`, and `Notification Digest` in `packages/web/src/pages/settings/NotificationTemplatesTab.tsx:376-435`; `3CX Phone System` fields in `packages/web/src/pages/settings/SmsVoiceSettings.tsx:364-385`; `Default Date Sort` and `Default Sort Order` in `packages/web/src/pages/settings/TicketsRepairsSettings.tsx:409-441`; receipt flags `Display repair service description on thermal receipt` and `Display item physical location` in `packages/web/src/pages/settings/ReceiptSettings.tsx:607-609`. For each, add persistence, backend consumers, and runtime behavior.

- [ ] WEB-UNWIRED-013. **Wire Team Inbox "Mine" filtering to the conversations query.** `packages/web/src/pages/communications/components/TeamInboxHeader.tsx:81` and `packages/web/src/pages/communications/CommunicationPage.tsx:1120-1171,1426` let users toggle `All` / `Mine`, but `assignedFilter` is not sent with the SMS conversations query and is not applied in local filtering. Add assigned-conversation filtering to the query/API path used by this page so the segmented control changes the list.

- [ ] WEB-UNWIRED-014. **Persist SMS follow-up reminders somewhere the app actually consumes.** `packages/web/src/pages/communications/CommunicationPage.tsx:1261,2024` shows a `Remind` / `Follow up in` menu, but the handler only appends to browser `localStorage` key `sms_reminders` and toasts success. Add a reminders API, due-reminder UI, notification path, and completion/snooze handling.

- [ ] WEB-UNWIRED-015. **Make campaign trigger-rule fields drive campaign dispatch.** `packages/web/src/pages/marketing/CampaignsPage.tsx:514,639` stores `trigger_rule_json` for fields like `Days before birthday`, `Inactive for at least`, and `Unpaid invoice older than`; `packages/server/src/routes/campaigns.routes.ts:866,906` hardcodes birthday/churn windows and no audited winback dispatcher consumes `inactive_days`. Wire dispatch eligibility to the saved rule JSON for birthday, churn, winback, and invoice-age campaigns.

- [ ] WEB-UNWIRED-016. **Make Dashboard "Download Report" download/export the report.** `packages/web/src/pages/dashboard/DashboardPage.tsx:1708` labels the Daily Sales button "Download Report", but the click only navigates to `/reports`. Connect it to an export/download flow for the Daily Sales report.

- [ ] WEB-UNWIRED-017. **Make POS Training mode route checkout/create-ticket through the training endpoint.** `packages/web/src/pages/unified-pos/TrainingModeBanner.tsx:7-18,63-88` says training sales should not affect inventory and should submit to `/pos-enrich/training/submit`, but no web consumer calls `useIsTraining()` or `training/submit`; `packages/web/src/pages/unified-pos/CheckoutModal.tsx:321-332` and `packages/web/src/pages/unified-pos/BottomActions.tsx:351-370` still submit to the normal checkout/ticket path. Branch those submits while training is active and verify training transactions do not affect inventory, invoices, or sales totals.

- [ ] WEB-UNWIRED-018. **Carry Unified POS "Estimated Completion" through checkout and ticket creation.** `packages/web/src/pages/unified-pos/RepairsTab.tsx:715,779,937` captures repair `due_date`, but `packages/web/src/pages/unified-pos/CheckoutModal.tsx:57` and `packages/web/src/pages/unified-pos/BottomActions.tsx:307` drop it when mapping devices. The server persists `dev.due_on` in `packages/server/src/routes/pos.routes.ts:1675,2118`. Standardize the field contract and persist Estimated Completion for both Create Ticket and Checkout.

- [ ] WEB-UNWIRED-019. **Wire POS referral source when the setting requires it.** `packages/server/src/routes/pos.routes.ts:1421` rejects customer ticket creation when `pos_require_referral` is enabled and `ticketData.referral_source` is missing, but Unified POS checkout and create-ticket omit `referral_source` in `packages/web/src/pages/unified-pos/CheckoutModal.tsx:106` and `packages/web/src/pages/unified-pos/BottomActions.tsx:334`. Expose the field in Unified POS and persist it in the POS ticket insert, matching `packages/server/src/routes/tickets.routes.ts:1096`.

- [ ] WEB-UNWIRED-020. **Apply BlockChyp/card processing to split tender card legs.** `packages/web/src/pages/unified-pos/CheckoutModal.tsx:528` disables non-split Card when BlockChyp is not configured, but the split tender method select still renders all `PAYMENT_METHODS` at `CheckoutModal.tsx:572`. Since terminal processing is guarded by `blockchypConfigured` at `CheckoutModal.tsx:345`, require terminal-backed authorization metadata before recording a card split payment.

- [ ] WEB-UNWIRED-021. **Make invoice printing invoice-scoped.** `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:839` passes both `ticketId` and `invoiceId` to `PrintPreviewModal`, but `packages/web/src/components/shared/PrintPreviewModal.tsx:8,21,113` uses `invoiceId` only for copy and builds `/print/ticket/${ticketId}`. Add an invoice-scoped print route and renderer so Invoice Detail prints the selected invoice, not whichever invoice the linked ticket loads.

- [ ] WEB-UNWIRED-022. **Add a real print surface for standalone invoices.** `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:367-371` opens the print modal only when `invoice.ticket_id` exists; otherwise it calls `window.print()` on the interactive detail page. Since `packages/web/src/App.tsx:461` and `packages/web/src/pages/print/PrintPage.tsx:969,1067` only define/render ticket print layouts, add a standalone invoice renderer for invoices without tickets.

- [ ] WEB-UNWIRED-023. **Align cash-register history user fields.** `/pos/register` selects `user_name` in `packages/server/src/routes/pos.routes.ts:180`, but `packages/web/src/pages/pos/CashRegisterPage.tsx:9,42,191` types and renders `first_name` / `last_name`. Return and render a consistent operator-name shape so cash drawer entries show the operator.

- [ ] WEB-UNWIRED-024. **Fix Customer Create address geocoding.** `packages/web/src/api/endpoints.ts:1571-1575` calls `/geocode/lookup?address=...`, while `packages/server/src/routes/geocode.routes.ts:13-19` defines `GET /geocode?address=...` and no audited server mount for `geocodeRoutes` was found. `packages/web/src/pages/customers/CustomerCreatePage.tsx:123-137,234-236` silently catches lookup failures, so lat/lng fields can appear automatic but never populate. Mount and align the endpoint, populate lat/lng, and surface lookup failures.

- [ ] WEB-UNWIRED-025. **Persist Customer Create custom fields with the server contract and surface failures.** `packages/web/src/api/endpoints.ts:1578-1597` posts `/custom-fields/values` with `{ entity_type, entity_id, values }`, but `packages/server/src/routes/customFields.routes.ts:120-144` exposes `GET/PUT /values/:entityType/:entityId` and expects `{ fields }`. `packages/web/src/pages/customers/CustomerCreatePage.tsx:144-154,526-542` silently catches custom-field save failures, so visible custom fields can be dropped after customer creation.

- [ ] WEB-UNWIRED-026. **Wire setup booking policy keys to public booking.** `packages/web/src/pages/setup/steps/StepBookingPolicy.tsx:105` saves `booking_online_enabled`, `booking_lead_hours`, `booking_max_days_ahead`, and `booking_walkins_enabled`; `packages/server/src/routes/bookingPublic.routes.ts:117` gates on `booking_enabled` and reads `booking_min_notice_hours` / `booking_max_lead_days`. Align the wizard and public booking API keys, and implement `booking_walkins_enabled` behavior.

- [ ] WEB-UNWIRED-027. **Allowlist and apply Data Retention month fields.** `packages/web/src/pages/settings/DataRetentionTab.tsx:122` sends `retention_sms_months`, `retention_calls_months`, `retention_email_months`, and `retention_ticket_notes_months`; `packages/server/src/routes/settings.routes.ts:263` only allowlists `retention_sweep_enabled`, while `packages/server/src/services/retentionSweeper.ts:121` reads the month keys. Allowlist/validate the fields and align the UI `0 = disabled` copy with sweeper behavior.

- [ ] WEB-UNWIRED-028. **Change setup first-employee invites to a real user/invite endpoint.** `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx:157` posts `POST /api/v1/users`, but server user creation is mounted under `/api/v1/settings` in `packages/server/src/index.ts:1575` and `packages/server/src/routes/settings.routes.ts:939` requires `username`, `first_name`, and `last_name`. Add a setup invite endpoint that accepts name/email/role/send_invite, creates the user/invite, and reports delivery status.

- [ ] WEB-UNWIRED-029. **Map setup backup destination controls into the active backup service.** `packages/web/src/pages/setup/steps/StepBackupDestination.tsx:101` saves `backup_destination_type`, `backup_destination_path`, and `backup_s3_*`, but `packages/server/src/services/backup.ts:393` reads `backup_path`, `backup_schedule`, and `backup_retention`. Make S3/Tailscale/local destination settings functional in the active backup service.

- [ ] WEB-UNWIRED-030. **Apply setup warranty defaults during ticket/POS repair intake.** `packages/web/src/pages/setup/steps/StepWarrantyDefaults.tsx:87` saves `warranty_default_months_*` and `warranty_disclaimer`; ticket creation and POS repair creation read the generic `repair_default_warranty_value/unit` keys in `packages/server/src/routes/tickets.routes.ts:1141` and `packages/server/src/routes/pos.routes.ts:1621`. Use the category defaults and disclaimer during repair intake, ticket creation, POS repair creation, and receipt/invoice rendering.

- [ ] WEB-UNWIRED-031. **Make setup notification template edits update real notification template rows.** `packages/web/src/pages/setup/steps/StepNotificationTemplates.tsx:146` writes `notif_tpl_*` config keys, while runtime settings and send paths use `notification_templates` rows in `packages/server/src/routes/settings.routes.ts:1580` and `packages/server/src/services/notifications.ts:432`. Make the setup step edit and save the real `notification_templates` rows used by runtime notifications.

- [ ] WEB-UNWIRED-032. **Honor the POS "Show out-of-stock products" setting.** `packages/web/src/pages/settings/PosSettings.tsx:180` exposes `pos_show_out_of_stock`, but `packages/web/src/pages/unified-pos/ProductsTab.tsx:159` still renders zero-stock products disabled and `packages/server/src/routes/pos.routes.ts:116` does not read the setting when listing products. Apply the saved setting to the POS product list and keep frontend rendering consistent with the backend result.

- [ ] WEB-UNWIRED-033. **Use BlockChyp invoice/refund signature terms in terminal flows.** `packages/web/src/pages/settings/BlockChypSettings.tsx:407` edits `invoice_signature_terms` and `invoice_refund_terms`, but `packages/server/src/services/blockchyp.ts:63,472` only reads terminal/check-in/payment flags and signature enable/format/width. Pass the saved terms into supported terminal payment/refund flows and store what the customer accepted.

- [ ] WEB-UNWIRED-034. **Wire Memberships "Run billing now" header action to a real global billing run.** `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:81-95,188` shows a page-level `Run billing now` button, but it only toasts that billing runs nightly. Add an admin billing-run endpoint/job trigger, progress/result reporting, and safe duplicate-run protection.

- [ ] WEB-UNWIRED-035. **Make per-row Membership "Bill now" perform an immediate charge.** `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:126-150` asks to charge immediately and calls `membershipApi.runBilling(id)`; `packages/web/src/api/endpoints.ts:1337` posts `/membership/:id/run-billing` without force, while `packages/server/src/routes/membership.routes.ts:344` rejects future `current_period_end` and a later `?force=1` handler is shadowed by the duplicate route. Expose a reachable force-billing route and wire the row action to it.

- [ ] WEB-UNWIRED-036. **Make Auto-Reorder saved rules control the "Run Auto-Reorder Now" job.** `packages/web/src/pages/inventory/AutoReorderPage.tsx:53-56,188` saves rule fields like `Min qty`, `Reorder qty`, `Supplier ID`, and `Lead time (days)` to `/inventory-enrich/auto-reorder-rules`, but the run button posts `/inventory/auto-reorder` and `packages/server/src/routes/inventory.routes.ts:347` uses `inventory_items.reorder_level`, `desired_stock_level`, and `supplier_id` instead. Wire the run path to `inventory_auto_reorder_rules`.

- [ ] WEB-UNWIRED-037. **Connect Inventory Detail bin fields to bin assignments.** `packages/web/src/pages/inventory/InventoryDetailPage.tsx:238` saves `Location`, `Shelf`, and `Bin` through the normal inventory update path, but `packages/web/src/pages/inventory/BinLocationsPage.tsx:267` and `packages/server/src/routes/inventoryEnrich.routes.ts:249,306` use `inventory_bin_assignments` for pick heatmaps and bin assignment. Make those fields update the bin assignment model used by warehouse/bin features.

- [ ] WEB-UNWIRED-038. **Wire serial status changes into stock movements and references.** `packages/web/src/pages/inventory/SerialNumbersPage.tsx:186` lets users change a serial to `Sold`, `Returned`, `Defective`, or `RMA`; `packages/server/src/routes/inventoryEnrich.routes.ts:586` only updates the serial row and `sold_at`, with no stock movement, invoice/ticket reference, return, or adjustment. Integrate those transitions with inventory movements, sale/return references, and adjustment history.

- [ ] WEB-UNWIRED-039. **Replace loaner return "Charge amount" with a real fee/payment workflow.** `packages/web/src/pages/loaners/LoanersPage.tsx:31-47,117` appends the charge amount to return notes and toasts "Collect $...", while `packages/server/src/routes/loaners.routes.ts:182` stores only `condition_in` and `notes`. Create a deposit/fee/payment record and connect it to customer billing/payment collection.

- [ ] WEB-UNWIRED-040. **Persist estimate line-item tax class IDs end-to-end.** `packages/web/src/pages/estimates/EstimateListPage.tsx:192-200,287` includes `tax_class_id` in the create payload, but `packages/server/src/routes/estimates.routes.ts:289,639` inserts/updates line items without that field. Persist `tax_class_id` through create/update/read flows and apply it when estimates convert to invoices/tickets.

- [ ] WEB-UNWIRED-041. **Collect/store payment tokens during customer membership activation.** `packages/web/src/pages/customers/CustomerDetailPage.tsx:891-894,1036` activates paid memberships with only `{ customer_id, tier_id }`; the API wrapper supports `blockchyp_token`, and `packages/server/src/routes/membership.routes.ts:188` can record a successful subscription payment with a null token even though later billing needs one. Capture and store a payment token during activation, then use it for subsequent billing.

## Button-sizing audit (UI-SIZE-1)

- [ ] UI-SIZE-1. **Standardize button sizes app-wide — current per-component custom heights produce a clashing mix on high-DPR displays (2.8K OLED).** User reported 2026-04-28: some buttons too small, some too big. Symptoms visible on the POS screen — sidebar icons (32×32), brand pills (~32h), popular-model pills (~28h), top-bar tabs, bottom action bar (~48h), Quick add (~36h) all live in close visual proximity at different sizes.
  - **Root cause:** no shared Button primitive. Every component composes raw `<button>` with ad-hoc padding (`px-3 py-2`, `px-4 py-3`, etc.). Tailwind defaults aren't enforced.
  - **Solution:** add `packages/web/src/components/shared/Button.tsx` with a `size` prop:
    - `xs` — h-7 (28px) — dense table actions, inline tags
    - `sm` — h-9 (36px) — secondary actions in forms / modals
    - `md` — h-10 (40px) — default for primary forms
    - `lg` — h-12 (48px) — bottom action bars, prominent CTAs
    - `xl` — h-14 (56px) — hero / wizard Continue
    Plus `variant`: primary / secondary / ghost / danger.
  - **Migration:** sweep all 200+ raw `<button>` callsites grouped by surface (POS, settings, wizard, modals, dashboard widgets) and convert. Lint rule (`no-restricted-syntax` for `<button>` outside Button.tsx) prevents regression.
  - **Acceptance:** every CTA on every page sized from the 5-tier scale; visible audit on a 2.8K screen shows uniform rhythm; Tailwind preset for button heights enforced via Tailwind plugin.
  - **Effort:** 2-3 days for the primitive + the high-traffic surfaces (POS, dashboard, settings); long tail of ~150 cosmetic files in the same week.

## BizarreSMS hosted-tier provider (HOSTED-SMS-1)

- [ ] HOSTED-SMS-1. **Build BizarreSMS as a hosted-tier convenience SMS provider — Twilio-API-compatible relay through Bizarre's own upstream account.** Per memory `project_communications.md`: self-host shops bring their own Twilio creds; hosted-tier shops can opt into BizarreSMS as a "skip the Twilio setup" extra. Today the wizard SMS provider list excludes BizarreSMS because zero server code exists for it — picking it would silently no-op. Build sequence:
  - **Backend service:** `packages/server/src/services/sms/providers/BizarreSmsProvider.ts` implementing the same `SmsProvider` interface as `TwilioSmsProvider`. Internally relays send-message calls to Bizarre's upstream Twilio (or BulkVS / Bandwidth — pick whichever has best A2P 10DLC pricing) account.
  - **Per-tenant sender ID:** memory mandates per-tenant DKIM-equivalent. For SMS that means a per-tenant 10DLC brand+campaign registration OR a per-tenant short code. Cheap path: alphanumeric sender ID per tenant where carriers allow; fall back to a shared shortcode with `From: <shop_name>:` header prefix.
  - **Per-tenant rate limits:** prevent one shop's spam from polluting the shared 10DLC reputation. Track sends/day per tenant; cap at tier limits (Free trial 50/day, Pro 500/day, Pro+ 2k/day).
  - **Billing integration:** charge tenants per outbound segment. Settle through whatever payment processor SaaS billing uses.
  - **Inbound:** Tailscale Funnel doesn't apply here (BizarreSMS is hosted). Inbound webhooks land on Bizarre's central server, route to the right tenant by destination number, then push via WebSocket to the tenant's CRM.
  - **Wizard:** ALREADY surfaces `BizarreSMS` first in `StepSmsProvider.tsx` with three visibility states gated by isMultiTenant + tier:
    - hosted + paid (trial/pro/pro_plus) → enabled, default-selected, "Default" pill
    - hosted + free → tease (disabled card with "Pro" pill, click → /settings?tab=billing)
    - self-host → hidden entirely
    UI is wired ahead of the backend adapter so the moment HOSTED-SMS-1 lands, no frontend change is required.
  - **Failure path:** if BizarreSMS upstream is down, queue + retry with exponential backoff. Surface `Last send failed` indicator in tenant Settings → SMS → Status.
  - **Effort estimate:** 2-4 weeks dev + an actual upstream SMS account ($75/mo minimum, +per-message) + spam-reputation management. Not a launch blocker — Twilio-BYO covers the canonical self-host path.

## Wizard dev-skip cleanup (must remove before SaaS launch)

- [ ] WIZARD-EMAIL-1. **Remove the temporary dev-skip email-verify path before SaaS launch.** Currently `POST /api/v1/auth/verify-email/dev-skip` (in `packages/server/src/routes/auth.verifyEmail.routes.ts`) is gated behind `NODE_ENV !== 'production'` + `WIZARD_DEV_SKIP_EMAIL=1`. The matching UI is the "Skip email check (dev only)" button in `packages/web/src/pages/setup/steps/StepVerifyEmail.tsx`, shown only when `import.meta.env.DEV`.
  - **Why temp:** outbound email isn't wired yet; this unblocks SaaS-mode wizard dogfooding.
  - **Removal action:** delete the route, delete the env-var check, delete the button, delete the `verifyEmailApi.devSkip` call. Then verify the wizard cannot proceed past Step 2 SaaS without a real verified code.
  - **Risk:** stray prod env var could expose this. Belt-and-suspenders is to delete the code path entirely.

## Signup flow consolidation (SSW-CANON-SIGNUP)

- [ ] SSW-SIGNUP-1. **Deprecate landing-page signup modal/quick-menu — canonical entry is `/signup` route.** Today the marketing landing page may have a "Sign up" button that pops a modal duplicating the fields collected on `/signup` (name/email/password/slug). Two paths to the same outcome doubles maintenance + risks drift (modal validates differently than page). After SSW1-5 ships the wizard, the canonical entry should be the page-based form at `/signup` (existing `SignupPage.tsx`).
  - **Files to audit:**
    - `packages/web/src/pages/landing/LandingPage.tsx` — find any `<button onClick={openSignupModal}>` / `<SignupModal>` usage. Replace with `<Link to="/signup">`.
    - `packages/web/src/components/SignupModal.tsx` (if exists) — delete after callsites migrated.
    - `packages/web/src/pages/signup/SignupPage.tsx` — verify form covers everything the old modal did.
  - **Outcome:** single signup form, single validation surface, single test target. Owner clicks landing CTA → routed to `/signup` page → wizard.

- [ ] SSW-SIGNUP-2. **Pre-fill Store info contact email from signup email (don't ask twice).** Wizard Step 6 (Store info) asks for the SHOP's contact email (used on receipts + invoices). Today wizard treats this as fresh input. SaaS owners just typed their account email at signup 30 seconds earlier — the same address is almost always the right shop email too.
  - On wizard mount: read account email from auth context → pre-fill `pending.store_email` (only if currently empty).
  - Add helper text under the field: "Pre-filled from your signup email. Change if your shop uses a different address."
  - Self-host: pre-fill from admin's user record email if available; helper text omits the "signup" framing.
  - File: `packages/web/src/pages/setup/steps/StepStoreInfo.tsx` — add prefill effect on mount.

- [ ] SSW-SIGNUP-3. **Verify-email screen does NOT re-ask email — confirms it.** Audit `packages/web/src/pages/auth/VerifyEmailPage.tsx` (or similar) to ensure it's read-only display ("we sent to <email>") not an input. If currently has an input field for email, change to read-only paragraph + "Resend" button + "Wrong address? Cancel signup" link that re-opens `/signup` with prefill.

## Dynamic repair-pricing index (DPI-PRICE-INDEX) — major feature

- [ ] DPI-1. **Tiered pricing by device-model age — wire wizard + Settings UI to per-device-model price matrix.** Real shops price by model generation: latest flagships (iPhone 15/16, Galaxy S24/S25, Pixel 9) command $249 labor on a screen replacement (≈$200 profit) while older devices (iPhone X/XR/8, S9/S10) sit at $79 labor (≈$40 profit, get-in-door). Schema `repair_prices(device_model_id, repair_service_id, labor_price)` exists since migration 010 — already per-device — but wizard + Settings only expose flat-per-service pricing today. Need to surface 3-tier defaults + per-device drill-down + auto-recalc loop.
  - **Tier classification (server-side):**
    - Tier A "Flagship": `device_models.released_year >= year(now) - 2`
    - Tier B "Mainstream": `released_year >= year(now) - 5 AND released_year < year(now) - 2`
    - Tier C "Legacy": `released_year < year(now) - 5`
    - Tier thresholds stored in `store_config` so owner can override (e.g. shops in markets with longer device lifecycles like LATAM may want B = 3-7yr).
    - Re-evaluated nightly (3 AM cron, after catalog price refresh) — when a model crosses a tier boundary the next year, its `repair_prices.labor_price` rebases to the new tier's value UNLESS the row has `is_custom=1` flag (operator-overridden).
  - **Wizard input surface:**
    - Default mode: "Tier by model age" — owner sets 3 labor inputs per service. Server fans out to all device models. 12 services × 3 tiers = 36 rows owner sees → 12 × 203 = 2,436 rows on disk.
    - Advanced: "Per-device matrix" — full 203×12 grid editable. Sets `repair_prices.is_custom=1` for any cell touched.
    - Flat mode (existing): one labor per service, applied to all devices regardless of age.
  - **Schema additions needed:**
    - Add `is_custom INTEGER DEFAULT 0` column to `repair_prices` (migration 154+) so tier rebase doesn't clobber owner overrides.
    - Add `tier_label TEXT NULL` (computed at write time from device_models.released_year via wizard logic — informational, not authoritative).
    - Add `last_tier_rebase_at` timestamp for audit.
  - **Files:**
    - `packages/server/src/db/migrations/154_repair_prices_is_custom.sql` (NEW)
    - `packages/server/src/services/repairPricing/tierResolver.ts` (NEW) — exports `tierForDeviceModel(deviceModelId)`, `computeTierThresholds()`, `bulkApplyTier(serviceId, tier, labor)` for wizard fan-out.
    - `packages/server/src/services/repairPricing/nightlyRebase.ts` (NEW) — cron job; reads each device, computes current tier, updates labor for non-custom rows.
    - `packages/web/src/pages/setup/steps/StepRepairPricing.tsx` (NEW) — wizard step matching preview HTML screen 8.
    - `packages/web/src/pages/settings/RepairPricingTab.tsx` (EDIT) — add tier-mode + per-device-matrix tabs.

- [ ] DPI-2. **Daily catalog price scrape feeds dynamic profit estimator — Mobilesentrix + PhoneLcdParts via cheerio.** CLAUDE.md notes scraper exists for these two suppliers. Currently scraped values land in `supplier_catalog` table but aren't joined to `repair_prices` for profit-margin calculation. Need a cron job that:
  - Runs once daily at 3 AM local (parameterized via `store_config.catalog_refresh_hour`, default 3)
  - For each `(device_model_id, repair_service_id)` pair in `repair_prices`:
    - Look up matching part in `supplier_catalog` (FK on `device_model_id` + service category)
    - Compute `profit_estimate = labor_price - latest_supplier_cost - tax_estimate`
    - Write to new column `repair_prices.profit_estimate REAL` (migration 155)
    - Stale-flag if no supplier match found in 7 days (`profit_stale_at` timestamp)
  - **Why daily, not real-time:** suppliers update catalog overnight. Scraping per-page-load explodes request count + breaks if supplier rate-limits. Daily batch is industry-standard.
  - **Auto-margin loop (opt-in):** when `auto_margin_enabled=1` flag is on, the cron also adjusts `labor_price` to preserve a target margin: `labor_price = max(min_labor, supplier_cost + target_profit)`. Owner sets `target_profit_amber` (warning floor) + `target_profit_green` (healthy floor) per tier in Settings (these keys already exist in ALLOWED_CONFIG_KEYS audit-gap from SSW1).
  - **Edge cases:**
    - Supplier 404s on a model: fall back to last-known-cost, mark `profit_stale=1`, surface in Settings → Repair Pricing as a yellow chip "stale 12 days".
    - Supplier price spike >50% overnight: don't auto-bump labor. Surface alert "Part cost jumped from $45 to $120 — review labor". Auto-margin pauses for that row pending owner ack.
    - New device model added to catalog mid-month: auto-classified into a tier on next nightly run; labor seeded from tier defaults. Owner sees yellow "new model — review pricing" chip on dashboard.
    - Two suppliers list same part at different prices: prefer the one with newer `last_seen_at`; tiebreak by lower price.
  - **Files:**
    - `packages/server/src/services/catalogScraper.ts` (EXISTS — extend to write `repair_prices.profit_estimate` after scrape)
    - `packages/server/src/services/repairPricing/profitRecompute.ts` (NEW) — daily cron callback; iterates active `repair_prices` rows.
    - `packages/server/src/services/repairPricing/autoMargin.ts` (NEW) — opt-in labor adjustment loop with safety rails (cap delta per night at 25% to prevent runaway).
    - `packages/server/src/db/migrations/155_repair_prices_profit_columns.sql` (NEW) — adds `profit_estimate REAL`, `profit_stale_at TIMESTAMP NULL`, `auto_margin_enabled INTEGER DEFAULT 0`, `last_supplier_cost REAL`, `last_supplier_seen_at TIMESTAMP`.
    - `packages/server/src/index.ts` (EDIT) — register cron `setInterval` 60min checker, fires once at `localHour === catalog_refresh_hour` with `shouldRunDaily()` idempotency.

- [ ] DPI-3. **Settings UI — Repair Pricing tab full matrix view + audit log per-row.** Owner needs to (a) see at a glance which device-services have stale supplier costs, (b) drill into one device for full-service pricing, (c) override any cell and have it stick (`is_custom=1`), (d) revert overrides back to tier default, (e) see history of automatic price changes for compliance. Pages exists at `pages/settings/RepairPricingTab.tsx` but only renders a flat list today.
  - **UI sections:**
    - Top: tier-mode editor (3 inputs × 12 services × per service = 36 inputs total). Same layout as wizard step.
    - Middle: per-device search with autocomplete. Pick "iPhone 15 Pro" → expands to 12-service column. All 12 inputs editable; non-custom rows show "Tier A · auto" placeholder; custom rows show value with "Revert to tier" link.
    - Bottom: audit log table — `repair_prices_audit(id, device_model_id, repair_service_id, old_labor, new_labor, changed_by, source ('tier'|'manual'|'auto-margin'|'supplier-spike'), created_at)`.
  - **Files:**
    - `packages/server/src/db/migrations/156_repair_prices_audit.sql` (NEW)
    - `packages/server/src/routes/repairPricing.routes.ts` (EDIT) — add `GET /repair-pricing/audit?device_model_id=&from=&to=` + `POST /repair-pricing/revert/:id` (sets `is_custom=0`, triggers tier-rebase recompute on this row)
    - `packages/web/src/pages/settings/RepairPricingTab.tsx` (EDIT) — three new sections.

- [ ] DPI-4. **Supplier source plugin architecture — abstract Mobilesentrix/PhoneLcdParts behind interface for adding more suppliers.** Today scraper hardcodes 2 suppliers. Real shops use 3-5 (PhoneLcdParts, Mobilesentrix, MobileDefenders, Repair Outlet, eTech Parts, Allparts). Plus dropshippers and LCD wholesalers. Needs pluggable source interface.
  - **Interface:**
    ```typescript
    interface SupplierSource {
      slug: string;
      displayName: string;
      authType: 'none' | 'apikey' | 'oauth';
      fetchPart(query: PartQuery): Promise<PartListing[]>;
      isPriceFresh(seenAt: Date): boolean;
    }
    ```
  - **Per-supplier files:**
    - `packages/server/src/services/suppliers/mobilesentrix.ts` (extract from existing scraper)
    - `packages/server/src/services/suppliers/phonelcdparts.ts` (extract)
    - `packages/server/src/services/suppliers/index.ts` (registry pattern)
    - `packages/server/src/services/suppliers/types.ts` (interface)
  - **Owner UI:** Settings → Suppliers — toggle on/off per supplier. Inactive ones don't get scraped, freeing rate-limit budget.

- [ ] DPI-5. **Tier rebase visibility — dashboard chip "12 devices crossed tier boundary last night, prices auto-adjusted."** When a device flips Tier A → B (e.g. iPhone 13 ages out of flagship in 2026), labor drops automatically. Owner needs visibility or they'll be confused why margins shifted.
  - Dashboard shows a chip with last-night's rebase count
  - Click → modal: list of crossing devices + before/after labor for each service
  - Acknowledge button writes `last_tier_rebase_acked_at`
  - Future rebases without acknowledgment compound a numbered chip: "5 unread tier shifts"

- [ ] DPI-6. **Per-shop tier configuration — owner can name tiers + set their own thresholds.** Phone-only shop may want 2 tiers ("New" / "Old"); console-repair shop may want 4 (release year matters less for consoles). Wizard ships 3-tier default but Settings should expose:
  - Tier count: 2-5 selectable
  - Per-tier: label, threshold years, color chip, default profit margin %
  - Validation: tiers must cover all years without overlap; wizard gates "Save" until valid.
  - Files: `packages/server/src/db/migrations/157_pricing_tier_config.sql` adds `pricing_tiers` table; `repair_prices.tier_id` FK.

- [ ] DPI-7. **Margin alerts — when a service's profit drops below `target_profit_amber` for 7+ days, alert dashboard + email digest.** Without alerts owner doesn't notice that supplier-cost creep silently ate margins.
  - Daily cron computes `profit_estimate < target_profit_amber` → write to `margin_alerts` table
  - Auto-resolve when profit recovers
  - Dashboard chip + weekly email digest (gated by `notification_digest_mode`)
  - Settings → Repair Pricing → add "Set thresholds" — green/amber/red profit floors per tier.

- [ ] DPI-8. **Initial seed strategy — when shop picks shop type at wizard, seed `repair_prices` with industry-median labor per (tier, service).** Owner doesn't have to think about prices day-1; defaults are reasonable and will auto-tune via supplier scrape over the first week.
  - Static seed table `seed_repair_prices_by_shop_type(shop_type, service_slug, tier_a_labor, tier_b_labor, tier_c_labor)` baked into migration.
  - Wizard step 8 inputs are pre-filled from this table; owner can adjust before save.
  - Sources for industry medians: scrape RepairDesk/RepairShopr public price lists once, hand-verified, anonymized. Document source in migration comment.
  - Update annually as part of major releases.

- [ ] DPI-9. **End-to-end test — fixture device catalog + supplier scrape + tier reclassify + auto-margin recompute.** Pure-handler vitest in `packages/server/src/__tests__/repairPricing.dpi.test.ts`:
  - Setup: in-memory DB with 3 device models (one per tier), 1 service, 1 fake supplier listing.
  - Run wizard fan-out → assert 3 `repair_prices` rows created at correct tier values.
  - Override one row (`is_custom=1`).
  - Run nightly rebase → assert non-custom rows updated, custom row unchanged.
  - Bump supplier cost → run profit recompute → assert `profit_estimate` updated, alert written.
  - Run auto-margin cron with target_profit set → assert labor_price bumped, capped at 25% delta.

- [ ] DPI-11. **Per-device pricing matrix — full 203×12 grid editor with virtualization, bulk-edit, CSV export/import, profit heatmap.** This is the power-user interface that lives behind the "Per-device matrix" tab in Settings → Repair Pricing AND in the wizard's advanced mode. Owner can override any individual cell, see profit-per-cell, sort/filter by margin, and bulk-apply changes. Performance-critical: naive React rendering of 2,436 input cells will stutter on a quad-core laptop, so virtualization is mandatory.
  - **Grid layout:**
    - Rows: 203 device models (`device_models` table, `is_active=1`)
    - Columns: 12 active services (`repair_services`, `is_active=1`) + frozen left column (device name + thumb + tier chip)
    - Rendered via `@tanstack/react-virtual` (already in tree per package.json) — only visible viewport rows render. ~30 visible rows × 12 cols = 360 inputs in DOM at once. Smooth scroll on >100k cells confirmed.
    - Sticky top header (service names + part-cost-trend mini chart per column).
    - Sticky left column (device row).
    - Cell width: 96px (input + tier chip + delta arrow).
  - **Cell anatomy:**
    - Input value = `repair_prices.labor_price`
    - Background tint by profit health: green (>amber), amber, red (<min). Read from `profit_estimate`.
    - Top-right badge: `T` (tier-derived, no override) / `C` (custom override).
    - Bottom-right delta: `↑$5` (labor went up vs last week) / `↓$3` / blank.
    - Hover tooltip: full breakdown — labor, supplier cost, last seen, tier, profit, suggested labor.
    - Right-click: "Revert to tier default" / "Lock cell (no auto-margin)" / "View audit history".
  - **Bulk operations:**
    - Multi-select rows via checkbox column → "Apply labor $X to all selected for column Y"
    - Multi-select columns (services) → "Multiply all selected by 1.10" (10% bump)
    - Select-all-tier (e.g. all Tier A) → bulk-edit
    - Confirmation modal showing impact: "147 cells will be modified. Estimated profit change: +$8.2k/month"
  - **Filtering + sorting:**
    - Filter by tier (A/B/C/All)
    - Filter by margin status (red/amber/green/stale)
    - Filter by manufacturer (Apple/Samsung/Google/etc.)
    - Filter by search box (free-text against device name)
    - Sort by any column (labor ascending/descending) OR by row's average profit
    - Hot-models toggle: filter to top-20 most-ticketed devices in last 30 days
  - **CSV export/import (round-trip):**
    - Export: streams CSV with columns `device_id, device_name, tier, service_id, service_name, labor_price, is_custom, profit_estimate, supplier_cost, last_supplier_seen_at`. Filename `repair-prices-YYYY-MM-DD.csv`.
    - Import: upload CSV; preview diff (rows changed/added/removed) before commit; commit applies via batch UPDATE; flags `is_custom=1` on every modified row.
    - Validation: reject CSV with missing device_id/service_id, invalid labor (negative or >$10000), or columns the importer doesn't know about.
    - Audit: each imported row gets `repair_prices_audit` entry with `source='csv-import'`, `imported_filename`, `imported_by`.
  - **Profit heatmap toggle:**
    - Off (default): cells show labor value as text.
    - On: cells colored by `(profit_estimate / labor_price) * 100`. Green = >40% margin, amber = 20-40%, red = <20%. Useful for spotting under-priced services at a glance.
    - Color-blind mode: switches to symbol overlay (◆/●/▲) instead of pure color.
  - **Mobile/tablet:**
    - Below `lg` breakpoint, the 12-column matrix collapses to a 2-pane drill-in:
      - Pane 1: device list (vertical scroll, 203 rows)
      - Pane 2: tap a device → expand all 12 services in card form
    - Bulk-edit disabled on mobile (too easy to misclick at scale).
  - **Performance budgets:**
    - Initial render <500ms with 203 devices loaded
    - Cell-edit response <16ms (one frame)
    - Filter change <100ms
    - CSV export of full grid <2s
    - CSV import + diff preview <5s for 2,436 rows
  - **State management:**
    - Use `react-hook-form` with `useFieldArray` for input state
    - Optimistic update on save (roll back on server error with toast + audit row marked `failed`)
    - Debounce save 800ms after last keystroke per cell
    - `BeforeUnload` warning when dirty
  - **Server endpoints:**
    - `GET /repair-pricing/matrix?tier=&manufacturer=&q=` — paginated per-device-service rows with tier metadata + profit estimate
    - `PATCH /repair-pricing/matrix` — batch update (max 500 rows per call), returns audit log entries
    - `POST /repair-pricing/matrix/import` — CSV upload, returns dry-run diff
    - `POST /repair-pricing/matrix/import/commit` — applies the diff
    - `GET /repair-pricing/matrix/export.csv` — streaming CSV (uses Node Readable, mirrors WEB-W3-013 inventory export pattern)
  - **Edge cases:**
    - **Device added to catalog mid-edit:** server returns 409 on save with stale-tier-id; client refetches + merges, preserves user's pending edits.
    - **Service archived during edit:** column greys out; existing rows for that service marked `archived_at`; values preserved for historical invoice reconstruction.
    - **Supplier price spike between page-load and save:** server includes `supplier_cost` snapshot in PATCH payload; if current cost differs by >25%, server rejects with `409 supplier_drift` + new value; client shows banner.
    - **Concurrent edits:** optimistic-locking via `repair_prices.updated_at` etag in PATCH header. Conflict → "Another admin edited row X seconds ago. Reload?"
    - **Partial save failure:** transactional batch — all-or-nothing per PATCH call. Failed batches return per-row error array; UI highlights the offending cells.
  - **Files:**
    - NEW: `packages/web/src/pages/settings/RepairPricingMatrix.tsx` (mounted as a sub-tab of `RepairPricingTab`)
    - NEW: `packages/web/src/pages/settings/components/PriceCell.tsx` — single cell with badge + delta + tooltip
    - NEW: `packages/web/src/pages/settings/components/MatrixToolbar.tsx` — filter bar, bulk-edit modal, heatmap toggle, export/import buttons
    - NEW: `packages/web/src/api/repairPricingMatrix.ts` — client wrapper for matrix endpoints
    - EDIT: `packages/server/src/routes/repairPricing.routes.ts` — add 4 matrix endpoints
    - NEW: `packages/server/src/services/repairPricing/csvImport.ts` — diff-based import
    - NEW: `packages/server/src/services/repairPricing/matrixQuery.ts` — efficient JOIN with `device_models` + `repair_prices` + `supplier_catalog`
    - DEPENDS: DPI-1 (tier classification), DPI-2 (profit_estimate column), DPI-3 (audit log table)
  - **Out of scope (future):** AI-suggested labor based on neighbor-shop pricing (would need shared pricing-bench feed); seasonal auto-adjustments (holiday pricing).

- [ ] DPI-12. **Expand `repair_services` seed catalog — console, tablet, IT services categories are too thin to ship.** Wizard "Console / PC" card claims 15 services but database only has 4 (HDMI port, disc drive, controller, overheating). Tablet has 2 (screen, battery only). "IT services" doesn't exist as a distinct category — wizard would have to fall back to a laptop subset. Need full coverage so shop owner picking a category gets a usable catalog day-1.
  - **Console (4 → 12):** add joystick repair, joystick drift fix, fan replacement, thermal paste, power button repair, eject mechanism repair, BD drive laser, hard drive upgrade, controller buttons, controller charge port, controller battery, jailbreak/firmware reset.
  - **Tablet (2 → 10):** add charging port, camera, button repair, water damage diagnostic, back glass, speaker, mic, software reset, jailbreak removal, glass-only (no LCD).
  - **IT services (0 → 9 dedicated):** virus removal, malware cleanup, OS reinstall, data recovery (drive imaging), network setup (home), network setup (small office), printer setup, password reset, in-home diagnostic visit. Add `category='it_service'` enum value + UI category icon.
  - **Phone (11 → 16):** add Face-ID repair, True-Tone calibration after screen, esim activation help, jailbreak/de-jailbreak, MDM unlock (with proof-of-ownership gate).
  - **Laptop (14 → 18):** add backlight repair, trackpad repair, HDMI port, audio jack, BIOS unlock, password reset.
  - **TV (9 → 14):** add HDMI port, audio output, voice remote pairing, smart-feature reset, wall-mount install service.
  - **Files:**
    - `packages/server/src/db/migrations/158_repair_services_expansion.sql` — INSERT OR IGNORE for new rows.
    - Update `packages/server/src/db/migrations/010_repair_pricing.sql` annotations only (don't modify shipped INSERT statements — additive in mig 158).

- [ ] DPI-13. **Seed `repair_prices` industry-median labor per (shop_type, tier, service) at wizard time.** Today `repair_prices` is empty — every owner has to set every price. Wizard shop-type pick should fan out reasonable defaults. Schema: a static seed table maps shop type + tier + service to a labor amount that's pre-populated when owner clicks Save on Step 8.
  - **Seed source data (research one-time + verify):** scrape RepairDesk + RepairShopr public price benchmarks; cross-reference with iFixit "professional rate" guide; survey 5-10 partner shops for sanity check. Document source per service in migration comment so future maintainers can re-verify.
  - **Schema:**
    ```sql
    CREATE TABLE seed_repair_prices (
      shop_type TEXT NOT NULL,        -- 'phone', 'multi-device', 'console', 'it', 'tv'
      tier TEXT NOT NULL,             -- 'A', 'B', 'C'
      service_slug TEXT NOT NULL,     -- FK to repair_services.slug
      labor_price INTEGER NOT NULL,   -- cents
      source TEXT,                    -- 'repairdesk-2025', 'shop-survey-2026q1', etc.
      verified_at DATE,
      PRIMARY KEY (shop_type, tier, service_slug)
    );
    ```
  - **Wizard integration:** when owner completes Step 5 + Step 8, server fans out: for each device_model in shop's category × each active service, look up `seed_repair_prices(shop_type, computeTier(device_model.release_year), service_slug)` → write `repair_prices(device_model_id, repair_service_id, labor_price)`.
  - **Coverage required:** 5 shop types × 3 tiers × ~12 services = 180 seed rows minimum. Document missing combinations → fall back to flat-per-service if the (shop_type, tier, service) tuple is missing in the seed table.
  - **Annual refresh:** seed table re-verified yearly + bumped via new migration. Owner who already customized via `is_custom=1` is protected from rebase clobber.
  - **Files:**
    - `packages/server/src/db/migrations/159_seed_repair_prices.sql` — table + ~180 INSERT rows.
    - `packages/server/src/services/repairPricing/seedFanout.ts` — wizard-time fan-out helper.

- [ ] DPI-14. **TV models seed — find or create.** CLAUDE.md claims "67 TV models" exist but `device-models-seed.ts` has 0 with `category: 'tv'`. Either (a) TVs live in a separate seed file, or (b) the 67 number was aspirational. Audit + reconcile:
  - Search for `tv-models` / `tv_models` table or seed file under `packages/server/src/db/`.
  - If missing: add 67 TV models with manufacturer (Samsung, LG, Sony, Vizio, Hisense, TCL, Philips), screen size (40"-85"), panel type (LED/OLED/QLED/Plasma), release year. Source: TV manufacturer model lists.
  - Wizard "TV repair" card should reflect the actual count.

- [ ] DPI-15. **Tier classification needs `release_year` to be populated on every device row.** `device-models-seed.ts` has `release_year ?? null` — many older devices lack release year. Tier resolver falls back to "unknown" → Tier C by default. Audit + backfill missing release years for the 236 seeded models.
  - Verify each row has `release_year` set.
  - Add NOT NULL constraint after backfill (migration).

- [ ] DPI-10. **Admin override audit + 4-eyes for tier threshold changes.** Changing tier thresholds (e.g. moving "Tier A" cutoff from 2 to 3 years) re-prices thousands of rows. Should require admin role + a confirmation modal listing impact: "This will reprice 47 device models. Estimated revenue change: -$14k/yr. Type 'CONFIRM' to proceed."
  - Audit log entry with before/after thresholds + projected revenue delta.
  - Email all admin users on change.

- [ ] DPI-16. **Auto-rounding of computed labor totals to psychological prices.** When auto-margin (DPI-7/8/9) computes a labor price like `$147.62` from `parts_cost + target_profit`, owners typically want a rounded retail price, not a fractional one. Add a per-shop `repair_pricing_rounding_mode` config:
  - `off` — emit raw computed value (`$147.62`).
  - `nearest_dollar` — round to nearest whole ($148).
  - `nearest_5` / `nearest_10` — round up to nearest $5 / $10 ($150).
  - `psychological_99` — round up and subtract $0.01 ($149.99). Many shops sell on charm-pricing — `$149.99` reads cheaper than `$150` to customers.
  - `psychological_95` — round up to nearest $5 then subtract $0.05 ($149.95).
  - Configurable in **Settings → Repair pricing → Rounding** with a live preview ("Sample: parts $45 + 60% margin = $112.50 → rounded to $114.99"). Applies to all auto-computed labor prices; manual overrides bypass rounding entirely.
  - Schema: add `repair_pricing_rounding_mode` to ALLOWED_CONFIG_KEYS in `settings.routes.ts`. Default `off` for new shops to avoid surprising migrations.
  - Wire in the same recompute pass as DPI-7 auto-margin so a parts-cost change triggers (recompute → round → write `repair_prices.labor_price`).
  - Tests: pure unit tests on the rounding helper (`roundForRetail(amount, mode)`); end-to-end fixture with auto-margin enabled + each rounding mode.

## Web Audit Wave-WEB-2026-04-24 — secondary surfaces (search agent A3)

### P2 (cosmetic / missing UI)

## Web Audit Wave-WEB-2026-04-24 — settings tabs + setup wizard (search agent A1)

### P0
  - File: `packages/web/src/pages/settings/PosSettings.tsx:220-236`
  - Fix: enforce server-side. POS routes should require a PIN-validation header on tendering / ticket actions when these flags are true. Add middleware `requirePosPin` reading store_config + `pos_pin_hash`.

### P1 (silent no-op)

## Web Audit Wave-WEB-2026-04-24 — core entity workflows (search agent A2)

### P1 (silent no-op / broken feature)
  - File: `packages/web/src/pages/tickets/TicketListPage.tsx`
  - Fix: map group label → status_id before query param.
- [ ] WEB-W2-011. **Activity filter tabs are client-side only — incomplete if backend paginates.**
  - File: `packages/web/src/pages/tickets/TicketNotes.tsx`
  - Fix: pass filter as query param to activity endpoint; rebuild filtering server-side.
  - File: `packages/web/src/pages/tickets/TicketDevices.tsx`
  - Fix: include these fields in PUT payload; verify route accepts them.
  - File: `packages/web/src/pages/tickets/TicketPayments.tsx`
  - Fix: replace `prompt()` with inline modal/input.

## Web Audit Wave-WEB-2026-04-24 Search S6 — entity create + employee + comms + reports

### P0 (data loss / broken submit)






### P1 (silent no-op / missing feature parity)














### P2 (UX / cosmetic / missing polish)

- [ ] WEB-S6-029. **TicketCreatePage: no form persistence — navigating away mid-fill (e.g. to look up a customer) loses all entered device data with no warn.**
  - File: `packages/web/src/pages/tickets/TicketCreatePage.tsx`
  - Fix: serialize form state to `sessionStorage` on change; restore on mount; clear on successful submit. Show `beforeunload` warning if form is dirty.





### Wave-75 scan-loop findings (2026-04-24) — customer GDPR re-auth (blocked on user WIP)
- [ ] SCAN-1183. **[HIGH] `DELETE /customers/:id/gdpr-erase` admin re-auth has no rate limit + no password length cap — sibling gap of SCAN-1178/1179/1181/1182 + SCAN-1108.**
  <!-- meta: scope=server/routes; files=packages/server/src/routes/customers.routes.ts:1870-1890; fix=checkWindowRate('customer_gdpr_reauth',userId:ip,5,3600_000)+cap-password<=72+recordWindowFailure-on-mismatch; BLOCKED: file is user WIP (never touch per project rule) -->

## AUDIT CYCLE 1 — 2026-04-19 (shipping-readiness sweep, web + Android + management)

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

- [ ] **T-C6-server. Tablet ticket-detail Quote add-row — server endpoints for SVC + MISC lines.** 2026-04-28: Android side shipped (commit on `androidfixes426` after T-C10): typeahead dropdown queries `InventoryApi.getItems(q=...)` + `RepairPricingApi.getServices(q=...)` in parallel, merges to `QuoteSuggestion(kind=PART|SVC|MISC, …)`. Tap on a PART suggestion ships a real `AddTicketPartRequest{inventory_item_id,…}` to existing `POST /tickets/devices/{deviceId}/parts` (server-wired). Tap on SVC or MISC currently logs the structured payload via `Timber.tag("T-C6-deferred")` and surfaces a "wiring deferred" snackbar — there is **no server route** for repair-service or one-off misc lines on a ticket today. Server work needed:
  - **(a)** New `POST /api/v1/tickets/devices/:deviceId/services` accepting `{ repair_service_id, name, labor_price, device_id, ticket_id }`. Should insert into a new `ticket_device_services` table (or extend existing `ticket_device_parts` with a `kind` discriminator — pick one). Mirrors the existing parts add flow.
  - **(b)** New `POST /api/v1/tickets/devices/:deviceId/misc` accepting `{ name, amount_cents, device_id, ticket_id }` for free-text one-off charges. Same insertion pattern; emits a `MISC` line on the ticket quote that doesn't reference inventory or pricing catalog.
  - **(c)** Optional: unified `GET /api/v1/search/quote?q=…` returning `[{kind, id, name, meta, price_cents}]` so Android (and future iOS / web tablet redesign) can stop merging client-side. The Android client merge stays in place either way as a 404-tolerant fallback.
  - Android wire-up after server lands: replace the two `else` branches in `TicketDetailViewModel.addQuoteLine` (search for `T-C6-deferred` Timber tag) with the real Retrofit calls — UI is fully built and predetermined payloads are already shaped to match these endpoints.

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





## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10

Self-serve signup on 2026-04-10 with slug `dsaklkj` completed successfully and the user was able to log in, but the shop then dropped them straight into the dashboard without asking for any of the info that `store_config` needs: store name (we set it from the signup form, but only that one key), phone, address, business hours, tax settings, receipt header/footer, logo, and — critically — whether they want to import existing data from RepairDesk / RepairShopr / another system. Result: the shop boots with mostly empty defaults and the user has to hunt through Settings to fill everything in. Poor first-run UX.






## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)

### Agent 1: Authentication & Session Management
- [ ] SA1-2. **Session Storage:** Authentication tokens stored in `localStorage` in the frontend are theoretically vulnerable. Migration to `httpOnly` secure cookies for the `accessToken` is recommended (currently only `refreshToken` uses cookies).
  - [ ] BLOCKED: full auth refactor — every web API call in `packages/web/src/api/**` sends the token from localStorage via axios interceptor; the server expects `Authorization: Bearer ...` and supports CSRF via double-submit. Migrating accessToken to httpOnly requires (1) server reads cookie OR header, (2) CSRF double-submit header on every mutating route, (3) web axios interceptor removes bearer header, (4) SW token refresh path still works over cookie, (5) Android app unaffected (keeps bearer). Too large for a single-item commit; should ship as its own PR with security-reviewer pass. Overlaps D3-6.

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely. — **Partial mitigation in place:** refreshToken is already `httpOnly + secure + sameSite: 'strict'` (auth.routes.ts:269), so XSS cannot rotate a session. AccessToken is short-lived. Full migration to httpOnly access cookie + CSRF header is a larger auth refactor — tracked but deferred.
  - [ ] BLOCKED: dup of SA1-2 — same auth refactor. Consolidate under SA1-2.

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
_See DONETODOS.md for D4-1 closure._

### 5. Infinite Undo/Redo Voids
_See DONETODOS.md for D4-5 closure._

### 9. HCI Touch Target Ratios
_See DONETODOS.md for D4-9 closure._

## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)

### 2. Missing Compose List Keys (Jank)
_See DONETODOS.md for D5-2 closure._

### 5. Infinite Snackbar Queues
_See DONETODOS.md for D5-5 closure._

# Functionality Audit

Scope: static audit of the BizarreCRM web/server codebase for user-visible usability bugs, disconnected buttons, TODO/stub behavior, and partially implemented enrichment features. This pass read `CLAUDE.md`, `README.md`, and used parallel code-review agents plus manual verification of the highest-risk findings.

## Executive Summary

- Highest risk area: public/customer-facing payment and messaging flows. Several buttons look live but either hit missing routes or mark payment state without a real provider checkout.
- Main staff-facing risk: settings and workflow controls are sometimes rendered as normal live controls even when metadata or code says the behavior is only planned.
- Most valuable quick wins: hide or badge incomplete controls, wire missing backend routes for customer-facing CTAs, and add navigation/entry points for pages/components that already exist.

## Low Priority / Usability Findings

  - `packages/web/src/components/shared/CommandPalette.tsx` searches entities only (tickets, customers, inventory, invoices), not static app pages.

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

## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

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

## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

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

### Wave-Loop Finder-A run 2026-04-24 — web/pages auth+signup+landing+dashboard+settings+team+super-admin+setup+billing+subscriptions+employees
- [~] WEB-FA-013. **[MED] DashboardPage: Hard-coded supplier domains:** mobilesentrix.com, phonelcdparts.com — not configurable from Settings. Fixer-B14 2026-04-25 — partial: extracted to `SUPPLIER_BASE_URLS` lookup at the top of the missing-parts block (`packages/web/src/pages/dashboard/DashboardPage.tsx`) so adding a third supplier is a one-line map entry. True per-tenant Settings configurability still pending (server `store_config` key + Settings UI).
  <!-- meta: scope=web/pages/dashboard; files=packages/web/src/pages/dashboard/DashboardPage.tsx:174-177; fix=move-to-catalog-provider-config -->

### Finder-C web polish findings (2026-04-24) — pages/{tickets,loaners,leads,automations,marketing,communications,reports,reviews,photo-capture,portal,print,tracking,tv,voice,expenses}
- [~] WEB-FC-012. **[MED] `ReferralsDashboard` computes stats from only the first page of rows.** Server returns rows with no pagination metadata, and the page computes `total`, `converted`, `conversion_rate`, and the leaderboard from that array — totals understate reality as soon as there are >N referrals. No "showing X of Y" footer. — **Fixer-B23 2026-04-25 [PARTIAL-truth-in-UI]**: query now reads `meta.total` or `X-Total-Count` header when the server provides one; if `serverTotal > rows.length` the "Total referrals" stat renders as `N+`, an amber `role="note"` banner says "Showing N of Y. Totals/conversion rate/leaderboard computed from the loaded page only." Fully-correct stats still need either a `/reports/referrals/stats` endpoint or pagination iteration server-side; tracked open for that.
  <!-- meta: scope=web/pages/marketing; files=packages/web/src/pages/marketing/ReferralsDashboard.tsx:52-75,98; fix=add-/reports/referrals/stats-endpoint-or-iterate-pagination-before-computing -->
- [~] WEB-FC-014. **[MED] `TaxReportPage` and `PartnerReportPage` open server-rendered HTML via `window.open(..., '_blank', 'noopener')` with no loading/auth-fail fallback.** Date range has no validation — `from > to` still opens a blank report. A logged-out session opens the server's 401 HTML in a new tab, which looks like the feature is broken rather than "please log in". — Fixer-B10 2026-04-25: TaxReportPage now blocks `from > to` / empty dates with inline error before window.open; auth-fail blob preflight + PartnerReportPage still TODO.
  <!-- meta: scope=web/pages/reports; files=packages/web/src/pages/reports/TaxReportPage.tsx:20-28 packages/web/src/pages/reports/PartnerReportPage.tsx:15-18; fix=validate-from<=to+HEAD-preflight-or-fetch+blob+open-with-revocation-or-inline-iframe-preview -->

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



- [~] WEB-FF-022. **[LOW] MembershipSettings + RepairPricingTab + DeviceTemplatesPage display prices via raw `${price.toFixed(2)}` template — locale + currency symbol assumed USD.** Same root cause as WEB-FF-003; specifically MembershipSettings.tsx:120,569 + RepairPricingTab.tsx:568,569,767,924,927,930. Tenant-onboarding wizard already collects locale but it never reaches these surfaces. — Fixer-C7 2026-04-25: PARTIAL. `MembershipSettings.tsx:120,569` swapped to `formatCurrency(...)` from `@/utils/format`. RepairPricingTab + DeviceTemplatesPage callsites still owed.
  <!-- meta: scope=web/settings; files=packages/web/src/pages/settings/MembershipSettings.tsx:120,569,packages/web/src/pages/settings/RepairPricingTab.tsx:568-930; fix=replace-template-strings-with-formatCurrency(amount,tenant.currency) -->


- [~] WEB-FF-024. **[LOW] Dashboard / DeviceTemplatesPage / GoalsPage use `(numerator / denominator) * 100` for progress bars without guarding NaN — division by zero when `total_entities=0` or `target_value=0` produces `NaN%` in the inline style.** `SettingsPage.tsx:2694` + `team/GoalsPage.tsx:142` already guard with `Math.min(100, ...)` but not `isNaN`. Renders as `width: NaN%` (browsers ignore, bar shows 0). Cosmetic but flags broken telemetry. PARTIAL-by-Fixer-GGG 2026-04-25 — `team/GoalsPage.tsx` now coerces `target_value`/`progress` via `Number()`, computes `ratio`, and clamps via `Number.isFinite(ratio) ? Math.max(0, Math.min(100, ratio)) : 0` so string targets / `null` denominators render `width: 0%` instead of `NaN%`. SettingsPage.tsx:2694 (already partially guarded) and DeviceTemplatesPage / TicketListPage progress bars still need the same `Number.isFinite` audit — leaving open under `[~]`.
  <!-- meta: scope=web/multiple; files=packages/web/src/pages/settings/SettingsPage.tsx:2694,packages/web/src/pages/team/GoalsPage.tsx:142,packages/web/src/pages/tickets/TicketListPage.tsx:1232-1238; fix=guard-Number.isFinite(pct)-or-fall-to-0 -->


### Wave-Loop Finder-D run 2026-04-24 — components/hooks/stores/api/utils














- [ ] WEB-FD-014. **[MED] `endpoints.ts` is 27k tokens / single-file mega-export — every page-level import drags the whole module graph.** Vite tree-shakes named exports but TypeScript declaration-merging across the file means a typo in one route forces a typecheck on every consumer. Split into `endpoints/{auth,ticket,customer,inventory,…}.ts` re-exported via `endpoints/index.ts`. Bundle and HMR cost: every chunk pulls every endpoint definition.
  <!-- meta: scope=web/api; files=packages/web/src/api/endpoints.ts; fix=split-by-domain+re-export-via-barrel -->




- [~] WEB-FD-018. **[LOW] `formatPhone` returns input unchanged for any string of length ≠ 10/11 starting digits — UK +44, AU +61, MX +52 callers see whatever they typed, no normalisation.** `utils/format.ts:118-131`: comment claims "preserve user formatting"; in practice a half-formatted "(303) 261-19" returns `"(303) 261-19"` raw with no `+1` prefix or fix. CROSS13 canonical format only kicks in at exactly 10 or 11 digits.
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

### Customer portal (`packages/web/src/pages/portal/`)

### Photo capture

### Print page

### Landing page

### Super-admin
- [ ] WEB-S4-041. **P2 — No pagination — fetches all tenants in one request.** Fix: server-side pagination params.

## Web Audit Wave-WEB-2026-04-24 Search S5 — cross-cutting UX

- [ ] WEB-S5-040. **[P3] `useSettings` creates N parallel useQuery subscriptions — coerceSettings runs N times.** Fix: lift into SettingsContext.

## Web Audit Wave-WEB-2026-04-24 Search S7 — data integrity + edge cases

### P0 — data loss / silent corruption / security









### P1 — wrong data displayed / partial data loss / bad UX under edge cases























### P2 — edge case / cosmetic / minor data inconsistency








- [ ] WEB-S7-038. **`parsePage` returns 1 for page=0 or page=-1 (good) but also for page=99999 — very large page numbers allowed server-side; sparse result sets return empty arrays silently with no "beyond last page" indicator.** `packages/server/src/utils/pagination.ts`. Fix: cap page at `Math.ceil(total / pageSize)` in route handlers and return `{ data: [], pagination: { … , out_of_bounds: true } }` so clients can redirect to last valid page.








---

### Severity summary (Wave S7, 45 findings)

P0 (critical — data loss / silent failure / security): 8 findings (WEB-S7-001 through 008)
P1 (wrong data / significant UX failure / N+1 under load): 22 findings (WEB-S7-009 through 030)
P2 (edge case / minor inconsistency / cosmetic under specific conditions): 15 findings (WEB-S7-031 through 045)

Key patterns: (1) `isError` absent from 4 high-traffic list/detail pages — silent blank screens on any API failure. (2) Hardcoded `$` + `.toFixed(2)` bypassing `formatCurrency()` in 3 pages. (3) No server-side date-format validation on filter inputs (SQLite silently returns NULL). (4) Naive date arithmetic ignores DST in reports and portal timeline sort. (5) `GET /inventory` missing `asyncHandler` — process-crashing unhandled rejection.
### Dashboard Electron audit loop (2026-04-24+)







- [ ] DASH-ELEC-007. **[LOW][SEC] No rate-limit or request-deduplication on IPC invoke calls from renderer** — packages/management/src/preload/index.ts:117-125 — safeInvoke passes through to ipcRenderer.invoke() with no dedup or throttling; a rapid-fire loop calling `management.getStats()` 1000 times will spawn 1000 API requests; fix: add optional debounce/throttle wrapper on hot-path invokes (stats, disk-space polling).



- [ ] DASH-ELEC-010. **[LOW][WIRING] No explicit audit log of IPC calls that modify system state (restart, stop, create-tenant, delete-tenant)** — all of packages/management/src/main/ipc/*.ts — sensitive operations like `service:restart`, `super-admin:delete-tenant` succeed silently without recording in a main-process audit log who (which renderer origin) initiated them; fix: add a per-file audit logger that records timestamp, origin, operation, and result to a rotating audit.log alongside dashboard.log for compliance/forensics.




- [ ] DASH-ELEC-013. **[MED][WIRING] QueryClient staleTime=10s but no explicit refetchInterval or polling strategy in management pages** — packages/management/src/renderer/src/main.tsx:60-68 — TanStack Query is configured but pages use manual setInterval (useInterval hook, useServerHealth setTimeout) instead of useQuery; mixed polling strategies may cause redundant fetches; fix: migrate high-frequency polls (stats, crashes, audit log) to useQuery with refetchInterval so react-query deduplicates and batches requests.


- [ ] DASH-ELEC-015. **[MED][WIRING] No error boundary wrapping individual page content, only top-level and PageErrorBoundary** — packages/management/src/renderer/src/components/layout/DashboardShell.tsx:30-32 — PageErrorBoundary wraps Outlet but a render error in Header, Sidebar, StatusFooter, or Banner components will crash the entire shell; fix: split PageErrorBoundary into smaller boundaries per major layout section (header, sidebar, main, footer).









- [ ] DASH-ELEC-024. **[MED][UI] tailwind.config.ts uses "Inter" font family — brand requires Saved By Zero (logo) + Bebas Neue (display) + Futura Medium (body)** — packages/management/tailwind.config.ts:58 — currently falls back to system UI sans-serif. Fix: load brand fonts (Bebas Neue + Futura Medium + Jost fallback per CLAUDE memory) and update `fontFamily.sans/display/heading`.



- [ ] DASH-ELEC-027. **[MED][UI] LogsPage long list not virtualized** — packages/management/src/renderer/src/pages/LogsPage.tsx — up to 2000 lines render as full DOM nodes; scroll jank on slow machines. Fix: react-window or custom virtualization for log rows.























- [ ] DASH-ELEC-050. **[LOW][SEC] CSP `style-src 'unsafe-inline'` is broader than needed** — packages/management/src/renderer/index.html:23 — Tailwind compiles to static bundle; only Lucide SVG stroke/fill needs inline styles. unsafe-inline allows any injected `<style>` or `style=`, enabling CSS-injection attribute-selector exfil. Fix: nonce-based style-src for prod build.






- [ ] DASH-ELEC-056. **[MED][SEC] No forgot-password / lost-2FA recovery path** — packages/management/src/renderer/src/pages/LoginPage.tsx (entire) — no recovery flow; no recovery codes shown during 2fa-setup; no "forgot 2FA" IPC handler. Operator who loses TOTP device fully locked out. Fix: show recovery codes during 2fa-setup; document CLI-assisted reset path in dashboard.

- [ ] DASH-ELEC-057. **[MED][UI] Admin Tools "step-up TOTP" claim is description-only — no challenge UI** — packages/management/src/renderer/src/pages/AdminToolsPage.tsx:196 — text claims TOTP gating but page only uses `window.confirm()` (lines 74, 124, 153) before destructive actions. Fix: add TOTP input modal before dispatch; verify server enforces independently.











- [ ] DASH-ELEC-068. **[LOW][UI] BackupPage missing download-to-file + upload-from-file** — BackupPage.tsx — no off-box backup path. Fix: `admin:download-backup` IPC (`dialog.showSaveDialog` + `fs.copyFile`); upload via `<input type="file">` + `admin:upload-backup`.











- [ ] DASH-ELEC-079. **[MED][SEC] EXPECTED_FINGERPRINT frozen at module load — cert rotation falls back to unauthenticated** — packages/management/src/main/services/api-client.ts:121-140 — fingerprint computed once via IIFE; after `setup.bat --reset-certs` mismatch returns Error from checkCertFingerprint but `rejectUnauthorized: false` ignores it. Fix: reload fingerprint per-request, or expose `refreshCertPin()` after server restart, or set `rejectUnauthorized: true` with pinned cert as CA.





- [ ] DASH-ELEC-084. **[MED][WIRE] `management:restart-server` and `service:restart` are two uncoordinated paths** — management-api.ts:1676-1680 (REST) + service-control.ts:663-681 (sc.exe/PM2/kill). Both exposed: `getAPI().management.restartServer()` (UpdatesPage) and `getAPI().service.restart()` (ServerControlPage). Fix: pick canonical path; remove or feature-flag the other; ensure mutual exclusion.






- [ ] DASH-ELEC-090. **[MED][UI] All 16 pages statically imported — no code splitting** — packages/management/src/renderer/src/App.tsx:5-18 + vite.config.ts (no manualChunks) — entire SPA in one chunk; main-thread parse blocks open. Fix: `React.lazy(() => import('./pages/FooPage'))` + shared `<Suspense fallback>` around `<Outlet>` in DashboardShell. Lazy at minimum: DiagnosticsPage, AdminToolsPage, AuditLogPage, CrashMonitorPage, UpdatesPage.







- [ ] DASH-ELEC-097. **[HIGH][BUILD] `dev` script never launches Electron + skips preload build** — packages/management/package.json:13 — runs `build:main --watch` and `vite` only; no electron `.`, no preload watch, no main-process auto-restart. Devs must additionally run `dev:electron` (one-shot). Fix: replace `dev` with concurrently launching: `build:main --watch`, `build:preload --watch`, `vite --port 5174`, and `wait-on dist/main/index.js && nodemon --watch dist/main --exec electron .`.

- [ ] DASH-ELEC-098. **[HIGH][BUILD] Zero test infrastructure — no framework, no test files, no CI test step** — packages/management/package.json (no vitest/jest), src/ (0 *.test.*), .github/workflows/ci.yml (no test job). CI only type-checks. Fix: add vitest + @vitest/ui + @testing-library/react + user-event; scripts `"test": "vitest run"` + `"test:watch"`; CI `test` job.

- [ ] DASH-ELEC-099. **[MED][BUILD] No ESLint config — package fully un-linted** — packages/management/ (no .eslintrc*/eslint.config*); no eslint deps; no `lint` script; no CI lint step. Fix: eslint.config.js with @typescript-eslint, eslint-plugin-react, react-hooks, jsx-a11y; `"lint": "eslint src"`; CI lint step.


- [ ] DASH-ELEC-101. **[MED][DEPS] electron pinned to non-LTS 39.8.7** — packages/management/package.json:37 — even-numbered Electron releases are LTS (32, 34, 36); 39 is odd dev/latest with no LTS security backports. As of 2026-04, Electron 36.x is current LTS. Fix: downgrade to `"electron": "^36.0.0"`.

- [ ] DASH-ELEC-102. **[MED][DEPS] `app-builder-bin` pinned to alpha `5.0.0-alpha.10`** — packages/management/package.json:28 — electron-builder internal binary as pre-release; production installers built with unfinished tool. Fix: remove explicit override (let electron-builder pull vetted bin), or pin to latest stable.

- [ ] DASH-ELEC-103. **[MED][BUILD] electron-builder.yml has no `publish` section — auto-update structurally broken** — no publish key + no electron-updater dep. Future auto-update silently produces un-updateable installers. Fix: add `publish: { provider: 'github', owner, repo }`; add `"electron-updater": "^6.0.0"` to deps.



- [ ] DASH-ELEC-106. **[LOW][BUILD] Root `build` excludes management — Electron dashboard never built by CI** — package.json:19 root build does shared/web/server only; CI Build & Type-check runs `tsc --noEmit` for management but not `build`. Broken renderer/preload build undetected until manual package. Fix: append `&& npm run build --workspace=packages/management` to root; add CI step.


- [ ] DASH-ELEC-108. **[LOW][BUILD] No README.md in packages/management/ — build/dev workflow undocumented** — no doc explaining 3 tsconfigs, 2-step dev/dev:electron pattern, or code-signing env vars. Fix: README covering local dev, 3 build targets, code-signing variables, CI jobs.




- [ ] DASH-ELEC-112. **[LOW][TELEM] No structured logging library in main process — plain console.log only** — packages/management/src/main/index.ts:102-104 + management-api.ts + service-control.ts — no levels, no JSON, no correlation IDs; no electron-log/winston/pino. Fix: introduce electron-log (zero-dep) for structured JSON lines `{ level, time, msg }`; serialize objects properly.




- [ ] DASH-ELEC-116. **[LOW][I18N] All 400+ user-facing strings hardcoded English — no i18n framework** — packages/management/src/renderer/src/ entire tree — no i18next/react-intl. Fix: adopt i18next with `en.json` namespace as foundation; literals become `t('key')` calls.

- [ ] DASH-ELEC-117. **[LOW][TELEM] No telemetry opt-out mechanism** — packages/management/ has no telemetry now but no opt-out infrastructure either; any future SDK would be on-by-default. Self-hosted GDPR concern. Fix: add `telemetry_opt_in: false` to platform_config; Settings toggle "Crash reporting & diagnostics"; gate future analytics behind it.














- [ ] DASH-ELEC-131. **[MED][WIRE] No "Revoke All Sessions" action — only per-session revoke** — packages/management/src/renderer/src/pages/SessionsPage.tsx (entire) — `super-admin:revoke-all` IPC handler does not exist. Credential-compromise incident requires one-by-one revoke; with 100s of sessions impractical. Fix: add `ipcMain.handle('super-admin:revoke-all-sessions', ...)` → POST /super-admin/api/sessions/revoke-all; "Revoke All" danger button in SessionsPage with ConfirmDialog.





- [ ] DASH-ELEC-136. **[LOW][UI] No bulk-select checkbox on TenantsPage table** — packages/management/src/renderer/src/pages/TenantsPage.tsx:357-479 — bulk suspend/activate/delete requires per-row clicks; 50+ tenants is friction-heavy. Fix: `<th>` checkbox column; `selectedSlugs: Set<string>`; contextual bulk-action bar with ConfirmDialog routing.














- [ ] DASH-ELEC-150. **[LOW][UI] `@apply` in globals.css component layer drifts from Tailwind tokens** — globals.css:70-97. Fix: remove `.stat-card`; inline as per-component constant.


- [ ] DASH-ELEC-152. **[HIGH][SEC] @xmldom/xmldom ≤0.8.12 — 4 active CVEs in electron-builder transitive** — package-lock.json:3932 — DoS + 3 XML-injection. Dev-only but runs in CI. Fix: `npm audit fix` or root override `{ "@xmldom/xmldom": "^0.9.0" }`.

- [ ] DASH-ELEC-153. **[MED][SEC] postcss <8.5.10 CVE — XSS via unescaped `</style>`** — package-lock.json:4726. Fix: bump `"postcss": "^8.5.10"`.

- [ ] DASH-ELEC-154. **[HIGH][DEPS] `app-builder-bin` 3-way alpha split** — packages/management/package.json:28 declares alpha.10; lockfile resolves alpha.13 + nested alpha.12. Fix: remove explicit override.

- [ ] DASH-ELEC-155. **[MED][DEPS] Renderer runtime deps misclassified as devDependencies** — packages/management/package.json:29-50 — react/react-dom/zustand/react-query/react-router-dom/clsx/date-fns/lucide-react/tailwind-merge/react-hot-toast in devDeps. Fix: move all renderer runtime to `dependencies`.

- [ ] DASH-ELEC-156. **[MED][DEPS] `app-builder-bin` erroneously listed in `dependencies` (prod) in lockfile** — package-lock.json:12535. Fix: remove from `dependencies`.

- [ ] DASH-ELEC-157. **[MED][DEPS] `inflight` + `glob@7` deprecated transitives** — package-lock.json:7620-7624 + 415-419. Fix: track electron-builder release that drops them.

- [ ] DASH-ELEC-158. **[MED][DEPS] `prebuild-install@7.1.3` deprecated — native-addon install vector** — package-lock.json:9368 — pulled by better-sqlite3 + canvas. Fix: update better-sqlite3 to version migrating away.

- [ ] DASH-ELEC-159. **[LOW][DEPS] `boolean@3.2.0` "no longer supported"** — package-lock.json:4570-4577. Fix: monitor electron-builder for removal.

- [ ] DASH-ELEC-160. **[LOW][DEPS] CSP `'unsafe-inline'` for style-src — prod build not verified to strip** — packages/management/src/renderer/index.html:23. Fix: evaluate `vite-plugin-csp` for nonce-based CSP.











- [ ] DASH-ELEC-171. **[LOW][UI] SettingsPage platform-config inputs save silently on blur — no undo** — packages/management/src/renderer/src/pages/SettingsPage.tsx:508-511 — onBlur fires handlePlatformConfigToggle immediately; Tab to next field permanent-writes. Env-settings on same page uses pending/discard pattern. Fix: dirty indicator + explicit Save button per field, OR "Tab to save / Esc to undo" hint. — Fixer-C27 2026-04-25 (PARTIAL — hint + Esc revert): added an amber `role="note"` paragraph under the section heading explaining "saves on blur (Tab or click away). Press Esc before leaving the field to revert." Wired `onKeyDown` on the platform-config text input to handle `Escape` by resetting `e.currentTarget.value = current` and calling `.blur()` (the `next !== current` guard in onBlur then short-circuits, no IPC fires). Dirty indicator + per-field Save button still TODO — would require pending-state ref map mirroring the env-settings UX.













- [ ] DASH-ELEC-184. **[MED][DEBT] `wrapHandler` typed `(...args: any[]) => Promise<any>` — IPC boundary untyped across ~60 handlers** — packages/management/src/main/ipc/management-api.ts:867-870 — silenced by 2 eslint-disables. Fix: typed generic `<T extends unknown[], R>(fn: (event: IpcMainInvokeEvent, ...args: T) => Promise<R>)`.






- [ ] DASH-ELEC-190. **[LOW][WIRE] `handleProtocolUrl` is permanent no-op stub but `bizarrecrm-dashboard:` scheme registered OS-wide** — packages/management/src/main/index.ts:246-269 — macOS `open-url` + Windows `second-instance` invoke dead handler. Fix: complete renderer routing OR remove OS registration until ready. — SKIPPED 2026-04-26: design decision (remove vs implement full routing) needed; not a small fix.



- [ ] DASH-ELEC-193. **[MED][WIRE] No Test Connection for Stripe/Cloudflare/hCaptcha** — packages/management/src/renderer/src/pages/SettingsPage.tsx:40-55. Fix: IPC probes; per-section Test button.
- [ ] DASH-ELEC-201. **[LOW][WIRE] No settingsDeadToggles equivalent — dead platform-config keys live** — SettingsPage.tsx. Fix: server expose `status?: 'coming_soon'`; render badge.
- [ ] DASH-ELEC-220. **[LOW][UI] AuditLogPage filter-by-user is client-side free-text only — server-truncates >200** — AuditLogPage.tsx:29-31, 58-65. Fix: add `username` server-side query param. — Fixer-C26 2026-04-25 (PARTIAL — UX hint only): added `title` tooltip on the text-filter input explaining that it searches the most recent 200 entries client-side, plus an inline amber hint row that appears below the toolbar whenever a textFilter is set AND the loaded batch is at the 200-row limit ("Showing matches in the most recent 200 entries only…"). Server-side `username` query param still TODO — needs server route change.
- [ ] DASH-ELEC-222. **[MED][UI] CrashMonitorPage no grouping — repeated identical errors shown N rows** — CrashMonitorPage.tsx:94-95, 112-121. Fix: `Map<string, {count,...}>` keyed `route+errorMessage.slice(0,120)`; expandable group rows.
- [ ] DASH-ELEC-223. **[LOW][UI] CrashMonitorPage drill-in lacks OS/Node/Electron/build context** — CrashMonitorPage.tsx:331-336 + bridge.ts:58-66. Fix: extend CrashEntry; capture `process.versions` + `app.getVersion()` at crash time.
- [ ] DASH-ELEC-224. **[LOW][UI] WebhookFailuresPanel expand shows `last_error` only — no sent payload** — WebhookFailuresPanel.tsx:213-217 + Row L10-18. Fix: `sent_payload: string | null` truncated 4KB server-side; Payload/Error tab switcher.

- [ ] DASH-ELEC-230. **[MED][WIRE] No idempotency keys on POST mutations** — management-api.ts:1036,1134,1154,1160,1170,1246,1328,1334,1695,1699,1743,1745,1768,1774. Fix: UUID per non-GET as `X-Idempotency-Key`.
- [ ] DASH-ELEC-237. **[MED][WIRE] No tenant plan-change UI — plan locked after creation** — TenantsPage + management-api.ts:1028-1074. Fix: inline plan select + super-admin:update-tenant IPC + server endpoint.
- [ ] DASH-ELEC-238. **[MED][WIRE] No tenant shop-name rename UI — name frozen post-create** — TenantsPage.tsx:385.
- [ ] DASH-ELEC-243. **[LOW][WIRE] Suspend/activate IPC has no `reason` field** — management-api.ts:1047-1058. Fix: schema + reason textarea in ConfirmDialog.
- [ ] DASH-ELEC-245. **[LOW][WIRE] No last_active / suspended_at timestamps in Tenant** — bridge.ts:92-100 + TenantsPage.tsx:23-28.
- [ ] DASH-ELEC-249. **[MED][UI] SetupChecklist invisible in single-tenant mode + can return null entirely** — packages/management/src/renderer/src/components/SetupChecklist.tsx:76,99,212,225. Fix: always render backup + kill-switch items; only skip multi-tenant-specific items.
- [ ] DASH-ELEC-251. **[MED][UI] No Required vs Recommended distinction in SetupChecklist** — packages/management/src/renderer/src/components/SetupChecklist.tsx:11-20. Fix: `tier: 'required' | 'recommended'` field; inline badge.
- [ ] DASH-ELEC-252. **[MED][WIRE] No cert expiry countdown — BannerCertWarning checks presence not validity** — packages/management/src/main/services/api-client.ts:312-322 + BannerCertWarning.tsx:17-37. Fix: parse via `crypto.X509Certificate(pem).validTo`; include `daysUntilExpiry`; banner amber ≤30d, red ≤7d.

- [ ] DASH-ELEC-258. **[LOW][WIRE] EXPECTED_FINGERPRINT pinned once at module load — cert rotation needs app restart** — api-client.ts:121-140. Fix: reloadCertFingerprint() + warning banner on detected mismatch.
- [ ] DASH-ELEC-263. **[LOW][WIRE] No powerMonitor integration — useServerHealth backoff doesn't reset after sleep/wake** — main/index.ts + useServerHealth.ts:37,70,91. Fix: emit IPC on `powerMonitor.on('resume')` → renderer poll() + reset to BASE_INTERVAL.
- [ ] DASH-ELEC-266. **[MED][DEBT] getAuditLog + getSessions return unparameterised `Promise<ApiResponse>`** — bridge.ts:263-264 + AuditLogPage.tsx:36-37 + SessionsPage.tsx:77-78.
- [~] DASH-ELEC-268. **[LOW][DEBT] createTenant + updateBackupSettings bridge params typed `unknown`** — bridge.ts:257,362. _(Fixer-C24 2026-04-25 — partial: `createTenant` now takes `TenantCreatePayload` (new exported interface) and `TenantsPage.tsx:159` no longer needs the `res.data as TenantCreateResult | undefined` cast; unused `TenantCreateResult` import removed. `updateBackupSettings` left — no renderer consumer to pivot.)_
- [ ] DASH-ELEC-269. **[LOW][DEBT] EnvFieldCategory union duplicated** — management-api.ts:145 + bridge.ts:203. — Fixer-C26 2026-04-25 (PARTIAL — drift-defense only): cross-reference comment added on both type declarations explaining that Electron main and renderer compile to separate bundles with no `packages/management/src/shared/` folder yet, so the union is intentionally duplicated; instructs future contributors to edit BOTH files in the same commit and points at the eventual cleanup path. Real dedup still requires creating a shared types file referenced by both tsconfigs.
- [ ] DASH-ELEC-273. **[MED][DEBT] safeInvoke returns `Promise<unknown>` — entire ElectronAPI surface erases return types** — preload/index.ts:117. Fix: typed IPC channel map or `safeInvoke<T>` overload.




---

## Web Audit Wave-WEB-2026-04-24 Search S8 — RBAC + backend route gaps













































- [ ] WEB-S8-045. **`settings.routes.ts` `GET /settings/users` is gated with `adminOnly` but the returned row shape includes `role` and `is_active` for all users — acceptable. However `PUT /settings/users/:id` (line 962) validates the new `role` against `VALID_ROLES` allowlist but also accepts `permissions` as a raw JSON blob from `req.body`, allowing any admin to write arbitrary permission overrides without schema validation or audit logging.** `packages/server/src/routes/settings.routes.ts` line 962+. Fix: parse and validate `permissions` against `VALID_PERMISSIONS` allowlist keys before storing; write an audit row for every permission change identical to the role-change audit.

---

### Severity summary (Wave S8, 45 findings)

P0 (critical — privilege escalation / unauthenticated mutation / process crash): 5 findings (WEB-S8-001, WEB-S8-004, WEB-S8-006, WEB-S8-010, WEB-S8-042)
P1 (missing role gate on sensitive data / IDOR / missing rate limit on expensive operations): 27 findings (WEB-S8-002 through WEB-S8-009, WEB-S8-011 through WEB-S8-017, WEB-S8-019 through WEB-S8-022, WEB-S8-024 through WEB-S8-031, WEB-S8-034 through WEB-S8-040, WEB-S8-043 through WEB-S8-044)
P2 (information disclosure / minor inconsistency / defense-in-depth): 13 findings (WEB-S8-018, WEB-S8-023, WEB-S8-028, WEB-S8-029, WEB-S8-032 through WEB-S8-033, WEB-S8-041, WEB-S8-045)

Key patterns: (1) Systemic absence of `requirePermission` on read-only inventory, catalog, and employee endpoints — cost prices, supplier data, and employee revenue visible to any role. (2) `import.routes.ts` status/history endpoints lack admin gate matching their sibling start/cancel endpoints. (3) `settings.routes.ts` uses raw `async (req, res)` throughout — ~15 handlers missing `asyncHandler`, creating unhandled-rejection crash vectors. (4) `catalog.routes.ts` import and live-search endpoints are ungated mutations that any authenticated user can call. (5) Tenant-isolation fallback to `'default'` slug in import checkpoints risks cross-tenant data exposure in multi-tenant mode.
### Wave-Loop Finder-I run 2026-04-24 — api/routing/hooks/stores deeper-pass












- [ ] WEB-FI-012. **[MED] `usePosKeyboardShortcuts` swallows F-keys with `event.preventDefault()` — handlers are read via `handlersRef.current` but if a parent's handler closure captured stale state and is updated only on commit, the F-key fires the previous-render value.** `usePosKeyboardShortcuts.ts:46-74`. Documenting handlers as "must read fresh state via refs/store" is a footgun. Either pass fresh args via a callback registry or document this prominently in the hook header.
  <!-- meta: scope=web/hooks; files=packages/web/src/hooks/usePosKeyboardShortcuts.ts:46-74; fix=document-stale-closure-risk+example-using-store -->










- [~] WEB-FI-022. **[LOW] No error-reporting hook (Sentry/Datadog/etc.) on any of the three boundary classes — `componentDidCatch` only `console.error`s, so prod render crashes are invisible without a user-supplied screenshot.** `ErrorBoundary.tsx:16-18`, `PageErrorBoundary.tsx:51-53`, `main.tsx:64-67`. Even a Vite env-flagged DSN (`import.meta.env.VITE_SENTRY_DSN`) would surface render errors to ops.
  <!-- meta: scope=web/components,web/root; files=packages/web/src/components/ErrorBoundary.tsx:16,packages/web/src/components/shared/PageErrorBoundary.tsx:51,packages/web/src/main.tsx:64; fix=add-import.meta.env.VITE_SENTRY_DSN-init+report-on-componentDidCatch -->





### Wave-Loop Finder-G run 2026-04-24 — auth/dashboard/settings deeper-pass









- [~] WEB-FG-009 (PARTIAL). **[MED] `PaymentLinksPage` create form has `<input type="number" step="0.01">` for amount but the `Customer ID` and `Invoice ID` fields are `type="text"` with no validation — operator pasting a slug or non-existent ID gets a generic backend error.** *(PARTIAL Fixer-OOO 2026-04-25 — added `parseStrictId` helper that rejects anything with non-digit characters via explicit toast (`'12abc'` no longer silently coerces to `12`), wired into `handleCreate`. ID inputs now ship `inputMode="numeric"` + `pattern="\d*"` + `aria-label` so mobile keyboards open the numeric pad. Expiry-date past-day check added. Server-side existence check + cents-only amount typing still pending.)*
  <!-- meta: scope=web/billing/forms; files=packages/web/src/pages/billing/PaymentLinksPage.tsx:104-117,172-200; fix=type=number+min=1+step=1+pattern=integer+server-side-existence-check -->







- [~] WEB-FG-016 (partial — LoginPage firstTimeSetup form done; ResetPasswordPage pending). **[MED] `LoginPage` first-time-setup form has `noValidate` + min-8 password but no `aria-invalid` / `aria-describedby` linking error messages to inputs.** `LoginPage.tsx:380-467,549-575`. When `setError('Password must be at least 8 characters')` fires the message is rendered in a sibling `<p>` with no programmatic association. Same a11y gap as FE-014 but specifically on the first surface every shop owner sees. Screen-reader users get the title but not the field-level cause. — Fixer-B17 2026-04-25: error block in firstTimeSetup form now carries `id="setup-form-error"` + `role="alert"` + `aria-live="polite"`; username/email/password inputs all set `aria-invalid={!!error}` + `aria-describedby="setup-form-error"` when an error is present. SR users now hear the error on submit and the field's invalid state is programmatically associated. ResetPasswordPage still TODO.
  <!-- meta: scope=web/auth/a11y; files=packages/web/src/pages/auth/LoginPage.tsx:380-467,549-575,packages/web/src/pages/auth/ResetPasswordPage.tsx:117-156; fix=wire-aria-invalid+aria-describedby=field-error-id+role=alert-on-error-block -->



- [ ] WEB-FG-019. **[LOW] `SettingsPage` 3464-line file is loaded as a single chunk on `/settings/*` route entry — the user landing on `/settings/general` pulls the entire 3.4 k-line file (and its sub-tabs DangerZone, BlockChyp, RepairPricing, NotificationTemplates, Audit) before paint.** Each tab is a logical lazy-load boundary (DangerZoneTab + BlockChypSettings + RepairPricingTab are 484/380/992 lines each — huge). React.lazy each tab and Suspense the panel.
  <!-- meta: scope=web/settings/perf; files=packages/web/src/pages/settings/SettingsPage.tsx:1-3464; fix=React.lazy-each-tab-and-Suspense-fallback-skeleton -->

- [~] WEB-FG-020 (partial — 4 of 5 pages). **[LOW] `team/*` pages use `text-gray-*` exclusively (no `dark:` partner) — `MyQueuePage.tsx:64-92,98-156`, `GoalsPage.tsx:113-180`, `ShiftSchedulePage.tsx:174-378`, `PerformanceReviewsPage.tsx:88-119`, `TeamLeaderboardPage.tsx`.** Fixer-C13 2026-04-25 added `dark:` variants on headers / cards / table chrome / hover-row partner for `MyQueuePage`, `GoalsPage`, `TeamLeaderboardPage`, and `PerformanceReviewsPage` (sidebar + role list). `ShiftSchedulePage.tsx` still has no `dark:` variants (schedule grid + per-shift cells need a denser pass — deferred).
  <!-- meta: scope=web/team/dark-mode; files=packages/web/src/pages/team/MyQueuePage.tsx,packages/web/src/pages/team/GoalsPage.tsx,packages/web/src/pages/team/ShiftSchedulePage.tsx,packages/web/src/pages/team/PerformanceReviewsPage.tsx; fix=codemod-text-gray-N+bg-white+border-to-surface-tokens-with-dark:variants -->





### Wave-Loop Finder-H run 2026-04-24 — pos/catalog/inventory deeper-pass
















- [~] WEB-FH-016. **[MED] Catalog import has no idempotency + double-click on "Add to Inventory" creates duplicate SKUs.** `CatalogPage.tsx:290-298` `importMutation` is a bare `catalogApi.importItem(id, { markup_pct })` POST. Modal "Add to Inventory" button (line 694-697) only disabled by `importMutation.isPending` — slow server returns mid-double-click create two inventory rows with identical SKUs from the supplier catalog. Inventory table has no UNIQUE on (source, external_id). Same gap as FH-001 but on the supplier-catalog -> inventory flow. — Fixer-B3 2026-04-25 (PARTIAL — client only): added a per-id timestamp ref so a second click within 1500 ms for the same catalog id is dropped before `mutate()`. Server-side dedupe / DB UNIQUE constraint still needed (the actual fix); this just removes the React-batched `isPending` race window where two synchronous clicks slipped through.
  <!-- meta: scope=web/pages/catalog; files=packages/web/src/pages/catalog/CatalogPage.tsx:290-298,694-697; fix=add-X-Idempotency-Key-header+disable-button-on-mouse-down-not-mutation-pending -->


- [ ] WEB-FH-018. **[MED] Estimate->Ticket convert drops attachments + photos — files attached to the estimate never reach the ticket.** `EstimateDetailPage.convertMut` line 74-83 calls `estimateApi.convert(id)`, server route at `estimates.routes.ts:704-867` does NOT touch any `attachments`/`photos` table — a grep for `attachment|photo|file` in `estimates.routes.ts` returns empty. If the customer uploaded device-condition photos against the estimate (via `/portal/estimates/:id` or back-office), those rows have estimate_id FK and stay there; new ticket row has no `attachments` link. Tech opens the new ticket, sees no photos, asks customer to re-upload.
  <!-- meta: scope=server/estimates+web/pages/estimates; files=packages/server/src/routes/estimates.routes.ts:704-867,packages/web/src/pages/estimates/EstimateDetailPage.tsx:74-83; fix=on-convert-also-INSERT-into-attachments(ticket_id,...)-SELECT-FROM-attachments-WHERE-estimate_id+repoint-photos -->








### Wave-Loop Finder-K run 2026-04-24 — tickets/leads/marketing/comms deeper-pass



- [~] WEB-FK-003. **[HIGH] LoanersPage has NO deposit field — deposit/hold collection is entirely missing from the loaner flow, even though the return-condition dropdown offers "damaged" and "missing parts".** `LoanersPage.tsx:55-95`: ReturnDialog only collects `condition_in` + `damageNotes`. There's no place to record a deposit at hand-out, no auto-release when condition_in='good', and no auto-charge when condition_in='damaged'/'missing'. Shop hands over a $1200 iPad as a loaner, customer returns it cracked, condition_in='damaged' is logged — but no money moved. The damage cost is the shop's. iPad-shop industry standard is hold-on-card + auto-release. PARTIAL FIXED-by-Fixer-A18 2026-04-25 (frontend-only) — `ReturnDialog` now reveals an amber `role="alert"` damage-charge panel whenever condition_in is `damaged` or `missing`. Cashier enters a USD amount that gets appended to the existing `notes` payload as `Damage charge owed: $X.XX` (server-schema-safe, no API change) and a long-duration toast on success commands the cashier `"Collect $X.XX damage charge from customer"` so a damaged return cannot silently close out without staff seeing the dollar figure. True hold-on-card + auto-release still requires server `deposit_amount`/`deposit_payment_id` columns + BlockChyp pre-auth wiring (out of frontend-only scope) — kept open as `[~]` so the backend half stays tracked.
  <!-- meta: scope=web/pages/loaners+server/loaners; files=packages/web/src/pages/loaners/LoanersPage.tsx,packages/server/src/routes/loaners.routes.ts; fix=add-deposit_amount+deposit_method+deposit_payment_id-fields-on-loan-out+ReturnDialog-shows-deposit-disposition(release/forfeit/partial)+ledger-rows -->







- [~] WEB-FK-010. **[MED] ReportsPage activeTab + dateRange held only in `useState` — every refresh / shared link kicks the user back to "sales / last_30".** `ReportsPage.tsx:1144-1147`. No `useSearchParams` integration. Manager drills into `tickets` tab with `2026-01-01..2026-03-31`, hits F5 to re-pull fresh data, lands back on `sales / last_30`. No way to copy-paste a permalink to a colleague ("here's our Q1 ticket count"). Same drift on `subTab`/`groupBy`/`compare` (lines 163, 896-897). Shareable analytics is the table-stakes feature for reports pages and it's not here. — Fixer-B10 2026-04-25: activeTab now persists to `?tab=` (validated against TABS); dateRange/subTab/groupBy/compare still TODO.
  <!-- meta: scope=web/pages/reports; files=packages/web/src/pages/reports/ReportsPage.tsx:1143-1171,896-897,163; fix=replace-useState-with-useSearchParams-bound-state(tab,from,to,preset,group_by,compare)+initialise-from-URL-on-mount -->

- [~] WEB-FK-011. **[MED] TvDisplayPage uses HTTP polling at `refetchInterval: 30000`, NOT a WebSocket — the spec line in scope (WS reconnect storm) is misdescribed but the polling path has its own waste: 24/7 lobby TV makes 2880 polls/day per tenant per location.** `TvDisplayPage.tsx:58-62`. No `Visibility API` pause when the TV cabinet is asleep, no exponential back-off on 5xx (next interval still 30s after a 503). Multiply by N tenants × M locations × always-on TVs and that's measurable load. WebSocket migration would be cheaper AND would let the stale "Auto-refreshes every 30 seconds" footer go away. As-is, change footer text to "live" only when polling actually succeeded recently.
  <!-- meta: scope=web/pages/tv; files=packages/web/src/pages/tv/TvDisplayPage.tsx:58-62,127-132; fix=switch-to-WS-with-1s-2s-4s-8s-back-off-cap-30s+pause-when-document.hidden+show-error-banner-if-no-data-for>2x-interval -->

- [ ] WEB-FK-012. **[MED] PrintPage receipt header reads `store_config.store_name/phone/address` from a SINGLE store — multi-location tenant prints the WRONG location's footer on every receipt.** `PrintPage.tsx:219-221,476-478,784-786,907,966`: `settingsApi.getConfig()` returns ONE flat key/value map; there's no `location_id` partitioning of the config keys. Ticket from Location B (downtown) printed on Location A (north) printer prints with Location A's address + phone. Customers walking into the wrong store with an issue. Tickets table has `location_id` (migration 136 per FK-003 context), but the print surface does not look it up.
  <!-- meta: scope=web/pages/print+server/settings; files=packages/web/src/pages/print/PrintPage.tsx:219-221,476-478,784-786,907,963-967,packages/server/src/routes/settings.routes.ts; fix=server-store_config-becomes-per-location+settingsApi.getConfig({location_id})+PrintPage-passes-ticket.location_id -->







### Wave-Loop Finder-L run 2026-04-24 — cross-page integration + dead-feature audit















- [ ] WEB-FL-015. **[MED] LandingPage covered in inline-styles — 60+ `style={{...}}` literals on JSX, no Tailwind, full HTML-mockup leak.** `pages/landing/LandingPage.tsx` lines 33, 34, 101-126, 275, 293, 313, 481 etc. — `padding`, `fontSize`, `background`, `color`, `borderRadius`, `boxShadow` all inline. Diverges from the rest of the app (Tailwind utility-first), defeats Tailwind's PurgeCSS for landing-page styles, harder to dark-mode. Pattern: HTML mockup was hand-pasted as JSX without conversion.
  <!-- meta: scope=web/pages/landing; files=packages/web/src/pages/landing/LandingPage.tsx; fix=convert-style={{}}-to-className=""-Tailwind-utilities+kill-arbitrary-rgba()-with-bg-black/50-tokens -->









- [~] WEB-FL-024. **[LOW] Repeated pattern: `e: any` in onError handlers across 119 occurrences of `as any` in web/src/pages.** Including ShrinkagePage:90, MassLabelPrintPage:55, BinLocationsPage:98, InventoryCreatePage:44, etc. Common `e?.response?.data?.message` chain rebuilt at every callsite with `any`. Should consolidate into shared `formatApiError(err: unknown)` already present in `utils/apiError.ts` — confirm it's used everywhere onError fires. — partial (Fixer-C9 2026-04-25): consolidated 4 callsites in inventory pages onto shared `formatApiError(e: unknown)` — `ShrinkagePage`, `MassLabelPrintPage`, `BinLocationsPage`, plus `InventoryCreatePage` (FL-023). Remaining `e: any` chains across other pages still pending — leave open until a wider sweep eliminates the pattern repo-wide.
  <!-- meta: scope=web/pages/inventory+utils; files=packages/web/src/utils/apiError.ts,packages/web/src/pages/inventory/ShrinkagePage.tsx:90,packages/web/src/pages/inventory/MassLabelPrintPage.tsx:55,packages/web/src/pages/inventory/BinLocationsPage.tsx:98; fix=replace-e:any+chain-with-formatApiError(e)-from-utils -->


### Wave-Loop Finder-J run 2026-04-24 — secrets/PII/audit-trail/cache









- [ ] WEB-FJ-009. **[MED] `customerApi.exportData` GDPR/CCPA export blob is generated client-side as plain JSON Blob — no Content-Disposition `filename*=UTF-8''` encoding + no encryption-at-rest option for the customer.** `pages/customers/CustomerDetailPage.tsx:252-270`. Dumps full `exportPayload` into `Blob([JSON.stringify(...)], 'application/json')` and `a.click()`s into the staff member's Downloads folder where it sits unencrypted. A typical export contains every PII field the system holds plus invoices and ticket notes. Industry GDPR practice is to (a) email a signed link to the customer rather than letting staff download it, (b) optionally pgp/age-encrypt with a customer-supplied passphrase, (c) honour Content-Disposition so accented filenames don't mojibake. None of those are present.
  <!-- meta: scope=web/pages/customers; files=packages/web/src/pages/customers/CustomerDetailPage.tsx:252-270; fix=server-builds-export+emails-signed-time-limited-link-direct-to-customer+staff-only-triggers+remove-client-Blob-path -->




- [ ] WEB-FJ-013. **[MED] `signupApi.createShop` POSTs admin password as a top-level JSON body field with no client-side hash + no breached-password check — works against `/api/v1/signup`.** `pages/signup/SignupPage.tsx:213-219` + `api/endpoints.ts:1234`. Modern signup flows prefilter against haveibeenpwned k-anonymity API client-side ("this password has been seen in 273k breaches") before submitting. Server-side bcrypt is fine but doesn't help the user who picks `password123`. Combined with the only client validation being `password.length < 8` (line 190), the system actively encourages weak passwords. Industry baseline is HIBP range query + zxcvbn strength meter.
  <!-- meta: scope=web/pages/signup; files=packages/web/src/pages/signup/SignupPage.tsx:190,213-219; fix=add-haveibeenpwned-range-API-check+block-on-Pwned-or-zxcvbn-score-<-3+show-strength-meter -->









### Wave-Loop Finder-N run 2026-04-24 — web-server contract drift





- [ ] WEB-FN-005. **[MED] Pagination param drift — server reads `pagesize` (most routes), `per_page` (gift-cards, loaners), and `limit` (catalog/teamChat/super-admin/inventory.low-stock), and within a single endpoint the request key is `pagesize` while the response key is `per_page`.** Examples: `inventoryApi.list` sends `pagesize` to `GET /inventory` (server reads `pagesize` ✓ but RESPONSE pagination key is `per_page` — inventory.routes.ts:127); `voiceApi.calls` sends `pagesize` (server reads `pagesize` ✓, response `per_page` — voice.routes.ts:181,218); `giftCardApi.list` sends `per_page` (server reads `per_page` ✓ — giftCards.routes.ts:122,145); `loanerApi.list` sends `per_page` (server reads `per_page` ✓). The query-vs-response asymmetry within a single endpoint plus the cross-endpoint inconsistency makes a generic `usePaginatedQuery` hook impossible — each caller hand-rolls. Industry baseline: settle on one name in both directions and add a server alias for the legacy.
  <!-- meta: scope=web/api+server/routes+server/utils/pagination; files=packages/web/src/api/endpoints.ts:103,310,590,981,1021,packages/server/src/utils/pagination.ts ↔ packages/server/src/routes/inventory.routes.ts:65,127,packages/server/src/routes/voice.routes.ts:181,218,packages/server/src/routes/giftCards.routes.ts:122,145; fix=server-accept-both-pagesize+per_page-(via-parsePageSize-OR)+settle-response-on-per_page+document-canonical-pagination-shape-in-CONTRACTS.md -->


- [~] WEB-FN-007. **[MED] WebSocket event-name drift: web `useWebSocket.ts` subscribes to legacy literal `'sms_received'` AND `WS_EVENTS.SMS_RECEIVED='sms:received'`; server only ever broadcasts the latter, so the literal handler is dead code AND the inline comment explaining its existence is stale.** Server: sms.routes.ts:1164 `broadcast(WS_EVENTS.SMS_RECEIVED, ...)` (resolves to `'sms:received'`). Web: useWebSocket.ts:78-85 has an inline comment claiming "SMS routes currently broadcast with literal `sms_received`" — wrong; server uses the colon form. The legacy entry will never fire. Same risk: server sends `'sms:status_updated'` literal (sms.routes.ts:1331) which is NOT in `WS_EVENTS` shared constants — web subscribes via literal at useWebSocket.ts:94 — string drift could break silently if either side ever changes. — Fixer-B12 2026-04-25: deleted the dead `'sms_received'` snake_case handler + stale inline comment in useWebSocket.ts; canonical `WS_EVENTS.SMS_RECEIVED` is now the only subscription. Remaining work: promote `'sms:status_updated'` to `WS_EVENTS` shared constant — left for follow-up since it touches packages/shared and server sms.routes.ts.
  <!-- meta: scope=web/hooks+shared/constants+server/routes/sms; files=packages/web/src/hooks/useWebSocket.ts:78-97,packages/shared/src/constants/events.ts:19 ↔ packages/server/src/routes/sms.routes.ts:1164,1331; fix=delete-legacy-'sms_received'-handler+add-SMS_STATUS_UPDATED-to-WS_EVENTS-and-replace-literal-on-both-sides -->




- [~] WEB-FN-011. **[LOW] Dead route family: `POST /api/v1/estimates/:id/sign` and the public `/public/api/v1/estimate-sign/*` endpoints (estimateSign.routes.ts) have no web caller — `grep -r "estimate-sign\|estimateSign" packages/web/src` returns zero hits.** The route file exports `authedRouter` (mount under `/estimates/:id`) and `publicRouter` (mount under `/public/api/v1/estimate-sign`) per the file header at estimateSign.routes.ts:1-18, but neither `endpoints.ts:estimateApi` nor any page imports the URL. The customer e-sign flow is wired on iOS/Android, not web. Either remove the public route from the web bundle's allow-list (CSP/CORS) or add the missing web caller to surface signing in the desktop estimate-detail view. _(Fixer-C6 2026-04-25: documented as **mobile-only** in `endpoints.ts` above the `estimateApi` block so a future audit can grep the rationale; CSP/CORS scoping + a web `<EstimateSignDialog>` are still open if desktop staff signing is wanted.)_
  <!-- meta: scope=server/routes+web; files=packages/server/src/routes/estimateSign.routes.ts:1-60 ↔ no-web-caller; fix=document-as-mobile-only-OR-add-estimateSignApi-wrapper-and-EstimateSignDialog-component -->

- [~] WEB-FN-012. **[LOW] `posApi` has no wrapper for `POST /pos/sales` (pos.routes.ts:916), `POST /pos/return` (pos.routes.ts:2471), or `GET/POST/PUT /pos/workstations*` (pos.routes.ts:2668-2740) — orphan server routes.** All four are guarded by `requirePermission` and look load-bearing — especially `/pos/return` for cash refunds and the workstations family for the multi-station kiosk flow described in `unified-pos`. Web pages either hand-roll axios calls for these or the features are silently unreachable. `/pos/sales` looks like a separate non-checkout-with-ticket path (legacy?) — confirm before linking.
  PARTIAL FIXED-by-Fixer-C12 2026-04-25 — typed wrappers added: `posApi.sales`, `posApi.return` (both with mandatory idempotency-key headers mirroring `checkoutWithTicket`), `posApi.listWorkstations`, `posApi.createWorkstation`, `posApi.updateWorkstation`. Page-level adoption + `setDefault` workstation route + sales-vs-checkoutWithTicket deprecation audit still TODO.
  <!-- meta: scope=web/api+server/routes/pos; files=packages/web/src/api/endpoints.ts:597-623 ↔ packages/server/src/routes/pos.routes.ts:916,2471,2668-2740; fix=add-posApi.return+posApi.workstations.{list,create,update,setDefault}+audit-pos.sales-vs-checkoutWithTicket-then-deprecate-one -->

- [~] WEB-FN-013. **[LOW] `voiceApi.calls` response leaks `recording_local_path` — server's filesystem path (e.g. `/var/data/tenants/foo/recordings/...`) is exposed to the wire.** voice.routes.ts:218 returns `data: { calls, pagination }` with `calls` essentially being a `SELECT *`. Web `VoiceCall` interface at endpoints.ts:570-577 declares `recording_local_path: string | null` — the type ACKNOWLEDGES the leak. Knowing the on-disk layout helps a path-traversal probe and reveals which tenants share storage by inspecting the slug segment. Server should project only `recording_url` on the wire and keep `recording_local_path` server-side. Web type should drop the field so a future audit surfaces if the leak reappears. _(Fixer-C6 2026-04-25: web side dropped — `recording_local_path` removed from `VoiceCall` (endpoints.ts) + the local `CallLog` interface in CommunicationPage; `hasRecording()` + the row "Recorded" badge + the audio `src` in CommunicationPage all switched to `recording_url`-only. Server-side projection trim is still open.)_
  <!-- meta: scope=server/routes/voice+web/api; files=packages/web/src/api/endpoints.ts:570-577 ↔ packages/server/src/routes/voice.routes.ts:218; fix=server-projects-only-recording_url+strip-recording_local_path-from-SELECT-OR-redact-to-filename-only -->


### Wave-Loop Finder-O run 2026-04-24 — concurrency + real-time + multi-tab









- [~] WEB-FO-009. **[MED] Header.tsx `fetchUnreadCount` / `fetchSmsUnreadCount` use raw axios (not React Query) and have no AbortController.** Fixer-B14 2026-04-25 — partial: added an `isMountedRef` guard that bails before `setUnreadCount` / `setSmsUnreadCount` / `setNotifications` / `setNotifLoading` if the Header has unmounted. No more setState-on-unmounted warnings + no more stale resolution overwriting fresh post-login state. Full AbortController-through-axios still pending — requires `notificationApi.unreadCount` / `smsApi.unreadCount` / `notificationApi.list` to accept a `signal` (endpoint-wrapper change).
  <!-- meta: scope=web/components/layout; files=packages/web/src/components/layout/Header.tsx:80-150; fix=convert-fetchUnreadCount-to-useQuery-or-add-AbortController+abort-on-unmount -->




- [ ] WEB-FO-013. **[MED] No navigation guard on in-flight mutations — clicking a sidebar link mid-mutation lets the request keep firing into a destroyed page; rollback `onError` toasts then surface on an unrelated route.** `pages/tickets/TicketDetailPage.tsx`, `KanbanBoard.tsx`, `TicketSidebar.tsx`. React Query's `useMutation` doesn't auto-cancel on unmount. The user drags a kanban card to "Repaired", clicks Customers, mutation 500s 2 s later → red toast saying "Failed to update ticket status" appears on /customers and the user has no idea which ticket. Fix: pass `signal` from a per-component AbortController into the mutation, abort in cleanup; or use React Router blocker on protected mutations.
  <!-- meta: scope=web/pages/tickets+web/pages/invoices; files=packages/web/src/pages/tickets/KanbanBoard.tsx,packages/web/src/pages/tickets/TicketDetailPage.tsx; fix=mutation-bound-AbortController-aborted-on-unmount+rollback-cache-locally-not-via-toast -->







- [ ] WEB-FO-020. **[LOW] No IndexedDB usage anywhere — all client-side cache is in-memory React Query (lost on reload) or 5 MB localStorage. POS receipts, ticket photos, big inventory lists never use IndexedDB even where it would obviously help.** Searched whole repo. Combined with the missing service worker, an "open invoice on a flaky connection" reload always re-fetches everything. Fix (long-term): persist React Query cache to IndexedDB via `@tanstack/query-persist-client-idb` for read-heavy lists; keep localStorage only for the small per-tenant prefs.
  <!-- meta: scope=web/main+web/api; files=packages/web/src/main.tsx:95-103; fix=add-tanstack-query-persist-client-idb-for-list-queries+keep-localStorage-for-prefs -->


### Wave-Loop Finder-M run 2026-04-24 — dead-code + duplicates + cleanup









- [ ] WEB-FM-009. **[MED] React.memo on `TicketRow`, `NotificationItem`, `UrgencyDot`, `SkeletonRow` without comparison fn + props include callbacks/objects -> memo is a NO-OP.** `pages/tickets/TicketListPage.tsx:330` `TicketRow` accepts 8 callbacks (`onNavigate`, `onToggleSelect`, `onToggleExpand`, `onChangeStatus`, `onPin`, `onPrint`, `onDelete`, `onAddNote`, `onSendSms`) plus a `ticket` object and `statuses` array — every parent render makes new identities, so `memo()` re-renders every row anyway. Same pattern at `components/layout/Header.tsx:521` `NotificationItem({notification, onClick})` — fresh `onClick` per render. Either pass a stable `id` + receive callbacks via context, or wrap with `useCallback`s in the parent (currently absent), or drop the `memo`.
  <!-- SKIP (todofixes426 2026-04-26): fix requires useCallback at every parent call-site for all 8 callbacks, or ticket context refactor. Not a small change — deferred. -->
  <!-- meta: scope=web/pages/tickets+components/layout; files=packages/web/src/pages/tickets/TicketListPage.tsx:78,330,690,packages/web/src/components/layout/Header.tsx:521; fix=stabilize-callbacks-with-useCallback-in-parent+pass-statuses-via-context-OR-remove-memo -->

- [ ] WEB-FM-010. **[MED] Three separate `ErrorBoundary` class implementations across the app — divergent recovery UX.** `src/main.tsx:57` has a private `ErrorBoundary` (white card + reload button), `src/components/ErrorBoundary.tsx:6` has another `ErrorBoundary` exported and imported by `App.tsx:9` (different fallback markup), and `src/components/shared/PageErrorBoundary.tsx` adds a third with the chunk-reload sentinel logic. The three trees nest (`<ErrorBoundary><AppShell>...<PageErrorBoundary/></AppShell></ErrorBoundary>`), each catching at a different level, with non-uniform "Retry" CTAs and reset behavior. A user who lands on a route-render crash sees the App-level fallback; a render crash inside `<main>` triggers PageErrorBoundary. Pick one canonical class with composable fallback render-prop; delete the other two.
  <!-- meta: scope=web/main+components; files=packages/web/src/main.tsx:57,packages/web/src/components/ErrorBoundary.tsx:6,packages/web/src/components/shared/PageErrorBoundary.tsx; fix=consolidate-into-one-ErrorBoundary-with-composable-fallback-prop+delete-the-other-two-after-migrating-callers -->

- [ ] WEB-FM-011. **[MED] `SettingsPage.tsx` is 3,464 LOC — the largest file in the repo by 1,200+ lines and impossible to code-review.** `pages/settings/SettingsPage.tsx` declares 60+ inline tab components in one default export. Other settings tabs (`AutomationsTab`, `BillingTab`, `RepairPricingTab`, `NotificationTemplatesTab`, etc.) are already extracted; the remaining inline tabs (`InvoiceSettings` block, `CustomerGroupRecord` table, role permissions, dead-toggles bulk panel) should follow the same pattern. Compile times suffer; HMR forces a full re-render of every tab on any edit.
  <!-- meta: scope=web/pages/settings; files=packages/web/src/pages/settings/SettingsPage.tsx; fix=extract-each-inline-tab-into-pages/settings/tabs/*.tsx-and-import-as-already-done-for-AutomationsTab+BillingTab -->

- [ ] WEB-FM-012. **[MED] Six pages exceed 1,500 LOC + endpoints.ts at 1,287 LOC — page-as-monolith pattern blocks tree-shake / parallel TS check.** After SettingsPage (3,464): `CommunicationPage.tsx` (2,223), `CustomerDetailPage.tsx` (2,142), `DashboardPage.tsx` (2,112), `TicketWizard.tsx` (2,008), `TicketListPage.tsx` (1,817), `InventoryListPage.tsx` (1,780), `RepairsTab.tsx` (1,448), `ReportsPage.tsx` (1,396). Each contains 5-15 tightly-coupled inline subcomponents. The single `endpoints.ts` causes any tiny API tweak to invalidate the cached type-build for all pages — split per-domain (auth, billing, tickets, inventory, ...).
  <!-- meta: scope=web/pages+api; files=packages/web/src/pages/communications/CommunicationPage.tsx,packages/web/src/pages/customers/CustomerDetailPage.tsx,packages/web/src/pages/dashboard/DashboardPage.tsx,packages/web/src/pages/tickets/TicketWizard.tsx,packages/web/src/pages/tickets/TicketListPage.tsx,packages/web/src/pages/inventory/InventoryListPage.tsx,packages/web/src/api/endpoints.ts; fix=extract-inline-subcomponents-into-co-located-./components/+split-endpoints.ts-by-domain -->










### Wave-Loop Finder-Q run 2026-04-24 — visual polish + brand consistency












- [ ] WEB-FQ-012. **[MED] Drop-shadow scale mixed: `shadow-sm` buttons next to `shadow-md`/`shadow-xl`/`shadow-2xl` modals with no semantic ladder.** `customers/CustomerListPage.tsx:577` Add CTA `shadow-sm`; line 804 modal `shadow-xl`; `CustomerDetailPage.tsx:565` modal `shadow-xl`; `leads/LeadListPage.tsx:126` modal `shadow-2xl`; `leads/CalendarPage.tsx:93,204` modals `shadow-2xl`. So "modal" is sometimes shadow-xl and sometimes shadow-2xl on adjacent flows. Should pick one elevation token per role.
  <!-- meta: scope=web/pages; files=packages/web/src/pages/customers/CustomerListPage.tsx:577,804,packages/web/src/pages/customers/CustomerDetailPage.tsx:565,packages/web/src/pages/leads/LeadListPage.tsx:126,packages/web/src/pages/leads/CalendarPage.tsx:93,204; fix=elevation-tokens(button=shadow-sm,popover=shadow-md,modal=shadow-xl,toast=shadow-2xl)+codemod -->


- [ ] WEB-FQ-014. **[MED] No EmptyState illustration — empty lists render plain `<p class="text-sm text-surface-400">No X yet</p>`, no icon, no CTA, on 18+ pages.** `NotificationTemplatesTab.tsx:280`, `CustomerDetailPage.tsx:980,993`, `SettingsPage.tsx:552`, `MembershipSettings.tsx:496`, `ReceiptSettings.tsx:187`, `AuditLogsTab.tsx:119`, `DeviceTemplatesPage.tsx:232,413`, `TicketNotes.tsx:302`, `RepairPricingTab.tsx:301,547`, `TicketDevices.tsx:86,519` — all single-line text. Shared `EmptyState` component exists (`shared/EmptyState.tsx`, used 5× in SettingsPage) but adoption is partial. New users see flat "no data" everywhere instead of guided illustrations.
  <!-- meta: scope=web/pages; files=packages/web/src/components/shared/EmptyState.tsx,packages/web/src/pages/settings/NotificationTemplatesTab.tsx:280,packages/web/src/pages/customers/CustomerDetailPage.tsx:980,packages/web/src/pages/tickets/TicketNotes.tsx:302; fix=expand-EmptyState-to-take-icon+title+description+action-prop+codemod-inline-`<p>No X yet</p>`-instances -->

- [ ] WEB-FQ-015. **[MED] Native browser `<select>` used 25× in pages while shared CommandPalette + custom dropdowns coexist — different a11y, hover, selection visuals.** `CustomerListPage.tsx:609,627`, `CustomerCreatePage.tsx:236`, all use raw `<select>` with `rounded-md` + Tailwind classes. Other surfaces (e.g. CustomerListPage:926 column-picker) hand-roll a custom `<div role="menu">` dropdown. Selects don't open to themed listbox; dropdowns don't follow native keyboard rules. No shared `<Select>` primitive. Date-picker landscape similar — 14 native `<input type="date">` only, no library; 0 themed pickers. (Memory says brand surface ramp drift.)
  <!-- meta: scope=web/pages+components; files=packages/web/src/pages/customers/CustomerCreatePage.tsx:236,packages/web/src/pages/customers/CustomerListPage.tsx:609,627,926; fix=add-shared/Select.tsx+shared/DatePicker.tsx-as-headless-radix/HeadlessUI-wrappers+codemod-25-native-selects -->

- [ ] WEB-FQ-016. **[MED] Status-color usage uses raw amber/blue/green/red Tailwind colors with NO dark variants in 30+ spots — light-only badges.** `CustomerListPage.tsx:464` rounded-full badge; `DashboardPage.tsx:284,314,355,738,776` `text-amber-600 dark:text-amber-400` (dark variants present here) but `:1338,1873` only `text-red-500` / `text-green-600` (no dark:). Customer detail page `border-purple-200 text-purple-700 bg-purple-50 dark:border-purple-500/30 dark:text-purple-300 dark:bg-purple-500/10` (long), but other pages omit the `dark:` arm. Inconsistent dark-mode coverage = washed-out badges in dark mode.
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








- [ ] WEB-FX-008. **[MED] PinModal is the only well-built modal — has `role="dialog"` + `aria-modal` + `aria-labelledby="pin-modal-title"` + close-button `aria-label="Close"`. Its pattern should be the shared `<Modal>` primitive everyone migrates to.** `components/shared/PinModal.tsx:133-146`. Currently each modal hand-rolls its own backdrop + close button, often forgetting all four ARIA hooks (see WEB-FX-003).
  <!-- meta: scope=web/components; files=packages/web/src/components/shared/PinModal.tsx:133-146,packages/web/src/components/shared/ConfirmDialog.tsx; fix=extract-shared/Modal.tsx-from-PinModal-pattern+add-focus-trap+ESC+codemod-46-bare-overlays-to-use-it -->






### Wave-Loop Finder-V run 2026-04-24 — error swallow + console.log + native modals









- [~] WEB-FV-009 (partial — console upgrade only). **[LOW] `SpotlightCoach.tsx:372,412,420` use `console.warn(...)` for tutorial-handler failures.** Fixer-C4 2026-04-25 — upgraded all three callsites from `console.warn('SpotlightCoach: …', err)` to `console.error('[spotlight] <tag>', err)` (`tutorial-complete` for the two complete-handler callsites + `dismissAllTutorials` for the third) so dev-tools default error filter surfaces them and a future Sentry shim can split breadcrumbs by tag. Sentry/captureException wiring still TODO (no SDK initialized in `main.tsx` yet) — entry rephrased to track only the SDK piece.
  <!-- meta: scope=web/components/onboarding; files=packages/web/src/components/onboarding/SpotlightCoach.tsx:372,412,420; fix=add-Sentry.captureException-and-eslint-rule-no-console-warn-in-src -->


- [~] WEB-FV-011. **[LOW] Inconsistent silent-catch error commentary — 30+ callsites have varied comments (`/* ignore */`, `/* swallow */`, `/* non-fatal */`, `/* storage unavailable */`, `/* best-effort */`) but same "do nothing" semantic — no shared `safeStorage` / `safeRun` helper.** `stores/confirmStore.ts:35` `/* best-effort */`, `tutorialFlows.ts:226` `/* storage unavailable — still proceed */`, `PrintPreviewModal.tsx:38,45,48` no comment. Standardize on a single helper `safeRun(() => ..., { tags: { ... } })` that logs to Sentry as breadcrumb + returns gracefully — eliminates 30+ ad-hoc try/catch trees and gives consistent ops visibility. (Fixer-C11 2026-04-25: helper authored at `packages/web/src/utils/safeRun.ts` exporting `safeRun` + `safeRunAsync` with provider-agnostic Sentry breadcrumb fallback; codemod of the 30 bare-catch sites still pending — landing the helper first so future fixers can adopt without inventing yet another shape.)
  <!-- meta: scope=web/stores+components; files=packages/web/src/stores/confirmStore.ts:35,packages/web/src/components/onboarding/tutorialFlows.ts:226,230,247,packages/web/src/components/shared/PrintPreviewModal.tsx:38,45,48; fix=author-utils/safeRun.ts+codemod-30-bare-catch-blocks-to-use-it -->

### Wave-Loop Finder-AC run 2026-04-25 — animations + reduced-motion





- [ ] WEB-FAC-005. **[MED] Tooltips implemented as native `title="..."` attributes on 168 elements — no delay-in/out, OS-rendered (breaks brand), flickers on rapid mouse movement across icon clusters.** `Header.tsx:284,294,313`, `Sidebar.tsx:352`, `ImpersonationBanner.tsx:86`, etc. Native title shows after ~700ms with no fade, dismisses on movement, ignores keyboard focus (a11y gap). Build a shared `<Tooltip>` with `delayShow={300}` `delayHide={150}` + 150ms fade-in/out, focus-visible support, motion-reduce fallback to instant show. Replace all 168 `title=` callsites via codemod.
  <!-- meta: scope=web/components; files=packages/web/src/components/layout/Header.tsx:284,294,313,packages/web/src/components/layout/Sidebar.tsx:352,packages/web/src/components/ImpersonationBanner.tsx:86; fix=author-shared/Tooltip.tsx+@radix-ui/react-tooltip+delay-300/150+motion-reduce:transition-none+codemod-title-attr -->

- [ ] WEB-FAC-006. **[MED] No page-route transitions — `<Routes>` in `App.tsx:351,369` swap routes synchronously with zero crossfade, causing "white flash" between heavy pages (Dashboard -> CustomerList -> TicketDetail).** React Router v6 unmounts old route immediately. Wrap `<Routes location={location} />` in `framer-motion AnimatePresence` keyed on `location.pathname` with 150ms fade or short slide. Critical when Suspense fallback (Skeleton) chains multiple paint phases — currently looks broken instead of intentional.
  <!-- meta: scope=web/App; files=packages/web/src/App.tsx:351,369; fix=AnimatePresence+motion.div-key=pathname+150ms-fade+motion-reduce:duration-0 -->





### Wave-Loop Finder-AD run 2026-04-25 — refetch storms + WS backoff






- [~] WEB-FAD-006. **[MED] `KanbanBoard.tsx:131` polls `tickets-kanban` every 30s while WS already invalidates `['tickets']` on TICKET_CREATED/UPDATED/STATUS_CHANGED/NOTE_ADDED/DELETED — no prefix-match because the kanban key is `['tickets-kanban']` (hyphen) not `['tickets', 'kanban']`.** WS map at `useWebSocket.ts:57-77` invalidates `['tickets']` on 5 ticket events but the kanban query key is `['tickets-kanban']` so WS DOESN'T touch it. Either rename to `['tickets', 'kanban']` so WS prefix-match catches it, OR drop the 30s poll and explicitly add `tickets-kanban` to the invalidation map. Same pattern likely repeats for `[tv-display]` (`TvDisplayPage.tsx:61` 30s poll, no WS link) and `[my-queue]` (`MyQueuePage.tsx:58`). <!-- PARTIAL Fixer-B24 2026-04-25: KanbanBoard renamed `['tickets-kanban']` → `['tickets', 'kanban']` (all 6 sites: useQuery + cancelQueries + getQueryData + setQueryData ×2 + invalidateQueries). WS prefix-match on `['tickets']` now catches kanban automatically. Loosened poll 30s → 60s (kept as fallback for WS-down). `[tv-display]` + `[my-queue]` siblings still pending. -->
  <!-- meta: scope=web/pages/tickets+tv+team; files=packages/web/src/pages/tickets/KanbanBoard.tsx:128-132,packages/web/src/pages/tv/TvDisplayPage.tsx:58-62,packages/web/src/pages/team/MyQueuePage.tsx:58; fix=normalize-queryKeys-to-['tickets','kanban']/['tickets','tv']/['tickets','my-queue']+drop-explicit-refetchInterval+rely-on-WS-prefix-invalidation -->





### Wave-Loop Finder-AE run 2026-04-25 — tenant + role isolation

- [~] WEB-FAE-001 (PARTIAL). **[HIGH] `PermissionBoundary` component (`components/shared/PermissionBoundary.tsx:13`) is defined but has ZERO callsites in the entire `packages/web/src` tree — gating done by ad-hoc `user?.role === 'admin'` literals scattered across 9+ files instead.** Fixer-II 2026-04-25 — adopted `PermissionBoundary` for the Settings dropdown entry in `components/layout/Header.tsx:439` (replaced `(user?.role === 'admin' || user?.role === 'manager') &&` with `<PermissionBoundary roles={['admin', 'manager']}>`). Component is no longer orphan. Remaining ad-hoc role checks pending a follow-up sweep: `Sidebar.tsx:147` (used in nav-filter `.map` → boolean, harder to wrap as JSX — wants a `useHasRole(roles)` hook), `DashboardPage.tsx:1626,1684`, `DangerZoneTab.tsx:35`, `BulkSmsModal.tsx:18`, `SettingsPage.tsx:1656,1761`, `ReportsPage.tsx:632`. PARTIAL FIXED-by-Fixer-A20 2026-04-25: authored `packages/web/src/hooks/useHasRole.ts` (boolean counterpart to `<PermissionBoundary>`, same auth-store source-of-truth, supports `string | string[]`). Adopted in two of the listed sites: `DashboardPage.tsx` (`showFinancials = useHasRole(['admin', 'manager'])`, replaces `role === 'admin' || role === 'manager'`) + `DangerZoneTab.tsx` (`isAdmin = useHasRole('admin')`, drops the local `useAuthStore` import + `user?.role === 'admin'` literal). Hook is now available so the remaining `.map` filters in Sidebar + `disabled`-style boolean gates can adopt it without contortions.
  <!-- meta: scope=web/components/shared+pages; files=packages/web/src/components/shared/PermissionBoundary.tsx:13,packages/web/src/components/layout/Header.tsx:439,packages/web/src/components/layout/Sidebar.tsx:147,packages/web/src/pages/dashboard/DashboardPage.tsx:1626,1684,packages/web/src/pages/settings/DangerZoneTab.tsx:35; fix=replace-ad-hoc-role-checks-with-PermissionBoundary+author-useHasRole-hook+single-source-truth -->


- [~] WEB-FAE-003 (PARTIAL). **[HIGH] `localStorage` keys are NOT user/tenant-scoped — survive logout and bleed across accounts on the same browser.** Fixer-II 2026-04-25 — fixed the highest-PII key (`recent_views`, the only one carrying customer/ticket labels): exported `recentViewsKey(userId)` from `components/layout/Sidebar.tsx` returning `recent_views:u${userId}`, switched the Sidebar reader + both writers (`pages/customers/CustomerDetailPage.tsx:120-137`, `pages/tickets/TicketDetailPage.tsx:362`) to the namespaced key, and added a module-level `bizarre-crm:auth-cleared` listener in `Sidebar.tsx` that wipes the legacy unscoped `recent_views` key plus every `recent_views:*` entry on logout/switchUser/forced-logout. The User type has no `tenant_id` (`packages/shared/src/types/employee.ts:1`), so per-`user.id` is the strongest scope expressible client-side; cross-tenant follows for free since one user.id can't span tenants. Still pending the same treatment: `useDismissible.ts:34` per-banner flags, `uiStore.ts:39` `sidebarCollapsed`, `ImpersonationBanner.tsx:17` IMPERSONATION_KEY (lower-PII but same isolation concern). PARTIAL FIXED-by-Fixer-A20 2026-04-25: extended the `bizarre-crm:auth-cleared` sweep in `packages/web/src/main.tsx` to wipe every `tutorial.*` localStorage key (covers `tutorial.all.dismissed` + `tutorial.<flowId>.dismissed`); a previous user's "skip all" decision no longer suppresses onboarding for the next sign-in on a shared kiosk PC. Same listener already nukes `recent_views` + `draft_*` so this co-locates the tutorial-flag cleanup with the existing PII purge.
  <!-- meta: scope=web/components+hooks+stores; files=packages/web/src/components/layout/Sidebar.tsx:259,packages/web/src/components/onboarding/tutorialFlows.ts:225,packages/web/src/hooks/useDismissible.ts:34,packages/web/src/components/ImpersonationBanner.tsx:17; fix=add-auth-cleared-listener-purges-non-allowlist-keys+OR-namespace-keys-by-tenant_id+user_id -->



- [ ] WEB-FAE-006. **[MED] Hardcoded role lists drift from server's canonical `shared/constants/permissions` — comment at `Sidebar.tsx:141` literally says "shared ROLE_PERMISSIONS grants manager every permission except a handful" but the client doesn't import that constant; it just reproduces `userRole === 'admin' || userRole === 'manager'` inline.** `Header.tsx:439` checks `'admin' || 'manager'`, `DashboardPage.tsx:1626` checks `'admin' || 'manager'`, `DangerZoneTab.tsx:35` checks only `'admin'`, `BulkSmsModal.tsx:18` says "backend enforces req.user.role === 'admin'" (only one consistent), `SettingsPage.tsx:1762` lists `'manager'`+`['Tickets', 'Customers', 'POS']`+`'technician'` — all hand-rolled. If server adds an `'owner'` or `'kiosk'` role, every callsite drifts silently. Import `ROLE_PERMISSIONS` from `@bizarre-crm/shared` and derive role gates from a single map.
  <!-- meta: scope=web/components+pages; files=packages/web/src/components/layout/Header.tsx:439,packages/web/src/components/layout/Sidebar.tsx:147,packages/web/src/pages/settings/SettingsPage.tsx:1761-1762,packages/web/src/pages/dashboard/DashboardPage.tsx:1626; fix=import-ROLE_PERMISSIONS-from-shared+derive-isAdminOrManager-from-canonical-map+add-eslint-rule-no-hardcoded-role-string-literal -->





---

## Web UI/UX Audit (WEB-UIUX) — 2026-05-04

Full-app usability audit: 16 lenses × ~194 files × 4 tiers. Findings are sequenced
WEB-UIUX-1..NNN, grouped by scope. Severity: blocker / major / minor / nit.
Lenses: L1-Speed L2-Hierarchy L3-NoDuplicates L4-Components L5-Workflow L6-States
L7-Forms L8-Feedback L9-Visual L10-Dark L11-Responsive L12-A11y L13-Animation
L14-Copy L15-Perf L16-Trust.

### Cross-Cutting (systemic patterns)

- [ ] WEB-UIUX-1. **[MAJOR] Zero adoption of canonical `<Button>` component.** Only 1 file imports `components/shared/Button.tsx` vs 1240+ raw `<button` tags across the entire web app. Every page hand-rolls its own class strings, producing inconsistent padding (py-1.5/py-2/py-2.5), border-radius (rounded-md/rounded-lg/rounded-full), disabled opacity (50/60/40), and missing focus rings. L4, L9, L12.
  <!-- meta: scope=web/all; files=all pages; fix=incremental-migration-to-Button-component -->

- [ ] WEB-UIUX-2. **[MAJOR] Zero semantic color token adoption.** 456 `red-*`, 294 `green-*`, 335 `amber-*`, 127 `blue-*`, 54 `teal-*`, 35 `purple-*` raw Tailwind colors used. The `error/success/warning/info` semantic ramps in tailwind.config.ts have ZERO imports anywhere. Every color change requires a global grep. L9.
  <!-- meta: scope=web/all; files=tailwind.config.ts:95-146 defines tokens; 0 callsites -->

- [ ] WEB-UIUX-3. **[MAJOR] 67 `bg-white` without `dark:` partner.** These elements render blinding white on dark mode. Concentrated in inventory sub-pages (8 files), team pages (4 files), and customer-facing pages (3 files). L10.
  <!-- meta: scope=web/all; fix=add-dark:bg-surface-800-or-dark:bg-surface-900 -->

- [ ] WEB-UIUX-4. **[MAJOR] 109+ icon-only buttons missing `aria-label`.** Buttons containing only an SVG icon (X, Plus, Printer, ChevronLeft, etc.) lack accessible names. Screen readers announce "button" with no context. L12.
  <!-- meta: scope=web/all; fix=add-aria-label-to-icon-only-buttons -->

- [ ] WEB-UIUX-5. **[MAJOR] Shared `<EmptyState>` component has ZERO imports.** The canonical component exists but no page uses it. Each page invents its own empty state with inconsistent styling, icons, and CTAs. L4, L6.
  <!-- meta: scope=web/all; files=components/shared/EmptyState.tsx; fix=migrate-existing-empty-states -->

- [ ] WEB-UIUX-6. **[MINOR] 54 raw `teal-*` color references without semantic alias.** Teal is used as a de facto brand accent (POS checkout, ticket actions, dashboard KPIs) but has no entry in the design system. Future brand changes require 54-site grep. L9.
  <!-- meta: scope=web/all; fix=define-semantic-alias-or-migrate-to-primary -->

- [ ] WEB-UIUX-7. **[MINOR] 15 `disabled:opacity-60` + 2 `disabled:opacity-40` vs canonical `disabled:opacity-50`.** Three different disabled visual treatments coexist. L4, L9.
  <!-- meta: scope=web/all; fix=normalize-to-opacity-50 -->

- [ ] WEB-UIUX-8. **[MINOR] Shared `<Skeleton>` component has only 2 imports.** Most pages use custom inline skeleton markup or plain "Loading..." text. L4, L6.
  <!-- meta: scope=web/all; files=components/shared/Skeleton.tsx; fix=migrate-loading-states -->

- [ ] WEB-UIUX-9. **[MINOR] Modals duplicate Esc-to-close logic individually.** 35+ files each implement their own `useEffect` + `keydown` + `Escape` handler. No shared `useEscClose` hook or `<Modal>` wrapper. L3, L4.
  <!-- meta: scope=web/all; fix=extract-useEscClose-hook-or-Modal-wrapper -->

- [ ] WEB-UIUX-10. **[MINOR] `disabled:pointer-events-none` on buttons prevents tooltip display.** Users cannot learn WHY a button is disabled. Found in LeadListPage, EstimateListPage, and 10+ other files. L12, L8.
  <!-- meta: scope=web/all; fix=remove-pointer-events-none-keep-cursor-not-allowed -->

- [ ] WEB-UIUX-11. **[MINOR] 5+ pages use raw `Date.toLocaleDateString()`/`toLocaleString()` instead of `formatDate`/`formatDateTime` helpers.** ReviewsPage, StocktakePage, SerialNumbersPage, ShrinkagePage, AbcAnalysisPage, InventoryDetailPage. L3, L9.
  <!-- meta: scope=web/all; fix=replace-with-formatDate-formatDateTime -->

- [ ] WEB-UIUX-12. **[MAJOR] `prefers-reduced-motion` not respected anywhere.** `animate-pulse`, `animate-spin`, transition animations run unconditionally. Users with vestibular disorders cannot suppress motion. L13, L12.
  <!-- meta: scope=web/all; fix=add-motion-reduce:animate-none-or-@media-prefers-reduced-motion -->

- [ ] WEB-UIUX-13. **[MINOR] `formatTicketId` duplicated across 5 files.** TicketListPage, TicketDetailPage, KanbanBoard, TicketActions, TicketSidebar all re-declare the same helper. L3, L15.
  <!-- meta: scope=web/pages/tickets; fix=extract-to-utils/ticket.ts -->

- [ ] WEB-UIUX-14. **[MINOR] `getScoreColor` duplicated across 3 files.** LeadListPage, LeadDetailPage, LeadPipelinePage. L3.
  <!-- meta: scope=web/pages/leads; fix=extract-to-utils/leadScore.ts -->

### Shell (AppShell, Sidebar, Header, CommandPalette)

- [ ] WEB-UIUX-15. **[MAJOR] CommandPalette PAGE_JUMPS contain 6 dead routes.** `/dashboard`, `/marketing`, `/campaigns`, `/referrals`, `/team`, `/billing` do not exist in App.tsx. Users who select these navigate to a blank/404 page. L5, L16.
  `packages/web/src/components/shared/CommandPalette.tsx`
  <!-- meta: fix=remove-dead-routes-or-add-matching-redirects -->

- [ ] WEB-UIUX-16. **[MAJOR] CommandPalette results list missing `role="listbox"` / `role="option"`.** Screen reader users cannot navigate results. L12.
  `packages/web/src/components/shared/CommandPalette.tsx`
  <!-- meta: fix=add-aria-roles -->

- [ ] WEB-UIUX-17. **[MINOR] Sidebar: Referrals + Gift Cards share identical Gift icon.** Users cannot distinguish between them visually. L9.
  `packages/web/src/components/layout/Sidebar.tsx:83,104`
  <!-- meta: fix=use-Ticket-or-CreditCard-icon-for-GiftCards -->

- [ ] WEB-UIUX-18. **[MINOR] Sidebar: All 4 Billing items (Invoices, Expenses, Subscriptions, Payment Links) use identical FileText icon.** L9.
  `packages/web/src/components/layout/Sidebar.tsx:128-131`
  <!-- meta: fix=differentiate-icons -->

- [ ] WEB-UIUX-19. **[MINOR] Header SwitchUserModal uses off-palette `teal-600`/`teal-400`.** L9.
  `packages/web/src/components/layout/Header.tsx:711,720`
  <!-- meta: fix=migrate-to-primary-600 -->

- [ ] WEB-UIUX-20. **[MINOR] Header notification badge uses raw `bg-red-500`, SMS badge uses raw `bg-green-500`.** Should use semantic `error-500` / `success-500`. L9.
  `packages/web/src/components/layout/Header.tsx:379,355`
  <!-- meta: fix=migrate-to-semantic-tokens -->

- [ ] WEB-UIUX-21. **[MINOR] ShortcutReferenceCard advertises F6="Returns" in POS — unwired stub.** Also omits F6=CommandPalette from Global section. L14, L16.
  `packages/web/src/components/onboarding/ShortcutReferenceCard.tsx:49`
  <!-- meta: fix=remove-F6-Returns-add-F6-CommandPalette -->

- [ ] WEB-UIUX-22. **[MINOR] ShortcutReferenceCard: missing focus trap despite `aria-modal="true"`.** L12.
  `packages/web/src/components/onboarding/ShortcutReferenceCard.tsx`
  <!-- meta: fix=add-focus-trap -->

- [ ] WEB-UIUX-23. **[MINOR] PrintPreviewModal / QuickSmsModal / UpgradeModal: all missing focus trap and focus-restore.** L12.
  `packages/web/src/components/shared/PrintPreviewModal.tsx`, `QuickSmsModal.tsx`, `UpgradeModal.tsx`
  <!-- meta: fix=add-focus-trap-and-focus-restore -->

- [ ] WEB-UIUX-24. **[MINOR] Breadcrumb uses off-palette `text-teal-500 dark:text-teal-400`.** L9.
  `packages/web/src/components/shared/Breadcrumb.tsx:35`
  <!-- meta: fix=migrate-to-primary-600 -->

- [ ] WEB-UIUX-25. **[MINOR] FormError uses raw `red-*` instead of `error-*` semantic tokens.** L9.
  `packages/web/src/components/shared/FormError.tsx:41,54,63`
  <!-- meta: fix=migrate-to-error-ramp -->

- [ ] WEB-UIUX-26. **[NIT] PinModal backdrop does NOT close on click (unlike all other modals).** Inconsistent dismiss pattern. L4.
  `packages/web/src/components/shared/PinModal.tsx`
  <!-- meta: fix=add-onBackdropClick-or-document-why -->

- [ ] WEB-UIUX-27. **[NIT] globals.css `.card` class uses zinc palette (`#e4e4e7`, `#18181b`) instead of surface CSS vars.** L9.
  `packages/web/src/styles/globals.css`
  <!-- meta: fix=migrate-to-surface-vars -->

- [ ] WEB-UIUX-28. **[NIT] globals.css `.btn-*` class system (lines 272-331) duplicates the React `<Button>` component.** Two competing button systems. L3.
  `packages/web/src/styles/globals.css:272-331`
  <!-- meta: fix=deprecate-btn-classes-after-Button-migration -->

### Tier 1: Dashboard + POS

- [ ] WEB-UIUX-29. **[BLOCKER] LeftPanel RepairRow quantity column hardcoded to `1`.** Always displays "1" regardless of actual quantity — misinforms cashier about line-item count. L6.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:577`
  <!-- meta: fix=render-item.quantity-or-remove-column -->

- [ ] WEB-UIUX-30. **[MAJOR] Hardcoded `$` in 30+ places across POS (LeftPanel, CheckoutModal, SuccessScreen).** Breaks for non-USD tenants. `formatCurrency` exists but is used inconsistently. L9, L14, L16.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:587,621,624,642...`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:441,446,451,455,473,623,661,667`
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:340,345`
  <!-- meta: fix=replace-dollar-literals-with-formatCurrency -->

- [ ] WEB-UIUX-31. **[MAJOR] "Order All" button rendered 3 times for same supplier in DashboardPage MissingPartsCard.** Reduces scannability. L3.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:339,375,466`
  <!-- meta: fix=keep-one-CTA-per-supplier -->

- [ ] WEB-UIUX-32. **[MAJOR] WidgetCustomizeModal has no focus trap.** Keyboard user can tab out into page behind. L12.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:1288`
  <!-- meta: fix=add-focus-trap -->

- [ ] WEB-UIUX-33. **[MAJOR] Clickable div rows (NeedsAttentionCard) not keyboard-focusable.** Uses `div onClick` + cursor-pointer without `role="button"` / `tabIndex="0"` / `onKeyDown`. L12.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:903,941,972`
  <!-- meta: fix=convert-to-button-or-add-role-tabindex-keydown -->

- [ ] WEB-UIUX-34. **[MAJOR] LeftPanel controlled number inputs coerce on every keystroke.** Typing "50." immediately parses to "50", eating trailing decimals. Affects labor price, product price, discount amount inputs. L7.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:592,743,938`
  <!-- meta: fix=use-uncontrolled-input-with-onBlur-commit-pattern -->

- [ ] WEB-UIUX-35. **[MAJOR] POS "Create Ticket" and "Checkout" buttons have reversed action hierarchy.** "Create Ticket" is the filled primary CTA (teal-600), while "Checkout" (the actual conversion action) is outlined secondary. L2.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:457-488`
  <!-- meta: fix=swap-visual-hierarchy-checkout=primary -->

- [ ] WEB-UIUX-36. **[MAJOR] POS Checkout CTA uses `bg-teal-600` — non-brand, non-semantic color.** Should be `bg-primary-600 text-primary-950`. L2, L9.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:707`, `BottomActions.tsx:459`
  <!-- meta: fix=migrate-to-primary -->

- [ ] WEB-UIUX-37. **[MAJOR] Bottom action buttons (Cancel/OpenDrawer/CreateTicket/Checkout) all missing `focus-visible:ring`.** No visual focus indicator for keyboard users, violating WCAG 2.4.7. L12.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:425,438,457,482`
  <!-- meta: fix=add-focus-visible:ring-2 -->

- [ ] WEB-UIUX-38. **[MAJOR] CashModal has no focus trap.** Unlike CheckoutModal which traps Tab. L12.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:58-114`
  <!-- meta: fix=add-focus-trap -->

- [ ] WEB-UIUX-39. **[MINOR] DashboardPage KpiCard uses clickable `div` instead of `<a>`.** Not keyboard-navigable. L12.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:182-184`
  <!-- meta: fix=use-Link-or-a-element -->

- [ ] WEB-UIUX-40. **[MINOR] DashboardPage InventoryValueWidget is clickable div, not keyboard-accessible.** L12.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:1631`
  <!-- meta: fix=convert-to-button-or-link -->

- [ ] WEB-UIUX-41. **[MINOR] CheckoutModal payment method grid is `grid-cols-4` but only 3 methods exist.** Leaves visual gap. L9.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:529`
  <!-- meta: fix=change-to-grid-cols-3 -->

- [ ] WEB-UIUX-42. **[MINOR] CheckoutModal split-payment `<select>` missing `aria-label`.** L12.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:563`
  <!-- meta: fix=add-aria-label -->

- [ ] WEB-UIUX-43. **[MINOR] DiscountEditor does not submit on Enter key.** Inconsistent with other POS inputs that support Enter-to-submit. L7.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:921-979`
  <!-- meta: fix=add-onKeyDown-Enter-handler -->

- [ ] WEB-UIUX-44. **[MINOR] DashboardPage fires 12 queries simultaneously on mount (AdminOrManagerDashboard).** Jitter only affects refetch, not initial load. Consider staggering or using Suspense boundaries. L15.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:1830-1914`
  <!-- meta: fix=stagger-initial-queries-or-add-suspense -->

- [ ] WEB-UIUX-45. **[MINOR] Scan flash `setTimeout` not cleaned up on unmount.** Can cause state-update-on-unmounted-component warning. L15.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:157-158`
  <!-- meta: fix=clearTimeout-in-cleanup -->

- [ ] WEB-UIUX-46. **[MINOR] CheckoutModal membership upsell button uses dynamic `backgroundColor` with always `text-white`.** If tier color is light (yellow), text becomes invisible. L9, L12.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:483-484`
  <!-- meta: fix=compute-contrast-and-use-dark-or-light-text -->

- [ ] WEB-UIUX-47. **[NIT] Cart empty state mentions "scan a barcode" — confusing if no scanner connected.** L14.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:1057`

- [ ] WEB-UIUX-48. **[NIT] BottomActions cancel confirm message doesn't mention customer will also be cleared.** L14.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:299-300`

### Tier 1: Tickets + Customers

- [ ] WEB-UIUX-49. **[MAJOR] `window.prompt()` used for device price editing.** Blocking, unstyled, no dark mode, broken on iOS PWA. InlinePriceEditor exists in same codebase. L1, L7, L9.
  `packages/web/src/pages/tickets/TicketDevices.tsx:822-828,926-930`
  <!-- meta: fix=replace-with-InlinePriceEditor-component -->

- [ ] WEB-UIUX-50. **[MAJOR] TicketListPage row hover dropdown (`hidden group-hover:block`) unreachable on touch/keyboard.** L1, L11, L12.
  `packages/web/src/pages/tickets/TicketListPage.tsx:560-578`
  <!-- meta: fix=use-click-toggled-dropdown -->

- [ ] WEB-UIUX-51. **[MAJOR] KanbanBoard HTML5 drag-and-drop does not work on mobile.** Touch users cannot change ticket status via kanban. L11, L5.
  `packages/web/src/pages/tickets/KanbanBoard.tsx`
  <!-- meta: fix=add-dnd-kit-or-tap-to-move-fallback -->

- [ ] WEB-UIUX-52. **[MAJOR] StatusDropdown + SavedFiltersDropdown have no keyboard accessibility.** No Escape, no arrow-key nav, no `role="listbox"`, no `aria-expanded`. L12.
  `packages/web/src/pages/tickets/TicketListPage.tsx:95-156,201`
  <!-- meta: fix=add-keyboard-nav-and-aria -->

- [ ] WEB-UIUX-53. **[MAJOR] Parts search "Add" buttons are `opacity-0 group-hover:opacity-100` — invisible to keyboard users.** L12, L1.
  `packages/web/src/pages/tickets/TicketDevices.tsx:558-563,579,609,986-1012`
  <!-- meta: fix=add-focus-visible:opacity-100 -->

- [ ] WEB-UIUX-54. **[MAJOR] Photo delete button uses `hidden group-hover:flex` — unreachable on touch/keyboard.** L11, L12.
  `packages/web/src/pages/tickets/TicketDevices.tsx:1070-1072`
  <!-- meta: fix=make-visible-or-add-long-press-affordance -->

- [ ] WEB-UIUX-55. **[MAJOR] TicketSidebar warranty countdown uses `created_at` not warranty start date.** Incorrect warranty days calculation. L5, L16.
  `packages/web/src/pages/tickets/TicketSidebar.tsx:544`
  <!-- meta: fix=use-warranty-activation-or-completion-date -->

- [ ] WEB-UIUX-56. **[MAJOR] CustomerCreatePage has no dirty-state guard.** Navigating away silently discards 15+ fields of data. L5, L7, L16.
  `packages/web/src/pages/customers/CustomerCreatePage.tsx`
  <!-- meta: fix=add-beforeunload-or-confirm-on-navigate -->

- [ ] WEB-UIUX-57. **[MAJOR] CustomerDetailPage header 5 action buttons overflow on narrow screens.** L11, L2.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:398-438`
  <!-- meta: fix=collapse-infrequent-actions-into-More-dropdown -->

- [ ] WEB-UIUX-58. **[MINOR] TicketListPage delete confirm says "cannot be undone" but action IS undoable (5s window).** Copy contradicts behavior. L14, L16.
  `packages/web/src/pages/tickets/TicketListPage.tsx:1898`
  <!-- meta: fix=update-message-to-mention-undo-window -->

- [ ] WEB-UIUX-59. **[MINOR] KanbanBoard loading state is plain text, not skeleton.** L6, L9.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:264-269`
  <!-- meta: fix=add-skeleton-columns -->

- [ ] WEB-UIUX-60. **[MINOR] Quick Note/SMS inputs lack `aria-label`.** L12.
  `packages/web/src/pages/tickets/TicketListPage.tsx:636-664`
  <!-- meta: fix=add-aria-label -->

- [ ] WEB-UIUX-61. **[MINOR] TicketNotes textarea missing accessible name.** L12.
  `packages/web/src/pages/tickets/TicketNotes.tsx:282-287`
  <!-- meta: fix=add-aria-label -->

- [ ] WEB-UIUX-62. **[MINOR] TicketSidebar assign dropdown has no Escape-to-close.** L12.
  `packages/web/src/pages/tickets/TicketSidebar.tsx:571-608`
  <!-- meta: fix=add-Escape-handler -->

- [ ] WEB-UIUX-63. **[MINOR] CustomerCreatePage Cancel navigates `navigate(-1)` — may leave the app.** L5.
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:550`
  <!-- meta: fix=fallback-to-navigate('/customers') -->

- [ ] WEB-UIUX-64. **[MINOR] CustomerDetailPage loading skeleton has no BackButton/Breadcrumb.** User stuck during long loads. L6, L1.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:303-305`
  <!-- meta: fix=render-Breadcrumb-outside-loading-guard -->

- [ ] WEB-UIUX-65. **[MINOR] MembershipCard uses `$${price.toFixed(2)}` instead of `formatCurrency`.** L9, L14.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:972`
  <!-- meta: fix=use-formatCurrency -->

- [ ] WEB-UIUX-66. **[MINOR] TicketListPage has no explicit `isError` handler.** Failed API call shows stale data or empty state with no error indication. L6.
  `packages/web/src/pages/tickets/TicketListPage.tsx`
  <!-- meta: fix=add-isError-fallback -->

- [ ] WEB-UIUX-67. **[MINOR] TicketListPage status filter `<select>` is `hidden sm:block` — mobile users cannot filter by individual status.** L11.
  `packages/web/src/pages/tickets/TicketListPage.tsx:1476`
  <!-- meta: fix=add-mobile-filter-mechanism -->

- [ ] WEB-UIUX-68. **[NIT] TicketActions renders both Breadcrumb and ArrowLeft back button to same `/tickets` target.** L3.
  `packages/web/src/pages/tickets/TicketActions.tsx:250-263`

- [ ] WEB-UIUX-69. **[NIT] QC sign-off button visible on closed/cancelled tickets.** L2, L5.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:591-597`

### Tier 1: Invoices + Inventory + Comms + CashRegister

- [ ] WEB-UIUX-70. **[MAJOR] InvoiceDetailPage uses `window.confirm()` for overpayment guard.** Every other confirm uses ConfirmDialog. L4, L9.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:236`
  <!-- meta: fix=replace-with-confirmStore -->

- [ ] WEB-UIUX-71. **[MAJOR] Hardcoded `$` in InvoiceDetailPage credit-note max + payment modal prefix.** L9, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:605,760,777`
  <!-- meta: fix=use-formatCurrency -->

- [ ] WEB-UIUX-72. **[MAJOR] Hardcoded `$` in InventoryDetailPage pricing display + InventoryCreatePage inputs.** L9, L16.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:271-282`
  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:162,169`
  <!-- meta: fix=derive-currency-symbol-from-tenant -->

- [ ] WEB-UIUX-73. **[MAJOR] CashRegisterPage summary card colors lack dark variants.** `text-green-600`/`text-red-600`/`text-blue-600` without dark counterparts. L10.
  `packages/web/src/pages/pos/CashRegisterPage.tsx:99-112`
  <!-- meta: fix=add-dark:text-green-400-etc -->

- [ ] WEB-UIUX-74. **[MINOR] CommunicationPage date formatters hardcode `en-US` locale.** L9, L14.
  `packages/web/src/pages/communications/CommunicationPage.tsx:175-197`
  <!-- meta: fix=remove-locale-arg-or-use-tenant-setting -->

- [ ] WEB-UIUX-75. **[MINOR] InventoryDetailPage uses `toLocaleString()`/`toLocaleDateString()` not shared formatters.** L9.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:419,444`
  <!-- meta: fix=use-formatDateTime-formatDate -->

- [ ] WEB-UIUX-76. **[MINOR] Duplicate "Record Payment" CTA on InvoiceDetailPage (top bar + summary card).** L3, L2.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:345,574`
  <!-- meta: fix=demote-one-to-secondary-variant -->

- [ ] WEB-UIUX-77. **[MINOR] Invoice overdue count computed but never displayed in UI.** L1, L6.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:190-199`
  <!-- meta: fix=add-badge-to-Overdue-tab -->

- [ ] WEB-UIUX-78. **[MINOR] InventoryListPage "PLP / MS" toggle label is unexplained jargon.** L14.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:529-530`
  <!-- meta: fix=rename-to-Supplier-Parts-or-add-tooltip -->

- [ ] WEB-UIUX-79. **[MINOR] CashRegisterPage has no loading skeleton (uses centered spinner).** L6, L15.
  `packages/web/src/pages/pos/CashRegisterPage.tsx:167-168`
  <!-- meta: fix=add-skeleton-cards -->

- [ ] WEB-UIUX-80. **[NIT] CashRegisterPage empty state is plain div, not shared EmptyState.** L4, L6.
  `packages/web/src/pages/pos/CashRegisterPage.tsx:170-172`

### Tier 2: Leads + Estimates + Reports

- [ ] WEB-UIUX-81. **[BLOCKER] Lead status set mismatch between LeadListPage and LeadDetailPage.** Detail page has `qualified` + `proposal` statuses that don't exist in list page filter pills — leads in those statuses are invisible in the list. L5.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:337` vs `LeadListPage.tsx:78-85`
  <!-- meta: fix=unify-statuses-to-shared-constant -->

- [ ] WEB-UIUX-82. **[MAJOR] `contacted` status color is amber in detail page but purple in list page.** Visual inconsistency. L9.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:19` vs `LeadListPage.tsx:81`
  <!-- meta: fix=extract-status-color-config-to-shared-constant -->

- [ ] WEB-UIUX-83. **[MAJOR] Bulk delete fires N parallel DELETE requests with no rollback.** Partial failure leaves data in inconsistent state. L5, L8.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:591-596`
  <!-- meta: fix=add-bulk-endpoint-or-handle-partial-failure -->

- [ ] WEB-UIUX-84. **[MAJOR] CalendarPage create-appointment form doesn't reset when `defaultDate` changes.** useState only reads initial value; re-opening modal shows stale date. L7.
  `packages/web/src/pages/leads/CalendarPage.tsx:210-221`
  <!-- meta: fix=useEffect-sync-or-key-on-modal -->

- [ ] WEB-UIUX-85. **[MAJOR] AppointmentDetailModal is read-only with no edit/cancel/reschedule actions.** Dead-end UI. L1, L2.
  `packages/web/src/pages/leads/CalendarPage.tsx:83-173`
  <!-- meta: fix=add-Edit-and-Cancel-buttons -->

- [ ] WEB-UIUX-86. **[MAJOR] LostReasonModal sr-only radio inputs lack arrow-key navigation.** L12.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:122-137`
  <!-- meta: fix=implement-radiogroup-with-aria-checked-and-arrows -->

- [ ] WEB-UIUX-87. **[MAJOR] Bulk status dropdown has no click-outside dismiss.** L5.
  `packages/web/src/pages/leads/LeadListPage.tsx:642-658`
  <!-- meta: fix=add-backdrop-or-useClickOutside -->

- [ ] WEB-UIUX-88. **[MAJOR] ReportsPage tab bar with 12 tabs overflows on tablets.** L11, L1.
  `packages/web/src/pages/reports/ReportsPage.tsx:1427-1459`
  <!-- meta: fix=two-row-layout-or-dropdown-overflow -->

- [ ] WEB-UIUX-89. **[MAJOR] Report tab labels `hidden sm:inline` — mobile shows icon-only, indistinguishable.** L12, L14.
  `packages/web/src/pages/reports/ReportsPage.tsx:1453`
  <!-- meta: fix=add-tooltip-or-always-show-labels -->

- [ ] WEB-UIUX-90. **[MAJOR] Export button has no loading/disabled state during async export.** L8.
  `packages/web/src/pages/reports/ReportsPage.tsx:1402-1408`
  <!-- meta: fix=add-exporting-state-and-spinner -->

- [ ] WEB-UIUX-91. **[MAJOR] EstimateDetailPage inline editor uses `className="input"` — may lack dark styles.** L10, L9.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:329-351`
  <!-- meta: fix=verify-input-class-dark-mode-or-use-full-tailwind -->

- [ ] WEB-UIUX-92. **[MAJOR] EstimateDetailPage action buttons overflow on small screens (5 buttons horizontal).** L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:190-255`
  <!-- meta: fix=wrap-or-collapse-into-dropdown -->

- [ ] WEB-UIUX-93. **[MINOR] LeadListPage focus-visible ring missing on inline action buttons.** L12.
  `packages/web/src/pages/leads/LeadListPage.tsx:792-835`
  <!-- meta: fix=add-focus-visible-ring -->

- [ ] WEB-UIUX-94. **[MINOR] No Breadcrumb/BackButton on loading/error states (LeadDetailPage, EstimateDetailPage).** User loses navigation context. L1, L6.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:318-333`
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:138-153`

- [ ] WEB-UIUX-95. **[MINOR] LeadPipelinePage: no breadcrumb or back-to-list navigation.** L1.
  `packages/web/src/pages/leads/LeadPipelinePage.tsx:299-311`

- [ ] WEB-UIUX-96. **[MINOR] Pipeline subtitle says "Drag-free kanban" which confuses users expecting DnD.** L14.
  `packages/web/src/pages/leads/LeadPipelinePage.tsx:305-309`

- [ ] WEB-UIUX-97. **[MINOR] Estimate empty state uses `colSpan={7}` but table has 8 columns.** L9.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:652`

- [ ] WEB-UIUX-98. **[MINOR] Pagination "Showing 1-0 of 0" instead of "No results" when total is 0.** L14, L6.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:862-866`

- [ ] WEB-UIUX-99. **[MINOR] Chart axis tick fill `#9ca3af` hardcoded — low contrast in dark mode.** L10.
  `packages/web/src/pages/reports/ReportsPage.tsx:372,615,1059`
  <!-- meta: fix=use-CSS-variable-or-theme-aware-fill -->

- [ ] WEB-UIUX-100. **[NIT] LeadDetailPage renders both ArrowLeft back button and Breadcrumb to same target.** L3.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:341-349`

### Tier 2: Expenses + PO + Catalog + Loaners + GiftCards + Subscriptions + Reviews + Voice + Inventory Sub-Pages

- [ ] WEB-UIUX-101. **[MAJOR] 8 inventory sub-pages have systemic dark-mode blindness.** StocktakePage, BinLocationsPage, AutoReorderPage, SerialNumbersPage, ShrinkagePage, AbcAnalysisPage, InventoryAgePage, MassLabelPrintPage — all use bare `bg-white`/`border-surface-300` with zero dark variants. Entirely broken on dark theme. L10.
  <!-- meta: fix=single-pass-normalize-all-8-files -->

- [ ] WEB-UIUX-102. **[MAJOR] 3 pages require raw numeric "Inventory item ID" — unusable.** AutoReorderPage:188, SerialNumbersPage:96, ShrinkagePage:129 ask users to type DB IDs with no search/autocomplete. L7, L5.
  <!-- meta: fix=create-shared-InventoryItemPicker-component -->

- [ ] WEB-UIUX-103. **[MAJOR] CatalogPage "Sync" mutation exists but no "Sync Now" button wired.** Users cannot trigger manual catalog syncs. L5.
  `packages/web/src/pages/catalog/CatalogPage.tsx:182,428-463`
  <!-- meta: fix=add-Sync-Now-button-per-source-card -->

- [ ] WEB-UIUX-104. **[MAJOR] GiftCardsListPage has no pagination controls despite pagination data in response.** Only first page visible. L5.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:264-406`
  <!-- meta: fix=add-pagination-controls -->

- [ ] WEB-UIUX-105. **[MAJOR] PurchaseOrdersPage ReceiveModal missing `role="dialog"`, `aria-modal`, `aria-label`.** Screen readers cannot identify as modal. L12.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:85`
  <!-- meta: fix=add-dialog-aria-attributes -->

- [ ] WEB-UIUX-106. **[MAJOR] ReceiveModal missing Esc-to-close and click-outside-to-close.** L5.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:84-150`
  <!-- meta: fix=add-escape-and-backdrop-handlers -->

- [ ] WEB-UIUX-107. **[MAJOR] SerialNumbersPage status dropdown fires mutation immediately on change — no confirmation.** Accidental "sold" status is irreversible without manual intervention. L16.
  `packages/web/src/pages/inventory/SerialNumbersPage.tsx:186-189`
  <!-- meta: fix=add-confirmation-dialog -->

- [ ] WEB-UIUX-108. **[MINOR] GiftCardsListPage search has no debounce — fires API per keystroke.** L15, L1.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:316`
  <!-- meta: fix=add-300ms-debounce -->

- [ ] WEB-UIUX-109. **[MINOR] GiftCards expiry date input allows past dates.** Can issue already-expired card. L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:222-224`
  <!-- meta: fix=add-min=today -->

- [ ] WEB-UIUX-110. **[MINOR] SubscriptionsListPage: no search, no filter, no pagination.** L5.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:100-293`
  <!-- meta: fix=add-search-status-filter-pagination -->

- [ ] WEB-UIUX-111. **[MINOR] SubscriptionsListPage "Run billing now" button only shows a toast saying "runs nightly".** Misleading CTA. L16, L8.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:87-95`
  <!-- meta: fix=make-functional-or-change-to-info-text -->

- [ ] WEB-UIUX-112. **[MINOR] LoanersPage: no search or filter, no pagination for 100+ devices.** L1, L5.
  `packages/web/src/pages/loaners/LoanersPage.tsx:317-319`
  <!-- meta: fix=add-search-and-pagination -->

- [ ] WEB-UIUX-113. **[MINOR] VoiceCallsListPage: no direction/status filter.** L5.
  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:222-338`
  <!-- meta: fix=add-direction-and-status-dropdowns -->

- [ ] WEB-UIUX-114. **[MINOR] CatalogPage device-model dropdown does not close on click-outside.** L5.
  `packages/web/src/pages/catalog/CatalogPage.tsx:534-553`
  <!-- meta: fix=add-onBlur-or-click-outside-listener -->

- [ ] WEB-UIUX-115. **[MINOR] ShrinkagePage photo file input invisible with no filename feedback.** L8.
  `packages/web/src/pages/inventory/ShrinkagePage.tsx:164-169`
  <!-- meta: fix=style-label-as-button-show-filename -->

- [ ] WEB-UIUX-116. **[MINOR] InventoryAgePage has no loading state.** Shows nothing until data arrives. L6.
  `packages/web/src/pages/inventory/InventoryAgePage.tsx:39-163`
  <!-- meta: fix=add-spinner-or-skeleton -->

- [ ] WEB-UIUX-117. **[MINOR] ReviewsPage "mark public" toggle lacks confirmation or feedback toast.** Misclick silently publishes/unpublishes. L8.
  `packages/web/src/pages/reviews/ReviewsPage.tsx:310-319`
  <!-- meta: fix=add-toast-on-success -->

- [ ] WEB-UIUX-118. **[MINOR] PO form inputs missing aria-labels.** L12.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:383-452`
  <!-- meta: fix=add-labels-or-aria-labels -->

- [ ] WEB-UIUX-119. **[MINOR] PO create: no form validation feedback — greyed button with no explanation.** L8.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:355-359`
  <!-- meta: fix=add-inline-field-errors -->

- [ ] WEB-UIUX-120. **[MINOR] ExpensesPage search input missing aria-label.** L12.
  `packages/web/src/pages/expenses/ExpensesPage.tsx:217-226`
  <!-- meta: fix=add-aria-label -->

### Tier 3: Admin & Team

- [ ] WEB-UIUX-121. **[MAJOR] SettingsPage uses raw `bg-blue-600 text-white` ~12 times instead of semantic primary.** L9, L4.
  `packages/web/src/pages/settings/SettingsPage.tsx:933`
  <!-- meta: fix=migrate-to-bg-primary-600-text-primary-950 -->

- [ ] WEB-UIUX-122. **[MAJOR] TeamChatPage send-hint says "Cmd+Enter" but Enter actually sends.** L14.
  `packages/web/src/pages/team/TeamChatPage.tsx:333,314-316`
  <!-- meta: fix=update-copy-to-match-implementation -->

- [ ] WEB-UIUX-123. **[MAJOR] TeamChatPage entirely missing dark mode.** bg-white, text-gray-* with zero dark: variants. L10.
  `packages/web/src/pages/team/TeamChatPage.tsx:244-338`
  <!-- meta: fix=add-dark-mode-throughout -->

- [ ] WEB-UIUX-124. **[MAJOR] RolesMatrixPage entirely missing dark mode.** L10.
  `packages/web/src/pages/team/RolesMatrixPage.tsx`
  <!-- meta: fix=add-dark-mode -->

- [ ] WEB-UIUX-125. **[MAJOR] ShiftSchedulePage entirely missing dark mode.** L10.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx`
  <!-- meta: fix=add-dark-mode -->

- [ ] WEB-UIUX-126. **[MAJOR] MyQueuePage entirely missing dark mode.** L10.
  `packages/web/src/pages/team/MyQueuePage.tsx`
  <!-- meta: fix=add-dark-mode -->

- [ ] WEB-UIUX-127. **[MAJOR] PaymentLinksPage table/filters missing dark mode (form has partial).** Visual split. L10.
  `packages/web/src/pages/settings/PaymentLinksPage.tsx`
  <!-- meta: fix=complete-dark-mode -->

- [ ] WEB-UIUX-128. **[MAJOR] AgingReportPage entirely missing dark mode.** L10.
  `packages/web/src/pages/reports/AgingReportPage.tsx`
  <!-- meta: fix=add-dark-mode -->

- [ ] WEB-UIUX-129. **[MINOR] PayrollPage is a stub with no content or empty state.** L1, L6.
  `packages/web/src/pages/team/PayrollPage.tsx`
  <!-- meta: fix=add-empty-state-with-explanation -->

- [ ] WEB-UIUX-130. **[MINOR] AuditLogsTab hardcodes dark surface colors without light-mode variants.** Assumes always-dark rendering context. L10.
  `packages/web/src/pages/settings/AuditLogsTab.tsx:75`
  <!-- meta: fix=add-light-mode-variants -->

### Tier 4: Auth, Setup, Customer-Facing

- [ ] WEB-UIUX-131. **[BLOCKER] SignupPage uses inline styles, zero Tailwind, zero dark mode, wrong fonts.** First surface new users see. Complete design-system bypass. L10, L14.
  `packages/web/src/pages/auth/SignupPage.tsx`
  <!-- meta: fix=rewrite-with-Tailwind+brand-fonts+dark-mode -->

- [ ] WEB-UIUX-132. **[BLOCKER] LandingPage uses inline styles + embedded `<style>` tag, zero dark mode.** Public marketing page bypasses entire design system. L10, L14.
  `packages/web/src/pages/public/LandingPage.tsx`
  <!-- meta: fix=rewrite-with-Tailwind+dark-mode -->

- [ ] WEB-UIUX-133. **[MAJOR] LandingPage testimonials are placeholders: "Testimonial coming soon."** On live public page — damages credibility. L16.
  `packages/web/src/pages/public/LandingPage.tsx`
  <!-- meta: fix=add-real-testimonials-or-remove-section -->

- [ ] WEB-UIUX-134. **[MAJOR] CustomerPayPage entirely missing dark mode.** Public payment page — customers with dark OS see blinding white. L10.
  `packages/web/src/pages/public/CustomerPayPage.tsx:128`
  <!-- meta: fix=add-dark-mode -->

- [ ] WEB-UIUX-135. **[MAJOR] TrackingPage portal detail view missing dark mode.** Raw `bg-white`/`text-slate-*` throughout device list and timeline. L10.
  `packages/web/src/pages/public/TrackingPage.tsx:419-560`
  <!-- meta: fix=add-dark-mode -->

- [ ] WEB-UIUX-136. **[MINOR] LoginPage verify-step button uses raw `bg-green-600` while other steps use `bg-primary-600`.** L9.
  `packages/web/src/pages/auth/LoginPage.tsx`

- [ ] WEB-UIUX-137. **[MINOR] ResetPasswordPage copy: "Enter securely a new password" — awkward phrasing.** L14.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:121`

- [ ] WEB-UIUX-138. **[MINOR] ResetPasswordPage auto-redirect 3s with no cancel/fallback button.** L5.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx`

- [ ] WEB-UIUX-139. **[MINOR] PortalEstimatesView / PortalInvoicesView status badges missing dark variants.** L10.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:159-170`
  `packages/web/src/pages/portal/PortalInvoicesView.tsx:195-208`

- [ ] WEB-UIUX-140. **[MINOR] ReviewPromptModal uses raw `gray-*` instead of semantic `surface-*` tokens.** L10.
  `packages/web/src/pages/portal/ReviewPromptModal.tsx:74`

- [ ] WEB-UIUX-141. **[NIT] CustomerPayPage "Pay now" button uses `bg-gray-900 text-white` — neutral, not brand.** L9.
  `packages/web/src/pages/public/CustomerPayPage.tsx:194`

### Recommended Sequencing

**Phase 1 — Blockers (ship-stoppers):**
WEB-UIUX-29 (RepairRow qty), WEB-UIUX-81 (lead status mismatch),
WEB-UIUX-131 (SignupPage), WEB-UIUX-132 (LandingPage)

**Phase 2 — High-impact systemic:**
WEB-UIUX-1 (Button adoption), WEB-UIUX-2 (semantic tokens),
WEB-UIUX-3 (bg-white dark gaps), WEB-UIUX-12 (reduced-motion),
WEB-UIUX-101 (inventory dark-mode cluster), WEB-UIUX-102 (item picker)

**Phase 3 — POS critical path:**
WEB-UIUX-30 (hardcoded $), WEB-UIUX-34 (decimal input),
WEB-UIUX-35 (action hierarchy), WEB-UIUX-36-038 (focus/teal)

**Phase 4 — Accessibility sweep:**
WEB-UIUX-4 (icon labels), WEB-UIUX-16 (CommandPalette ARIA),
WEB-UIUX-50-054 (hover-only elements), WEB-UIUX-105-106 (modal ARIA)

**Phase 5 — Dark-mode completion:**
WEB-UIUX-121-128 (admin/team pages), WEB-UIUX-134-135 (public pages)

**Phase 6 — Workflow + forms:**
WEB-UIUX-15 (dead routes), WEB-UIUX-49 (window.prompt),
WEB-UIUX-51 (mobile kanban), WEB-UIUX-56 (dirty guard),
WEB-UIUX-83-084 (bulk delete, calendar form)


### Web UI/UX Audit — Pass 2 (2026-05-04, post-research)

Continuing from WEB-UIUX-141. Pass 2 covers settings tabs, super-admin/marketing/billing,
and WCAG 2.2 / online research findings. Sources cited: w3.org/TR/WCAG22, snabble.io,
creativenavy POS guides, Tailwind dark-mode docs.

#### Settings Tabs

- [ ] WEB-UIUX-142. **[BLOCKER] RepairPricingTab renders `<td>` inside `<div>` (invalid HTML).** `<td colSpan={8}>` with nested `<td>` elements outside any `<tr>`. Will fail axe, screen readers see no cells. L4, L12.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:765-803`
  <!-- meta: fix=restructure-as-tr-with-colspan-td -->

- [ ] WEB-UIUX-143. **[BLOCKER] ReceiptSettings saves entire config object — clobbers other tabs.** WEB-FG-006 already fixed PosSettings via owned-keys allowlist; receipts regressed. If POS/SMS tabs have staged changes elsewhere, this overwrites them. L5, L16.
  `packages/web/src/pages/settings/ReceiptSettings.tsx:347-359`
  <!-- meta: fix=add-RECEIPT_OWNED_KEYS-allowlist-pattern -->

- [ ] WEB-UIUX-144. **[BLOCKER] TicketsRepairsSettings same clobber bug.** L5, L16.
  `packages/web/src/pages/settings/TicketsRepairsSettings.tsx:238-251`
  <!-- meta: fix=add-TICKETS_OWNED_KEYS-pattern -->

- [ ] WEB-UIUX-145. **[BLOCKER] SmsVoiceSettings Voice section has NO save button.** User edits voice fields, clicks "Save Provider" → voice values silently persisted as side-effect because save reads via `document.getElementById`. L5, L7.
  `packages/web/src/pages/settings/SmsVoiceSettings.tsx:264-322`
  <!-- meta: fix=make-voice-controlled-state-add-Save-Voice-button -->

- [ ] WEB-UIUX-146. **[MAJOR] SmsVoiceSettings reads voice toggles via `document.getElementById`.** DOM-as-state pattern — fragile, breaks on rapid toggles or re-renders. L4, L7.
  `packages/web/src/pages/settings/SmsVoiceSettings.tsx:117-145, 270-321`
  <!-- meta: fix=convert-to-controlled-useState -->

- [ ] WEB-UIUX-147. **[MAJOR] RepairPricingTab AdjustmentsSubTab uses `useState(() => sideEffect)` as effect.** Lazy-init slot runs once at mount, never reacts to data changes. `useMemo` directly below also misused as effect. L4, L15.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:836-851`
  <!-- meta: fix=replace-with-proper-useEffect -->

- [ ] WEB-UIUX-148. **[MAJOR] BlockChyp Test Connection unreachable after reload.** Disables button unless all 3 secrets typed in current session, but secrets arrive redacted as `''` → user with valid stored creds sees disabled button. Dead-end UX. L8.
  `packages/web/src/pages/settings/BlockChypSettings.tsx:282-288`
  <!-- meta: fix=track-hasServerCreds-flag-from-GET-response -->

- [ ] WEB-UIUX-149. **[MAJOR] All 5+ settings modals lack focus trap.** AutomationModal, EditTemplateModal, TerminationModal, DeviceTemplatesPage editor, MembershipSettings TierForm — all implement Esc+backdrop+ARIA but don't trap Tab. Tab escapes to obscured page below. L12.
  Files: AutomationsTab.tsx:402-501, NotificationTemplatesTab.tsx:60-181, DangerZoneTab.tsx:182-271, DeviceTemplatesPage.tsx:317-563, MembershipSettings.tsx:188-339
  <!-- meta: fix=adopt-shared-Modal-or-focus-trap-react -->

- [ ] WEB-UIUX-150. **[MAJOR] ReceiptSettings live preview rendered TWICE.** `ReceiptLivePreview` component PLUS hand-rolled mock receipts (lines 494-565). They will diverge. L1, L15.
  `packages/web/src/pages/settings/ReceiptSettings.tsx:494-565`
  <!-- meta: fix=delete-handrolled-block -->

- [ ] WEB-UIUX-151. **[MAJOR] Toggle/Switch component duplicated 8 times across settings.** AutomationsTab, BlockChypSettings, MembershipSettings, PosSettings, ReceiptSettings, SmsVoiceSettings, NotificationTemplatesTab, TicketsRepairsSettings — each ships its own variant. Different sizes (h-5/h-6), different colors (teal/green/primary). L3, L4.
  <!-- meta: fix=extract-Switch-component-shared -->

- [ ] WEB-UIUX-152. **[MAJOR] RepairPricingTab Prices table has NO inline edit.** To change a labor price user must delete (losing grades) and recreate. Services table supports edit; prices doesn't. L4.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:600-820`
  <!-- meta: fix=add-edit-in-place-parallel-to-ServicesSubTab -->

- [ ] WEB-UIUX-153. **[MAJOR] Save buttons not sticky on long forms.** PosSettings (15+ toggles), ReceiptSettings (25+ toggles in 4 sections), TicketsRepairsSettings — save in card header only, user scrolls back to save. L1.
  <!-- meta: fix=sticky-top-save-bar-or-footer-bar -->

- [ ] WEB-UIUX-154. **[MAJOR] ConditionsTab condition-check delete + category-template delete fire without confirmation.** Adjacent Checklist Templates section does prompt — inconsistency. L8.
  `packages/web/src/pages/settings/ConditionsTab.tsx:145,355-361`
  <!-- meta: fix=wrap-in-confirm-store -->

- [ ] WEB-UIUX-155. **[MAJOR] BlockChyp Save button uses `bg-green-600 text-white` — non-canonical.** Other save buttons use `bg-primary-600 text-primary-950`. L9.
  `packages/web/src/pages/settings/BlockChypSettings.tsx:222-231`

- [ ] WEB-UIUX-156. **[MAJOR] NotificationTemplatesTab `show_in_canned` accessed via `(t as any)` — type drift hidden.** Field not declared on `NotificationTemplate` interface. L4.
  `packages/web/src/pages/settings/NotificationTemplatesTab.tsx:11-22, 351`
  <!-- meta: fix=add-show_in_canned-to-interface -->

- [ ] WEB-UIUX-157. **[MINOR] RepairPricingTab declares `useQuery` for prices with NO queryFn — dead code.** Variable `prices` never used. Returns `undefined` on cold cache. L15.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:426-428`

- [ ] WEB-UIUX-158. **[MINOR] RepairPricingTab GradesSection 50-line stale-comment monologue.** Belongs in PR description, not source. L14.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:430-484`

- [ ] WEB-UIUX-159. **[MINOR] Hardcoded `$` in RepairPricing prices/adjustments + BillingTab + DeviceTemplatesPage.** L9, L14.
  `RepairPricingTab.tsx:781,937-950`, `BillingTab.tsx:111,200`, `DeviceTemplatesPage.tsx:287`

- [ ] WEB-UIUX-160. **[MINOR] Settings settings tabs use 4 different sub-tab visual languages.** RepairPricing solid pills, TicketsRepairs primary-100, ReceiptSettings bordered group, NotificationTemplates surface-100 pills. L4.
  <!-- meta: fix=extract-Tabs-primitive -->

- [ ] WEB-UIUX-161. **[MINOR] DeviceTemplatesPage part search has no debounce.** Every keystroke fetches. L1, L15.
  `packages/web/src/pages/settings/DeviceTemplatesPage.tsx:109-117`

- [ ] WEB-UIUX-162. **[MINOR] RepairPricing DeviceModelPicker + InventoryPartPicker dropdowns don't close on click-outside.** Phantom dropdowns on tablets. L1, L11.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:339-365, 385-413`

- [ ] WEB-UIUX-163. **[MINOR] MembershipSettings tier badge `text-white` over `style={backgroundColor: tier.color}` — contrast risk.** Some preset colors (amber, light yellow) below 4.5:1. L9, L12.
  `packages/web/src/pages/settings/MembershipSettings.tsx:130-137`
  <!-- meta: fix=compute-luminance-pick-text-color -->

- [ ] WEB-UIUX-164. **[MINOR] AutomationsTab Edit button uses `Zap` icon — same as section header. Should be `Pencil`.** Visual conflict. L1, L9.
  `packages/web/src/pages/settings/AutomationsTab.tsx:770-776`

- [ ] WEB-UIUX-165. **[MINOR] DangerZone "Close" button doesn't sign user out despite copy saying "signed out on next action".** Ambiguous state until next request. L5.
  `packages/web/src/pages/settings/DangerZoneTab.tsx:484-495`

- [ ] WEB-UIUX-166. **[MINOR] DangerZone token expiry shown but not enforced client-side.** User can submit known-dead token. L8.
  `packages/web/src/pages/settings/DangerZoneTab.tsx:344-398`

- [ ] WEB-UIUX-167. **[MINOR] ConditionsTab GripVertical icon shown without functional drag-and-drop.** Misleading affordance — only chevron up/down works. L1.
  `packages/web/src/pages/settings/ConditionsTab.tsx:284`

- [ ] WEB-UIUX-168. **[NIT] DangerZoneTab line 73 has `disabled:cursor-not-allowed` duplicated in className.** L13.
  `packages/web/src/pages/settings/DangerZoneTab.tsx:73`

- [ ] WEB-UIUX-169. **[NIT] AutomationsTab toast emoji `🔍` (cross-platform inconsistent).** Brand uses Lucide icons. L14.
  `packages/web/src/pages/settings/AutomationsTab.tsx:633`

- [ ] WEB-UIUX-170. **[NIT] AutomationDetailPage shows raw `<pre>` JSON dump.** Useful for engineers, scary for shop owners. L1, L14.
  `packages/web/src/pages/settings/AutomationDetailPage.tsx:207-223`

#### Super-Admin / Marketing / Billing

- [ ] WEB-UIUX-171. **[MAJOR] Impersonate confirm uses `bg-amber-600` (warning tone) for cross-tenant access escalation.** Should be danger-red — operation is logged to audit and creates legal liability. L9, L16.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:401-405,325-326`

- [ ] WEB-UIUX-172. **[MAJOR] CustomerPayPage shows amount + invoice ref but NEVER displays merchant name/logo/address.** Public payment link via SMS — customer has zero phishing-protection signals. Trust gap. L16.
  `packages/web/src/pages/billing/CustomerPayPage.tsx:131-187`
  <!-- meta: fix=server-expose-tenant_name-tenant_logo-render-prominent -->

- [ ] WEB-UIUX-173. **[MAJOR] CustomerPayPage "Pay now" button uses `bg-gray-900 text-white`.** Public customer paying real money sees neutral-gray button, looks like different product. L9, L16.
  `packages/web/src/pages/billing/CustomerPayPage.tsx:191-201`

- [ ] WEB-UIUX-174. **[MAJOR] Aging-report bulk-action button buried inside total-outstanding banner.** Discoverability poor — operator scans for primary CTAs above the table, not in tip strip. L1, L2, L5.
  `packages/web/src/pages/billing/AgingReportPage.tsx:130-148`
  <!-- meta: fix=move-to-sticky-toolbar-above-table -->

- [ ] WEB-UIUX-175. **[MAJOR] Aging-report missing select-all checkbox in thead.** Clearing 50+ overdue invoices is dominant workflow. L5.
  `packages/web/src/pages/billing/AgingReportPage.tsx:154`

- [ ] WEB-UIUX-176. **[MAJOR] Campaigns Run-now confirm button NOT disabled while count is loading.** Can dispatch to "unknown" recipients before count returns — TCPA-safety story collapses. L6, L8.
  `packages/web/src/pages/marketing/CampaignsPage.tsx:386-405`

- [ ] WEB-UIUX-177. **[MAJOR] Campaigns row action stack is 6 vertical buttons.** "Run now" dominates, "Delete" one tab-stop away. Flat hierarchy. L1, L2.
  `packages/web/src/pages/marketing/CampaignsPage.tsx:268-342`
  <!-- meta: fix=primary-CTA-plus-overflow-MenuButton -->

- [ ] WEB-UIUX-178. **[MAJOR] Dunning per-step Trash button has no confirm — single-click delete loses sequence draft.** No autosave either. L6, L16.
  `packages/web/src/pages/billing/DunningPage.tsx:272-280`

- [ ] WEB-UIUX-179. **[MAJOR] PaymentLinks Cancel button single-click cancels link without confirm.** Customer mid-checkout hits dead-end. L6, L16.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:309-318`

- [ ] WEB-UIUX-180. **[MAJOR] DunningPage step row hard-codes `grid-cols-[auto_1fr_1fr_auto]`.** Selects squish to ~80px on 375px viewport, options truncate without ellipsis. L11.
  `packages/web/src/pages/billing/DunningPage.tsx:232`

- [ ] WEB-UIUX-181. **[MAJOR] TenantsListPage table no mobile card layout — 7 cols horizontal-scroll trap.** Touch users won't discover rightmost action. L11.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:517-542`

- [ ] WEB-UIUX-182. **[MAJOR] NpsTrendPage chart has no aria-label, no SR table fallback.** Pure `<div>` bars with `style={{height}}`. Owners using SR get nothing. L12.
  `packages/web/src/pages/marketing/NpsTrendPage.tsx:115-146`

- [ ] WEB-UIUX-183. **[MAJOR] DunningPage step editor selects have no `<label>` or `aria-label`.** SR announces "select, Email" with no field context. L7, L12.
  `packages/web/src/pages/billing/DunningPage.tsx:235-270`

- [ ] WEB-UIUX-184. **[MAJOR] EmployeeListPage ExpandedRow fires 3 separate queries when employee.detail already returns clock_entries + commissions.** N+1 the audit-fix removed for the list, but expand path still does it. L15.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:319-339`

- [ ] WEB-UIUX-185. **[MAJOR] EmployeeListPage `<tr onClick>` row expand has no role/tabIndex/keydown.** Keyboard users can't expand rows. L12.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:614-617`

- [ ] WEB-UIUX-186. **[MINOR] PaymentLinks expiry date stamps `T23:59:59` browser-local.** EST merchant creating "expires today" produces UTC timestamp PST customer experiences as early-expired. L7, L14.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:236-241,134-141`
  <!-- meta: fix=show-tz-helper-text-or-explicit-time-picker -->

- [ ] WEB-UIUX-187. **[MINOR] PaymentLinks customer/invoice ID inputs are bare numeric — no picker.** Typo only caught after submit. L7.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:208-227`

- [ ] WEB-UIUX-188. **[MINOR] DepositCollect amount input uses dollars but server uses cents — silent rounding drift.** `100.005` → server may round to `10000` cents (lose 0.5¢). L16.
  `packages/web/src/pages/billing/DepositCollectModal.tsx:52-61`
  <!-- meta: fix=multiply-to-int-cents-on-client -->

- [ ] WEB-UIUX-189. **[MINOR] GiftCardDetail Reload no upper-bound validation.** Typo `10000.00` for `100.00` reloads $10k silently. L7, L16.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:90-96`
  <!-- meta: fix=cap-at-5k-second-step-confirm-over-500 -->

- [ ] WEB-UIUX-190. **[MINOR] CustomerPayPage swallows 4xx/5xx into generic "Could not load".** 410-Gone (expired) and 500 look identical to user. L8.
  `packages/web/src/pages/billing/CustomerPayPage.tsx:89-96`

- [ ] WEB-UIUX-191. **[MINOR] ImpersonateConfirmModal backdrop click during submit cancels visually but not the request.** Token still arrives, banner state still set. L16.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:312-316`

- [ ] WEB-UIUX-192. **[MINOR] CustomerPayPage uses `text-4xl` raw `✓` emoji.** Renders inconsistently across OS, no SR label. L9, L12.
  `packages/web/src/pages/billing/CustomerPayPage.tsx:164`

- [ ] WEB-UIUX-193. **[MINOR] TenantsList "Sign out" sits in toolbar next to filter — same shape/weight.** Confusion risk. L2.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:481-493`
  <!-- meta: fix=move-to-user-menu -->

- [ ] WEB-UIUX-194. **[MINOR] Container width inconsistency across pages.** Marketing: max-w-6xl. Billing: full-bleed p-6. Tenants: no wrapper. GiftCardDetail: max-w-3xl. App feels like 4 different products. L2, L11.
  <!-- meta: fix=PageContainer-with-narrow-default-wide -->

- [ ] WEB-UIUX-195. **[MINOR] Heading size inconsistency: text-xl vs text-2xl, font-bold vs font-semibold across pages.** L2.
  Three weight+size combinations for same element role.

#### WCAG 2.2 + Online Research

- [ ] WEB-UIUX-196. **[MAJOR] WCAG 2.4.11 Focus Not Obscured — sticky table headers can hide focused rows.** 14+ pages use `<thead className="sticky top-0">` (TicketListPage, CustomerListPage, InvoiceListPage, InventoryListPage, DashboardPage tables, etc.). When user tabs to a focused row near top of scroll, sticky thead obscures it. WCAG 2.2 AA. L12.
  Pattern across: `pages/customers/CustomerListPage.tsx:731`, `pages/invoices/InvoiceListPage.tsx:435`, `pages/tickets/TicketListPage.tsx:1707`, `pages/dashboard/DashboardPage.tsx:1165,1726,2260`
  <!-- meta: fix=scrollMarginTop-on-focusable-rows-or-overflow-anchor -->

- [ ] WEB-UIUX-197. **[MAJOR] WCAG 2.5.8 Target Size Minimum (24x24 CSS px) — many `p-1` icon buttons under threshold.** Header notification buttons, ZReportModal close (p-1, ~16px), TicketSidebar X icons. WCAG 2.2 AA. L12, L11.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:120` (p-1 close button)
  Audit needed: `grep -rn 'className=".*p-1[^0-9]' --include="*.tsx" | grep "<button"`
  <!-- meta: fix=normalize-icon-button-padding-to-p-1.5-min -->

- [ ] WEB-UIUX-198. **[MAJOR · BLOCKED] WCAG 1.3.5 Identify Input Purpose — many email/tel/name inputs missing `autoComplete`.** CustomerCreatePage email/tel/firstname/lastname (`autoComplete="email"`/`"tel"`/`"given-name"`/`"family-name"` missing), CustomerDetailPage edit fields, Settings staff add form. Browsers can't autofill. L7, L12.
  **STATUS: BLOCKED** — deferred until email/messaging infrastructure work begins (per user 2026-05-05). Note: this is purely a client-side HTML attribute fix and could be unblocked early if needed.
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:335,348,359` (and others)
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1269,1278,1289`
  <!-- meta: fix=add-autoComplete-attributes-per-WHATWG-spec -->

- [ ] WEB-UIUX-199. **[MAJOR] WCAG 3.2.6 Consistent Help — no consistent Help/Support entry point across pages.** Some pages link to settings tooltip, others have nothing. New WCAG 2.2 AA criterion. L1, L4.
  <!-- meta: fix=add-persistent-support-link-in-header-or-sidebar -->

- [ ] WEB-UIUX-200. **[MAJOR] WCAG 3.3.7 Redundant Entry — multi-step setup re-prompts for info already entered.** SetupPage steps may ask same fields multiple times (verify). New WCAG 2.2 A. L7.
  `packages/web/src/pages/setup/SetupPage.tsx`
  <!-- meta: fix=audit-step-flow-pre-fill-from-prior-steps -->

- [ ] WEB-UIUX-201. **[MAJOR] CustomerPayPage uses `bg-gray-900` (true black) — research flags as "brutal at night".** Research consensus: darkest background should be #121212 not #000. Same on CustomerPayPage Pay button. L10.
  `packages/web/src/pages/billing/CustomerPayPage.tsx:194`
  <!-- meta: fix=use-surface-950-token-not-gray-900 -->

- [ ] WEB-UIUX-202. **[MAJOR] Dashboard scan flash, KPI skeleton, all spinners run unconditionally — POS UX research: cashier pace is 2x normal user.** `motion-reduce:animate-none` not applied anywhere. WCAG 2.3.3 + ergonomics. L13.
  All `animate-pulse` / `animate-spin` callsites.
  <!-- meta: fix=add-motion-reduce:animate-none-globally-via-Skeleton-component -->

- [ ] WEB-UIUX-203. **[MAJOR] POS UX research — cashier needs role-based view, but POS shows all functions to all roles.** Compare LeftPanel actions for cashier vs manager. Cashier doesn't need PriceOverride/VoidLine without ManagerPin every time. L1, L2.
  `packages/web/src/pages/unified-pos/`
  <!-- meta: fix=role-based-action-visibility -->

- [ ] WEB-UIUX-204. **[MINOR] WCAG 3.3.8 Accessible Authentication — LoginPage password field doesn't disable browser autofill paste.** Verify `autoComplete="current-password"` set + no onPaste prevention (we found 0 onPaste handlers, good). New WCAG 2.2 AA. L7, L12.
  `packages/web/src/pages/auth/LoginPage.tsx:698` ✓ correct
  <!-- meta: status=already-compliant-on-login-verify-other-password-fields -->

- [ ] WEB-UIUX-205. **[MINOR] Tailwind dark-mode research: `dark:` class on wrapper breaks portals/popovers if sibling.** Check that `dark` class is on `documentElement`, not inner wrappers. Verify in `useTheme` hook. L10.
  `packages/web/src/hooks/useTheme.ts` (verify)
  <!-- meta: fix=ensure-dark-class-on-html-element -->

- [ ] WEB-UIUX-206. **[MINOR] POS UX research: tap zones for cashier should be larger than normal user (2x speed).** POS tile buttons use default Tailwind `p-3` (~24px). Should be at least 44x44 for touch (`min-h-[44px]`). L11.
  `packages/web/src/pages/unified-pos/ProductsTab.tsx:163-175`
  <!-- meta: fix=normalize-POS-tap-targets-to-44px-min -->

#### Recommended Sequencing — Pass 2 Additions

**Phase 1 — Pass-2 blockers:**
WEB-UIUX-142 (invalid HTML), WEB-UIUX-143 + 144 (settings clobber bugs),
WEB-UIUX-145 (voice settings no save UI)

**Phase 2 — Trust + safety:**
WEB-UIUX-172-173 (CustomerPayPage merchant identity + button color),
WEB-UIUX-176 (Campaign run-now race), WEB-UIUX-178-179 (no-confirm destructive)

**Phase 3 — A11y (WCAG 2.2):**
WEB-UIUX-149 (settings focus traps), WEB-UIUX-182-183 (chart + select labels),
WEB-UIUX-185 (row keydown), WEB-UIUX-196-200 (sticky obscure, target size, autocomplete, consistent help, redundant entry)

**Phase 4 — Component extraction:**
WEB-UIUX-151 (Switch component), WEB-UIUX-160 (Tabs primitive),
extracted Modal shell (cross-cutting)


### Web UI/UX Audit — Pass 3 (2026-05-05, brand+forms+toast research)

#### Brand & Identity

- [ ] WEB-UIUX-207. **[MAJOR] Bebas Neue (display font) declared in tailwind.config but not in `<link rel=preload>`.** Index.html preloads Inter, Jost, JetBrains Mono, League Spartan, Roboto — but NOT Bebas Neue. All `font-display` headings silently fall back to Jost. Brand identity gap. L9, L14.
  `packages/web/index.html:64`
  `packages/web/tailwind.config.ts:157`
  <!-- meta: fix=add-Bebas+Neue-to-Google-Fonts-preload-or-self-host -->

- [ ] WEB-UIUX-208. **[MAJOR] `font-display` (Bebas Neue) used in only 1 file across entire web app.** 100+ `<h1>`/`<h2>` headings use default `font-sans` (Jost). Brand display font effectively unused. L9.
  Recommendation: audit `grep -rn "<h[12]" --include="*.tsx"` and add `font-display` where appropriate.
  <!-- meta: fix=apply-font-display-class-to-h1-h2-page-titles -->

- [ ] WEB-UIUX-209. **[MAJOR] `font-logo` (Saved By Zero) has ZERO usages anywhere.** Logo wordmark in Header/Sidebar uses default font. Brand voice missing entirely. Memory note: woff2 file pending self-host. L9, L14.
  <!-- meta: fix=ship-SavedByZero.woff2-and-apply-font-logo-to-Logo-component -->

- [ ] WEB-UIUX-210. **[MINOR] Index.html preloads legacy fonts Inter + League Spartan + Roboto.** Per brand spec these are NOT canonical. Wastes preload budget. L9, L15.
  `packages/web/index.html:64`
  <!-- meta: fix=remove-Inter-LeagueSpartan-Roboto-from-preload -->

- [ ] WEB-UIUX-211. **[MINOR] SignatureCanvas hardcodes `12px Inter, sans-serif` for canvas text.** Bypasses brand fonts. L9.
  `packages/web/src/components/shared/SignatureCanvas.tsx:109,209`
  <!-- meta: fix=use-Jost-or-Futura-font-stack -->

- [ ] WEB-UIUX-212. **[MINOR] `<title>BizarreCRM</title>` static — never updates per route.** No page-context in tab. SEO + UX hurt. L1, L14.
  `packages/web/index.html:36`
  <!-- meta: fix=use-react-helmet-or-useEffect-to-set-document.title -->

- [ ] WEB-UIUX-213. **[MINOR] `<html lang="en">` hardcoded.** Won't adapt for non-English tenants. WCAG 3.1.1 compliance for i18n. L12, L14.
  `packages/web/index.html:2`

#### Form Accessibility (WebAIM 2026 research: 33% of inputs unlabeled)

- [ ] WEB-UIUX-214. **[MAJOR] 381 placeholder usages vs 107 `htmlFor=` pairs across all .tsx files.** ~3.5:1 ratio means most inputs are placeholder-only — disappear on type, fail WCAG 1.3.1, 4.1.2. WebAIM 2026 reports 33% web average; appears worse here. L7, L12.
  Pattern across many files. Audit needed: `grep -L 'htmlFor' files-with-input.tsx`
  <!-- meta: fix=add-explicit-label-or-aria-label-to-placeholder-only-inputs -->

- [ ] WEB-UIUX-215. **[MAJOR] Only 38 `aria-invalid` callsites for ~750 toast.error firings.** Form errors surfaced as toasts but don't mark the offending field as invalid. SR users don't know which field needs fixing. L7, L8, L12.
  <!-- meta: fix=mirror-toast.error-to-setError(field)+aria-invalid=true -->

- [ ] WEB-UIUX-216. **[MAJOR] Only 40 `aria-describedby` callsites — error messages not linked to fields.** Per research: invalid fields must use aria-describedby pointing to the error message id. L7, L8, L12.
  <!-- meta: fix=add-aria-describedby+id-pattern-to-FormError-component -->

- [ ] WEB-UIUX-217. **[MINOR] CustomerCreatePage uses `className="input"` global utility — bypass Tailwind dark mode tracking.** L4, L10.
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:283` (and many others)
  <!-- meta: fix=verify-input-class-or-migrate-to-explicit-classes -->

- [ ] WEB-UIUX-218. **[MINOR] No form-level error summary at top of long forms.** Per WebAIM: long forms should show errors-summary `role="alert"` linking to each errored field. CustomerCreatePage, EstimateDetailPage edit, SettingsPage forms all lack this. L7, L8, L12.

#### Toast UX (LogRocket/Carbon/research)

- [ ] WEB-UIUX-219. **[MINOR] Toaster default duration 4000ms — research: 5000ms minimum for most users to read.** Short success (3000ms) too short for non-trivial messages. L8, L12.
  `packages/web/src/main.tsx:410-411`
  <!-- meta: fix=raise-default-to-5000-success-to-4000 -->

- [ ] WEB-UIUX-220. **[MINOR] Toaster lacks explicit `role="status"` + `aria-live="polite"` props.** react-hot-toast sets it by default, but explicit declaration documents intent. L12.
  `packages/web/src/main.tsx:404-415`

- [ ] WEB-UIUX-221. **[MINOR] LoanersPage important transactional toast `Collect $X damage charge` only 8s + uses `$` literal.** User must remember $ amount after toast disappears — should be UI banner, not toast. L8, L9, L16.
  `packages/web/src/pages/loaners/LoanersPage.tsx:46`
  <!-- meta: fix=show-banner-not-toast-for-action-required-info -->

- [ ] WEB-UIUX-222. **[MINOR] CheckoutModal terminal-failure toast 8s ("Retry from invoice page").** Critical workflow info — should be persistent inline error in Modal until user dismisses. L8, L16.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:365,397`
  <!-- meta: fix=render-inline-failure-state-in-modal -->

- [ ] WEB-UIUX-223. **[MAJOR] Multiple toasts can stack but ToastAvalancheGuard caps at 5 — 6th+ toast silently dropped.** Important error toasts can be lost. Per research: deduplication better than dropping. L8.
  `packages/web/src/main.tsx:418`
  <!-- meta: fix=deduplicate-by-id-instead-of-cap+drop -->

#### Loading & Feedback States

- [ ] WEB-UIUX-224. **[MINOR] No `aria-busy` on data tables during loading despite 10 callsites total.** Should mark `<tbody aria-busy="true">` while query.isLoading. L6, L12.


### Web UI/UX Audit — Pass 4 (2026-05-05, setup wizard + onboarding + components)

Setup wizard, onboarding, print, TV, photo-capture, reports sub-components, tickets components, team components.

#### Blockers/Trust

- [ ] WEB-UIUX-225. **[BLOCKER · BLOCKED] StepVerifyEmail advances on ANY 6-digit code.** Endpoint not wired — toast says "wired later" + advances. Bypasses email verification entirely. L16.
  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/setup/steps/StepVerifyEmail.tsx:42-51`
  <!-- meta: fix=feature-flag-or-block-advancement-until-SMTP-wired -->

- [ ] WEB-UIUX-226. **[MAJOR · BLOCKED] StepVerifyEmail "Resend code" is no-op toast — pretends to resend.** L16.
  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/setup/steps/StepVerifyEmail.tsx:53-55`

- [ ] WEB-UIUX-227. **[MAJOR] StepCashDrawer "Pop drawer (test)" is toast-only stub.** User configures cash drawer they can't verify. L16.
  `packages/web/src/pages/setup/steps/StepCashDrawer.tsx:84-88`

- [ ] WEB-UIUX-228. **[MAJOR] StepReview SENSITIVE_KEYS check uses label string, not key.** Mask never triggers — sensitive values like smtp_pass exposed in review. L7.
  `packages/web/src/pages/setup/steps/StepReview.tsx:115-122`
  <!-- meta: fix=iterate-by-key-not-label -->

- [ ] WEB-UIUX-229. **[MAJOR] StepRepairPricing preview tabs label "coming soon" but interactive.** Confused for broken. L16.
  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:367-481`

- [ ] WEB-UIUX-230. **[MAJOR] StepRepairPricing profit-per-repair badge uses hardcoded $40/$30/$20 parts cost.** Misleading anchor for new shop owners. L14.
  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:199-206`

- [ ] WEB-UIUX-231. **[MAJOR] CommissionPeriodLock single-click locks period (irreversible) with no confirm.** L16.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:158-175`
  <!-- meta: fix=two-step-or-modal-confirm -->

- [ ] WEB-UIUX-232. **[MAJOR] QcSignOffModal backdrop click closes — loses signature/photo/checklist work.** L5.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:184-187`
  <!-- meta: fix=confirm-discard-if-touched -->

- [ ] WEB-UIUX-233. **[MAJOR] QcSignOffModal: every checklist item must pass — no "failed" state, no reroute path.** L5.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:136-137`
  <!-- meta: fix=add-Failed-state-and-Reject-CTA -->

#### Setup Wizard A11y / Components

- [ ] WEB-UIUX-234. **[MAJOR] SetupPage missing `<main>` landmark, `<h1>`, skip link.** Screen readers land on plain region. L12.
  `packages/web/src/pages/setup/SetupPage.tsx:362-373`

- [ ] WEB-UIUX-235. **[MAJOR] WizardBreadcrumb decorative — no `aria-current="step"`, no `<nav>` landmark.** SR users get 3 unrelated label strings. L12.
  `packages/web/src/pages/setup/components/WizardBreadcrumb.tsx:67-103`

- [ ] WEB-UIUX-236. **[MAJOR] SkipToDashboard confirm panel not real dialog — no focus trap, no Esc.** L12.
  `packages/web/src/pages/setup/SkipToDashboard.tsx:21-46`

- [ ] WEB-UIUX-237. **[MAJOR] All wizard step Continue/Back buttons hand-rolled. Hover variants drift: hover:bg-primary-400 vs primary-500 vs primary-700.** L4, L9.
  20+ wizard step files
  <!-- meta: fix=migrate-to-canonical-Button-component -->

- [ ] WEB-UIUX-238. **[MAJOR] StepWelcome label has no `htmlFor` linking to input id.** Click target only via proximity. L7, L12.
  `packages/web/src/pages/setup/steps/StepWelcome.tsx:48-59`

- [ ] WEB-UIUX-239. **[MINOR] StepFirstLogin/StepSignup primary button `hover:bg-primary-500` (no visible hover).** Same color as default. L8.
  `packages/web/src/pages/setup/steps/StepFirstLogin.tsx:154`, `StepSignup.tsx:382`, `StepForcePassword.tsx:220`

- [ ] WEB-UIUX-240. **[MINOR] StepStoreInfo validation hides errors when field empty.** User can't tell what's blocking submit. L8.
  `packages/web/src/pages/setup/steps/StepStoreInfo.tsx:36-53`

- [ ] WEB-UIUX-241. **[MINOR] StepShopType "Skip" advances without recording intent.** Audit gap. L5.
  `packages/web/src/pages/setup/steps/StepShopType.tsx:106-109`

- [ ] WEB-UIUX-242. **[MINOR] StepImportHandoff cards have no explicit bg — invisible boundaries in dark mode unless hovered.** L10.
  `packages/web/src/pages/setup/steps/StepImportHandoff.tsx:62-70`

- [ ] WEB-UIUX-243. **[MINOR] 6+ wizard step files have empty `<div className="mb-6 flex justify-center">`.** Leftover from removed brand logo. L9.
  `StepFirstLogin.tsx:60-62`, `StepSignup.tsx:213-214`, `StepForcePassword.tsx:104-105`, `StepVerifyEmail.tsx:114-115`, `StepDone.tsx:67-68`

- [ ] WEB-UIUX-244. **[MINOR] StepFirstLogin default-credentials warning is `role="status"` (polite) — should be omitted or `role="alert"`.** L12.
  `packages/web/src/pages/setup/steps/StepFirstLogin.tsx:78-86`

- [ ] WEB-UIUX-245. **[MINOR] StepForcePassword strength heuristic rates passphrases "weak".** "correct horse battery staple" → weak. L8.
  `packages/web/src/pages/setup/steps/StepForcePassword.tsx:25-33`
  <!-- meta: fix=use-zxcvbn-or-length-bonus -->

- [ ] WEB-UIUX-246. **[MINOR] StepSignup + StepForcePassword use different password strength scales.** L3.
  Files: StepSignup.tsx:37-50 vs StepForcePassword.tsx:25-33
  <!-- meta: fix=extract-shared-gradePassword-helper -->

- [ ] WEB-UIUX-247. **[MINOR] StepSignup slug debounce uses race-discard not AbortController.** Out-of-order responses can flash wrong availability. L1.
  `packages/web/src/pages/setup/steps/StepSignup.tsx:88-125`

- [ ] WEB-UIUX-248. **[MINOR] StepSignup `setSlug(.toLowerCase())` on every keystroke breaks IME composition.** L7.
  `packages/web/src/pages/setup/steps/StepSignup.tsx:338`

- [ ] WEB-UIUX-249. **[MINOR] StepSignup derives shop name from email-local-part — "joe.smith" → "Joe.smith" on receipts.** L14.
  `packages/web/src/pages/setup/steps/StepSignup.tsx:152-159`

- [ ] WEB-UIUX-250. **[MINOR] StepTwoFactorSetup skip abandons in-flight TOTP secret with no server-side cancel.** L16.
  `packages/web/src/pages/setup/steps/StepTwoFactorSetup.tsx:125-131`

- [ ] WEB-UIUX-251. **[MINOR] StepRepairPricing defaults not seeded into pending on mount.** Going Back loses defaults. L5.
  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:181-194`

- [ ] WEB-UIUX-252. **[MINOR] StepFirstEmployees "PIN (opt.)" no security framing.** Users pick weak PINs (1234, 0000). L14, L16.
  `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx:349-372`

- [ ] WEB-UIUX-253. **[MINOR] StepFirstEmployees retry button has no debounce.** L1.
  `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx:214-218,388-396`

- [ ] WEB-UIUX-254. **[MINOR] StepCashDrawer IP input no format validation.** "192.168.1.50:porty" silently saves. L7.
  `packages/web/src/pages/setup/steps/StepCashDrawer.tsx:165-176`

- [ ] WEB-UIUX-255. **[MINOR] ExtrasHub.tsx is dead code from removed non-linear hub flow.** 287 lines unused. L3.
  `packages/web/src/pages/setup/ExtrasHub.tsx`
  <!-- meta: fix=delete-or-document-as-fallback -->

#### Onboarding

- [ ] WEB-UIUX-256. **[MAJOR] SpotlightCoach tooltip `role="dialog"` without focus trap or focus restore.** Tab escapes overlay. L12.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:170-176`

- [ ] WEB-UIUX-257. **[MAJOR] SpotlightCoach "Skip all tutorials" writes localStorage permanently — no UI to undo.** Stray click loses every tutorial forever. L6, L16.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:422-429`
  <!-- meta: fix=add-Re-enable-toggle-in-Settings-confirm-before-nuking -->

- [ ] WEB-UIUX-258. **[MINOR] SpotlightCoach Esc dismisses entire flow permanently — should pause.** L5.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:432-439`

- [ ] WEB-UIUX-259. **[MINOR] SpotlightCoach overlay `boxShadow: '0 0 0 9999px rgba(0,0,0,0.5)'` — fails on 4K+ zoomed-out browsers.** L11.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:99-112`
  <!-- meta: fix=use-svg-mask-with-rect-cutout -->

- [ ] WEB-UIUX-260. **[MINOR] SpotlightCoach hardcodes CARD_WIDTH=320 — overflows 320px viewport.** L11.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:138-166`

- [ ] WEB-UIUX-261. **[MINOR] DailyNudge close button `aria-label="Got it"` confuses with implicit "confirm".** L14.
  `packages/web/src/components/onboarding/DailyNudge.tsx:130-132`

- [ ] WEB-UIUX-262. **[MINOR] DailyNudge CTA dismisses + navigates — user navigates back, loses suggestion silently.** L5.
  `packages/web/src/components/onboarding/DailyNudge.tsx:100-103`

- [ ] WEB-UIUX-263. **[MINOR] GettingStartedWidget reduced-motion check skips confetti but no static "Done!" badge replacement.** L13.
  `packages/web/src/components/onboarding/GettingStartedWidget.tsx:166-205`

- [ ] WEB-UIUX-264. **[MINOR] SampleDataCard "Click again to confirm" same color/position — fat-finger destroys data.** L8.
  `packages/web/src/components/onboarding/SampleDataCard.tsx:103-115`

- [ ] WEB-UIUX-265. **[MINOR] ShortcutReferenceCard z-[60] but toasts may render above — modal hidden behind backdrop.** L11.
  `packages/web/src/components/onboarding/ShortcutReferenceCard.tsx:90`

#### Print / TV / Photo Capture

- [ ] WEB-UIUX-266. **[MAJOR] PhotoCapturePage hardcodes `bg-gray-900 text-white` — no light variant.** Daylight street use blinds user. L10.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:127-287`

- [ ] WEB-UIUX-267. **[MINOR] PhotoCapturePage uses raw `bg-gray-*` not `surface-*` tokens.** L4.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:127-287`

- [ ] WEB-UIUX-268. **[MINOR] PhotoCapturePage upload token in URL persists in browser history before strip.** L16.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:14-27`
  <!-- meta: fix=migrate-to-per-action-JWT -->

- [ ] WEB-UIUX-269. **[MINOR] PrintPage size-switching uses raw `<a href>` — full reload kills React Query caches.** L1, L15.
  `packages/web/src/pages/print/PrintPage.tsx:1051-1063`

- [ ] WEB-UIUX-270. **[MINOR] PrintPage sanitizePrintText/sanitizeTerms called inline per-render.** DOMPurify is non-trivial. L15.
  `packages/web/src/pages/print/PrintPage.tsx:231,402,429,672,712,902`

- [ ] WEB-UIUX-271. **[MINOR] PrintPage `<style>` injects color:#000/bg:#fff — flashes light against dark page surround.** L10.
  `packages/web/src/pages/print/PrintPage.tsx:1022-1038`

- [ ] WEB-UIUX-272. **[MINOR] TvDisplayPage `text-primary-950` on `bg-primary-600` ≈ 2.3:1 contrast — fails WCAG AA.** L12.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:128-133`

- [ ] WEB-UIUX-273. **[MINOR] TvDisplayPage lobby PII partial — first name initial shown but full device name "iPhone 14 Pro Max" exposes correlation.** L16.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:191-214`
  <!-- meta: fix=add-config-toggle-or-show-device-class-only -->

- [ ] WEB-UIUX-274. **[MINOR] TvDisplayPage no exponential backoff on retry — React Query default hammers servers.** L1.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:78-84`

#### Reports Sub-Components

- [ ] WEB-UIUX-275. **[MAJOR] All 6 reports tabs use raw chart hex colors (`#3b82f6` etc.) — don't auto-theme dark mode.** L10.
  `packages/web/src/pages/reports/components/*.tsx`
  <!-- meta: fix=define-chart-CSS-vars-in-design-system -->

- [ ] WEB-UIUX-276. **[MINOR] All 6 reports tabs duplicate identical loading/error block.** L3.
  <!-- meta: fix=extract-useReportQuery-hook -->

- [ ] WEB-UIUX-277. **[MINOR] DeviceModelsTab recomputes `Math.max(...rows.map(...))` per row — O(n²).** L15.
  `packages/web/src/pages/reports/components/DeviceModelsTab.tsx:75`

- [ ] WEB-UIUX-278. **[MINOR] StalledTicketsTab ticket IDs truncated with no tooltip or click-to-expand.** Operators can't see which tickets without hover. L5.
  `packages/web/src/pages/reports/components/StalledTicketsTab.tsx:105`

- [ ] WEB-UIUX-279. **[MINOR] Reports tooltip `border: '1px solid #374151'` raw hex — won't theme-switch.** L10.
  `CustomerAcquisitionTab.tsx:81`, `TechnicianHoursTab.tsx:86`

#### Tickets Components

- [ ] WEB-UIUX-280. **[MINOR] BenchTimer setInterval fires every 1s on hidden tabs.** No visibility guard. L1, L15.
  `packages/web/src/components/tickets/BenchTimer.tsx:100-105`

- [ ] WEB-UIUX-281. **[MINOR] BenchTimer Resume=green-600, Stop=red-600, Start=primary — inconsistent semantics.** L4.
  `packages/web/src/components/tickets/BenchTimer.tsx:218-263`

- [ ] WEB-UIUX-282. **[MINOR] CustomerHistorySidebar `isSafePhotoUrl` accepts `/uploads/../etc/passwd`.** Path traversal. L16.
  `packages/web/src/components/tickets/CustomerHistorySidebar.tsx:48-60`
  <!-- meta: fix=restrict-prefix-to-/uploads/-or-/api/files/ -->

- [ ] WEB-UIUX-283. **[MINOR] DefectReporterButton modal Esc closes but no focus restore to trigger.** L12.
  `packages/web/src/components/tickets/DefectReporterButton.tsx:94-99`

- [ ] WEB-UIUX-284. **[MINOR] DefectReporterButton + QcSignOffModal `URL.createObjectURL` blobs never `revokeObjectURL`-ed.** Memory leak. L15.
  `DefectReporterButton.tsx:88-91,203-206`, `QcSignOffModal.tsx:128-134,275-282`

- [ ] WEB-UIUX-285. **[MINOR] QcSignOffModal canvas width=600 height=140 fluid CSS — saved PNG blurry on retina.** L9.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:289-301`
  <!-- meta: fix=multiply-backing-store-by-devicePixelRatio -->

#### Team Components

- [ ] WEB-UIUX-286. **[MAJOR] CommissionPeriodLock card `bg-white` no dark variant.** White rectangle on dark page. L10.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:126,182-244`

- [ ] WEB-UIUX-287. **[MAJOR] CommissionPeriodLock modal `role="dialog"` but no focus trap.** L12.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:183-243`

- [ ] WEB-UIUX-288. **[MAJOR] MentionPicker outer `<div>` `bg-white border` — invisible against dark surfaces.** L10.
  `packages/web/src/components/team/MentionPicker.tsx:78-83`

- [ ] WEB-UIUX-289. **[MAJOR] TicketHandoffModal `bg-white rounded-lg shadow-xl` — same dark-mode gap.** L10.
  `packages/web/src/components/team/TicketHandoffModal.tsx:84-90`

- [ ] WEB-UIUX-290. **[MINOR] MentionPicker filter input no `dark:bg-*`/`dark:text-*` — white-on-white in dark.** L10.
  `packages/web/src/components/team/MentionPicker.tsx:91-99`

- [ ] WEB-UIUX-291. **[MINOR] TicketHandoffModal "reason" textarea no character counter or maxLength.** Server cap fails silently. L7.
  `packages/web/src/components/team/TicketHandoffModal.tsx:114-125`

- [ ] WEB-UIUX-292. **[MINOR] MentionPicker + TicketHandoffModal use separate cache keys for same `employees` data.** L15.
  Cache: `['employees','simple']` vs `['employees','simple-mention']`

#### Cross-Cutting (Pass 4)

- [ ] WEB-UIUX-293. **[MAJOR] Modal pattern duplicated 6+ more times in this pass.** QcSignOffModal, DefectReporterButton, TicketHandoffModal, CommissionPeriodLock dialog, ShortcutReferenceCard, SkipToDashboard confirm. Each subtly different (focus trap, Esc, click-outside, backdrop-blur). L3, L4.
  <!-- meta: fix=canonical-Modal-or-adopt-Radix-or-HeadlessUI -->

- [ ] WEB-UIUX-294. **[MAJOR] `text-primary-950` on `bg-primary-500/600` recurring — needs explicit WCAG AA contrast verification.** L12.
  StepWelcome:105, StepStoreInfo:200, StepShopType:215 + many more


### Web UI/UX Audit — Pass 5 (2026-05-05, keyboard shortcuts + error boundary + z-index)

#### Keyboard Shortcuts (WCAG 2.1.4)

- [ ] WEB-UIUX-295. **[MAJOR] WCAG 2.1.4 violation: single-key shortcuts F2/F3/F4/F6 + `?` not disableable.** No user setting to turn off. Conflicts with assistive tech, voice control software, browser extensions. WCAG Level A. L12.
  `packages/web/src/components/layout/AppShell.tsx:108-128`
  `packages/web/src/components/layout/Header.tsx:286`
  <!-- meta: fix=add-shortcut-toggle-in-Settings-Accessibility-tab -->

- [ ] WEB-UIUX-296. **[MAJOR] No `aria-keyshortcuts` attribute anywhere — 0 callsites.** Buttons/menus advertising shortcuts via tooltip text only. Screen readers don't announce shortcut bindings. L12.
  <!-- meta: fix=add-aria-keyshortcuts=F2-on-POS-link-etc -->

- [ ] WEB-UIUX-297. **[MINOR] Settings tab `Ctrl/Cmd+K` overlaps with global Header `Cmd+K` command palette.** Both fire on settings page — race condition. L5.
  `packages/web/src/pages/settings/components/SettingsGlobalSearch.tsx:55-67` vs `components/layout/Header.tsx:281`
  <!-- meta: fix=stop-propagation-or-coordinate-via-uiStore -->

#### Error Boundary Coverage

- [ ] WEB-UIUX-298. **[MAJOR] ErrorBoundary only at root + App.tsx + 2 places in TicketDetailPage.** 60+ routes, 90+ pages have NO route-level error boundary. Single render error in any page nukes entire app section, drops user to global crash screen. L6.
  `packages/web/src/main.tsx:364`, `packages/web/src/App.tsx:443`
  <!-- meta: fix=wrap-each-lazy-route-in-PageErrorBoundary -->

#### Z-Index Stacking War

- [ ] WEB-UIUX-299. **[MAJOR] No documented z-index scale — values 60, 80, 100, 101, 9998, 9999 + 105 Tailwind class usages.** Modal-on-modal (e.g. ConfirmDialog over QuickSmsModal) shows wrong layer. Toast over modal works only by accident. L9, L11.
  Pattern across web/src
  <!-- meta: fix=define-z-index-scale-in-design-tokens-modal:50-toast:60-banner:40 -->

- [ ] WEB-UIUX-300. **[MINOR] ShortcutReferenceCard `z-[60]` may render below toasts (`z-9999`).** L11.
  `packages/web/src/components/onboarding/ShortcutReferenceCard.tsx:90`


#### Cross-Cutting Pass 5

- [ ] WEB-UIUX-301. **[MINOR] 237 `Loader2 animate-spin` callsites — most duplicate centered-loading pattern.** L3, L4.
  <!-- meta: fix=extract-LoadingSpinner-component-or-Skeleton-defaults -->

- [ ] WEB-UIUX-302. **[MINOR] 39 `console.log/warn/error` callsites in production code.** Debug info may leak to browser console for users with DevTools open. L15, L16.
  <!-- meta: fix=use-logger-with-environment-gate -->

- [ ] WEB-UIUX-303. **[MAJOR] No layered error-boundary strategy per research best practice (2026).** "Catastrophic failure" UX — single boundary at root means broken widget kills entire session. Should follow per-widget pattern: Sidebar boundary, Header boundary, page boundary, widget boundary. L6.
  <!-- meta: fix=add-PageErrorBoundary-+-WidgetErrorBoundary-with-retry -->


#### Responsive Modern Techniques

- [ ] WEB-UIUX-304. **[MAJOR] Zero container queries (`@container`/`cqw`/`cqh`) in entire codebase.** Per 2026 research, container queries are essential for component-level responsive design — especially for CRM dashboards where same widget renders in different layouts (sidebar vs main grid). L11.
  Pattern across web/src
  <!-- meta: fix=adopt-container-queries-for-widgets-that-render-in-multiple-contexts -->

- [ ] WEB-UIUX-305. **[MINOR] `clamp()` fluid typography only on LandingPage.** Rest of app uses fixed Tailwind text sizes. Headings jump at breakpoints instead of scaling smoothly. L11.
  `packages/web/src/pages/landing/LandingPage.tsx:374,377,399,429,458` (only file)

- [ ] WEB-UIUX-306. **[MAJOR] Zero swipe gesture handlers across web app.** Per 2026 mobile CRM research, swipe-to-archive/swipe-to-act is expected. TicketListPage, CustomerListPage, InvoiceListPage all rely on tap-only on mobile. L11.
  <!-- meta: fix=add-swipe-handlers-on-list-rows-for-archive-quick-actions -->

- [ ] WEB-UIUX-307. **[MINOR] Only 4 `xl:` callsites vs 100 `sm:`, 97 `md:`, 50 `lg:`.** Large desktop (1280px+) under-optimized. CRM dashboards on widescreen don't take advantage of horizontal space. L11.
  <!-- meta: fix=audit-1280px-layouts-add-xl:-grid-cols-4-or-side-panels -->


### Web UI/UX Audit — Pass 6 (2026-05-05, hooks + utils + stores + api)

#### Trust + Security UX

- [ ] WEB-UIUX-308. **[MAJOR] `accessToken` stored in `localStorage` — XSS exposes bearer.** Comment in client.ts:24-31 acknowledges. 2026 SPA pattern: in-memory + httpOnly cookie. L16.
  `packages/web/src/stores/authStore.ts:95-171`, `packages/web/src/api/client.ts:180`
  <!-- meta: fix=migrate-to-in-memory-token+httpOnly-refresh -->

- [ ] WEB-UIUX-309. **[MAJOR] `useDraft` stores PII (customer notes/IMEIs/addresses) plaintext in localStorage.** Per-user namespace prevents cross-user bleed but value is plaintext. L16.
  `packages/web/src/hooks/useDraft.ts:201`
  <!-- meta: fix=AES-encrypt-with-per-session-key -->

- [ ] WEB-UIUX-310. **[MINOR] `superAdminClient` token in `sessionStorage` — same XSS exposure as localStorage within tab.** L16.
  `packages/web/src/api/client.ts:450-494`

- [ ] WEB-UIUX-311. **[MINOR] `formatApiError` doesn't auto-redact emails on unauthenticated surfaces.** Defers to caller; future leaks likely. L16.
  `packages/web/src/utils/apiError.ts:96-103`
  <!-- meta: fix=add-formatApiErrorPublic-variant-with-auto-redact -->

- [ ] WEB-UIUX-312. **[MINOR] `apiError.formatApiError` echoes server `code` verbatim in toast — no whitelist.** Hostile error envelope could leak `ERR_<sensitive>` strings. L16.
  `packages/web/src/utils/apiError.ts:50,99`

- [ ] WEB-UIUX-313. **[MINOR] `authStore.checkAuth` csrf_token cookie sniff via regex — brittle on name change.** Silently flips to never-authed UX. L16.
  `packages/web/src/stores/authStore.ts:139-144`

#### Loading + Cache + Stale Data

- [ ] WEB-UIUX-314. **[MAJOR] `useSettings` 5-minute staleTime hides config edits across tabs.** Manager edits store hours → other tabs render stale for up to 5 min. L6.
  `packages/web/src/hooks/useSettings.ts:41`
  <!-- meta: fix=invalidate-on-settings-mutation -->

- [ ] WEB-UIUX-315. **[MAJOR] `useDefaultTaxRate` falls back to 0% with no UI signal on query failure.** POS undercharges silently. L6.
  `packages/web/src/hooks/useDefaultTaxRate.ts:29-35`
  <!-- meta: fix=expose-isError-flag-render-banner -->

- [ ] WEB-UIUX-316. **[MAJOR] `formatCurrency` returns `$0.00` for null/undefined/NaN — looks like real zero.** Most invoice tables affected. L6.
  `packages/web/src/utils/format.ts:55-57`
  <!-- meta: fix=add-nullDisplay-param-default-emdash -->

- [ ] WEB-UIUX-317. **[MAJOR] `useWebSocket` 10-fail reconnect cap strands user offline until tab-blur/focus.** Laptop-wake on single tab = permanent "Realtime offline" banner. No `online` event listener. L1.
  `packages/web/src/hooks/useWebSocket.ts:533-587`
  <!-- meta: fix=add-window-online-event-listener -->

- [ ] WEB-UIUX-318. **[MAJOR] `useDraft` 100KB cap silently drops draft on overflow.** User assumes autosaved, loses work on reload. L7.
  `packages/web/src/hooks/useDraft.ts:194-198`
  <!-- meta: fix=expose-isDraftTooLarge-flag-warn-user -->

#### Forms + Feedback

- [ ] WEB-UIUX-319. **[MAJOR] `useUndoableAction` unmount fires destructive action on route nav.** Navigating away within 5s window = silent commit. L5.
  `packages/web/src/hooks/useUndoableAction.tsx:217-242`
  <!-- meta: fix=toast-on-nav-Action-committed -->

- [ ] WEB-UIUX-320. **[MAJOR] Global 5xx toast in client.ts says "Server error — please try again" with no request-id despite interceptor populating it 5 lines earlier.** Users can't quote ref to support. L8, L14.
  `packages/web/src/api/client.ts:364-370`
  <!-- meta: fix=use-formatApiError(error)-include-requestId -->

- [ ] WEB-UIUX-321. **[MAJOR] `useUndoableAction` Undo button no `aria-live` region.** SR users not told action will fire in 5s. L12.
  `packages/web/src/hooks/useUndoableAction.tsx:129-158`

- [ ] WEB-UIUX-322. **[MAJOR] `formatPhone` and `formatPhoneAsYouType` produce divergent canonical formats.** `+1 (XXX)-XXX-XXXX` vs `(XXX) XXX-XXXX`. Mixed display on same screen. L2, L9.
  `packages/web/src/utils/format.ts:184-188`
  `packages/web/src/utils/phoneFormat.ts:1-9`

- [ ] WEB-UIUX-323. **[MINOR] `formatPhone` partial-input falls through raw until 4th digit, then suddenly applies `+1 (XXX)-`.** Visual jump breaks input rhythm. L1.
  `packages/web/src/utils/format.ts:202-208`

- [ ] WEB-UIUX-324. **[MINOR] 409 conflict toast `id: 'conflict-409'` swallows subsequent unrelated 409 within ~3s.** L8.
  `packages/web/src/api/client.ts:382-394`
  <!-- meta: fix=dedupe-per-URL-not-global -->

- [ ] WEB-UIUX-325. **[MINOR] `useUndoableAction` pending toast lacks status icon.** Visually identical to generic toast. L8.
  `packages/web/src/hooks/useUndoableAction.tsx:129-158`

- [ ] WEB-UIUX-326. **[MINOR] `useWebSocket` `setWsOffline(true)` flips state but no toast/banner wired in this file.** Only visible if some component subscribes. L8.
  `packages/web/src/hooks/useWebSocket.ts:533-538`

#### Dark-Mode + Theme

- [ ] WEB-UIUX-327. **[MAJOR] `applyTheme` runs at module-import time but may execute AFTER React mount → flash-of-light-theme on dark users.** Canonical fix: inline `<script>` in index.html before React loads. L10.
  `packages/web/src/stores/uiStore.ts:59-62`
  Note: index.html:66-89 already has fallback script — verify it covers all paths

- [ ] WEB-UIUX-328. **[MINOR] `applyThemeWithFade` 320ms transition applied to `html.theme-transition *` — every element transitions, including expensive layout properties.** Heavy pages (POS/Reports) jank. L10, L13.
  `packages/web/src/stores/uiStore.ts:36-57`
  <!-- meta: fix=scope-transition-to-color-bg-only -->

- [ ] WEB-UIUX-329. **[MINOR] `safeColor` falls back to grey `#6b7280` regardless of theme.** Invisible on dark surfaces. L9, L10.
  `packages/web/src/utils/safeColor.ts:16`

- [ ] WEB-UIUX-330. **[NIT] Theme cross-fade 320ms with rapid toggles produces stutter — in-progress transition not cancelled.** L13.
  `packages/web/src/stores/uiStore.ts:38-57`

#### Copy + Confirms

- [ ] WEB-UIUX-331. **[MINOR] `confirmStore` default `confirmLabel = "Confirm"` — generic, doesn't tell user what executes.** Should force callers to provide a verb (Delete/Cancel/Send). L14.
  `packages/web/src/stores/confirmStore.ts:13,27,62`

- [ ] WEB-UIUX-332. **[MINOR] `LOGOUT_REQUIRED` toast: "Your session has expired. Please sign in again." reads as user fault.** Distinguish "Signed out from another tab" vs "expired due to inactivity". L14.
  `packages/web/src/stores/authStore.ts:300-302`

- [ ] WEB-UIUX-333. **[MINOR] `useUndoableAction` default pendingMessage `"Action scheduled"` — vague.** Should be `"Will run in 5s"` or force callers. L14.
  `packages/web/src/hooks/useUndoableAction.tsx:127`

- [ ] WEB-UIUX-334. **[MINOR] Generic 5xx toast copy passive — no concrete next step.** Should suggest "Try again, or contact support with ref XXXXXXXX". L14.
  `packages/web/src/api/client.ts:369`

- [ ] WEB-UIUX-335. **[MINOR] `confirmStore` message field plain string only — no JSX/markup support.** Confirms can't include semantic markup for SR (lists, item-name emphasis). L12.
  `packages/web/src/stores/confirmStore.ts:11-21`

#### Components / Duplicates

- [ ] WEB-UIUX-336. **[MINOR] Three near-identical JWT decoders.** `client.ts:122-142`, `client.ts:427-441`, `authStore.ts:241-249` — different error tolerance and length guards. L3.
  <!-- meta: fix=consolidate-into-utils/jwt.ts -->

- [ ] WEB-UIUX-337. **[MINOR] Idempotency-key fallback `crypto.randomUUID() ?? "prefix-Date.now()-Math.random()"` duplicated across 6 endpoints.** L3.
  `packages/web/src/api/endpoints.ts:278-283,287-292,712-722,740-748,753-761,1177-1180`

- [ ] WEB-UIUX-338. **[MINOR] `useUndoableAction` Undo button hand-rolls Tailwind classes — not the Button component.** Different padding/hover/dark-mode. L4.
  `packages/web/src/hooks/useUndoableAction.tsx:131-156`

#### Performance

- [ ] WEB-UIUX-339. **[MINOR] `formatCurrency` rebuilds `Intl.NumberFormat` per call when `currencyOverride`/`localeOverride` is passed.** 100-row invoice list = 100 formatter constructions. L15.
  `packages/web/src/utils/format.ts:46-66`
  <!-- meta: fix=memoize-by-code+locale-key -->

- [ ] WEB-UIUX-340. **[MINOR] `useDraft.wipeAllDrafts` + `authStore` dismiss-key sweep both walk full localStorage on logout.** Two iterations. L15.
  `packages/web/src/hooks/useDraft.ts:42-56`, `packages/web/src/stores/authStore.ts:185-200`

- [ ] WEB-UIUX-341. **[MINOR] `formatCurrency` console.errors per-call on unknown code → hundreds of errors per render.** L15, L16.
  `packages/web/src/utils/format.ts:60-66`
  <!-- meta: fix=rate-limit-or-single-warning -->

- [ ] WEB-UIUX-342. **[NIT] `useWebSocket` heartbeat sends ping every 30s on idle dashboards — battery drain.** L15.
  `packages/web/src/hooks/useWebSocket.ts:420-440`

- [ ] WEB-UIUX-343. **[NIT] `buildInvalidationMap` rebuilds on every `useWebSocket` mount — should be module-scope const.** L15.
  `packages/web/src/hooks/useWebSocket.ts:75-255,291`

- [ ] WEB-UIUX-344. **[NIT] `useDismissible` per-user dismiss keys not wiped after timeout — only on logout.** Shared kiosk = sticky banners. L16.
  `packages/web/src/hooks/useDismissible.ts:35-72`

#### A11y + Misc

- [ ] WEB-UIUX-345. **[NIT] `formatApiError` request-id 8-char prefix not selectable as unit, no "Copy ref" button.** L8.
  `packages/web/src/utils/apiError.ts:96-103`


### Web UI/UX Audit — Pass 7 (2026-05-05, portal + voice + communications + billing components)

#### Portal — Customer-Facing

- [ ] WEB-UIUX-346. **[BLOCKER] LanguageSwitcher writes `dark` class to `document.body` not `<html>`.** Tailwind `darkMode: 'class'` selector compiles against `<html class="dark">` — toggle may be no-op. L10.
  `packages/web/src/pages/portal/components/LanguageSwitcher.tsx:27-29`
  <!-- meta: fix=use-document.documentElement.classList.toggle -->

- [ ] WEB-UIUX-347. **[MAJOR] CustomerPortalPage status pill `style={{backgroundColor: safeColor}}` + hardcoded `text-white` — light status colors fail contrast.** L9, L12.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:386-390`
  <!-- meta: fix=compute-luminance-pick-text-color -->

- [ ] WEB-UIUX-348. **[MAJOR] Widget "Track My Repair" error block has no `role="alert"`/`aria-live`.** SR users silent on validation failure. L12, L8.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:320-322`

- [ ] WEB-UIUX-349. **[MAJOR] LanguageSwitcher 6 buttons (EN/ES/A-/A+/contrast/dark) lack `focus-visible:ring`.** Keyboard users no focus indicator. L12.
  `packages/web/src/pages/portal/components/LanguageSwitcher.tsx:116-166`

- [ ] WEB-UIUX-350. **[MAJOR] PhotoGallery has no full-size lightbox view.** 96x96 thumbnails only — customers can't inspect repair work. L5.
  `packages/web/src/pages/portal/components/PhotoGallery.tsx:128-148`

- [ ] WEB-UIUX-351. **[MAJOR] StatusTimeline still uses raw `bg-gray-*`/`text-gray-*`/`border-gray-*` not `surface-*` tokens.** L9, L10.
  `packages/web/src/pages/portal/components/StatusTimeline.tsx:59,69-91`

- [ ] WEB-UIUX-352. **[MINOR] Auto-prompt review modal opens automatically 2.5s after pickup with sessionStorage gate.** Pushy. Should be user-initiated toast with CTA. L5, L14.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:519-528`

- [ ] WEB-UIUX-353. **[MINOR] Token tail leaks last 6 chars in toast — enumerable info, no benefit.** L16.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:73,88,93`
  <!-- meta: fix=use-server-supplied-correlation-id -->

- [ ] WEB-UIUX-354. **[MINOR] `clearPortalSecurityTokens` not called on inner-request 401/403.** Widget keeps bad portal_token until handleReset. L16, L6.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:269-294`

- [ ] WEB-UIUX-355. **[MINOR] FaqTooltip `mousedown` outside-close — keyboard Tab can't close popover.** L12.
  `packages/web/src/pages/portal/components/FaqTooltip.tsx:20-29`
  <!-- meta: fix=add-focusin-document-listener -->

- [ ] WEB-UIUX-356. **[MINOR] FaqTooltip `bg-surface-900 dark:bg-surface-700` — dark variant LIGHTER than dark page bg.** Tooltip floats incorrectly. L10.
  `packages/web/src/pages/portal/components/FaqTooltip.tsx:50`

- [ ] WEB-UIUX-357. **[MINOR] PhotoGallery alt text identical for every photo: "Repair photo".** SR repeats same string. L12.
  `packages/web/src/pages/portal/components/PhotoGallery.tsx:138`
  <!-- meta: fix=encode-before-after+order+date-in-alt -->

- [ ] WEB-UIUX-358. **[MINOR] QueuePosition `ordinal()` only handles English ("4th").** Spanish locale renders English ordinals. L14, L12.
  `packages/web/src/pages/portal/components/QueuePosition.tsx:22-26,71`

- [ ] WEB-UIUX-359. **[MINOR] CustomerPortalPage progress bar div has no `role="progressbar"`/`aria-valuenow`.** L12.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:393-407`

- [ ] WEB-UIUX-360. **[MINOR] CustomerPortalPage ResizeObserver postMessages parent on every pixel change — no throttle.** Floods host frame. L15.
  `packages/web/src/pages/portal/CustomerPortalPage.tsx:133-142,260-267`

- [ ] WEB-UIUX-361. **[MINOR] LanguageSwitcher `applyContrast` writes body class but no CSS imported in this file.** Silent no-op if portal-enrichment.css not bundled with route. L9.
  `packages/web/src/pages/portal/components/LanguageSwitcher.tsx:5-7,23-25`

#### Communications Components

- [ ] WEB-UIUX-362. **[BLOCKER] BulkSmsModal no focus trap, no initial focus.** Esc wired, Tab can land outside. L12.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:111-128`

- [ ] WEB-UIUX-363. **[BLOCKER] ScheduledSendModal no focus trap.** L12.
  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx:104-123`

- [ ] WEB-UIUX-364. **[MAJOR] BulkSmsModal "Send to N" destructive but no typing-to-confirm for count > 50.** L16, L8.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:215-222`

- [ ] WEB-UIUX-365. **[MAJOR] BulkSmsModal segment buttons not `radiogroup`/`role="radio"`.** Mutually exclusive but SR doesn't know. L12.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:142-164`

- [ ] WEB-UIUX-366. **[MAJOR] CannedResponseHotkeys binds Cmd+1..3 (macOS browser tab switch shortcut).** Conflicts with browser native. L1, L13.
  `packages/web/src/pages/communications/components/CannedResponseHotkeys.tsx:58-60`
  <!-- meta: fix=use-Ctrl-only-or-Alt-1..3 -->

- [ ] WEB-UIUX-367. **[MAJOR] ConversationAssignee fetches ALL conversations to find one row's assignee.** N+1 — repeats per row. L15.
  `packages/web/src/pages/communications/components/ConversationAssignee.tsx:33-39`
  <!-- meta: fix=add-/inbox/conversation/:phone-or-prop-drill-list -->

- [ ] WEB-UIUX-368. **[MAJOR] ConversationTags fetches all conversations per phone — same N+1 as 367.** L15.
  `packages/web/src/pages/communications/components/ConversationTags.tsx:34-40`

- [ ] WEB-UIUX-369. **[MAJOR] SentimentBadge `EMOJI` map values are LITERAL TEXT 'angry'/'happy' — renders "angry Angry" inside pill.** L9, L4.
  `packages/web/src/pages/communications/components/SentimentBadge.tsx:22-27,61`
  <!-- meta: fix=use-actual-emoji-glyphs-or-remove-prefix-span -->

- [ ] WEB-UIUX-370. **[MAJOR] ScheduledSendModal validates date in component-local TZ but submits via `toISOString()`.** No TZ name shown. L14, L16.
  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx:66-85`

- [ ] WEB-UIUX-371. **[MINOR] BulkSmsModal backdrop click during preview discards 5-min confirmation_token.** L8, L5.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:117,121`

- [ ] WEB-UIUX-372. **[MINOR] ConversationTags suggestions only render `tags.length === 0`.** Once 1 tag exists, no more suggestions. L5.
  `packages/web/src/pages/communications/components/ConversationTags.tsx:124`

- [ ] WEB-UIUX-373. **[MINOR] FailedSendRetryList truncated to first 10 with no "show more".** L5.
  `packages/web/src/pages/communications/components/FailedSendRetryList.tsx:94`

- [ ] WEB-UIUX-374. **[MINOR] FailedSendRetryList "attempt #${retry_count + 1}" reads "attempt #1" before any retry.** L14.
  `packages/web/src/pages/communications/components/FailedSendRetryList.tsx:109-111`

- [ ] WEB-UIUX-375. **[MINOR] OffHoursAutoReplyToggle `mutate` fires before local state knows — visual switch flickers.** L13, L6.
  `packages/web/src/pages/communications/components/OffHoursAutoReplyToggle.tsx:74-78`
  <!-- meta: fix=optimistic-update-with-onMutate-rollback-onError -->

- [ ] WEB-UIUX-376. **[MINOR] QuickSmsAttachmentButton preview blob URL not revoked on parent unmount mid-upload.** L15.
  `packages/web/src/pages/communications/components/QuickSmsAttachmentButton.tsx:76-79,61`

- [ ] WEB-UIUX-377. **[MINOR] TeamInboxHeader avg-SLA pill `hidden md:flex`.** Mobile operators see no SLA pulse. L11.
  `packages/web/src/pages/communications/components/TeamInboxHeader.tsx:106-113`

- [ ] WEB-UIUX-378. **[MINOR] TemplateAnalyticsCard table missing `<caption>` for SR.** L12.
  `packages/web/src/pages/communications/components/TemplateAnalyticsCard.tsx:67-105`

- [ ] WEB-UIUX-379. **[MINOR] ConversationAssignee popover no Esc handler.** L12.
  `packages/web/src/pages/communications/components/ConversationAssignee.tsx:99-138`

#### Voice

- [ ] WEB-UIUX-380. **[BLOCKER] RecordingConsentDialog no focus trap, no Esc.** L12.
  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:23-72`

- [ ] WEB-UIUX-381. **[MAJOR] VoiceCallsListPage table rows have no link/click affordance to call detail.** Dead-end UX. L5.
  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:160-217`

- [ ] WEB-UIUX-382. **[MINOR] STATUS_COLORS missing entries for "queued"/"ringing"/"canceled" Twilio statuses.** L6.
  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:81-87`

#### Billing Pages + Components

- [ ] WEB-UIUX-383. **[BLOCKER] AgingReportPage no dark-mode classes anywhere — pure light-mode page.** L10.
  `packages/web/src/pages/billing/AgingReportPage.tsx:100-209`

- [ ] WEB-UIUX-384. **[BLOCKER] PaymentLinksPage table hardcodes `text-gray-*`/`bg-gray-50` not dark-aware.** L10, L9.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:276-323`

- [ ] WEB-UIUX-385. **[BLOCKER] FinancingButton stub modal `bg-white p-6 shadow-xl` no dark variant.** L10.
  `packages/web/src/components/billing/FinancingButton.tsx:81-107`

- [ ] WEB-UIUX-386. **[BLOCKER] FinancingButton modal no focus trap, no `aria-describedby`.** L12.
  `packages/web/src/components/billing/FinancingButton.tsx:81-108`

- [ ] WEB-UIUX-387. **[BLOCKER] DepositCollectModal no focus trap.** L12.
  `packages/web/src/pages/billing/DepositCollectModal.tsx:73-89`

- [ ] WEB-UIUX-388. **[BLOCKER] InstallmentPlanWizard whole component lacks dark-mode classes.** L10.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:97-197`

- [ ] WEB-UIUX-389. **[MAJOR] AgingReportPage row checkboxes no `aria-label`.** SR users hear unlabeled checkbox. L12.
  `packages/web/src/pages/billing/AgingReportPage.tsx:174-178`

- [ ] WEB-UIUX-390. **[MAJOR] PaymentLinksPage form labels invisible — placeholder only, disappears on focus.** L7, L12.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:208-248`

- [ ] WEB-UIUX-391. **[MAJOR] PaymentLinksPage `cancelMutation` fires immediately — no confirm guard.** L16, L8.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:309-318`
  <!-- meta: fix=use-confirmStore -->

- [ ] WEB-UIUX-392. **[MAJOR] FinancingButton: "Pay over time with Affirm" CTA + ComingSoonBadge legally implies availability.** L14, L16.
  `packages/web/src/components/billing/FinancingButton.tsx:69-78`

- [ ] WEB-UIUX-393. **[MAJOR] InstallmentPlanWizard typed-name acceptance accepts "abc" (≥3 chars) as legal signature.** L7, L16.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:81-94,170-176`

- [ ] WEB-UIUX-394. **[MAJOR] InstallmentPlanWizard amber acceptance card no dark variants — `text-amber-900`/`bg-amber-50` only.** L10, L12.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:163-177`

- [ ] WEB-UIUX-395. **[MINOR] AgingReportPage no empty state — empty buckets + headers shown when zero overdue.** L8.
  `packages/web/src/pages/billing/AgingReportPage.tsx:104-128`

- [ ] WEB-UIUX-396. **[MINOR] AgingReportPage bucket cards lack `aria-pressed={isSelected}`.** L12.
  `packages/web/src/pages/billing/AgingReportPage.tsx:109-127`

- [ ] WEB-UIUX-397. **[MINOR] InstallmentPlanWizard schedule uses local-time `setDate(d.getDate() + i*N)` — DST shifts last installment by 1h.** L6.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:67-78`
  <!-- meta: fix=compute-in-UTC-noon-or-date-fns/addDays -->

- [ ] WEB-UIUX-398. **[MINOR] DepositCollectModal `<input type="number" step="0.01">` accepts negatives — only blocked client-side after submit.** L7.
  `packages/web/src/pages/billing/DepositCollectModal.tsx:99-106`

- [ ] WEB-UIUX-399. **[MINOR] PaymentLinksPage Token column shows `row.token.slice(0,12)…` — rows with same prefix indistinguishable.** L2.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:295`

- [ ] WEB-UIUX-400. **[MINOR] PaymentLinksPage feature-disabled banner generic — empty state doesn't say "and you can't create new ones until provider configured".** L8.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:289-291`

- [ ] WEB-UIUX-401. **[MINOR] InstallmentPlanWizard schedule preview no `<tfoot>` total row — verification of `sum === totalCents` impossible at glance.** L16.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:140-161`

- [ ] WEB-UIUX-402. **[MINOR] RefundReasonPicker grid-cols-2 with long labels wraps awkwardly on phones.** L11.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:62`

- [ ] WEB-UIUX-403. **[MINOR] QrReceiptCode fallback renders empty placeholder (only enters when `!value`).** L8.
  `packages/web/src/components/billing/QrReceiptCode.tsx:21-43`

#### Super-Admin Deeper

- [ ] WEB-UIUX-404. **[MAJOR] TenantsListPage no pagination — large fleets load all tenants in one query.** L15.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:435-545`

- [ ] WEB-UIUX-405. **[MAJOR] ImpersonateConfirmModal focus not auto-moved to slug input on mount.** L12.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:311-417`

- [ ] WEB-UIUX-406. **[MAJOR] TenantRow "Log in as" same primary color as "Sign out" — destructive-cross-boundary indistinguishable from safe.** L9, L16.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:246-259`

- [ ] WEB-UIUX-407. **[MINOR] SuperAdminLoginForm TOTP input doesn't autofocus on second step.** L1.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:118-149`

- [ ] WEB-UIUX-408. **[MINOR] ImpersonateConfirmModal `slugMatches` rejects trailing whitespace silently.** L8.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:297-299`

- [ ] WEB-UIUX-409. **[MINOR] TenantsListPage table no sortable columns.** L5.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:518-541`

- [ ] WEB-UIUX-410. **[MINOR] SuperAdminLoginForm Continue/Verify buttons no semantic differentiation across 2FA steps.** L2.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:91-117`

- [ ] WEB-UIUX-411. **[NIT] TenantsListPage `db_size_mb` rendered as raw "MB" — no GB rollup for large tenants.** L14.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:242`

#### Cross-Cutting (Pass 7)

- [ ] WEB-UIUX-412. **[BLOCKER] 6+ modals across Pass 7 lack focus trap.** BulkSmsModal, ScheduledSendModal, RecordingConsentDialog, DepositCollectModal, FinancingButton stub, ImpersonateConfirmModal. L12, L4.
  <!-- meta: fix=shared-Modal-primitive-with-focus-trap+Esc+scroll-lock -->

- [ ] WEB-UIUX-413. **[MAJOR] Multiple modals close on backdrop click without confirming dirty input.** DepositCollectModal, BulkSmsModal, ScheduledSendModal, FinancingButton stub. L5, L8.

- [ ] WEB-UIUX-414. **[MAJOR] Loose `any` casts on API responses across 3 components mask schema drift.** BulkSmsModal `tplData?.data as any`, FailedSendRetryList, ConversationAssignee. L4, L15.
  <!-- meta: fix=zod-validate-at-API-client-boundary -->

- [ ] WEB-UIUX-415. **[MINOR] At least 4 different loading strings: "...", "Loading...", "Loading…", "Looking up…", "Sending…".** L14.
  Pattern across web/src
  <!-- meta: fix=standardize-on-shared-LoadingText-component -->

- [ ] WEB-UIUX-416. **[MINOR] Toast strings English-only across staff surfaces.** Portal has i18n; Communications/Billing/Super-admin don't translate. L14.

- [ ] WEB-UIUX-417. **[MINOR] Date inputs (`<input type="date">`) used without TZ disclaimer.** PaymentLinks `expires_at`, InstallmentPlanWizard `startDate`. L7, L14.

- [ ] WEB-UIUX-418. **[MINOR] `text-primary-950` text-on-primary works only for warm-cream scheme — unreadable if primary changes to dark color.** L9.
  <!-- meta: fix=introduce-text-on-primary-semantic-token -->

- [ ] WEB-UIUX-419. **[MINOR] Components return `null` for empty/error states — silent layout shift, no user-visible reason.** TechCard, TrustBadges, QueuePosition. L8, L11.

- [ ] WEB-UIUX-420. **[NIT] Spanish a11y labels missing verbs.** "Alto contraste" should be "Alternar alto contraste". L14, L12.
  `packages/web/src/pages/portal/i18n.ts:152-154`

- [ ] WEB-UIUX-421. **[NIT] `review.title` key used as both modal title and button label — context mismatch.** L14.
  `packages/web/src/pages/portal/i18n.ts:53,121`


#### Cross-Cutting (table a11y)

- [ ] WEB-UIUX-422. **[MAJOR] WCAG 1.3.1 / sortable table a11y: 52 tables across web, ZERO `aria-sort` and ZERO `role="columnheader"`.** Sortable list pages (TicketListPage, CustomerListPage, EstimateListPage, LeadListPage, InventoryListPage) all have sortable headers but SR users get no sort-state announcement. L12.
  Pattern across all list pages
  <!-- meta: fix=add-aria-sort=ascending|descending|none-on-sortable-th -->


### Web UI/UX Audit — Pass 8 (2026-05-05, USABILITY FLOW: "Process Refund")

Walking real user flow: cashier wants to refund customer. Entry point: invoice detail page.

#### Refund Flow

- [ ] WEB-UIUX-423. **[BLOCKER usability] "Credit Note" label hides the refund function from non-accountant users.** Cashiers/shop owners say "refund" — they don't recognize "Credit Note" as the right button. Most click "Void" first (red, more prominent) thinking it's the refund, then realize they wanted partial refund and now full transaction is voided. Lost time + lost transaction history. L14, L1, L2.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377` (button), `:748` (modal title), `:800` (submit label)
  <!-- meta: fix=rename-to-Refund-or-Issue-Refund-keep-credit-note-as-secondary-explanation -->

- [ ] WEB-UIUX-424. **[MAJOR usability] Visual hierarchy reversed — "Void" (red destructive) more prominent than "Credit Note" (amber, the actual refund).** Refund is the routine flow; void is rare. Amber implies caution but action is routine; red void implies last-resort. Operator's eye lands on red first. L2, L9.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377-388`
  <!-- meta: fix=neutral-secondary-button-for-Refund-keep-Void-tertiary-or-overflow-menu -->

- [ ] WEB-UIUX-425. **[MAJOR usability] Modal description "This will reduce the outstanding balance" is wrong when invoice fully paid.** If customer already paid in full (amount_due = 0), there's no balance to reduce — refund creates customer credit balance OR refunds to original tender. Modal doesn't explain which. Operator confused about destination of money. L14, L8, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:753-755`
  <!-- meta: fix=conditional-copy-based-on-amount_due-state -->

- [ ] WEB-UIUX-426. **[MAJOR usability] Modal does NOT tell operator where the refunded money goes.** Back to original card? Cash from drawer? Customer credit? Operator submits without knowing. If customer paid by card and expects card refund but system issues store credit, customer disputes. L8, L16, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:738-805`
  <!-- meta: fix=show-refund-destination-before-confirm-Will-refund-$X-to-Visa-ending-1234 -->

- [ ] WEB-UIUX-427. **[MAJOR usability] No flow for "refund all" — operator must look up `amount_paid`, type it manually as "Credit Amount".** Common case (full refund of paid invoice) requires manual transcription with no helper button. L1, L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`
  <!-- meta: fix=add-Refund-Full-Amount-quick-button-or-Max-link -->

- [ ] WEB-UIUX-428. **[MAJOR usability] Void copy "This cannot be undone" inaccurate — partial refund (Credit Note) IS available for paid invoices.** Operator reading "cannot be undone" may panic-void thinking nothing else available. L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:810`
  <!-- meta: fix=Voiding-restores-stock-and-marks-all-payments-voided-for-partial-refund-use-Refund-instead -->

- [ ] WEB-UIUX-429. **[MAJOR usability] Component file named `RefundReasonPicker` but UI everywhere says "Credit".** Engineers know it's a refund; users see "Credit Note". Code/UI mismatch suggests engineers know "refund" is the right word but bowed to accounting. L14.
  `packages/web/src/components/billing/RefundReasonPicker.tsx`

- [ ] WEB-UIUX-430. **[MAJOR usability] Submit button "Create Credit Note" doesn't tell operator final outcome.** Should say "Refund $50.00 to original payment method" with computed amount + destination. L8, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:800`

- [ ] WEB-UIUX-431. **[MINOR usability] After successful credit-note, no on-screen confirmation of refund destination.** Just toast "success". Operator can't tell customer "refunded $50 to your Visa ending 1234". Receipt printout is 4-5 clicks away. L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-180`
  <!-- meta: fix=success-modal-with-refund-summary+print-receipt-CTA -->

- [ ] WEB-UIUX-432. **[MINOR usability] Refund modal hardcodes `$` symbol — multi-currency tenants see wrong glyph.** Already flagged (WEB-UIUX-71) but ALSO appears at line 760 `<span>$</span>` prefix and line 766 placeholder + line 777 max display. L9, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:760,766,777`

- [ ] WEB-UIUX-433. **[MINOR usability] No way to refund directly from POS sale — operator must navigate to Invoices → find invoice → open detail → click Credit Note.** ~5 clicks for what should be 2-tap operation in-store. L1, L5.
  Cross-reference: `packages/web/src/pages/unified-pos/` no refund affordance from past-sales view
  <!-- meta: fix=add-Refund-button-to-recent-sales-list-in-POS -->

#### Cross-Cutting (Pass 8)

- [ ] WEB-UIUX-434. **[MAJOR usability pattern] Many destructive flows label by ENGINEERING action, not USER intent.** "Void" = engineering noun. "Credit Note" = accounting noun. Users think in verbs: refund, cancel, undo. Audit all action labels for engineering-vs-user-intent mismatch. L14.
  Audit needed: search for buttons named: Void, Reverse, Reconcile, Reissue, Mutate, etc.

- [ ] WEB-UIUX-435. **[MAJOR usability pattern] Modal descriptions don't show outcome state — only action.** "Issue a credit note" tells operator the verb; doesn't preview "Customer's Visa ending 1234 will be refunded $50 within 3 business days." Outcome-preview reduces error. L8, L14.
  Cross-cutting modal pattern


### Web UI/UX Audit — Pass 8 (2026-05-05, shared/layout/tickets/tv/print/team)

#### Shared Modal Primitives

- [ ] WEB-UIUX-436. **[BLOCKER] No shared `<Modal>` primitive — 9 sites in this pass each hand-roll backdrop+role+focus+Esc.** ConfirmDialog, CommandPalette, PinModal, UpgradeModal, PrintPreviewModal, QuickSmsModal, MergeDialog (TicketDetail), ReloadModal (gift-card), NewShiftModal. Inevitable focus/scroll/Esc drift. L4, L12.
  <!-- meta: fix=extract-Modal-with-portal+focus-trap+scroll-lock+restore-focus -->

- [ ] WEB-UIUX-437. **[BLOCKER] CommandPalette no focus trap.** Tab cycles to host page chrome behind backdrop. Esc handled on input only — focus on a result row + Esc closes via list keydown delegation but Tab after last result escapes. L12.
  `packages/web/src/components/shared/CommandPalette.tsx:325-342,444-453`

- [ ] WEB-UIUX-438. **[BLOCKER] UpgradeModal no focus trap, no initial focus, no focus-restore.** Open via planStore from anywhere → Tab leaks behind backdrop, focus lands wherever it was before. L12.
  `packages/web/src/components/shared/UpgradeModal.tsx:13-20,77-90`

- [ ] WEB-UIUX-439. **[BLOCKER] PrintPreviewModal no focus trap, no initial focus.** L12.
  `packages/web/src/components/shared/PrintPreviewModal.tsx:62-68,69-78`

- [ ] WEB-UIUX-440. **[BLOCKER] QuickSmsModal no focus trap. `autoFocus` lands on textarea but Tab cycles out.** L12.
  `packages/web/src/components/shared/QuickSmsModal.tsx:101-114,179-187`

- [ ] WEB-UIUX-441. **[BLOCKER] Body-scroll-lock missing on every modal in this pass.** Backdrop intercepts clicks but `<body>` keeps scrolling under modal — keyboard space/PageDown scrolls page behind dialog. L4, L11.
  9 sites
  <!-- meta: fix=add-useScrollLock-or-data-attr-toggle-on-body -->

- [ ] WEB-UIUX-442. **[MAJOR] ConfirmDialog focus restore tied to cleanup of `useEffect([open, requireTyping])`.** Toggling `requireTyping` while open re-runs cleanup → focus restored to original element while modal still showing. L12.
  `packages/web/src/components/shared/ConfirmDialog.tsx:36-57`

- [ ] WEB-UIUX-443. **[MAJOR] ConfirmDialog focus-trap selector misses `<a>`, `<select>`, `<textarea>`, `[contenteditable]`.** Empirically only buttons + inputs in current usage; trap will leak if any consumer adds a link or textarea. L12.
  `packages/web/src/components/shared/ConfirmDialog.tsx:19`

- [ ] WEB-UIUX-444. **[MAJOR] CommandPalette uses `'k'` literal not `e.key.toLowerCase()`.** Cmd+Shift+K (DevTools toggle on Firefox) bypasses preventDefault but if user has CapsLock on, Cmd+K does nothing. L1.
  `packages/web/src/components/layout/Header.tsx:281`

- [ ] WEB-UIUX-445. **[MAJOR] PinModal Cancel button is the closest focus target after lockout.** Once `isLocked`, the disabled input keeps focus but typing is no-op — user has no clear indication that Tab→Cancel is the only way out. L12, L8.
  `packages/web/src/components/shared/PinModal.tsx:213-222`

- [ ] WEB-UIUX-446. **[MAJOR] CommandPalette page-jump match is global substring on aliases — `q="po"` lights up "Pos", "Purchase Orders" (alias `po`), "Pipeline".** No fuzzy/prefix preference. L5.
  `packages/web/src/components/shared/CommandPalette.tsx:83-101`

- [ ] WEB-UIUX-447. **[MAJOR] CommandPalette stale-search guard uses `reqSeq.current` ref but doesn't cancel underlying axios request.** Slow-network responses still fly + parsed. Wasted bandwidth + minor server pressure. L15.
  `packages/web/src/components/shared/CommandPalette.tsx:266-301`
  <!-- meta: fix=AbortController-passed-to-axios-signal -->

- [ ] WEB-UIUX-448. **[MINOR] ConfirmDialog backdrop-click cancels even with required-typing in progress.** Half-typed confirm text discarded silently. L8.
  `packages/web/src/components/shared/ConfirmDialog.tsx:93`

- [ ] WEB-UIUX-449. **[MINOR] PrintPreviewModal `iframe.onload` polls every 200 ms for 8 s checking for `[data-print-ready]` — no `data-print-ready` actually emitted by PrintPage.** Fallback path always taken. L13, L4.
  `packages/web/src/components/shared/PrintPreviewModal.tsx:39-56`
  vs `packages/web/src/pages/print/PrintPage.tsx` — no `data-print-ready` attribute

- [ ] WEB-UIUX-450. **[MINOR] UpgradeModal close button absolute-positioned `right-4 top-4` overlaps gradient header text on narrow viewports.** L11.
  `packages/web/src/components/shared/UpgradeModal.tsx:91-98,100-109`

- [ ] WEB-UIUX-451. **[MINOR · BLOCKED] QuickSmsModal `MAX_CHARS=160` hardcoded — Twilio SMS-segment is 153 for concatenated multi-part GSM-7.** Counter shows "(2 msgs)" at 161 instead of 154. L14, L4.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/components/shared/QuickSmsModal.tsx:34,190-192`

- [ ] WEB-UIUX-452. **[MINOR] CommandPalette `kbd` ESC hint hidden below `sm` — mobile users see no close hint.** L11.
  `packages/web/src/components/shared/CommandPalette.tsx:480-482`

- [ ] WEB-UIUX-453. **[MINOR] CommandPalette `useRecent(term)` sets query but doesn't trigger immediate fetch — 300 ms debounce delay still applies.** Looks broken on click. L5.
  `packages/web/src/components/shared/CommandPalette.tsx:354-357`

- [ ] WEB-UIUX-454. **[MINOR] EmptyState component has no `role="status"` — SR users miss "no results" announcement on async results swap.** L12.
  `packages/web/src/components/shared/EmptyState.tsx:18`

- [ ] WEB-UIUX-455. **[MINOR] Skeleton uses `Math.random()` for column widths — every render shifts skeleton sizes.** Visible jiggle on parent re-render. L13.
  `packages/web/src/components/shared/Skeleton.tsx:41`
  <!-- meta: fix=seed-random-by-row-index -->

- [ ] WEB-UIUX-456. **[MINOR] Breadcrumb hardcodes `text-teal-500` not brand token.** L9, L10.
  `packages/web/src/components/shared/Breadcrumb.tsx:35`

- [ ] WEB-UIUX-457. **[MINOR] Breadcrumb `text-surface-500` for "Home" link wrapper but link itself uses teal — visual inconsistency.** L9.
  `packages/web/src/components/shared/Breadcrumb.tsx:17,35`

- [ ] WEB-UIUX-458. **[MINOR] Button primary variant `text-primary-950` only legible if primary is light/cream.** Same issue as WEB-UIUX-418 but in shared component. L9.
  `packages/web/src/components/shared/Button.tsx:55-56`

- [ ] WEB-UIUX-459. **[MINOR] OfflineBanner not in landmark — sits between `<ImpersonationBanner>` and `<Header>` with no `<aside>`/`<section>` wrapper.** Banner appears as orphan to SR rotor. L12.
  `packages/web/src/components/shared/OfflineBanner.tsx:42-50`

- [ ] WEB-UIUX-460. **[MINOR] OfflineBanner `role="status"`+`aria-live="polite"` but aria-live region must be present BEFORE update; conditional `if (online) return null` re-mounts the region each transition.** SR may miss the announcement. L12.
  `packages/web/src/components/shared/OfflineBanner.tsx:39-46`
  <!-- meta: fix=always-render-region+toggle-content -->

- [ ] WEB-UIUX-461. **[MINOR] PageErrorBoundary auto-reload sentinel uses `pathname` only.** Same component erroring on `/tickets` after navigate from `/customers` resets the 30 s window — second reload loop possible across rapid navs. L6.
  `packages/web/src/components/shared/PageErrorBoundary.tsx:79-119`

- [ ] WEB-UIUX-462. **[MINOR] SignatureCanvas `cursor-crosshair` set on canvas but `pointer-events-none` on baseline drawing — single tap with pen tool registers as start of stroke even on the "Sign here" hint area.** L13.
  `packages/web/src/components/shared/SignatureCanvas.tsx:106-110,277-287`

- [ ] WEB-UIUX-463. **[MINOR] TrialBanner three sequential `if` blocks each match-and-return — banner state machine not data-driven.** Adding a 7-day banner means a 4th branch. L4.
  `packages/web/src/components/shared/TrialBanner.tsx:50-128`

#### Layout (AppShell + Header + Sidebar)

- [ ] WEB-UIUX-464. **[BLOCKER] AppShell global F2/F3/F4/F6 shortcuts conflict with browser-reserved keys on Firefox/Safari.** F3 = Find Next on Windows browsers, F4 = address bar dropdown, F6 = focus URL bar. Bypassed only by `preventDefault` — confusing for power users who expect Find Next. L1, L13.
  `packages/web/src/components/layout/AppShell.tsx:108-128`
  <!-- meta: fix=use-Alt+F2..F6-or-document-as-app-shortcuts -->

- [ ] WEB-UIUX-465. **[MAJOR] Header `?` shortcut dispatched on `keydown` checks `e.target` for editable — but a `contenteditable` ancestor is not detected (only `target.isContentEditable`).** Rich-text editors that put `contenteditable` on an outer div (not target) leak `?` press. L1.
  `packages/web/src/components/layout/Header.tsx:286-297`

- [ ] WEB-UIUX-466. **[MAJOR] Header user menu `role="menu"` but children use `role="menuitem"` on `<button>` not arrow-key navigation.** WAI-ARIA menu pattern requires Up/Down between menuitems; current impl is just buttons inside a list-styled div. L12.
  `packages/web/src/components/layout/Header.tsx:464-535,575-588`
  <!-- meta: fix=or-drop-role=menu-and-use-list-of-buttons -->

- [ ] WEB-UIUX-467. **[MAJOR] Header notification dropdown clicks-outside via `mousedown` — touch-tap on iOS triggers `mousedown` after a delay, double-firing close+open on rapid bell tap.** L13.
  `packages/web/src/components/layout/Header.tsx:248-259`

- [ ] WEB-UIUX-468. **[MAJOR] Header `aria-live="polite"` SR region for unread count includes every count change.** Bell at 99+ recomputing every WS event spams SR. L12, L15.
  `packages/web/src/components/layout/Header.tsx:362-365`
  <!-- meta: fix=debounce-aria-live-or-announce-only-on-increase -->

- [ ] WEB-UIUX-469. **[MAJOR] AppShell skip-to-main link target `<main tabIndex={-1}>` but `focus-visible:outline-none` on main hides the focus ring after activation — keyboard user has no signal that the skip worked.** L12.
  `packages/web/src/components/layout/AppShell.tsx:144-149,208`

- [ ] WEB-UIUX-470. **[MAJOR] Sidebar `RecentViews` reads localStorage on every `location.pathname` change — JSON.parse + validation per route nav.** Cheap individually but unbounded route changes hammer it. L15.
  `packages/web/src/components/layout/Sidebar.tsx:311-350`

- [ ] WEB-UIUX-471. **[MAJOR] Sidebar collapsed-mode flat list drops section grouping but keeps order — `Settings` and Admin items rendered at end mixed with Team/Billing.** Visual hierarchy loss. L11, L4.
  `packages/web/src/components/layout/Sidebar.tsx:208-213`

- [ ] WEB-UIUX-472. **[MAJOR] Sidebar tooltip in collapsed mode (`SidebarTooltipWrapper`) uses `group-hover:opacity-100` — keyboard focus shows no tooltip.** L12.
  `packages/web/src/components/layout/Sidebar.tsx:457-464`
  <!-- meta: fix=add-group-focus-within:opacity-100 -->

- [ ] WEB-UIUX-473. **[MAJOR] Sidebar SidebarSection collapse state in component-local `useState(true)` — reset on every Sidebar remount.** User collapsing "Operations" loses state on logout/login. L5.
  `packages/web/src/components/layout/Sidebar.tsx:466-487`
  <!-- meta: fix=persist-per-section-in-localStorage-or-uiStore -->

- [ ] WEB-UIUX-474. **[MAJOR] Header SwitchUserModal local — duplicates PinModal logic (lockout missing!) just to avoid `onSuccess(pin)` plumbing.** Opens PIN auth without 5-attempt lockout, no `data-lpignore`. L4, L16.
  `packages/web/src/components/layout/Header.tsx:642-728`
  <!-- meta: fix=reuse-PinModal-with-purpose=switch-user -->

- [ ] WEB-UIUX-475. **[MINOR] Header search button collapses to icon below `sm` but `<span>Search...` still rendered in DOM (just not visible).** SR reads "Search or press ⌘K..." on mobile too — not wrong, but kbd hint is misleading on touch device. L12, L11.
  `packages/web/src/components/layout/Header.tsx:319-328`

- [ ] WEB-UIUX-476. **[MINOR] Header notification dropdown 320 px wide on mobile (`w-80`) — overflows right edge if user menu is open simultaneously (both anchor right).** L11.
  `packages/web/src/components/layout/Header.tsx:386`

- [ ] WEB-UIUX-477. **[MINOR] AppShell dev banner red bar can be dismissed but `--dev-banner-h` CSS var still set when banner hidden via animation.** Cosmetic 28 px reservation persists for one paint. L13.
  `packages/web/src/components/layout/AppShell.tsx:175,193-206`

- [ ] WEB-UIUX-478. **[MINOR] AppShell `useWebSocket()` on every render — fine in React but combined with `useQuery({queryKey:['settings-config-env']...})` on mount creates tight startup race.** L15.
  `packages/web/src/components/layout/AppShell.tsx:37,63-67`

- [ ] WEB-UIUX-479. **[MINOR] Sidebar `RecentViews` collapsed-mode renders `label.slice(0,6)` with no tooltip wait time — hover instantly pops 5+ tooltips on mouse-over.** L11.
  `packages/web/src/components/layout/Sidebar.tsx:381-384`

- [ ] WEB-UIUX-480. **[MINOR] Header `⌘K` mac shortcut shown on Mac iPad too — but iPad keyboards are physical Cmd keys, fine; iPad Safari without keyboard sees ⌘K hint that's unreachable.** L14.
  `packages/web/src/components/layout/Header.tsx:87-88`

- [ ] WEB-UIUX-481. **[MINOR] Sidebar `MyQueueWidget` 30 s `refetchInterval` independent from kanban poll — same data fetched twice in different shapes.** L15.
  `packages/web/src/components/layout/Sidebar.tsx:401-409`

- [ ] WEB-UIUX-482. **[NIT] Header dev/prod role labels `'Owner'` not present in shared types but in ROLE_LABELS map — dead branch.** L4.
  `packages/web/src/components/layout/Header.tsx:56-63`

#### Tickets (KanbanBoard, TicketActions, TicketDetail, TicketNotes)

- [ ] WEB-UIUX-483. **[BLOCKER] KanbanBoard relies on HTML5 drag/drop API — no keyboard alternative for status change.** Keyboard-only users cannot move cards across columns. L12.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:204-262`
  <!-- meta: fix=add-arrow-key-shortcuts-or-status-dropdown-fallback -->

- [ ] WEB-UIUX-484. **[BLOCKER] KanbanCard `onClick={navigate}` PLUS `draggable` — on touch devices, single tap can register as drag-start before drop. Card never opens.** L13.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:82-93`

- [ ] WEB-UIUX-485. **[BLOCKER] MergeDialog (TicketDetailPage) no focus trap, `onKeyDown={Escape}` only on backdrop div — child focus escapes Esc.** L12.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:114-128`

- [ ] WEB-UIUX-486. **[MAJOR] KanbanCard age-coloring overlays `bg-red-50`/`bg-amber-50` on top of `bg-white` — wins specificity but darkens to `dark:bg-red-950/20` only when also dark.** Two cards red on light, ringed by `border-l` colored differently. L9, L10.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:87-91`

- [ ] WEB-UIUX-487. **[MAJOR] KanbanBoard `min-w-[280px] w-[300px]` per column × 8 columns = 2400 px horizontal scroll forced on every viewport.** No "compact" mode. L11, L5.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:317-324`

- [ ] WEB-UIUX-488. **[MAJOR] TicketActions sticky header `-top-6 -mx-6` relies on parent padding — breaks if `<TicketDetailPage>` ever changes wrapper padding.** L11.
  `packages/web/src/pages/tickets/TicketActions.tsx:249`

- [ ] WEB-UIUX-489. **[MAJOR] TicketActions device pills (`devices.map((d:any) =>`) — `any` cast silences missing TicketDevice fields and renders unbounded long device names without truncation.** L4, L11.
  `packages/web/src/pages/tickets/TicketActions.tsx:271-276`

- [ ] WEB-UIUX-490. **[MAJOR] TicketActions ActionsDropdown items not keyboard-navigable as menu — buttons in plain `<div>`, no `role="menu"`, no arrow-key.** Tab between but no Up/Down. L12.
  `packages/web/src/pages/tickets/TicketActions.tsx:151-179`

- [ ] WEB-UIUX-491. **[MAJOR] TicketActions HeaderStatusDropdown 80vh max + 18rem min-width on small screen overflows right edge.** L11.
  `packages/web/src/pages/tickets/TicketActions.tsx:75-76`

- [ ] WEB-UIUX-492. **[MAJOR] TicketNotes `dangerouslySetInnerHTML` on system events — DOMPurify scoped to `b/i/em/strong` but description is server-supplied + may include user input.** Safe today, drift risk if event message format expands. L16.
  `packages/web/src/pages/tickets/TicketNotes.tsx:377-384`

- [ ] WEB-UIUX-493. **[MAJOR] TicketNotes Save button reads `noteContent.trim()` AFTER a 0.3s autosave debounce — fast click after typing may save trimmed empty if `useDraft` write is pending.** L6.
  `packages/web/src/pages/tickets/TicketNotes.tsx:243-264`

- [ ] WEB-UIUX-494. **[MAJOR · BLOCKED] TicketNotes SMS character counter divides by 160 for GSM-7 only — Unicode messages segment at 70.** Counter wrong for emoji/é characters. L14, L4.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/tickets/TicketNotes.tsx:291-295`

- [ ] WEB-UIUX-495. **[MINOR] KanbanBoard column header title `truncate` but column width fixed 300 px — long status names truncated identically every render.** L11.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:335-337`

- [ ] WEB-UIUX-496. **[MINOR] KanbanBoard "X columns · N tickets" counter not aria-live — users tracking mass move see no SR feedback.** L12.
  `packages/web/src/pages/tickets/KanbanBoard.tsx:308-310`

- [ ] WEB-UIUX-497. **[MINOR] TicketActions PrintButton spawns PrintPreviewModal but mounting cost paid on `setShowModal(true)` — no `lazy` boundary.** L15.
  `packages/web/src/pages/tickets/TicketActions.tsx:184-198`

- [ ] WEB-UIUX-498. **[MINOR] TicketActions Checkout button `bg-teal-600` not brand token — hardcoded teal across this and Breadcrumb.** L9, L10.
  `packages/web/src/pages/tickets/TicketActions.tsx:289-294`

- [ ] WEB-UIUX-499. **[MINOR] MergeDialog "type to search" 2-char minimum — not announced; no aria-describedby.** Empty results say "Type to search for tickets..." but SR users hit Enter on empty input. L12.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:147-153`

#### TV Display

- [ ] WEB-UIUX-500. **[BLOCKER] TvDisplayPage hardcodes `en-US` locale for clock + date.** Spanish/multi-language tenants see English on lobby screen. L14.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:33-37,112-116`

- [ ] WEB-UIUX-501. **[MAJOR] TvDisplayPage no auto-cycle — if more tickets than fit on screen, customers below the fold never see their status.** L5, L8.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:153-158`
  <!-- meta: fix=add-page-rotation-or-virtualized-scroll -->

- [ ] WEB-UIUX-502. **[MAJOR] TvDisplayPage shows `customer_first_name.charAt(0)` initial — but device names rendered in full (`d` text) can include customer-identifiable IMEI/serial pattern.** PII bleed not consistent with initial-only customer name. L16.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:202-211`

- [ ] WEB-UIUX-503. **[MAJOR] TvDisplayPage tickets array typed via `as any` cast — server schema drift silent.** L4.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:92`

- [ ] WEB-UIUX-504. **[MAJOR] TvDisplayPage retry button always available even when isFetching — repeated clicks fire concurrent refetch.** L6.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:128-134`

- [ ] WEB-UIUX-505. **[MINOR] TvDisplayPage `text-white` card content on dark gradient — works, but ticket-status badge `safeColor + 25` opacity over `bg-surface-800/60` produces low-contrast pills for dark status colors.** L9.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:46-48`

- [ ] WEB-UIUX-506. **[MINOR] TvDisplayPage `Auto-refreshes every 30 seconds` footer text — not localized, not aria-live.** L14, L12.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:165`

- [ ] WEB-UIUX-507. **[MINOR] TvDisplayPage no fullscreen toggle / wake-lock — lobby cabinet sleeps on macOS/Windows defaults.** L8.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:75-169`

- [ ] WEB-UIUX-508. **[MINOR] TvDisplayPage TicketCard hover effect (`hover:border-surface-600/50`) on a TV display — non-interactive surface, hover meaningless.** L13.
  `packages/web/src/pages/tv/TvDisplayPage.tsx:179-184`

#### Photo Capture

- [ ] WEB-UIUX-509. **[MAJOR] PhotoCapturePage re-uploads ALL photos on retry — no per-photo state.** Network drop mid-batch wastes bandwidth on already-uploaded ones. L15, L8.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:94-123`

- [ ] WEB-UIUX-510. **[MAJOR] PhotoCapturePage no client-side rotation/EXIF strip — iOS portrait shots upload with rotation tag, server-side display may render sideways.** L4, L8.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:79-85`

- [ ] WEB-UIUX-511. **[MAJOR] PhotoCapturePage hardcodes `bg-gray-900`/`text-white` — not dark/light mode aware.** Pre-condition page only — fine for kiosk, broken if customer accesses on system in light scheme. L10.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:127-285`

- [ ] WEB-UIUX-512. **[MAJOR] PhotoCapturePage strings English-only ("Take Photo", "Add more").** Customer-facing. L14.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:185-256`

- [ ] WEB-UIUX-513. **[MAJOR] PhotoCapturePage Camera button uses `<label>` wrapping `<input type="file">` — keyboard Tab+Space activates correctly but Enter sometimes doesn't trigger file picker on iOS.** L12, L13.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:251-264`

- [ ] WEB-UIUX-514. **[MINOR] PhotoCapturePage 10 MB MAX_FILE_SIZE pre-resize — modern phones produce 4-8 MB easily; reject path triggers on edge cases.** L8.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:45,65-68`
  <!-- meta: fix=add-canvas-downscale-before-upload -->

- [ ] WEB-UIUX-515. **[MINOR] PhotoCapturePage emoji 📸 in instruction text rendered without `role="img"`/`aria-label`.** SR reads "camera with flash". L12.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:192-194`

- [ ] WEB-UIUX-516. **[MINOR] PhotoCapturePage uploaded confirmation page renders `#${ticketId}` raw — no formatting (`T-0042`).** L14.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:154`

- [ ] WEB-UIUX-517. **[MINOR] PhotoCapturePage no photo metadata (timestamp, geolocation toggle) — repair photo evidence can't establish chain of custody.** L16.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:79-85`

#### Print Page

- [ ] WEB-UIUX-518. **[BLOCKER] PrintPage `PrintTicket extends Record<string, any>` — every prop access types as `any`. Complete loss of type safety on print surface.** L4.
  `packages/web/src/pages/print/PrintPage.tsx:40-90`

- [ ] WEB-UIUX-519. **[BLOCKER] PrintPage thermal receipt 58mm uses 9 pt font — passes but no `min-height` or page-break. Long receipts blank-paper a printer mid-render.** L11, L8.
  `packages/web/src/pages/print/PrintPage.tsx:204-441`

- [ ] WEB-UIUX-520. **[MAJOR] PrintPage `cfg('receipt_cfg_*', '1')` defaults all toggles ON — fresh tenant who hasn't configured anything gets the most verbose receipt by default.** L8.
  `packages/web/src/pages/print/PrintPage.tsx:192,448`

- [ ] WEB-UIUX-521. **[MAJOR] PrintPage `BarcodeBlock` uses `JsBarcode` synchronously in useEffect — failed barcode silently swallowed via empty catch.** L8.
  `packages/web/src/pages/print/PrintPage.tsx:165-185`

- [ ] WEB-UIUX-522. **[MAJOR] PrintPage signature size cap 100 KB but PDF surface (server-side) doesn't enforce same cap — print preview loads OK but prod-print may reject.** L16.
  `packages/web/src/pages/print/PrintPage.tsx:148-154`

- [ ] WEB-UIUX-523. **[MAJOR] PrintPage hardcodes `'Courier New'` thermal monospace — falls back to platform default if absent (Windows default Courier is fine; Linux thermal printer driver may not have it).** L11.
  `packages/web/src/pages/print/PrintPage.tsx:204`

- [ ] WEB-UIUX-524. **[MAJOR] PrintPage thermal `*** WARRANTY REPAIR ***` not localized, English-only.** Receipts go to customers — translation matters. L14.
  `packages/web/src/pages/print/PrintPage.tsx:245-247`

- [ ] WEB-UIUX-525. **[MAJOR] PrintPage `formatDateTime` everywhere — but tenant TZ from store_settings ignored when timestamps stored as UTC. Print date may be wrong by ±12h.** L6, L14.
  `packages/web/src/pages/print/PrintPage.tsx:250,515`

- [ ] WEB-UIUX-526. **[MINOR] PrintPage `<svg>` for barcode but no `aria-label` — screen-reading the receipt skips ID.** L12.
  `packages/web/src/pages/print/PrintPage.tsx:184`

- [ ] WEB-UIUX-527. **[MINOR] PrintPage `isSafeLogoUrl` accepts `https://` from any host — server settings can store `https://attacker.com/logo.png` and print pages exfiltrate user IP via image fetch.** L16.
  `packages/web/src/pages/print/PrintPage.tsx:102-113`
  <!-- meta: fix=allow-list-logo-host-or-relative-only -->

- [ ] WEB-UIUX-528. **[MINOR] PrintPage `$$` in receipt strings via shared `formatCurrency` — no per-line column alignment via `text-align: right`. Multi-digit totals don't right-align.** L11.
  `packages/web/src/pages/print/PrintPage.tsx:336-380`

#### Team Pages (TeamChat, ShiftSchedule, MyQueue, Payroll)

- [ ] WEB-UIUX-529. **[BLOCKER] PayrollPage is a 10-line stub with only `<CommissionPeriodLock>` — no payroll list, no period summary, no employee earnings table.** Routed but functionally empty. L8.
  `packages/web/src/pages/team/PayrollPage.tsx:1-10`

- [ ] WEB-UIUX-530. **[BLOCKER] TeamChatPage New-channel modal no focus trap, no initial focus.** L12.
  `packages/web/src/pages/team/TeamChatPage.tsx:340-382`

- [ ] WEB-UIUX-531. **[BLOCKER] ShiftSchedulePage NewShiftModal no focus trap, no initial focus.** L12.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:307-407`

- [ ] WEB-UIUX-532. **[BLOCKER] TeamChatPage messages render `body` raw via `whitespace-pre-wrap` — no @mention highlight, no link auto-detect, no escape.** Chat content escapes via React's default but `@evil.com` link not clickable. L4, L8.
  `packages/web/src/pages/team/TeamChatPage.tsx:287`

- [ ] WEB-UIUX-533. **[MAJOR] TeamChatPage send-on-Enter swallows IME composition correctly but Cmd+Enter (claimed in footer hint) actually sends — comment says Slack/Discord-style but footer says "Press Cmd/Ctrl + Enter to send".** Mismatch. L14.
  `packages/web/src/pages/team/TeamChatPage.tsx:309-320,333-335`

- [ ] WEB-UIUX-534. **[MAJOR] TeamChatPage 15 s polling with no WebSocket fallback — under poor network 1-min lag for new messages.** L15.
  `packages/web/src/pages/team/TeamChatPage.tsx:89-108`

- [ ] WEB-UIUX-535. **[MAJOR] TeamChatPage scrollIntoView on every message-length change — even when user has scrolled up to read history. Yanks them to bottom on tick.** L13.
  `packages/web/src/pages/team/TeamChatPage.tsx:129-131`
  <!-- meta: fix=detect-near-bottom-before-scroll -->

- [ ] WEB-UIUX-536. **[MAJOR] TeamChatPage timestamps `toLocaleTimeString([], hour:2-digit minute:2-digit)` — strips date. Yesterday and today both show "10:30 AM". L14.
  `packages/web/src/pages/team/TeamChatPage.tsx:283-285`

- [ ] WEB-UIUX-537. **[MAJOR] ShiftSchedulePage `startOfWeek()` hardcodes Monday-start.** Tenants in regions with Sunday or Saturday week-start see misaligned grid. L14.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:47-54`

- [ ] WEB-UIUX-538. **[MAJOR] ShiftSchedulePage `delete shift` button no confirm — single click destroys row.** L16, L8.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:251-258`

- [ ] WEB-UIUX-539. **[MAJOR] ShiftSchedulePage time-off Approve/Deny buttons no confirm — accidental click immutably approves/denies.** L16, L8.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:284-300`

- [ ] WEB-UIUX-540. **[MAJOR] ShiftSchedulePage `<input type="datetime-local">` submits in user's TZ but server stores UTC — DST or operator-in-different-TZ bookings shift by 1h.** L6, L14.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:328-343,108-112`

- [ ] WEB-UIUX-541. **[MAJOR] ShiftSchedulePage uses `e:any` on mutation onError 3 times.** Lost type safety. L4.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:124,136,148`

- [ ] WEB-UIUX-542. **[MAJOR] MyQueuePage hardcodes `bg-red-100/text-red-700` etc. without dark variants.** Light-mode-only badges on dark-mode queue. L10, L9.
  `packages/web/src/pages/team/MyQueuePage.tsx:34-48`

- [ ] WEB-UIUX-543. **[MAJOR] MyQueuePage no sort columns, no filter — tech with 50+ tickets sees long table sorted by server.** L5.
  `packages/web/src/pages/team/MyQueuePage.tsx:100-160`

- [ ] WEB-UIUX-544. **[MINOR] TeamChatPage `MentionPicker` shows on every `MENTION_TAIL_RE.test(tail)` change — no debounce + no aria-controls connecting picker to textarea.** L12.
  `packages/web/src/pages/team/TeamChatPage.tsx:184-188,292-298`

- [ ] WEB-UIUX-545. **[MINOR] TeamChatPage channel list has no unread/badge indicator — operators must open each channel to spot new messages.** L8.
  `packages/web/src/pages/team/TeamChatPage.tsx:244-258`

- [ ] WEB-UIUX-546. **[MINOR] ShiftSchedulePage week navigation Prev/Next/This-week buttons no `aria-label` describing destination.** SR users hear "← Prev". L12.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:180-205`

- [ ] WEB-UIUX-547. **[MINOR] ShiftSchedulePage day grid `min-h-[280px]` fixed — no auto-fit when many shifts overflow vertically (scroll lost).** L11.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:231`

- [ ] WEB-UIUX-548. **[MINOR] ShiftSchedulePage time-off pending list has no "view all" — long list lives in sidebar with no overflow control.** L5.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:268-303`

#### Gift Card Detail

- [ ] WEB-UIUX-549. **[BLOCKER] GiftCardDetailPage ReloadModal no focus trap.** L12.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:115-155`

- [ ] WEB-UIUX-550. **[MAJOR] GiftCardDetailPage `dollarsFromMaybeCents` ad-hoc heuristic.** Server schema flip risk; helper duplicated from list page. L4, L6.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:41-44`
  <!-- meta: fix=server-canonicalize-cents-or-shared-amount-utility -->

- [ ] WEB-UIUX-551. **[MAJOR] GiftCardDetailPage `showCode` toggle reveals full code in DOM — no rate limit, no audit log, no auto-hide on tab blur.** Casual shoulder-surf risk for high-value cards. L16.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:233-244`

- [ ] WEB-UIUX-552. **[MAJOR] GiftCardDetailPage Reload button enabled when `card.status !== 'used' && !== 'disabled'` — but no plan-feature gate (gift cards may be Pro-only).** Free-tenant click → 403. L8.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-294`

- [ ] WEB-UIUX-553. **[MAJOR] ReloadModal accepts `parseFloat(amount) <= 0` reject AT mutation but type=number `min=0.01` cosmetic only — pasting `-50` accepted by browser, mutation rejects with toast (better: client-side block).** L7.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:90-95,127-131`

- [ ] WEB-UIUX-554. **[MINOR] GiftCardDetailPage txColor returns same red for `redemption` regardless of refund vs spend — no distinction.** L9.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:63-69`

- [ ] WEB-UIUX-555. **[MINOR] GiftCardDetailPage transaction table no pagination — 1000-tx history loads in one query.** L15, L5.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:304-329`

- [ ] WEB-UIUX-556. **[MINOR] GiftCardDetailPage `useQuery` `staleTime: 30_000` but reload mutation invalidates — cache hit→bust pattern fine, but no `refetchOnWindowFocus` so tab-back may show stale balance.** L15.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:178-186`

#### Cross-Cutting (Pass 8)

- [ ] WEB-UIUX-557. **[BLOCKER] 12+ modals across this pass alone lack focus trap and/or scroll lock.** ConfirmDialog has trap but no scroll lock; CommandPalette/UpgradeModal/PrintPreviewModal/QuickSmsModal/MergeDialog/TeamChat-NewChannel/ShiftSchedule-NewShift/Reload/SwitchUserModal — each rolls own backdrop. L4, L11, L12.

- [ ] WEB-UIUX-558. **[BLOCKER] No keyboard alternative for any drag-drop UI (Kanban, planned drag).** Operators using only keyboard cannot transition tickets via Kanban. L12.

- [ ] WEB-UIUX-559. **[MAJOR] `as any` casts on API responses in ≥6 surfaces this pass.** TvDisplayPage tickets, TicketDetailPage MergeDialog candidates, TicketActions devices, ShiftSchedulePage onError, TicketNotes structuredClone, TicketDevices d. L4, L15.
  <!-- meta: fix=zod-validate-axios-response-once-at-client -->

- [ ] WEB-UIUX-560. **[MAJOR] Hardcoded color tokens (`text-teal-*`, `bg-green-*`, `bg-red-100`) outside the surface/primary/brand semantic system span 30+ usages this pass.** L9, L10.

- [ ] WEB-UIUX-561. **[MAJOR] Multiple components register their own `keydown` Esc listeners on `document`/`window` — stacking modals (e.g. UpgradeModal opening over a TicketDetail MergeDialog) causes Esc to close BOTH at once.** L13, L12.
  <!-- meta: fix=top-of-stack-modal-handler-via-shared-Modal-primitive -->

- [ ] WEB-UIUX-562. **[MAJOR] `refetchOnWindowFocus: true` overrides on a few shared-state surfaces (KanbanBoard, MyQueue) — but TeamChat, ShiftSchedule, TvDisplay rely on polling only.** Returning operator may stare at stale grid. L15.

- [ ] WEB-UIUX-563. **[MAJOR] Toast strings + section titles English-only across staff surfaces (Team/Tickets/Print/TV).** Spanish-tenant staff get mixed English UI. L14.

- [ ] WEB-UIUX-564. **[MINOR] Inconsistent spinner: `Loader2 className="animate-spin"` (lucide) vs Tailwind `animate-pulse` skeletons vs raw `border-t-brand-500 animate-spin` — no shared `<Spinner>`.** L4.

- [ ] WEB-UIUX-565. **[MINOR] Drop-shadow disparity: cards use `shadow-sm`, modals `shadow-2xl`, dropdowns `shadow-lg`/`shadow-xl` arbitrarily.** L11.

- [ ] WEB-UIUX-566. **[MINOR] Rounded-corner inconsistency: `rounded-md`, `rounded-lg`, `rounded-xl`, `rounded-2xl` mixed within single page.** TicketDetailPage MergeDialog `rounded-xl`, FaqTooltip `rounded-md`, Pin `rounded-xl` but inputs `rounded-lg`. L11.

- [ ] WEB-UIUX-567. **[MINOR] No global `useEscapeStack` hook — every modal duplicates the same `useEffect(()=>{addEventListener('keydown',Esc)})` pattern.** L4.
  <!-- meta: fix=create-useEscapeStack+register-with-z-index-to-resolve-stacked-modals -->

- [ ] WEB-UIUX-568. **[NIT] `disabled:pointer-events-none` cargo-culted alongside `disabled:opacity-50` on every button — disabled `<button>` already drops events; class is redundant.** L4.

### Web UI/UX Audit — Pass 9 (2026-05-05, shared components + inventory + gift-cards detail)

#### Blockers/Trust

- [ ] WEB-UIUX-569. **[BLOCKER] Two distinct `TrialBanner` components — one is dead code.** `components/TrialBanner.tsx` (114 lines, queries setupStatus+config) NOT imported anywhere. Only `components/shared/TrialBanner.tsx` (130 lines) wired via AppShell. Diverges in dismissal/thresholds/copy/colors. L3.
  `packages/web/src/components/TrialBanner.tsx`
  <!-- meta: fix=delete-orphan-or-merge -->

- [ ] WEB-UIUX-570. **[BLOCKER] ImpersonationBanner is a `<button>` covering entire bar — click anywhere exits impersonation.** Including X icon at line 107 looks like separate close action. Super-admin debugging tenant accidentally logs out by clicking banner text. L16, L12.
  `packages/web/src/components/ImpersonationBanner.tsx:96-109`
  <!-- meta: fix=split-status-display-from-action-target-use-role=status+separate-button -->

- [ ] WEB-UIUX-571. **[BLOCKER usability] InventoryListPage 1946 lines holds 7 inline modals + EmptyState + helpers.** No code splitting; every render parses 96kb of TSX. Maintenance + perf hit. L15.
  `packages/web/src/pages/inventory/InventoryListPage.tsx`
  <!-- meta: fix=split-into-VarianceModal+ReceiveModal+EmptyState+lazy-load-modals -->

#### Onboarding

- [ ] WEB-UIUX-572. **[MAJOR] SpotlightCoach `aria-modal` missing despite `role="dialog"`.** Focus not trapped, not moved into card on mount. L12.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:168-176`

- [ ] WEB-UIUX-573. **[MAJOR] SpotlightCoach `CARD_EST_HEIGHT=240` hardcoded — flip-above branch mis-places by 80-100px on long-body steps.** L13, L11.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:139,151-156`
  <!-- meta: fix=useLayoutEffect-measure-getBoundingClientRect -->

- [ ] WEB-UIUX-574. **[MAJOR] SpotlightCoach 50% black overlay no `prefers-reduced-transparency` opt-out.** Low-vision users lose page context entirely. L12, L13.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:107`

- [ ] WEB-UIUX-575. **[MAJOR usability] SpotlightCoach "Skip step" sits next to "Skip tutorial" with similar styling — destructive vs non-destructive indistinguishable.** L14, L2.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:234-241,408-410`
  <!-- meta: fix=rename-to-Next-or-Mark-as-done-different-color-from-Skip-tutorial -->

- [ ] WEB-UIUX-576. **[MAJOR] `useMilestoneToasts` + `SuccessCelebration` both fire toast+confetti on first payment.** Duplicate celebration. Per-tab sessionStorage means each open tab fires independently. L3, L8.
  `packages/web/src/components/onboarding/useMilestoneToasts.ts:13-17,107-123`

- [ ] WEB-UIUX-577. **[MINOR] SpotlightCoach `TARGET_FIND_TIMEOUT_MS=300` linear retry — partial-render races show nothing for 300ms then snap.** L1, L12.
  `packages/web/src/components/onboarding/SpotlightCoach.tsx:33,322-345`
  <!-- meta: fix=use-MutationObserver-on-document.body -->

- [ ] WEB-UIUX-578. **[MINOR] tutorialFlows final hint says "real jobs" — implies prior was simulation but flow used real money.** L14.
  `packages/web/src/components/onboarding/tutorialFlows.ts:189`

- [ ] WEB-UIUX-579. **[MINOR] tutorialFlows `dismissAllTutorials` writes localStorage BEFORE API call.** API failure leaves local flag sticky. L16.
  `packages/web/src/components/onboarding/tutorialFlows.ts:223-239`

#### Shared Components

- [ ] WEB-UIUX-580. **[MAJOR] LoadingScreen + NotFoundPage + SetupFailedScreen + PageErrorBoundary + ErrorBoundary all reinvent button styles instead of canonical `<Button>`.** Cumulative drift. L4, L9.
  Files: `components/shared/LoadingScreen.tsx:13-30,40-45,88-100`, `components/shared/PageErrorBoundary.tsx:142-160`, `components/ErrorBoundary.tsx:32-60`

- [ ] WEB-UIUX-581. **[MAJOR] OfflineBanner uses `relative z-0` — modals at z-50 hide it.** Cashier mid-transaction can't see offline state. L8, L11.
  `packages/web/src/components/shared/OfflineBanner.tsx:45`
  <!-- meta: fix=z-[60]+ensure-banners-stack-above-modals -->

- [ ] WEB-UIUX-582. **[MAJOR] OfflineBanner doesn't toast on online↔offline transitions — silent state change.** L8.
  `packages/web/src/components/shared/OfflineBanner.tsx:26-37`
  <!-- meta: fix=fire-toast.error-on-offline-toast.success-on-recovery -->

- [ ] WEB-UIUX-583. **[MAJOR] PageErrorBoundary auto-reload pinball: oscillating between 2 stale routes triggers chain.** 30s window protects same-route only. L13, L15.
  `packages/web/src/components/shared/PageErrorBoundary.tsx:79-118`
  <!-- meta: fix=add-attempts-counter-bail-after-3 -->

- [ ] WEB-UIUX-584. **[MAJOR] ErrorBoundary + PageErrorBoundary fallback UI 80% redundant.** L3, L4.
  `components/ErrorBoundary.tsx:32-60` vs `components/shared/PageErrorBoundary.tsx:128-163`
  <!-- meta: fix=extract-ErrorFallback-shared -->

- [ ] WEB-UIUX-585. **[MAJOR] TrialBanner (shared) uses 4 different button styles + 3 different upgrade verbs across 3 banner variants.** Visually identical except color/copy — extract subcomponent. L9, L14.
  `packages/web/src/components/shared/TrialBanner.tsx:55-72,84-105,108-127`

- [ ] WEB-UIUX-586. **[MAJOR] ImpersonationBanner shows `tenant_slug` raw — should show `tenant_name` (human label) primary.** Misleading on slug-only display. L9, L16.
  `packages/web/src/components/ImpersonationBanner.tsx:101-106`

- [ ] WEB-UIUX-587. **[MINOR] LoadingScreen "Loading..." with no context — boot >3s users have zero idea what's happening.** L14, L8.
  `packages/web/src/components/shared/LoadingScreen.tsx:18`

- [ ] WEB-UIUX-588. **[MINOR] SetupFailedScreen request-id `break-all` but no copy button.** Manual selection error-prone. L12.
  `packages/web/src/components/shared/LoadingScreen.tsx:80-85`

- [ ] WEB-UIUX-589. **[MINOR] PermissionBoundary silent fallback hides UX — vanished tabs/buttons with no explanation.** L12, L8.
  `packages/web/src/components/shared/PermissionBoundary.tsx:13-25`

- [ ] WEB-UIUX-590. **[MINOR] Timeline empty state hand-rolled — should use shared EmptyState.** L4.
  `packages/web/src/components/shared/Timeline.tsx:28-34`

- [ ] WEB-UIUX-591. **[MINOR] ImpersonationBanner + OfflineBanner + TrialBanner z-index inconsistency.** Stacking order undefined. L9.
  <!-- meta: fix=define-banner-stack-impersonation-z-30-offline-z-25-trial-z-20 -->

#### Inventory Detail/Create

- [ ] WEB-UIUX-592. **[MAJOR usability] InventoryDetailPage "Adjust Stock" inline panel not modal — no focus trap, no Esc, no auto-focus.** Tab cycles through underlying form. L12, L7.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:346-382`

- [ ] WEB-UIUX-593. **[MAJOR usability] InventoryDetailPage handleAdjust uses `parseInt('+5')` — returns NaN in older engines, silently truncates `5.5` to `5`.** L7.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:127-131`

- [ ] WEB-UIUX-594. **[MAJOR usability] handlePrintBarcode opens `window.open('')` without checking for popup-blocker rejection.** Click does nothing, no toast. L8, L16.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:144-159`
  <!-- meta: fix=if-printWindow-null-toast.error-allow-popups -->

- [ ] WEB-UIUX-595. **[MAJOR usability] InventoryCreatePage `retail_price="0"` passes truthy validation — user can submit free product accidentally.** L7.
  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:73`
  <!-- meta: fix=parseFloat>0-with-explicit-error -->

- [ ] WEB-UIUX-596. **[MAJOR usability] InventoryCreatePage all errors via toast — no inline FormError, no aria-invalid.** L7, L8, L12.
  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:70-86`

- [ ] WEB-UIUX-597. **[MAJOR usability] InventoryListPage Bulk Price `pct === -100` passes (`pct < -100` strict) — accidentally zeros all prices.** L7, L16.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:330`
  <!-- meta: fix=use-pct<=-100-or-explicit-error-Use-Delete-instead -->

- [ ] WEB-UIUX-598. **[MAJOR] InventoryListPage 7 inline modals reinvent backdrop+close boilerplate.** ~80 lines duplicated each. L3, L4.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:947,1029,1109,1158,1244,1531,1750`
  <!-- meta: fix=extract-Modal-primitive-saves-~400-lines -->

- [ ] WEB-UIUX-599. **[MAJOR] InventoryListPage modal `autoFocus` on input but no focus trap — Tab cycles to underlying page.** L12.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:1530-1690`

- [ ] WEB-UIUX-600. **[MAJOR usability] InventoryListPage 8 header buttons + Tools bar = button overload on tablet.** No "More actions ▼" overflow. L1, L11.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:425-470,492-502`

- [ ] WEB-UIUX-601. **[MINOR] InventoryDetailPage Cancel during edit reverts to stale item silently — no unsaved-changes warning.** L7, L8.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:195`

- [ ] WEB-UIUX-602. **[MINOR usability] InventoryListPage "Order All on Supplier Sites" opens 1st link sync without confirmation.** Accidental click jumps off-app. L8, L16.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:712-720`

- [ ] WEB-UIUX-603. **[MINOR] InventoryListPage Bulk Price preview only first 20 items — no "...30 more" disclosure.** L8.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:998`

- [ ] WEB-UIUX-604. **[MINOR] InventoryListPage Receive playBeep creates new AudioContext per scan — leak after ~6 scans.** L8, L15.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:1695-1708`

- [ ] WEB-UIUX-605. **[MINOR] InventoryDetailPage Stock Movements caps at max-h-96 with no "View all" link.** L8.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:402`

- [ ] WEB-UIUX-606. **[MINOR] InventoryCreatePage type="service" code paths still exist despite "service option removed" comment.** Dead conditional rendering. L4.
  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:76,116-122,188`

- [ ] WEB-UIUX-607. **[MINOR] InventoryListPage debounce `searchTimerRef`+`setTimeout` not cleaned on unmount — fires `setParam` after unmount.** L7, L1.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:66-67,170-174`

#### Gift Card Detail

- [ ] WEB-UIUX-608. **[MAJOR usability] GiftCardDetailPage ReloadModal disabled-button check uses `!amount` — `"abc"` is truthy so button stays enabled, throws inside mutationFn.** L7, L8.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:90-104,143-150`

- [ ] WEB-UIUX-609. **[MINOR] GiftCardDetailPage code-toggle button missing `aria-pressed`.** L12.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:237-243`

- [ ] WEB-UIUX-610. **[MINOR] GiftCardDetailPage masked code `****1234` cramped — no separator like `**** **** **** 1234`.** L9.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:235`

- [ ] WEB-UIUX-611. **[MINOR] GiftCardDetailPage transactions table no `overflow-x-auto` or mobile card layout.** Overflow on 360px viewport. L11.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:304-328`

- [ ] WEB-UIUX-612. **[MINOR] GiftCardDetailPage local DetailSkeleton + bespoke "Gift card not found" + "No transactions yet" all bypass canonical Skeleton + EmptyState.** L4.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:159-167,199-211,301-302`


### Web UI/UX Audit — Edge-Case Pass A (2026-05-05, parallel agents)

#### ED1: Checkout → Mistake → Delete → Refund

- [ ] WEB-UIUX-613. **[BLOCKER usability] SuccessScreen has NO undo/cancel/refund button.** Cashier just hit checkmark, realizes mistake, only options are Print/View Invoice/View Ticket/New Sale. Must mentally translate "I made a mistake" into "navigate to invoice → click Credit Note OR Void". L1, L4.
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:407-446`
  <!-- meta: fix=add-Issue-Refund-Cancel-sale-button-routes-to-credit-note-modal -->

- [ ] WEB-UIUX-614. **[BLOCKER] Ticket delete dialog says "removed from all views" — silent on paid invoice 403, on auto-void cascade, on stock restoration.** Server 403 message swallowed by generic "Failed to delete ticket" toast. Optimistic cache hide already navigated user away. L7, L4, L11.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:627-637,321-336`
  <!-- meta: fix=pre-compute-paidAmount+invoice.status-pass-server-403-verbatim -->

- [ ] WEB-UIUX-615. **[BLOCKER] No client-side enforcement of refund-before-delete order.** Delete button unconditionally rendered regardless of invoice state. Server 403's after typed-id confirm. L8, L12.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:503,TicketActions.tsx:171-174`

- [ ] WEB-UIUX-616. **[MAJOR] Void invoice silently zeros `amount_paid` even when cash was physically collected.** Confirm dialog never warns about financial-reporting impact. Cashier expects refund, gets ledger destruction. L8, L4.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:807-817`

- [ ] WEB-UIUX-617. **[MAJOR] Soft-deleted ticket leaves dangling "Ticket #X" link in InvoiceDetailPage.** Click → "Ticket Not Found". State drift unmarked. L6, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:416-420,687-698,839-845`

- [ ] WEB-UIUX-618. **[MAJOR] Server auto-voids invoice on ticket delete invisibly — confirm dialog doesn't enumerate side effects.** L7, L11.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:630`

- [ ] WEB-UIUX-619. **[MAJOR] Delete confirm shows ticket order ID but no customer/device/invoice context — typed-id requireTyping is theatre.** L12, L13.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:633-634`

- [ ] WEB-UIUX-620. **[MAJOR] 5s undo window for delete-with-cascade too short.** Same window used for void invoice — heavy cascades, often dismissed by other toasts. L4, L11.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:327`

- [ ] WEB-UIUX-621. **[MAJOR] No combined "Cancel Sale" wizard.** 4-step manual sequence: refund → navigate → delete → confirm. Each abandonable mid-flow → inconsistent intermediate state. L8, L4.

- [ ] WEB-UIUX-622. **[MINOR] Credit Note modal max field has no per-payment-row indicator showing which payment will be marked VOIDED.** L11.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:763-778`

- [ ] WEB-UIUX-623. **[MINOR] Credit Note copy doesn't say "this does NOT restore stock — use Void to restore stock".** Asymmetry with Void confirm. L5.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`

- [ ] WEB-UIUX-624. **[MINOR] After credit-note success, no "send refund receipt" prompt mirroring post-payment receipt prompt.** Customer walks away with no proof of refund. L5.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-175`

- [ ] WEB-UIUX-625. **[MINOR] Voided-payment detection relies on substring search of `[VOIDED]` inside free-text notes column.** Off-by-one math: running total INCLUDES voided payments. L13, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:485,488`

#### ED2: Split-Tender Partial Refund

- [ ] WEB-UIUX-626. **[BLOCKER] Operator cannot choose refund tender — all refunds via Credit Note generic.** Original cash+card+gift-card split → no UI to specify "$X back to card, $Y to cash". Server `/credit-note` accepts amount only. L1, L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`
  `packages/server/src/routes/invoices.routes.ts:1162-1318`

- [ ] WEB-UIUX-627. **[BLOCKER] Credit-note never inserts payment-out row, never decrements gift-card balance, never calls BlockChyp reverse.** Paper-only ledger adjustment — physical money never moves. Z-report still shows original cash sale. L8, L13, L16.
  `packages/server/src/routes/invoices.routes.ts:1213-1257`

- [ ] WEB-UIUX-628. **[BLOCKER] No `/blockchyp/refund` endpoint exists at all.** Even with UI, server has no path to settle card refund through terminal. L5, L16.
  `packages/server/src/routes/blockchyp.routes.ts`

- [ ] WEB-UIUX-629. **[BLOCKER] `/blockchyp/void-payment` is a no-op — never calls BlockChyp reverse, just appends "[VOIDED]" to notes string.** Card transaction stays captured upstream. L16, L13.
  `packages/server/src/routes/blockchyp.routes.ts:482-543`

- [ ] WEB-UIUX-630. **[BLOCKER] Web frontend never calls `giftCardApi.redeem` — gift cards cannot be used at POS at all.** PAYMENT_METHODS hardcoded to Cash/Card/Other. L1, L5.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:23-27`

- [ ] WEB-UIUX-631. **[MAJOR] Cash refund never inserts `cash_register cash_out` event.** Drawer-balance card on CashRegisterPage permanently understates cash-out. End-of-day = surplus over physical drawer. L13, L16.
  `packages/server/src/routes/invoices.routes.ts:1162-1318`

- [ ] WEB-UIUX-632. **[MAJOR] Two parallel refund paths: web wires only the broken `/credit-note`. Better-designed `/refunds` (per-method caps, approval gating) is dead code.** L3, L4.
  `packages/server/src/routes/refunds.routes.ts:107` (unused by web)

- [ ] WEB-UIUX-633. **[MAJOR] Card-leg failure mid-split leaves leg-1 captured, retry charges new money — no "you have $30 already-captured, finish or reverse".** L5, L8, L11.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:367-402`

- [ ] WEB-UIUX-634. **[MAJOR] `payments` table has no `parent_payment_id`/`refund_of_payment_id` link.** Schema gap underlying every refund-routing problem. L4.

- [ ] WEB-UIUX-635. **[MINOR] RefundReasonPicker single-purpose — no `RefundDestinationPicker` companion.** L4.
  `packages/web/src/components/billing/RefundReasonPicker.tsx`

#### ED4: Stock/Inventory Chaos

- [ ] WEB-UIUX-636. **[BLOCKER] Stocktake commit irreversible — no rollback after wrong count committed.** Confirm dialog only says "Inventory counts will be updated" — no diff, no undo. L4, L13.
  `packages/web/src/pages/inventory/StocktakePage.tsx:136-148,337-348`

- [ ] WEB-UIUX-637. **[BLOCKER] PO Receive has no un-receive path.** Wrong items received → vanish into stock with no recovery. inventoryApi has no `un-receive`/`cancel-receipt`/`negative-receive`. L4, L16.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:64-80,138-146`

- [ ] WEB-UIUX-638. **[MAJOR] Stocktake commit confirm has no diff/preview — no items-changing list, no $-impact.** L8, L13.
  `packages/web/src/pages/inventory/StocktakePage.tsx:336-348`

- [ ] WEB-UIUX-639. **[MAJOR] Bulk price update preview truncated to 20 items.** 200 selected → user sees random 20, clicks Apply, no "view all" toggle. L8.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:998`

- [ ] WEB-UIUX-640. **[MAJOR] Shrinkage events cannot be edited or deleted — wrong reason (e.g. "stolen" vs "damaged") permanent.** Compliance + insurance implications. L4, L16.
  `packages/web/src/pages/inventory/ShrinkagePage.tsx:73-99,209-243`

- [ ] WEB-UIUX-641. **[MAJOR] Loaner has no `due_back_at` field, no overdue detection, no charge-customer flow that creates invoice.** Damage cost goes to free-text `notes` only. L5, L13.
  `packages/web/src/pages/loaners/LoanersPage.tsx:312-422`

- [ ] WEB-UIUX-642. **[MAJOR] No "mark loaner as lost" status — enum is `available|loaned` only.** Customer walks off with device → loaner stuck "loaned" forever. L5, L13.
  `packages/web/src/api/endpoints.ts:1218-1259`

- [ ] WEB-UIUX-643. **[MAJOR] Stocktake quick-scan default = "current stock + 1" — silently increments.** Scanning twice = +2. No "confirm existing count" mode. L7, L8.
  `packages/web/src/pages/inventory/StocktakePage.tsx:174-181`

- [ ] WEB-UIUX-644. **[MAJOR] Stocktake count rows read-only — no per-row edit/delete before commit.** Mistake = `cancelMut` nukes entire session. L4.
  `packages/web/src/pages/inventory/StocktakePage.tsx:378-400`

- [ ] WEB-UIUX-645. **[MAJOR] Serial number status flip has zero side effects.** `sold→returned` doesn't increment in_stock, no invoice back-link enforced, no warning. L13, L16.
  `packages/web/src/pages/inventory/SerialNumbersPage.tsx:74-81,186-198`

- [ ] WEB-UIUX-646. **[MAJOR] PO Receive doesn't capture serials at receive time — phantom stock for serialized items until separate manual entry.** L13.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:50-151`

- [ ] WEB-UIUX-647. **[MAJOR] Bulk price `pct === -100` allowed (strict `pct < -100`) — accidentally zeros all prices.** Combined with no-revert = catastrophic. L7, L16.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:330`

#### ED6: Ticket Lifecycle Chaos

- [ ] WEB-UIUX-648. **[BLOCKER] QC sign-off has NO fail path — submit only when allPassed, no "items 3+5 failed" recording.** L5, L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:54-59,136-137`

- [ ] WEB-UIUX-649. **[BLOCKER] QC prior-attempt state never displayed.** `qc.status(ticketId)` API exists but only invalidated, never queried. New tech after reassignment sees no failed-checklist context. L13, L11.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:590-598,649-658`

- [ ] WEB-UIUX-650. **[MAJOR] Closing ticket doesn't stop running BenchTimer — labor billed against closed job.** No timer-state check in status transition. L5, L13.
  `packages/web/src/pages/tickets/TicketActions.tsx:84-95`

- [ ] WEB-UIUX-651. **[MAJOR] BenchTimer only renders for owner — second viewer sees `idle` even when another tech has timer running.** Manager closing ticket = zero in-page signal. L11.
  `packages/web/src/components/tickets/BenchTimer.tsx:62-87`

- [ ] WEB-UIUX-652. **[MAJOR] Manager can't stop someone else's timer — only owner has Stop button.** Orphan timers run until owner starts another. L4, L13.
  `packages/web/src/components/tickets/BenchTimer.tsx:168-177`

- [ ] WEB-UIUX-653. **[MAJOR] No per-device pickup state — ticket-level "Ready for Pickup" all-or-nothing.** Multi-device ticket: device 1 done, device 2 waits parts → no UI for partial pickup. L5, L11.
  `packages/web/src/pages/tickets/TicketDevices.tsx:797-1149`

- [ ] WEB-UIUX-654. **[MAJOR] Defect data exists per item but never read at reorder time.** `benchApi.defects.byItem(itemId)` API exists, zero call sites. Tech can re-add same defective part with no warning. L13.
  `packages/web/src/pages/tickets/TicketDevices.tsx:439-510`
  `packages/web/src/pages/inventory/AutoReorderPage.tsx:42-50`

- [ ] WEB-UIUX-655. **[MAJOR] DefectReporterButton only renders for parts with `inventory_item_id` — quick-added custom parts have no defect-reporting affordance.** Defect signal lost at most relevant moment. L5.
  `packages/web/src/pages/tickets/TicketDevices.tsx:996-1005`

- [ ] WEB-UIUX-656. **[MAJOR] No optimistic-concurrency guard on status or handoff.** Two techs flipping status simultaneously → last-write-wins silently. Loser's optimistic UI flips silently with no toast. L11, L4.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:271-316`
  `packages/web/src/components/team/TicketHandoffModal.tsx:50-72`

- [ ] WEB-UIUX-657. **[MAJOR] Expired estimate still allows Send/Approve/Convert — silently honors stale prices.** L5, L7.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:191-247`

- [ ] WEB-UIUX-658. **[MAJOR] No "renew" / "extend valid_until" / "clone" action on expired estimate.** Customer comes back, operator has to manually clone. L1, L5.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx`

- [ ] WEB-UIUX-659. **[MAJOR] Convert estimate→ticket doesn't snapshot pricing — profit margin set 90 days ago even if parts costs changed.** L13.

- [ ] WEB-UIUX-660. **[MAJOR · BLOCKED] No abandoned-ticket workflow.** 90-day Ready-for-Pickup gets zero escalation lane (lumped with 7-day stale tickets in dashboard). No SMS cadence, no liability disclaimer, no auto-write-off. L5.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-661. **[MINOR] Service price uses native `prompt()` for inline edit — unstyled, no Esc-cancel reliable, invisible to surrounding aria-modal.** L7, L12.
  `packages/web/src/pages/tickets/TicketDevices.tsx:820-823,927-930`

#### ED10: Search/Filter Weirdness

- [ ] WEB-UIUX-662. **[MAJOR] CustomerListPage / TicketListPage / LeadListPage search sends raw input, NO phone/email normalization.** Searching `(555) 123-4567` won't match stored `5551234567`. CSR daily friction. L7, L1.

- [ ] WEB-UIUX-663. **[MAJOR] Bulk selection survives filter changes silently.** Select 100 under `status=open`, change to `status=closed` → badge still "100 selected" but bulk-action hits hidden rows. L8, L11.

- [ ] WEB-UIUX-664. **[MAJOR] Cross-page selection invisible.** Page 1 select 25 → page 2 → "50 selected" badge but page 2 checkboxes unchecked. Mystery state. L11.

- [ ] WEB-UIUX-665. **[MAJOR] Estimate customer-search autocomplete has NO request-id guard or AbortController.** Slow `'Sm'` lands after `'Smith'` opens dropdown → wrong customer attached to estimate. L1.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:86-92`

- [ ] WEB-UIUX-666. **[MAJOR] EstimateListPage bulk delete fires N parallel requests, no batching.** 1000 selected = 1000 simultaneous DELETEs. L15.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:587-601`

- [ ] WEB-UIUX-667. **[MINOR] Filter persistence inconsistent — survives back-button but resets on side-nav menu click.** L5.

- [ ] WEB-UIUX-668. **[MINOR] Saved filter deleted by user A → user B's cache still applies the deleted filter (no cross-tab invalidation).** L6.
  `packages/web/src/pages/tickets/TicketListPage.tsx:201-320`

- [ ] WEB-UIUX-669. **[MINOR] Invoice empty state: just icon + "No invoices found" — no "clear filters" CTA.** L8.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:426-430`

- [ ] WEB-UIUX-670. **[MINOR] No "Select all 4,832 matching" affordance like Gmail.** Bulk actions max at pagesize. L1.

- [ ] WEB-UIUX-671. **[MINOR] Native `<input type="date">` for from/to has no max/min — future date `2099-01-01` allowed silently.** L7.
  `packages/web/src/pages/customers/CustomerListPage.tsx:636-642`

- [ ] WEB-UIUX-672. **[MINOR] DateRangePicker `from > to` (inverted) accepted by typing.** L7.
  `packages/web/src/components/shared/DateRangePicker.tsx:109-115`

- [ ] WEB-UIUX-673. **[MINOR] Old/invalid status param in URL silently passed to server.** "No items match" with no flag that filter value is invalid. L8, L14.

- [ ] WEB-UIUX-674. **[MINOR] Export with current filter applied — no "Export filtered / Export all" choice.** Surprise = recipient gets subset. L8.

- [ ] WEB-UIUX-675. **[MINOR] CommandPalette saveRecentSearch persists to sessionStorage — doesn't filter sensitive data (SSN, card-shape).** L16.
  `packages/web/src/components/shared/CommandPalette.tsx:142-169`

#### ED11: Print/Receipt Failures

- [ ] WEB-UIUX-676. **[MAJOR] Drawer-pop button optimistically toasts "Cash drawer opened" on HTTP 200.** No driver poll, no tactile confirm. Drawer disconnect/jam = silent fail with green toast. L8.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:430-437`

- [ ] WEB-UIUX-677. **[MAJOR] Print Receipt is fire-and-forget `window.print()` — no printer-online pre-check, no success/failure callback.** Cashier clicks → silence → walks away. L8.
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:151-157`

- [ ] WEB-UIUX-678. **[MAJOR · BLOCKED] No "if printer fails, still email" auto-fallback.** Three independent buttons, `handlePrintReceipt` calls `resetAll()` BEFORE navigation → loses access to email button. L4.
  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:96-130,367-389`

- [ ] WEB-UIUX-679. **[MAJOR] Z-Report uses single `window.print()` with no resume-on-jam, no save-as-PDF fallback, no `printed_at` audit flag.** L4, L13.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:81`

- [ ] WEB-UIUX-680. **[MAJOR] Mass label batch monolithic — one bad SKU = whole job fails or quietly truncates.** Server returns single blob, no per-item state, no "X succeeded Y failed". L8.
  `packages/web/src/pages/inventory/MassLabelPrintPage.tsx:42-95`

- [ ] WEB-UIUX-681. **[MAJOR] Invoice print fallback uses `window.print()` against current SPA route — prints sidebar+toolbars+breadcrumbs.** Same on EstimateDetailPage. L9, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:367-373`
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:249`

- [ ] WEB-UIUX-682. **[MAJOR] `checkin_auto_print_label` toggle marked "live" but has NO consumer.** Setting persists, nothing reads it. SuccessScreen never honors. L5, L8.
  `packages/web/src/pages/settings/PosSettings.tsx:233-238`
  `packages/web/src/pages/settings/settingsMetadata.ts:669-674`

- [ ] WEB-UIUX-683. **[MAJOR] No printer-status telemetry anywhere — zero hits for printer.*offline / printer_status.** Cannot pre-disable Print buttons when no printer connected. L8, L11.

- [ ] WEB-UIUX-684. **[MINOR] PrintPreviewModal paper-size selection has no in-modal override.** 80mm receipt rendered on 58mm thermal → right edge clipped. L9.
  `packages/web/src/components/shared/PrintPreviewModal.tsx:16-21`

- [ ] WEB-UIUX-685. **[MINOR] LabelLayout silently truncates devices to first 2 — multi-device tickets lose 3rd+ device on bench label.** No "+N more". L13.
  `packages/web/src/pages/print/PrintPage.tsx:936-938`

- [ ] WEB-UIUX-686. **[MINOR] PrintPage autoprint `useEffect` deps include query result — refetch on focus triggers second `window.print()`.** L1, L13.
  `packages/web/src/pages/print/PrintPage.tsx:993-998`

- [ ] WEB-UIUX-687. **[MINOR] QR receipt has no human-readable fallback URL or numeric code — customer can't scan, no typeable code.** Cellular customer can't access LAN-internal serverUrl. L4, L11.
  `packages/web/src/components/billing/QrReceiptCode.tsx:20-60`

- [ ] WEB-UIUX-688. **[MINOR] SuccessScreen `resetAll()` called BEFORE print navigation — print page fails, cart already wiped.** L4.
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:144-148`

#### ED12: Notifications/Automations Gaps

- [ ] WEB-UIUX-689. **[BLOCKER · BLOCKED] Template syntax fragmented — automations use `{var}`, campaigns use `{{var}}`, no client-side schema validator.** "first_nam" typo = 1000 SMS with literal text. L7, L16.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/settings/AutomationsTab.tsx:59-69`
  `packages/web/src/pages/marketing/CampaignsPage.tsx:84,727`

- [ ] WEB-UIUX-690. **[BLOCKER] No unknown-token detection on template bodies.** Save accepts any `{...}` token, dryRun success toast slices first 60 chars. L7, L8.
  `packages/web/src/pages/settings/AutomationsTab.tsx:182-189`

- [ ] WEB-UIUX-691. **[BLOCKER · BLOCKED] Off-hours auto-reply has no loop-detection.** Auto-reply phrasing matches automation trigger → re-fires. SMS spend bomb. L5, L16.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/communications/components/OffHoursAutoReplyToggle.tsx`

- [ ] WEB-UIUX-692. **[MAJOR] Stale phone hard-coded in automation `to` field — no warning that hard-coded value won't track customer record updates.** L5, L11.
  `packages/web/src/pages/settings/AutomationsTab.tsx:170-180`

- [ ] WEB-UIUX-693. **[MAJOR] Campaign opt-out compliance regex catches phrasings but doesn't show which segment members are suppressed.** Operator firing 2000 blast can't see "X opted out, will not receive". L7, L16.
  `packages/web/src/pages/marketing/CampaignsPage.tsx:81-88`

- [ ] WEB-UIUX-694. **[MAJOR] No duplicate-rule detection — two rules sharing `(trigger_type, trigger_config)` both fire silently.** Dry-run shows single rule only. L3, L8.
  `packages/web/src/pages/settings/AutomationsTab.tsx`

- [ ] WEB-UIUX-695. **[MAJOR] Disable rule toggle has no UI feedback about pending/queued sends.** Disabled rule, queued effects honored or aborted? L11, L8.
  `packages/web/src/pages/settings/AutomationsTab.tsx:606-612`

- [ ] WEB-UIUX-696. **[MAJOR] ScheduledSendModal naive about DST — March 9 03:00 EDT-edge case ambiguous.** Zoneless `<input type="datetime-local">`, no UTC display, no impossible-time rejection. L7, L14.
  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx:27-83`

- [ ] WEB-UIUX-697. **[MAJOR] FailedSendRetryList doesn't distinguish permanent failures (5xx hard bounce, opted-out).** Retry button always enabled — operator can hammer bounced address. L8, L16.
  `packages/web/src/pages/communications/components/FailedSendRetryList.tsx:21-31`

- [ ] WEB-UIUX-698. **[MAJOR] Segments have no concept of intersection / precedence.** Customer in "VIP" AND "High Risk" → which campaign wins? Undocumented. L5, L14.
  `packages/web/src/pages/marketing/SegmentsPage.tsx`

- [ ] WEB-UIUX-699. **[MAJOR] Automation triggers don't include `customer_in_segment`.** Operator wanting "send VIP auto-reply" cannot express it. L5.
  `packages/web/src/pages/settings/AutomationsTab.tsx:42-48`

- [ ] WEB-UIUX-700. **[MINOR] Segment value coercion: `Number("$50")` = NaN → falls through to string → segment matches zero customers silently.** L7.
  `packages/web/src/pages/marketing/SegmentsPage.tsx:252-264`

- [ ] WEB-UIUX-701. **[MINOR · BLOCKED] Campaign Run Now has no rate-limit / dispatch-lock indicator.** Two operators click within 30s → same customer in both segments gets 2 SMS. L5, L8.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/marketing/CampaignsPage.tsx:381-405`

- [ ] WEB-UIUX-702. **[MINOR] Segment delete confirm doesn't enumerate referencing campaigns.** Active campaign breaks silently. L7.
  `packages/web/src/pages/marketing/SegmentsPage.tsx:172-189`

### Web UI/UX Audit — Pass 10 (2026-05-05, flow walk: process refund — server-vs-client gaps)

Re-walk of the "Process Refund" user flow, focusing on **server-side capability vs client wiring** rather than label/copy (already covered in Pass 8 #423-433). Key finding: server has TWO refund APIs (`refunds.routes.ts` with approval workflow + `creditNotes.routes.ts` collection) plus POS-return endpoint that web never calls. The Credit Note path on InvoiceDetail is the ONLY surfaced refund flow.

#### Blockers — Unwired server APIs

- [ ] WEB-UIUX-703. **[BLOCKER] No web UI for `refunds.routes.ts` API surface.** Server exposes POST `/refunds` (idempotent + `refunds.create` perm), PATCH `/refunds/:id/approve` (+`refunds.approve`), PATCH `/refunds/:id/decline`, GET `/refunds/credits/:customerId`, POST `/refunds/credits/:customerId/use`, GET `/refunds/credits/liability`. Zero callers in `packages/web/src` (grep `/refunds`, `refundsApi` → 0). Operators have only Credit Note path — no approval workflow, no store-credit redemption at POS, no manager liability dashboard. L8, L3, L1.
  `packages/server/src/routes/refunds.routes.ts:107,253,418,439,462,529`
  <!-- meta: fix=add-refundsApi-endpoint-shim+RefundsListPage+ApprovalQueue+StoreCreditRedeemModal -->

- [ ] WEB-UIUX-704. **[BLOCKER] No web UI for `creditNotes.routes.ts` collection endpoints.** Server exposes GET `/credit-notes`, GET `/credit-notes/:id`, POST `/credit-notes/:id/apply` (use credit), POST `/credit-notes/:id/void`. Web only calls invoice-scoped POST `/invoices/:id/credit-note`. No list page, no detail page, no apply-to-future-invoice flow, no void path for mistaken credit notes. L3, L8.
  `packages/server/src/routes/creditNotes.routes.ts:63,135,237,318`
  <!-- meta: fix=add-creditNotesApi+CreditNotesListPage+apply-modal+void-mutation -->

- [ ] WEB-UIUX-705. **[BLOCKER] `posApi.return` defined in endpoints.ts but never invoked.** "Cash refund on existing sale" idempotent endpoint at `/pos/return` — declared with full idempotency-key boilerplate but no UI consumer. Cashier on POS cannot run a return without leaving POS to InvoiceDetail. L8, L3.
  `packages/web/src/api/endpoints.ts:749-761`

- [ ] WEB-UIUX-706. **[BLOCKER] Credit Note button has no `requirePermission('invoices.credit_note')` gate.** Server checks perm; client renders button to all roles. Junior staff click → 403 → generic toast "Failed to create credit note". L12, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`
  <!-- meta: fix=wrap-button-in-PermissionBoundary+invoices.credit_note -->

#### Major — State visibility, recovery, integration

- [ ] WEB-UIUX-707. **[MAJOR] InvoiceDetailPage never displays credit notes already issued against the invoice.** No fetch of `credit_note_for = invoiceId` siblings. Operator who issued $50 credit yesterday opens invoice today, sees no record on this page. Must navigate to InvoiceListPage and find the negative-total entry to inspect. L8, L1.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:474-548`
  <!-- meta: fix=add-Credit-Notes-section-below-Payment-Timeline+invoice.credit_notes-from-server -->

- [ ] WEB-UIUX-708. **[MAJOR] `'refunded'` invoice status is dead UI code — never set by native refund flows.** STATUS_COLORS at `InvoiceListPage:33` and `CustomerDetailPage:1685` map `refunded → purple`, but server only sets `'refunded'` from RepairShopr/RepairDesk/MyRepairApp importers, never from credit-note or refund routes. Native flow leaves invoice as `'paid'` and creates a sibling negative-total invoice. Color swatch in donut chart promises a status the native refund can't produce. L8, L9.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:33,41` `packages/web/src/pages/customers/CustomerDetailPage.tsx:1685`
  `packages/server/src/services/repairShoprImport.ts:773-774` `packages/server/src/services/repairDeskImport.ts:1290`
  <!-- meta: fix=either-set-refunded-on-original-when-fully-credited-OR-remove-dead-color -->

- [ ] WEB-UIUX-709. **[MAJOR] Credit Note destructive but no `requireTyping` confirm — Void requires typing the order ID.** Asymmetric friction: Void (which has 5s undo + reverses cleanly) demands typing; Credit Note (which moves money out, has NO undo, NO client-side void path) is one click + amount + reason. Operator misclick refunds $200. L1, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:807-817` (Void) vs `737-805` (CreditNote)
  <!-- meta: fix=ConfirmDialog-with-requireTyping-amount-OR-add-undoableAction-window -->

- [ ] WEB-UIUX-710. **[MAJOR] Credit Note has no undo window; Void has 5s undo (`useUndoableAction`).** Same severity action, different recovery affordance. Operator-initiated mistake on credit note is permanent from web (server has POST /credit-notes/:id/void but unwired — see WEB-UIUX-704). L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177,110-135`

- [ ] WEB-UIUX-711. **[MAJOR] Credit Note modal does not show store-credit overflow preview.** Server (`invoices.routes.ts:1259-1289`) silently creates `store_credits` row when credit > remaining due. Operator never told customer accumulated $X store credit. Customer leaves not knowing they have a balance. L8, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`

- [ ] WEB-UIUX-712. **[MAJOR] Customer's existing `store_credits` balance not displayed anywhere in web.** Server endpoints `GET /refunds/credits/:customerId` + `POST /refunds/credits/:customerId/use` exist; CustomerDetailPage has no panel, InvoiceDetailPage cannot apply prior credit toward outstanding. Customers expecting "use my $20 credit" cannot — operator runs cash payment instead, ledger drifts. L8, L1.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx`
  <!-- meta: fix=add-Store-Credit-card-on-customer-page+Apply-Credit-button-on-invoice -->

- [ ] WEB-UIUX-713. **[MAJOR] `RefundReasonPicker` swallows note text typed before reason picked.** Line 47-50: `handleNoteChange` only fires `onChange` when `localReason` is non-null. Operator who types a 3-sentence justification first, picks reason after, loses the note text from the parent state — but the local textarea still shows it (false sense of safety). Submit fires with `note=""`. L7, L1.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:47-50`
  <!-- meta: fix=always-fire-onChange-with-current-or-pending-reason -->

- [ ] WEB-UIUX-714. **[MAJOR] `'other'` reason permits empty note — refund reporting useless.** Picker hint says "Free-form reason in the note" implying note required when `other`; `handleCreditNote` (line 305) only validates `reason` exists, not note when `other`. Reports group all "other"-coded refunds with no detail. L7, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:305` `packages/web/src/components/billing/RefundReasonPicker.tsx:23`
  <!-- meta: fix=if-code===other-require-note.trim().length>=10 -->

- [ ] WEB-UIUX-715. **[MAJOR] Credit Note submit invalidates `['invoices']` but not `['invoice-stats']` — donut chart on list page stays stale.** `creditNoteMutation.onSuccess` line 169-171 misses the stats key used by `InvoiceListPage:175`. Operator returns to list, status distribution still shows old paid count. L15.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-171`

- [ ] WEB-UIUX-716. **[MAJOR] Credit Note button uses `<CreditCard>` icon — semantically conflicts (this is not a card-payment).** Operators scanning header read it as "charge card" or "save card on file". Should be `Receipt` / `Undo2` / `RotateCcw` / `BanknoteArrowDown` (lucide). L9, L1.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:378`

- [ ] WEB-UIUX-717. **[MAJOR] Credit Note backdrop click dismisses with no unsaved-changes guard.** Operator types $147 + reason + 480-char note, accidentally clicks backdrop, all lost. No `beforeunload`-style confirm. Same defect on Payment Modal. L8, L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:744,597`
  <!-- meta: fix=guard-on-isDirty -->

- [ ] WEB-UIUX-718. **[MAJOR] Credit Note button gated on `Number(invoice.total) > 0` — hides for fully-credited invoices, but ALSO hides for legitimate $0 invoices that received an over-payment.** Edge: $0 invoice, $50 deposit recorded by mistake — cashier wants to refund the $50, button gone. L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376`
  <!-- meta: fix=gate-on-amount_paid>0-not-total>0 -->

- [ ] WEB-UIUX-719. **[MAJOR] Credit Note primary submit is `bg-amber-600` — cautionary but not destructive.** Pattern elsewhere: amber=warn, red=destructive (Void uses red border + red text). Credit Note moves money out — deserves at least red-tinted variant or explicit warning iconography. L9, L1.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-801`

- [ ] WEB-UIUX-720. **[MAJOR] Header action overload — 6 buttons (Record Payment, Payment Plan, Financing, Print, Credit Note, Void) on unpaid invoice.** No "More actions ▼" overflow. Tablet (768 px) wraps + shrinks; primary action loses prominence vs visual cluster. L1, L11.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:342-389`
  <!-- meta: fix=primary=Record-Payment-keep-Print-collapse-rest-into-overflow-menu -->

- [ ] WEB-UIUX-721. **[MAJOR] No "Refund to original card" branch — server has no card-refund route either.** `blockchyp.routes.ts` exposes process-payment + void-payment but no refund endpoint. Card-charged customer always gets store credit, never card-credited back. Common SaaS expectation broken (chargeback risk). L8, L16.
  `packages/server/src/routes/blockchyp.routes.ts:131,482` (no refund route)
  <!-- meta: fix=add-blockchypApi.refund+wire-from-CreditNote-modal-when-card-payment-exists -->

- [ ] WEB-UIUX-722. **[MAJOR · BLOCKED] After credit-note success, no "send credit-note slip" prompt.** Mirror of `showReceiptPrompt` after payment (line 102, 676-735) absent for credit notes. Customer leaves register without paper/SMS/email proof of refund. Compare to payment flow which has 3-channel send-receipt modal. L8, L3.
  **STATUS: BLOCKED** — deferred until messaging (email/SMS) infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-177` (credit note success) vs `:96-103` (payment success)
  <!-- meta: fix=mirror-showReceiptPrompt-trigger-on-creditNote-success -->

#### Minor — Polish, edge cases

- [ ] WEB-UIUX-723. **[MINOR] Credit Note modal `<input min="0.01" max={amount_paid}>` is browser-advisory only.** Pasting `0.001` or `999999` accepted; server enforces. Add explicit `parseFloat` validation matching server bounds. L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:763`

- [ ] WEB-UIUX-724. **[MINOR] Credit Note "Max: $X (amount paid)" hint duplicates `max=` attr but uses raw `$` not `formatCurrency`.** Inconsistent currency rendering inside same dialog. L9, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:776-778`

- [ ] WEB-UIUX-725. **[MINOR] RefundReasonPicker uses `useState` for localReason/localNote initialised from props once — parent state changes don't re-sync.** Works today because parent only resets on success, but breaks if parent ever pre-fills (e.g., editing a draft credit note). L4.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:39-40`

- [ ] WEB-UIUX-726. **[MINOR] RefundReasonPicker note `maxLength=500` silently truncates paste — no count, no warning.** Operator pasting 800-char dispute log doesn't know last 300 chars dropped. L8.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:85-92`
  <!-- meta: fix=add-X/500-counter+toast-on-truncate -->

- [ ] WEB-UIUX-727. **[MINOR] RefundReasonPicker grid-cols-2 cards on mobile — 6 reasons × 2-line label = ~6 row tap targets, scroll within modal.** Could collapse to single column on `sm:` and below. L11.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:62`

- [ ] WEB-UIUX-728. **[MINOR] Credit Note success toast "Credit note created" omits issued amount + credit-note number.** Cannot confirm "I refunded $X, credit note CN-NNNN". Compare payment toast which says nothing about amount either — pattern flaw. L8, L14.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:172`

- [ ] WEB-UIUX-729. **[MINOR] Credit Note dialog has `aria-modal="true"` and `aria-labelledby` but no focus trap.** `autoFocus` on amount input but Tab cycles into underlying invoice page. Same defect as Payment Modal. L12.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:739-746`

- [ ] WEB-UIUX-730. **[MINOR] Credit Note Esc-to-close handler shared with Payment Modal — logical race if both somehow open Esc closes Credit Note only.** Brittle. L13.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:60-69`

- [ ] WEB-UIUX-731. **[MINOR] `creditNoteMutation` `onError` catches `e?.response?.data?.message` but no field-level highlight on the error.** Operator just gets generic toast, must re-read modal to find the offending field. L7, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:176`

- [ ] WEB-UIUX-732. **[MINOR] `STATUS_COLORS` map at top of InvoiceDetailPage has `unpaid/partial/paid/void` but missing `'refunded'` — yet List + Customer pages have it.** If server ever sets refunded, detail page renders empty class (no badge color). Inconsistent across pages even within stale-status assumption. L9.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:26-31`

- [ ] WEB-UIUX-733. **[NIT] Credit-note `code` + `note` composed into one `reason` string at client (`${d.code}: ${d.note}`) before send.** Server already accepts `code` + `note` as separate fields (migration 150) and stores them in `credit_note_code` / `credit_note_note`. The composed `reason` is now redundant — server stores both. Drift. L4.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-167`


### Web UI/UX Audit — Edge-Case Pass B (2026-05-05, more agents)

#### ED9: Concurrent Editor Conflicts

- [ ] WEB-UIUX-734. **[BLOCKER] No version/etag on any write — server is naive last-write-wins.** Two cashiers editing same ticket — one notes, one status — both succeed; later PUT wins for fields it sends. L11, L4.
  `packages/web/src/api/client.ts:372-394` (acknowledged)

- [ ] WEB-UIUX-735. **[BLOCKER] ReceiptSettings/InvoiceSettings/TicketsRepairsSettings/BlockChypSettings/SmsVoiceSettings/DataRetentionTab all PUT entire config blob.** Sibling tab clobber bug (PosSettings already fixed via OWNED_KEYS). L5, L16.
  Multiple settings tabs share `['settings','config']` cache

- [ ] WEB-UIUX-736. **[BLOCKER] Inventory adjustStock sends raw delta with NO expected-quantity verification.** Operator A reduces by 1, Operator B types +5 simultaneously → both apply blindly. L6, L11.
  `packages/web/src/pages/inventory/InventoryDetailPage.tsx:101-112,127-131`

- [ ] WEB-UIUX-737. **[MAJOR] Optimistic mutations cancel queries but never reconcile WS pushes mid-flight.** User flips status to Done → WS pushes "In Progress" from co-worker → invalidate fires → user's optimistic Done disappears mid-render. Pill flickers, no signal. L11, L4.
  Tickets, sidebar, notes, kanban share pattern

- [ ] WEB-UIUX-738. **[MAJOR] CustomerDetailPage InfoTab — WS-driven `customer:updated` invalidation + `useEffect setForm(newCustomer)` overwrites in-progress edits silently.** L6, L11.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1104-1167,1200-1201`

- [ ] WEB-UIUX-739. **[MAJOR] `useDraft` 2-tab race — same draft key in two tabs → setItem clobbers each other on debounce-tick.** No `storage` event listener, no merge. L6.
  `packages/web/src/hooks/useDraft.ts:28-32,86,215-219`

- [ ] WEB-UIUX-740. **[MINOR] `useWsStore.lastMessage` stored on every event but ZERO consumers.** Pages can't show "Bob just edited this — refresh?" banners. Wasted state. L11.
  `packages/web/src/hooks/useWebSocket.ts:25-28,454`

- [ ] WEB-UIUX-741. **[MINOR] No "stale data" age indicator anywhere.** Zero "edited X ago, refresh" badges. L11.

#### ED5: Auth/Session/Permission Edges

- [ ] WEB-UIUX-742. **[BLOCKER] SwitchUser is sticky forever — no auto-revert, no banner.** Manager switches in to override, walks away, cashier sells under manager identity. Only signal = name in Header avatar. L16, L11.
  `packages/web/src/components/layout/Header.tsx:101,540-555`
  `packages/web/src/stores/authStore.ts:113-127`
  <!-- meta: fix=ImpersonationBanner-style-yellow-bar+auto-revert-after-N-min -->

- [ ] WEB-UIUX-743. **[BLOCKER] Permission downgrade mid-session never re-renders gates.** `performRefresh()` writes new accessToken but doesn't parse JWT or re-fetch /auth/me. Demoted user keeps using manager-only pages until manual logout. L16.
  `packages/web/src/api/client.ts:78-108`
  `packages/web/src/components/shared/PermissionBoundary.tsx:18-25`

- [ ] WEB-UIUX-744. **[BLOCKER] `auth-cleared` fires on cross-tab silent refresh — wipes drafts/dismissals on active tab even though SAME USER.** Tab B refreshes → tab A's drafts gone. L6, L7.
  `packages/web/src/stores/authStore.ts:269-282`
  `packages/web/src/hooks/useDraft.ts:59`

- [ ] WEB-UIUX-745. **[MAJOR] Mid-action 401 → form data lost.** Forced logout → SPA nav to /login → wipeAllDrafts() synchronous. Re-login lands on fromPath but form is fresh state. L4, L7.
  `packages/web/src/stores/authStore.ts:294-309`

- [ ] WEB-UIUX-746. **[MAJOR] Cross-tab logout wipes drafts in current tab even mid-form — NO toast, NO warning before redirect.** L6, L4.
  `packages/web/src/stores/authStore.ts:213-228`

- [ ] WEB-UIUX-747. **[MAJOR] No global inactivity timeout / no expiring-session warning.** TODO since DASH-6. Token rolls forward indefinitely. L1, L16.
  `packages/web/src/stores/authStore.ts:62-71`

- [ ] WEB-UIUX-748. **[MAJOR] POS cart bleeding partially mitigated (user-scoped key) but `auth-cleared` doesn't clear POS store.** Stale cart from cashier A persists, resumes on relogin (privacy: customer phone/email attached). L16.
  `packages/web/src/pages/unified-pos/store.ts:64-68`

- [ ] WEB-UIUX-749. **[MAJOR] Trial expiry mid-action: 403 upgrade_required opens modal — but CART NOT PERSISTED before modal.** Cashier mid-sale loses cart. L4, L8.
  `packages/web/src/api/client.ts:294-313`

- [ ] WEB-UIUX-750. **[MAJOR] Mid-checkout 401 → re-login lands back on POS but no banner: "Your previous checkout was interrupted. Check Tickets to verify."** Cashier may run sale twice on different till. L8, L11.

- [ ] WEB-UIUX-751. **[MINOR] Expired password reset link copy intentionally vague + no resend affordance.** Three-click recovery (back to login → forgot → email → wait). L4, L14.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:71-84`

- [ ] WEB-UIUX-752. **[MINOR] PIN modal lockout uses sessionStorage scoped per-tab → multi-tab brute force (10 attempts in 2 tabs).** Server catches but UI message misleading. L16.
  `packages/web/src/components/shared/PinModal.tsx:21-50`

- [ ] WEB-UIUX-753. **[MINOR] TrialBanner expired state dismissible — silenced forever (key on trialEndsAt which doesn't change).** Should be non-dismissible. L8, L16.
  `packages/web/src/components/shared/TrialBanner.tsx:52-74`

#### ED13: File Upload Chaos

- [ ] WEB-UIUX-754. **[BLOCKER] No global drag-drop guard — zero `addEventListener('drop'` outside specific handlers.** Drag PDF/photo onto any non-handler region → browser navigates to file://, app unloads, all unsaved forms lost. L7, L4.
  `packages/web/src/main.tsx`
  <!-- meta: fix=window-addEventListener-dragover-drop-preventDefault -->

- [ ] WEB-UIUX-755. **[BLOCKER] ReceiptSettings logo upload accepts SVG (image/svg+xml) — no magic-byte sniff.** XSS surface via persisted `receipt_logo` data URI when consumed by mobile/email clients. L16.
  `packages/web/src/pages/settings/ReceiptSettings.tsx:70-82`
  `packages/web/src/pages/settings/InvoiceSettings.tsx:135`

- [ ] WEB-UIUX-756. **[MAJOR] PhotoCapturePage single multipart POST of all photos — connection drop = entire batch fails.** Re-upload 200MB on cellular. No chunking, no resumable, no AbortController. L4, L8.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:94-123`

- [ ] WEB-UIUX-757. **[MAJOR] CommunicationPage `handleImageSelect` has ZERO pre-validation while QuickSmsAttachmentButton has 5MB+MIME guards.** 20MB photo blasts straight to server, generic "Upload failed" toast. L7, L8.
  `packages/web/src/pages/communications/CommunicationPage.tsx:1469-1485` vs `QuickSmsAttachmentButton.tsx:32-55`

- [ ] WEB-UIUX-758. **[MAJOR] HEIC blind spot — PhotoCapturePage uses `file.type.startsWith('image/')` so HEIC accepted but Chrome/Firefox 404 thumbnails.** L7, L11.
  `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:60-70`

- [ ] WEB-UIUX-759. **[MAJOR] QcSignOffModal + DefectReporterButton `URL.createObjectURL` blobs NEVER `revokeObjectURL`-ed — leaks until tab close.** L15.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:128-134`
  `packages/web/src/components/tickets/DefectReporterButton.tsx:86-91`

- [ ] WEB-UIUX-760. **[MAJOR] InventoryListPage CSV import casts to `unknown as ImportInventoryItem[]` — no required-column validation, no errors-CSV download.** CustomerListPage does this right. L7, L8.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:377-390`

- [ ] WEB-UIUX-761. **[MAJOR] ExpensesPage receipt upload `accept="image/*,application/pdf"` — no size cap, no MIME allow-list, no magic-byte sniff.** 50MB PDF → 413 → generic toast. L7, L8.
  `packages/web/src/pages/expenses/ExpensesPage.tsx:308-314`

- [ ] WEB-UIUX-762. **[MINOR] CustomerListPage / InventoryListPage CSV `readAsText` no size cap, no encoding declaration.** 200MB CSV hangs renderer; Windows-1252/Shift_JIS exports show mojibake. L15.

- [ ] WEB-UIUX-763. **[MINOR] CommunicationPage `safeMediaUrl` accepts any http(s) URL → leaks Referer to attacker.example.** No `referrerpolicy="no-referrer"` on rendered img/a. L16.
  `packages/web/src/pages/communications/CommunicationPage.tsx:2120-2145`

#### ED14: Tax/Pricing/Discount Chaos

- [ ] WEB-UIUX-764. **[BLOCKER] Discount stacking has NO canonical order — single cart-wide `discount` slot.** No model for "10% off + $5 off + member 20%" with sequence/basis. Subtle base-vs-net errors. L7, L13.
  `packages/web/src/pages/unified-pos/store.ts:101-103,235-237`

- [ ] WEB-UIUX-765. **[BLOCKER] No `tax_exempt` flag on customer record.** Cashiers must manually toggle each line's `taxable`. Customer change AFTER lines added doesn't auto-flip. Silent tax on non-profit invoice. L6, L13.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1123,1191,1253-1254`

- [ ] WEB-UIUX-766. **[BLOCKER] Discount cap permission gate not implemented — cashier can apply $9999 discount on $50 sale.** `pos_max_cashier_discount_pct` setting missing. L16.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:880-888`

- [ ] WEB-UIUX-767. **[BLOCKER] Group/auto-apply discount silently flips when customer changes mid-cart.** Switch to customer with `group_auto_apply=true` → cart total drops 10-20% silently. L6, L8.
  `packages/web/src/pages/unified-pos/CustomerSelector.tsx:91-102`

- [ ] WEB-UIUX-768. **[MAJOR] No multi-jurisdiction tax breakdown — single `Tax (8.875%)` line.** Settings supports list but UI surfaces only one. CA/FL receipts require local rate broken out. L7, L9.
  `packages/web/src/pages/unified-pos/totals.ts:94`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:464-466`

- [ ] WEB-UIUX-769. **[MAJOR] Refund line cannot be entered — clamp at parse hides use case.** Trade-in credits, returns can't be expressed at POS. L5, L7.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:599-603`

- [ ] WEB-UIUX-770. **[MAJOR] Tip/gratuity not implemented + no rounding-mode selector.** No tip-on-card flow, no Canada/Switzerland 5¢ rounding. L5, L7.

- [ ] WEB-UIUX-771. **[MAJOR] Tax-rate change updates cart silently mid-checkout — no banner.** "Your total is $108.88" → "$109.13" between cashier saying it and tap to charge. L6, L8.
  `packages/web/src/hooks/useDefaultTaxRate.ts:18-22`

- [ ] WEB-UIUX-772. **[MAJOR] Bulk-price adjustment changes don't recompute existing cart lines.** Two cashiers add same item → different totals depending on add-time. L6, L11.
  `packages/web/src/pages/settings/RepairPricingTab.tsx:823-971`

- [ ] WEB-UIUX-773. **[MAJOR] Tax-inclusive flag locked at line add — no UI to flip in cart.** ProductRow shows "No tax" for tax-inclusive item, cashier panic. L7, L9.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:756-771`

- [ ] WEB-UIUX-774. **[MAJOR] `Math.max(0, total)` clamp masks refund-driven negative cart.** `Total: $0.00` instead of negative store-credit issuance. L7, L13.
  `packages/web/src/pages/unified-pos/totals.ts:95`

- [ ] WEB-UIUX-775. **[MAJOR] Persisted cart in localStorage outlives tax-rate/customer-group config changes.** Reopen cart next morning → stale snapshot. L6.
  `packages/web/src/pages/unified-pos/store.ts:289-304`

- [ ] WEB-UIUX-776. **[MINOR] `group_discount_pct` field overloaded — % when type='percent', $ when type='fixed'.** No UI distinction; $0.50 fixed auto-applies like 50% percent. L7, L4.
  `packages/web/src/pages/unified-pos/totals.ts:79-85`

- [ ] WEB-UIUX-777. **[MINOR] Per-line tax cell uses pre-discount math, summary uses post-discount — row tax doesn't reconcile to total tax.** L9.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:621,655,769,809`

- [ ] WEB-UIUX-778. **[MINOR] Discount input unbounded `parseFloat` — "1e3" parses to 1000.** Same in CashModal split amounts. L7.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:881-887`

#### ED15: Time/Timezone/Scheduling

- [ ] WEB-UIUX-779. **[BLOCKER] No shop-timezone awareness on display — all surfaces render in browser local.** `formatTime/formatDateTime` never accept `timeZone` option. Shop has `store_timezone` setting, never consumed. L6, L14.
  `packages/web/src/utils/format.ts:101-144`

- [ ] WEB-UIUX-780. **[MAJOR] CalendarPage uses BROWSER TZ for input AND display, ignoring shop TZ entirely.** Receptionist in PST scheduling for shop in EST = 3 hours off. Zero "Times shown in [Shop TZ]" disclaimer. L6.
  `packages/web/src/pages/leads/CalendarPage.tsx:176-192,524,607,661,125-127`

- [ ] WEB-UIUX-781. **[MAJOR] DST spring-forward gap silently materialised — picking 02:30 on March 8 lands at 03:30 MDT.** No "non-existent local time" check. 15-min select includes 4 invalid slots. L7.
  `packages/web/src/pages/leads/CalendarPage.tsx:179-192`

- [ ] WEB-UIUX-782. **[MAJOR] DST fall-back ambiguity silently picks first occurrence.** Shift end 02:00 + start 01:00 on rollback day → undercount or silent overlap. Payroll bug. L7, L13.

- [ ] WEB-UIUX-783. **[MAJOR] ShiftSchedulePage `start_at: newStart` sends `<input type="datetime-local">` value RAW with no offset.** Server interprets as UTC vs local vs shop-TZ — undefined. L7, L14.
  `packages/web/src/pages/team/ShiftSchedulePage.tsx:108-113`

- [ ] WEB-UIUX-784. **[MAJOR] ReportsPage date range presets mix UTC and local arithmetic.** `todayStr() = .toISOString().slice(0,10)` is UTC; "this_month" computes local then slices UTC. Late-evening runs west of UTC drift to previous month. L7, L13.
  `packages/web/src/pages/reports/ReportsPage.tsx:74-114`

- [ ] WEB-UIUX-785. **[MAJOR] No fiscal-year support anywhere — `grep -rn "fiscal"` returns 0 hits.** DateRangePicker has no this_year/last_year/ytd preset. L5.
  `packages/web/src/components/shared/DateRangePicker.tsx:26-34`

- [ ] WEB-UIUX-786. **[MINOR] InstallmentPlanWizard local-midnight + `.toISOString().slice(0,10)` — DST-crossing weekly plan can preview due-date one day earlier.** L6.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:67-78`

- [ ] WEB-UIUX-787. **[MINOR] PaymentLinks `expires_at` date-only sent as YYYY-MM-DD — server picks own end-of-day in own TZ.** Hawaii customer at 9pm sees "Expired" unexpectedly. L7, L14.
  `packages/web/src/pages/billing/PaymentLinksPage.tsx:135-148,238-241`

- [ ] WEB-UIUX-788. **[MINOR] `.toISOString().slice(0,10)` anti-pattern in 8+ sites.** Latent local-vs-UTC drift bug west of UTC after ~4pm. Pattern caught/fixed in ExpensesPage but lesson didn't propagate. L7.

- [ ] WEB-UIUX-789. **[MINOR] `timeAgo()` appends `Z` only if no `Z`/`+` — `2026-04-30T10:00:00-05:00Z` malformed.** Mixed-format timestamps produce wrong "ago" labels. L14.
  `packages/web/src/utils/format.ts:154-168`

- [ ] WEB-UIUX-790. **[MINOR] BenchTimer visibility refetch is correct but visible jitter on wake — local elapsed snaps high then snaps to server.** L13.
  `packages/web/src/components/tickets/BenchTimer.tsx:92-121`

#### ED16: Barcode/Scanner Input

- [ ] WEB-UIUX-791. **[BLOCKER] Stocktake "quick-scan default" sets counted_qty to `expected + 1` not actual physical count.** Scanning 5 units of `in_stock=3` → counted_qty=4, not 5. STOCKTAKE MATH WRONG. L7, L13.
  `packages/web/src/pages/inventory/StocktakePage.tsx:174-177`

- [ ] WEB-UIUX-792. **[MAJOR] POS global scan handler bails on Enter only checks 2 modals (CheckoutModal, SuccessScreen).** DeviceTemplateNudge, UpsellPrompt, PinModal etc. don't block. Phantom line items added to next sale. L5, L11.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:138-144`

- [ ] WEB-UIUX-793. **[MAJOR] Scanner "first match wins" silently picks wrong item on multi-match.** Server `name LIKE %12345%` matches "iPhone 12345 mAh battery" before exact UPC. `lookupBarcode` exact endpoint exists but unused. L1, L8.
  Multiple scan paths: `UnifiedPosPage.tsx:166`, `LeftPanel.tsx:453`, `StocktakePage.tsx:173`

- [ ] WEB-UIUX-794. **[MAJOR] POS detection threshold `100ms/char` too lenient for fast typists (40+ wpm = ~75ms/char).** Fast-typed `1234⏎` qualifies as scan, silently adds wrong product. L1, L7.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:190-198`

- [ ] WEB-UIUX-795. **[MAJOR] Scan-no-match toasts but ZERO recovery path.** Scanned barcode lost, not pre-filled into "Quick add" form, not logged. Cashier must re-scan or re-type. L4, L8.

- [ ] WEB-UIUX-796. **[MAJOR] Two scans 200ms apart: second aborts first's API call. First scan's product NEVER added.** No queue, no toast-on-loss. L11, L8.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:160-163`

- [ ] WEB-UIUX-797. **[MAJOR] ReceiveItemsModal scans NOT tied to any PO.** Scan-and-go restock looks like PO receive but creates ad-hoc unlinked stock. PO permanently "open". L5, L13.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:1318-1492`

- [ ] WEB-UIUX-798. **[MAJOR] Four independent scan implementations with no shared abstraction — diverge in all behaviors.** Multi-match, in-flight guard, audio, no-match recovery, modal context — all different across 4 paths. L3, L4.

- [ ] WEB-UIUX-799. **[MAJOR] `posApi.products` no LIMIT — short numeric scan (e.g. "1") returns all matching items.** 10k-item inventory = MB+ payload. Client takes [0]. L15.

- [ ] WEB-UIUX-800. **[MINOR] Scan flash "Scan detected!" set BEFORE API call.** 404/500 still shows green flash + concurrent red toast. L8.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:157-158`

#### ED17: Estimate→Ticket→Invoice Chain

- [ ] WEB-UIUX-801. **[BLOCKER] Estimate edits silently mutate post-conversion source-of-truth.** `approved` (signed!) estimate has line items rewritten in place. Customer doesn't know what they signed. L13, L16.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:127-136,289,403-409`

- [ ] WEB-UIUX-802. **[BLOCKER] No signature artifact rendered anywhere on web estimate detail.** No `signed_at`, no signature image, no "signed by …". Web operator can rewrite mobile-signed estimate without warning. L13, L16.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx`

- [ ] WEB-UIUX-803. **[BLOCKER] Bulk delete on EstimateList allows deleting `converted` rows.** Orphans linked tickets. Confirm doesn't enumerate. L13, L16.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:587-601`

- [ ] WEB-UIUX-804. **[MAJOR] No back-link from Ticket→Estimate.** `ticket.estimate_id` never read or rendered. Ticket is orphan after conversion. L5, L13.

- [ ] WEB-UIUX-805. **[MAJOR] No back-link from Invoice→Estimate.** Chain is one-way only. Dispute can't go back to estimate phase from invoice. L5, L13.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:416-420`

- [ ] WEB-UIUX-806. **[MAJOR] Version history shows version numbers but NOT signature/approval lineage.** No `total_at_signing`, no signed-version indicator. Operator can't tell which version was signed. L13, L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:27-31,510-552`

- [ ] WEB-UIUX-807. **[MAJOR] Convert-to-ticket allowed on stale/expired estimates without warning.** `draft` estimate (never sent/approved/signed) → billable ticket no friction. L5, L7.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:219-231`

- [ ] WEB-UIUX-808. **[MAJOR] Print on EstimateDetail uses `window.print()` of LIVE DOM.** Post-edit numbers + original `created_at` + `order_id` — customer can argue printout doesn't match what they signed. L13.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:248-254`

- [ ] WEB-UIUX-809. **[MAJOR] PrintPreviewModal has no `estimateId` prop — operator can only print latest invoice/work-order, never original signed quote.** L5, L13.
  `packages/web/src/components/shared/PrintPreviewModal.tsx:100-120`

- [ ] WEB-UIUX-810. **[MAJOR] Stage-skip allowed: estimate→invoice WITHOUT going through ticket approval.** `Generate Invoice` only checks `!ticket.invoice_id`, not approved-estimate gate. L5, L16.
  `packages/web/src/pages/tickets/TicketPayments.tsx:114-123,270-274`

- [ ] WEB-UIUX-811. **[MAJOR] Customer-side approval doesn't lock totals snapshot.** Operator edits line items post-approval (WEB-UIUX-801), portal shows new totals "Approved on [date]" — customer told they approved version they never saw. L16.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:22-51`

- [ ] WEB-UIUX-812. **[MINOR] Customer-side portal has only Approve, not Reject.** Q4 ("customer rejects → ticket auto-cancels?") unimplementable on customer side. L5.

#### ED18: Super-Admin / Multi-Tenant

- [ ] WEB-UIUX-813. **[BLOCKER] Impersonation indistinguishable from real login at logout time.** SA walks away mid-session, token expires (15min), bounces to /login (tenant login) → next person at kiosk logs in as REAL tenant admin, looks normal. L16.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:185-211`

- [ ] WEB-UIUX-814. **[BLOCKER] Single localStorage key `impersonation_session` for marker — second impersonation clobbers first across tabs.** Banner says A, requests use B. L16.
  `packages/web/src/components/ImpersonationBanner.tsx:6,17`

- [ ] WEB-UIUX-815. **[BLOCKER] Banner trusts localStorage without verifying token claims.** Stale marker + fresh login on same browser → "Impersonating acme-co" while user is logged in as themselves at acme-co. L16, L11.
  `packages/web/src/components/ImpersonationBanner.tsx:26-43,50-85`

- [ ] WEB-UIUX-816. **[BLOCKER] Cross-tenant guard skipped when oldSlug is null.** Tab logged-out + sibling tab writes tenant-B token → tab silently re-hydrates as B. L16.
  `packages/web/src/stores/authStore.ts:250-267`

- [ ] WEB-UIUX-817. **[MAJOR] Guard reads `payload.tenantSlug` (camelCase) but rest of codebase uses `tenant_slug` (snake_case) — guard likely silently no-op.** L16.
  `packages/web/src/stores/authStore.ts:241-249`

- [ ] WEB-UIUX-818. **[MAJOR] Exit impersonation calls full `logout()` → bounces to tenant /login.** SA console not restored. SA must manually navigate back to /super-admin/tenants. L4, L1.
  `packages/web/src/components/ImpersonationBanner.tsx:89-93`

- [ ] WEB-UIUX-819. **[MAJOR] `jti` returned from /impersonate never persisted client-side.** `endImpersonation` API exists but unreachable — leaked token can't be revoked from UI. Only TTL expiry. L16.
  `packages/web/src/pages/super-admin/TenantsListPage.tsx:179-212`

- [ ] WEB-UIUX-820. **[MAJOR] Tenant suspended mid-session → 401 → generic "session expired" toast.** Real reason buried in `error.response.data.code`. Operator doesn't know why. L8, L4.
  `packages/web/src/api/client.ts:320-349`

- [ ] WEB-UIUX-821. **[MAJOR] Trial expiry mid-sale: 403 upgrade modal but cart NOT preserved.** Cashier mid-sale loses cart silently. L4, L8.

- [ ] WEB-UIUX-822. **[MAJOR] Last-admin deletion: 409 surfaces wrong toast "This item was updated elsewhere — refresh to see latest changes."** Tenant locked out forever, no in-app recovery path. L8, L4.

- [ ] WEB-UIUX-823. **[MAJOR] Tenant slug change breaks magic links with no graceful surface.** L4, L14.

- [ ] WEB-UIUX-824. **[MINOR] `impersonation_session` localStorage outlives sessionStorage SA token.** Marker survives browser restart with no live token. L16.

#### ED7: Subscription/Billing Chaos

- [ ] WEB-UIUX-825. **[BLOCKER] CheckoutModal HTTP 202 / `pending_reconciliation` lumped into flat "decline".** Cashier hits Retry, server idempotency replays prior charge, customer potentially double-billed. UI never tells operator first charge actually went through. L8, L16.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:351-365,377-398`

- [ ] WEB-UIUX-826. **[BLOCKER] `subscribeMut` calls `membershipApi.subscribe` with NO `blockchyp_token` and NO `signature_file`.** Activation never captures card on file. Every nightly renewal will fail by definition. L5, L7, L16.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:891-902`

- [ ] WEB-UIUX-827. **[BLOCKER] Cancel hard-codes `{ immediate: true }` — no end-of-period option.** Customer paid through end of month → forfeits remaining time. CustomerDetailPage variant has NO confirmation at all. L5, L8, L16.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:904-911`
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:113-124,155-168`

- [ ] WEB-UIUX-828. **[BLOCKER] No tier-change UI ANYWHERE.** `membershipApi` exposes only subscribe/cancel/pause/resume. Operator must cancel (immediately, see above) + re-subscribe at full price. L5, L7.

- [ ] WEB-UIUX-829. **[BLOCKER] Past-due status badge shown but per-row "Bill now" button gated on `status === 'active'` — past-due rows can't be retried.** Wrong gating. L5, L8.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:260`

- [ ] WEB-UIUX-830. **[BLOCKER] Dunning bulk run partial-failure: aggregate counters only, no list of which 5 of 200 failed.** No "Retry failed" button. L8, L13.
  `packages/web/src/pages/billing/DunningPage.tsx:153-164,119-151`

- [ ] WEB-UIUX-831. **[MAJOR] InstallmentPlanWizard customer-default-on-3rd-payment story COMPLETELY ABSENT.** No payment status per row, no missed-payment marker, no transition to dunning, no auto-debit retry view. L5, L13.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:43-198`

- [ ] WEB-UIUX-832. **[MAJOR] BillingTab has no representation of "trial ended but card declined" state.** Stripe redirect handler reads only `?upgraded=1`/`?cancelled=1`, no `?declined=1` branch. L5, L8.
  `packages/web/src/pages/settings/BillingTab.tsx:104-118`

- [ ] WEB-UIUX-833. **[MAJOR] Pause subscription doesn't capture reason — API accepts `{reason}` but UI passes nothing.** Audit trail empty. L7, L13.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:913-920`

- [ ] WEB-UIUX-834. **[MAJOR] Generic "Billing failed" toast — no differentiation between card_expired/insufficient_funds/invalid_token/terminal_offline.** L8, L14.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:135-139`

- [ ] WEB-UIUX-835. **[MAJOR] BlockChyp Test Connection only checks at config-time — no live status indicator at checkout.** Cashier hits "Complete" → failure happens DURING charge attempt. L8, L11.
  `packages/web/src/pages/settings/BlockChypSettings.tsx:281-289`

- [ ] WEB-UIUX-836. **[MAJOR] Subscription credit-note doesn't cancel future billing.** Goodwill refund → next cron charges again two weeks later. No "Also cancel subscription" checkbox. L5, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311`

- [ ] WEB-UIUX-837. **[MAJOR] InstallmentPlanWizard `acceptanceText.trim().length >= 3` accepts "Bob" as legal auto-debit signature.** Fails any reasonable e-sign audit. L7, L16.
  `packages/web/src/components/billing/InstallmentPlanWizard.tsx:81`

- [ ] WEB-UIUX-838. **[MINOR] Dunning step builder lacks `request_card_update` action.** Only email/sms/call_queue/escalate. Exact workflow needed for card-on-file expired. L5.
  `packages/web/src/pages/billing/DunningPage.tsx:64-68`

- [ ] WEB-UIUX-839. **[MINOR] MembershipSettings tier deactivation copy misleading: "Existing subscribers will keep their membership until cancellation".** No way to migrate to another tier first. L14.
  `packages/web/src/pages/settings/MembershipSettings.tsx:434-440`

- [ ] WEB-UIUX-840. **[MINOR] No batch dry-run on Dunning sequence creation.** 200-customer sequence with `d+0 escalate` fires 200 escalations day-zero. L8.

#### ED20: Error Recovery Patterns

- [ ] WEB-UIUX-841. **[MAJOR] `useWsStore.isWsOffline` set after 10 reconnect failures but ZERO components consume it.** Stale tickets/SMS/inventory with no indicator WS dead. L11.
  `packages/web/src/hooks/useWebSocket.ts:524-538`

- [ ] WEB-UIUX-842. **[MAJOR] CustomerCreatePage / LeadCreatePage / EstimateCreatePage / ExpenseCreatePage have NO `useDraft` wiring.** 22+ field forms held only in useState. 500 on submit → user hits browser-back → all input gone. L4, L7.

- [ ] WEB-UIUX-843. **[MAJOR] No mutation queueing while offline — every mutation fires, hits 30s timeout, generic toast.** Cashier checkout-while-wifi-drops stares at spinners 30s. L4, L8.
  `packages/web/src/components/shared/OfflineBanner.tsx:1-51` (informational only)

- [ ] WEB-UIUX-844. **[MAJOR] `useUndoableAction` SPA navigation FIRES the destructive action on unmount instead of aborting.** Browser back during 5s window = commits deletion mid-navigation. L4, L11.
  `packages/web/src/hooks/useUndoableAction.tsx:217-242`

- [ ] WEB-UIUX-845. **[MINOR] `useDraft` 100KB cap silently drops paste over 100KB.** No textarea-level maxLength either. L7, L8.
  `packages/web/src/hooks/useDraft.ts:7,195-198`

- [ ] WEB-UIUX-846. **[MINOR] `QuotaExceededError` on draft write → `console.warn` only.** Kiosk localStorage saturated → drafts silently fail. L8.
  `packages/web/src/hooks/useDraft.ts:200-207`

- [ ] WEB-UIUX-847. **[MINOR] Slow 3G: skeleton runs ~60s before user gets feedback (default `retry: 1` × 30s timeout).** No "Still loading..." nudge after 5-10s. L6, L8.

- [ ] WEB-UIUX-848. **[MINOR] `skipGlobal500Toast` config flag supported by interceptor but ZERO callers.** Every 5xx triggers global toast even when page renders inline error. L8.
  `packages/web/src/api/client.ts:355-369`


### Web UI/UX Audit — Edge-Case Pass C (2026-05-05, journeys + data flow + security + keyboard)

#### JOURNEY1: New Shop Owner Day 1

- [ ] WEB-UIUX-849. **[BLOCKER · BLOCKED] Server `skipEmailVerification = true` HARDCODED.** Anyone signs up with any email/slug → instant tenant + auth tokens. Typo'd email registers tenant real owner can never access. L16.
  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05). Do not address until email/SMTP system is ready.
  `packages/server/src/routes/signup.routes.ts:618`

- [ ] WEB-UIUX-850. **[BLOCKER] Wizard `completedCards` is hardcoded `new Set()` — never populated.** Review step's "Extras configured" section permanently empty. After 24 wizard steps, owner sees Review screen with NO confirmation work was captured. L8, L11.
  `packages/web/src/pages/setup/SetupPage.tsx:345`

- [ ] WEB-UIUX-851. **[BLOCKER] Card payments silently disabled day 1 — BlockChyp underwriting takes 24-48h.** No fallback (Stripe/Square/manual), no warning before wizard. New owner with 5 walk-ins waiting = stuck. L1, L4, L16.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:178,533-538`

- [ ] WEB-UIUX-852. **[BLOCKER] Tickets list empty state has NO "+ New Ticket" button.** Most important page for new repair shop has the worst empty state. CustomerListPage has CTA + "Load 5 sample customers" — TicketListPage has neither. L1, L8.
  `packages/web/src/pages/tickets/TicketListPage.tsx:1750-1760`

- [ ] WEB-UIUX-853. **[MAJOR] Wizard is 24 mandatory-or-skip body steps — "About 10 minutes" claim wildly optimistic.** Realistic 30-60min. 12% rage-quit at step 8. Skip cap = 3, cooldown 24h. L1, L14.
  `packages/web/src/pages/setup/wizardTypes.ts:84-92`

- [ ] WEB-UIUX-854. **[MAJOR] StepMobileAppQr unusable on SaaS — `lan_ip` from `/api/v1/info` meaningless behind Cloudflare.** L11.
  `packages/web/src/pages/setup/steps/StepMobileAppQr.tsx:38-80`

- [ ] WEB-UIUX-855. **[MAJOR · BLOCKED] Test SMS button fires BEFORE save — Twilio charges per attempt regardless.** No rate-limit, double-click sends 2 messages. L7, L16.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/setup/steps/StepSmsProvider.tsx:201-225`

- [ ] WEB-UIUX-856. **[MAJOR] Payment terminal "Test connection" is STUB pretending to work.** 400ms spinner → "unverified" status with tiny "Stub" pill. Owners proceed thinking terminal paired. L8, L16.
  `packages/web/src/pages/setup/steps/StepPaymentTerminal.tsx:153-172`

- [ ] WEB-UIUX-857. **[MAJOR · BLOCKED] StepFirstEmployees sends invites BEFORE wizard finishes — IRREVERSIBLE.** Mistyped email → orphan account, no recall path, no confirmation. L7, L4.
  **STATUS: BLOCKED** — deferred until email infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx:153-212`

- [ ] WEB-UIUX-858. **[MAJOR] Tax step defaults to 8.25% blindly with no state lookup.** OR shop overcharges 8.25% silently. CO/CA/NY all different. L7, L16.
  `packages/web/src/pages/setup/steps/StepTax.tsx:38,56`

- [ ] WEB-UIUX-859. **[MAJOR] Repair pricing tier B/C use Preview placeholders that look like real options.** Owner clicks "Per-device matrix" → 5 rows of fake iPhone pricing → nothing saves. L5, L8.
  `packages/web/src/pages/setup/steps/StepRepairPricing.tsx:236-240,370-481`

- [ ] WEB-UIUX-860. **[MAJOR] Catalog empty when StepShopType skipped — no recovery path from POS.** "Mobile" → empty results → stuck. No "Load sample data" on RepairsTab. L4, L8.
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:154-200`

- [ ] WEB-UIUX-861. **[MAJOR · BLOCKED] Customer creation: SMS opt-in is OFF by default — breaks auto-SMS feature wizard promotes.** Every first customer has `sms_opt_in=false`. L5, L14.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:51-53`

- [ ] WEB-UIUX-862. **[MAJOR] Inventory creation: Tax Class dropdown empty by default — wizard wrote `tax_default_parts` to `store_config` not tax_classes table.** User picks "No Tax" silently. L7, L16.
  `packages/web/src/pages/inventory/InventoryCreatePage.tsx:175-179`

- [ ] WEB-UIUX-863. **[MAJOR] Daily nudges hardcode paths that may not exist.** Day-3 ctaHref `/settings/users` — but Settings tabs are query-string based. Day-7 sends to `/invoices` for "refund" but new shop has zero invoices. L5, L14.
  `packages/web/src/components/onboarding/DailyNudge.tsx:37,47,55`

- [ ] WEB-UIUX-864. **[MAJOR] Membership upsell shown to brand-new customers at checkout.** "Save X% with [Tier]!" banner before owner has configured tiers. L1, L14.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:194-237`

- [ ] WEB-UIUX-865. **[MINOR · BLOCKED] StepDefaultStatuses (step 9) warns about auto-SMS BEFORE SMS configured (step 16).** Jargon-overload. L14.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-866. **[MINOR] StepShopType "Thin" badge hover-only — tablet/iPad users never see why.** Picking Console/PC traps shop in near-empty seed. L11, L14.

#### JOURNEY2: Busy Saturday

- [ ] WEB-UIUX-867. **[MAJOR] POS draft persistence is per-user, not per-register/till.** Two cashiers sharing login on same till clobber each other on every keystroke. L6, L11.
  `packages/web/src/pages/unified-pos/store.ts:64-68,273-288`

- [ ] WEB-UIUX-868. **[MAJOR] Customer search: 300ms debounce + 8-result hard cap + no fuzzy phone normalization.** Operator types 7-digit phone → ≥2.1s accumulated debounce. 100 walk-ins → 8 results truncated silently. L1, L7.
  `packages/web/src/pages/unified-pos/CustomerSelector.tsx:58-77`

- [ ] WEB-UIUX-869. **[MAJOR · BLOCKED] BulkSmsModal full-screen overlay — operator can't answer inbound SMS during 5-min token window.** No progress chip on enqueue, no abort mid-preview. L11, L1.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-870. **[MAJOR] Tech context-switching between 5 tickets loses cart state — only ONE persisted cart per user.** Switching ticket via `?ticket=` calls `resetAll()`. Inactivity timer 10min silently `resetAll()`. L4, L5.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:240-251`

- [ ] WEB-UIUX-871. **[MAJOR] Kanban no batch drag.** Tech with 5 "ready for pickup" tickets must drag each individually. Bulk-mode exists in List view but not Kanban. L1, L5.

- [ ] WEB-UIUX-872. **[MAJOR] End-of-day flow scattered across 3 pages — no End-of-Day wizard.** CashDrawerWidget + CashRegisterPage + BottomActions. No unified close-shift sequence. L1, L4.

- [ ] WEB-UIUX-873. **[MAJOR] Estimate→Ticket conversion: one-shot `confirm()` with no preview.** No which-fields-transfer, no edit-before-conversion, no link to result in toast. L5, L8.

- [ ] WEB-UIUX-874. **[MINOR] DashboardPage refetches 10+ queries on 60-120s jittered interval + `refetchOnWindowFocus: true`.** Constrained shop tablet pinned. L15.

#### JOURNEY3: Angry Customer Dispute

- [ ] WEB-UIUX-875. **[BLOCKER] Voice calls list cannot identify caller — `from_number` rendered as raw text, no customer lookup.** Operator hand-copies number, navigates to Customers, searches → 15-30s lost. L1, L4.
  `packages/web/src/pages/voice/VoiceCallsListPage.tsx:160-217`

- [ ] WEB-UIUX-876. **[BLOCKER] No "VIP / At-Risk / Disputed" customer flag in header.** Tags exist but buried in Info tab edit form. HealthScoreBadge tracks LTV but a churning customer can show "champion" while screaming. L1, L11.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:330-396`

- [ ] WEB-UIUX-877. **[BLOCKER] No manager-override / approval gate on refunds.** Anyone with InvoiceDetail access issues credit-note up to amount_paid in single click. No PIN, no threshold. Audit trail captures `recorded_by` for payments but NOT for credit-note in UI. L16, L4.

- [ ] WEB-UIUX-878. **[MAJOR] Refund reason picker missing service-recovery codes.** No `failed_repair`, `lost_data`, `extended_delay`, `goodwill_gesture`, `chargeback_prevention`, `warranty_invocation`. Most common scenarios collapse into "dissatisfaction". L14, L13.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:17-24`

- [ ] WEB-UIUX-879. **[MAJOR · BLOCKED] No "do not request review" flag for unhappy customers.** Refund customer 4h ago → automated review-request SMS fires → 1-star review. L5, L16.
  **STATUS: BLOCKED** — deferred until messaging (email/SMS) infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-880. **[MAJOR] QC sign-off result invisible on completed ticket.** Modal writes data, no read-only display surface. Operator handling "you didn't fix my phone" can't point to "Steve QC-passed Tuesday 4pm with photo proof". L11, L13.
  `packages/web/src/components/tickets/QcSignOffModal.tsx`
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:590-597`

- [ ] WEB-UIUX-881. **[MAJOR] CustomerHistorySidebar caps at 5 with NO "See all" + repeat-fault pill only fires for current device.** L11.
  `packages/web/src/components/tickets/CustomerHistorySidebar.tsx:90-92`

- [ ] WEB-UIUX-882. **[MAJOR] Communications tab on customer page strips call affordances — no duration, no recording-play, no transcript link.** 200% regression vs standalone CommunicationPage. L11, L4.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1740-1785`

- [ ] WEB-UIUX-883. **[MAJOR] Refund history not aggregated anywhere.** Operator clicks each invoice individually to see credit-note timeline. CustomerAnalyticsBar shows LTV but no "total refunds" or "refund ratio". L11, L13.

- [ ] WEB-UIUX-884. **[MAJOR] No "invite back for free re-repair" workflow.** `cloneWarranty` exists but hidden in overflow menu, doesn't auto-message, no zero-cost line-item template. 5 manual steps. L4, L5.

- [ ] WEB-UIUX-885. **[MAJOR · BLOCKED] No SMS/email follow-up scaffold from credit-note success.** Customer hangs up not knowing if refund landed. Receipt-prompt only fires after payment, not after refund. L8, L4.
  **STATUS: BLOCKED** — deferred until messaging (email/SMS) infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-886. **[MINOR] Note-taking is slow — customer-level notes via `comments` textarea (free-form string), no "+ Add Note", no timestamp/author.** L7, L13.

#### DATA1: Data Flow Consistency

- [ ] WEB-UIUX-887. **[BLOCKER] POS sale never invalidates inventory cache.** `CheckoutModal.onSuccess` invalidates `['membership',...]` only. Other tabs show pre-sale stock indefinitely. L6, L11, L13.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:228-230`

- [ ] WEB-UIUX-888. **[BLOCKER] `pos-products` cache key NEVER invalidated by any mutation.** Inventory edit (price/stock/PO/stocktake) → POS product tile shows old price/stock until hard refresh. Cashier rings yesterday's price. L6, L13, L16.
  `packages/web/src/pages/unified-pos/ProductsTab.tsx:40`

- [ ] WEB-UIUX-889. **[BLOCKER] Stocktake commit doesn't invalidate inventory cache.** Toast says "Committed: N items adjusted" but inventory list shows pre-stocktake numbers. L6, L13.
  `packages/web/src/pages/inventory/StocktakePage.tsx:141-145`

- [ ] WEB-UIUX-890. **[BLOCKER] PO receive doesn't invalidate inventory cache.** After receiving 50 phones, POS still says "0 in stock". L6, L13.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:553-555`

- [ ] WEB-UIUX-891. **[MAJOR · BLOCKED] SMS conversation linkage is by phone string, not customer_id.** Customer phone change → previous `conv_phone` becomes orphan stranger thread, new phone has no history. L5, L13.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/communications/CommunicationPage.tsx:50,68,91,1440,1651-1655`

- [ ] WEB-UIUX-892. **[MAJOR] Customer phone change strands portal account.** Portal login uses phone as identity key. Front-desk update silently breaks portal access. L5, L16.
  `packages/web/src/pages/portal/portalApi.ts:194-195`

- [ ] WEB-UIUX-893. **[MAJOR] Customer name/email/phone edits don't invalidate dependent list caches.** `['tickets']`/`['invoices']`/`['estimates']`/`['sms-conversations']`/`['leads']` all show OLD name. WS `customer:updated` only invalidates `['customers']`. L6, L9.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1154-1157`

- [ ] WEB-UIUX-894. **[MAJOR] Currency change in Settings requires page reload.** `formatCurrency` reads module-level singleton refreshed only by `['settings-config-env']`. Saving currency in `['settings','store']` invalidates DIFFERENT key. L6, L10.

- [ ] WEB-UIUX-895. **[MAJOR] Print page renders LIVE customer/store data on re-print of historical receipts.** Renamed customer "J Doe" → "Jane Doe-Smith" → reprint of 6-month-old receipt now says new name. Tax/legal expects point-in-time snapshots. L13, L16.
  `packages/web/src/pages/print/PrintPage.tsx:195-241,451-549,763-810,910-941`

- [ ] WEB-UIUX-896. **[MAJOR] Ticket detail status change invalidates `['ticket', id]` only — Kanban shows OLD column.** Mitigated by WS but fails offline / tab-suspended. L11.

- [ ] WEB-UIUX-897. **[MINOR] Customer membership tier discount snapshotted into POS cart customer object.** Admin changes discount mid-cart → in-memory cart keeps old discount until customer re-selected. L6.

#### SEC1: Security UX

- [ ] WEB-UIUX-898. **[MAJOR] BulkSmsModal trigger has NO client-side role gate.** Cashier sees Bulk button, opens modal, picks segment+template, sees recipient count (PII leak), only then 403. L12, L16.
  `packages/web/src/pages/communications/CommunicationPage.tsx:1546-1554`

- [ ] WEB-UIUX-899. **[MAJOR] `posPinVerified` flag never expires — only reset by `resetAll()`.** Cashier verifies, walks away, another staff steps up to checkout, reuses verification. L16.
  `packages/web/src/pages/unified-pos/store.ts:126-127,253-254,268,290-303`

- [ ] WEB-UIUX-900. **[MAJOR] SwitchUser in Header bypasses shared PinModal — NO failCount, NO lockout, NO sessionStorage persistence.** Walk-up brute force at network round-trip rate. L16.
  `packages/web/src/components/layout/Header.tsx:642-728`

- [ ] WEB-UIUX-901. **[MAJOR] Customer CSV export not role-gated, no PII warning, no audit-log breadcrumb.** Cashier exports entire DB. L16, L8.
  `packages/web/src/pages/customers/CustomerListPage.tsx:308-354,586-589`

- [ ] WEB-UIUX-902. **[MAJOR] 18 direct `user.role === 'admin'` literals despite `useHasRole` hook.** Inconsistent role semantics. Future role rename = 18 places. L4, L16.

- [ ] WEB-UIUX-903. **[MAJOR] 403 responses to non-auth endpoints have NO global toast.** Demoted user clicks manager-only button → silent dead-end. L8.
  `packages/web/src/api/client.ts:294-313,361-370`

- [ ] WEB-UIUX-904. **[MAJOR] Logout shows NO global toast / cross-tab confirmation.** Sibling tabs flip silently. L8.

- [ ] WEB-UIUX-905. **[MINOR] DangerZoneTab visible to managers, button only disabled.** Should redirect away like AuditLogsTab does. L11, L16.
  `packages/web/src/pages/settings/DangerZoneTab.tsx:32-83`

- [ ] WEB-UIUX-906. **[MINOR] AuditLogsTab `formatDetails` JSON in `title=` tooltip exposes hashed PINs/IPs/PII on hover.** Screen-share/screenshot leak. L12, L16.
  `packages/web/src/pages/settings/AuditLogsTab.tsx:60-70,161`

- [ ] WEB-UIUX-907. **[MINOR] Recent_views localStorage keys not in auth-cleared sweep.** Kiosk handoff: cashier B sees admin's recent customers in CommandPalette. L16.
  `packages/web/src/stores/authStore.ts:185-200`

- [ ] WEB-UIUX-908. **[MINOR] `pos-store-u*` keys never swept.** Fired employee's pending cart sits forever in localStorage with customer name + items. L16.

- [ ] WEB-UIUX-909. **[MINOR] PinModal lockout is `sessionStorage` per-tab — multi-tab evasion.** Open second tab → 5 fresh attempts. L16.
  `packages/web/src/components/shared/PinModal.tsx:23-55`

- [ ] WEB-UIUX-910. **[MINOR] AuditLogsTab cannot export / search-by-user from UI.** During incident, admin can't filter by user_id. No export. L1, L13.

#### ED19: Keyboard Nav

- [ ] WEB-UIUX-911. **[MAJOR] 30+ `role="dialog"` sites lack focus-restore on close.** Only ConfirmDialog implements lastFocused capture/restore. PinModal, UpgradeModal, QuickSmsModal, CheckoutModal, WidgetCustomizeModal, SwitchUserModal, ReviewPromptModal, 5 InventoryListPage modals — focus drops to body. L12.

- [ ] WEB-UIUX-912. **[MAJOR] `opacity-0 group-hover:opacity-100` buttons in 12+ sites are keyboard-invisible.** Visible focus rings appear with no context. LeadPipelinePage:124 already has comment `WEB-FC-006: always visible (no opacity-0 hover trap)` — fix not propagated. L12.
  TicketDevices.tsx:559,581,611,988,1008; TicketSidebar.tsx:232; KanbanBoard.tsx:114; DashboardPage.tsx:860; RepairsTab.tsx:1366,1372; ConditionsTab.tsx:337

- [ ] WEB-UIUX-913. **[MAJOR] Toasts not keyboard-reachable or dismissible.** No tabIndex/role on toast nodes, no Esc handler, no per-toast dismiss button. 599+ toast() calls. L12.
  `packages/web/src/main.tsx:404-415`

- [ ] WEB-UIUX-914. **[MAJOR] Focus lost after destructive delete.** Optimistic row removal → button unmounts → focus drops to body. No "next/prev row" target. L12, L4.

- [ ] WEB-UIUX-915. **[MAJOR] Settings tab strip is 21 plain `<button>` elements — no `role="tablist"`/`role="tab"`, no arrow-key nav.** 21 Tab stops to reach active tab content. L12.
  `packages/web/src/pages/settings/SettingsPage.tsx:2285-2313`

- [ ] WEB-UIUX-916. **[MAJOR] No focus-to-first-error after validation fail.** Sighted keyboard users have no idea where first broken field is. L12, L8.
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:186-208`

- [ ] WEB-UIUX-917. **[MINOR] Password-toggle eye buttons set `tabIndex={-1}` everywhere.** Forces blind typing with no peek-ahead. Material/GOV.UK convention is to keep in tab order. L12.

- [ ] WEB-UIUX-918. **[MINOR] Esc behavior inconsistent across search inputs.** Some clear, some close parent modal, some no-op. No documented policy. L4, L12.

- [ ] WEB-UIUX-919. **[MINOR] Per-field `role="alert"` spam — every FormError variant including `field`/`hint` uses `role="alert"`.** 10-field form fail = 10 simultaneous SR announcements. L12.
  `packages/web/src/components/shared/FormError.tsx:53,65`

- [ ] WEB-UIUX-920. **[MINOR] `<aside>` Sidebar lacks `aria-label`.** SR users hear unlabeled aside region. L12.
  `packages/web/src/components/layout/Sidebar.tsx:176`

- [ ] WEB-UIUX-921. **[MINOR] CustomerListPage CustomerActionsMenu lacks `role="menu"`/`menuitem`, no arrow-key nav, no Esc handler.** Header.tsx:465 + LeadPipelinePage.tsx:144 use proper pattern — propagate. L12.

- [ ] WEB-UIUX-922. **[MINOR] Star-rating radiogroup no arrow keys.** 5 radios = 5 Tab stops instead of 1 group with arrows. L12.
  `packages/web/src/pages/portal/components/ReviewPromptModal.tsx:86-108`

- [ ] WEB-UIUX-923. **[MINOR] SignatureCanvas has NO keyboard alternative.** 0 keyboard handlers. Customers required to sign on portal cannot complete with keyboard alone. L12.
  `packages/web/src/components/shared/SignatureCanvas.tsx`

#### ED22: Reports Data Accuracy

- [ ] WEB-UIUX-924. **[MAJOR] Reports `last_7` is 8 days, `last_30` is 31 days — Dashboard uses correct math.** Same product, same preset name, different ranges across pages. L7, L13.
  `packages/web/src/pages/reports/ReportsPage.tsx:98-101`

- [ ] WEB-UIUX-925. **[MAJOR] Reports `todayStr()` uses `.toISOString().slice(0,10)` (UTC) — Dashboard fixed via `localYmd()` (SCAN-1162) — Reports never adopted.** 11:55pm America/Denver → tomorrow's UTC date. L7, L13.

- [ ] WEB-UIUX-926. **[MAJOR] Comparison "vs prior period" pairs by ARRAY INDEX, not month label.** Server may omit empty buckets → Apr-current shown next to Feb-previous bar. L11, L13.
  `packages/web/src/pages/reports/ReportsPage.tsx:993-1000`

- [ ] WEB-UIUX-927. **[MAJOR] Chart fills "0" for missing days — no distinction between "no sales", "shop closed", "data not yet computed".** L8, L11.

- [ ] WEB-UIUX-928. **[MAJOR] CSV export silently drops or includes data the operator didn't intend.** Tickets export = 2 columns (`Day, Created`) ignoring 5 KPIs + byStatus + byTech. L8, L13.
  `packages/web/src/pages/reports/ReportsPage.tsx:1274-1282`

- [ ] WEB-UIUX-929. **[MAJOR] Refunds KPI tooltip: "Total refunded amount" — no period/sign disclosure, doesn't say if Net Profit subtracts refunds.** L13, L14.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:2120`

- [ ] WEB-UIUX-930. **[MINOR] Avg Turnaround Hours card never discloses if On-Hold/Awaiting-Customer time excluded.** SummaryCard lacks tooltip prop. L14.

- [ ] WEB-UIUX-931. **[MINOR] No `data_as_of` / generated_at timestamp on any Reports tab.** `staleTime: 30_000` cache opaque. L13, L11.

- [ ] WEB-UIUX-932. **[MINOR] Aging Report has NO date-range picker — "as of when" invisible.** L7, L13.
  `packages/web/src/pages/billing/AgingReportPage.tsx:46-52`

- [ ] WEB-UIUX-933. **[MINOR] DateRangePicker custom-range "To" has NO upper bound — future date allowed.** Backend silently clamps; chart renders empty days. L7.
  `packages/web/src/components/shared/DateRangePicker.tsx:236,252-253`

- [ ] WEB-UIUX-934. **[MINOR] `formatCurrency` swallows NaN as `$0.00`.** Server returns object → `$0.00` silently. Indistinguishable from real zero. L8, L13.
  `packages/web/src/utils/format.ts:55-57`

#### ED23: External Integrations

- [ ] WEB-UIUX-935. **[BLOCKER] BlockChyp `processPayment` mints fresh idempotency key per call.** Server idem cache keyed by `(user, url, key)` — every retry treated as fresh charge. Operator clicks "Pay via Terminal", times out at 30s, clicks again → server processes both. L16, L4.
  `packages/web/src/api/endpoints.ts:1177-1209`

- [ ] WEB-UIUX-936. **[BLOCKER] Default 30s axios timeout shorter than terminal user-input window (60-90s).** Tap-to-pay/chip flow times out client-side while server still processing. Combined with above = double-charge. L16, L4.
  `packages/web/src/api/client.ts:65`

- [ ] WEB-UIUX-937. **[BLOCKER] `/blockchyp/status` reports configured-state, NEVER reachability.** No "online/last-heartbeat" field. Configured-but-offline terminal silently passes gate, fails during charge. L8, L11.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:170-178`

- [ ] WEB-UIUX-938. **[MAJOR] BlockChyp Test Connection requires unsaved keys — operator can't retest live key against offline terminal.** Saved secrets arrive redacted as `''`. Most common diagnostic ("did terminal go offline?") requires re-entering 3 secrets. L8, L4.
  `packages/web/src/pages/settings/BlockChypSettings.tsx:282-296`

- [ ] WEB-UIUX-939. **[MAJOR] Catalog `partial_failure` job status falls through to "pending" badge.** Looks like in-progress job. Operator can't distinguish "still running" from "finished but skipped half". L11, L8.
  `packages/web/src/pages/catalog/CatalogPage.tsx:27-42`

- [ ] WEB-UIUX-940. **[MAJOR] Supplier-template-drift / selector-mismatch invisible to UI.** Server logs `selector mismatch` warnings — UI shows generic `error_message` text truncated. No "stale catalog" amber banner. L8, L13.
  `packages/web/src/pages/catalog/CatalogPage.tsx:660-676`

- [ ] WEB-UIUX-941. **[MAJOR · BLOCKED] SMS send error path swallows 429/silent-drop/invalid-number distinctions.** Generic "Failed to send message" toast. L8, L14.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-942. **[MAJOR · BLOCKED] No path from operator-facing 401 (invalid SMS provider key) to settings page that fixes it.** Generic toast. CheckoutModal pattern (`Terminal not configured — go to Settings → Payments`) missing for SMS. L4, L8.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).

- [ ] WEB-UIUX-943. **[MAJOR] VoiceCallsListPage swallows recording-fetch errors with generic "Could not load recording".** 401/404/410 indistinguishable. No retrigger webhook path. L8.

- [ ] WEB-UIUX-944. **[MINOR · BLOCKED] Webhook URL panel never tests bilateral connectivity.** No "send test webhook" action to verify provider can reach server, signing-secret matches. Silent drop if misconfigured. L8.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).
  `packages/web/src/pages/settings/SmsVoiceSettings.tsx:235-262`

- [ ] WEB-UIUX-945. **[MINOR · BLOCKED] SMS auto-reply "Sent once per sender per 24-hour window" hardcoded server-side, not configurable from UI.** No "auto-reply paused due to rate limit" indicator. L7, L11.
  **STATUS: BLOCKED** — deferred until messaging/SMS infrastructure work begins (per user 2026-05-05).


### Web UI/UX Audit — Pass 11 (2026-05-05, flow walk: approve estimate — server-vs-client gaps + customer e-sign)

Walk of the "Approve Estimate" flow: staff create → send-by-SMS → customer (or staff) approves → optional convert-to-ticket. Cross-checked server `estimates.routes.ts` + `estimateSign.routes.ts` (sign-URL + signature-capture) + `portal.routes.ts /estimates/:id/approve` against client `EstimateListPage`, `EstimateDetailPage`, `PortalEstimatesView`. Largest gap: server has full e-sign infra (`estimate_signatures` table, sign-token issuance, public signer UI) **mobile-only** — desktop flow flips `status='approved'` with zero name/IP/UA capture. Compliance/audit gap.

#### Blockers — Status drift, missing audit trail, unwired endpoints

- [ ] WEB-UIUX-946. **[BLOCKER] `'signed'` status missing from every web status map.** `estimateSign.routes.ts:617` sets `status='signed'` on customer e-sign POST, yet `EstimateDetailPage.STATUS_COLORS` (`:16-22`) and `EstimateListPage.ESTIMATE_STATUSES` (`:17-24`) and portal `EstimateStatusBadge.colors` (`PortalEstimatesView:158-164`) ALL omit it. Mobile-signed estimate renders raw text "signed" with gray fallback, list-page filter pills can't filter by signed, customer portal shows draft-gray. L9, L1.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:16-22`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:17-24`
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:158-164`
  <!-- meta: fix=add-signed-color-everywhere+filter-pill+detail-badge -->

- [ ] WEB-UIUX-947. **[BLOCKER] Portal Approve fires `POST /portal/estimates/:id/approve` with NO signature/name capture.** `portal.routes.ts:1454-1457` sets `status='approved'` and `approved_at` only — does not write `estimate_signatures` row, no signer_name, no signer_ip, no user_agent. Server has full table + capture via `/public/api/v1/estimate-sign/:token` (`estimateSign.routes.ts:611-623`) but the portal one-click "Approve Estimate" button bypasses it entirely. Compliance/legal: shop has zero proof customer pressed approve. Chargeback dispute = no defense. L8, L11, L16.
  `packages/server/src/routes/portal.routes.ts:1437-1478`
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:132-139`
  <!-- meta: fix=portal-Approve-must-route-through-signed-token-flow-OR-capture-signer-name-+-IP-+-UA-server-side -->

- [ ] WEB-UIUX-948. **[BLOCKER] No web UI for `POST /api/v1/estimates/:id/sign-url`.** `estimateSign.routes.ts:233-309` issues admin-side e-sign token + URL (`buildPublicSignUrl`) so staff can hand customer a secure copy-link or QR for in-shop signature pad. Zero callers in `packages/web/src` (grep `sign-url` → only authedRouter declaration in server). Desktop staff can't hand customer the e-sign URL — only mobile clients drive it. EstimateDetailPage has Send (SMS) but nothing for sign-link generation. L8, L3.
  `packages/server/src/routes/estimateSign.routes.ts:233-309`
  <!-- meta: fix=add-Generate-Sign-Link-button-on-EstimateDetailPage+modal-with-copy+QR+TTL-picker -->

- [ ] WEB-UIUX-949. **[BLOCKER] No web UI for `GET /api/v1/estimates/:id/signatures`.** Admin endpoint at `estimateSign.routes.ts:319-353` lists captured signatures (signer_name, IP, UA, signed_at). Web detail page never fetches it; admin reviewing a "signed" estimate sees `approved_at` date but no name, no audit trail. Mobile captures signatures the desktop staff cannot review without DB query. L8, L11.
  `packages/server/src/routes/estimateSign.routes.ts:313-353`
  <!-- meta: fix=add-Signatures-card-on-EstimateDetailPage-sidebar-when-status===signed -->

- [ ] WEB-UIUX-950. **[BLOCKER] `'cancelled'` status referenced server-side, never mapped client-side.** `estimates.routes.ts:740,808` blocks convert when `status='cancelled'`, yet ESTIMATE_STATUSES + STATUS_COLORS omit it. If a row exists with `cancelled`, list filter chip absent, badge gray fallback, detail page color undefined. Either set never reachable or dead code on client. L9.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:17-24`

#### Major — Truthfulness, hierarchy, recovery

- [ ] WEB-UIUX-951. **[MAJOR] Self-approval check is server-side only — Approve button does NOT pre-disable when `created_by === currentUser.id`.** `estimates.routes.ts:1138-1143` rejects with 403 "Cannot approve your own estimate. Another admin must approve this one." — UI lets the operator click, then surfaces server's message via toast. Should disable button + tooltip "needs another admin to approve" up-front. L8, L1.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:206-218`

- [ ] WEB-UIUX-952. **[MAJOR] Staff Approve confirm copy hides the audit gap.** "Mark this estimate as approved?" — does not warn this BYPASSES customer e-sign and writes no `estimate_signatures` row. Operator approving on customer's behalf has no in-UI signal that this is a unilateral action vs the customer's own portal/SMS approval. L7, L16.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:209`
  <!-- meta: fix=copy=Approving-on-customer-behalf-skips-signature-capture+require-typing-INITIAL-OR-reason -->

- [ ] WEB-UIUX-953. **[MAJOR] `estimateApi.send` typed `method?: 'sms' | 'email'` but server rejects `'email'` with 400.** `endpoints.ts:906` advertises both; `estimates.routes.ts:967-969` throws "Unsupported send method 'email'". TS contract is a lie — caller writing email path gets runtime error, no compile warning. L7.
  `packages/web/src/api/endpoints.ts:906`
  `packages/server/src/routes/estimates.routes.ts:967-969`
  <!-- meta: fix=narrow-type-to-'sms'-only-OR-implement-email-path -->

- [ ] WEB-UIUX-954. **[MAJOR] SMS body hardcoded server-side, says "Reply YES to approve" but NO inbound-SMS approve handler exists.** `estimates.routes.ts:984` builds `Hi ${first_name}, ... Reply YES to approve...`. Customer texts "YES" → goes to nowhere (smsInbox shows it as raw thread message; no parser flips estimate status). False promise. Customers expect SMS-reply approval, get silence. L7, L16.
  `packages/server/src/routes/estimates.routes.ts:984`

- [ ] WEB-UIUX-955. **[MAJOR] `send` flips `status='sent'` BEFORE SMS dispatch; SMS failure surfaces toast but status stays `'sent'`.** `estimates.routes.ts:949-955` UPDATEs status='sent' first, then SMS attempt at `:980-1003` may fail. Web treats `data.sent === false` as error toast (`EstimateDetailPage:76-77`) but the estimate's status persists as 'sent' — operator/customer/audit chain says "sent" even though nothing left the building. L7, L11.
  `packages/server/src/routes/estimates.routes.ts:949-1003`
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:73-83`

- [ ] WEB-UIUX-956. **[MAJOR] Send confirm dialog does not show the destination phone number.** "Send this estimate to the customer via SMS?" — no `${formatPhone(estimate.customer_mobile)}`. Operator can't catch a typo'd phone before the SMS fires + counts toward Twilio cost + status flips to sent. L7, L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:195`

- [ ] WEB-UIUX-957. **[MAJOR] No fallback channel when SMS fails — operator gets toast, no "Try email/portal-link instead" branch.** `estimates.routes.ts` returns `sent: false, warning, sms_error` but web just shows the warning toast. Customer with no phone or bad number = dead end; operator must navigate elsewhere to send by alternate means (and there is no alternate means in web). L4, L8.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:75-80`

- [ ] WEB-UIUX-958. **[MAJOR] Convert button enabled while `status='draft'` — operator converts never-sent estimate to ticket.** `:219` gates only on `!== 'converted' && !== 'rejected'`. Customer who never saw the estimate now has a billable ticket. Should require `status IN ('approved','signed','sent')` minimum, with explicit warn for `'sent'` (not yet approved). L1, L5.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:219-231`

- [ ] WEB-UIUX-959. **[MAJOR] Convert button enabled while `status='sent'` (not approved) — silent conversion of unapproved estimate.** Confirm "Convert this estimate to a ticket?" gives no signal that customer hasn't approved yet. Same defect on EstimateListPage row action. L7, L1.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:222`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:772`

- [ ] WEB-UIUX-960. **[MAJOR] Convert mutation `onError: () => toast.error('Failed to convert')` swallows server's specific 409/400/403 messages.** `estimates.routes.ts:739-740,809,748` returns "Already converted", "Estimate was cancelled", "Estimate is already being converted. Try again in a moment.", "Plan limit reached". Web replaces all with generic "Failed to convert". Operator hits tier limit, gets useless toast. L8, L7.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:102`
  <!-- meta: fix=use-formatApiError(err)+err.response.data.message-fallback -->

- [ ] WEB-UIUX-961. **[MAJOR] Detail header has 5 outline-style action buttons in a row + Print = 6 total — no clear primary CTA.** Send (primary border), Approve (emerald border), Convert (green border), Reject (red border), Print (surface border). All same height, same padding, all outline; emerald + green are visually near-identical. Operator scanning header can't identify highest-leverage action. Tablet (768) wraps awkwardly. L1, L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:190-255`
  <!-- meta: fix=primary-action=solid-fill-by-status(Approve-when-sent-or-Send-when-draft-or-Convert-when-approved)+collapse-rest-into-overflow-menu -->

- [ ] WEB-UIUX-962. **[MAJOR] List-page bulk action bar exposes only Delete — `bulkConvert` API + client wrapper exist unused.** `endpoints.ts:904` declares `bulkConvert(estimate_ids[])`, server `estimates.routes.ts:325-489` implements it (admin-only, tier-limit, idempotency, 100-id cap). `EstimateListPage.tsx:580-608` bulk bar has only Delete-selected. Operator approving 30 estimates after a quote-batch must click Convert one row at a time. L8, L3.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:580-608`
  <!-- meta: fix=add-Convert-Selected-button-using-estimateApi.bulkConvert -->

- [ ] WEB-UIUX-963. **[MAJOR] List-page bulk-Delete uses `Promise.all` — partial failure shows "Deleted N" toast even when half failed.** `:591-595`: `Promise.all([...selectedIds].map(id => estimateApi.delete(id)))` — if 3 of 10 throw, `.all` rejects but `await` is inside try, `catch` shows generic. Even when all settle, success toast counts requested IDs not server-confirmed. L8.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:588-596`

- [ ] WEB-UIUX-964. **[MAJOR] Reject confirm copy "This cannot be undone" — false. PUT `/:id` accepts arbitrary `status` change, server has no rule preventing rejected→draft.** Copy lies; operator who mis-clicks Reject reads "permanent" warning, panics, opens ticket. L7.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:237`
  <!-- meta: fix=either-enforce-server-side-rejected-as-terminal-OR-soften-copy-to-Reject-this-estimate? -->

- [ ] WEB-UIUX-965. **[MAJOR] Detail h1 renders "Estimate " (trailing space) when `order_id` is null.** `:177` `<h1>Estimate {estimate.order_id}</h1>` — breadcrumb falls back to `Estimate #${id}` (`:166`) but the page title doesn't. Estimates pre-`order_id`-policy or imported rows show empty heading. L7, L9.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:177`
  <!-- meta: fix=mirror-breadcrumb-fallback -->

- [ ] WEB-UIUX-966. **[MAJOR] Detail page shows `Sent` date but never `approval_token_expires_at`.** SMS contains a magic-link approval URL with TTL (`APPROVAL_TOKEN_TTL_MS`); customer who delays beyond expiry hits 410, asks shop to reissue. Web detail Details card has no "Approval link expires DD MMM HH:mm" row. Operator can't see whether to resend. L8, L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:461-507`

- [ ] WEB-UIUX-967. **[MAJOR] Inline line-item editor exposes raw `tax_amount` cell with no `tax_class_id` picker.** `EstimateDetailPage:345-350`. Modal create at `EstimateListPage:287-296` has tax-class dropdown that auto-computes. Editor forces operator to do mental math + paste cents into tax field. Inconsistent within same flow. L4, L7.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:323-359`

- [ ] WEB-UIUX-968. **[MAJOR] Inline line-item Save accepts empty-description rows.** Save click sends `draftItems` raw; no `filter(li => li.description.trim())`. CreateEstimateModal at `EstimateListPage:179-183` filters; editor doesn't. Server stores blank line-items. L7, L8.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:309`

#### Minor — Polish, edge cases

- [ ] WEB-UIUX-969. **[MINOR] CreateEstimateModal has no `discount` input; server accepts `discount` field — modal forces "create then edit notes" two-step.** `EstimateListPage:188-202` payload omits discount. Estimate with line-item discount not expressible in create flow. L4.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:171-203`

- [ ] WEB-UIUX-970. **[MINOR] `sent_at = COALESCE(sent_at, ?)` — re-send after edit doesn't refresh `sent_at`.** Audit trail loses re-send timestamp; Detail "Sent" field shows first-send only even if customer received v2 yesterday. L11, L8.
  `packages/server/src/routes/estimates.routes.ts:944,953-954`

- [ ] WEB-UIUX-971. **[MINOR] List sort headers include `customer` column — server may not honor.** `EstimateListPage:621` adds 'customer' to sort headers; `estimates.routes.ts` GET `/` likely whitelists `order_id|status|total|valid_until|created_at`. Click on Customer → arrow flips, list unchanged or 400 swallowed. L7, L8.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:619-625`

- [ ] WEB-UIUX-972. **[MINOR] Detail page has no `valid_until` editor.** Notes editable inline; expiry is not. Operator extending validity must round-trip via server PUT (no UI). L4.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:399-431`

- [ ] WEB-UIUX-973. **[MINOR] Versions accordion shows `v1, v2` + date but no diff/view button.** `estimateApi.versionDetail` exposed in `endpoints.ts:909`, never called. Operator can see "3 prior versions exist" but cannot inspect what changed. Useless history panel. L8, L1.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:530-549`

- [ ] WEB-UIUX-974. **[MINOR] Inline line-item Save: sidebar Total stays stale until `invalidateQueries` refetch settles.** No client-side recompute; brief mismatch where line items show new sum but Summary card still shows old. L1, L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:127-136,437-457`

- [ ] WEB-UIUX-975. **[MINOR] Approve / Send / Convert / Reject confirms use generic `confirm()` dialog with no `confirmLabel` differentiation except Reject (`danger:true`).** Approve and Convert get default neutral OK button — pattern asymmetry. Operator scanning the dialog can't tell at a glance which flow they're in. L9.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:209,222`

- [ ] WEB-UIUX-976. **[MINOR] `'converting'` transient status leaks to UI on race.** `estimates.routes.ts:802` flips status to 'converting' for atomic guard; if operator refreshes during the convert window, badge shows raw "converting" with gray fallback. Should map to "Converting…" with spinner. L9, L13.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:16-22`

- [ ] WEB-UIUX-977. **[MINOR] List-page empty state copy says "Click 'New Estimate' above" but no in-state CTA button.** Operator must scroll up to find the button. Standard pattern: include a primary button inline. L4, L1.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:651-663`

- [ ] WEB-UIUX-978. **[MINOR] `_redirect_after_convert` is implicit — `convert` mutation auto-navigates to `/tickets/:id`.** No "Open ticket" / "Stay here" choice; operator wanting to print estimate before viewing ticket is yanked away. L4.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:99-101`

- [ ] WEB-UIUX-979. **[NIT] Approve mutation loading state coexists with Reject loading state via shared `anyMutationPending` — clicking Approve disables Reject too, fine — but no per-button skeleton cue beyond `<Loader2>` icon swap. Reject button visually identical mid-Approve.** L11.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:160`

- [ ] WEB-UIUX-980. **[NIT] Approve button confirm rejects auto-cleanup on backdrop dismiss — modal overlay click counts as "no" via `confirm` store, no toast feedback. Operator who clicks outside waits for nothing.** L8.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:209`


### Web UI/UX Audit — Pass 12 (2026-05-05, flow walk: Issue Gift Card — sell, redeem, reload, recover)

Walk of "Issue Gift Card" end-to-end: cashier issues card → must sell to customer → customer presents card at POS → cashier redeems → balance reloads later. Cross-checked server `giftCards.routes.ts` (issue/lookup/redeem/reload + 128-bit hashed codes + brute-force rate limit + audit) against client `GiftCardsListPage.tsx`, `GiftCardDetailPage.tsx`, `unified-pos/CheckoutModal.tsx`, `App.tsx`, `Sidebar.tsx`, `CommandPalette.tsx`. Largest gap: server has full lookup + redeem infra (admin-side enumerated by `giftCardApi.lookup`/`redeem`) but **no POS UI ever calls it**. Cards can be issued and reloaded; cannot be spent.

#### Blockers — Cannot redeem, silent currency corruption, no recovery, no nav

- [ ] WEB-UIUX-981. **[BLOCKER] POS has no Gift Card tender — `PaymentMethod = 'Cash' | 'Card' | 'Other'`.** `CheckoutModal.tsx:16` literal union does not include gift card; `PAYMENT_METHODS` array (`:23-27`) only Cash/Card/Other. Operator finishes sale → customer hands physical card → no UI path to apply balance. `giftCardApi.lookup` + `giftCardApi.redeem` declared in `endpoints.ts:1274-1276` and never called anywhere in `packages/web/src`. Entire feature half-built. L1, L8, L4.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:16-27`
  `packages/web/src/api/endpoints.ts:1274-1276`
  <!-- meta: fix=add-GiftCard-tender+code-input-modal+lookup→redeem-flow+update-PaymentMethod-union -->

- [ ] WEB-UIUX-982. **[BLOCKER] Currency render heuristic silently 100x-divides $1000–$10000 cards.** `formatCurrency` in both list + detail pages: `Number.isInteger(amount) && Math.abs(amount) >= 1000 ? amount / 100 : amount`. Server `GIFT_CARD_MAX_AMOUNT = 10_000` (dollars). Issue $1500 corp card → server stores `1500` (integer) → list/detail render `$15.00`. Comment claims "no real-world gift-card balance reaches $1000 in float-dollars outside corporate gifting" — corporate gifting is exactly the cohort that uses $1000+ cards. Reload to round amount has same defect. L7, L13, L8.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:57-63`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:41-49`
  <!-- meta: fix=remove-cents-heuristic+pin-server-to-one-representation+migrate-callsites -->

- [ ] WEB-UIUX-983. **[BLOCKER] No way to disable lost/stolen card.** DB `status` enum has `'disabled'` (statusBadge handles it, list filter has Disabled option) but giftCards.routes.ts exposes ONLY GET, POST, redeem, reload — no PATCH/DELETE/disable route. DetailPage has no Disable / Void / Cancel button. Customer reports stolen $500 card → operator must hit DB directly. L1, L8, L16.
  `packages/server/src/routes/giftCards.routes.ts:104-451`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-293`
  <!-- meta: fix=add-POST-/:id/disable-server-route+Disable-Card-action-on-DetailPage+confirm-with-reason -->

- [ ] WEB-UIUX-984. **[BLOCKER] Issued code shown ONCE, never recoverable.** IssueModal success state at `:138-141`: "Save this code now — it will not be shown again." Code value is `select-all` div with no Copy button, no QR, no Print, no Send-to-recipient-email. Server stores `code_hash` only (SEC-H38, plaintext drops on next migration). `recipient_email` collected at issue but no email-send path — the field is decorative. Customer who drops the receipt = card lost forever. L4, L8.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:123-153`
  <!-- meta: fix=email-on-issue+Copy-button+QR-render+Print-receipt -->

- [ ] WEB-UIUX-985. **[BLOCKER] Issue success modal closes on backdrop click + Esc — code lost on stray click.** `:127` root `onClick={onClose}` and `:128` `onKeyDown Escape→onClose`. The state is "code shown for first/last time, save NOW" yet the dismiss surface is a full-screen click-target. Operator scrolls, clicks page background → modal closes → code never seen again. Should require explicit Done click + maybe typed-confirm "I have saved the code" checkbox. L8, L16, L11.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:125-130`

- [ ] WEB-UIUX-986. **[BLOCKER] Sidebar has zero Gift Cards entry.** `grep "gift" packages/web/src/components/layout/Sidebar.tsx` → empty. Discoverable only via Cmd+K palette (`CommandPalette.tsx:73`) or direct `/gift-cards` URL. Cashier with no docs cannot find feature. L8, L1, L4.
  `packages/web/src/components/layout/Sidebar.tsx`

- [ ] WEB-UIUX-987. **[BLOCKER] POS has no "sell gift card" line item.** Operator selling a $50 gift card to a walk-in customer must (a) leave POS, (b) navigate to /gift-cards, (c) Issue card, (d) save code, (e) return to POS, (f) add a generic "Gift Card" misc product line, (g) checkout. Sale is never linked to gift_card_id; receipt doesn't show issued code; `gift_card_transactions` row says `notes='Initial load'` instead of `'Sold via invoice #N'`. Walk-in flow broken. L1, L4, L8.
  `packages/web/src/pages/unified-pos/`
  `packages/server/src/routes/giftCards.routes.ts:303-307`
  <!-- meta: fix=add-Sell-Gift-Card-button-in-POS-Misc-section+create-invoice-line+POST-issue-with-invoice_id-link -->

#### Major — Truthfulness, label/hierarchy, recovery

- [ ] WEB-UIUX-988. **[MAJOR] IssueModal collects no `customer_id` — server accepts it, list endpoint LEFT-JOINs customers, both wasted.** `giftCards.routes.ts:128` joins `customers c ON c.id = gc.customer_id`, returns `c.first_name, c.last_name`. UI's `IssueFormState` has only amount/recipient_name/recipient_email/expires_at. Operator selling to existing customer with full profile must retype name. Card never appears on customer's profile. L1, L4.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:38-43,86-91,104-109`
  <!-- meta: fix=add-CustomerPicker-component+pass-customer_id+show-customer-link-on-list+detail -->

- [ ] WEB-UIUX-989. **[MAJOR] IssueModal collects no `notes` — server validates 1000 chars.** `giftCards.routes.ts:284-286` accepts notes, INSERT writes notes column. UI never offers field. Operator can't tag "promo: black-friday-2025" or "comp: customer service apology". Reporting on issuance reasons impossible. L4, L8.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:177-227`

- [ ] WEB-UIUX-990. **[MAJOR] DetailPage typed `notes: string | null` but never renders it.** `GiftCardDetail` interface includes notes; the meta `<dl>` at `:258-281` shows recipient/email/issued/expires but skips notes. Manager auditing card never sees the original tag. L1, L8.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:31,258-281`

- [ ] WEB-UIUX-991. **[MAJOR] DetailPage transaction row never shows WHO redeemed/reloaded.** Server `gift_card_transactions` has `user_id` column written on every insert. DetailPage transactions table renders date / type / notes / amount only. Audit trail invisible — operator can't tell which cashier rang the redemption. L8, L11.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:303-329`
  <!-- meta: fix=server-detail-route-must-JOIN-users+UI-add-By-column -->

- [ ] WEB-UIUX-992. **[MAJOR] DetailPage redemption row never links invoice.** `redeem` route accepts `invoice_id` and writes it on the transaction row. List response `:447-449` selects `*`, so invoice_id is present. UI doesn't render — Notes column shows hardcoded "Redeemed at POS". Operator reconciling a refund can't pivot from gift-card-tx → invoice. L1, L8.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:317-318`

- [ ] WEB-UIUX-993. **[MAJOR] IssueModal "Initial value ($)" hardcoded `$` glyph — ignores tenant currency.** Label `:180`. Tenant in EUR sees "$" prompt; submits "25.00" thinking euros; server stores 25 dollar-denominated value (server doesn't know currency). Same pattern as the @audit-fixed display path but the input prompt itself was missed. L9, L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:180`

- [ ] WEB-UIUX-994. **[MAJOR] No client-side max on amount; server caps $10k → generic toast.** IssueModal input `min="0.01"` no `max`; ReloadModal input same. Operator types 50000 → server 400 "Gift card amount cannot exceed $10,000" → onError toast = `err.message` (mutation throw is `'Enter a valid amount'`, axios error different). Server's specific message NOT surfaced — `onError` swallows it: `err instanceof Error ? err.message : 'Failed to issue gift card'` — server error reaches as AxiosError with `.response.data.message` not on the Error.message. L8, L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:117-121`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:101-103`

- [ ] WEB-UIUX-995. **[MAJOR] Expiry date input has no `min` — accepts past dates.** `<input type="date" value={form.expires_at}>` at `:220-225`. Operator can set expiry to yesterday → server `validateIsoDate` accepts (no past-check) → card issues already-expired. Customer gets card, attempts redeem, server returns "Gift card expired". L7, L8.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:216-226`

- [ ] WEB-UIUX-996. **[MAJOR] List page has no pagination control rendered despite server returning `pagination` block.** `GiftCardListData.pagination` typed; query result destructure pulls `cards` and `summary`, never reads `pagination`. Tenant with 200 cards sees first 50 + nothing else. L1, L8.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:282-283,353-406`

- [ ] WEB-UIUX-997. **[MAJOR] List page has no "expiring soon" filter or warning column.** Card with expiry 7 days out is visually identical to never-expiring card. Liability cleanup / customer outreach impossible from this surface. L8, L11.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:309-331,353-406`

- [ ] WEB-UIUX-998. **[MAJOR] No "outstanding liability" CSV export.** GAAP requires gift-card-liability tracking; the summary card shows total_outstanding but no Export button. Bookkeeper must screenshot or extract from DB. L1, L8.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:285-307`

- [ ] WEB-UIUX-999. **[MAJOR] Reload button stays enabled when card balance ≥ $10,000.** Server `GIFT_CARD_MAX_AMOUNT = 10_000` rejects further reload but the gate at `GiftCardDetailPage.tsx:283` only checks `status !== 'used' && status !== 'disabled'`. Operator clicks Reload, types $1, server 400, generic toast. L1, L8.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-293`

- [ ] WEB-UIUX-1000. **[MAJOR] DetailPage no "Send code to recipient email" action even when recipient_email is set.** Field collected at issue, stored, displayed as readonly meta — never actionable. Customer says "I lost the code, can you resend?" → no UI. L4, L8.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:265-269`

- [ ] WEB-UIUX-1001. **[MAJOR] No dual-control / second-admin requirement on issuance.** Issuing cash-equivalent value of up to $10,000 takes one admin or manager click. Estimates have a self-approval guard (`Cannot approve your own estimate`); gift cards have nothing. Cashier-collusion risk: manager-role employee mints $10k card, reads code from success modal, uses it. L16.
  `packages/server/src/routes/giftCards.routes.ts:253-323`

#### Minor — Polish, edge cases

- [ ] WEB-UIUX-1002. **[MINOR] IssueModal Issue button gate `!form.amount` accepts non-numeric "abc" — same defect as WEB-UIUX-489 on Reload.** Click → mutationFn `parseFloat → NaN` → throws → toast. Should disable until `parseFloat(form.amount) > 0`. L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:236-243`

- [ ] WEB-UIUX-1003. **[MINOR] IssueModal first-render no autofocus on amount input.** ReloadModal correctly auto-focuses; IssueModal's amount input lacks `autoFocus`. Cashier on quiet POS Tab-stops through DOM. L4, L12.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:182-190`

- [ ] WEB-UIUX-1004. **[MINOR] Issue success modal "Done" button label generic.** Better: "I've saved the code". Reinforces the consequence + acknowledges the irreversibility. L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:145-150`

- [ ] WEB-UIUX-1005. **[MINOR] Issue success modal monospaced code at 2xl size with `tracking-widest` — 32-char code wraps awkwardly on narrow modal.** No segmentation like `XXXX-XXXX-XXXX-...`. Eye chunks readability research (Tinker; Wickelgren) shows 4-char groups improve transcription accuracy ~30%. L9, L11.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:142-144`

- [ ] WEB-UIUX-1006. **[MINOR] Detail page back-link is text + arrow only ("Gift Cards"), no breadcrumb path.** Pattern asymmetry vs Estimates/Tickets which expose breadcrumb. L9.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:191-193,217-223`

- [ ] WEB-UIUX-1007. **[MINOR] Currency-cents heuristic comment says "> 1000" but code uses `>= 1000`.** Off-by-one between docstring and behavior — also reinforces that the heuristic is a known footgun. L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:50-62`

- [ ] WEB-UIUX-1008. **[MINOR] List balance column right-aligned but column header "Balance" left-aligned (`text-left px-4 py-3`) — header drifts away from values on wide tables.** Visual scan friction. L9, L11.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:360`

- [ ] WEB-UIUX-1009. **[MINOR] List status filter chip not visually grouped with keyword search — separate `<select>` is plain styled, no chip pattern.** Most filter UIs in this app use chip toggles (LeadPipelinePage etc). Inconsistency. L9.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:321-330`

- [ ] WEB-UIUX-1010. **[MINOR] Detail "Reload balance" button sized small + outline — same surface as primary buttons elsewhere on the page; no obvious primary CTA.** L1, L11.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:285-291`

- [ ] WEB-UIUX-1011. **[MINOR] No progress bar / "spent of initial" visualization.** Detail summary shows `$X of $Y initial` text only. A linear bar improves at-a-glance utilization. L9.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:251-255`

- [ ] WEB-UIUX-1012. **[MINOR] `statusBadge` switch is exhaustive but has no default — TS `never` guard fine, but if backend adds a status (`'expired'` natural next) the badge silently renders nothing.** L7.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:70-76`

- [ ] WEB-UIUX-1013. **[MINOR] Lookup endpoint rate-limit error 429 never surfaced to operator UI** — `giftCardApi.lookup` not called, but if/when wired, generic-onError handlers won't translate "Too many lookup attempts" into a meaningful "wait 60s" countdown. Pre-emptive: lookup UI should special-case 429 + show retry-after. L8.
  `packages/server/src/routes/giftCards.routes.ts:188-197`

- [ ] WEB-UIUX-1014. **[NIT] `dollarsFromMaybeCents` exists on detail page, near-duplicate `formatCurrency` on list page — two separate copies of the same fragile heuristic.** L7.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:41-49`
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:57-63`

- [ ] WEB-UIUX-1015. **[NIT] Issue success modal Done button color `bg-primary-600 text-primary-950` — relies on tenant theme; in dark theme on mobile, `text-primary-950` (very dark) on `bg-primary-600` may have <3:1 contrast depending on primary hue.** L12.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:147`

- [ ] WEB-UIUX-1016. **[NIT] No `aria-live` region on the issued-code success block.** Screen reader users get the modal but the line "Save this code now — it will not be shown again" is not announced as `polite`/`assertive`. L12.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:138-144`


### Web UI/UX Audit — Pass 13 (2026-05-05, flow walk: Process Refund — issue, approve, return, store credit)

Walk of "Process Refund" end-to-end. Server `/api/v1/refunds` (mounted at `index.ts:1603`) exposes a full pending→completed/declined refund state-machine with idempotency, role gates, atomic capture-state checks, commission reversal, and store-credit upsert. Client surface: zero. `endpoints.ts` declares 46 `*Api` namespaces; **no `refundApi` exists**. Three parallel write paths (`POST /refunds`, `POST /invoices/:id/credit-note`, `POST /pos/return`) — only path #2 wired to UI (the InvoiceDetail "Credit Note" button). The pending-refund approval queue is invisible. Cross-checked `refunds.routes.ts`, `pos.routes.ts:2492-2637`, `invoices.routes.ts:1159-1318`, `InvoiceDetailPage.tsx`, `RefundReasonPicker.tsx`, `endpoints.ts`, `Sidebar.tsx`, `CommandPalette.tsx`, `App.tsx`, `UnifiedPosPage.tsx`, `CustomerDetailPage.tsx`.

#### Blockers — Refund flow non-existent in UI; approval workflow defeated

- [ ] WEB-UIUX-1017. **[BLOCKER] Entire `/api/v1/refunds` API has zero client callers — no `refundApi` in `endpoints.ts`.** Server exposes GET / (list with pagination + customer/invoice/creator joins), POST / (create pending), PATCH /:id/approve (admin only, atomic + commission reversal + optional store-credit upsert), PATCH /:id/decline, GET /credits/:customerId, POST /credits/:customerId/use, GET /credits/liability. `grep refundApi packages/web/src` → empty. `grep "/refunds" packages/web/src` → empty. Months of server work — pending-state machine, SCAN-779 transitions, SEC-H28 atomic guard, SEC-H29 idempotency, SEC-M44 capture-state checks, EM1 commission reversal — entirely unreachable through any UI. L1, L8, L4.
  `packages/web/src/api/endpoints.ts:35-1492 (no refundApi exported)`
  `packages/server/src/routes/refunds.routes.ts:73-546`
  `packages/server/src/index.ts:1603`
  <!-- meta: fix=add-refundApi-namespace+wire-list+approve+decline+create+credits-endpoints -->

- [ ] WEB-UIUX-1018. **[BLOCKER] No `/refunds` route, no Sidebar entry, no CommandPalette command.** `App.tsx`, `Sidebar.tsx`, `CommandPalette.tsx` grep for "refund" → empty. Even if a refund row existed in the DB, no operator can navigate to it. F6 "Returns hotkey" handler at `UnifiedPosPage.tsx:121` toasts `'Returns flow coming soon — scan the original invoice from the ticket page for now'` — feature key is recognized but dead. L8, L1, L4.
  `packages/web/src/App.tsx`
  `packages/web/src/components/layout/Sidebar.tsx`
  `packages/web/src/components/shared/CommandPalette.tsx`
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:121`

- [ ] WEB-UIUX-1019. **[BLOCKER] Pending-refund approval queue invisible — admin has no UI to approve or decline a pending refund.** `refunds.routes.ts:253-435` implements PATCH /:id/approve + PATCH /:id/decline with admin-only role gate, prior-status guard, atomic flip + invoice decrement, commission reversal, store-credit upsert. There is no list page of pending refunds, no detail view with Approve/Decline buttons, no notification when a refund needs admin attention. The dual-control workflow exists in code but is effectively dead. L1, L8, L16.
  `packages/server/src/routes/refunds.routes.ts:253-435`
  <!-- meta: fix=add-RefundsListPage+RefundDetailPage+approve-decline-buttons+notification-on-pending-create -->

- [ ] WEB-UIUX-1020. **[BLOCKER] POS has no return / refund flow despite `posApi.return` declared with idempotency.** `endpoints.ts:753-761` exposes `posApi.return` with X-Idempotency-Key headers. `grep "posApi.return" packages/web/src` → 0 callers. Server `/pos/return` (`pos.routes.ts:2492-2637`) creates negative invoice + restores stock + writes refund row at status='completed'. Cashier with returning customer must (a) navigate to invoice detail, (b) click Credit Note (different flow!), (c) manually open drawer, (d) hand back cash — no scan-returned-item, no per-line-item return UI. L1, L4, L8.
  `packages/web/src/api/endpoints.ts:749-761`
  `packages/server/src/routes/pos.routes.ts:2492-2637`

- [ ] WEB-UIUX-1021. **[BLOCKER] `/pos/return` writes refund row directly at `status='completed'` — bypasses dual-control approval entirely.** `pos.routes.ts:2618-2621` `INSERT INTO refunds ... status='completed'`. Refunds.routes.ts `POST /` always inserts `status='pending'` then requires admin approve. The cashier path (when wired) skips that gate. Defeats the entire SEC-H28 atomic-approve design + SEC-H29 idempotency + EM1 commission reversal that fires only on `/approve`. Manager dual-control becomes opt-in based on which write path the cashier happens to take. L16, L4.
  `packages/server/src/routes/pos.routes.ts:2618-2621`
  `packages/server/src/routes/refunds.routes.ts:107,229-234`
  <!-- meta: fix=force-pos-return-to-status=pending-OR-require-elevated-role-at-route-level -->

- [ ] WEB-UIUX-1022. **[BLOCKER] Commission reversal SKIPPED on the only currently-reachable refund path (Credit Note).** `refunds.routes.ts:322-377` calls `reverseCommission` inside the approve handler — wired to `/refunds/:id/approve` only. Wired UI flow is `/invoices/:id/credit-note` (`invoices.routes.ts:1162-1317`) which never calls `reverseCommission`. Tech who fitted the device on a returned/credited ticket keeps full commission; payroll overpays. Same gap on `/pos/return` (also creates negative invoice without commission reversal). L8, L16.
  `packages/server/src/routes/invoices.routes.ts:1162-1317`
  `packages/server/src/routes/pos.routes.ts:2496-2637`
  <!-- meta: fix=invoke-reverseCommission-from-credit-note-and-pos-return-paths-with-original-invoice-fraction -->

- [ ] WEB-UIUX-1023. **[BLOCKER] No store-credit balance shown anywhere on Customer Detail.** Server `GET /refunds/credits/:customerId` returns `{ balance, transactions[] }`; `POST /credits/:customerId/use` debits with atomic guarded UPDATE. `CustomerDetailPage.tsx` grep for "store_credit|credit balance|store credit" → empty. Customer with $200 store credit on file is invisible to cashier; cashier can't apply credit to a sale; bookkeeper can't audit per-customer balance. L1, L8.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx`
  `packages/server/src/routes/refunds.routes.ts:439-525`

- [ ] WEB-UIUX-1024. **[BLOCKER] No "Credits Liability" / "Outstanding Refund Liability" dashboard.** Server `GET /refunds/credits/liability` (admin/manager) returns total + per-customer breakdown; never called. GAAP requires gift-card AND store-credit liability tracking on the closing books — same finding pattern as WEB-UIUX-998 for gift cards. Bookkeeper must hit DB. L8, L1.
  `packages/server/src/routes/refunds.routes.ts:528-545`

- [ ] WEB-UIUX-1025. **[BLOCKER] No way to issue a CASH refund — the only wired path ("Credit Note") creates a negative invoice but does not move money out.** Customer wants a $50 cash refund from till. Operator clicks "Credit Note" on InvoiceDetail → server creates `CRN-####` invoice with `amount_paid=0`, decrements original invoice's amount_due. No drawer pop, no `cash_register` row written, no `payments` row showing $-50 paid out. Cashier hands back $50 from drawer with no system record of the cash leaving. End-of-day Z-report won't reconcile. L1, L4, L8, L16.
  `packages/server/src/routes/invoices.routes.ts:1162-1317`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311,737-805`
  <!-- meta: fix=add-Cash-Refund-tender-on-credit-note-modal+post-cashRegister-row+open-drawer -->

#### Major — Truthfulness, hierarchy, recovery, mismatch with server

- [ ] WEB-UIUX-1026. **[MAJOR] InvoiceDetail "Credit Note" button label misleads — does not file a refund row, only creates a negative invoice.** Operator looking at `/refunds` (when it exists) won't see this credit-note in the refund list because `invoices.routes.ts:1162-1317` writes to `invoices` table with `credit_note_for=N`, never to `refunds` table. Manager asking "show me all refunds processed today" gets an empty list while ten credit notes were issued. The two reporting surfaces never reconcile. L7, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377-380`
  <!-- meta: fix=server-must-also-INSERT-INTO-refunds-on-credit-note-OR-rename-button-to-Issue-Credit-Note-(no-money-back) -->

- [ ] WEB-UIUX-1027. **[MAJOR] Credit Note modal client-side max = `amount_paid` — server caps at `original.total` minus prior credits.** `InvoiceDetailPage.tsx:298-303`: `maxRefundable = Number(invoice.amount_paid)`. Server (`invoices.routes.ts:1186-1202`): caps at `original.total` minus aggregate `SUM(-total) FROM invoices WHERE credit_note_for = ?`. Two failure modes: (a) invoice partially paid, fully credit-able by server — client blocks at `amount_paid`; (b) invoice already partially credited — client allows full `amount_paid` even though server now caps lower. Operator hits 400 "Credit note total would exceed invoice total" with no client-side hint. L7, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311`
  `packages/server/src/routes/invoices.routes.ts:1186-1202`

- [ ] WEB-UIUX-1028. **[MAJOR] Credit Note modal "Max: $X (amount paid)" hint never subtracts prior credit notes.** Operator on a $200 invoice that already has a $50 credit issued sees "Max: $200" → types $200 → server 400 "already credited 50.00 of 200.00". Hint outright lies. L7, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:776-778`
  <!-- meta: fix=fetch-invoice.related_credit_notes-and-subtract-from-displayed-cap -->

- [ ] WEB-UIUX-1029. **[MAJOR] Credit Note success toast "Credit note created" omits the new `CRN-####` order id — operator cannot reference doc.** `creditNoteMutation.onSuccess` at `:172` toasts a generic string. Server returns `creditNote` in the response with `order_id: 'CRN-####'`. Operator who needs to email or print the credit note has no in-toast link or copy affordance. L8, L11.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-176`

- [ ] WEB-UIUX-1030. **[MAJOR] No "View credit notes" / "Related documents" panel on InvoiceDetail.** Once a credit note is issued, original invoice has `credit_note_for=null` (it's the credit-note that points up via `credit_note_for=ORIG_ID`). InvoiceDetail of the original never lists child credit notes. Reconciliation requires manual `WHERE credit_note_for = ?` query. L1, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:393-588`

- [ ] WEB-UIUX-1031. **[MAJOR] InvoiceDetail of a credit-note (negative) invoice has no "Original invoice" link.** When operator opens `CRN-####` invoice in InvoiceDetail, the page renders the same UI as a regular invoice — header just shows the negative total. `credit_note_for` field present in `InvoiceDetail` type but page doesn't render a link back to original. Cashier navigating credit-note can't pivot to source. L1, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:328-423`

- [ ] WEB-UIUX-1032. **[MAJOR] Credit-Note-overflow → store credit happens silently — UI gives no acknowledgement.** Server `invoices.routes.ts:1259-1302` upserts `creditOverflow` into `store_credits` table when `amount > remaining due`. UI just toasts "Credit note created"; customer's new store-credit balance is not surfaced. Operator cannot tell the customer "We've put $X on file." L8, L11.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-177`
  `packages/server/src/routes/invoices.routes.ts:1259-1302`

- [ ] WEB-UIUX-1033. **[MAJOR] `RefundReasonPicker` "Other" option requires no minimum note length — server accepts blank.** `:43-50` `handleNoteChange` doesn't enforce that "other" code carries a non-empty note. Server `invoices.routes.ts:1183-1185` `cnNote` accepts blank string trimmed to null. Reporting on "other" reasons becomes useless tag-without-context. L7, L8.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:42-50`

- [ ] WEB-UIUX-1034. **[MAJOR] `composedReason = ${code}: ${note}` — colon ambiguity destroys downstream parsing.** `InvoiceDetailPage.tsx:159-161` builds `reason` as `${code}: ${note}` but a note like "see ticket #123 12:30pm" reintroduces the same colon, breaking any `split(':')`-based reverse-parse. Server now stores both `credit_note_code` + `credit_note_note` separately (migration 150) but the legacy `reason` column still stamped via the composed string is what most reports read. L7, L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-167`

- [ ] WEB-UIUX-1035. **[MAJOR] CustomerDetail invoice list status enum has `'refunded'` color branch — server invoice status enum never sets `'refunded'`.** `CustomerDetailPage.tsx:1685` includes `refunded:` color rule. Server invoice statuses: `unpaid|partial|paid|void|credit_note` (per `invoices.routes.ts:1217,1250` + assertInvoiceTransition). Dead branch; if a future migration ever sets `'refunded'`, it'll render purple but the rest of the UI doesn't know that status. L7.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1685`

- [ ] WEB-UIUX-1036. **[MAJOR] Credit Note modal's `aria-describedby="credit-amount-label"` references a non-existent id.** `:768`. The "Max: $X (amount paid)" `<p>` hint at `:776-778` has no id. Screen reader users get a dangling describedby pointer; the hint is not announced as the input's description. L12.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:768,776-778`

- [ ] WEB-UIUX-1037. **[MAJOR] Credit Note modal has no recovery: no "Preview", no "Save Draft", no Undo window.** Void has 5s undo (`useUndoableAction` at `:110-135`); credit-note creation is fire-and-forget. Operator who fat-fingers $200 instead of $20 must manually issue a $180 reverse credit note and reconcile. Pattern asymmetry inside same page. L8, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177`

- [ ] WEB-UIUX-1038. **[MAJOR] Refund-related side-effects (commission reversal, payroll lock) entirely invisible to operator.** Server emits `commission_reversal_skipped` and `commission_reversal_error` flags in approve response (`refunds.routes.ts:404-411`); even if a refund-approve UI were wired, the typical `onSuccess` toast pattern won't surface those flags. Manager approving a refund won't know whether commission was reversed or skipped due to locked payroll period. L8, L11.
  `packages/server/src/routes/refunds.routes.ts:319-411`

#### Minor — Polish, edge cases, label/hierarchy

- [ ] WEB-UIUX-1039. **[MINOR] InvoiceDetail header has 5 buttons in a row (Record Payment, Payment Plan, Financing, Print, Credit Note, Void) — no clear primary CTA on a partially-paid invoice.** Same finding as WEB-UIUX-961 (estimates). Six similar-height pills crowd the header on tablet (768) and wrap. Highest-leverage action depends on status but UI doesn't reflect that. L1, L11.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:342-389`

- [ ] WEB-UIUX-1040. **[MINOR] Credit Note button uses amber ramp; Void uses red — color implies "amber = warning, red = danger" gradient, but Credit Note is also irreversible (no rollback path).** Operator scanning the header may treat amber as "soft action" and miss the no-undo property. L9.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377-388`

- [ ] WEB-UIUX-1041. **[MINOR] Credit Note modal Cancel + Create buttons same width (`flex-1`) — no visual hierarchy. Create is amber-filled, Cancel is outline-neutral; sizes equal.** L9, L11.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:791-802`

- [ ] WEB-UIUX-1042. **[MINOR] RefundReasonPicker hint copy uses terminal periods ("Arrived broken or malfunctioned.") — micro-inconsistency vs other dropdown labels in the app that omit terminal periods.** L9.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:18-23`

- [ ] WEB-UIUX-1043. **[MINOR] RefundReasonPicker "free-form context to help with reporting…" placeholder mixes purpose + audience — clearer: "What happened? (optional)".** L7.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:88`

- [ ] WEB-UIUX-1044. **[MINOR] RefundReasonPicker note `maxLength=500` client-side — server has no documented cap on `credit_note_note` column.** Client enforces a cap the server doesn't; if server later trims, mismatch silent. L7.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:91`

- [ ] WEB-UIUX-1045. **[MINOR] Credit Note modal opens with amount input autofocused but no "Full amount" preset button (Record Payment modal has one at `:618`).** Pattern asymmetry within same page. Operator refunding the full paid balance must hand-type. L4, L9.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`

- [ ] WEB-UIUX-1046. **[MINOR] Credit Note modal Esc-to-close wired (`:60-69`) but backdrop-click also closes (`:744`) without confirming unsaved input.** Operator who typed amount + reason + note clicks slightly off-modal → loses everything. Same surface pattern as gift-card success modal (WEB-UIUX-985) — one stray click destroys staged data. L8, L16.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:744`

- [ ] WEB-UIUX-1047. **[MINOR] Z-Report (`ZReportModal.tsx:204`) shows "Refunds" total in cents, but no drill-down link to refund detail and no per-tender breakdown (cash refunds vs card refunds).** End-of-day reconciliation is summary-only. L8, L1.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:204`

- [ ] WEB-UIUX-1048. **[MINOR] BlockChyp settings page references "refund" but no card-refund-back-to-original-tender flow is wired in any UI.** `blockchypApi` likely has no `refund(transactionId)` method despite the processor supporting it. Card customers expecting refund back to card get cash or "credit on file" instead. L8.
  `packages/web/src/pages/settings/BlockChypSettings.tsx`

- [ ] WEB-UIUX-1049. **[MINOR] Dashboard `DashboardPage.tsx` mentions "refund" but has no widget for "pending refunds requiring approval" — admin landing page doesn't surface the queue.** Even if the approval UI existed, admin would need to remember to navigate. L1, L4.
  `packages/web/src/pages/dashboard/DashboardPage.tsx`

- [ ] WEB-UIUX-1050. **[MINOR] DailyNudge component (`DailyNudge.tsx`) references refund-onboarding text but the feature it nudges users toward doesn't exist in UI.** Onboarding step points at a missing surface. L7, L4.
  `packages/web/src/components/onboarding/DailyNudge.tsx`

- [ ] WEB-UIUX-1051. **[MINOR] Refund permission strings (`refunds.create`, `refunds.approve`, `invoices.credit_note`) never referenced in client.** `grep "refunds.create\|refunds.approve\|invoices.credit_note" packages/web/src` → empty. Permission-aware buttons (hide Credit Note if no `invoices.credit_note`) not implemented; cashier-tier users can click Credit Note then get 403 toast instead of having the button hidden. L8.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`

- [ ] WEB-UIUX-1052. **[NIT] `creditNoteForm` typed `reason: RefundReasonCode | null` but backend receives composed `reason: string` + `code: RefundReasonCode` — local state name "reason" actually holds the *code*.** Variable name lies about what it stores. L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:46-50`

- [ ] WEB-UIUX-1053. **[NIT] Invoice list page status filter unclear — does it surface `credit_note` status invoices? When filter is empty, mixed regular + credit-note invoices appear in list with negative totals. No "Hide credit notes" toggle.** L9.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx`

- [ ] WEB-UIUX-1054. **[NIT] Credit Note modal title "Create Credit Note" — better: "Issue Credit Note" or "Refund / Credit Note" to align operator mental model with the dual purpose (it both refunds money and reduces balance).** L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:748`

- [ ] WEB-UIUX-1055. **[NIT] Cancel button label "Cancel" is generic — when Cancel-on-modal could destroy 30s of typing, "Discard changes" or "Close without saving" is clearer.** Cross-flow finding (applies to most modals on this page). L7.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:792-794`

### Web UI/UX Audit — Pass 14 (2026-05-05, flow walk: Cancel Subscription — list, profile, server gaps)

Walked end-to-end: admin navigates to membership list → clicks Cancel on a paying subscriber → also same flow from CustomerDetailPage → server processes cancel → admin tries to view cancelled history. Cross-checked `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx`, `packages/web/src/pages/customers/CustomerDetailPage.tsx:846-1093`, `packages/server/src/routes/membership.routes.ts`, `packages/web/src/components/layout/Sidebar.tsx`, `packages/web/src/api/endpoints.ts:1289-1325`.

#### Blocker — Discoverability, label/destination, recovery

- [ ] WEB-UIUX-1056. **[BLOCKER] Sidebar has zero Memberships/Subscriptions entry.** `grep -i "subscrip\|members\|crown\|/billing" Sidebar.tsx` → empty. Discoverable only via Cmd+K palette (`CommandPalette.tsx:72`) or direct URL `/subscriptions`. Admin without docs cannot find recurring-revenue page. Same blocker pattern as gift cards (WEB-UIUX-986). L8, L1, L4.
  `packages/web/src/components/layout/Sidebar.tsx`
  <!-- meta: fix=add-Memberships-link-under-Customers-section+Crown-icon+route=/subscriptions -->

- [ ] WEB-UIUX-1057. **[BLOCKER] Duplicate `POST /:id/run-billing` route registered twice in same file.** First definition `membership.routes.ts:317-402`, second `:452-553`. Express routes match in registration order so the second handler is dead code — never executes — but reads identical at audit/grep time (false sense of two paths). Logic is also drift-prone: first uses `setMonth(getMonth()+1)` from `now()`, second uses `setMonth(getMonth()+1)` from `current_period_end` (correct cycle continuity). Production runs the WRONG one. Past_due renewal advances period from today instead of from missed-cycle end → admin loses one whole missed month of dunning. L2, L4.
  `packages/server/src/routes/membership.routes.ts:317-402,452-553`
  <!-- meta: fix=delete-first-handler-block-317to402+keep-second-which-uses-period_end-anchor+verify-no-other-callers -->

- [ ] WEB-UIUX-1058. **[BLOCKER] Customer-profile Cancel button fires WITHOUT confirm modal.** `cancelMut.mutate()` wired directly to `onClick` (`CustomerDetailPage.tsx:999`). Single mis-click on Joe's profile cancels his $50/mo Gold membership; UI gives only a "Membership cancelled" success toast — no undo, no period-end option, no refund prompt. List page has confirm (`SubscriptionsListPage.tsx:158`); profile does not — same destructive action, two different guard rails. L8, L2, L7. Industry baseline (Stripe Dashboard, Recurly, Chargebee) all require typed confirm or two-step on cancel.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:998-1005`
  <!-- meta: fix=wrap-cancelMut-in-confirm-from-confirmStore+danger:true+match-list-page-pattern -->

- [ ] WEB-UIUX-1059. **[BLOCKER] Cancel hardcodes `immediate: true` everywhere in UI; server's `cancel_at_period_end` path unreachable.** `SubscriptionsListPage.tsx:114` and `CustomerDetailPage.tsx:905` both pass `{ immediate: true }`. Server `membership.routes.ts:229-235` supports both modes — column `cancel_at_period_end` exists, list-page row even renders "Cancels {date}" (`SubscriptionsListPage.tsx:245-249`) for that state — but no UI surface ever sets it. Customer who cancels mid-cycle loses paid remaining days; refunds aren't auto-issued either. Stripe/Recurly default = end-of-period; immediate is the override. We've inverted the safer default. L2, L1, L4.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:113-124`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:904-911`
  <!-- meta: fix=replace-confirm-with-modal-radio[end-of-period(default)|cancel-now]+pass-immediate-from-radio -->

- [ ] WEB-UIUX-1060. **[BLOCKER] Cancelled subscriptions vanish from list — no history view.** `GET /membership/subscriptions` query filters `cs.status IN ('active','past_due','paused')` (`membership.routes.ts:283`). Once cancelled, row drops from `SubscriptionsListPage`. Admin can't answer "Was Joe ever a Gold member? When did he leave?" Cannot re-activate. Cannot view past-payment history because page is the only entry to `/payments` data. Same defect on customer profile: `getCustomerMembership` filters `IN ('active','past_due')` (`membership.routes.ts:138`) so cancelled membership disappears from CRM card too. L4, L8, L9.
  `packages/server/src/routes/membership.routes.ts:138,283`
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:208-292`
  <!-- meta: fix=add-status-tab-filter[active|paused|past_due|cancelled]+show-cancelled-greyed-with-Reactivate-button+keep-history-LEFT-JOIN-not-INNER -->

#### Major — Truthfulness, hierarchy, feedback, recovery

- [ ] WEB-UIUX-1061. **[MAJOR] `RunBillingButton` (top-right header) is a decoy.** Click → toast "Billing cron runs nightly automatically. Use server console to trigger manually." (`SubscriptionsListPage.tsx:88`). But per-row `Bill now` button DOES trigger billing via `POST /:id/run-billing`. So the most prominent admin button literally tells admin a working feature is unavailable, while the real button hides at row level. Misleading at L2 (label promises action that fires only an info toast), confusing at L1 (wrong primary action elevated). Either remove the header button or wire it to bulk-bill all due subs.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:81-96`
  <!-- meta: fix=remove-header-button-OR-wire-to-bulk-runBilling-for-all-status='past_due'-rows-with-confirm -->

- [ ] WEB-UIUX-1062. **[MAJOR] Cancel button rendered to non-admin clerks; server returns 403, UI shows opaque toast.** `SubscriptionsListPage.tsx:275-284` has zero role gate. `Bill now` is wrapped in `<AdminOnly>` (line 261) — Cancel is not. Clerk clicks Cancel → confirm modal → confirm → server 403 → onError fires generic `'Failed to cancel subscription'` (`:121`). No mention of role required. Even worse, `formatApiError(err)` is imported and used inside the *unreachable* try/catch around `confirm()` (`:166`) — never reached because `confirm()` resolves, doesn't reject. Real error path drops the server's specific message. L7, L2.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:120-122,155-168,275-284`
  <!-- meta: fix=wrap-Cancel-button-in-AdminOnly+replace-onError-toast-with-formatApiError(err) -->

- [ ] WEB-UIUX-1063. **[MAJOR] Header label "Memberships" but route+filename "subscriptions"; CommandPalette aliases both.** `SubscriptionsListPage.tsx:180` reads "Memberships". Route `/subscriptions` (`App.tsx:540`). CommandPalette entry `display: 'Subscriptions'` with aliases `['memberships','recurring']` (`CommandPalette.tsx:72`). Three names for one feature. Customer-profile card uses third term "Membership" (singular). Support tickets ambiguous; new admins searching for the wrong word miss it. Pick one (industry: Stripe → Subscriptions; Shopify/Recharge → Subscriptions; Squarespace/Wix → Memberships when consumer-facing). For repair-shop B2C this is consumer-facing → Memberships, then rename URL/file/component. L2.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:180`
  `packages/web/src/App.tsx:540`
  <!-- meta: fix=rename-route-to-/memberships+keep-/subscriptions-as-301-redirect+rename-file+update-CommandPalette-display -->

- [ ] WEB-UIUX-1064. **[MAJOR] Empty-state CTA points to wrong destination.** Page text: `"Enroll customers from the Memberships settings tab."` (`SubscriptionsListPage.tsx:204`). But to enroll, admin must navigate to a Customer's profile → MembershipCard → Enroll button (`CustomerDetailPage.tsx:1037`). Settings tab (`MembershipSettings.tsx`) configures *tiers*, not enrollment. Brand-new admin reads the empty state, clicks through to Settings, finds nothing to enroll, dead-ends. L1, L3, L8.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:199-206`
  <!-- meta: fix=change-CTA-to-link-to-/customers-with-text="Open-a-customer-profile-and-tap-Enroll-in-Membership"-also-add-Configure-Tiers-secondary-link -->

- [ ] WEB-UIUX-1065. **[MAJOR] No Pause/Resume on list page; admin must click into each customer.** Server `POST /:id/pause` and `/:id/resume` exist (`membership.routes.ts:241-258`). Customer-profile MembershipCard exposes both (`CustomerDetailPage.tsx:990-1017`). List page exposes only Cancel + Bill now. Admin processing 50 subs for a snowstorm closure must navigate to each profile individually. Inconsistent affordance, lost bulk recovery. L1, L4, L8.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:257-286`
  <!-- meta: fix=add-Pause/Resume-buttons-to-row-action-cell+row-level-state+optional-bulk-pause-checkbox-selection -->

- [ ] WEB-UIUX-1066. **[MAJOR] Pause endpoint accepts `reason` but UI never sends one.** Server: `req.body.reason || null` written to `pause_reason` column (`membership.routes.ts:246-247`). UI: `pauseMut.mutate()` with no payload (`CustomerDetailPage.tsx:914`, `:991`). Column always NULL. List page even reads `sub.pause_reason` shape (line 33) but renders nothing. Lost telemetry for "why paused" → no win-back categorisation. L1, L4.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:913-920,990-997`
  <!-- meta: fix=replace-pauseMut.mutate()-with-prompt(reason)-or-modal-with-preset-reasons[customer-request|payment-fail|seasonal|other]+pass-as-body -->

- [ ] WEB-UIUX-1067. **[MAJOR] Cancel reason not collected at all.** Industry standard (Stripe, Recurly, Chargebee, ChartMogul) prompts `cancellation_reason` on cancel for retention analytics + win-back targeting. Server has no `cancellation_reason` column on `customer_subscriptions`; UI has no field; audit log has only `{ subscription_id, immediate }` (`membership.routes.ts:237`). Lost MRR-churn signal entirely. L1, L4.
  `packages/server/src/routes/membership.routes.ts:222-239`
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:155-168`
  <!-- meta: fix=add-cancellation_reason+cancellation_note-cols-via-migration+modal-radio[too-expensive|moved|switched|not-using|other]+include-in-audit -->

- [ ] WEB-UIUX-1068. **[MAJOR] Hard `$` currency prefix in two paths; bypasses tenant-currency formatter.** (1) Server payment-link description: `'$' + tier.monthly_price` via `description = "${tier.name} Membership - $${tier.monthly_price}/mo"` (`membership.routes.ts:422`). (2) Customer-profile MembershipCard price: `${memberData.monthly_price.toFixed(2)}/mo` (`CustomerDetailPage.tsx:972`) — adjacent `@audit-cents WEB-FF-019` comment already flags the cents-migration risk but the currency-symbol bug is a separate, current bug. Brazilian/EU tenant sees BRL/EUR everywhere except hosted-payment link and own profile card → "is this $50 USD or BRL50?" L2, L7.
  `packages/server/src/routes/membership.routes.ts:422`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:971-973`
  <!-- meta: fix=server-pass-tenant-currency-into-description-template+web-call-formatCurrency()-from-utils/format -->

- [ ] WEB-UIUX-1069. **[MAJOR] Past-due subs share Cancel button affordance with active subs; no "Retry payment" CTA.** Past-due is the highest-leverage retention state — Stripe surfaces "Retry now" and "Send invoice" as the *primary* actions. Our list shows Bill now (admin only, behind token) + Cancel — Cancel is destructive yet visually equivalent to billing. No alert badge on the row, no "X days overdue", no email-customer button. L1, L5, L9.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:240-286`
  <!-- meta: fix=for-status='past_due'-promote-Retry-payment-as-primary+add-days-overdue-pill+SendDunningEmail-secondary-action -->

- [ ] WEB-UIUX-1070. **[MAJOR] `runBillingMut` invalidates only `['subscriptions']`; profile-page query stale.** List page invalidates `queryKey: ['subscriptions']` (`SubscriptionsListPage.tsx:131`). Customer-profile MembershipCard uses `['membership','customer',customerId]` (`CustomerDetailPage.tsx:861`). Admin opens both tabs → bills from list → profile shows old `current_period_end`. Same defect on cancel: `cancelMutation` invalidates `['subscriptions']` only (`:116`). MembershipCard `cancelMut` invalidates only `['membership','customer',customerId]` (`:907`) — list page in another tab keeps stale "active" row. Cross-surface invalidation missing. L7.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:115-124,128-139`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:894-929`
  <!-- meta: fix=after-each-mutation-invalidate-both-['subscriptions']-and-['membership','customer',customerId]+also-['membership','tiers']-after-tier-CRUD -->

- [ ] WEB-UIUX-1071. **[MAJOR] No "Reactivate" path for cancelled membership; re-enrol creates new row + fragmented history.** When `customer_subscriptions.status='cancelled'`, `getCustomerMembership` filter `IN ('active','past_due')` returns null (`membership.routes.ts:138`), MembershipCard branches to no-membership state (`CustomerDetailPage.tsx:1024`), admin clicks Enroll → `POST /membership/subscribe` → INSERT new row. Customer's churn-and-return creates two rows; LTV reports must `GROUP BY customer_id`; payment history splits across `subscription_id`s. Industry pattern (Stripe `customer.subscriptions.update({pause_collection:null})` or `unpause`) reactivates the same record. L4, L9.
  `packages/server/src/routes/membership.routes.ts:138,222-239`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:935-1022,1024-1092`
  <!-- meta: fix=add-POST-/:id/reactivate-route-flips-status-back-to-active+resets-cancel_at_period_end+UI-Reactivate-button-when-most-recent-sub-is-cancelled -->

#### Minor — feedback specificity, sub-state polish

- [ ] WEB-UIUX-1072. **[MINOR] Cancel success toast is identical for immediate vs end-of-period cancel.** `toast.success('Subscription cancelled')` (`SubscriptionsListPage.tsx:117`). Once WEB-UIUX-1059 ships the radio choice, the same string lies for `immediate:false` (which doesn't cancel — it schedules cancel). L7. Trivial fix when the choice modal lands: read response `data.immediate` and switch text.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:117`
  <!-- meta: fix=after-WEB-UIUX-1059-toast='Cancelled-immediately'-vs-'Will-cancel-on-{date}' -->

- [ ] WEB-UIUX-1073. **[MINOR] No payment-history view from list page despite server endpoint existing.** `GET /membership/:id/payments` exists (`membership.routes.ts:262-270`), `endpoints.ts` has no wrapper. List page row has no expand/drill-down. To answer "did this card decline last month?" admin must SSH to the DB. L4, L8.
  `packages/server/src/routes/membership.routes.ts:262-270`
  `packages/web/src/api/endpoints.ts:1289-1325`
  <!-- meta: fix=add-membershipApi.getPayments(id)-wrapper+row-expand-shows-last-3-payments+full-history-modal -->

- [ ] WEB-UIUX-1074. **[MINOR] Subs without `blockchyp_token` give zero recovery affordance.** `Bill now` only renders when `sub.blockchyp_token` truthy (`SubscriptionsListPage.tsx:260`). For a sub created via signup-flow without card, admin sees no hint to "Add card" or "Send payment link". Server has `POST /membership/payment-link` for exactly this case but no UI surface here. L8, L9.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:259-274`
  <!-- meta: fix=when-no-blockchyp_token-render-secondary-button-Send-payment-link-calling-membershipApi.createPaymentLink+toast-with-copyable-URL -->

- [ ] WEB-UIUX-1075. **[MINOR] Subscription list missing primary "Add subscription / Enroll customer" action.** Page is the recurring-revenue dashboard yet has no entry-point to enrolment workflow — admin must remember "go to a customer profile". Industry baseline: Stripe Dashboard → Subscriptions → Create subscription opens customer-picker first. L1, L8.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:175-189`
  <!-- meta: fix=add-primary-button-New-subscription-opens-modal-CustomerPicker+TierPicker+CardOnFile-or-PaymentLink -->

- [ ] WEB-UIUX-1076. **[MINOR] `_data, id` unused param in `runBillingMut.onSuccess`** (`SubscriptionsListPage.tsx:130`). Cosmetic — `id` shadowed and unused. L not applicable; cleanup.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:130-134`
  <!-- meta: fix=destructure-only-the-args-actually-used -->

#### Nit — visual contrast

- [ ] WEB-UIUX-1077. **[NIT] Empty-state Crown icon `text-surface-300` and cancelled-status badge `bg-surface-100 text-surface-500` fail WCAG AA contrast on white.** `SubscriptionsListPage.tsx:201,47`. Same pattern flagged in earlier passes for empty states; consistency only. L not strictly usability-blocking.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:47,201`
  <!-- meta: fix=upgrade-to-text-surface-400-icon+text-surface-600-badge-text -->

### Web UI/UX Audit — Pass 15 (2026-05-05, flow walk: QC Sign-Off — bench QC modal, server gates, admin surfaces)

Walked end-to-end: tech finishes repair → opens TicketDetail → clicks green "QC sign-off" button → fills checklist + photo + signature + signs → ticket status moves on. Cross-checked `packages/web/src/components/tickets/QcSignOffModal.tsx`, `packages/web/src/pages/tickets/TicketDetailPage.tsx:32,390,591-597,649-658`, `packages/server/src/routes/bench.routes.ts:255-275,596-910`, `packages/server/src/db/migrations/088_bench_timer_qc_defects.sql`, `packages/server/src/services/ticketStatus.ts`, `packages/web/src/api/endpoints.ts:1355-1375`, `packages/web/src/pages/settings/` (no Bench/QC page exists).

#### Blocker — broken contract, unwired status, missing admin surfaces

- [ ] WEB-UIUX-1078. **[BLOCKER] Migration 088 promises `qc_required=true` blocks PATCH `status='complete'` until a `qc_sign_offs` row exists — no server enforcement exists.** `088_bench_timer_qc_defects.sql:22-23` states the gate; `tickets.routes.ts` has zero references to `qc_required` or `qc_sign_offs`. Admin who flips the flag (DB-only, see WEB-UIUX-1079) gets a false sense of compliance — every tech still completes tickets without sign-off. Documentation lies. L2, L8.
  `packages/server/src/db/migrations/088_bench_timer_qc_defects.sql:18-26`
  `packages/server/src/routes/tickets.routes.ts`
  <!-- meta: fix=in-tickets-PATCH-status-handler-when-qc_required==='true'-AND-target-status-is-terminal('Repaired'|'Repaired-Pending QC'|'Payment Received & Picked Up')-SELECT-1-FROM-qc_sign_offs-WHERE-ticket_id=?-LIMIT-1+throw-409-if-missing -->

- [ ] WEB-UIUX-1079. **[BLOCKER] No admin UI to flip `qc_required` (or `bench_timer_enabled`, `bench_labor_rate_cents`, `defect_alert_threshold_30d`).** `packages/web/src/pages/settings/` has no Bench / QC page. Setting only mutable via direct `UPDATE store_config SET value='true' WHERE key='qc_required'`. Admin onboarding mentions QC; admin can never enable it. L4, L8.
  `packages/web/src/pages/settings/SettingsPage.tsx`
  `packages/server/src/routes/bench.routes.ts:255-275`
  <!-- meta: fix=add-pages/settings/BenchQcSettings.tsx+settings-tab-Bench/QC+toggles-for-qc_required+bench_timer_enabled+number-input-for-labor-rate -->

- [ ] WEB-UIUX-1080. **[BLOCKER] No admin UI for QC checklist CRUD — and the modal's empty-state copy points to that nonexistent page.** Server has `POST/PUT/DELETE /bench/qc-checklist` admin-gated routes (`bench.routes.ts:614-700`) with no client wrapper besides `checklist()` (read). Empty-state in modal: `"Ask an admin to add some under Settings → Bench / QC."` (`QcSignOffModal.tsx:218`) — that path doesn't exist. Tech reads guidance, admin follows guidance, both dead-end. L1, L2, L4, L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:217-219`
  `packages/web/src/api/endpoints.ts:1366-1374`
  <!-- meta: fix=add-pages/settings/QcChecklistPage.tsx+row-CRUD+device-category-filter+drag-sort_order+wire-endpoints.bench.qc.{create,update,delete}+update-empty-state-link-to-real-route -->

- [ ] WEB-UIUX-1081. **[BLOCKER] `GET /bench/qc/status/:ticketId` has zero web callers — TicketDetail never reflects whether the ticket has been QC-signed.** `grep "qc/status\|qcStatus"` in `packages/web/src` returns only the endpoint definition. Reviewer/manager scanning a ticket cannot tell at-a-glance "QC done by Joe at 14:32"; tech reopening modal can't see prior sign-off. Combined with no `UNIQUE(ticket_id)` on `qc_sign_offs` (`088_bench_timer_qc_defects.sql:71-82`), every modal submit creates a fresh row. Tickets accumulate duplicate sign-off rows; audit log doubles. L1, L4, L7, L8.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:591-597`
  `packages/server/src/routes/bench.routes.ts:703-753`
  <!-- meta: fix=add-useQuery(['qc-status',ticketId])-in-TicketDetail+badge-"QC signed by {name} at {time}"+disable-button-if-already-signed-or-show-"Re-sign-(needs-manager)"+add-UNIQUE(ticket_id)-via-migration-OR-explicit-INSERT-OR-REPLACE-with-confirm -->

- [ ] WEB-UIUX-1082. **[BLOCKER] Server's specific 400 messages never reach the operator — `onError` toast displays axios's generic `err.message`.** `signMut.onError` at `QcSignOffModal.tsx:170-173` does `err instanceof Error ? err.message : 'Sign-off failed'`. Axios errors expose server payload at `err.response?.data?.message`, not `err.message` (which is `"Request failed with status code 400"`). Server messages like `"QC failed: 3 checklist item(s) not passed"`, `"working_photo image is required"`, `"Storage limit (500 MB) reached. Upgrade to Pro"` all stripped. Tech who hits the 403 storage-quota path sees "Request failed with status code 403" instead of the upgrade prompt. L7, L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:170-173`
  <!-- meta: fix=import-formatApiError-from-utils+toast.error(formatApiError(err))+also-special-case-403{upgrade_required:true}-to-show-upgrade-CTA -->

#### Major — fail-path missing, role gates, identity, hierarchy, visual context

- [ ] WEB-UIUX-1083. **[MAJOR] No "QC fail" path in the modal.** Modal accepts only the all-green outcome (`canSubmit = allPassed && photo && signature`). If during QC the tech finds a fresh defect (camera misaligned, port loose), they cannot record "fail with reason", route the ticket back to "In Progress", or generate a fail report. They must abandon modal → manually change ticket status → write a note → start over. Migration 088 even seeds `defect_threshold` infrastructure for this exact case but UI doesn't link the two. L1, L4, L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:136-174`
  <!-- meta: fix=add-row-level-pass/fail-radio+if-any-fail-replace-CTA-with-Mark-failed-routes-ticket-to-In-Progress-and-creates-defect-report-with-reason -->

- [ ] WEB-UIUX-1084. **[MAJOR] `POST /bench/qc/sign-off` has no role gate — any authenticated user can sign as the tech.** `bench.routes.ts:756-772` checks only `req.user?.id`. Cashier role, viewer role, even a sandboxed customer-portal user (if added) can submit a sign-off and have `tech_user_id` recorded as theirs. Compare admin-only routes for checklist CRUD (`:618,650,693`). Industry baseline: QC sign-off requires explicit `qc.sign` permission gated to tech/manager. L8.
  `packages/server/src/routes/bench.routes.ts:756-774`
  <!-- meta: fix=add-requireRole(['tech','manager','admin'])-or-permission(qc.sign)-middleware-before-handler -->

- [ ] WEB-UIUX-1085. **[MAJOR] Signature canvas content not bound to the signing user's identity — `tech_user_id = req.user.id` regardless of squiggle drawn.** No PIN re-auth, no name typed, no biometric, no hash of the captured image vs. a baseline signature on file. A manager who hands their tablet to an apprentice gets "signed by manager" stored on a record actually signed by apprentice. Repudiation risk in warranty / dispute scenarios. L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:289-307`
  `packages/server/src/routes/bench.routes.ts:885-902`
  <!-- meta: fix=add-required-typed-name-field+optional-PIN-re-auth-modal-before-canvas+server-stores-typed_name+pin_verified_at-alongside-image -->

- [ ] WEB-UIUX-1086. **[MAJOR] Successful sign-off does not advance ticket status — sign-off is decorative.** `signMut.onSuccess` (`QcSignOffModal.tsx:163-169`) toasts + invalidates queries; no `ticketsApi.updateStatus(ticketId, 'Repaired')` call. Tech still has to manually move the status pill. State machine in `ticketStatus.ts:99-108` lists `'Repaired - Pending QC'` as a valid transition out of `'Repaired'` (backwards) but no automatic forward path triggered by a successful sign-off. L1, L4, L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:163-169`
  <!-- meta: fix=after-sign-off-PATCH-ticket-status-to-Repaired-OR-Pending-QC-handoff-config-driven+offer-radio-Move-to-Repaired-now-vs-Stay-on-current-status -->

- [ ] WEB-UIUX-1087. **[MAJOR] Backdrop click silently closes modal — destroys checklist + photo + signature without confirm.** `QcSignOffModal.tsx:184-187` wires `onClick={onClose}` on the bg div. Tech who has ticked 9 items, attached photo, drawn signature, and accidentally clicks outside the centered card → all gone, no toast, no recovery. Same anti-pattern flagged elsewhere (WEB-UIUX-985, 1046); especially severe here because signature-drawing is hard-to-redo. L8, L16.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:182-194`
  <!-- meta: fix=guard-backdrop-onClick-with-isDirty-check+confirm-modal-or-just-no-op-if-anything-staged -->

- [ ] WEB-UIUX-1088. **[MAJOR] No "Tickets pending QC" worklist anywhere.** Tickets list, dashboard, sidebar all silent on QC backlog. Tech has to remember which tickets they've finished but not yet signed; manager has no view into "X tickets sat on Repaired without sign-off > 24h". Compare commission queue, dunning queue — both surface unworked items. L1, L4, L8.
  `packages/web/src/pages/tickets/TicketsListPage.tsx`
  `packages/web/src/components/layout/Sidebar.tsx`
  <!-- meta: fix=add-page-/qc/queue-listing-tickets-status='Repaired-Pending-QC'-OR-status='Repaired'-AND-no-qc_sign_off-LEFT-JOIN-qc_sign_offs-IS-NULL+badge-on-Sidebar-Tickets -->

- [ ] WEB-UIUX-1089. **[MAJOR] Signed sign-off is not printable / emailable / PDF-exportable — customer never receives a copy.** Migration 088 stores signature + photo + checklist results, but no `/qc/sign-off/:id/pdf` route, no print template, no `Email customer` button on TicketDetail post-sign. Customer who was promised "we'll send you the QC certificate" gets nothing. L1, L4, L8.
  `packages/server/src/routes/bench.routes.ts:703-910`
  <!-- meta: fix=add-GET-/qc/sign-off/:id/pdf-uses-existing-pdf-pipeline+after-success-toast-render-button-Send-to-customer-emails-PDF -->

- [ ] WEB-UIUX-1090. **[MAJOR] Photo `accept` excludes HEIC/HEIF — iPhone Safari users blocked from camera roll.** `QcSignOffModal.tsx:255` `accept="image/jpeg,image/png,image/webp"`. iOS default capture is HEIC. Tech opens picker, sees photos greyed out, has no in-app guidance to convert. `ALLOWED_MIMES` server-side likely also rejects HEIC (verify in `bench.routes.ts:130-132`). L1, L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:252-258`
  <!-- meta: fix=add-image/heic+image/heif-to-accept+verify-server-ALLOWED_MIMES-or-add-client-side-heic-to-jpeg-conversion-via-heic2any -->

- [ ] WEB-UIUX-1091. **[MAJOR] No `capture="environment"` on photo input — operator gets file picker, not the live rear camera.** `QcSignOffModal.tsx:252-258`. Tech finishing a repair on tablet expects "tap → camera opens"; instead it opens recently-used files. Real flow needs the rear camera with one-tap shutter. L1, L4.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:252-258`
  <!-- meta: fix=add-capture="environment"-attr+keep-fallback-to-picker-when-no-camera -->

- [ ] WEB-UIUX-1092. **[MAJOR] Single working-photo only; no before/after, no defect-marker overlay, no multi-photo.** Repair shops universally document "before" + "after" — small claims / warranty disputes hinge on the pair. `working_photo_path` column is scalar (`088_bench_timer_qc_defects.sql:79`); UI has one slot. Operator who wants to document multiple angles or attach a video can't. L1, L4.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:248-285`
  <!-- meta: fix=schema-add-qc_sign_off_photos-table-(sign_off_id,path,kind:before|after|other)+UI-multi-upload+server-multipart-array -->

- [ ] WEB-UIUX-1093. **[MAJOR] `GET /qc/status` strips `tech_signature_path` + `working_photo_path` for non-admin/non-manager (`bench.routes.ts:738-740`) — tech who signed cannot review their own signature later.** Self-review is the most common dispute case ("did I sign that?"). Privilege filter denies the signing party access to their own act. L1, L8.
  `packages/server/src/routes/bench.routes.ts:728-741`
  <!-- meta: fix=loosen-filter-to-isPrivileged-OR-tech_user_id===req.user.id -->

- [ ] WEB-UIUX-1094. **[MAJOR] `setPassedMap({})` reset keyed on `[items.length]` — admin edits checklist mid-modal-session and the local map stays mapped to stale ids.** `QcSignOffModal.tsx:55-59`. Admin renames or replaces "Speakers tested" → "Speakers + mic + dongle"; if the count is unchanged, modal still shows old labels with old `passedMap` keys, but server validates against new `id`s. Tech ticks UI, server returns "checklist items not passed" with mismatched ids; or worse, `passedMap` has phantom `true` for an id that no longer exists, server marks unrelated id as passed by coincidence. L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:54-59`
  <!-- meta: fix=key-reset-on-JSON.stringify(items.map(i=>i.id))+also-add-server-side-version-token-on-checklist-and-409-on-stale -->

- [ ] WEB-UIUX-1095. **[MAJOR] Canvas signature rendered at fixed 600×140 bitmap — blurry on retina iPad / iPhone.** `QcSignOffModal.tsx:292-300`. Canvas is CSS-scaled to container width; no `devicePixelRatio` upscale. Stored PNG always 600×140; on a 12.9" iPad the rendered preview is fuzzy and the legal-grade signature artifact is low-res. Industry tooling (DocuSign, HelloSign) auto-detects DPR and upscales. L1.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:289-307`
  <!-- meta: fix=in-useEffect-set-canvas.width=cssWidth*dpr+canvas.height=cssHeight*dpr+ctx.scale(dpr,dpr)+CSS-keeps-original-display-size -->

- [ ] WEB-UIUX-1096. **[MAJOR] Modal header lacks ticket id, customer name, device.** `QcSignOffModal.tsx:194-210` shows only "QC Sign-Off" + close X. Tech with two browser tabs (one on T-1234, another on T-1240) can open modal in wrong tab, sign, hit submit, attribute QC to wrong job. No defensive context to catch the mistake before it persists. L7, L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:194-210`
  <!-- meta: fix=fetch-ticketsApi.get(ticketId)+render-subtitle="T-{order_id} · {customer_name} · {device_name}" -->

- [ ] WEB-UIUX-1097. **[MAJOR] `qc-status` invalidate key (`QcSignOffModal.tsx:165`) is referenced by no `useQuery` anywhere — dead invalidation.** Combined with WEB-UIUX-1081 (no status query exists), the cache invalidation is wishful. When the status query is wired, the invalidation works; until then, the line is documentation pretending to be code. L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:163-167`
  <!-- meta: fix=track-with-WEB-UIUX-1081-when-status-query-lands -->

#### Minor — copy, hierarchy, edge cases

- [ ] WEB-UIUX-1098. **[MINOR] "QC sign-off" green button on TicketDetail always rendered, regardless of ticket status or `qc_required` flag.** `TicketDetailPage.tsx:590-597`. Tech can sign QC on a ticket still in `'Awaiting parts'` — bypasses any process intent. Should be hidden until status is `'Repaired'` / `'Repaired - Pending QC'`, or always visible but disabled with tooltip "Status must be Repaired". L1, L9.
  `packages/web/src/pages/tickets/TicketDetailPage.tsx:590-597`
  <!-- meta: fix=gate-button-on-isRepairableStatus(ticket.status)+optionally-hide-when-bench-config.qc_required==false -->

- [ ] WEB-UIUX-1099. **[MINOR] No client-side photo size guard.** `onPhotoChange` (`:128-134`) ingests file blindly. 30MB photo from a recent iPhone gets uploaded over a flaky shop wifi, fails midway, no UX. Server has `enforceUploadQuota` but operator sees a generic axios error. L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:128-134`
  <!-- meta: fix=if-file.size>10*1024*1024-toast.error+offer-client-side-resize-via-canvas -->

- [ ] WEB-UIUX-1100. **[MINOR] Checklist `<input type="checkbox">` rows have no `<label htmlFor>` association.** `QcSignOffModal.tsx:227-243` renders checkbox + adjacent span. Screen reader announces "checkbox, unchecked" without reading item name unless the span is wrapped in a label. Tap target is also smaller — only the box is clickable, not the row. Reach test on tablet: row is 100% width but tap on item text doesn't toggle. L4, L12.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:227-244`
  <!-- meta: fix=wrap-row-in-<label-className=cursor-pointer>+keep-checkbox-and-span-as-children -->

- [ ] WEB-UIUX-1101. **[MINOR] "Cancel" same visual weight as "Sign off" — both filled-equivalent buttons.** `QcSignOffModal.tsx:324-343`. Cancel destroys 30s+ of work; Sign off persists it. Cancel should be ghost/text-only; primary CTA should dominate. L9.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:324-343`

- [ ] WEB-UIUX-1102. **[MINOR] Notes placeholder "Any observations the customer should know about..." — but `qc_sign_offs.notes` is internal (no email path, no print path per WEB-UIUX-1089).** Tech writes a note thinking customer will see it; customer never does. Misleading copy. L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:319-321`
  <!-- meta: fix=change-placeholder-to-"Internal-notes-for-the-record"-or-actually-route-to-customer-email-when-WEB-UIUX-1089-lands -->

- [ ] WEB-UIUX-1103. **[MINOR] Empty-state has no recovery affordance.** When `items.length===0` (`QcSignOffModal.tsx:216-219`), banner says "Ask an admin..." (broken anyway per WEB-UIUX-1080) but no "Restore default checklist" button — and migration 088 *seeds* 9 default items. Admin who deleted them all is stuck. L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:216-220`

- [ ] WEB-UIUX-1104. **[MINOR] Esc closes modal silently with same destructive effect as backdrop click.** `QcSignOffModal.tsx:176-180`. Same pattern as WEB-UIUX-1087. L8.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:176-180`

- [ ] WEB-UIUX-1105. **[MINOR] No "view past sign-offs" history.** Re-sign overwrites visually (only latest queried per `LIMIT 1` at `:712`), but DB keeps all rows. No UI to enumerate. Manager investigating "which sign-off captured the working state" can't reach prior rows. L4.
  `packages/server/src/routes/bench.routes.ts:711-714`

- [ ] WEB-UIUX-1106. **[MINOR] "Notes" textarea has `maxLength={1000}` but no character counter.** `QcSignOffModal.tsx:317-321`. Tech typing detailed defect description silently truncated at 1000. L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:317-321`

- [ ] WEB-UIUX-1107. **[NIT] Title icon `CheckCircle2 text-primary-500` reads as "completed" — overloaded with the dashboard's "task complete" green check.** Status before action; user expects success ICON only post-sign. L9.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:200-201`

- [ ] WEB-UIUX-1108. **[NIT] Photo button label `"Capture / upload photo"` — slash awkward and verbose.** `QcSignOffModal.tsx:265`. Industry copy: "Take photo" or "Add photo". L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:264-266`

- [ ] WEB-UIUX-1109. **[NIT] "Working device photo" wording ambiguous — could mean photo OF the device working, or photo for use during work.** Cleaner: "Photo of working device". L7.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:249-251`

- [ ] WEB-UIUX-1110. **[NIT] `accept="image/webp"` accepted but webp not capturable from iOS Safari — slot likely useless on tablets.** Trim or document. L9.
  `packages/web/src/components/tickets/QcSignOffModal.tsx:255`

### Web UI/UX Audit — Pass 16 (2026-05-05, flow walk: Send Bulk SMS — preview, confirm, dispatch, feedback)

Walked end-to-end: admin opens Communications page → Messages view → clicks "Bulk" → BulkSmsModal opens → picks segment + template → Preview → Send to N → server two-step token verify → sequential dispatch → toast. Cross-checked `packages/web/src/pages/communications/components/BulkSmsModal.tsx`, `packages/web/src/pages/communications/CommunicationPage.tsx:1545-1563,2472`, `packages/server/src/routes/inbox.routes.ts:381-705` (preview + bulk-send), template select query path, segment consent filters, sms_retry_queue side effects.

#### Blocker — Feedback truthfulness, label vs body, recovery

- [ ] WEB-UIUX-1111. **[BLOCKER] Success toast renders "Enqueued undefined messages" — client reads field server no longer returns.** Client typed shape: `interface ConfirmResponse { enqueued: number; segment; confirmed: true }` (`BulkSmsModal.tsx:47-51`) and toast `Enqueued ${r.enqueued} messages` (`:92`). Server payload (`inbox.routes.ts:693-703`) returns `{ attempted, sent, failed, segment, template, confirmed: true }` — note the comment block at `:619-625` explicitly documents the migration FROM `enqueued` to `attempted/sent/failed` so admin sees truthful counts. Client never updated. Result: after blasting 1,200 customers admin sees `Enqueued undefined messages` and modal closes. Cannot tell 0 sent vs 1200 sent vs 1200 failed. Worst-case dispatch (provider down, all queued to `sms_retry_queue` with `status='failed'`) reads identical to a perfect 1200/1200 success. L7, L2.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:47-51,91-96`
  <!-- meta: fix=update-ConfirmResponse-to-{attempted,sent,failed,segment,template,confirmed}+toast=`Sent ${r.sent} of ${r.attempted}${r.failed?` (${r.failed} failed — see retry queue)`:''}`+keep-modal-open-when-failed>0 -->

- [ ] WEB-UIUX-1112. **[BLOCKER] Template selected by NAME only — body never previewed before blast.** `BulkSmsModal.tsx:171-186` renders `<select>` with `<option>{t.name}</option>` from `smsApi.templates()`. Picking "April Reminder" sends whatever the template body is RIGHT NOW. Common drift: marketing edits body to "Spring sale 50% off!" but leaves name as "April Reminder", admin clicks Send to 1,200, sends a sale blast they didn't intend. Twilio Console / Klaviyo / Attentive all render the resolved body BEFORE confirm. Compounds with 1111 — no truthful post-send signal either. L2, L6.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:167-186`
  <!-- meta: fix=on-templateId-change-set-tplPreview-from-templates.find(t=>t.id===id).content+render-160char-preview+character-count-vs-160-segment-cost -->

- [ ] WEB-UIUX-1113. **[BLOCKER] No recipient sample / no recipient list — pure blind dispatch.** Modal shows ONLY a count (`This will send to 1,200 recipients`, `:191-194`). Operator cannot inspect WHO. Server's `previewBulkSegment` already collects up to 500 phones (`inbox.routes.ts:420`), only the count is wired into the response. Industry baseline: Klaviyo/Attentive/Postscript show 5-10 sample recipients + opt to download CSV pre-send. For repair-shop SMS where one wrong segment = TCPA complaint, this is operator-protection minimum. L6, L8.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:188-196`
  `packages/server/src/routes/inbox.routes.ts:563-571`
  <!-- meta: fix=server-include-first-5-phones-in-preview-payload+client-render-list+optional-exclude-toggle -->

- [ ] WEB-UIUX-1114. **[BLOCKER] Backdrop click silently destroys preview token mid-confirm.** `BulkSmsModal.tsx:117` `onClick={onClose}` and Esc handler at `:100-107` both close without confirm. After Preview generates a 5-min HMAC token (server-bucket-sealed against the consented phone list, `inbox.routes.ts:556-562`), a stray click on dark backdrop nukes the token + count + selection. Reopening = re-preview = potentially different segment hash if a customer opted in/out in the gap. For an action labeled `Send to 1,200` with red destructive styling, accidental dismissal cost is steep. Same anti-pattern as WEB-UIUX-1104. L8.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:111-117,100-107`
  <!-- meta: fix=stage===preview-warn-before-onClose+confirm-or-no-op-on-backdrop+only-X-button-closes -->

#### Major — Hierarchy, label honesty, recovery, discoverability

- [ ] WEB-UIUX-1115. **[MAJOR] Segment hint copy lies about scope — opt-in / consent filter invisible to operator.** Modal hints (`BulkSmsModal.tsx:29-33`):
  - `all_customers` → "Every customer with a mobile number"
  - `recent_purchases` → "Customers who bought in last 30 days"
  - `open_tickets` → "Customers with tickets in progress"
  Server filters all three by `COALESCE(sms_opt_in,0)=1 AND COALESCE(sms_consent_marketing,0)=1` (`inbox.routes.ts:397,404,415`). Operator with 4,000 customers sees `Send to 1,200` and assumes 2,800 lacked phone numbers — actually most of them opted out of marketing. No copy explains it. Risk: admin assumes coverage they don't have, sends fewer reminders than intended. L2.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:29-33`
  <!-- meta: fix=append-"(opted-in-for-marketing)"-to-each-hint+modal-banner-explaining-consent-filter+show-excluded-count-from-server -->

- [ ] WEB-UIUX-1116. **[MAJOR] Confirm button red `bg-red-600` (destructive color) for an additive marketing send.** `BulkSmsModal.tsx:218`. Page elsewhere uses red for void/delete/cancel-subscription (per WEB-UIUX-1062 cluster). High-blast-radius doesn't equal destructive — sending a wanted reminder to 1,200 opt-ins is the OPPOSITE of destruction. Color signals hesitation when click should be confident. Stripe/Klaviyo/Attentive all use brand-color or accent for primary send + reserve red for destructive. Pair with "Send to N" label that's already specific → drop red, keep `bg-primary-600`. L5.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:215-222`
  <!-- meta: fix=swap-bg-red-600/hover:bg-red-700-to-bg-primary-600/hover:bg-primary-700+keep-Send-icon -->

- [ ] WEB-UIUX-1117. **[MAJOR] No in-flight progress + no abort during ~10–30s dispatch.** Server loops `for (const phone of preview.phones)` SYNCHRONOUSLY awaiting each `sendSmsTenant` (`inbox.routes.ts:640-676`). At provider-typical 100-200ms per SMS, 500 recipients = 50-100s blocking response. Client only renders `Sending…` on the button (`:221`); modal frozen. No cancel button, no progress bar, no streamed counter. If admin realizes 5s in "wrong template" — too late, no abort path. Per-message inserts to `sms_retry_queue` mean partial failures persist mid-loop with no surface. L7, L8. (Note: server-side fix needed; client UX still has place for streaming via SSE / polling on a job id.)
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:215-222`
  `packages/server/src/routes/inbox.routes.ts:637-704`
  <!-- meta: fix=convert-to-job-table+return-job_id-immediately+client-poll-/inbox/bulk-send/:job_id+show-progress-bar+abort-button-flips-job-state -->

- [ ] WEB-UIUX-1118. **[MAJOR] Trigger button labeled "Bulk" with no medium-channel hint; only icon + tooltip carry the meaning.** `CommunicationPage.tsx:1547-1554`: `text-xs`, tertiary border, content `<Users icon /> Bulk`. `title="Bulk SMS"` is hover-only, fails on touch + screen readers without focus. Admin scanning page for "send marketing text" reads "Bulk", thinks bulk-archive or bulk-tag. Compare neighboring "+ New" (line 1555-1561) — primary blue, larger, unambiguous. Recurring SaaS pattern (Front, Intercom): `Bulk SMS` or `Send blast` spelled fully. L1, L6.
  `packages/web/src/pages/communications/CommunicationPage.tsx:1547-1554`
  <!-- meta: fix=label="Bulk-SMS"+aria-label="Send-bulk-SMS"+remove-title-only-affordance -->

- [ ] WEB-UIUX-1119. **[MAJOR] Trigger renders only when `mainView==='messages'` — invisible from Email tab and from Marketing/Campaigns.** `CommunicationPage.tsx:1545`. Admin who lands on Email view to send blast can't find SMS bulk; must toggle tabs. Marketing > Campaigns page (`marketing/CampaignsPage.tsx`) is the obvious home for blast sends — has zero entry to BulkSmsModal. Two parallel "send to many people" surfaces (Campaigns + Bulk SMS) that don't link to each other. Same fragmentation pattern as Pass 13 refunds. L4, L8.
  `packages/web/src/pages/communications/CommunicationPage.tsx:1545-1563`
  `packages/web/src/pages/marketing/CampaignsPage.tsx`
  <!-- meta: fix=move-Bulk-SMS-button-out-of-mainView-conditional+add-quick-action-tile-on-CampaignsPage+OR-collapse-bulk-into-Campaigns-as-an-instant-campaign-type -->

- [ ] WEB-UIUX-1120. **[MAJOR] Modal hides existing rate-limit signal — admin learns "1 send per hour" only on second attempt.** Server enforces `INBOX_BULK_SEND_MAX_PER_HOUR` (`inbox.routes.ts:583-589`) and replies 429-shaped on overshoot via `guardInboxRate`. UI never displays remaining quota or last-send timestamp. Admin clicks Send → success → 5min later realizes the segment was wrong → tries again → opaque "Bulk send failed" toast (`BulkSmsModal.tsx:97`) with no countdown. Industry baseline (Postscript, Attentive): show "Next bulk available in 47min" inline. L7, L8.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:97`
  `packages/server/src/routes/inbox.routes.ts:582-589`
  <!-- meta: fix=server-include-rate-limit-headers-X-RateLimit-Remaining/Reset+client-render-cooldown-pill-when-remaining=0+toast-error-include-reset-time -->

#### Minor — Polish, copy, defaults

- [ ] WEB-UIUX-1121. **[MINOR] Default segment is `open_tickets` — chosen as first array element, not by intent.** `BulkSmsModal.tsx:54` `useState<Segment>('open_tickets')`. Open-tickets-blast is the LEAST common bulk send (status updates are usually transactional 1:1, not blast). Most-frequent ones (recent_purchases for review nudges, all_customers for promo) are deeper in list. L1.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:54`
  <!-- meta: fix=default-to-recent_purchases+OR-no-default-force-explicit-pick -->

- [ ] WEB-UIUX-1122. **[MINOR] No quiet-hours / TCPA timing guard surfaced in UI.** Sending bulk SMS at 11pm violates TCPA in many US states (8am–9pm restriction). `BulkSmsModal.tsx` and `inbox.routes.ts` neither check the local-time window nor the recipient timezone (which would require zip→tz mapping). For a multi-tenant repair-shop product, soft warning ("Local time is 22:14 — typical quiet-hours start at 21:00") would prevent costly compliance hits. L7.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx`
  <!-- meta: fix=client-Date.now()-against-tenant-business-hours-from-/settings/business-hours+modal-banner-when-outside-window+block-or-warn-toggle -->

- [ ] WEB-UIUX-1123. **[MINOR] No character / segment counter — admin blind to per-message cost.** SMS pricing tiers at 160 chars (1 segment), 153 (multi-segment). 1,200 recipients × 3 segments = 3,600 billable units. Modal shows neither template length nor multiplied cost preview. Pairs with WEB-UIUX-1112 (no body preview) — admin literally can't see what they're paying. L6, L7.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx`
  <!-- meta: fix=after-template-pick-render-`${len}/160-chars,-${segments}-segments-×-${count}-=${total}-units`+pull-provider-rate-from-/settings -->

- [ ] WEB-UIUX-1124. **[NIT] "Confirmation expires in 5 minutes" warning has no countdown.** `BulkSmsModal.tsx:191-194` static text. Token bucket is `Math.floor(Date.now()/(5*60_000))` (`inbox.routes.ts:460`) — actual expiry is 5–10min depending on bucket boundary at preview time. Static "5 minutes" undersells half the time, oversells the other. L7.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:191-194`
  <!-- meta: fix=track-previewedAt+show-mm:ss-countdown+disable-Send-when-countdown=0-and-prompt-re-preview -->

### Web UI/UX Audit — Pass 17 (2026-05-05, flow walk: Create Ticket from POS — entry, customer step, signature, success)

Walk: cashier opens POS via sidebar or `/tickets/new` link → CustomerStep (search/new/walk-in) → CategoryStep → DeviceStep → ServiceStep → DetailsStep → repair lands in cart → BottomActions "Create Ticket" → optional signature gate → SuccessScreen. Audited each click target, label vs. action, route destination, recovery path. Findings sorted by severity.

#### Blocker — flow can't complete

- [ ] WEB-UIUX-1125. **[BLOCKER] "Walk-in (no customer info)" button creates a dead-end — repair is added, then "Create Ticket" refuses to submit.** `RepairsTab.tsx:1263` walk-in path: `onClick={() => { setCustomer(null); onDone(); }}` — sets store `customer` to `null`. `BottomActions.tsx:354-358` and `:406-409` then guard the Create-Ticket / Checkout paths with `if (customer === null) { toast.error('Please select or create a customer first'); return; }`. Comment on line 354 says "Allow walk-in (id === 0) and any real customer id. Only block when customer is null." — i.e. the contract was supposed to be a sentinel id=0, but the CustomerStep button never passes one. Server backstop in `pos.routes.ts:1431-1437` happily resolves `customerId=null` to `getOrCreateWalkInCustomerId(adb)` for new tickets, so this gate is purely a UI bug. Result: cashier picks Walk-in → completes the entire device/service/details drill (~30 s of typing) → button blocks them with a toast that contradicts the choice they just made. The flow has no walk-in path that actually finishes. L1, L3, L4.
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:1262-1267`
  `packages/web/src/pages/unified-pos/BottomActions.tsx:354-358,402-410`
  `packages/server/src/routes/pos.routes.ts:1431-1437`
  <!-- meta: fix=CustomerStep-walk-in-onClick=setCustomer({id:0,first_name:'Walk-in',last_name:'',phone:null,mobile:null,email:null,organization:null})+drop-`customer===null`-checks-to-`customer===null||customer.id===undefined` -->

#### Blocker — silent data integrity loss

- [ ] WEB-UIUX-1126. **[BLOCKER] Custom-device + empty manual-price creates a $0-labor repair with no warning.** `RepairsTab.tsx:680-687` "Continue to Details" button is `disabled={!hasPricing && !manualPrice && deviceModelId > 0}`. When the cashier picked "Other device" → free-text name (`onSelect(0, name)` at line 404), `deviceModelId === 0`, so `deviceModelId > 0` is false → disable=false → button is enabled even with empty `manualPrice`. `handleAdd` at line 504-510 then runs `parseFloat('') = NaN`, and the validation regex only fires for non-empty input (`if (manualPrice.trim() !== '' && ...)`), so empty falls through to `laborPrice = Number.isFinite(parsed) ? parsed : 0` → repair added at $0 labor. Cashier sees the cart line at $0.00, can hit Create Ticket, ticket saved. Found weeks later when LTV report shows free repairs. L1, L4 (button enables when it shouldn't), L7.
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:500-510,680-687`
  <!-- meta: fix=disable-button-also-when-deviceModelId===0&&!manualPrice||toast.error('Enter-a-price')-in-handleAdd-when-empty -->

#### Major — finder/recovery breakage

- [ ] WEB-UIUX-1127. **[MAJOR] "New Ticket" link from TicketListPage routes to POS surface, not a ticket-creation form.** `TicketListPage.tsx:1205-1211` `<Link to="/tickets/new">New Ticket</Link>` → `App.tsx:483` `<Route path="/tickets/new" element={<UnifiedPosPage />} />`. User clicks "New Ticket", lands on Unified POS — three tabs (Repairs / Products / Misc), Cash Drawer widget, "Open Drawer" button, Cash In/Out controls, Z-Report — none of which a user creating a ticket needs. Tab defaults to `repairs` (`store.ts:247`) but URL/intent mismatch is unfixed: bookmarking `/tickets/new` always lands in cash-drawer chrome. Consider either a dedicated ticket-creation route that hides POS-only chrome OR rename the button + URL to "New Sale / Repair". L3 route correctness, L6 discoverability.
  `packages/web/src/pages/tickets/TicketListPage.tsx:1205-1211`
  `packages/web/src/App.tsx:483`
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:375-422`
  <!-- meta: fix=`/tickets/new`-renders-stripped-shell:LeftPanel+RepairsTab+`Create-Ticket`-only;-no-Products/Misc-tabs;-no-Cash-Drawer-Widget;-no-Open-Drawer-button -->

- [ ] WEB-UIUX-1128. **[MAJOR] "Skip Signature" button on signature gate has no PIN/role check — anyone can bypass legal customer signature.** `BottomActions.tsx:174-181` (pending state) and `:215-221` (error state) render an unguarded `<button onClick={onBypass}>Skip Signature</button>`. `onBypass` at line 528-531 closes the modal and calls `doCreateTicket()` with `signatureFile=undefined`. The whole point of `requireSignature = bcEnabled && bcTcEnabled` (line 280) is to enforce terms-and-conditions sign-off; the bypass route undoes it with a single click and zero authorization. Compare `pos_require_pin_ticket` / `pos_require_pin_sale` gating elsewhere (line 288-289) — already wired, just not on this button. L1, L4, L7.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:174-181,215-221,280,402-416,528-531`
  <!-- meta: fix=gate-bypass-behind-PinModal('manager'-or-'pos_require_pin_signature_skip')+audit-log-the-skip-with-userId+ticketId -->

- [ ] WEB-UIUX-1129. **[MAJOR] "Create Ticket" button is enabled when no customer is set — clicking it just throws a toast.** `BottomActions.tsx:454` `disabled={!hasRepair || creatingTicket || !!sourceTicketId}`. No `customer === null` term → button looks active in teal even when the customer pill isn't filled. Clicking fires the `customer === null` toast at line 408. Better UX is either (a) disable the button with the existing `title=` hint mechanism ("Select a customer first"), or (b) auto-scroll/focus the customer search input so the gap is visible. Currently the cashier clicks the prominent CTA, gets a 3-second toast, has to remember where the customer step lives, scroll back. L1 findability of the next required action, L7 feedback.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:448-464`
  <!-- meta: fix=disabled+={!customer}+title='Select-a-customer-first'+onClick-fallback-scrollIntoView-on-customer-search-input -->

- [ ] WEB-UIUX-1130. **[MAJOR] "Open Drawer" button (POS bottom bar) opens cash drawer with no PIN gate, regardless of `pos_require_pin_sale`.** `BottomActions.tsx:429-443` `onClick={async () => { await posApi.openDrawer(); toast.success('Cash drawer opened'); }}`. PIN settings (line 288-289) explicitly gate Create-Ticket / Checkout but not the drawer. Manager-PIN threshold (line 269-270) also not consulted. Anyone with a logged-in POS terminal can trigger a drawer-pop without sale or recorded reason — exact pattern that tills want to prevent (the `CashModal` cash-in/out flow at line 23-115 properly records `reason` for audit; the "Open Drawer" shortcut bypasses both). L4 destructive distinguishability, L7 audit trail.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:429-443`
  <!-- meta: fix=add-pos_require_pin_drawer-setting+gate-onClick-behind-PinModal-when-set+server-side-log-cash_drawer_opens(user_id,reason,opened_at) -->

- [ ] WEB-UIUX-1131. **[MAJOR] DeviceTemplateNudge "Go to templates" button navigates away from POS mid-flow — destroys partial customer/device entry.** `UnifiedPosPage.tsx:48-58` `<button onClick={() => navigate('/settings/device-templates')}>Go to templates</button>`. No confirm guard, no draft persistence. Cashier on first ticket: types customer name/phone, picks category, searches device, sees the amber nudge bar above, taps "Go to templates" out of curiosity → returns minutes later → empty cart, no customer, ticket they were halfway through gone. Combined with no autosave for in-progress tickets, this is a recoverable-state cliff. L8 recovery, L4 destructive treatment of a non-destructive-looking link.
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx:48-58`
  <!-- meta: fix=if-cart.length>0||customer-non-null-then-confirm('Leave-and-discard-current-ticket?')-or-stash-draft-in-localStorage+restore-on-return -->

- [ ] WEB-UIUX-1132. **[MAJOR] Ticket-creation SuccessScreen has no "Send confirmation to customer" action — only payment-receipt mode does.** `SuccessScreen.tsx:184-296` (ticket-only branch) renders Print Label / Print Receipt / View Ticket / New Check-in. The SMS/Email buttons live only in the payment-received branch (line 367-389), gated on `invoiceId`. A drop-off customer who left their device and is walking out the door wants a text with the ticket order_id and tracking link — the very thing the QR Photo widget hints at — but there's no button to send it. They have to wait for a status-change-driven SMS later or none at all. L1, L7. Industry pattern: every drop-off CRM (RepairShopr, RepairDesk) sends a "Ticket created" SMS by default; gating it on payment is the wrong axis.
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:184-296`
  <!-- meta: fix=add-Send-Drop-off-Confirmation-(SMS+Email)-buttons-in-the-isTicketOnly-branch+wire-to-existing-smsApi.send/notificationApi.sendReceipt(entity_type:'ticket',entity_id) -->

- [ ] WEB-UIUX-1133. **[MAJOR] Print Label / Print Receipt / View Ticket on SuccessScreen call `resetAll()` BEFORE navigating — no way back to the success view to print the other format.** `SuccessScreen.tsx:143-165` `handlePrintLabel`, `handlePrintReceipt`, `handleViewTicket` all do `resetAll(); navigate(...)`. After printing the label, cashier has to retype/re-walk the ticket to reach the success screen for the receipt — except the ticket is already created, so they'd need to navigate to `/tickets/:id` and find the print actions there. Also breaks the QR-photo flow: the QR is in the success view; reset destroys the scoped photo-upload token (`scopedToken` query, line 56-67) — customer scans an expired link. Industry pattern: keep the success view rendered, open print pages in a new tab/window so the success state survives. L4 (action takes more than its label promises — "Print" also resets POS), L8 recovery.
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:143-165`
  <!-- meta: fix=window.open(url,'_blank')-for-print-routes;-keep-resetAll-only-for-`New-Check-in`-and-`View-Ticket`(navigate-only,no-reset) -->

#### Major — feedback / state-transition mismatch

- [ ] WEB-UIUX-1134. **[MAJOR] Idempotency replay returns the original ticket but UI re-fires the success screen + tutorial advance event identically — cashier can't tell a duplicate-click was rejected vs. a fresh ticket was made.** `BottomActions.tsx:366-372` `posApi.checkoutWithTicket(payload, idempotencyKey, pv)` then unconditionally `setShowSuccess({...res.data.data, mode:'create_ticket'})` and dispatches `pos:ticket-saved`. Server-side `idempotent` middleware returns the cached response on replay (same `ticket_id`/`order_id`), so the UI just shows the same SuccessScreen again. Cashier who double-clicks "Create Ticket" sees green checkmark twice with the same order id, no signal "this was a duplicate"; if they were debugging "did my click register?" they are now uncertain whether one or two tickets exist. L7 feedback specificity.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:366-372`
  `packages/server/src/middleware/idempotent.ts` (cache header)
  <!-- meta: fix=server-emit-`X-Idempotent-Replay:1`+UI-toast('Already-saved-as-{order_id}','info')-instead-of-2nd-success-screen -->

- [ ] WEB-UIUX-1135. **[MAJOR] Customer-search "create new" 409-conflict toast says "Search for them above" but pre-fills the search box with the raw phone — search input expects (XXX) XXX-XXXX format (`formatPhoneAsYouType`) — search may not match.** `RepairsTab.tsx:1149-1162` on `409 Phone number already belongs to`, `setQuery(newForm.phone.trim())` shoves the user's typed-as-formatted phone string back into the search box. Search call (`customerApi.search(query)` line 1097) is server-driven; depending on whether the server trims/normalizes phone, the cashier might see "No customers found" right after being told the customer exists. Consistency hole — strip to digits before stuffing into search. L7 feedback specificity, L9 error helpfulness.
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:1149-1162`
  `packages/web/src/utils/phoneFormat.ts` (`stripPhone`)
  <!-- meta: fix=setQuery(stripPhone(newForm.phone))+verify-customerApi.search-handles-digit-string-or-add-search-by=phone-param -->

#### Minor — copy + hierarchy polish

- [ ] WEB-UIUX-1136. **[MINOR] Cancel button uses generic "Clear the cart and start over?" copy even when a `sourceTicketId` is loaded — the user is editing an existing ticket, not starting a sale over.** `BottomActions.tsx:298-303` `handleCancel` → `confirm('Clear the cart and start over?')` regardless of mode. With `sourceTicketId` set the button discards the ticket-load context AND any local edits — the prompt should distinguish: "Discard changes to {order_id}?" vs. "Clear the cart and start over?". L2 truthful copy.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:298-303`
  <!-- meta: fix=if(sourceTicketId)-confirm(`Discard-changes-to-${sourceTicketOrderId}?`)-else-existing-string -->

- [ ] WEB-UIUX-1137. **[MINOR] SuccessScreen photo-token `Generating secure link…` placeholder has no timeout/Retry — if `getPhotoUploadToken` hangs the customer waits indefinitely on a "Take Device Photos" prompt with no QR.** `SuccessScreen.tsx:55-67` query has `retry: false` + `staleTime: 25min` but no timeout. `photoTokenError` branch (line 231-234) shows a "QR unavailable" message but only if the request errors — a hung/in-flight request shows the loader forever. Cashier ends up handing the device over without any photo-capture link. L9 loading-state usefulness, L7 feedback.
  `packages/web/src/pages/unified-pos/SuccessScreen.tsx:55-67,231-234,256-260`
  <!-- meta: fix=AbortController+8s-timeout+show-Retry-link-on-timeout-or-show-fallback-staff-app-instructions -->

- [ ] WEB-UIUX-1138. **[MINOR] DetailsStep "Add to Cart" success toast says "Added to cart! Select another device or Create Ticket when ready." but the Create-Ticket button is in BottomActions (offscreen on small viewports) and the toast doesn't scroll/highlight it.** `RepairsTab.tsx:795`. New cashiers report scanning the screen for the named action. L1 findability.
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:795`
  <!-- meta: fix=toast.success(...,{icon:'✓'})+briefly-pulse-the-Create-Ticket-button-via-store-flag+ring-2-ring-primary-500-for-1.5s -->

- [ ] WEB-UIUX-1139. **[MINOR] "Photo reminder" amber strip in DetailsStep tells the cashier to take photos but offers no in-flow capture button — the QR/photo widget is on the next-screen success view.** `RepairsTab.tsx:980-985` "Remember to take device photos after check-in for pre-repair documentation." — passive copy, no link or trigger. By the time the success screen renders, the device may already be on the bench. Inline "Capture now (camera)" or "Email me the link" would complete the loop. L6 discoverability.
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:980-985`
  <!-- meta: fix=replace-static-strip-with-button-that-opens-PhotoCaptureModal-pre-create-OR-promotes-the-success-screen-QR-into-this-step -->

### Web UI/UX Audit — Pass 18 (2026-05-05, flow walk: Lock Commission Period — list, lock, CSV, server gates)

Flow walked: Sidebar → Team → "Payroll" → `PayrollPage` → `<CommissionPeriodLock />`. Server: `/team/payroll/periods` (GET/POST), `/team/payroll/lock/:id` (POST), `/team/payroll/export.csv` (GET), `/team/payroll/lock-check` (GET).

#### Blocker — irreversible action with no guardrails

- [ ] WEB-UIUX-1140. **[BLOCKER] Lock button fires immediately on click, no `confirm()` / no modal — and server has NO unlock route. Mis-click = period frozen forever, recoverable only via raw SQL.** `CommissionPeriodLock.tsx:163-174` button calls `lockMut.mutate(p.id)` with zero confirmation. Server `team.routes.ts:882-902` writes `locked_at` + audit row but exposes no inverse — `grep -rn "unlock\|/payroll/unlock" packages/server/src/routes` returns nothing. `_team.payroll.ts:14-28` `isCommissionLocked` then refuses every commission/clock-entry edit in the [start_date, end_date] range (`commissions.ts:181,237`, `employees.routes.ts:375,447-448`, `pos.routes.ts:787`). Real consequence: admin clicks "Lock" on `2026-W14` thinking it was `2026-W13` → all W14 commission tickets/tips/timesheets are now read-only with no UI path back. L1 (irreversible action prominence), L8 (recovery).
  `packages/web/src/components/team/CommissionPeriodLock.tsx:163-174`
  <!-- meta: fix=window.confirm(`Lock ${p.name}? This is permanent — commissions and time entries in ${p.start_date}→${p.end_date} can never be edited again.`)+show-typed-confirm-modal-with-name-echo+optionally-add-server-side-/payroll/unlock-admin+24h-window -->

- [ ] WEB-UIUX-1141. **[BLOCKER] Lock button styled amber (mid-priority) — same visual weight as a "warning" badge. Refactoring UI / NN-G destructive-action guidance: irreversible operations must use red + bold treatment so the eye flags them as different from routine.** `CommissionPeriodLock.tsx:164` `bg-amber-600 text-white hover:bg-amber-700`. Sits next to a neutral Download icon button — operator scanning the row sees them as comparable affordances. L5 hierarchy of destructive vs safe actions.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:164`
  <!-- meta: fix=use-bg-red-600-hover:bg-red-700+ShieldAlert-icon-or-keep-amber-only-if-paired-with-confirmation-modal-(WEB-UIUX-1140) -->

#### Major — role gates, missing context, feedback gaps

- [ ] WEB-UIUX-1142. **[MAJOR] Sidebar shows "Payroll" to managers (`isAdminOrManager`) but server `requireAdmin` rejects Lock and CSV-export — manager sees the page, clicks Lock or Download, gets a generic "Lock failed" / "CSV export failed" toast with no role context.** `Sidebar.tsx:120` entry `{ label: 'Payroll', path: '/team/payroll', icon: DollarSign, adminOnly: true }` is filtered through `isAdminOrManager = userRole === 'admin' || userRole === 'manager'` (`:166-173`) — manager passes the `adminOnly` filter. But `team.routes.ts:887` (`requireAdmin`) and `:910` (`requireAdmin`) gate the only mutating endpoints. Only `POST /payroll/periods` (`:861`) accepts manager. Net effect: manager sees a page where 2 of 3 actions silently 403. Either tighten sidebar to admin-only, or relax server, or surface "Admin only — ask owner" inline. L2 truth, L7 feedback specificity.
  `packages/web/src/components/layout/Sidebar.tsx:120`
  <!-- meta: fix=either-restrict-sidebar-to-admin-only(role==='admin')-OR-conditionally-render-Lock+Download-with-role-tooltip-OR-relax-server-gate-to-admin-or-manager -->

- [ ] WEB-UIUX-1143. **[MAJOR] Lock action freezes commissions AND time entries (per server `:885-887` comment) but UI says nothing about timesheets — admin locking to "freeze commissions" doesn't realise clock-entry edits also break.** `CommissionPeriodLock.tsx:1-11` doc-comment mentions "commission edits" only; no inline copy on the card. Real downstream: `employees.routes.ts:375,447-448` blocks clock-in/out edits in locked range; `pos.routes.ts:787` blocks tip edits. Side-effects undisclosed at action site. L6 discoverability, L9 (action consequence visibility).
  `packages/web/src/components/team/CommissionPeriodLock.tsx:125-145`
  <!-- meta: fix=add-helper-line-under-section-heading:-Locking-prevents-edits-to-commissions,-tips,-and-clock-entries-in-the-period-range. -->

- [ ] WEB-UIUX-1144. **[MAJOR] `locked_by_user_id` and `locked_at` are fetched (interface lines 23-24) but never rendered. After lock, second admin sees a closed-lock icon and nothing else — no "locked by Sasha · May 4 14:22" attribution.** `CommissionPeriodLock.tsx:158-161` locked-state branch shows only `<Lock className="w-4 h-4" />` inside a span. Audit metadata wasted; users can't verify their own lock applied (no echo) and can't see who froze the period when reconciling pay disputes. L7 feedback meaningfulness, L9 (locked-state usefulness).
  `packages/web/src/components/team/CommissionPeriodLock.tsx:158-161`
  <!-- meta: fix=resolve-locked_by_user_id-via-team-roster-lookup-(or-server-pre-join)-and-render-`Locked by ${name} · ${formatDate(locked_at)}`-as-secondary-text -->

- [ ] WEB-UIUX-1145. **[MAJOR] No "preview consequences" before Lock — admin should see "X commissions, Y time entries, Z employees" affected before clicking Lock.** Currently zero context. The same data already powers `/payroll/export.csv` (`team.routes.ts:925-956`) — could be exposed as `/payroll/periods/:id/summary` for an inline `<details>` row. Refactoring UI: "show consequences before destructive action". L9 (preview-before-action).
  `packages/web/src/components/team/CommissionPeriodLock.tsx:140-179`
  <!-- meta: fix=add-server-route-/payroll/periods/:id/summary-returning-{commission_count,clock_entry_count,employee_count,gross_total}+render-as-secondary-line-on-each-unlocked-row -->

- [ ] WEB-UIUX-1146. **[MAJOR] CSV download success has no toast — only error path does. On flaky shop wifi or popup-blocker the operator clicks Download, nothing visible happens, retries → 2 CSVs land in Downloads.** `CommissionPeriodLock.tsx:96-123` success branch (`:113`) clicks the anchor and silently revokes the blob URL. Compare line 121 `toast.error('CSV export failed')`. Inconsistent with rest of app (e.g. `WEB-FB-006` blob exports). L7 feedback meaningfulness.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:96-123`
  <!-- meta: fix=after-a.click()-toast.success(`Downloaded payroll-period-${periodId}.csv`)-or-`Saved to Downloads` -->

- [ ] WEB-UIUX-1147. **[MAJOR] Period name uniqueness + range overlap not validated on either side — two periods with the same name or overlapping ranges silently coexist; commissions in overlap are double-counted in both CSVs.** `team.routes.ts:858-880` POST insert has no UNIQUE constraint check, no overlap check. Client `CommissionPeriodLock.tsx:54-77` doesn't pre-flight either. Demonstrable bug: create `2026-W14` (May 1-7) and `2026-W14b` (May 5-11) → `payroll_periods` has both rows. CSV export for each will both include May 5-7 commission rows because the SUM-by-range query (`team.routes.ts:934-940`) doesn't dedupe across periods. L2, L9 (data integrity feedback).
  `packages/server/src/routes/team.routes.ts:858-880`
  `packages/web/src/components/team/CommissionPeriodLock.tsx:54-77`
  <!-- meta: fix=server-validation:-reject-when-EXISTS-payroll_periods-WHERE-(start_date<=newEnd-AND-end_date>=newStart)-AND-locked_at-IS-NOT-NULL+OR-warn-on-any-overlap+enforce-name-UNIQUE -->

- [ ] WEB-UIUX-1148. **[MAJOR] Period list capped at server `LIMIT 100` with zero pagination/filter/search; weekly cadence × 2 years fills it; older periods silently fall off the end.** `team.routes.ts:852` `ORDER BY start_date DESC LIMIT 100`. Client `CommissionPeriodLock.tsx:35-44` accepts whatever it gets, no "load more". Manager opening the page after 24 months sees the most recent 100 weeks; periods 101+ are invisible to the UI even though the audit/CSV export still works by ID. L6 discoverability of historical data.
  `packages/server/src/routes/team.routes.ts:847-856`
  <!-- meta: fix=add-?year=YYYY-or-?before=ISO+limit/offset-pagination+client-year-picker-or-Load-more-link -->

- [ ] WEB-UIUX-1149. **[MAJOR] Page title "Payroll" but page only locks periods + exports CSV — no payroll-run, no preview totals, no per-employee detail. User clicking "Payroll" looking for "run payroll" finds a lock toggle.** `PayrollPage.tsx:6` `<h1>Payroll</h1>` over a single `<CommissionPeriodLock />` card. Mismatch between sidebar label, page header, and actual functionality. L2 label truthfulness, L5 hierarchy.
  `packages/web/src/pages/team/PayrollPage.tsx:5-9`
  `packages/web/src/components/team/CommissionPeriodLock.tsx:128`
  <!-- meta: fix=rename-page-Payroll-Periods-OR-expand-page-to-include-per-employee-totals+pay-run-summary -->

- [ ] WEB-UIUX-1150. **[MAJOR] `useQuery` `isLoading` state ignored — initial render shows "No payroll periods yet." for ~200-500ms before data lands. Empty-state false positive on cold load.** `CommissionPeriodLock.tsx:35-44` destructures only `{ data }`; `:136-138` shows the empty placeholder when `periods.length === 0`. Should branch on `isLoading` to render skeleton or "Loading periods…" first. L9 loading-state helpfulness.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:35-138`
  <!-- meta: fix=destructure-isLoading-and-render-3-skeleton-rows-or-Loader2-when-isLoading-before-the-empty-state -->

- [ ] WEB-UIUX-1151. **[MAJOR] `lockMut.isPending` disables every unlocked row's Lock button while one mutation is in flight — visually all pending locks "go grey" though the operator only clicked one.** `CommissionPeriodLock.tsx:165` `disabled={lockMut.isPending}` with shared mutation hook across the whole list. Confusing on weekly periods where 4-5 unlocked rows are visible. L7 feedback specificity.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:165-173`
  <!-- meta: fix=track-lockingId-state-(useState-number|null)+disable+spinner-only-on-the-row-whose-id-matches-OR-use-useMutation-with-variables-and-compare-lockMut.variables===p.id -->

#### Minor — labels, validation, modal hygiene

- [ ] WEB-UIUX-1152. **[MINOR] New-period modal primary button is "Save" — generic verb. Refactoring UI/NN-G: button labels should describe the noun action ("Create period").** `CommissionPeriodLock.tsx:237`. L2 truthful copy.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:231-238`
  <!-- meta: fix=replace-Save-with-Create-period -->

- [ ] WEB-UIUX-1153. **[MINOR] Date-range invalid client-side: form lets `end < start`, Save stays enabled, server returns 400 → toast "end_date must be on/after start_date" surfaces only after submit.** `CommissionPeriodLock.tsx:203-222` no client comparison. `:233` `disabled={!newName || !newStart || !newEnd || createMut.isPending}` doesn't include the range check. L7 feedback specificity (catch earlier).
  `packages/web/src/components/team/CommissionPeriodLock.tsx:203-238`
  <!-- meta: fix=disable-Save-when-newStart>newEnd+inline-error-text-End-must-be-on-or-after-start -->

- [ ] WEB-UIUX-1154. **[MINOR] Modal backdrop click closes without "discard changes?" guard — typing 5 fields then mis-clicking the backdrop wipes form state.** `CommissionPeriodLock.tsx:183` `onClick={() => setShowNew(false)}`. Esc handler at `:47-52` has the same property but Esc is at least a deliberate keystroke. L8 recovery.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:182-189`
  <!-- meta: fix=track-isDirty-(any-field-non-empty)+confirm(Discard-this-period?)-on-backdrop-or-Cancel-when-dirty -->

- [ ] WEB-UIUX-1155. **[MINOR] `LockOpen` icon next to "Lock" label is iconographically ambiguous — open-padlock could read "this is open / unlocked" rather than "click to lock the open one". No `aria-label` on the button.** `CommissionPeriodLock.tsx:163-174`. Screen readers announce "Lock, button" without the period name. L4 accessibility, L5 visual clarity.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:163-174`
  <!-- meta: fix=aria-label=`Lock period ${p.name}`+title=`Permanently lock ${p.name}`+consider-Shield-or-Lock-icon-with-arrow -->

- [ ] WEB-UIUX-1156. **[MINOR] Empty-CSV (period with zero commissions/clock entries) still triggers a download with header row + zeros for every active employee — no "No payroll data for this period" prompt.** `team.routes.ts:971-989` always emits a row per active user even when h/c/t are all 0. Operator opens an empty payroll CSV and wonders if export broke. L9 empty-state.
  `packages/server/src/routes/team.routes.ts:925-996`
  <!-- meta: fix=if-all-rows-zero-return-409-with-message-No-payroll-activity-or-client-pre-flight-via-/payroll/periods/:id/summary-(WEB-UIUX-1145) -->

- [ ] WEB-UIUX-1157. **[MINOR] `onError` handler reads only `e.response.data.error` (string) — Zod-style array errors collapse to "Failed to create period" / "Lock failed".** `CommissionPeriodLock.tsx:70-77` and `:87-94`. Lose detail when server returns `{ errors: [{path, message}] }`. L7 actionable error.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:70-94`
  <!-- meta: fix=fall-through-to-data?.errors[0]?.message-or-data?.message-before-string-fallback -->

- [ ] WEB-UIUX-1158. **[NIT] Bulk-lock for past closed periods absent — weekly cadence requires admin to click Lock + (eventual) confirm 4× per month per shop. No "Lock all periods ending before {date}" affordance.** `CommissionPeriodLock.tsx` only renders per-row buttons. After WEB-UIUX-1140 confirmation lands, bulk action saves rep-stress without lowering safety. L6 discoverability of bulk operation.
  `packages/web/src/components/team/CommissionPeriodLock.tsx:139-180`
  <!-- meta: fix=add-Lock-all-closed-periods-button+confirm-dialog-listing-affected-period-names+server-batch-endpoint-/payroll/lock-bulk -->


### Web UI/UX Audit — Pass 19 (2026-05-05, flow walk: Close Cash Drawer Shift — start, count, Z-report, recovery)

Walked end-to-end: cashier clicks **Start Shift** in `BottomActions` (POS) → `OpenShiftModal` enters opening float → server `POST /pos-enrich/drawer/open` writes `cash_drawer_shifts` row → mid-shift cash-in/out routed via `posApi.cashIn`/`cashOut` (separate `cash_register` table) → cashier clicks **Close Shift** → `CloseShiftModal` prompts counted cash blind → server `POST /pos-enrich/drawer/:id/close` computes variance + caches `z_report_json` → `ZReportModal` opens once → operator may print. Cross-checked `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx`, `packages/web/src/pages/unified-pos/ZReportModal.tsx`, `packages/web/src/pages/unified-pos/BottomActions.tsx:418-446`, `packages/web/src/pages/pos/CashRegisterPage.tsx`, `packages/server/src/routes/posEnrich.routes.ts:211-495`, `packages/server/src/routes/pos.routes.ts:203-232`.

#### Blocker — money-reconciliation, variance correctness, dual-systems

- [ ] WEB-UIUX-1159. **[BLOCKER] `computeExpectedCents` IGNORES the `cash_register` table — every paid-in/paid-out from CashRegisterPage (legacy `posApi.cashIn`/`cashOut` → `/pos/cash-in`,`/pos/cash-out`) is invisible to the shift's expected_cents.** `posEnrich.routes.ts:211-229` sums only `payments WHERE method LIKE '%cash%'` between `opened_at..closed_at`. So a $200 float + $50 cash-in (till change) + $30 cash-out (vendor refund) + $0 sales should expect $220 in drawer, but the server computes $200 → declares a $20 OVER variance for an in-balance till. Cashier "investigates" a phantom variance every shift. **Money-correctness bug.** L1, L7, L13, L16.
  `packages/server/src/routes/posEnrich.routes.ts:211-229`
  `packages/web/src/pages/pos/CashRegisterPage.tsx:54-86`
  <!-- meta: fix=expand-computeExpectedCents-to-also-SUM(amount-where-type=cash_in)-MINUS-SUM(amount-where-type=cash_out)-FROM-cash_register-WHERE-created_at-BETWEEN-?-AND-?+include-the-net-in-Z-report-payment_breakdown-as-Cash-Adjustments-row -->

- [ ] WEB-UIUX-1160. **[BLOCKER] Two parallel cash-tracking systems coexist with no UI signposting that they're disconnected — operators routinely use both.** Sidebar exposes "Cash Register" page (`/pos/cash-in`,`/pos/cash-out`, `cash_register` table, dollars REAL) AND POS BottomActions exposes "Start/Close Shift" (cents INTEGER, `cash_drawer_shifts` table, with Z-report). Neither page mentions the other. Same operator clicks "Cash In" on Cash Register page during a `pos_drawer_shift` and assumes it'll appear in the shift's Z-report — it doesn't (see WEB-UIUX-1159). Architectural drift surfaces as a usability failure: operator's mental model is "one drawer", reality is "two ledgers". L1 finds two cash buttons; L2 "Cash In" label means different things in different places; L7 feedback never indicates the parallel state. L1, L2, L4, L7, L13.
  `packages/web/src/pages/pos/CashRegisterPage.tsx`
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx`
  <!-- meta: fix=consolidate-into-single-cash-drawer-domain:-make-/pos/cash-in-/pos/cash-out-also-write-to-cash_drawer_shifts.adjustments+OR-deprecate-CashRegisterPage-and-add-an-In-shift-Cash-Adjustments-section-on-CashDrawerWidget-modal -->

- [ ] WEB-UIUX-1161. **[BLOCKER] `CloseShiftModal` does not surface expected cash, opening float math, or in-shift cash adjustments before the irreversible commit. Operator counts blind, sees variance only after the close mutation succeeds — and there is no reopen path.** `CashDrawerWidget.tsx:246-296` shows only opening float + counted input. The user submits and the server writes `closed_at`, freezes `z_report_json`, locks the shift; `posEnrich.routes.ts:303-385` rejects re-close (409) and there is no admin reverse-close endpoint anywhere. So a typo in counted (e.g., `2200` instead of `220.00`) is permanent and the next shift starts with the prior one's bad variance baked into the audit log. L7 feedback (no preview), L8 recovery (no undo), L1 finding the right number. L7, L8.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:220-296`
  `packages/server/src/routes/posEnrich.routes.ts:303-385`
  <!-- meta: fix=before-submit-show-Expected-row-(call-/pos-enrich/drawer/:id/preview-or-compute-locally)+confirm()-when-counted-is->-3x-or-<-third-of-expected+admin-only-/drawer/:id/reopen-endpoint-that-clears-closed_at+nulls-z_report_json+writes-audit-row -->

#### Major — discoverability, label clarity, recovery, observability

- [ ] WEB-UIUX-1162. **[MAJOR] `GET /pos-enrich/drawer/:id/z-report` on an OPEN shift falls through to `buildZReport` with `counted_cents=0` and `expected_cents=opening_float_cents` — admin previewing in-progress shift sees catastrophic phantom "short by $X" variance.** `posEnrich.routes.ts:484-494` defaults `counted_cents` to `shift.closing_counted_cents ?? 0` when shift is open, producing a -$expected variance the modal renders red with the "Variance ≥ $5 — investigate before next shift" warning. There's no "shift in progress" placeholder. Manager checking mid-shift health gets a fake panic. L9 loading/in-progress state, L7 truthful feedback. L7, L9.
  `packages/server/src/routes/posEnrich.routes.ts:461-495`
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:142-176`
  <!-- meta: fix=server-flag-in_progress=true-when-closed_at-IS-NULL+omit-counted/variance-or-set-to-null+client-render-In-progress-section-without-variance-row-and-warning -->

- [ ] WEB-UIUX-1163. **[MAJOR] "Open Drawer" (physical till-kick) sits adjacent to "Start Shift" (logical accounting) in `BottomActions` — both verbs read like "open the cash drawer", same icon family (LockOpen / Lock).** `BottomActions.tsx:429-446` renders "Open Drawer" then `<CashDrawerWidget />` which renders "Start Shift". A new cashier clicks "Open Drawer" expecting it to begin their shift; nothing in audit/state changes (toast: "Cash drawer opened"), drawer pops, then they're confused why "Close Shift" is greyed out. Label collision between hardware action and accounting action. L2 truthfulness, L1 findability of correct action. L1, L2.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:429-446`
  <!-- meta: fix=rename-Open-Drawer-to-Pop-Cash-Drawer+swap-icon-to-PackageOpen-or-Coins+group-with-receipt-printer-actions-not-shift-actions -->

- [ ] WEB-UIUX-1164. **[MAJOR] `CashModal` in `BottomActions.tsx` (in-shift POS Cash In/Out) does NOT pass `idempotency_key`, while the IDENTICAL `CashRegisterPage.tsx` flow does.** `BottomActions.tsx:37-56` calls `posApi.cashIn({ amount, reason })` with no key. `CashRegisterPage.tsx:51-86` mints `idemKeyRef` and passes `idempotency_key`. Server endpoint accepts the key but doesn't enforce it (`pos.routes.ts:203-217` lacks `idempotent` middleware on cash-in/out). Stalled-network double-click on POS bottom-actions ⇒ duplicate `cash_register` row + duplicate audit, drawer balance off. L7 (silent corruption, no feedback), L8 (no recovery once duplicate posted).
  `packages/web/src/pages/unified-pos/BottomActions.tsx:23-115`
  `packages/server/src/routes/pos.routes.ts:203-232`
  <!-- meta: fix=add-idempotency_key=crypto.randomUUID()-mint-on-modal-open+pass-on-call+wire-idempotent-middleware-to-/pos/cash-in-/pos/cash-out-routes-(same-as-/pos/transaction:253) -->

- [ ] WEB-UIUX-1165. **[MAJOR] Open shift requires no role; close requires manager/admin (`requireManagerOrAdmin`). Asymmetric — cashier opens, then can't close at end of shift if no manager onsite.** `posEnrich.routes.ts:245-301` no role check on open; `:303-307` requires manager on close. End-of-shift cashier stuck staring at "Close Shift" button that 403s — error toast surfaces server message but no path forward (no "request manager approval" affordance, no manager-PIN inline gate like the high-value-sale path). L8 recovery, L1 findability of next step.
  `packages/server/src/routes/posEnrich.routes.ts:245-307`
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:225-244`
  <!-- meta: fix=add-inline-ManagerPinModal-fallback-when-close-returns-403+OR-allow-cashier-to-close-with-manager-PIN-co-sign-(server-accepts-pin-field-bypass-of-role-check) -->

- [ ] WEB-UIUX-1166. **[MAJOR] Variance "high variance" warning hardcoded at `>= 500` cents ($5) — not derived from store config.** `ZReportModal.tsx:171` `Math.abs(variance) >= 500`. High-volume stores routinely run $5 variance per shift; low-volume tobacco shops want $1. Hardcoded threshold means warning fires constantly OR never. Should read `store_config.pos_variance_warn_cents`. L7 actionable feedback (signal-to-noise).
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:170-176`
  <!-- meta: fix=server-include-variance_warn_cents-in-z-report-payload-driven-by-store_config+default-500+UI-uses-the-payload-value-not-magic-number -->

- [ ] WEB-UIUX-1167. **[MAJOR] Close-shift mutation returns the freshly-built `z_report_json` inline (`posEnrich.routes.ts:383`) — client throws it away and refetches via separate `GET /drawer/:id/z-report`.** `CashDrawerWidget.tsx:225-244` calls `api.post(.../close, ...)` with no `.then(res => res.data.data)`, then `onClosed(shift.id)` triggers `<ZReportModal>` whose `useQuery` fires a NEW fetch. Race: if the cached `z_report_json` write hasn't flushed (sync sqlite tx so unlikely but possible across read replicas), the GET rebuilds and could differ. Also wastes a round-trip. L9 perf, L7 consistency.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:225-244`
  `packages/server/src/routes/posEnrich.routes.ts:383`
  <!-- meta: fix=consume-close-response-data+seed-react-query-cache-with-queryClient.setQueryData(['pos-enrich','z-report',shiftId],-resp.data.data)-before-opening-modal -->

- [ ] WEB-UIUX-1168. **[MAJOR] Z-Report viewable only at moment of close; no "View Z-report for shift #N" affordance in POS or admin UI. Operator dismisses modal, the printed paper is the only record.** No route at `/pos/shifts/history`, no link in admin reports, no "Reprint Z-report" button on CashDrawerWidget. Server endpoint `GET /pos-enrich/drawer/:id/z-report` exists and accepts any closed shift id but no UI calls it post-dismiss. L6 discoverability, L8 recovery (lost paper, no reprint path), L13.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:79-83`
  <!-- meta: fix=add-Past-Shifts-link-on-CashDrawerWidget+ShiftHistoryPage-listing-cash_drawer_shifts+row-click-opens-ZReportModal-readonly -->

- [ ] WEB-UIUX-1169. **[MAJOR] `CashDrawerWidget` query refetched only on widget mount + 30s staleTime — POS Cash In/Out via the older CashModal (`BottomActions.tsx`) does NOT invalidate `['pos-enrich','drawer-current']`.** UI shows stale shift state for up to 30s after a cash adjustment. Variance preview (when WEB-UIUX-1161 lands) would also be wrong. L7 feedback consistency.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:37-56`
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:68-75`
  <!-- meta: fix=on-cash-in/out-success-call-queryClient.invalidateQueries({queryKey:['pos-enrich','drawer-current']})+also-invalidate-cash-register -->

- [ ] WEB-UIUX-1170. **[MAJOR] Z-report payload omits cashier name, station/terminal id, shift duration, manager who closed — fields legally required on EOD reports for many jurisdictions and for audit reconciliation.** `posEnrich.routes.ts:391-459` returns: shift_id, opened_at, closed_at, opening_float, expected, counted, variance, payment_breakdown, totals. Missing: `opened_by_user` (joined first/last name), `closed_by_user`, `terminal_id` / `station_id`, `duration_minutes`, `manager_notes`. Printed receipt-shaped Z-report is anonymous. L6, L13 trust/auditability.
  `packages/server/src/routes/posEnrich.routes.ts:391-459`
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:142-211`
  <!-- meta: fix=server-JOIN-users-on-opened_by_user_id-and-closed_by_user_id+include-first/last+include-store_config.station_id-or-similar+UI-renders-Cashier-Manager-Duration-rows-above-totals -->

- [ ] WEB-UIUX-1171. **[MAJOR] No reverse-close / reopen-shift path anywhere. A wrong counted value or accidental click on "Close Shift & View Z-Report" is permanent.** `posEnrich.routes.ts` exposes only `/open` and `/:id/close`. Recovery options: ZERO. The variance lives in the audit log forever; the next shift inherits a fictitious starting position if the operator over/undercounts. L8 recovery (cardinal rule — every irreversible action needs an admin path back).
  `packages/server/src/routes/posEnrich.routes.ts:303-385`
  <!-- meta: fix=admin-only-POST-/pos-enrich/drawer/:id/reopen-with-reason+nulls-closed_at+closing_counted_cents+expected_cents+variance_cents+z_report_json+writes-drawer_shift_reopened-audit-with-prior-values+UI-button-on-ZReportModal-(admin-role)-with-confirm-modal-and-required-reason -->

#### Major — security, info-disclosure

- [ ] WEB-UIUX-1172. **[MAJOR] `GET /pos-enrich/drawer/current` is gated only by base auth — any authenticated user (cashier, technician, even support staff) sees the current shift's `opening_float_cents`, opener id, and opened_at.** `posEnrich.routes.ts:237-243` no role check. Float amounts are shop-confidential (security gates burglary risk). Should be cashier-on-shift OR manager only. L1 (no actionable need for non-cashiers), security adjacent.
  `packages/server/src/routes/posEnrich.routes.ts:237-243`
  <!-- meta: fix=requireRoleAtLeast(cashier)-or-restrict-to-shift.opened_by_user_id===req.user.id-or-manager+admin -->

#### Minor — copy, validation, modal hygiene

- [ ] WEB-UIUX-1173. **[MINOR] Variance copy reads "$5.00 short" / "$5.00 over" / "$0.00 exact" — awkward postfix word grammar; the zero case is especially weird (`"$0.00 exact"`).** `ZReportModal.tsx:169`. Refactoring UI / NN-Group: prefer "Short by $5.00", "Over by $5.00", "Balanced" (no amount). L2 label clarity.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:163-176`
  <!-- meta: fix=replace-with-variance===0?Balanced:variance>0?`Over-by-${formatCents(variance)}`:`Short-by-${formatCents(Math.abs(variance))}` -->

- [ ] WEB-UIUX-1174. **[MINOR] `formatSignedCents` name implies sign-handling but body just delegates to `formatCents` — never prepends `+`/`-` for over/short. Misleading helper.** `ZReportModal.tsx:47-50`. Dead abstraction or unfinished one. L2 (code-clarity adjacent — affects future fixes for WEB-UIUX-1173).
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:42-50`
  <!-- meta: fix=either-make-it-actually-sign-(prepend-+-when->0)-or-inline-formatCents-everywhere-and-delete-the-helper -->

- [ ] WEB-UIUX-1175. **[MINOR] `CashModal` (BottomActions) is a `<div>` not a `<form>` — Enter in Amount field does nothing. `ManagerPinModal` and `OpenShiftModal` callers each diverge on this. Inconsistent keyboard UX across cash-related modals.** `BottomActions.tsx:80-114` vs `:560-642` (form). Tablet keyboards expose "Go" / "Enter" prominently — operator hits it expecting submit. L7, L11 keyboard.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:80-114`
  <!-- meta: fix=wrap-in-form+onSubmit=handleSubmit+button-type=submit -->

- [ ] WEB-UIUX-1176. **[MINOR] `OpenShiftModal` Float input shows no "(max $50,000)" inline — user types 60000, gets a toast error, has to delete digits.** `CashDrawerWidget.tsx:175-188`. The cap exists in `centsFromInput`; UI hides it until violated. L7 specificity, L9.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:175-188`
  <!-- meta: fix=helper-text-below-input:Max-${formatCurrency(DRAWER_CAP_DOLLARS)}+(or-link-Increase-to-pos_high_volume_drawer-toggle-when-bumping-up-against-it) -->

- [ ] WEB-UIUX-1177. **[MINOR] `OpenShiftModal` opens with `submitting=false` after error but does not re-focus the Amount input; placeholder "200.00" reappears as if untouched.** Combined with toast-only error feedback, operator may double-submit thinking the first click registered nothing. L7 (where did my error go?), L8.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:138-209`
  <!-- meta: fix=track-error-state-in-modal+render-inline-aria-live-error+keep-amount-value+focus-back-to-Amount-on-failure -->

- [ ] WEB-UIUX-1178. **[MINOR] Toast "Shift opened" / "Shift closed" lacks shift number, time, variance — operator with multiple closes per day can't disambiguate later in the audit log.** `CashDrawerWidget.tsx:155, 237`. Should be `Shift #N opened (float $X)` and `Shift #N closed — variance $Y short/over`. L7 specificity.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:151-159, 230-244`
  <!-- meta: fix=use-the-server-response-(z_report-on-close-includes-shift_id+variance_cents)-and-format-rich-toast-with-shift-and-variance -->

- [ ] WEB-UIUX-1179. **[MINOR] Counting input is single text field — no denomination breakdown (1s/5s/10s/20s/50s/100s + coins). Cashiers ALWAYS count by stack; UI forces them to do mental sum on calculator first, type total, then pray.** `CashDrawerWidget.tsx:262-273`. Industry-standard EOD UI is grid of denomination × count cells with auto-sum. Single-field gives an answer with no audit of how the count was obtained — high-fraud surface. L1 finding right tool, L13 trust/correctness.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:257-292`
  <!-- meta: fix=add-toggle-Count-by-denomination+grid-(1,5,10,20,50,100,coin-buckets)+sum-into-counted_cents+persist-breakdown-as-cash_drawer_shifts.count_breakdown_json-for-audit -->

- [ ] WEB-UIUX-1180. **[MINOR] `CashDrawerWidget` `isLoading` returns `null` — entire widget vanishes for 100-300ms on POS load. The "Start Shift / Close Shift" button position is empty space then suddenly populates. Layout shift + brief illusion that no shift control exists.** `CashDrawerWidget.tsx:77`. L9 loading state.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:77`
  <!-- meta: fix=render-skeleton-button-(<button-disabled>Loading…</button>)-while-isLoading -->

- [ ] WEB-UIUX-1181. **[MINOR] `OpenShiftModal` and `CloseShiftModal` lack `role=dialog`/`aria-modal`/`aria-labelledby` (unlike sibling `ZReportModal` and `CashModal` which DO set them).** `CashDrawerWidget.tsx:164-209, 246-296`. Screen-reader announces "dialog" generically without title; tab order may escape modal. L4 a11y.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:164-209, 246-296`
  <!-- meta: fix=mirror-ZReportModal-pattern:-role=dialog-aria-modal-true-aria-labelledby=open/close-shift-title+id-on-h3+focus-trap-or-trap-within-modal -->

- [ ] WEB-UIUX-1182. **[MINOR] Z-Report "Print" injects a global `body > * { display: none }` style and removes it on unmount — but if user opens another modal mid-print (e.g. a confirm dialog from elsewhere), that modal disappears from screen too because it's also a `body > *`.** `ZReportModal.tsx:66-79`. Brittle global style hijack. Standard approach is a dedicated `@media print` stylesheet with `data-print-only` semantics on the receipt content. L9, L13 robustness.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:66-79`
  <!-- meta: fix=use-react-to-print-or-render-receipt-into-a-portal-iframe-and-call-iframe.contentWindow.print()+remove-global-style-injection -->

#### Nit — copy, polish

- [ ] WEB-UIUX-1183. **[NIT] CloseShift button label "Close Shift & View Z-Report" reads as a single conjoined irreversible action — the "& View" is innocuous but the sentence makes the operator commit to the destructive part to see the report.** `CashDrawerWidget.tsx:288-291`. Cleaner: "Close Shift" alone (Z-report opens automatically). L2 label truthfulness (don't combine actions in label even if they happen together).
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:285-291`
  <!-- meta: fix=Close-Shift-as-button+small-helper-text-below-Z-report-will-open-after-close -->

- [ ] WEB-UIUX-1184. **[NIT] OpenShiftModal placeholder `"200.00"` and CloseShiftModal placeholder `"0.00"` inconsistent — opener suggests a typical amount, closer suggests "type your count" but reads as "your count is zero".** `CashDrawerWidget.tsx:185, 271`. L2 label clarity.
  `packages/web/src/pages/unified-pos/CashDrawerWidget.tsx:185, 271`
  <!-- meta: fix=both-empty-placeholders+add-aria-describedby-helper-text-Enter-amount-in-dollars-cents -->

- [ ] WEB-UIUX-1185. **[NIT] Print copy of Z-report has no signature / initials line for cashier and manager — required by accounting practice for EOD handover.** `ZReportModal.tsx:142-211`. L13.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:198-208`
  <!-- meta: fix=add-print-only-block-with-Cashier-signature-line+Manager-signature-line+Date-line-(visible-only-in-@media-print) -->

- [ ] WEB-UIUX-1186. **[NIT] Z-report "Payment Breakdown" empty-state reads "No payments recorded" — unclear if this means no payments or query failure.** `ZReportModal.tsx:185-187`. L9.
  `packages/web/src/pages/unified-pos/ZReportModal.tsx:185-187`
  <!-- meta: fix=No-payments-recorded-during-this-shift-(zero-transactions) -->

### Web UI/UX Audit — Pass 20 (2026-05-05, flow walk: Receive Inventory PO — create, status, receive, recovery)

Flow under test (Operations sidebar → "Purchase Orders" → New PO → expand row → Receive Items): create supplier order, transition draft → ordered, count physical receipt, post stock movement, undo if mistake. Server routes audited: `POST /inventory/purchase-orders` (create), `PUT /inventory/purchase-orders/:id` (status change), `POST /inventory/purchase-orders/:id/receive`. Client surface: `PurchaseOrdersPage.tsx` (single page handles list + create form + expand row + receive modal). Real workflow blocked by missing status-change UI; receive defaults to "everything ordered" instead of forcing physical count entry.

#### Blocker — workflow dead-end

- [ ] WEB-UIUX-1187. **[BLOCKER] No UI to advance PO status from `draft` → `pending` → `ordered`. Newly created POs are stuck — receive modal hint says "Change status to 'ordered' before receiving" but zero buttons exist on the page that call `updatePurchaseOrder` (PUT).** Server route `PUT /inventory/purchase-orders/:id` exists (`inventory.routes.ts:1546`) and the API client wraps it (`endpoints.ts:371` `updatePurchaseOrder`). But `PurchaseOrdersPage.tsx` never imports/uses it — only call sites for `inventoryApi.update*` against POs are zero (verified via grep — only literal hint string `Change status to "ordered" before receiving.` at line 272 references it). The user is told what to do but given no control to do it. End-to-end flow (create → receive) is broken. L3 route correctness, L4 flow completion, L8 recovery.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:271-273`
  `packages/web/src/api/endpoints.ts:368-371` (PUT wrapper exists, never invoked)
  `packages/server/src/routes/inventory.routes.ts:1546` (server route)
  <!-- meta: fix=add-status-dropdown-or-"Mark-as-Ordered"-button-to-PoDetailRow-when-status-in-{draft,pending}+wire-to-updatePurchaseOrder({status:'ordered'}) -->

- [ ] WEB-UIUX-1188. **[BLOCKER] Receive modal pre-fills `receive_qty` with FULL remaining quantity for every line — operator who clicks "Confirm Receive" without re-counting silently posts the entire ordered amount as received, even if half the box is missing.** `PurchaseOrdersPage.tsx:60` defaults each line to `it.quantity_ordered - (it.quantity_received || 0)`. Server commits the count straight to `inventory_items.in_stock` and writes a `stock_movements` row marked `'purchase'`. There is NO undo path — receiving stock cannot be reversed from any UI in the app (no "reverse receipt" / "void shipment" button anywhere — searched). One careless click → permanent inventory ghost units → cycle counts will surface them weeks later. Industry standard for receiving UX defaults the count box to **0** (force the human to type physical count). L2 truthful default, L8 recovery (none), L4 destructive default. Severity: blocker because the optimistic default is a silent data-corruption vector, not a visual annoyance.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:51-62, 64-80`
  `packages/server/src/routes/inventory.routes.ts:1465-1526` (no reverse endpoint)
  <!-- meta: fix=default-receive_qty=0+placeholder=`max ${remaining}`+optionally-show-"Receive All-Remaining"-quick-action-button -->

#### Major — flow incompleteness + data loss

- [ ] WEB-UIUX-1189. **[MAJOR] Receive modal captures only quantity — no field for supplier invoice #, packing slip #, lot/batch, expiration date, bin location, or actual unit cost as received.** Standard receiving workflow needs invoice number for AP matching and lot/expiry for traceability (mandatory for regulated parts). Without these the `stock_movements.notes` column is hard-coded `'Received from PO'` (server line 1503) — no audit trail of which physical shipment created the units. Cost variance: PO `cost_price` is locked at order time; if supplier raised price between order and ship, actual cost is silently lost. L4 flow completion, L11 data integrity.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:50-150`
  `packages/server/src/routes/inventory.routes.ts:1465-1526`
  <!-- meta: fix=add-optional-supplier_invoice_no+packing_slip+per-line-lot/batch/expiry/actual_cost+bin-location-fields+server-extends-stock_movements.notes-or-new-receipts-table -->

- [ ] WEB-UIUX-1190. **[MAJOR] Create PO form omits `expected_date` even though server accepts it.** `PurchaseOrdersPage.tsx:288, 326-330` `NewPoForm` has `supplier_id`, `notes`, `items` only. Server `POST /purchase-orders` reads `expected_date` from body (`inventory.routes.ts:1384`). Without expected delivery date, no late-shipment alerting, no aging reports — the data column exists in the schema but is forever NULL. L4 flow gap, L6 discoverability.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:24-28, 288, 326-330`
  `packages/server/src/routes/inventory.routes.ts:1384`
  <!-- meta: fix=add-Expected-Delivery-date-input-to-create-form+pass-as-expected_date-in-createPurchaseOrder-payload -->

- [ ] WEB-UIUX-1191. **[MAJOR] No "Send PO to Supplier" action — created PO sits in `draft` forever with no email/PDF/print path.** Procurement workflow normally: create PO → email supplier → mark `pending` (awaiting confirm) → mark `ordered` (supplier acknowledged). This UI has neither send action nor PDF render. Real-world cashier creates PO and then has to retype it into a separate email client. L4 flow completion, L6 discoverability.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx` (entire file — no send action)
  <!-- meta: fix=add-"Send-to-Supplier"-button-on-PO-row+server-endpoint-POST-/purchase-orders/:id/email+optional-pdf-render-via-existing-print-pipeline -->

- [ ] WEB-UIUX-1192. **[MAJOR] PO list has no search and no status filter.** `PurchaseOrdersPage.tsx:293-297` calls `listPurchaseOrders({ page, pagesize: 25 })` with no `status` or `q` param. Server LIST endpoint accepts `status` (`inventory.routes.ts:1356-1361`) but no `q` (search by PO #, supplier name). At 25 rows/page a shop with 500 POs/yr scrolls 20 pages to find one. L6 discoverability.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:286, 293-297, 363-374`
  `packages/server/src/routes/inventory.routes.ts:1347-1378`
  <!-- meta: fix=add-status-pill-filter-row+search-input-debounced-by-PO-#-or-supplier-name+server-extends-LIST-with-q-LIKE-clause -->

- [ ] WEB-UIUX-1193. **[MAJOR] No barcode-scan receive path surfaced from PO page.** Server has `POST /inventory/receive-scan` (`inventory.routes.ts:1716`) for barcode receiving — but no link from `PurchaseOrdersPage`. Operator with a hand scanner has to manually find the line item and type qty. Faster, less error-prone path is hidden. L6 discoverability, L4 flow.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx` (no scan entry point)
  `packages/server/src/routes/inventory.routes.ts:1713-1716`
  <!-- meta: fix=add-"Scan-to-Receive"-button-on-PoDetailRow-(canReceive)+open-modal-with-scanner-input-bound-to-receive-scan-endpoint -->

- [ ] WEB-UIUX-1194. **[MAJOR] Receive modal "Cancel" silently discards typed counts — no dirty-state warning.** `PurchaseOrdersPage.tsx:135-137` `<button onClick={onClose}>Cancel</button>` and same `onClose` on `✕` and likely on backdrop click (no `e.stopPropagation` on backdrop — no backdrop close handler actually, but the muscle memory of clicking outside). For a modal that captures physical-count data, accidental dismiss = recount the entire shipment. L8 recovery.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:85, 92, 135-137`
  <!-- meta: fix=if-any-receive_qty-differs-from-default-show-confirm("Discard-counted-quantities?")-on-cancel/✕ -->

#### Minor — copy + hierarchy + discoverability

- [ ] WEB-UIUX-1195. **[MINOR] Sidebar uses identical `Package` icon for "Inventory" AND "Purchase Orders" — adjacent rows in Operations section visually collide.** `Sidebar.tsx:76, 80`. Standard PO icon: `ClipboardList` or `Truck`. L5 hierarchy / scannability.
  `packages/web/src/components/layout/Sidebar.tsx:76, 80`
  <!-- meta: fix=swap-PO-icon-to-Truck-or-ClipboardList -->

- [ ] WEB-UIUX-1196. **[MINOR] "Change status to 'ordered' before receiving" hint shown only for status `draft` — `pending` POs also can't receive but get no hint.** `PurchaseOrdersPage.tsx:271-273` checks `status === 'draft'` only. Allowed receivable statuses are `ordered`, `partial`, `backordered`. Pending PO row shows no inline guidance. L9 empty-state helpfulness.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:268-273`
  <!-- meta: fix=show-hint-when-!canReceive&&status!=='received'&&status!=='cancelled' -->

- [ ] WEB-UIUX-1197. **[MINOR] PO row click toggles expand, but PO # column is styled as a primary-color link (`text-primary-600`) — sets affordance for "click to navigate to detail page" that doesn't exist.** `PurchaseOrdersPage.tsx:181-186`. Either drop the link styling or add a real PO detail route. L2 label/affordance truthfulness.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:181-186`
  <!-- meta: fix=remove-text-primary-600-from-PO#-cell-OR-add-/purchase-orders/:id-detail-route -->

- [ ] WEB-UIUX-1198. **[MINOR] Cost-price field on Create form defaults to `0` and silently submits `$0` line items.** `PurchaseOrdersPage.tsx:438-446` placeholder `"Unit cost"` but no validation that cost > 0. Server `validatePrice` allows 0 — inventory items pulled from catalog (`updateItem` at line 416-419) prefill from `inventoryItems.cost_price`, so users who pick from the dropdown are fine. But a row left at 0 silently passes. L7 feedback specificity.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:438-446`
  <!-- meta: fix=warn-on-submit-if-any-line-cost_price===0+confirm("Submit-with-$0-line-items?") -->

- [ ] WEB-UIUX-1199. **[MINOR] After successful receive, toast "Stock received and updated" gives no link to verify.** `PurchaseOrdersPage.tsx:73`. User who wants to check the resulting stock movement has to go to inventory item page manually. Consider toast with action: `toast.success("Stock received", { onClick: () => navigate(`/inventory/${id}`) })`. L7 feedback meaningfulness.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:72-76`
  <!-- meta: fix=use-react-hot-toast-custom-toast-with-link-to-stock-movements-or-the-first-affected-inventory-item -->

- [ ] WEB-UIUX-1200. **[MINOR] Create form Cancel button does NOT reset form state — re-opening shows stale supplier + items.** `PurchaseOrdersPage.tsx:461-463` only flips `setShowCreate(false)`, never `setNewPo({...EMPTY})`. Surprise on re-open. Compare to success path which DOES reset (line 336). L4 flow consistency.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:461-463`
  <!-- meta: fix=cancel-handler-also-calls-setNewPo({supplier_id:'',notes:'',items:[{...EMPTY_ITEM}]}) -->

- [ ] WEB-UIUX-1201. **[MINOR] Empty `—` for `supplier_name` masks data integrity issue.** `PurchaseOrdersPage.tsx:188`. Supplier is REQUIRED at PO create time (`createMut` line 321 + server line 1385). The only path to NULL `supplier_name` is supplier deletion after PO creation. Em-dash hides this — show "(Supplier removed)" so user knows the link is broken. L9 empty-state honesty.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:187-189`
  <!-- meta: fix=supplier_name||"(Supplier-removed)"+add-FK-ON-DELETE-RESTRICT-or-soft-delete-suppliers -->

- [ ] WEB-UIUX-1202. **[NIT] Receive modal's "Confirm Receive" never confirms — fires immediately. Receiving stock is irreversible (no reverse-receipt UI, see WEB-UIUX-1188); high-stakes click deserves a confirm step.** `PurchaseOrdersPage.tsx:138-145`. L4 destructive-action protection, L8 recovery.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:138-145`
  <!-- meta: fix=2-step-confirm-on-Receive-when-totalToReceive>0+show-summary-"Receive-N-units-of-M-items?-This-cannot-be-undone." -->

- [ ] WEB-UIUX-1203. **[NIT] Modal close button uses literal `✕` glyph instead of `X` icon from lucide.** `PurchaseOrdersPage.tsx:92-94`. Inconsistent with other modals in app (which use `<X />` icon). L5 visual consistency.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:92-94`
  <!-- meta: fix=replace-✕-with-<X-className="h-4-w-4"-/>-from-lucide-react -->

- [ ] WEB-UIUX-1204. **[NIT] Receive modal has no Esc-to-close handler.** Standard modal pattern: Esc dismisses. Cashier with hand on numpad can't close without mouse trip. L9, L13 keyboard support.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:84-150`
  <!-- meta: fix=useEffect-keydown-listener-on-mount+if-key=Escape+confirm-if-dirty-then-onClose -->

- [ ] WEB-UIUX-1205. **[NIT] Suppliers + inventory selects in Create form have no loading state — fast users hit "New Purchase Order" and see empty `<select>` until queries land.** `PurchaseOrdersPage.tsx:299-314` (`enabled: showCreate`). For a couple-hundred-ms blip, dropdown reads "Select supplier…" with nothing to pick. L9 loading state.
  `packages/web/src/pages/inventory/PurchaseOrdersPage.tsx:299-314, 383-392, 409-429`
  <!-- meta: fix=if(suppliersLoading||inventoryLoading)-show-skeleton-or-spinner-inside-select+disable-Create-button -->


### Web UI/UX Audit — Pass 21 (2026-05-05, flow walk: Process Refund / Credit Note — invoice detail entry, picker, server effects, recovery)

Flow under test (Invoice detail → "Credit Note" button → reason picker → submit): operator wants to give a customer their money back after a defective sale. Walked entry point on `InvoiceDetailPage.tsx`, the `RefundReasonPicker` component, the `POST /invoices/:id/credit-note` server handler, and the entire `refunds.routes.ts` parallel approval-workflow (which exists end-to-end on the server but has zero UI). Mismatch between the operator's mental model ("refund the card") and what the system actually does ("create a credit note that zeros the invoice and possibly mints store credit") is the dominant theme.

#### Blocker — semantic mismatch + dead workflow

- [ ] WEB-UIUX-1206. **[BLOCKER] No "Refund" action exists in the UI — the only money-back affordance on an invoice is "Credit Note", which DOES NOT reverse the customer's card payment.** `InvoiceDetailPage.tsx:376-380` renders one button (`<CreditCard /> Credit Note`). The handler calls `POST /invoices/:id/credit-note` (`invoices.routes.ts:1162`). That endpoint creates a negative-total invoice, marks the original `paid`, and (if overflow) increments `store_credits`. It NEVER touches the original card payment, never calls BlockChyp/Stripe void, never decrements `payments.amount`. Operator picking reason "Defective product" or "Duplicate charge" expects the customer's card to be credited; instead the customer's card statement is unchanged and the shop's books say "paid". The reason picker labels (`RefundReasonPicker.tsx:18-23`) prove the design intent was a refund flow — but the wired action is a ledger adjustment. L2 truthfulness (label = "Credit Note", reasons = refund-language), L3 destination correctness (button doesn't do what the reasons promise).
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`
  `packages/web/src/components/billing/RefundReasonPicker.tsx:17-24`
  `packages/server/src/routes/invoices.routes.ts:1162-1316`
  <!-- meta: fix=split-into-two-actions:-Refund-Card-(calls-blockchypApi.refund-or-creates-pending-refund-row-via-POST-/refunds)-AND-Credit-Note-(current-behavior)+each-with-distinct-icon-and-help-copy+reason-picker-shared+route-by-original-payment-method -->

- [ ] WEB-UIUX-1207. **[BLOCKER] Entire `refunds.routes.ts` workflow (POST `/refunds`, PATCH `/refunds/:id/approve`, PATCH `/refunds/:id/decline`, GET `/refunds`) has ZERO UI callers — full pending/approved/declined state machine, role gates, idempotency middleware, commission reversal, payroll-period-lock handling — all dead code from the user's perspective.** Verified: grepped client tree for `'/refunds'`, `refundsApi`, `refundApi` — no matches. The server even has `requirePermission('refunds.create')` and `requirePermission('refunds.approve')` permission rows tracked, but neither permission gates anything in the UI (no button in admin reports, no inbox of pending refunds, no list page). A real refund (with manager approval) cannot be initiated by any operator. L3 dead route, L6 discoverability, L4 flow completion.
  `packages/server/src/routes/refunds.routes.ts:1-548` (entire file unreachable from UI)
  `packages/web/src/api/endpoints.ts` (no `refundsApi` export)
  <!-- meta: fix=add-refundsApi-with-list/create/approve/decline+RefundsQueuePage-under-Admin/Reports-listing-pending-refunds+approve/decline-buttons+wire-Refund-Card-button-on-InvoiceDetailPage-to-create-a-pending-refund-row-when-original-payment-was-card -->

#### Major — flow correctness + recovery

- [ ] WEB-UIUX-1208. **[MAJOR] Credit-note silently inflates `amount_paid` on the original invoice by the credit amount — invoice flips to "paid" status with no actual money movement.** `invoices.routes.ts:1245-1257` `cappedAmountPaid = Math.min(prevAmountPaid + amount, total)` then UPDATE. So a $100 invoice with $50 collected, after a $50 credit note, reads `amount_paid=$100, amount_due=$0, status=paid` — but the customer paid only $50 cash. Reconciliation between AR ledger and bank deposits will silently disagree by $50 forever. The accounting-correct shape is: original invoice's `amount_paid` stays at $50 (real cash), and the new credit-note row's negative total is what brings net AR to zero. L13 trust/correctness, L7 honest feedback (status reads "paid" while customer was not refunded).
  `packages/server/src/routes/invoices.routes.ts:1245-1257`
  <!-- meta: fix=do-not-mutate-original.amount_paid-on-credit-note+let-the-negative-credit-note-row-cover-the-AR-reduction+OR-introduce-amount_credited-column-distinct-from-amount_paid -->

- [ ] WEB-UIUX-1209. **[MAJOR] Invoice list (`GET /invoices`) does not exclude credit-note rows — negative-total `CN-XXXX` invoices interleave with normal invoices.** `invoices.routes.ts:234-283` builds WHERE clause from status/customer/date/keyword filters but never filters on `credit_note_for IS NULL` or distinguishes `inv.total < 0`. AR aging totals, monthly receivables charts, and the invoice list table all show negative phantom rows. UI (`InvoiceListPage.tsx`) likewise renders them without distinction. L9 honest list state, L13 reporting integrity.
  `packages/server/src/routes/invoices.routes.ts:234-283`
  `packages/web/src/pages/invoices/InvoiceListPage.tsx`
  <!-- meta: fix=add-?type=invoice|credit_note|all-query-param+default-to-invoice+UI-tab-toggle-Invoices/Credit-Notes/All+badge-on-CN-rows-when-mixed-view -->

- [ ] WEB-UIUX-1210. **[MAJOR] "Credit Note" button is rendered to every authenticated user (`InvoiceDetailPage.tsx:376-380` shows it whenever `status !== 'void' && total > 0`), but the server requires `invoices.credit_note` permission (`invoices.routes.ts:1162`).** Cashier-tier user clicks the visible button → fills the modal → submits → 403 toast. No way to know in advance the action is unavailable. Compare to `Void` (line 384) which has the same lack of gating but at least has a typed-confirm. L1 findability of correct action, L7 specificity (the 403 copy doesn't tell them who CAN do this).
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380, 384-388`
  `packages/server/src/routes/invoices.routes.ts:1162`
  <!-- meta: fix=client-fetch-permissions-via-existing-/me-or-/permissions-call+conditionally-render-Credit-Note-and-Void-buttons+show-disabled-tooltip-Need-manager-permission-when-user-lacks-it -->

- [ ] WEB-UIUX-1211. **[MAJOR] No confirm dialog for "Create Credit Note". One click on "Create Credit Note" in modal posts it irrevocably — there is NO `voidCreditNote` / `reverseCreditNote` endpoint anywhere.** Compare `Void Invoice` flow (line 807-817) which correctly forces typing the order_id. Credit notes are equally irreversible (the negative invoice stays in AR forever, the original is permanently "paid", and any store-credit overflow can be SPENT by the customer before the operator notices). One operator typo on the amount field = permanent ledger drift. L4 destructive-action protection, L8 recovery (none).
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-801`
  `packages/server/src/routes/invoices.routes.ts:1162-1316` (no reverse endpoint exists)
  <!-- meta: fix=ConfirmDialog-with-requireTyping=order_id+danger-styling+server-add-DELETE-/invoices/:cn_id/credit-note-(admin-only)-or-POST-/invoices/:id/credit-note/reverse -->

- [ ] WEB-UIUX-1212. **[MAJOR] After credit note, no customer notification — no email "we issued a $X credit toward invoice Y", no SMS.** Operator who issues credit-as-refund-substitute then has to manually message the customer "your card wasn't refunded but you have store credit" or risk a chargeback. The `notificationApi.sendReceipt` exists for receipts; there's no analogous `sendCreditNote` path. L4 flow completion, L7 customer-side feedback.
  `packages/server/src/routes/invoices.routes.ts:1303-1316`
  `packages/web/src/api/endpoints.ts` (no `sendCreditNote`)
  <!-- meta: fix=server-after-credit-note-create-enqueue-notification-credit_note_issued+send-via-existing-notif-pipeline+template-includes-amount-reason-store-credit-balance-if-overflow -->

- [ ] WEB-UIUX-1213. **[MAJOR] Credit-note success only invalidates `['invoice', id]` and `['invoices']` — not `['payments']`, not customer's `['store-credit', customerId]`, not `['reports', ...]`.** `InvoiceDetailPage.tsx:169-171`. Side panels showing payment history, customer's store-credit balance, and AR reports remain stale until manual refresh. The credit-note's overflow path (`invoices.routes.ts:1261-1297`) writes to `store_credits` and `store_credit_transactions` — neither cache is invalidated client-side. L7 feedback consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-175`
  <!-- meta: fix=on-success-invalidate:['invoice',id]+['invoices']+['payments',invoiceId]+['store-credit',customer_id]+['reports']+['customer',customer_id] -->

- [ ] WEB-UIUX-1214. **[MAJOR] Credit-overflow → store credit is silent. Modal copy "This will reduce the outstanding balance" never warns that an excess will become store credit.** A $200 credit on an invoice with $50 paid creates $150 of store credit for the customer (`invoices.routes.ts:1261-1297`) — but the modal's max-helper says "Max: $50.00 (amount paid)" so client-side validation catches THIS exact case (line 298-303). However, server-side the cap is `original.total` not `amount_paid` (line 1186), so a curl-direct request OR a future UI change can land overflow with no warning. Even within the current cap, the credit + already-paid math means `requested > total` is impossible (capped at $50)... but the comment block at 1240-1244 explicitly preserves the overflow path. Either the path is reachable through some flow not audited, or the code is dead — either way the docstring promise ("record overflow as store credit") is not surfaced anywhere in the UI. L7 invisible side-effect, L13 audit trail.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:753-755`
  `packages/server/src/routes/invoices.routes.ts:1240-1297`
  <!-- meta: fix=if-amount-greater-than-amount_due-show-warning-block:Excess-of-$X-will-be-issued-as-store-credit+OR-server-tighten-cap-to-amount_paid-and-delete-overflow-path-if-truly-unreachable -->

#### Minor — picker bugs, modal hygiene, copy

- [ ] WEB-UIUX-1215. **[MINOR] `RefundReasonPicker` swallows note text typed BEFORE a reason is picked — `handleNoteChange` only calls `onChange` when `localReason` is set.** `RefundReasonPicker.tsx:47-50`. Operator opens modal, types a long explanation in Notes, then clicks a reason chip — the note IS now propagated. But if they type the note then close the modal (Esc, Cancel, backdrop), parent's `note` is `''` and the typing is lost. The visible `value={localNote}` (line 86) preserves text in the textarea so the user thinks it's safely captured. L7 silent state loss.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:39-50`
  <!-- meta: fix=propagate-note-to-parent-on-every-keystroke-regardless-of-localReason+OR-disable-the-note-textarea-until-a-reason-is-selected -->

- [ ] WEB-UIUX-1216. **[MINOR] Note textarea `maxLength={500}` silently truncates. No character counter, no warning at threshold.** `RefundReasonPicker.tsx:91`. Operator pasting a long incident report from chat hits 500 chars, rest disappears with no signal. L7 specificity.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:85-92`
  <!-- meta: fix=add-counter-${localNote.length}/500-below-textarea+turn-amber-when->450 -->

- [ ] WEB-UIUX-1217. **[MINOR] "Other" reason hint reads "Free-form reason in the note." but the note label says "Notes (optional)" — for "Other" the note should be required, otherwise the audit row stores only the literal string `"other"`.** `RefundReasonPicker.tsx:23, 83`. Reporting that groups by reason gets a useless `"other"` bucket with no detail. L4 flow completion (forced detail), L13 audit value.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:23, 82-92`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:305-310` (validation only requires `reason`, not `note` when reason==='other')
  <!-- meta: fix=if-localReason==='other'-make-note-required+label-becomes-Notes-(required)+parent-handleCreditNote-validates-note.trim().length-when-code==='other' -->

- [ ] WEB-UIUX-1218. **[MINOR] Credit-note modal backdrop click dismisses without dirty-state warning.** `InvoiceDetailPage.tsx:744` `onClick={(e) => { if (e.target === e.currentTarget) setShowCreditNote(false); }}`. Same misclick risk as receive-modal (WEB-UIUX-1194) — typed amount + selected reason + typed note all lost. L8 recovery.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:738-746`
  <!-- meta: fix=if-(amount||reason||note.trim())-show-window.confirm("Discard-credit-note?")-on-backdrop-click+also-on-Esc-handler-in-useEffect:60-69 -->

- [ ] WEB-UIUX-1219. **[MINOR] "Create Credit Note" submit button is amber-600 (warning hue) — neither destructive (red) nor primary. Inconsistent with Void (red) which IS destructive in the same way.** `InvoiceDetailPage.tsx:798`. Color signals "caution" but action is irreversible money movement; should match Void's red palette OR primary for non-destructive save. L5 hierarchy / destructive distinguishability.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-801`
  <!-- meta: fix=switch-to-bg-red-600/hover:bg-red-700-to-match-Void-button+OR-bg-primary-600-and-add-an-explicit-confirm-step-(see-WEB-UIUX-1211) -->

- [ ] WEB-UIUX-1220. **[MINOR] Reason picker labels "Defective product / Duplicate charge / Wrong item" all imply REFUND semantics (money back to card). The chosen action (Credit Note) does not refund the card. Either the picker is wrong here or the action is wrong — they don't match.** `RefundReasonPicker.tsx:17-24` was authored as a refund picker (component name + comments confirm — see line 2 "for partial refunds"); reusing it on a credit-note modal mis-leads operators. L2 truthful labels.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:1-10`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:783-789`
  <!-- meta: fix=split-CreditNoteReasonPicker-(price_adjustment+goodwill+billing_correction+other)-from-RefundReasonPicker-(defective+wrong_item+duplicate_charge+dissatisfaction+other)+each-paired-with-its-correct-action -->

- [ ] WEB-UIUX-1221. **[MINOR] Server `code` field accepts arbitrary string — not validated against the 6-code enum.** `invoices.routes.ts:1180-1182` `typeof req.body.code === 'string' && req.body.code.trim()`. UI sends from a fixed list; curl/integration callers can submit `code='lol'` and the row stores it. Reports that group by reason then have unbounded code cardinality, breaking aggregation. L13 schema integrity.
  `packages/server/src/routes/invoices.routes.ts:1180-1182`
  <!-- meta: fix=validateEnum(req.body.code,['defective','dissatisfaction','wrong_item','duplicate_charge','price_adjustment','other','billing_correction','goodwill'],'code')+share-the-list-with-RefundReasonPicker -->

- [ ] WEB-UIUX-1222. **[MINOR] Modal description "Issue a credit note against invoice X. This will reduce the outstanding balance." — inaccurate when the invoice has zero outstanding balance.** `InvoiceDetailPage.tsx:753-755`. For a `paid` invoice (amount_due=0), the credit creates store-credit overflow; "reduce the outstanding balance" is false. L2 truthfulness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:753-755`
  <!-- meta: fix=conditional-copy-based-on-invoice.amount_due:amount_due>0?Reduces-balance-by-X:Adds-to-customer's-store-credit-balance -->

- [ ] WEB-UIUX-1223. **[MINOR] Cancel button on credit-note modal doesn't reset form state. Re-open shows stale amount + reason + note.** `InvoiceDetailPage.tsx:792-794` `onClick={() => setShowCreditNote(false)}`. Compare success path (line 173-174) which DOES reset. Same bug pattern as PO-create cancel (WEB-UIUX-1200). L4 flow consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:791-794`
  <!-- meta: fix=cancel-handler:setShowCreditNote(false)+setCreditNoteForm({amount:'',reason:null,note:''})+also-Esc-handler-and-✕-handler -->

#### Nit — visual polish

- [ ] WEB-UIUX-1224. **[NIT] Reason picker uses `grid-cols-2` on all viewports — on narrow modal widths the 2-line hints wrap awkwardly into 3-4 lines per chip.** `RefundReasonPicker.tsx:62`. Single-column under `sm:` would breathe. L11 responsive.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:62`
  <!-- meta: fix=grid-cols-1-sm:grid-cols-2 -->

- [ ] WEB-UIUX-1225. **[NIT] Credit-note `notes` field on the new invoice row stores `"Credit note: ${reason}"` (`invoices.routes.ts:1224`) — duplicates `credit_note_code` + `credit_note_note` columns. Three places store the reason; report queries that read `notes` get the legacy composed string while reports reading `credit_note_code` get the enum value.** Risk of divergence as new credit notes are issued. L13 schema dup.
  `packages/server/src/routes/invoices.routes.ts:1213-1224`
  <!-- meta: fix=stop-writing-Credit-note-prefix-into-notes+OR-derive-notes-display-from-code+note-on-read+single-source-of-truth -->

### Web UI/UX Audit — Pass 22 (2026-05-05, flow walk: Apply Discount at POS — line item, order-wide, member, manager-PIN gate, server enforcement)

Flow under test (LeftPanel cart → click `Add discount` pill → enter amount + optional reason → Apply → checkout): operator wants to give a customer money off their cart at the register. Walked the cart-wide `DiscountEditor` (`LeftPanel.tsx:864-981`), the orphaned `LineItemDiscountMenu` component, the auto-applied member discount on `CustomerSelector.tsx`, the manager-PIN threshold logic in `BottomActions.tsx:244-270`, and the server's `POST /pos/checkout-with-ticket` discount validation (`pos.routes.ts:1869-1889`). Recurring theme: cart-wide is dollar-only with zero policy (no max, no manager gate, no percent), per-line is ghost-coded, member discount silently overrides instead of stacking, and reason capture is best-effort and partially dropped on the invoice path.

#### Blocker — missing primitives + dead UI

- [ ] WEB-UIUX-1226. **[BLOCKER] `LineItemDiscountMenu` (164 lines, complete chip-picker with 5 reason codes + percent input + portal positioning) is NEVER imported anywhere in the codebase — per-line discount UI does not exist for operators.** `LineItemDiscountMenu.tsx:1-164`. Verified by `grep -rn "LineItemDiscountMenu"` — only matches are inside its own file. `RepairsTab.tsx:790` always inits `lineDiscount: 0`, `LeftPanel.tsx:148/399` and `UnifiedPosPage.tsx:318` only read `device.line_discount` from a server-loaded ticket — there is no client write path. The cart row at `LeftPanel.tsx:585-589` displays a per-line discount line item if non-zero, but no UI lets the operator set one. Server (`pos.routes.ts:1630-1668`) accepts `line_discount` per device, validates and applies it, so backend is fully wired — only the client UI is missing. Operator wanting "10% off labor on this device only" has to (a) edit `laborPrice` directly to fake it (loses the audit reason, breaks reports that group by `line_discount`), or (b) apply a cart-wide discount that hits everything. L3 destination correctness (no entry point), L6 discoverability, L4 flow completion.
  `packages/web/src/pages/unified-pos/LineItemDiscountMenu.tsx:1-164` (dead component)
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:585-608` (display path with no editor)
  `packages/web/src/pages/unified-pos/RepairsTab.tsx:790` (init only, never updated)
  <!-- meta: fix=wire-LineItemDiscountMenu-into-RepairRow-(LeftPanel.tsx:574-)+anchor-on-click-of-the-laborPrice-cell-or-add-a-Percent-icon-button+onApply=updateCartItem(item.id,{lineDiscount:laborPrice*p/100,lineDiscountReason:reason})+extend-types.ts-RepairCartItem-with-lineDiscountReason+include-in-buildTicketPayload+server-already-accepts -->

- [ ] WEB-UIUX-1227. **[BLOCKER] No max-discount cap and no manager-PIN gate for high discounts. `pos_max_discount`, `pos_max_discount_pct`, and `pos_require_manager_for_discount` settings do not exist in `settingsMetadata.ts` or `store_config`.** Verified: grepped repo for any of those keys — zero matches. Operator can apply a $399.99 discount to a $400 cart with reason "Loyalty" (a free-text string), single-handed, no oversight. The only PIN gate (`BottomActions.tsx:244-270`) fires on cart **subtotal** crossing `pos_manager_pin_threshold` — orthogonal to discount magnitude. So a $40 cart with $39 discount: no gate, audit log records `discount_amount: 39, discount_reason: 'Loyalty'`, sale closes. L4 flow completion (no policy enforcement), L13 audit/shrinkage protection, L4 destructive-action protection.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:880-888` (no cap check)
  `packages/server/src/routes/pos.routes.ts:1869-1889` (server caps only at subtotal+tax, not at policy max)
  <!-- meta: fix=add-pos_max_discount_pct-(default-50)+pos_require_manager_for_discount_pct-(default-25)+pos_max_discount_dollars-cap+server-validate-against-store_config+client-trigger-ManagerPinModal-when-amount/subtotal-crosses-threshold-(reuse-existing-PIN-flow-from-BottomActions.tsx:237) -->

#### Major — silent overrides, missing reasoning, dead paths

- [ ] WEB-UIUX-1228. **[MAJOR] Server takes `Math.max(manualDiscount, membershipDiscountAmt)` by default — manual discount is silently DROPPED if membership tier discount is larger, with no UI feedback.** `pos.routes.ts:1881` `const discount = roundCents(Math.max(manualDiscount, membershipDiscountAmt))`. Operator types $5 manual "Damaged box" reason → customer's Gold tier gives 15% = $30 → final invoice records $30 discount, reason becomes the audit log's `discount_reason: 'Damaged box'` (manual reason preserved) but the manual $5 was discarded. Operator believes both applied. The `stack_membership` flag (line 1880 elided) lets them sum, but NO client passes it (verified — grepped `stack_membership` across web tree, zero matches). L7 silent state loss, L2 truthful feedback.
  `packages/server/src/routes/pos.routes.ts:1869-1889`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:102-121` (request payload — no `stack_membership` field)
  <!-- meta: fix=client-show-Member-tier-X-discount:-$Y-line-separately-from-manual+OR-add-stackMembership-toggle-with-explanation+server-warn-if-manual<member-and-not-stacking-(return-info-in-response) -->

- [ ] WEB-UIUX-1229. **[MAJOR] Member discount auto-application has zero UI surface — no toast, no banner, no cart line. `CustomerSelector.tsx:91-102` calls `setMemberDiscountApplied(true)` silently when a customer with `group_auto_apply` is selected.** Customer sees their total drop $30 mid-flow with no explanation. The cart `DiscountEditor` (`LeftPanel.tsx:895-919`) only shows the manual `discount` value, not membership. The combined `totals.discountAmount` (`totals.ts:87` = manual + member) IS rendered in the checkout summary as a single "Discount" line — no breakdown. L7 invisible side-effect, L2 truthful feedback, L4 customer-facing transparency.
  `packages/web/src/pages/unified-pos/CustomerSelector.tsx:90-102`
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:899-906`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:443-447`
  <!-- meta: fix=add-second-row-in-cart-totals-when-member-applied:Member-(Gold-15%)-(-$X)+toast-on-customer-pick:Auto-applied-Gold-tier-15%-discount+receipt-prints-each-discount-line-separately -->

- [ ] WEB-UIUX-1230. **[MAJOR] `discount_reason` is captured client-side and sent in every checkout payload, but the `INSERT INTO invoices ...` statement at `pos.routes.ts:2217-2236` does NOT pass it.** Schema HAS `invoices.discount_reason TEXT` (`migrations/001_initial.sql:282`, `013_invoices_nullable_customer.sql:21`). For non-ticket sales (product-only carts), the reason vanishes from invoices.discount_reason — only audit_logs gets it. `InvoiceDetailPage.tsx:460` reads `invoice.discount_reason` and prints it parenthetically; for product-only checkouts it always renders blank. L13 schema/data integrity, L4 audit completeness, L7 truthful display.
  `packages/server/src/routes/pos.routes.ts:2215-2236` (missing column)
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:460`
  <!-- meta: fix=add-discount_reason-to-INSERT-INTO-invoices-(both-update-and-insert-arms)+pass-ticketData?.discount_reason ?? null+drop-redundant-audit-only-path-OR-keep-both -->

- [ ] WEB-UIUX-1231. **[MAJOR] Cart-wide discount is dollar-only — no percent shorthand. Operator giving "10% off this $327.50 sale" must mental-math $32.75, type, hope.** `LeftPanel.tsx:936-948` only renders an `Amount ($)` input. Compare orphan `LineItemDiscountMenu.tsx:118-130` which accepts percent (the right primitive for "10% off"). Real-world POS operators apply percentage discounts far more often than fixed-dollar (every retail study confirms). L7 affordance / cognitive load, L4 flow ergonomics.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:936-948`
  <!-- meta: fix=toggle-pill-$/%-above-input+if-%-store-as-derived-amount=subtotal*p/100-OR-server-accept-discount_pct-and-resolve-(matches-membership-path)+show-both-values-in-summary -->

- [ ] WEB-UIUX-1232. **[MAJOR] No client-side cap on typed discount amount — operator typing $1000 on a $200 cart only finds out after clicking Apply, then trying to checkout, then server returns 400 "Discount cannot exceed subtotal + tax".** `LeftPanel.tsx:880-888` clamps negatives to 0 but does not clamp upper bound. `pos.routes.ts:1886` rejects on server. Toast appears AFTER the operator has progressed to the checkout modal in many flows (because `setDiscount` always succeeds locally). L7 deferred error, L4 flow recovery — they have to reopen the cart, fix amount, re-progress.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:880-888`
  <!-- meta: fix=clamp-amount-to-subtotal+show-helper-Max:-${subtotal.toFixed(2)}-below-input+amber-warning-when-amount===subtotal:Will-zero-the-cart -->

- [ ] WEB-UIUX-1233. **[MAJOR] Reason input is plain free-text — no chip palette, no autocomplete from prior reasons, no enum.** `LeftPanel.tsx:954-961`. Reports that group by `discount_reason` will see infinite-cardinality strings ("loyalty", "Loyalty", "loyal", "loyaty", " loyalty "). Compare `RefundReasonPicker.tsx:14-31` (refund flow) and the orphan `LineItemDiscountMenu.tsx:25-31` — both use a fixed enum + chips + custom fallback. The reason-picker pattern was already authored TWICE in this repo and yet the cart-wide discount uses neither. L13 reporting integrity, L4 consistency.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:954-961`
  <!-- meta: fix=extract-DiscountReasonPicker-with-chips-loyalty/bulk/employee/damaged/manager-comp/custom+share-with-LineItemDiscountMenu-(once-it's-wired)+server-enum-validate-with-custom-allowed -->

- [ ] WEB-UIUX-1234. **[MAJOR] `pos_show_discount_reason` defaults to off — most stores will leave it disabled, making the audit-log entry record `discount_reason: null` for every discounted sale. Audit trail is operationally useless.** `LeftPanel.tsx:867`. The toggle exists in `PosSettings.tsx:207-208` but the only enforcement is "block apply when amount > 0 and reason empty" (`LeftPanel.tsx:882-884`); when off, reason is never asked for. Manager investigating shrinkage gets `discount_reason: null` in audit_logs. L13 audit value vs. operator friction tradeoff, but default should err toward audit.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:867,882-884`
  `packages/web/src/pages/settings/PosSettings.tsx:207-208`
  <!-- meta: fix=default-pos_show_discount_reason-to-1+OR-make-reason-required-when-discount-exceeds-N-percent-(graduated-policy)+document-rationale-in-PosSettings-help-text -->

- [ ] WEB-UIUX-1235. **[MAJOR] X (remove) button on `Add discount` pill silently wipes amount + reason with no confirm.** `LeftPanel.tsx:907-916`. Operator has typed 100 chars of context "Customer claims item arrived damaged on Tuesday Mar 3, returned Wed, photos in email" → misclick on the X next to the pill → all gone, no undo, no toast. Compare cart-discount Apply path which keeps the panel state syncable, but this path doesn't even open the panel — it's instant clear. L8 recovery (none), L4 destructive-action protection.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:907-916`
  <!-- meta: fix=on-click-of-X-when-discountReason.length>20-show-window.confirm("Discard-discount-and-reason?")+OR-open-the-editor-instead-of-clearing-and-let-operator-Clear-from-inside -->

#### Minor — picker bugs, copy, ergonomics

- [ ] WEB-UIUX-1236. **[MINOR] `Add discount` pill has Percent icon but field accepts dollars. Misleading affordance — operators expect % input.** `LeftPanel.tsx:904`. Confirms WEB-UIUX-1231: the percent icon was clearly the original design intent (matches `LineItemDiscountMenu.tsx:92` which IS percent). Either swap the icon to `DollarSign` OR add the % toggle and keep Percent. L2 truthful icon.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:904`
  <!-- meta: fix=swap-Percent-for-Tag-or-DollarSign-(lucide)+OR-implement-WEB-UIUX-1231-and-keep-Percent-as-default-mode -->

- [ ] WEB-UIUX-1237. **[MINOR] `parseFloat(draftAmount)` in handleApply accepts garbage: "$5" → NaN → 0 (silently); "5,00" (EU) → 5; "5e2" → 500; "1.2.3" → 1.2.** `LeftPanel.tsx:881`. NaN coerces to falsy and `parseFloat(draftAmount) || 0` zeros it without telling the operator the input was rejected. EU operators dragging-and-dropping numbers from chat hit this. L7 silent input loss.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:881-887`
  <!-- meta: fix=use-validatePrice-style-parser-(strip-$,reject-comma,reject-scientific)+show-inline-error-Invalid-amount+keep-panel-open -->

- [ ] WEB-UIUX-1238. **[MINOR] On Apply success, focus does not return to the trigger pill — focus drops to body. Keyboard / screen-reader users lose place.** `LeftPanel.tsx:880-888`. After `setOpen(false)` the panel unmounts; no `triggerRef.current?.focus()`. WCAG 2.4.3 focus-order. L11 a11y.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:864-919`
  <!-- meta: fix=add-triggerRef-on-the-Add-discount-button+useEffect-on-open-transition:if-was-open-and-now-closed-trigger.focus() -->

- [ ] WEB-UIUX-1239. **[MINOR] Esc and outside-click do NOT close the discount editor.** `LeftPanel.tsx:921-981`. Compare the orphan `LineItemDiscountMenu.tsx:54-67` which does both. Operator opens panel, types, decides to abandon — must mouse-click the small X. Esc-to-cancel is the muscle memory across every other modal in the app. L4 consistency, L11 keyboard.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:864-981`
  <!-- meta: fix=mirror-LineItemDiscountMenu's-useEffect-Esc+outside-click-handlers+also-warn-on-dirty-state-(see-WEB-UIUX-1235) -->

- [ ] WEB-UIUX-1240. **[MINOR] Aria-label on the Add-discount pill stays "Add order discount" even when a discount IS already applied — should switch to "Edit order discount: -$X" so screen reader announces state.** `LeftPanel.tsx:902`. L11 a11y (state announcement).
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:898-906`
  <!-- meta: fix=aria-label={discount>0?`Edit order discount: -$${discount.toFixed(2)}`:'Add order discount'} -->

- [ ] WEB-UIUX-1241. **[MINOR] Reason input placeholder "e.g. Loyalty, damaged, etc." mixes title-case and lowercase — implies operator should type free-form variants. Reinforces WEB-UIUX-1233 cardinality problem.** `LeftPanel.tsx:958`. L13 string normalization.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:957-958`
  <!-- meta: fix=after-implementing-WEB-UIUX-1233-this-becomes-a-static-chip-list+if-keeping-free-text-show-Pick-from-loyalty/bulk/employee/damaged-or-type-custom -->

- [ ] WEB-UIUX-1242. **[MINOR] No visual link from the `Reason` field to the auto-required asterisk when amount > 0 — the asterisk only appears AFTER typing a non-zero amount.** `LeftPanel.tsx:949-953`. Operator who tabs to Reason first (because they thought of the reason before the amount) sees "Reason" without the asterisk, types nothing thinking it's optional, then Apply errors. The asterisk should toggle on amount-input, but with `requireReason && parseFloat(draftAmount) > 0` gate the parsed amount only updates on each keystroke; UI flickers. L7 form ergonomics.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:949-961`
  <!-- meta: fix=show-asterisk-whenever-requireReason+OR-show-helper-text-Reason-becomes-required-once-amount-is-entered -->

- [ ] WEB-UIUX-1243. **[MINOR] `manualDiscount` validation in `pos.routes.ts:1874` allows zero but not via the same code path as the rest — `ticketData?.discount ? validatePrice(...) : 0`.** Edge: a client sending the literal string `"0.00"` (truthy) goes through validatePrice (fine), but `0` (falsy) skips. Inconsistent with `tip` handling on the same form. L13 input contract.
  `packages/server/src/routes/pos.routes.ts:1874-1876`
  <!-- meta: fix=use-rawDiscount!=null?validatePrice(rawDiscount,'discount'):0+match-existing-tip-style -->

- [ ] WEB-UIUX-1244. **[MINOR] Closing the editor via the small X (`LeftPanel.tsx:927-934`) does NOT reset `draftAmount`/`draftReason`. Reopen shows last unsaved typing — could leak between sessions if cashier-A opens panel, walks away, cashier-B opens it.** Cart store-level reset on `resetAll()` clears `discount`/`discountReason`, but the local `draft*` state in DiscountEditor lives at the component level and survives across cart resets unless the component unmounts. L4 flow consistency, L13 multi-cashier hygiene.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:921-981`
  <!-- meta: fix=on-resetAll-also-reset-DiscountEditor-(via-effect-listening-on-cartItems.length===0)+OR-key-the-component-on-cartId-so-it-remounts-clean -->

- [ ] WEB-UIUX-1245. **[MINOR] `Math.max(manual, member)` server-side means a tiny manual discount + a tiny membership tier silently picks one — operator who deliberately wants both has no UX path. `stack_membership` server flag is exposed but no UI.** Discussed in WEB-UIUX-1228 from the silent-override angle; this is the inverse — an intentional power-user can't compose. L6 discoverability of advanced.
  `packages/server/src/routes/pos.routes.ts:1879-1881`
  <!-- meta: fix=expose-Stack-with-membership-checkbox-in-DiscountEditor-when-customer-has-active-tier+pass-stack_membership=true-in-buildTicketPayload-when-checked -->

- [ ] WEB-UIUX-1246. **[MINOR] `cartTotalCents` (`BottomActions.tsx:247-260`) for manager-PIN gate uses pre-discount line subtotal — does NOT subtract cart-wide `discount` value. Mathematically defensible (so an operator can't bypass via discount), but inconsistent with how the SAME total is displayed in `LeftPanel`'s totals (post-discount).** Two "cart total" definitions in same screen. L2 truthfulness, L13 internal consistency.
  `packages/web/src/pages/unified-pos/BottomActions.tsx:247-260`
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:1093-1106`
  <!-- meta: fix=rename-cartTotalCents-to-cartGrossSubtotalCents-to-clarify+document-the-policy-(intentional:-bypass-prevention)-in-comment+leave-math-as-is -->

#### Nit — visual polish

- [ ] WEB-UIUX-1247. **[NIT] Apply button color (teal-600) and Clear button (outline) have equal visual weight in the editor footer (`LeftPanel.tsx:963-979`) — Clear is a destructive (loses typing) but is no more conspicuous than a passive secondary.** L5 destructive distinguishability.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:963-979`
  <!-- meta: fix=Clear-color-text-red-600-border-red-300-when-discount>0+otherwise-treat-as-passive-Cancel-with-clear-affordance-Cancel-(no-changes) -->

- [ ] WEB-UIUX-1248. **[NIT] Discount green color (`LeftPanel.tsx:586`, `CheckoutModal.tsx:444`) is `text-green-600 dark:text-green-400` but the cart-wide pill (`LeftPanel.tsx:901`) uses `text-teal-600 dark:text-teal-400`. Inconsistent semantic color for the same concept across the same screen.** L5 hierarchy / palette.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:586,901`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:444`
  <!-- meta: fix=pick-one-(green-for-money-saved-is-the-retail-convention)+update-pill+line-discount-line+CheckoutModal-summary -->

- [ ] WEB-UIUX-1249. **[NIT] `Add discount` pill is rendered between Subtotal and Tax rows with smaller text and underline-on-hover — looks like a help-link, not a primary action. Operators in research often miss it.** `LeftPanel.tsx:895-919`. Compare cart-wide actions like the Customer pill which is full-width and bordered. L1 findability.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:895-919`
  <!-- meta: fix=upgrade-to-bordered-button-style-(matches-DiscountEditor-open-state)+OR-add-a-Tag-icon-and-keep-text-link-but-bump-to-text-sm-with-explicit-+icon -->

- [ ] WEB-UIUX-1250. **[NIT] `Apply` button in the editor uses `text-xs` while the input is `text-sm` — visual hierarchy inverted (action smaller than input).** `LeftPanel.tsx:973-977`. L5.
  `packages/web/src/pages/unified-pos/LeftPanel.tsx:963-980`
  <!-- meta: fix=text-sm-on-Apply-and-Clear+keep-input-text-sm+optionally-bump-Apply-to-font-semibold-text-sm-py-1.5 -->

### Web UI/UX Audit — Pass 23 (2026-05-05, flow walk: Time Clock Punch In/Out — list, PIN modal, server gates, location, recovery)

- [ ] WEB-UIUX-1251. **[MAJOR] Manager sees the green Clock-In / red Clock-Out button on every employee row and clicking a peer's button hits server 403 "Can only clock yourself in/out" — page is gated to `admin|manager` (`App.tsx:520`) but server only lets admins clock others (`employees.routes.ts:311`,`412`). UI has no role-or-self gate; manager hits the dead-end.** L3 route correctness, L4 flow completion.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:660-675`
  <!-- meta: fix=hide-or-disable-clock-button-when-currentUser.role!=='admin'-AND-currentUser.id!==employee.id+show-tooltip-"Only-admins-can-clock-others" -->

- [ ] WEB-UIUX-1252. **[MAJOR] No location selector in PIN modal even though server `clock-in` accepts `location_id` (`employees.routes.ts:381-389`). Web mutation never passes one (`EmployeeListPage.tsx:470,485`,`endpoints.ts:919-920`). Multi-location stores silently record every punch under `home_location_id` or `1` — wrong-location hours leak into the wrong payroll/commission bucket.** L4 flow completion, L7 feedback.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:469-505`
  `packages/web/src/api/endpoints.ts:919-920`
  <!-- meta: fix=add-location-select-in-PinModal-when-locations.count>1+default-to-home_location_id+pass-through-mutation-and-API-client -->

- [ ] WEB-UIUX-1253. **[MAJOR] Enter-key auto-submits PIN at length 4 (`EmployeeListPage.tsx:184`) but PIN is 4–6 digits. Worker with a 5- or 6-digit PIN typing fast triggers a wrong-PIN submit at digit 4, and server rate-limit is 5 attempts per 15 min (`employees.routes.ts:328`). Three accidental early-submits + two real mistypes = 15-min lockout in normal use.** L7 feedback, L8 recovery.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:183-185`
  <!-- meta: fix=remove-Enter-auto-submit-OR-debounce-300ms-after-last-keystroke-OR-only-auto-submit-when-pin.length===6-(max)+keep-explicit-Submit-button -->

- [ ] WEB-UIUX-1254. **[MAJOR] Active shift has no live-elapsed timer. Status column shows green dot + "Clocked In" only; expanded row shows "Active" badge with no duration (`EmployeeListPage.tsx:386-388`). Worker can't see "you've been on the clock for 4h 12m" — primary at-a-glance info for any time-clock UI.** L1 primary-action findability, L7 feedback.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:642-655,386-388`
  <!-- meta: fix=add-elapsed-counter-(now-clock_in)-next-to-status-pill+ticking-once-per-minute+also-render-in-expanded-Active-entry -->

- [ ] WEB-UIUX-1255. **[MAJOR] Auto-clock-out on stale shifts is silent. Server closes >16h-old open shifts on next clock-in (`employees.routes.ts:347-364`) and tags the entry `[auto-closed on clock-in]` — UI never surfaces this. Worker who forgot to punch out yesterday loses real hours and gets no notice; only a forensic look at expanded row's notes column reveals it (and the UI doesn't even render notes).** L7 feedback meaningful, L8 recovery.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:469-481`
  <!-- meta: fix=clock-in-success-handler-inspect-response-for-auto_closed_entry+toast-warning-"Previous-shift-was-auto-closed-after-16h+contact-manager-to-correct"+also-show-banner-on-row -->

- [ ] WEB-UIUX-1256. **[MAJOR] Clock-out toast says only "Clocked out successfully" (`EmployeeListPage.tsx:487`). Server returns `total_hours` (`employees.routes.ts:457,473`) — UI throws it away. Worker has zero confirmation of what was banked: shift duration, clock-in time, lunch deduction. Industry baseline is "Clocked out: 4h 32m logged".** L7 feedback meaning.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:484-496`
  <!-- meta: fix=onSuccess-read-data.data.total_hours-and-clock_in+toast.success(`Clocked-out-${formatHours(total_hours)}-(${formatTime(clock_in)}-→-${formatTime(now)})`)+similar-detail-on-clock-in -->

- [ ] WEB-UIUX-1257. **[MAJOR] PIN-required dead-end loop. When `has_pin=false`, modal title still reads "Clock In - John" (false promise) and copy says "Open Edit Employee and set a 4–6 digit PIN" (`EmployeeListPage.tsx:165-168`) — but there's no inline link, and Edit Employee lives at `/settings/users` which most non-admins can't access. Worker reads the warning, closes modal, has no path forward.** L2 label truthfulness, L4 flow completion.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:147,162-169`
  <!-- meta: fix=title="PIN-Required"-when-!has_pin+inline-link-(admin-only)-"Set-PIN-now"-→-/settings/users?employee=ID+for-non-admins-show-"Ask-an-admin-to-set-your-PIN" -->

- [ ] WEB-UIUX-1258. **[MAJOR] Header "Add Employee" button (`EmployeeListPage.tsx:515-521`) is a navigation to `/settings/users`, not an in-page form. Label promises action ("Add Employee"), reality is page transfer. Same surprise pattern flagged in past passes for other CTAs.** L2 label truthfulness, L3 route correctness.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:515-521`
  <!-- meta: fix=relabel-to-"Manage-Users-→"+ext-link-icon-OR-mount-the-Add-Employee-create-form-as-a-modal-on-this-page -->

- [ ] WEB-UIUX-1259. **[MAJOR] No employee search/filter on the list. Stores with 30+ staff make a kiosk worker scroll the entire table to find their row before clocking in. No filter by clocked-in/out, no search by name, no role filter.** L1 primary-action findability, L6 discoverability.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:531-570`
  <!-- meta: fix=add-search-input-(name+email)+role-chip-filter+status-filter-(clocked-in/out)+sticky-table-header -->

- [ ] WEB-UIUX-1260. **[MAJOR] List has no `refetchInterval` (`EmployeeListPage.tsx:459-462`). Worker who clocks in via mobile shows "Clocked Out" on this kiosk indefinitely; pressing Clock-In hits server 400 "Already clocked in" with no hint to refresh. Common multi-device confusion.** L7 feedback, L3 route correctness.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:458-466`
  <!-- meta: fix=refetchInterval:30000+also-on-window-focus-(default-on)+map-server-"Already-clocked-in"-error-to-toast-with-"Refresh"-action -->

- [ ] WEB-UIUX-1261. **[MAJOR] Notes field unreachable. Server clock-out accepts `notes` (`employees.routes.ts:410,461`). API client ignores it (`endpoints.ts:920` signature has only pin+location_id), and PIN modal has no textarea. Manager can't append "covered for sick teammate" or "client meeting ran late" — context lost.** L4 flow completion.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:113-225`
  `packages/web/src/api/endpoints.ts:920`
  <!-- meta: fix=add-optional-notes-textarea-in-PinModal-(only-for-clock-out)+pass-through-employeeApi.clockOut(id,pin,location_id,notes) -->

- [ ] WEB-UIUX-1262. **[MAJOR] Rate-limit lockout has no countdown. After 5 wrong PINs, server returns "Too many PIN attempts… Try again in 15 min" (`employees.routes.ts:329`); UI just toasts the string. No live countdown timer, no remaining-attempts indicator before lockout. Worker keeps retrying, server keeps rate-limiting, frustration spirals.** L7 feedback meaning, L8 recovery.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:478-481,492-495`
  <!-- meta: fix=parse-Retry-After-or-add-server-field-{lockedUntil}-→-render-countdown-in-modal+also-display-attempts-remaining-(N/5)-after-each-failed-attempt -->

- [ ] WEB-UIUX-1263. **[MINOR] Header subtitle "Manage technicians and staff" (`EmployeeListPage.tsx:513`) — page also lists cashiers, managers, admins. Tech-shop legacy language; misleads non-tech-shop tenants.** L2 label truthfulness.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:512-514`
  <!-- meta: fix="Manage-team,-time,-and-pay"-or-just-"Manage-team-members" -->

- [ ] WEB-UIUX-1264. **[MINOR] Pay-rate edit has no effective-date or history. After raising someone's rate (`PayRateEditor.commit`), the new value applies — but commissions table has its own per-record amounts, hours don't snapshot the rate, and prior pay calculations have no audit trail visible from this UI. Manager raised John from $18 → $20 mid-week; no way to confirm which rate the current pay-period uses.** L7 feedback meaning, L4 flow completion.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:227-315`
  <!-- meta: fix=show-"Effective-from-{today}"-on-save+keep-pay_rate_history-table-and-render-last-3-changes-in-expanded-row -->

- [ ] WEB-UIUX-1265. **[MINOR] Pay-rate validation accepts 0 (`EmployeeListPage.tsx:253` checks `rate! < 0` only). $0.00/hr is almost certainly a typo and silently zeros out future commissions/hours math. No confirm prompt for low values either ($0.01 typo).** L7 feedback meaning.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:250-258`
  <!-- meta: fix=warn-on-rate===0-with-confirm-"Set-pay-rate-to-$0.00?-Worker-will-not-accrue-hourly-pay."+also-warn-on-rate<5 -->

- [ ] WEB-UIUX-1266. **[MINOR] PIN input has no show/hide toggle (`EmployeeListPage.tsx:177-189` `type="password"`). Workers can't verify input before submit; with the 5-attempt cap, every mistype costs ~20% of their attempt budget.** L8 recovery.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:175-190`
  <!-- meta: fix=add-eye-icon-toggle-right-side-of-input+briefly-reveal-on-press-(2s)-or-toggle-with-state -->

- [ ] WEB-UIUX-1267. **[MINOR] `getWeekRange()` hardcodes Monday-start (`EmployeeListPage.tsx:85-95`). Stores running Sunday–Saturday or Saturday–Friday pay weeks see misaligned "Hours This Week" — number on this page won't match what payroll reports show.** L11 i18n / config awareness.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:85-104`
  `packages/server/src/routes/employees.routes.ts:201`
  <!-- meta: fix=read-store-setting-pay_week_start_day-(0-6)+derive-monday-offset-from-it+server-and-client-must-agree -->

- [ ] WEB-UIUX-1268. **[MINOR] Recent clock entries / commissions capped at 5 with no "View all" or "View timesheet" link (`EmployeeListPage.tsx:341-342`). To see anything past the last 5, user has to navigate elsewhere — unclear where. Discoverability gap.** L6 discoverability.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:359-432`
  <!-- meta: fix=add-"View-all-(N)-→"-link-under-each-list+target-/timesheets?user_id=X-or-/team/payroll -->

- [ ] WEB-UIUX-1269. **[MINOR] Empty-state copy "No clock entries yet. Use the clock in/out buttons above." (`EmployeeListPage.tsx:372`) — buttons are in the row's Actions column to the right, not "above". Spatial reference is wrong; on mobile (vertical stack) they may indeed be above, but on desktop they're inline-right.** L2 label truthfulness, L9 empty-state honesty.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:371-372`
  <!-- meta: fix="Use-the-Clock-In-button-on-the-row-header"-or-just-"No-clock-entries-yet." -->

- [ ] WEB-UIUX-1270. **[NIT] No bulk close-all action for end-of-day. Manager closing the shop has to expand each row, click Clock Out, type PIN, repeat — for every still-active worker who forgot. The 16-hour auto-close (`employees.routes.ts:115`) won't fire until tomorrow.** L6 discoverability, L7 feedback.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:531-570`
  <!-- meta: fix=admin-only-"End-of-Day"-button-→-confirm-modal-listing-active-workers-→-bulk-clock-out-with-manager-PIN-once -->

- [ ] WEB-UIUX-1271. **[NIT] PIN input lacks `aria-describedby` pointing at the "4–6 digit PIN" placeholder hint (`EmployeeListPage.tsx:177-189`). Screen-reader users hear only "Enter PIN" without the length constraint.** L10 a11y.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:172-190`
  <!-- meta: fix=add-id="pin-help"-on-a-helper-paragraph-"4-to-6-digit-PIN"+aria-describedby="pin-help"-on-input -->

- [ ] WEB-UIUX-1272. **[NIT] Clocked-in indicator is a 2.5px green dot (`EmployeeListPage.tsx:643-646`) — barely visible from across a room on a kiosk display. For a glanceable status, the dot should be ~3× larger or use a pill.** L5 visual hierarchy.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:642-655`
  <!-- meta: fix=h-3-w-3-or-h-4-w-4-dot+OR-replace-with-green-pill-"On-shift"-vs-gray-pill-"Off" -->

- [ ] WEB-UIUX-1273. **[NIT] Modal title "Clock In - John" omits last name (`EmployeeListPage.tsx:147`). Two staff with the same first name (small-team scenario) → ambiguous confirmation; worker can't tell whose timesheet they're about to punch.** L2 label truthfulness.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:146-148`
  <!-- meta: fix={first_name}-{last_name}-or-{first_name}-{last_name[0]}. -->

- [ ] WEB-UIUX-1274. **[NIT] Header X icon and footer Cancel/Close button do the same thing (`EmployeeListPage.tsx:149-151,195-200`). One dismiss is enough; two surface the same action twice. Footer action could become "Set PIN" / link to settings instead, recovering one slot for the dead-end case (see WEB-UIUX-1257).** L5 hierarchy.
  `packages/web/src/pages/employees/EmployeeListPage.tsx:149-151,195-200`
  <!-- meta: fix=keep-header-X-only+repurpose-footer-secondary-slot-for-context-action -->

### Web UI/UX Audit — Pass 24 (2026-05-05, flow walk: Process Refund — credit-note modal, /pos/return orphan, /refunds approval, stock + tax handling)

#### Blocker — flow dead-ends, financial data integrity

- [ ] WEB-UIUX-1275. **[BLOCKER] No UI surface for the entire `/refunds` workflow. Server has full create/approve/decline state machine (`refunds.routes.ts:107,253`), permission gates `refunds.create`/`refunds.approve`, card-method-aware caps, commission reversal — and zero web pages or buttons trigger it.** No `Refunds` route in `App.tsx`, no list page, no pending-approval queue, no admin approval UI. Pending refunds (status='pending') created via API have no human approval path. Permission tier accomplishes nothing if no workflow exposes it. L3 dead backend, L1 findability, L4 flow completion.
  `packages/server/src/routes/refunds.routes.ts:107-239,253-320`
  `packages/web/src/api/endpoints.ts` (no `refundsApi`)
  <!-- meta: fix=add-RefundsListPage-/refunds+RefundDetailPage-with-Approve/Decline-buttons-(admin-only)+sidebar-link-under-Billing+endpoints.ts-refundsApi.list/get/create/approve/decline -->

- [ ] WEB-UIUX-1276. **[BLOCKER] `/pos/return` (line-item return + stock restoration) is an orphan endpoint. Built `pos.routes.ts:2496` with admin-only gate, per-line quantity/reason, automatic inventory restoration via `stock_movements`, and credit-note generation — and ZERO web callers (`grep posApi.return` returns only the wrapper definition).** Manager who returns "1 of the 3 chargers from invoice INV-44" has no UI: forced to use the full-amount Credit Note modal which does NOT restore stock. Inventory shrinkage hidden, COGS skewed. L3, L4, L13 inventory integrity.
  `packages/server/src/routes/pos.routes.ts:2492-2637`
  `packages/web/src/api/endpoints.ts:753-761` (wrapper exists, no caller)
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx` (only Credit Note path)
  <!-- meta: fix=add-ReturnItemsModal-on-InvoiceDetailPage-with-line-item-checkboxes+per-line-quantity-input+RefundReasonPicker-shared+wire-posApi.return-with-idempotencyKey+gate-on-invoice.line_items.some(inventory_item_id) -->

- [ ] WEB-UIUX-1277. **[BLOCKER] Credit Note path silently does NOT refund tax. `invoices.routes.ts:1217` inserts the credit note with `total_tax: 0` while the original collected tax. Operator processing a $108 sale ($100 + $8 tax), refunding the full amount via Credit Note → ledger credits $100, customer expects $108. Either customer is short by the tax amount, or the cashier covers the gap from the till. State sales-tax filings then misreport collected vs. refunded tax.** L13 financial correctness, L7 truthful feedback, L4 flow completion.
  `packages/server/src/routes/invoices.routes.ts:1213-1230`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805` (modal hides this fact)
  <!-- meta: fix=server-derive-credit-tax-proportionally-(amount/total*total_tax)+credit-line-net+tax-separately+OR-explicit-toggle-Refund-tax-too-default-on+update-modal-summary-Net/Tax/Total -->

- [ ] WEB-UIUX-1278. **[BLOCKER] Credit Note posts immediately on click — no confirm step, no typed confirm, no undo window. Compare Void: typed confirm + 5s undo (`InvoiceDetailPage.tsx:807-817,109-135`).** A $5,000 fat-finger credit note has the same financial impact as voiding a $5,000 invoice and zero friction to reverse. The `creditNoteMutation` fires straight from the form's Submit button. L4 destructive-action protection, L8 recovery (none).
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177,795-801`
  <!-- meta: fix=wrap-handleCreditNote-in-useUndoableAction-(same-as-void)+OR-ConfirmDialog-with-amount-display-when-amount>$500+OR-typed-confirm-with-amount-string-for-amount>=invoice.total -->

#### Major — labels, routing, mental model

- [ ] WEB-UIUX-1279. **[MAJOR] CTA labeled "Credit Note" — operators say "process a refund". Two-second findability test fails: cashier scanning the action bar looking for refund sees Record Payment / Payment Plan / Print / Credit Note / Void. "Credit Note" is accounting-speak; "Refund" is the user mental model. Real-world POS operators (Square/Shopify field studies) hunt the word `refund` 9× more often than `credit note`.** L1 findability, L2 label truthfulness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`
  <!-- meta: fix=relabel-button-Refund-(keep-Credit-Note-as-modal-doc-name)+OR-split-into-two-CTAs-Refund-(cash-back)-vs-Issue-Credit-(store-credit) -->

- [ ] WEB-UIUX-1280. **[MAJOR] Single "Credit Note" CTA conflates three distinct outcomes the server supports: cash refund (`type='refund'`), store credit (`type='store_credit'`), credit note (`type='credit_note'`) — `refunds.routes.ts:18-19`. UI hardcodes the credit-note path (`InvoiceDetailPage.tsx:162` → `/invoices/:id/credit-note`). Operator who wanted "give the customer their card-charged money back" gets a ledger entry instead of a refund to the card. Customer calls back angry. Card-refund branch (`refunds.routes.ts:177-202`) is unreachable from this UI.** L1 findability, L3 wrong destination, L4 flow completion.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177,376-380`
  `packages/server/src/routes/refunds.routes.ts:107-239`
  <!-- meta: fix=Refund-modal-with-radio-group-type=refund_to_original|store_credit|credit_note+route-cash/card-refunds-through-/refunds+keep-/credit-note-only-for-explicit-doc-issuance -->

- [ ] WEB-UIUX-1281. **[MAJOR] No record of prior credit notes on the invoice page. Server enforces `priorCredits` aggregate (`invoices.routes.ts:1192-1202`); UI never shows them. Operator who already credited $50 against a $200 paid invoice sees identical UI to a never-credited invoice; tries to credit another $200; bounces on server reject "would exceed invoice total (already credited 50.00 of 200.00)". The Payment Timeline (`InvoiceDetailPage.tsx:475-548`) has no Credit Notes timeline.** L7 feedback meaningful, L9 missing prior-credit state.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:474-548`
  `packages/server/src/routes/invoices.routes.ts:1192-1202`
  <!-- meta: fix=add-Credit-Notes-section-OR-merge-into-Payment-Timeline-(query-invoices-where-credit_note_for=:id)+each-row-amount+date+CRN-link+update-Max-helper-amount_paid-already_credited -->

- [ ] WEB-UIUX-1282. **[MAJOR] "Max: $X.XX (amount paid)" helper (`InvoiceDetailPage.tsx:776-778`) lies after the first credit. UI reads `invoice.amount_paid` only; server caps at `amount_paid - prior_credits`. After a $30 credit on a $200 paid invoice, the modal still shows "Max: $200.00" until a hard refresh; operator types $200, gets server reject. Same bug echoes into `<input max>` (line 763) and the client-side cap check (lines 298-303).** L2 truthful display, L7 deferred error.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:298-304,763,766,776-778`
  <!-- meta: fix=server-include-credits_remaining-in-invoice-detail-payload+UI-read-it-as-the-cap+invalidate-cache-on-credit-note-success-(line-170-already-but-stale-modal-state-survives) -->

- [ ] WEB-UIUX-1283. **[MAJOR] After Credit Note creation, operator gets "Credit note created" toast but no link to the new credit note. The CRN-NNNN row exists, has a printable view, but the user has to navigate to the invoice list, filter for credit notes (no filter exists — see WEB-UIUX-1287), find it. Server returns the full credit-note record (`invoices.routes.ts:1316`); UI throws it away (`InvoiceDetailPage.tsx:172`).** L7 feedback meaning, L4 no document handoff.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-176`
  <!-- meta: fix=onSuccess-toast-with-action-View-credit-note-CRN-XXXX-→-/invoices/{cnId}+OR-prompt-Print/Email-credit-note-(mirror-Receipt-prompt) -->

- [ ] WEB-UIUX-1284. **[MAJOR] No print/email/SMS handoff for the credit-note customer copy. Compare the Receipt prompt that fires after Record Payment (`InvoiceDetailPage.tsx:676-734`) — Print / SMS / Email. Credit note has zero customer-facing artifact path. Customer leaves the counter with nothing in hand showing the refund.** L4 flow completion, L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:154-177`
  <!-- meta: fix=after-credit-note-success-fire-CreditNoteReceiptPrompt-with-Print/SMS/Email-mirroring-payment-prompt-but-credit-note-template -->

- [ ] WEB-UIUX-1285. **[MAJOR] No "Refund full balance" preset. Payment modal has "Pay full balance" quick-fill (`InvoiceDetailPage.tsx:618-621`); credit-note modal forces the operator to read `Max: $X` then type the amount. Common case (full refund) takes 8 keystrokes instead of 1.** L1 findability for common case, L7 ergonomics.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:756-779`
  <!-- meta: fix=add-Refund-full-amount-($amount_paid)-button-below-the-amount-input+matches-Pay-full-balance-style -->

- [ ] WEB-UIUX-1286. **[MAJOR] Credit Note modal doesn't warn when prior refunds exist via the separate `/refunds` POST path. The two paths (refunds vs credit-notes) maintain independent ledgers from the operator's POV — server's amount_paid clamp guards the math, not operator intent. A manager who already gave $50 cash back on Tuesday can issue a $50 credit note on Wednesday for the same complaint; only post-hoc forensic looks catch the duplication.** L4 flow completion, L13 audit clarity.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`
  `packages/server/src/routes/invoices.routes.ts:1162-1317`
  <!-- meta: fix=warning-banner-when-(prior_refunds+prior_credits)>0-Already-N-refund(s)-totaling-$X-against-this-invoice+Continue?-OR-block-when-resulting-total-clears-amount_paid -->

- [ ] WEB-UIUX-1287. **[MAJOR] Invoice list has no `credit_note` status tab/filter. `STATUS_TABS` (`InvoiceListPage.tsx:19-26`) lists All/Unpaid/Partial/Overdue/Paid/Void — `pos.routes.ts:2597` inserts credit notes with `status='credit_note'`, `invoices.routes.ts:1217` inserts with `status='paid'`. Two paths, two statuses, neither filterable. Bookkeeper looking up "all credit notes this month" has nowhere to click.** L1 findability, L6 discoverability, L13 internal consistency.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:19-26`
  `packages/server/src/routes/invoices.routes.ts:1217`
  `packages/server/src/routes/pos.routes.ts:2597`
  <!-- meta: fix=add-Credit-Notes-tab-(where-credit_note_for-IS-NOT-NULL)+normalize-server-to-emit-the-same-status-for-both-paths+filter-on-presence-of-credit_note_for-not-on-status-string -->

#### Major — flow gates / data integrity

- [ ] WEB-UIUX-1288. **[MAJOR] "Other" reason picker option (`RefundReasonPicker.tsx:23`) hint reads "Free-form reason in the note." but the note input is `(optional)` and never required when `code='other'`. Operator picks Other, leaves note empty, submits → server stores `code='other', note=null` → audit trail useless.** L7 truthful affordance, L13 audit value.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:23,82-92`
  <!-- meta: fix=when-localReason==='other'-make-note-required+aria-invalid+disable-Submit-until-non-empty+update-label-Notes-(required-for-Other) -->

- [ ] WEB-UIUX-1289. **[MAJOR] `RefundReasonPicker` keeps internal `localReason`/`localNote` state initialised from props ONLY at mount (`useState(value)`/`useState(note)`, lines 39-40). After parent's onSuccess `setCreditNoteForm({ ..., reason: null, note: '' })` (line 174), the picker's internal state still carries the last selection until the modal unmounts. Reopening the modal in the same lifecycle silently re-applies the prior choice.** L13 controlled-component contract violated.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:39-50`
  <!-- meta: fix=remove-internal-state-(use-value/note-props-directly)+OR-useEffect-syncing-on-value/note-prop-changes -->

- [ ] WEB-UIUX-1290. **[MAJOR] Reason picker missing the most-frequent retail reasons. REASONS array has 6 abstract codes (`RefundReasonPicker.tsx:17-24`); real-world refund logs cluster around: "Cancelled service / appointment", "Returned for exchange (no money back)", "Manager comp / goodwill", "Tax adjustment", "Shipping issue", "Loyalty / promo retroactive". Operators forced into Other + free-text → cardinality explodes, reports useless.** L13 reporting integrity.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:17-24`
  <!-- meta: fix=expand-REASONS-cancelled_service+exchange+goodwill+tax_adjustment+shipping+promo+keep-other-as-fallback+server-enum-validate-against-this-list -->

- [ ] WEB-UIUX-1291. **[MAJOR] Reason composed as `${code}: ${note}` AND sent both as `reason` AND structured `code`/`note` (`InvoiceDetailPage.tsx:158-167`). Server stores all three (`invoices.routes.ts:1180-1185,1224`). Reports keying on `reason` get pre-FA-L8 free-text rows AND new "code: note" rows mixed; reports keying on `code` lose pre-FA-L8 rows entirely. No back-fill migration. Reporting cardinality is still split.** L13 reporting integrity.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:158-168`
  `packages/server/src/routes/invoices.routes.ts:1180-1230`
  <!-- meta: fix=migration-back-fill-credit_note_code-from-reason-where-prefix-matches-known-code+drop-reason-or-derive-it-server-side-from-code+note -->

- [ ] WEB-UIUX-1292. **[MAJOR] Credit-note amount input `type=number max=amount_paid` is browser-advisory only. Pasting `99999` or arrow-keys past max does NOT clamp; only the manual JS check in `handleCreditNote` (`InvoiceDetailPage.tsx:298-303`) catches it on submit. Operator is rewarded with an error toast after typing — no inline bound enforcement, no live "exceeds max" hint.** L7 deferred error.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`
  <!-- meta: fix=onChange-clamp-to-Math.min(parsed,amount_paid)+inline-amber-helper-when-input-exceeds-max+disable-Submit-while-out-of-bounds -->

- [ ] WEB-UIUX-1293. **[MAJOR] No commission reversal on the credit-note path. `/refunds` PATCH approve calls `reverseCommission()` (`refunds.routes.ts:10`); `/invoices/:id/credit-note` does NOT. Tech who earned $40 commission on a $400 invoice that's then credit-noted keeps the $40; payroll-period lock never trips. Operator processing a returned-product credit note has no idea this is happening.** L13 ledger integrity, L7 silent side-effect.
  `packages/server/src/routes/invoices.routes.ts:1162-1317` (no commission reversal)
  `packages/server/src/routes/refunds.routes.ts:10` (vs. has it)
  <!-- meta: fix=server-credit-note-route-call-reverseCommission-proportionally+OR-warn-in-modal-Credit-notes-do-not-reverse-tech-commissions+document-policy -->

- [ ] WEB-UIUX-1294. **[MAJOR] No idempotency key on `createCreditNote` POST (`endpoints.ts:297-298`). Compare `recordPayment` (lines 285-293) and `posApi.return` (lines 753-761) which both add `X-Idempotency-Key`. Double-click on slow network → two credit notes against the same invoice. Server's prior-credits aggregate guards the math (line 1197), but the second insert still creates a second CRN row + audit entry + broadcast — orphan record.** L8 recovery.
  `packages/web/src/api/endpoints.ts:295-298`
  <!-- meta: fix=add-X-Idempotency-Key-header-(crypto.randomUUID-fallback)+wrap-credit-note-route-with-idempotent-middleware-server-side -->

- [ ] WEB-UIUX-1295. **[MAJOR] Card-method routing missing. When the original payment was on a BlockChyp terminal (`processor_transaction_id` set, `InvoiceDetailPage.tsx:203-205`), the natural refund path is to send the credit BACK to the original card. UI offers no terminal-refund button; operator with a $300 card sale + customer in front of them has no way to push the refund through the terminal. They click Credit Note → ledger only. Customer leaves with no money on the card.** L1 findability, L4 flow completion.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:203-205,376-380`
  <!-- meta: fix=if-cardPaymentWithTxn-add-Refund-to-Card-($amount-on-card-XXXX)-button+wire-blockchypApi.processRefund-(stub-if-not-yet-implemented)+otherwise-warn-Card-refund-not-available -->

- [ ] WEB-UIUX-1296. **[MAJOR] No partial-line-item picker — credit-note modal accepts only a free-form total amount. To return 1 of 3 phone cases ($25 each on a $75 line), operator types $25, but the line items table still shows "qty 3"; stock untouched; no reference to the specific item being returned. Compare orphan `/pos/return` (per-line, with stock restoration).** L1 findability of the right primitive, L4 flow completion.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:737-805`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:425-450` (line items table is read-only)
  <!-- meta: fix=checkboxes+qty-spinners-on-line-items-table-when-modal-open+derive-amount-from-selection+post-to-/pos/return+amount-only-mode-fallback-for-non-product-invoices -->

#### Minor — modal copy, validation, focus

- [ ] WEB-UIUX-1297. **[MINOR] Modal title "Create Credit Note" but body copy says "This will reduce the outstanding balance" (`InvoiceDetailPage.tsx:753-755`). Misleading on a fully-paid invoice — there IS no outstanding balance; the credit accumulates as store-credit overflow (`invoices.routes.ts:1259-1302`). Operator reading the description thinks "this lowers what they owe" when it actually creates store credit.** L2 label truthfulness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:753-755`
  <!-- meta: fix=conditional-copy-amount_due>0-current-text+amount_due===0-"This-will-be-recorded-as-store-credit-on-the-customer's-account." -->

- [ ] WEB-UIUX-1298. **[MINOR] Store-credit overflow path (`invoices.routes.ts:1248-1302`) is server-only; UI never tells the operator the credit went to the customer's store-credit balance. Customer gets no heads-up either. Operator can't answer "where did the $50 overflow go" without DB access.** L7 feedback meaning.
  `packages/server/src/routes/invoices.routes.ts:1248-1302`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-176`
  <!-- meta: fix=server-return-credit_overflow+store_credit_balance-in-response+UI-onSuccess-toast/banner-$X-applied-to-balance,-$Y-added-to-store-credit-(now-$Z) -->

- [ ] WEB-UIUX-1299. **[MINOR] `formatCurrency` used in error toast (`InvoiceDetailPage.tsx:302`) but raw `.toFixed(2)` in helper text (line 766, 777) and placeholder. Tenant currency (€, £) shows as "$" in 2 of 3 spots in the same modal.** L13 i18n consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:766,777`
  <!-- meta: fix=replace-.toFixed(2)-with-formatCurrency-everywhere-in-modal+drop-hardcoded-$-prefix-on-input-(use-currency-symbol-from-formatCurrency)-or-keep-$-and-be-explicit-USD-only -->

- [ ] WEB-UIUX-1300. **[MINOR] Submit button label "Create Credit Note" (`InvoiceDetailPage.tsx:799-800`) doesn't include the amount. Compare Payment terminal button (line 655) which does ("Pay $X.XX via Terminal"). Confirmation-on-the-button reduces fat-finger commits — operator sees the dollar value at the click target.** L7 feedback at decision moment.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-801`
  <!-- meta: fix=label=`Issue ${formatCurrency(parseFloat(amount)||0)} credit note`-when-amount>0+default-Create-Credit-Note-when-empty -->

- [ ] WEB-UIUX-1301. **[MINOR] Amount input has no auto-format on blur. Operator types `100` → stays `100`, not `100.00`; no `$` echo until tab-out — and even then nothing changes. A typed `1000` is way easier to mistake for `100.00` than `1,000.00`.** L7 input ergonomics.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`
  <!-- meta: fix=onBlur-format-amount-via-Number().toFixed(2)+thousands-separator-via-formatCurrency-stripping-symbol -->

- [ ] WEB-UIUX-1302. **[MINOR] No keyboard trap inside modal. Tab from the last button reaches the page behind. Modal is `role="dialog" aria-modal="true"` (line 740-742) but no focus trap implementation.** WCAG 2.4.3 / 2.4.7. L11 a11y.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:738-805`
  <!-- meta: fix=use-FocusTrap-or-headlessui-Dialog-(or-mirror-existing-modal-pattern-on-this-page-if-trapping)+restore-focus-to-trigger-on-close -->

- [ ] WEB-UIUX-1303. **[MINOR] Reason chips wrap into 2 columns (`RefundReasonPicker.tsx:62`) but the longer "Customer dissatisfied" + "Duplicate charge" labels overflow the chip on small viewports (no min-width, no truncate). Causes wrap-mid-word visual.** L5 visual hierarchy.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:62-78`
  <!-- meta: fix=grid-cols-1-md:grid-cols-2+OR-truncate-with-title-attr+OR-shorten-labels-Defective/Dissatisfied/Wrong-item/Dup-charge/Price-adj/Other -->

- [ ] WEB-UIUX-1304. **[MINOR] Credit Note button shown even when `amount_paid === 0` (an unpaid invoice with `total > 0`). The condition is `invoice.status !== 'void' && Number(invoice.total) > 0` (`InvoiceDetailPage.tsx:376`). Server rejects because amount > amount_paid — but only on submit. The button promises an action that's impossible to complete.** L1 findability of disabled state.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380`
  <!-- meta: fix=condition-also-Number(invoice.amount_paid)>0+OR-show-button-disabled-with-tooltip-No-payments-yet—nothing-to-credit -->

- [ ] WEB-UIUX-1305. **[MINOR] Backdrop click closes the modal even when the form has unsaved typing (amount/reason/note). No "Discard?" prompt. Operator who wrote a 200-char detailed note + accidentally clicks the backdrop → all gone.** L8 recovery.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:744`
  <!-- meta: fix=on-backdrop-click-if-amount||reason||note-then-window.confirm-Discard-credit-note-draft?+otherwise-close-immediately -->

- [ ] WEB-UIUX-1306. **[MINOR] No max-amount visual progress / use-up indicator. Operator typing $50 of $200 max sees raw text only; an `$50 / $200` bar or "remaining-after-this" would help (esp. avoid the surprise of "this will leave $0 due"). Common in Stripe/Shopify refund modals.** L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-779`
  <!-- meta: fix=below-input-add-After-this-credit-balance-$X+remaining-creditable-$Y+slim-bar-amount/max-percent -->

- [ ] WEB-UIUX-1307. **[MINOR] `payments` timeline ignores credit notes — credit notes are separate invoice rows, not payment rows. Original invoice's payment timeline never shows "Credit note CRN-0001 issued $50". Bookkeeper toolkit gap.** L7 feedback meaning.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:474-548`
  <!-- meta: fix=fetch-credit-notes-where-credit_note_for=:id-and-merge-into-the-timeline-with-distinct-icon+sort-by-created_at -->

#### Nit — visual polish

- [ ] WEB-UIUX-1308. **[NIT] Submit button colour is amber (`bg-amber-600`, line 798). Amber typically signals warning/caution; in this app destructive (Void) uses red, primary (Record Payment) uses primary, credit-note uses amber — unique-snowflake. Either it's destructive (red) or primary (primary-600). Amber leaves the operator unsure.** L5 hierarchy.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:798`
  <!-- meta: fix=pick-one-(red-if-destructive-treatment+primary-if-routine)+document-colour-policy-in-styleguide -->

- [ ] WEB-UIUX-1309. **[NIT] Header has Print/Void/Credit Note/Payment Plan/Financing — a 5+ button row that crowds on smaller viewports. Rare actions (Credit Note, Void) should live in a `…` overflow menu; common-and-frequent (Record Payment) front-and-centre.** L5 hierarchy, L1 primary action.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:342-389`
  <!-- meta: fix=keep-Record-Payment+Print-in-header+wrap-Void+Credit-Note+Payment-Plan-into-Kebab-More-actions-menu -->

- [ ] WEB-UIUX-1310. **[NIT] No screen-reader announcement on success. Toast is visual only; `aria-live` region not present. SR users issuing a refund hear nothing.** L11 a11y.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:172`
  <!-- meta: fix=mount-aria-live=polite-region-rendering-last-toast-text+OR-verify-react-hot-toast-emits-role=status -->

- [ ] WEB-UIUX-1311. **[NIT] Modal X close (line 749) and Cancel (line 792) coexist; same outcome. Pick one — common pattern: keep header X (mouse) and either remove footer Cancel or repurpose it.** L5 redundancy.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:749,792`
  <!-- meta: fix=remove-footer-Cancel+widen-Submit-OR-remove-header-X-(more-keyboard-friendly) -->

- [ ] WEB-UIUX-1312. **[NIT] No analytics / dashboard tile for refund volume. Server has the data; UI surfaces nothing. Manager asking "why are returns up this month" has no in-app answer.** L6 discoverability of insights.
  `packages/server/src/routes/refunds.routes.ts:74-95` (data)
  `packages/web/src/pages/dashboard/DashboardPage.tsx` (no refund tile)
  <!-- meta: fix=Refunds-this-week-tile-on-dashboard+drilldown-to-Refunds-page-(see-WEB-UIUX-1275)+top-3-reason-codes-bar -->

- [ ] WEB-UIUX-1313. **[NIT] Title "Create Credit Note" (line 748) uses Save-style verb. "Create" suggests drafting; the action is irrevocable issuance. "Issue Credit Note" is the bookkeeping verb-of-art and matches permanence.** L2 truthful label.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:748`
  <!-- meta: fix=Issue-Credit-Note-(modal-title+submit-button)+document-as-final-not-draft -->

- [ ] WEB-UIUX-1314. **[NIT] `min="0.01"` on amount input (line 763) prevents 0 client-side, but the helper text never communicates the minimum to the operator. A typed 0 silently rejected via `parseFloat || 0` flow on submit.** L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`
  <!-- meta: fix=helper-text-Min-$0.01-Max-$X-(amount-paid)+OR-disable-Submit-while-input<0.01 -->

### Web UI/UX Audit — Pass 25 (2026-05-05, flow walk: Schedule Appointment — calendar create, lead/customer entry, edit/cancel recovery, server gaps)

Flow walked: nav → Calendar (`/leads/calendar`) → "New Appointment" → fill form → submit → click pill in grid → AppointmentDetailModal. Alt entry: Ticket detail → AppointmentsCard. Lead detail page reviewed for missing entry. Server route `POST /leads/appointments` cross-checked.

- [ ] WEB-UIUX-1315. **[BLOCKER] CreateAppointmentModal has no customer or lead picker. Server INSERT (`leads.routes.ts:590-603`) stores `customer_id` and `lead_id`; form (`CalendarPage.tsx:211-221`) collects neither and `endpoints.ts:876` ignores them. Every appt created from /leads/calendar is an orphan — staff books "Screen repair consultation 2pm" with no customer attached, then can't tie it back when the person walks in.** L1 primary action, L4 flow completion.
  `packages/web/src/pages/leads/CalendarPage.tsx:211-221,309-316`
  `packages/web/src/api/types.ts:436-442`
  <!-- meta: fix=add-Customer-typeahead+optional-Lead-typeahead+pass-customer_id+lead_id-in-payload+extend-CreateAppointmentInput-with-both -->

- [ ] WEB-UIUX-1316. **[BLOCKER] No edit, reschedule, cancel, or mark-no-show path anywhere in UI. `leadApi.updateAppointment` and `leadApi.deleteAppointment` (`endpoints.ts:877-878`) exist; **zero call sites** in `packages/web/src`. AppointmentDetailModal (`CalendarPage.tsx:82-173`) is read-only — no buttons. Once created, status frozen at "scheduled" forever; customer reschedule = staff has to recreate (and orphan the old one since they can't delete it either).** L8 recovery, L4 flow completion.
  `packages/web/src/pages/leads/CalendarPage.tsx:82-173`
  `packages/web/src/api/endpoints.ts:877-878`
  <!-- meta: fix=add-Edit/Reschedule/Cancel/Mark-No-show-buttons-in-AppointmentDetailModal+wire-updateAppointment+deleteAppointment+confirm-modal-on-cancel/delete -->

- [ ] WEB-UIUX-1317. **[BLOCKER] LeadDetailPage shows appointments list (`LeadDetailPage.tsx:711-745`) but has NO "Schedule Appointment" button. Staff opens lead "John Doe — Sony A7 repair quote", sees "0 appointments", and has zero affordance to book one without leaving for /leads/calendar (which then can't pre-fill the lead — see WEB-UIUX-1315). Primary CRM action invisible on the very page where intent is highest.** L1 findability, L6 discoverability.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:711-745`
  <!-- meta: fix=Schedule-button-in-Appointments-card-header+open-CreateAppointmentModal-pre-filled-with-lead_id+route-back-to-lead-on-success -->

- [ ] WEB-UIUX-1318. **[BLOCKER] Appts outside `DEFAULT_HOURS` (7am–7pm) silently invisible in DayView/WeekView. DayView filter (`CalendarPage.tsx:632,637`) and WeekView (`589-592`) match against `hours[]`; an appt at 06:30 or 20:00 disappears with no "+1 hidden" indicator. MonthView shows them; week/day don't. Staff trusting week view will double-book a tech who's already booked at 6am.** L4 flow, L7 feedback, L9 empty/loading honesty.
  `packages/web/src/pages/leads/CalendarPage.tsx:583-616,621-674`
  <!-- meta: fix=show-out-of-hours-band-collapsed-(N-before-7am,-M-after-7pm)+expand-on-click+OR-auto-expand-hours-to-cover-min/max-actual-appts -->

- [ ] WEB-UIUX-1319. **[MAJOR] Server returns `warning: "Technician already has an appointment at this time"` on create (`leads.routes.ts:584-587,685-687`). Client `onSuccess` (`CalendarPage.tsx:238-244`) only toasts "Appointment created" — drops the warning field. User clicks past the local overlap warning, server detects same conflict on the authoritative full-DB scan, and the heads-up is silently discarded.** L7 feedback meaning.
  `packages/web/src/pages/leads/CalendarPage.tsx:236-244`
  <!-- meta: fix=onSuccess-read-data.warning+toast.error/warning(warning)-when-present+keep-success-toast-only-when-no-warning -->

- [ ] WEB-UIUX-1320. **[MAJOR] Server supports `recurrence` (weekly/biweekly/monthly) and auto-creates 4 occurrences (`leads.routes.ts:609-680`); response includes `recurring_ids[]`. Form has NO recurrence field. Manager who wants "weekly therapy follow-up" has to manually create 5 separate appts. Existing customers booking recurring service silently get only one slot. Hidden feature behind no UI affordance.** L6 discoverability, L4 flow completion.
  `packages/web/src/pages/leads/CalendarPage.tsx:211-221,309-316`
  <!-- meta: fix=add-Repeat-select-(none/weekly/biweekly/monthly)+show-summary-"Will-create-5-appointments-(today+4-weekly)"+toast-after-success-using-recurring_ids.length+1 -->

- [ ] WEB-UIUX-1321. **[MAJOR] Server supports `location_id` (`leads.routes.ts:537-547,602`); form omits it → defaults to 1 always. Multi-location shop can't book at branch B from calendar, and reports filtered by location will show zero at every branch except #1.** L3 route correctness, L4 flow.
  `packages/web/src/pages/leads/CalendarPage.tsx:309-316`
  <!-- meta: fix=Location-select-in-modal+default-to-current-active-location-from-locationContext+pass-location_id-in-payload -->

- [ ] WEB-UIUX-1322. **[MAJOR] `defaultDate` initializer uses `toISOString().slice(0, 10)` (`CalendarPage.tsx:209`) — UTC date, not local. PST user clicking "+New Appointment" at 5pm on Dec 31 gets the form pre-filled with **Jan 1**. Same off-by-one fires for any non-UTC user at edge hours. Bookings land on wrong day if user submits without re-checking date.** L3 route correctness, L7 feedback.
  `packages/web/src/pages/leads/CalendarPage.tsx:209`
  <!-- meta: fix=use-local-YYYY-MM-DD-(date.getFullYear()/getMonth()+1/getDate()-padded)+OR-toLocaleDateString('sv-SE')-which-emits-ISO-in-local-tz -->

- [ ] WEB-UIUX-1323. **[MAJOR] `useState({...start_date: dateStr, ...})` initializer (`CalendarPage.tsx:211-221`) captures defaultDate ONCE on mount. Modal mounts globally because `<CreateAppointmentModal open={showCreate}>` is always rendered (`CalendarPage.tsx:881-887`); user navigates calendar to next month → opens modal → form still pre-fills the FIRST month they viewed. Off-by-N silent date error.** L7 feedback, L4 flow.
  `packages/web/src/pages/leads/CalendarPage.tsx:209-221,881-887`
  <!-- meta: fix=move-form-state-init-into-useEffect-on-[open,defaultDate]+OR-conditionally-render-modal-(unmount-on-close)-so-init-runs-each-time -->

- [ ] WEB-UIUX-1324. **[MAJOR] `existingAppointments` passed to overlap check (`CalendarPage.tsx:200-206,256-271`) is the current viewport only (month/week/day window from `dateRange` query). Booking on the last day of viewed month against an appt on the first day of next month: client says all clear. Server warning catches some, but #1319 throws that away anyway. False sense of safety on every cross-window booking.** L7 feedback meaning.
  `packages/web/src/pages/leads/CalendarPage.tsx:256-271,727-733`
  <!-- meta: fix=fetch-±1-week-buffer-around-target-time-on-modal-open-(or-on-time-change)+server-side-precondition-check-already-correct,-just-surface-warning-(see-WEB-UIUX-1319) -->

- [ ] WEB-UIUX-1325. **[MAJOR] Status select in CreateAppointmentModal (`CalendarPage.tsx:396-405`) lists scheduled/confirmed/completed/cancelled — missing `no-show`, even though STATUS_COLORS keys it (`line 39`) and server audit logs `appointment_no_show` events (`leads.routes.ts:734`). Combined with #1316 (no edit), once a customer is a no-show there is **no UI path** to flag it; the field stays unfilled forever, breaking attendance reports and recurrence churn analysis.** L4 flow, L6 discoverability.
  `packages/web/src/pages/leads/CalendarPage.tsx:396-405`
  <!-- meta: fix=add-No-show-option+also-expose-via-edit-modal-(WEB-UIUX-1316)+server-PUT-already-supports-no_show-flag -->

- [ ] WEB-UIUX-1326. **[MAJOR] TicketSidebar "Schedule appointment" trigger is a 14px `<CalendarPlus>` icon-only button (`TicketSidebar.tsx:289-295`) labeled only via `title="Schedule appointment"`. Touch users (tablet at front desk) miss the affordance entirely; mobile keyboard-only users get no `aria-label` (only `title=`, which most SRs read inconsistently). Primary scheduling action on ticket page is functionally hidden.** L1 findability, L6 discoverability, L11 a11y (16-lens).
  `packages/web/src/pages/tickets/TicketSidebar.tsx:289-295`
  <!-- meta: fix=replace-with-text-button-"+ Schedule"+aria-label+min-32px-hit-target+OR-keep-icon-but-add-visible-label-on-hover/focus -->

- [ ] WEB-UIUX-1327. **[MAJOR] MonthView "+N more" (`CalendarPage.tsx:528-530`) is a `<p>` element, not a button. Day with 4+ appts: 4th, 5th… Nth invisible AND no path to view them — except switching to day view manually and remembering the date. Discoverability dead-end.** L6 discoverability, L8 recovery.
  `packages/web/src/pages/leads/CalendarPage.tsx:528-530`
  <!-- meta: fix=button+onClick-switch-to-day-view-on-that-date+OR-popover-listing-all-day-appts -->

- [ ] WEB-UIUX-1328. **[MAJOR] No click-to-create on calendar grid. MonthView day cells (`483-538`), WeekView slots (`588-613`), DayView slots (`641-672`) ignore clicks. Every booking flows through "New Appointment" button → form pre-filled 9:00–10:00 → user manually re-types date+time. Industry-standard calendar UX (Google/Outlook/Cal.com) is click-an-empty-slot-to-create. Forced friction on the most common action.** L1 findability, L4 flow completion, L6 discoverability.
  `packages/web/src/pages/leads/CalendarPage.tsx:483-538,557-617,621-674`
  <!-- meta: fix=onClick-on-empty-cell-opens-CreateAppointmentModal-with-pre-filled-date-(month)-or-date+hour-(week/day)+drag-to-select-range-for-end-time -->

- [ ] WEB-UIUX-1329. **[MAJOR] Empty state (`CalendarPage.tsx:864-869`) renders BELOW the calendar grid even though grid is also rendered when 0 appts. User sees an empty grid PLUS a centered "No appointments in this period" — confusing dual layout, looks like a render bug. No CTA to create one from the empty state either.** L9 empty state, L1 findability.
  `packages/web/src/pages/leads/CalendarPage.tsx:830-869`
  <!-- meta: fix=replace-grid-when-month-view-and-0-appts+OR-keep-grid-but-make-empty-msg-an-overlay-banner-with-"+ Schedule one"-CTA -->

- [ ] WEB-UIUX-1330. **[MINOR] Form default end-time stays "10:00" regardless of start-time. Pick start 18:00 → submit blocked with toast "End time must be after start time" (`CalendarPage.tsx:296-298`) until user manually edits. Should auto-set end = start + 1h on start change.** L7 feedback, L4 flow.
  `packages/web/src/pages/leads/CalendarPage.tsx:340-378`
  <!-- meta: fix=onChange-of-start-fields-set-end-=-start+60min-when-end-is-still-default-or-<=-start -->

- [ ] WEB-UIUX-1331. **[MINOR] `CreateAppointmentInput` type (`api/types.ts:436-442`) lacks `title`, `status`, `customer_id`, `recurrence`, `location_id` — yet client payload sends `title` and `status`, and server accepts all five (`leads.routes.ts:537,590-603`). TS excess-property check passes via wider param shape; type drifts away from API surface. Future devs reading the type assume those fields don't exist.** L6 discoverability (for devs).
  `packages/web/src/api/types.ts:436-442`
  `packages/web/src/pages/leads/CalendarPage.tsx:227-234,309-316`
  <!-- meta: fix=extend-CreateAppointmentInput+UpdateAppointmentInput-to-include-title?+status?+customer_id?+recurrence?+location_id?+no_show? -->

- [ ] WEB-UIUX-1332. **[MINOR] AppointmentDetailModal title field (`CalendarPage.tsx:118`) shows "Untitled" when blank; LeadDetailPage appt list (`LeadDetailPage.tsx:723`) shows blank-string with no fallback. Same record renders differently in two surfaces — operator confused which is the real label.** L7 feedback consistency.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:723`
  <!-- meta: fix=apply-`a.title || 'Untitled'`-fallback-everywhere-OR-make-server-reject-empty-title-(currently-defaults-to-''-`leads.routes.ts:595`) -->

- [ ] WEB-UIUX-1333. **[MINOR] No timezone display on calendar header or appt detail. Multi-location org with branches in different TZs sees "10:00 AM" with no tz suffix; manager looking at LA appt from NYC reads it as ET. Server stores TZ-tagged ISO (`toISOWithOffset` in client, raw string from server response then re-parsed in browser local TZ).** L7 feedback meaning.
  `packages/web/src/pages/leads/CalendarPage.tsx:122-128,765-771`
  <!-- meta: fix=show-current-tz-abbrev-(e.g.-PST)-in-header+show-on-appt-detail-row+future-add-location-tz-override-when-location_id-supports-it -->

- [ ] WEB-UIUX-1334. **[MINOR] "Today" button (`CalendarPage.tsx:801-806`) jumps date but doesn't change view. User in month view clicks Today on Mar 5 → still month view. If user just glanced at the wrong week, they expected day-jump-to-today behavior. No `aria-pressed` either when current date == today.** L7 feedback, L11 a11y.
  `packages/web/src/pages/leads/CalendarPage.tsx:749,801-806`
  <!-- meta: fix=Today-resets-date-only-(current-behavior-OK)+add-aria-current="date"-when-relevant+OR-click-Today-twice-toggles-to-day-view -->

- [ ] WEB-UIUX-1335. **[NIT] Status badge `capitalize` class (`CalendarPage.tsx:132`) only capitalizes first letter; renders "no-show" → "No-show" (acceptable) but breaks if status ever has multi-word like "in-progress" → "In-progress" (only first letter). Pre-format display text from a label map instead.** L11 polish.
  `packages/web/src/pages/leads/CalendarPage.tsx:132-137`
  <!-- meta: fix=STATUS_LABELS-map-(scheduled→Scheduled,no-show→No-Show)+drop-capitalize-class -->

- [ ] WEB-UIUX-1336. **[NIT] No SMS/email confirmation toggle on create. If server auto-sends confirmation (per location settings), staff has no way to opt out for internal-only blocks. If server doesn't, staff has no way to send. Either way, opaque.** L7 feedback, L6 discoverability.
  `packages/web/src/pages/leads/CalendarPage.tsx:288-440`
  <!-- meta: fix=checkbox-"Send-SMS-confirmation-to-customer"-(default-on-when-customer-selected)+wire-server-to-honor-flag -->

### Web UI/UX Audit — Pass 26 (2026-05-05, flow walk: Convert Lead to Ticket — detail button, status pill, pipeline drop, reminders, dedupe)

Walk: lead detail "Convert to Ticket" green CTA → confirm() → POST /leads/:id/convert (creates customer + ticket + flips status) → toast → navigate /tickets/:id. Parallel paths: (a) status-pill picker on detail page sets `status='converted'` via PUT /:id, (b) pipeline kanban "Move to Converted" menu also calls PUT /:id. Server PUT only checks transition legality (`proposal → converted` allowed) — DOES NOT call the convert handler. Both bypass paths leave the lead orphan-converted with NO ticket, NO customer, NO audit. Confirm-copy hides the customer-creation side effect. Detail-page error handler swallows server messages (tier-limit upgrade nudge, bad email, missing customer info → all collapse to "Failed to convert"). Reminders pinned to lead never migrate to the new ticket. Convert silently dupes customers when phone/email already exist.

- [ ] WEB-UIUX-1337. **[BLOCKER] Two ghost paths to "converted" status that DO NOT create a ticket. (1) Detail page status-pill picker (`LeadDetailPage.tsx:358-379`) — clicking the "converted" pill calls `scheduleStatusChange('converted', from)` → `leadApi.update({status:'converted'})` → PUT /leads/:id. PUT only enforces `assertLeadTransition` (`leads.routes.ts:850-852`); `proposal → converted` is legal (line 36) so the write succeeds with NO ticket, NO customer, NO `lead_converted` audit. (2) Pipeline kanban "Move to Converted" (`LeadPipelinePage.tsx:148-161`, handler `:283-293`) — same path. Lead now shows green "Converted" badge, Convert-to-Ticket button hidden (`LeadDetailPage.tsx:397`), no ticket exists. Operator believes work is filed; nothing downstream fires. The Lost path was carefully gated (FA-M25 comment lines 13-19 skips Lost from kanban because it needs a reason) — Convert is equally side-effecting and is left wide open.** L2 truthful action, L3 wrong destination, L4 broken flow, L5 hierarchy mismatch with Lost gating.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:358-379`
  `packages/web/src/pages/leads/LeadPipelinePage.tsx:20-27,148-161,283-293`
  `packages/server/src/routes/leads.routes.ts:36,818-903,1001-1136`
  <!-- meta: fix=server-side-PUT-/:id-must-reject-status='converted'-(force-callers-to-use-/convert-handler)+detail-pill-picker-and-pipeline-move-menu-special-case-'converted'-like-'lost'-(open-confirm/route-to-convert-mut)+remove-'converted'-from-PIPELINE_STAGES-OR-make-the-drop-trigger-the-real-convert-handler -->

- [ ] WEB-UIUX-1338. **[MAJOR] Detail-page convert mutation swallows every server error message. `LeadDetailPage.tsx:205` is `onError: () => toast.error('Failed to convert')` — discards `err.response.data.message`. Server returns rich, actionable text: tier-limit "Monthly ticket limit reached (50/50). Upgrade to Pro for unlimited tickets." (`leads.routes.ts:1044-1054`, `upgrade_required:true`), `Cannot convert lead without customer information` (`:1082`), `Lead already converted` (`:1013`), state-machine reject (`:1015`), email/phone validation throws from `:1068-1069`. All collapse to the same generic toast. Operator has no idea whether to (a) buy a plan, (b) fix the lead's email, (c) refresh the page, or (d) call support. LeadListPage already does this correctly (`:425-430`) — copy that handler.** L7 feedback meaningfulness (worst lens fail of the flow), L8 recovery.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:197-206`
  `packages/server/src/routes/leads.routes.ts:1013,1015,1044-1054,1068-1069,1082`
  <!-- meta: fix=copy-LeadListPage-onError-pattern-(extract-formatApiError)+special-case-upgrade_required:true-to-route-user-to-/billing-with-CTA-button-in-toast -->

- [ ] WEB-UIUX-1339. **[MAJOR] No customer dedupe at convert time → silent duplicate customer rows. `leads.routes.ts:1063-1080` only branches on `!customerId` — when the lead has no `customer_id` link it INSERTs a fresh customer with the lead's first/last/email/phone, no lookup against existing rows. Real flow: web form submits a lead for "jane@acme.com" who is already a customer; staff convert without manually linking; second customer record now exists with same email. Customer Create page does duplicate detection (`CustomerCreatePage.tsx:64,371-378`) — convert flow doesn't. Pollutes loyalty, marketing dedupe, support history. Server has no UNIQUE on customers.email/phone either (UI accepts, downstream merge needed).** L4 flow correctness, L7 feedback (no "this email already exists, link to Customer #123?" branch).
  `packages/server/src/routes/leads.routes.ts:1063-1080`
  `packages/web/src/pages/customers/CustomerCreatePage.tsx:64,371-378`
  <!-- meta: fix=convert-handler-SELECT-customers-WHERE-email=?-OR-phone=?-LIMIT-1-before-INSERT+if-match-return-{found:true,customer_id,name}+UI-presents-link-or-create-new-choice -->

- [ ] WEB-UIUX-1340. **[MAJOR] Lead reminders orphaned by convert. Lead has `lead_reminders` rows (`leads.routes.ts:945-998`); convert flips status to 'converted' but never copies/migrates reminders to the new ticket. Operator scheduled "follow up Mon" on the lead → converted same day → Monday arrives, no reminder fires (ticket has no reminder, lead is closed). Detail page even shows the reminders in the activity timeline (`LeadDetailPage.tsx:290-298`) so user thinks they're real promises. Devices DO get copied (`:1098-1113`); reminders are forgotten.** L4 broken flow, L7 silent loss of work.
  `packages/server/src/routes/leads.routes.ts:945-998,1098-1136`
  `packages/web/src/pages/leads/LeadDetailPage.tsx:290-298`
  <!-- meta: fix=convert-handler-INSERT-INTO-ticket_reminders-(SELECT-...-FROM-lead_reminders-WHERE-lead_id=?-AND-is_dismissed=0)+OR-leave-reminders-on-lead-and-add-link-back-to-lead-from-ticket-detail+document-which-side-owns-future-followups -->

- [ ] WEB-UIUX-1341. **[MAJOR] Confirm copy hides the customer side effect. `LeadDetailPage.tsx:405` and `LeadListPage.tsx:805` both prompt "Convert this lead to a ticket? This will create a new ticket with the lead data." — never mention that a Customer record is also created (`leads.routes.ts:1071-1080`) and (per WEB-UIUX-1339) may duplicate an existing one. Operator who already created the customer manually thinks "ticket only" and gets two customer rows. Truthful prompt would flag the customer creation step.** L2 label truthfulness, L7 informed consent.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:405`
  `packages/web/src/pages/leads/LeadListPage.tsx:805`
  `packages/server/src/routes/leads.routes.ts:1063-1082`
  <!-- meta: fix=copy="Convert-this-lead?-Will-create-Ticket+Customer-records.-Existing-customer-with-this-email/phone-will-be-linked-instead." -->

- [ ] WEB-UIUX-1342. **[MAJOR] Pipeline move menu lists every stage including illegal targets — no client-side guard. `LeadPipelinePage.tsx:148` filters only by `s.key !== lead.status`. A lead in `qualified` shows "Converted" as a target → click → server PUT runs `assertLeadTransition('qualified','converted')` → reject "Cannot transition lead from 'qualified' to 'converted'" → optimistic UI rolls back (`:277-280`) → toast error. User has no way to know this from the menu. Same trap for `converted → scheduled/qualified/proposal` (re-opened cards can only go back to new/contacted per `:42`). Disable illegal options at the menu level using LEGAL_LEAD_TRANSITIONS exposed to the client.** L4 dead-end clicks, L6 discoverability of legal moves, L7 deferred error.
  `packages/web/src/pages/leads/LeadPipelinePage.tsx:148-161`
  `packages/server/src/routes/leads.routes.ts:31-43`
  <!-- meta: fix=expose-LEGAL_LEAD_TRANSITIONS-via-/api/leads/transitions-(or-bake-into-frontend-constant)+filter-menu-items-to-allowed[lead.status]+grey-out-with-"requires-Proposal-status-first"-tooltip-for-converted -->

- [ ] WEB-UIUX-1343. **[MAJOR] Detail-page status-pill picker has no LEGAL_LEAD_TRANSITIONS guard either. Lines 358-379 render all 7 statuses as pills with no per-source filter. Same dead-click trap as WEB-UIUX-1342 but with the additional bug that `converted` still leaks through (per WEB-UIUX-1337) without server reject when source is `proposal`. Optimistic update at `:246-252` flips the badge instantly; server reject from any other illegal transition triggers `useUndoableAction` rollback (`:222-242`) but the picker UI is already closed, so the badge silently rolls back without explanation beyond the toast.** L4, L6, L7.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:222-255,358-379`
  <!-- meta: fix=share-the-LEGAL_LEAD_TRANSITIONS-client-table-from-WEB-UIUX-1342+disable-illegal-pills-with-tooltip+keep-special-case-for-lost-(modal)-and-converted-(real-convert-handler) -->

- [ ] WEB-UIUX-1344. **[MAJOR] "Mark as Lost" buried 2 clicks deep; "Convert" is a prominent green CTA. Detail header (`LeadDetailPage.tsx:396-419`) shows ONLY the green Convert button. To mark a lead lost, user must (1) click the status badge to enter edit mode, (2) click the "lost" pill, (3) fill the modal, (4) confirm. Convert is one click + confirm. In CRM real-world, leads die more often than they convert — the more frequent action is harder to reach. No "Mark as Lost" button next to Convert. Hierarchy inverted vs. conversion funnel reality.** L1 findability, L5 hierarchy.
  `packages/web/src/pages/leads/LeadDetailPage.tsx:396-419`
  <!-- meta: fix=add-secondary-"Mark-Lost"-button-next-to-Convert-(red-outline-low-emphasis)+opens-LostReasonModal-directly+reduces-3-clicks-to-1 -->

- [ ] WEB-UIUX-1345. **[MAJOR] LeadListPage row actions are icon-only with no labels — Convert (ArrowRightLeft) and Delete (Trash2) sit side-by-side, both bare icons. Lines 792-836. Only differentiation is hover color (green vs red) and tooltip. New staff cannot identify which is which without hover; touch users get no tooltip. Convert is rarely-needed-but-irreversible (creates ticket+customer+audit); Delete is destructive. Two destructive-feeling icons with no labels invites mis-clicks. Industry standard for low-frequency irreversible actions: text label or kebab menu.** L1 findability, L2 truthfulness, L5 hierarchy (destructive vs creative not visually distinct).
  `packages/web/src/pages/leads/LeadListPage.tsx:790-837`
  <!-- meta: fix=move-Convert+Delete-into-overflow-kebab-with-text-labels+keep-only-View-as-icon+OR-add-text-labels-(sm:inline)-on-Convert/Delete-buttons -->

- [ ] WEB-UIUX-1346. **[MAJOR] Pipeline column for "Converted" is dead real estate. `LeadPipelinePage.tsx:26` includes `{key:'converted',label:'Converted',color:'#22c55e'}`. Once converted, leads move to ticket workflow — there's no kanban work left here. The column accumulates closed cards that never leave (only legal transitions back are new/contacted, rare admin-recovery action). Clutters the pipeline, blocks horizontal screen real estate, makes the genuine work-in-progress columns scroll. Every other CRM hides Won/Closed from the active pipeline (filter or "Closed last 30d" toggle).** L1 visual noise on primary view, L5 hierarchy.
  `packages/web/src/pages/leads/LeadPipelinePage.tsx:20-27`
  <!-- meta: fix=remove-'converted'-from-PIPELINE_STAGES+add-"Show-converted"-toggle-OR-show-only-converted-from-last-30d+keep-link-from-each-converted-lead-to-its-ticket-via-card-footer -->

- [ ] WEB-UIUX-1347. **[MINOR] No loading state on the Convert button in LeadListPage row — convertMut.isPending disables ALL row Convert buttons globally (`:812`) since it's one shared mutation. Click Convert on lead A → buttons on B, C, D all dim simultaneously even though they're independent. With async network, looks like batch action; user gets confused which one is converting.** L7 feedback specificity.
  `packages/web/src/pages/leads/LeadListPage.tsx:812-817`
  <!-- meta: fix=track-pendingId-state-(useState<number|null>)+disable-only-the-row-being-converted+show-spinner-on-that-icon -->

- [ ] WEB-UIUX-1348. **[MINOR] After successful convert, navigate fires (`LeadDetailPage.tsx:203`) but lead-detail query was just invalidated (`:200`) — race: brief flash of refetched "converted" detail page before route changes. Cosmetic but jarring. Also, undo window for the `useUndoableAction` status changes (`:222-242`) is absent for convert — convert is irreversible (creates ticket+customer+audit) but UX provides no warning that this is final.** L7 feedback, L8 recovery (none expected for convert but copy could acknowledge it).
  `packages/web/src/pages/leads/LeadDetailPage.tsx:197-206`
  <!-- meta: fix=skip-invalidate-when-navigating-away+confirm-copy-add-"This-cannot-be-undone-from-the-UI"+server-already-supports-converted→new-recovery-but-only-via-direct-DB/admin -->

- [ ] WEB-UIUX-1349. **[MINOR] Tier-limit reject (`leads.routes.ts:1044-1054`) returns `res.status(403)` with `upgrade_required:true` and structured fields — but no UI surface even *exists* for a billing/upgrade nudge in the convert flow. Toast (after WEB-UIUX-1338 fix) would just dump the message string; ideal handling is a modal CTA "Upgrade to Pro →" linking to /billing. Currently 403 is generic-503-ish to the user.** L7 feedback meaningfulness, L4 monetization flow dead-end.
  `packages/server/src/routes/leads.routes.ts:1044-1054`
  `packages/web/src/pages/leads/LeadDetailPage.tsx:197-206`
  <!-- meta: fix=detect-err.response.data.upgrade_required+open-UpgradeModal-(reuse-from-/billing-CTA-elsewhere)+ticket-count-progress-bar-shown-on-/leads-when-current/limit>=80% -->

- [ ] WEB-UIUX-1350. **[NIT] LeadListPage convertMut success message says "Lead converted to ticket" (`:418`), navigates to /tickets/:id. Detail-page success says "Converted to ticket" (`:201`). Inconsistent copy across two surfaces for same action. Pick one ("Lead #L042 converted → Ticket #T117") and include both order_ids so user can confirm correct destination.** L7 feedback specificity, L11 consistency.
  `packages/web/src/pages/leads/LeadListPage.tsx:418`
  `packages/web/src/pages/leads/LeadDetailPage.tsx:201`
  <!-- meta: fix=both-toasts-show-"Lead-{order_id}-→-Ticket-{ticket.order_id}"+single-helper-formatConvertSuccess(res) -->


### Web UI/UX Audit — Pass 27 (2026-05-05, flow walk: Stocktake — adjust inventory count, scan, commit, recovery)

Flow audited: operator opens `/inventory` → Tools row → "Stocktake" pill → `/inventory/stocktake` → "New Stocktake" → name/location → "Open" → scan SKU + qty → "Count" repeated → "Commit (N)" → success toast → counts locked. Server: `packages/server/src/routes/stocktake.routes.ts` (open=admin|manager, scan=admin|manager|technician, commit/cancel=admin|manager).

#### Blocker — flow-breaking semantics

- [ ] WEB-UIUX-1351. **[BLOCKER] Scan default is `item.in_stock + 1` — math is against system's *expected* qty, not the count history. Operator scanning a single item once produces variance=+1 instead of "I have 1 on the shelf". Defaulting to `expected + 1` actively *inflates stock to expected+1 every scan*, which is the opposite of reconciliation. The natural stocktake default is "this scan = 1 physical unit; running count + 1".** L2 label truthfulness, L4 flow.
  `packages/web/src/pages/inventory/StocktakePage.tsx:174-177`
  <!-- meta: fix=default-counted-qty-to-prior-counted_qty+1-(or-1-if-first-scan)+NOT-expected+1+show-running-count-in-placeholder -->

- [ ] WEB-UIUX-1352. **[BLOCKER] Re-scanning the same SKU UPSERTs `counted_qty = excluded.counted_qty` (server line 222-227) — server replaces, never increments. Combined with client default of `expected+1`, scanning the same SKU 5 times yields counted_qty = expected+1 for ALL five scans. Operator believes they counted 5 physical units; row says counted_qty = expected+1.** Two-side bug: client default wrong AND server should *increment* counted_qty by client-supplied delta (or client should add prior+1).** L4 flow completion.
  `packages/web/src/pages/inventory/StocktakePage.tsx:177` + `packages/server/src/routes/stocktake.routes.ts:218-234`
  <!-- meta: fix=client-keeps-running-count+sends-absolute-counted_qty=prior+1+OR-add-POST-/counts/increment-route-with-delta-semantics -->

- [ ] WEB-UIUX-1353. **[BLOCKER] SKU lookup uses `keyword=q&pagesize=1` — picks FIRST match silently, including partial matches. Scanning a barcode that maps to 2+ items (sku-prefix collision, search treats keyword as fuzzy) credits an arbitrary item. No "exact match required" or "did you mean…" feedback.** L2 label truthfulness, L4 flow.
  `packages/web/src/pages/inventory/StocktakePage.tsx:166-173`
  <!-- meta: fix=add-/inventory/by-sku?sku=:exact-route-OR-pass-exact_sku=1-flag+if-no-exact-match-show-toast-with-top-3-fuzzy-suggestions -->

#### Blocker — recovery + irreversible state

- [ ] WEB-UIUX-1354. **[BLOCKER] No way to delete or amend a single count row from the UI. Server has UPSERT (and a row-delete is trivially adddable) but UI gives operator no per-row edit/remove. A typo on row 384 of a 1000-line stocktake is unrecoverable except by re-scanning the same SKU with a corrected qty AND knowing what the right qty is.** L8 recovery.
  `packages/web/src/pages/inventory/StocktakePage.tsx:378-400`
  <!-- meta: fix=add-row-actions-cell-with-edit-counted_qty-input+delete-button+wire-DELETE-/stocktake/:id/counts/:countId-route -->

- [ ] WEB-UIUX-1355. **[BLOCKER] "Cancel stocktake" uses `confirmLabel:'Cancel stocktake'+danger:true` modal — single confirm. Operator on a 200+ row stocktake who accidentally clicks Cancel (which sits 8px from Commit) loses every count with no undo route. Cancelled is terminal — server has no /restore endpoint.** L8 recovery.
  `packages/web/src/pages/inventory/StocktakePage.tsx:349-361` + `packages/server/src/routes/stocktake.routes.ts:398-430`
  <!-- meta: fix=type-to-confirm-modal-(operator-types-session-name)+OR-min-counts>50-trigger-typed-confirmation+separate-Cancel-and-Commit-with-12+-px-gap+place-Cancel-far-right -->

#### Major — feedback gaps

- [ ] WEB-UIUX-1356. **[MAJOR] Variance computed against `expected_qty` snapshot taken at scan time (server line 215). UI never warns "your variance baseline may be stale — items sold since you scanned will skew totals". A 4-hour stocktake with concurrent sales produces wrong variance and operator has no way to know.** L7 feedback meaningfulness.
  `packages/server/src/routes/stocktake.routes.ts:209-216` + `packages/web/src/pages/inventory/StocktakePage.tsx:285-305`
  <!-- meta: fix=show-banner-"baseline-locked-at-scan-time:N-sales-since-then"+server-includes-current_in_stock-in-counts-row+UI-shows-current-vs-baseline-side-by-side -->

- [ ] WEB-UIUX-1357. **[MAJOR] Server accepts `notes` per count (line 203-205, 233) but UI form (lines 312-333) has no notes input. Surplus of +50 with no explanation lands in stock_movements with blank reason — auditor cannot reconstruct "why".** L7 feedback meaningfulness.
  `packages/web/src/pages/inventory/StocktakePage.tsx:312-333`
  <!-- meta: fix=add-optional-notes-input-next-to-qty+thread-notes-into-scanMut-payload+show-notes-icon-on-table-row-when-present -->

- [ ] WEB-UIUX-1358. **[MAJOR] Server accepts session-level `notes` on POST (line 102-104) but inline new-session form has only name + location. Multi-day or multi-zone counts ("north room, sealed boxes only") have no place to record context auditors will ask about.** L6 discoverability.
  `packages/web/src/pages/inventory/StocktakePage.tsx:206-219`
  <!-- meta: fix=add-third-textarea-"Notes-(optional)"-to-new-session-form+thread-into-createMut.mutate-payload -->

- [ ] WEB-UIUX-1359. **[MAJOR] No high-variance toast on scan. `scanMut.onSuccess` (line 127-133) just clears inputs and refetches. Operator scanning an item where physical=4 but expected=100 should immediately see "⚠ Variance: -96 — verify count" before scanning the next SKU. Currently they see only the row appear in the table after scrolling.** L7 feedback.
  `packages/web/src/pages/inventory/StocktakePage.tsx:122-134`
  <!-- meta: fix=onSuccess-receives-{name+expected+counted+variance}+if-abs(variance)>=threshold-(configurable+default-10%)-show-warning-toast-or-inline-banner -->

- [ ] WEB-UIUX-1360. **[MAJOR] Scanned item never echoed by name on success. Operator looking at scanner gun, not screen, has no audio/visual confirmation that the right item was counted. Toast like "Counted 5× iPhone 13 mini" gives confidence; clearing inputs does not.** L7 feedback.
  `packages/web/src/pages/inventory/StocktakePage.tsx:127-133`
  <!-- meta: fix=toast.success(`${name}-→-counted-${counted_qty}-(${variance>0?+:''}${variance})`)+optional-audio-cue-on-non-zero-variance -->

- [ ] WEB-UIUX-1361. **[MAJOR] Counts table timestamp uses `toLocaleTimeString()` only — no date. A 3-day stocktake shows "10:24 AM" for both Mon and Wed counts, indistinguishable.** L7 feedback.
  `packages/web/src/pages/inventory/StocktakePage.tsx:397`
  <!-- meta: fix=use-formatDateTime-helper-(already-imported)+OR-add-day-suffix-when-not-today -->

- [ ] WEB-UIUX-1362. **[MAJOR] Session list cards show `opened_at` only, no progress preview. Operator returning to a list of 5 open sessions must drill into each to remember "which one had I gotten to 200 items on". Compare invoices/estimates lists which surface counts/totals on the row.** L7 feedback.
  `packages/web/src/pages/inventory/StocktakePage.tsx:244-273`
  <!-- meta: fix=add-items_counted+items_with_variance-to-/stocktake-list-payload+render-pill-"42-items-3-variance"-on-each-card -->

- [ ] WEB-UIUX-1363. **[MAJOR] When session is `committed` or `cancelled`, scan UI block disappears but no banner explains "Read-only — this session is committed (timestamp) by user". Operator sees a session with no actions and no context.** L7 feedback, L9 empty/loading/error states.
  `packages/web/src/pages/inventory/StocktakePage.tsx:307`
  <!-- meta: fix=else-branch-renders-banner-with-session.committed_at+committed_by_user_id-resolved-to-name+include-link-to-stock_movements-audit -->

#### Major — discoverability + nav

- [ ] WEB-UIUX-1364. **[MAJOR] Stocktake entry buried in 8-pill `text-xs` "Tools:" row on InventoryList — pills indistinguishable, no icons, no priority order. Stocktake is a *quarterly bookkeeping requirement* for VAT/sales-tax compliance; should be a top-level Inventory action button or sidebar nav item, not a small text chip.** L1 primary action findability, L6 discoverability.
  `packages/web/src/pages/inventory/InventoryListPage.tsx:491-502`
  <!-- meta: fix=hoist-Stocktake+Auto-Reorder+Shrinkage-to-an-actions-bar-with-icons+drop-the-rest-into-overflow-menu+OR-add-Inventory>Operations-sidebar-section -->

- [ ] WEB-UIUX-1365. **[MAJOR] No table search/filter inside session detail. 1000-line stocktakes have no way to "show variance > 0" or "search for SKU ABC123". `Variance items: N` summary stat (line 293-295) is decorative — clicking does nothing.** L4 flow, L6 discoverability.
  `packages/web/src/pages/inventory/StocktakePage.tsx:286-410`
  <!-- meta: fix=add-search-input+filter-pills-(All|Variance|Surplus|Shortage)+make-Variance-summary-stat-a-button-that-toggles-the-filter -->

- [ ] WEB-UIUX-1366. **[MAJOR] No CSV/PDF export of counts. Auditors require a flat list to attach to year-end paperwork. App has print/CSV elsewhere (invoices, reports) — pattern not extended here.** L6 discoverability.
  `packages/web/src/pages/inventory/StocktakePage.tsx:283-410`
  <!-- meta: fix=add-Export-CSV-button-near-summary+wire-/stocktake/:id.csv-server-route-(reuse-csv-helper-from-reports.routes) -->

- [ ] WEB-UIUX-1367. **[MAJOR] Session list has no status filter, no location filter, no search. A multi-store operator with 5 open + 30 historical sessions cannot scope the panel to "Brooklyn, open only". Server already supports `?status=` query (line 66-79) — UI doesn't surface.** L6 discoverability.
  `packages/web/src/pages/inventory/StocktakePage.tsx:239-273`
  <!-- meta: fix=add-segmented-control-(All|Open|Committed|Cancelled)+location-select-(populated-from-distinct-locations)+pass-status+location-into-query -->

- [ ] WEB-UIUX-1368. **[MAJOR] No upload-CSV path for blind counts. Many stores count on paper or offline scanner gun, then bulk-upload at end of day. Forcing real-time scan-to-server excludes that workflow entirely. Industry-standard stocktake tools (Square, Lightspeed, Vend) all support CSV import.** L6 discoverability.
  `packages/web/src/pages/inventory/StocktakePage.tsx`
  <!-- meta: fix=add-Import-CSV-button+modal-with-sample-template+POST-/stocktake/:id/counts/bulk-route-with-sku|qty-rows -->

#### Major — hierarchy + role-gating

- [ ] WEB-UIUX-1369. **[MAJOR] Action button hierarchy inverted. "Cancel" (green-bordered red text, low-density button, `danger:true` modal) only marks status=cancelled — no stock changes, no audit-trail damage. "Commit" (solid green, plain confirm modal) rewrites EVERY `inventory_items.in_stock` row + writes stock_movements + audit log + closes the session — irreversible, organisation-wide impact. Treatment is backwards: Commit is the destructive write, Cancel is the safe abort.** L5 hierarchy.
  `packages/web/src/pages/inventory/StocktakePage.tsx:336-361`
  <!-- meta: fix=Cancel-becomes-secondary-grey+plain-confirm+Commit-becomes-primary-with-typed-confirmation-modal-and-summary-of-effect-(N-items-±X-variance) -->

- [ ] WEB-UIUX-1370. **[MAJOR] Commit + Cancel buttons render for technician role even though server rejects (lines 271-274, 401-405). Client doesn't gate on `useUser().role`; technician sees buttons, clicks, gets a 403 toast. Should hide buttons for unauthorised roles, not error after click.** L4 flow, L11 a11y.
  `packages/web/src/pages/inventory/StocktakePage.tsx:336-361`
  <!-- meta: fix=wrap-action-row-in-{['admin','manager'].includes(user.role)&&...}+OR-render-disabled-state-with-tooltip-"manager-required" -->

- [ ] WEB-UIUX-1371. **[MAJOR] No duplicate-name guard. Server (lines 87-128) lets operator open two sessions named "Q2 2026 full count" simultaneously. Resuming a multi-day count → operator opens by same name on day 2, gets a NEW empty session, day-1 counts orphaned in another row.** L4 flow.
  `packages/server/src/routes/stocktake.routes.ts:97-128`
  <!-- meta: fix=server-rejects-409-if-status='open'+name=:name-already-exists+UI-suggests-resume-existing -->

- [ ] WEB-UIUX-1372. **[MAJOR] No optimistic loading state on slow commit. `commitMut.isPending` disables button (line 344) but Commit on 500-line stocktake takes seconds — single spinner gives no progress, no "applying 327/500"; operator may double-click thinking it hung.** L7 feedback, L9 loading.
  `packages/web/src/pages/inventory/StocktakePage.tsx:336-348`
  <!-- meta: fix=show-blocking-progress-modal-with-spinner+text-"committing-N-counts"+disable-page-nav+server-streams-progress-via-SSE-or-returns-batched-result -->

#### Major — empty/loading/error

- [ ] WEB-UIUX-1373. **[MAJOR] No loading skeleton — `useQuery` starts undefined, sessions list shows "No sessions yet" text instantly until fetch resolves. Slow connections see a false-empty flash that contradicts reality.** L9 empty/loading/error states.
  `packages/web/src/pages/inventory/StocktakePage.tsx:241-243, 277-281`
  <!-- meta: fix=check-isPending+show-skeleton-or-Loader2+only-show-empty-state-when-data-is-defined-and-array-is-zero -->

- [ ] WEB-UIUX-1374. **[MAJOR] First-time-user empty state ("No sessions yet") gives no help text or "Open your first stocktake" CTA. Compare InventoryList empty state which guides creation. Stocktake is unfamiliar workflow; needs onboarding nudge.** L9 empty/loading/error.
  `packages/web/src/pages/inventory/StocktakePage.tsx:241-243`
  <!-- meta: fix=replace-text-with-illustrated-empty-state+CTA-button-"Open-First-Stocktake"+link-to-help-doc-explaining-the-flow -->

#### Minor — labels + dark mode + nits

- [ ] WEB-UIUX-1375. **[MINOR] Two competing "Cancel" buttons coexist. New-session form has "Cancel" (line 232 — closes form) and active session has "Cancel" (line 360 — destroys session). If operator opens new-session form while a session is selected, both render simultaneously with same word, opposite scopes.** L2 label truthfulness.
  `packages/web/src/pages/inventory/StocktakePage.tsx:232, 360`
  <!-- meta: fix=form-cancel-becomes-"Discard"-or-"Close"+session-cancel-becomes-"Abandon-stocktake"-or-"Discard-counts" -->

- [ ] WEB-UIUX-1376. **[MINOR] "Open" button on new-session form is ambiguous. Could mean "Open a file", "Open camera", "Open a session". Better: "Start counting" or "Begin stocktake".** L2 label truthfulness.
  `packages/web/src/pages/inventory/StocktakePage.tsx:226`
  <!-- meta: fix=rename-to-"Begin-Stocktake"-or-"Start-Counting" -->

- [ ] WEB-UIUX-1377. **[MINOR] Status pill `open` colored amber (line 260) — amber implies warning/needs-attention. Open is the normal active working state. Should be primary/blue.** L5 hierarchy.
  `packages/web/src/pages/inventory/StocktakePage.tsx:258-263`
  <!-- meta: fix=open=primary-100/primary-700-(or-blue)+committed-stays-green+cancelled-grey -->

- [ ] WEB-UIUX-1378. **[MINOR] Inline new-session form inputs lack `dark:bg-surface-...` classes — pure white background bleeds through dark theme. Same applies to scan + qty inputs (lines 318, 325).** L13 styling.
  `packages/web/src/pages/inventory/StocktakePage.tsx:211, 217, 318, 325`
  <!-- meta: fix=add-dark:bg-surface-900+dark:border-surface-700+dark:text-surface-100-to-each-input-OR-extract-Input-component-and-reuse -->

- [ ] WEB-UIUX-1379. **[MINOR] Selected session card uses `bg-primary-50` (line 251) with no dark mode variant — primary-50 on dark theme reads almost white-on-near-white.** L13 styling.
  `packages/web/src/pages/inventory/StocktakePage.tsx:248-253`
  <!-- meta: fix=add-dark:bg-primary-900/40+dark:border-primary-600-to-selected-state -->

- [ ] WEB-UIUX-1380. **[MINOR] "Back to Inventory" link is a flat anchor; loses tab+filter state from `/inventory?type=part`. Returning to InventoryList drops user's tab.** L4 flow.
  `packages/web/src/pages/inventory/StocktakePage.tsx:187-189`
  <!-- meta: fix=use-navigate(-1)-or-store-prior-search-params-in-state-and-restore-on-back -->

- [ ] WEB-UIUX-1381. **[NIT] "No item matching X" toast (line 170) provides only the failed query — no fuzzy-match suggestions. Inventory keyword search supports prefix; surface top-3 partial matches in toast or inline.** L7 feedback.
  `packages/web/src/pages/inventory/StocktakePage.tsx:170`
  <!-- meta: fix=on-zero-exact-match-fetch-pagesize=3+show-toast-with-clickable-suggestions -->


### Web UI/UX Audit — Pass 28 (2026-05-05, flow walk: process refund — invoice → reduce balance, return cash, queue/approve)

Flow audited: cashier needs to refund a customer who paid for an invoice. Walk: open `/invoices/:id` → look for "Refund" button → no such button. Only "Credit Note" (reduces ledger balance, no money returned). Server has full `refunds.routes.ts` (548 lines: GET list, POST create pending, PATCH approve, PATCH decline, store-credit credits/use/liability) wired at `/api/v1/refunds` (`packages/server/src/index.ts:1603`) — but ZERO web client surface (no `refundsApi` in `endpoints.ts`, no route in `App.tsx`, no nav link, no list page, no approve queue).

#### Blocker — entire refund subsystem unreachable from UI

- [ ] WEB-UIUX-1382. **[BLOCKER] No refund UI exists at all. `packages/server/src/routes/refunds.routes.ts` exposes 6 endpoints (list, create, approve, decline, credits/use, credits/liability) under `/api/v1/refunds`; `packages/web/src/api/endpoints.ts` defines NO `refundsApi` object. No page in `packages/web/src/App.tsx` (77 routes — none for `/refunds`). No nav item. Operator who needs to issue an actual cash/card refund — money returned to customer — has no entry point. Closest UI is "Credit Note" which reduces invoice balance only; it never moves money. Refund queue (pending → admin approves) cannot be actioned by anyone via the web. Manager-tier permission `refunds.create` is granted but unusable.** L1 primary action findability, L4 flow completion (irrecoverable dead-end), L6 discoverability.
  `packages/server/src/routes/refunds.routes.ts:107,253,418`
  `packages/web/src/api/endpoints.ts:1-end (no refundsApi)`
  `packages/web/src/App.tsx (no /refunds route)`
  <!-- meta: fix=add-refundsApi-(list+create+approve+decline+credits)+create-RefundsListPage-with-pending-approve-queue+create-NewRefundModal-on-InvoiceDetail+wire-Refunds-into-sidebar-under-Billing+expose-Refund-button-on-paid-invoices -->

- [ ] WEB-UIUX-1383. **[BLOCKER] Dashboard "Refunds" KPI is dead clickthrough — `href: undefined` (`DashboardPage.tsx:2120`) while every sibling KPI links to a relevant page (Sales→/reports, Discounts→/invoices, COGS→/inventory, Receivables→/invoices?status=unpaid). Refunds drilldown promise is implicit in card layout but click does nothing. Operator hunting for "where did $1,247 of refunds come from?" gets a non-interactive number.** L1, L4, L7 feedback meaningfulness.
  `packages/web/src/pages/dashboard/DashboardPage.tsx:2120`
  <!-- meta: fix=after-WEB-UIUX-1382-create-/refunds-page+set-href:'/refunds'+OR-/reports?metric=refunds-with-anchor -->

- [ ] WEB-UIUX-1384. **[BLOCKER] "Credit Note" button label is what cashiers reach for when they mean "give the customer their money back" — but credit note only reduces the invoice ledger (negative invoice row, `invoices.routes.ts:1212-1230`). No cash leaves the till. No card refund is initiated. The operator-facing copy "Issue a credit note against invoice X. This will reduce the outstanding balance" (`InvoiceDetailPage.tsx:753-755`) does not say *cash is not returned*. Cashier issues a $200 credit note thinking they refunded the card; customer leaves expecting card credit; reality: no money moved, customer disputes a week later.** L2 label truthfulness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380, 748-755`
  <!-- meta: fix=copy="Reduces-the-invoice-balance-on-our-books.-No-money-is-returned-to-the-customer."+OR-after-WEB-UIUX-1382-show-Refund-button-(actually-returns-money)-next-to-Credit-Note-(ledger-only) -->

#### Blocker — POS return path unreachable

- [ ] WEB-UIUX-1385. **[BLOCKER] `posApi.return` (`endpoints.ts:753`) POSTs `/pos/return` with idempotency key — never called from any UI. Cashier with a returning customer holding receipt #12345 has no "Process Return" path through POS. UnifiedPosPage has no return tab/mode; CashRegisterPage has only cash in/out (drawer events, not sales-returns). The endpoint is documented as "Cash refund on an existing sale" but is dead.** L4 flow, L6 discoverability.
  `packages/web/src/api/endpoints.ts:749-761`
  `packages/web/src/pages/unified-pos/UnifiedPosPage.tsx`
  <!-- meta: fix=add-Returns-tab-to-UnifiedPosPage+receipt-lookup-by-order_id-or-scan+select-line-items-to-return+method-picker-(cash|card|store-credit)+POST-/pos/return-with-idempotency -->

#### Major — credit-note flow ergonomics + truthfulness

- [ ] WEB-UIUX-1386. **[MAJOR] Credit-note client cap mismatched to server cap. Client caps amount at `Number(invoice.amount_paid) || 0` (`InvoiceDetailPage.tsx:298,763,777`). Server caps at `original.total - alreadyCreditedSoFar` (`invoices.routes.ts:1186,1197-1201`). Unpaid $200 invoice that legitimately needs a $200 ledger write-off (e.g. uncollectible debt to be written off as discount-after-the-fact) cannot be credited via UI — client throws "Amount cannot exceed amount paid ($0)" before request leaves browser. Server would accept the $200 credit. Two divergent rules; client is more restrictive than necessary.** L4 flow, L11 consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:298-303,763,776-778`
  `packages/server/src/routes/invoices.routes.ts:1186,1197-1201`
  <!-- meta: fix=decide-policy:-(a)-write-off-flow-needs-server+client=invoice.total-prior_credits+OR-(b)-document-credit-note-as-refund-only-and-keep-amount_paid-cap+server-aligns-to-amount_paid -->

- [ ] WEB-UIUX-1387. **[MAJOR] No credit-note history shown on InvoiceDetail. Server creates a *separate negative invoice* row with `credit_note_for=invoiceId` (`invoices.routes.ts:1212-1230`) — these never surface on the original invoice's detail page. Operator returning to invoice INV-001 cannot see "Credit note CN-007 issued for $50 on 2026-04-12 by Jane (reason: defective)". They must search invoice list and discover the negative row. Payment Timeline (`InvoiceDetailPage.tsx:475-548`) shows payments only.** L7 feedback meaningfulness, L9 empty/loading/error.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:475-548`
  <!-- meta: fix=GET-/invoices/:id-payload-include-credit_notes:[{order_id,amount,reason,created_by,created_at}]+render-as-Credit-Notes-section-or-merge-into-timeline-with-distinct-icon -->

- [ ] WEB-UIUX-1388. **[MAJOR] Credit-note modal lacks `requireTyping` confirm pattern that the same page uses for Void (`:813,815` — `requireTyping confirmText={String(invoice?.order_id)}`). Credit notes are similarly irreversible (server has no DELETE) and similarly affect stored ledger; the inconsistency invites mis-clicks on a small button-only modal. A single confirm-on-click is too thin for a permanent ledger entry.** L5 hierarchy (destructive action gated weaker than less-destructive sibling), L8 recovery.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:795-802 vs 807-817`
  <!-- meta: fix=switch-creditNoteMutation-to-ConfirmDialog-with-requireTyping=true+confirmText=invoice.order_id+danger=true -->

- [ ] WEB-UIUX-1389. **[MAJOR] Credit-note error toasts dump server message verbatim — `e?.response?.data?.message || 'Failed to create credit note'` (`InvoiceDetailPage.tsx:176`). Server says "Credit note total would exceed invoice total (already credited 50.00 of 200.00)" — useful number but UI does not extract `priorCredits` to update the cap input or show a "Max remaining: $150" hint. Operator must read the toast, do mental math, retry.** L7 feedback meaningfulness, L4.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:176`
  `packages/server/src/routes/invoices.routes.ts:1192-1201`
  <!-- meta: fix=server-returns-{message,already_credited,max_remaining}-structured+UI-special-cases-and-pre-fills-input-with-max_remaining+banner-"Already-credited:-$50.-Remaining:-$150" -->

- [ ] WEB-UIUX-1390. **[MAJOR] Credit-note submit happens on Enter inside the amount input — no per-field validation feedback, no inline error, only the toast. `handleCreditNote` `:288-311` sequence: amount-empty-or-zero → toast; amount > paid → toast; reason missing → toast. Each is a separate red flash, not a per-field hint. Operator cannot see at-a-glance which field is wrong if they have all three issues.** L7 feedback specificity.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:288-311`
  <!-- meta: fix=track-fieldErrors:Record<string,string>+render-text-red-500-text-xs-mt-1-under-each-field+disable-Create-button-when-any-fieldError-set -->

- [ ] WEB-UIUX-1391. **[MAJOR] No notification to customer when credit note created. Refund-style action against a paid invoice — customer expects an email/SMS receipt of the credit ("$50 credited toward INV-001 — reason: defective product"). Server returns success silently; UI clears form, no follow-up. Compare InvoiceDetail's `showReceiptPrompt` after payment (`:594+`) which prompts cashier to email/SMS receipt. Symmetry broken on the credit side.** L7 feedback (downstream actor unaware), L4 flow.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:169-177, 594-733`
  <!-- meta: fix=onSuccess-show-prompt-modal-(reuse-receipt-prompt-pattern)+wire-notificationApi.sendCreditNoteReceipt+pre-fill-with-customer-email -->

- [ ] WEB-UIUX-1392. **[MAJOR] Credit-note creates ledger entry but never adjusts customer's `store_credits` row when a refund-to-credit method is desired. Server only credits `store_credits` for *overflow* (credit > remaining due, `invoices.routes.ts:1259-1283`). Operator who wants "$50 credit note → put $50 on customer's store credit" with the invoice fully unpaid has no way to do this from credit-note flow. Refund route handles it (`refunds.routes.ts:383-396`) but refund route has no UI (WEB-UIUX-1382).** L4 flow, L6 discoverability.
  `packages/server/src/routes/invoices.routes.ts:1259-1283`
  `packages/server/src/routes/refunds.routes.ts:383-396`
  <!-- meta: fix=add-method-picker-to-credit-note-modal-(refund-cash|refund-card|store-credit|ledger-only)+route-to-refund-route-when-money-actually-leaves -->

- [ ] WEB-UIUX-1393. **[MAJOR] `invoice.status='refunded'` is defined as a status colour (`InvoiceListPage.tsx:33,41`, `CustomerDetailPage.tsx:1685`) but no flow ever assigns it. Credit note moves status through unpaid→partial→paid via `assertInvoiceTransition` (`invoices.routes.ts:1252-1257`), never through `refunded`. Refund route never updates invoice.status. Dead status decoration.** L11 consistency, L13 dead code.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:33,41`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1685`
  `packages/server/src/routes/refunds.routes.ts:253-412`
  <!-- meta: fix=on-refund-approve-set-invoice.status='refunded'-when-cumulative-refunds>=amount_paid+OR-remove-the-status-colour-decoration -->

- [ ] WEB-UIUX-1394. **[MAJOR] No way to view, approve, or decline a pending refund. `PATCH /refunds/:id/approve` (admin-only) requires a queue/list to action. With no list page, an admin cannot complete the workflow even on existing pending rows seeded by tests/imports. `refunds.create` permission grants creation but not the path to push it through.** L4 flow, L5 hierarchy.
  `packages/server/src/routes/refunds.routes.ts:253-412`
  <!-- meta: fix=ship-RefundsListPage-with-status-filter-(pending|completed|declined)+inline-Approve+Decline-buttons-for-pending-rows-(admin-only)+confirm-with-amount+reason+invoice-link -->

- [ ] WEB-UIUX-1395. **[MAJOR] `RefundReasonPicker` component is used inside the "Credit Note" modal but its label is "Refund reason *" (`RefundReasonPicker.tsx:60`). Operator sees the modal title "Create Credit Note", types the amount, then a "Refund reason" picker — terminology drift mid-flow. Either the modal is a refund (then call it Refund) or the reason picker is a "Credit note reason" (then rename the picker label).** L2, L11 consistency.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:60`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:748-789`
  <!-- meta: fix=rename-picker-prop-to-allow-label-override+pass-label="Credit-note-reason"-from-credit-note-modal+keep-"Refund-reason"-when-(eventually)-used-in-real-refund-flow -->

#### Major — discoverability + nav gaps

- [ ] WEB-UIUX-1396. **[MAJOR] Permissions matrix exposes `refunds.create`, `refunds.approve`, `refunds.decline` (all wired in `refunds.routes.ts:107,253,418`) but Settings > Roles UI has no way to test what these permissions actually unlock — the surface they protect is invisible (WEB-UIUX-1382). Admin assigns "manager can refund" then no manager can find a refund button. Permission feels broken.** L6 discoverability, L7 feedback.
  `packages/server/src/routes/refunds.routes.ts:107,253,418`
  <!-- meta: fix=blocker-on-WEB-UIUX-1382-(ship-UI)-OR-add-Settings-banner-"Refund-routes-currently-have-no-UI;-permissions-take-effect-once-/refunds-page-ships" -->

- [ ] WEB-UIUX-1397. **[MAJOR] Reports do not surface refund detail. Dashboard KPI shows aggregate (`kpis.refunds`); `/reports` page (linked from KPI siblings) has no per-refund breakdown — server's `GET /refunds` returns paginated detail with customer name + invoice order_id + creator, but the data is unread by any frontend.** L6 discoverability, L4 flow.
  `packages/server/src/routes/refunds.routes.ts:74-95`
  `packages/web/src/pages/dashboard/DashboardPage.tsx:2120`
  <!-- meta: fix=add-Refunds-Detail-tab-to-/reports+table-with-date+invoice+customer+amount+reason+method+approver -->

- [ ] WEB-UIUX-1398. **[MAJOR] Card-method refund cap exists in server (`refunds.routes.ts:177-202` — `cardCollected - cardAlreadyRefunded`) but no UI surface ever sends `method:'card'`. The whole branch is dead defence-in-depth. Once UI is added, the method picker must default to the *original payment method* of the invoice (lookup last payment.method) — otherwise operator hand-picks "cash" and bypasses card cap.** L4 flow, L7 feedback.
  `packages/server/src/routes/refunds.routes.ts:177-202`
  <!-- meta: fix=NewRefundModal-prefill-method-from-invoice.payments[0].method+disable-non-card-options-when-original-was-card+show-card-cap-inline-($X-card-collected,-$Y-already-refunded) -->

- [ ] WEB-UIUX-1399. **[MAJOR] Capture-state precondition (`refunds.routes.ts:140-153` — refunds blocked while any payment is `authorized` or `voided` not yet captured) — no UI hint. Operator on an invoice with an auth-only BlockChyp payment will hit a 400 "Cannot refund — N payment(s) on this invoice are not captured" with no path to "Capture or void the authorization first" the error tells them to do. Capture flow itself buried/nonexistent.** L4 flow dead-end, L7 feedback unactionable.
  `packages/server/src/routes/refunds.routes.ts:133-153`
  <!-- meta: fix=Refund-button-disabled-with-tooltip-"Capture-pending-authorization-first"-when-any-payment.capture_state!='captured'+CTA-link-to-capture-flow -->

- [ ] WEB-UIUX-1400. **[MAJOR] Store-credit balance never shown to cashier at sale time. `GET /refunds/credits/:customerId` returns balance + 50-row history; UI has no equivalent to "this customer has $X store credit available, apply now?" prompt at checkout. UnifiedPosPage CheckoutModal does not query credit. Issued credits become invisible — customer holds it, cashier doesn't know.** L6 discoverability, L4 flow.
  `packages/server/src/routes/refunds.routes.ts:439-454`
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx`
  <!-- meta: fix=at-customer-select-fetch-credits.balance+show-pill-"Store-credit:-$X"+payment-method-includes-store_credit-with-cap-at-balance+POST-/refunds/credits/:id/use-on-apply -->

#### Major — recovery + concurrency surfacing

- [ ] WEB-UIUX-1401. **[MAJOR] Server returns 409 "Refund exceeds available balance (concurrent refund conflict)" (`refunds.routes.ts:227`) and 409 "Refund is no longer pending" (`:299`) — surface-friendly admin needs UI hint "another admin just acted; reload". With no UI today the messages are theoretical, but when WEB-UIUX-1382 lands the toast must distinguish 409 (race, retry) from 400 (operator-fixable input).** L7 feedback specificity, L8 recovery.
  `packages/server/src/routes/refunds.routes.ts:227,299,308`
  <!-- meta: fix=on-409-show-toast-"Already-actioned-by-another-admin.-Refresh-to-see-current-state."+auto-invalidate-refund-list-query+on-400-keep-form-open-with-server-message -->

- [ ] WEB-UIUX-1402. **[MAJOR] Commission reversal silently skipped on locked payroll period. Server returns `commission_reversal_skipped:true` in success payload (`refunds.routes.ts:404-411`) — no UI consumes this flag. Refund completes; commissions stay paid; no operator warning that "refund applied, but $32 of paid commission was NOT clawed back because Jan 2026 payroll is locked. Reverse manually after unlock." Will reach UI debt level once refund UI ships.** L7 feedback meaningfulness.
  `packages/server/src/routes/refunds.routes.ts:319-376,404-411`
  <!-- meta: fix=refund-approve-success-handler-checks-data.commission_reversal_skipped+shows-warning-toast-with-link-to-payroll-period-unlock+OR-pending-task-in-Needs-Attention -->

#### Minor — labels, copy, dark-mode

- [ ] WEB-UIUX-1403. **[MINOR] Credit Note icon is `CreditCard` (`InvoiceDetailPage.tsx:378`) — overloaded with payment-method/credit-card semantics. Suggests "pay by card", not "issue credit". Industry pattern: rotated arrow icon, ReceiptText, or Undo2.** L2 truthfulness, L11 iconography.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:378`
  <!-- meta: fix=swap-CreditCard-for-ReceiptText-or-Undo2 -->

- [ ] WEB-UIUX-1404. **[MINOR] "Voiding this invoice will restore stock and mark all payments as voided. This cannot be undone." — Void disclaimer says "restore stock". Credit Note disclaimer ("Issue a credit note against invoice X. This will reduce the outstanding balance.") says nothing about stock. Server credit-note path never restores stock either (`invoices.routes.ts:1213-1230` — only inserts negative invoice). For a credit note covering the *full* invoice in a return scenario, stock is left as sold. No UI hint, no server hook.** L7 feedback, L4 flow.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:807-817 vs 753-755`
  `packages/server/src/routes/invoices.routes.ts:1213-1283`
  <!-- meta: fix=add-checkbox-"Restore-line-item-stock"-(default-off-since-credit-note-is-ledger-only;-on-when-physical-return)+server-honours-flag+adjusts-inventory_items.in_stock+stock_movements -->

- [ ] WEB-UIUX-1405. **[MINOR] Credit-note submit button colour is amber-600 (`InvoiceDetailPage.tsx:798`); Void is red (`:386`); Pay is primary green (`:345`). No visual cue that credit-note is also a destructive ledger write. Amber reads as "warning, proceed with care" but is shared with low-stakes warning toasts. Standardize: ledger-irreversible actions use red border/text + amber fill, payments use green, void uses solid red.** L5 hierarchy.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:377,386,798`
  <!-- meta: fix=elevate-credit-note-CTA-to-red-border+amber-fill-(or-borrow-Void-treatment)+document-the-pattern-in-tokens -->

- [ ] WEB-UIUX-1406. **[MINOR] `RefundReasonPicker` "Other" option pairs with optional notes textarea. When operator picks Other and leaves note empty, server stores reason "other:" — meaningless reporting bucket. Picker should require notes when reason='other'. UI does not enforce.** L7 feedback, L4 flow integrity.
  `packages/web/src/components/billing/RefundReasonPicker.tsx:23,42-50,80-93`
  <!-- meta: fix=if-localReason==='other'-mark-Notes-required+disable-onChange-emit-until-note.length>=3+show-error-text -->

- [ ] WEB-UIUX-1407. **[MINOR] Credit-note amount input has `max={Number(invoice.amount_paid) || 0}` HTML attribute (`InvoiceDetailPage.tsx:763`) but type=number with step=0.01 — Chrome shows browser-native validation, Safari/Firefox tolerate over-cap until submit. Operator gets inconsistent UX across browsers. Backed-by-state cap with `aria-invalid` already present (`:767`) but the visible style change is subtle.** L7 feedback, L11 cross-browser consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:761-771`
  <!-- meta: fix=replace-HTML-max-with-onChange-clamp+show-inline-red-text-when-value>cap+disable-Create-button -->

- [ ] WEB-UIUX-1408. **[NIT] Credit-note cap label "Max: $X (amount paid)" (`InvoiceDetailPage.tsx:776-778`) becomes nonsensical when `amount_paid=0` (unpaid invoice) — shows "Max: $0.00 (amount paid)". Operator on unpaid invoice cannot create credit note even though the server accepts up to invoice.total (per WEB-UIUX-1386). Either suppress the modal entry on `amount_paid=0` or align cap policy.** L7 feedback, L9 empty/edge state.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:376-380,776-778`
  <!-- meta: fix=when-amount_paid==0-disable-Credit-Note-button-with-tooltip-"No-payment-to-credit"+OR-after-WEB-UIUX-1386-relax-cap-and-update-label -->

- [ ] WEB-UIUX-1409. **[NIT] No keyboard shortcut to focus credit-note amount input on modal open. AutoFocus is set (`:770`) — covered. But Esc dismisses only via outside-click handler (`:744`); no Escape key listener.** L11 a11y/keyboard.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:738-805`
  <!-- meta: fix=add-useEffect-keydown-Escape→setShowCreditNote(false)+document-pattern-as-Modal-helper -->

### Web UI/UX Audit — Pass 29 (2026-05-05, flow walk: Forgot Password → Reset — login forgot panel, email link, set new password, recovery)

- [ ] WEB-UIUX-1410. **[BLOCKER] Forgot-password panel swallows server errors silently. `else` branch (`:758-765`) increments `forgotFailCount` and resets captcha but never sets `error`/`forgotSent`/any visible state. User clicks Send on a typo'd email — server returns 400 "Valid email is required" — UI does NOTHING visible. User clicks Send again — same silent failure. After 3 attempts they hit 429 and still see no message. Critical recovery flow gives zero feedback on failure.** L7 feedback meaningfulness.
  `packages/web/src/pages/auth/LoginPage.tsx:751-765`
  <!-- meta: fix=add-forgotError-state+set-it-from-err.response.data.message+render-as-LoginError-inside-forgot-panel+distinguish-400/429/network-kinds -->

- [ ] WEB-UIUX-1411. **[BLOCKER] Reset-success redirect lands on marketing page on bare-domain tenants. App.tsx:424-433 `showLanding` branch renders only `/signup`, `/reset-password/:token`, and a `*` LandingPage catch-all — no `/login` route. ResetPasswordPage (`:69`) navigates to `/login` after 3 seconds. Public-domain user resets password → gets dropped onto landing page → has no idea where login is. Reset flow visibly succeeds but user cannot complete the loop.** L3 route correctness, L4 flow completion.
  `packages/web/src/App.tsx:424-433` + `packages/web/src/pages/auth/ResetPasswordPage.tsx:68-70`
  <!-- meta: fix=either-add-/login-route-to-showLanding-routes-block-OR-redirect-to-tenant-subdomain-/login-when-tenantSlug-known+pass-tenant-context-via-localStorage-or-from-reset-link-query -->

- [ ] WEB-UIUX-1412. **[MAJOR] No way to retry forgot-password with a different email after `forgotSent=true`. Once panel shows "If an account exists, link sent" (`:716-722`), there is no "Try a different email" or "Resend" button. State is locked. User who typo'd `jhon@x.com` instead of `john@x.com` waits 30 minutes, never gets email, then must close+reopen panel via "Forgot password?" toggle — non-obvious recovery path.** L8 recovery, L4 flow completion.
  `packages/web/src/pages/auth/LoginPage.tsx:716-722`
  <!-- meta: fix=add-secondary-"Send-to-different-email"-button-below-success-message+resets-forgotSent+forgotEmail+forgotFailCount-on-click -->

- [ ] WEB-UIUX-1413. **[MAJOR] Reset-success page auto-redirects in 3s, drags user away mid-read. ResetPasswordPage (`:68-70`) `setTimeout(() => navigate('/login'), 3000)`. Body text is 2 sentences plus a "Return to Login" Link — user reading "Your password has been successfully updated. You will be redirected..." gets yanked away before they can finish. The Link below is redundant once auto-redirect fires. Best practice: NO auto-redirect on success-of-irreversible-action; user clicks Continue when ready.** L7 feedback, L8 recovery.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:67-70`
  <!-- meta: fix=remove-setTimeout+make-"Return-to-Login"-Link-a-prominent-primary-button+optional-countdown-text-only-if-auto-redirect-kept -->

- [ ] WEB-UIUX-1414. **[MAJOR] Reset-token-failure error is a dead-end. ResetPasswordPage (`:79-83`) shows "Failed to reset password. Please request a new reset link." with NO link/button to do so. User must manually retype URL → /login → click "Forgot password?" → re-enter email. Recovery copy tells user what to do but doesn't enable it inline.** L8 recovery, L4 flow completion.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:79-83,158-162`
  <!-- meta: fix=when-error-non-400-or-token-invalid-render-secondary-button-"Request-new-reset-link"-that-routes-to-/login?forgot=1+LoginPage-auto-opens-forgot-panel-on-?forgot=1 -->

- [ ] WEB-UIUX-1415. **[MAJOR] Password-history rule (P2FA8) hidden until rejection. Server rejects with "Password must be different from your last 5 passwords" (auth.routes.ts:1810) but UI advertises only "Min 8 characters" (`:807`). User picks favorite reused password → submit → rejected with rule they never saw. Surface upfront so the cognitive load is on entry, not on retry.** L6 discoverability, L7 feedback.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:118-123`
  <!-- meta: fix=info-banner-text="Min-8-chars+must-differ-from-last-5-passwords"+optionally-render-list-of-rules-as-checkmarks-progressively-validated-as-user-types -->

- [ ] WEB-UIUX-1416. **[MAJOR] No live "passwords match" indicator on confirm field. ResetPasswordPage validates `password !== confirmPassword` only at submit (`:53`). User typos confirm field, hits Reset, sees "Passwords do not match", retypes both. A live green-check / red-x adjacent to the confirm field would catch the typo before submit and save a round-trip — standard pattern from any password-reset flow.** L7 feedback, L9 loading/empty states.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:142-156`
  <!-- meta: fix=derive-confirmMatches=confirmPassword.length>=8&&password===confirmPassword+show-CheckCircle2-green-or-XCircle-red-icon-inside-input-trailing-edge -->

- [ ] WEB-UIUX-1417. **[MAJOR] "Reset Password" button hides destructive side-effect. Server (auth.routes.ts:1830-1854) atomically updates password AND deletes ALL sessions (P2FA2). User logged in on iPad/phone gets silently kicked. Label "Reset Password" implies password-only change. Should warn "Resets password and signs out other devices" — especially relevant if user is resetting because of suspected compromise vs because they forgot it on this browser only.** L2 label truthfulness, L7 feedback.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:164-170`
  <!-- meta: fix=button-label="Reset-password-&-sign-out-other-devices"-OR-add-info-line-above-button-"This-will-sign-out-all-other-sessions" -->

- [ ] WEB-UIUX-1418. **[MAJOR] Non-400 errors on reset collapse to "request a new reset link" — wrong instruction for network failures. ResetPasswordPage (`:75-83`) only surfaces server `message` for status===400; everything else (network down, 500, 429) becomes "Failed to reset password. Please request a new reset link." User offline retypes new URL → still offline → same message → keeps requesting new tokens, burning rate limit. Distinguish network/server/rate-limit from token-invalid.** L7 feedback meaningfulness, L8 recovery.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:71-86`
  <!-- meta: fix=branch-on-status:-no-response→"Cannot-reach-server.-Check-connection.";-429→"Too-many-attempts,-try-again-later";-400→server-message;-other→"Server-error,-try-again" -->

- [ ] WEB-UIUX-1419. **[MAJOR] Forgot panel Send button has same primary-600 hue as main Sign In button — hierarchy collision. LoginPage.tsx:770 (Send) and :782 (Sign In) both `bg-primary-600`. User who opened forgot panel by mistake then habitually presses Enter — focus might be on Send button — could trigger reset email instead of login. Also visually competes for primary-action attention. Forgot Send should be secondary (outlined / surface tone).** L5 hierarchy.
  `packages/web/src/pages/auth/LoginPage.tsx:742-774`
  <!-- meta: fix=Send-button-bg-surface-200-text-surface-700-OR-bg-primary-100-text-primary-700+border-primary-300+keep-Sign-In-as-only-primary-600-on-screen -->

- [ ] WEB-UIUX-1420. **[MAJOR] "Forgot password?" link is text-xs (12px), right-aligned, no underline, no icon. Lowest visual weight on the page. Users in actual recovery mode (who came to login BECAUSE they forgot) will stare at the form for several seconds before scanning to find the link. Industry pattern: link sized at least text-sm with KeyRound or HelpCircle icon, left-or-center positioned near password field.** L1 primary action findability, L5 hierarchy.
  `packages/web/src/pages/auth/LoginPage.tsx:709-713`
  <!-- meta: fix=text-xs→text-sm+add-KeyRound-h-3.5-w-3.5-icon-prefix+optional-underline-on-hover+keep-right-align-or-move-below-password-field -->

- [ ] WEB-UIUX-1421. **[MAJOR] Captcha widget appears mid-panel after first failure with no label or explanation. LoginPage.tsx:728-731 conditionally renders `<div ref={forgotCaptchaContainerRef} />` once `forgotFailCount >= 1` — but combined with WEB-UIUX-1410 (silent error on failure), user sees: clicked Send → nothing happened → suddenly an unfamiliar captcha widget appears below the email field → no caption telling them why. Add "Verify you're human, then resend" header above widget.** L7 feedback meaningfulness, L6 discoverability.
  `packages/web/src/pages/auth/LoginPage.tsx:728-731`
  <!-- meta: fix=above-widget-render-<p-class="text-xs">"Confirm-you're-human-and-press-Send-again"</p>+wrap-widget-in-labeled-fieldset-for-screen-readers -->

- [ ] WEB-UIUX-1422. **[MAJOR] No recovery path for "lost 2FA + lost trusted-device". Login flow assumes user has TOTP code or trusted-device cookie. If user wipes browser AND loses authenticator (phone destroyed/lost), they cannot log in — no "I lost my 2FA device" link on /login. Settings sessions revoke is gated behind logging in. Result: locked out, must contact admin. Should expose admin-recovery email request from login screen.** L8 recovery, L4 flow completion.
  `packages/web/src/pages/auth/LoginPage.tsx:862-928`
  <!-- meta: fix=add-tertiary-link-"Lost-your-2FA-device?"-near-trust-checkbox-or-below-Verify-button+routes-to-/account/recover-which-emails-admin-or-owner-of-account-with-recovery-instructions -->

- [ ] WEB-UIUX-1423. **[MINOR] Forgot Send button label "Send" is vague — doesn't describe action. Email subject is "Password Reset"; button could say "Email reset link" or "Send reset email". Single-word "Send" doesn't tell user what gets sent or where. Especially after captcha widget renders, unfamiliar users hesitate.** L2 label truthfulness.
  `packages/web/src/pages/auth/LoginPage.tsx:771-774`
  <!-- meta: fix=button-text="Email-reset-link"+aria-label-same -->

- [ ] WEB-UIUX-1424. **[MINOR] Forgot success copy "Check your inbox" misses the spam-folder advice. Reset emails commonly land in spam on first delivery to address. Add "(check spam if not there in a minute)" — saves 30%+ of "I never got the email" support tickets in standard SaaS deployments.** L7 feedback, L9 helpful empty/loading messages.
  `packages/web/src/pages/auth/LoginPage.tsx:719-721`
  <!-- meta: fix=copy="If-an-account-with-that-email-exists,-a-reset-link-has-been-sent.-Check-your-inbox-(and-spam-folder)." -->

- [ ] WEB-UIUX-1425. **[MINOR] ResetPasswordPage info-banner copy "Enter securely a new password for your account." reads as misordered translation. Native phrasing: "Enter a new password for your account." Adverb "securely" is a verb modifier on "Enter" but action of typing is not the security control — TLS + bcrypt are. Copy adds noise without clarifying anything.** L2 label truthfulness.
  `packages/web/src/pages/auth/ResetPasswordPage.tsx:118-123`
  <!-- meta: fix=copy="Enter-a-new-password-for-your-account." -->

- [ ] WEB-UIUX-1426. **[MINOR] Forgot panel loading indicator is `Loader2 h-3 w-3` — same dimensions as Mail icon (`:772`). When `forgotLoading=true`, button visually "swaps" icon imperceptibly. No label change ("Send" stays). User clicks twice thinking nothing happened — but disabled prop prevents second submit. Still: poor perceptual feedback. Add "Sending..." text while loading.** L7 feedback meaningfulness, L9 loading state.
  `packages/web/src/pages/auth/LoginPage.tsx:771-774`
  <!-- meta: fix=button-text-conditional:-loading?"Sending...":"Email-reset-link"+keep-spinner -->

### Web UI/UX Audit — Pass 30 (2026-05-05, flow walk: issue gift card → deliver code → redeem at POS → reload)

Flow audited: cashier wants to sell a $50 gift card to a walk-in, hand the recipient a usable code, then later redeem it during a POS sale and reload it when the recipient returns. Walk: open `/gift-cards` (no nav link — must use Cmd+K) → click "Issue gift card" → no customer link, no notes, no email/print delivery → code shown ONCE on screen → close modal → recipient holds code → cashier opens POS → no gift-card payment method → no lookup-by-code surface → recipient cannot redeem via UI; the entire `/gift-cards/lookup/:code` and `/gift-cards/:id/redeem` server pair is dead from the web client. Reload modal exists on detail page but hides current balance and is gated by status='used' (UI stricter than server).

#### Blocker — gift-card delivery + redemption are unreachable from the floor

- [ ] WEB-UIUX-1427. **[BLOCKER] No POS payment method for gift cards. CheckoutModal `PaymentMethod = 'Cash' | 'Card' | 'Other'` (`CheckoutModal.tsx:16,23-27`). Server's `/gift-cards/lookup/:code` + `POST /gift-cards/:id/redeem` (`giftCards.routes.ts:172,328`) cannot be reached from any sale UI. Recipient walks in with the code → cashier rings up sale → no "Gift Card" tile in payment methods → cashier hand-codes "Other" → no balance check, no redemption row written → server gift-card balance never decremented → physical card stays at full balance forever, customer can spend it again at next visit.** L1 primary action findability, L4 flow completion (entire redemption loop dead), L6 discoverability.
  `packages/web/src/pages/unified-pos/CheckoutModal.tsx:16,23-27,530-575`
  `packages/server/src/routes/giftCards.routes.ts:172-245,328-392`
  <!-- meta: fix=add-PaymentMethod='GiftCard'+tile-with-Gift-icon+on-select-show-code-input+lookup→show-balance-pill-"$45.00-available"+confirm-amount-(cap-at-min(due,balance))+POST-/gift-cards/:id/redeem-with-invoice_id-on-checkout-success+include-in-split-payments -->

- [ ] WEB-UIUX-1428. **[BLOCKER] No way to deliver issued code to recipient. Issue success modal shows the 32-char hex code in `select-all` div (`GiftCardsListPage.tsx:142-144`) with body copy "Save this code now — it will not be shown again." Then a single "Done" button (`:145-150`). No copy-to-clipboard, no "Email to recipient", no "Send SMS", no "Print receipt", no "Print physical card layout". Recipient_email field on the issue form (`:208-214`) is harvested but server never emails the code (no notification call in `giftCards.routes.ts:253-323`); UI never surfaces a delivery action either. Cashier must manually transcribe a 32-char hex code onto something physical, or hand the recipient an unsealed slip with the code visible. Code is lost = balance unrecoverable (server hashes the plaintext at storage; only the GET /:id endpoint returns it before a future migration drops the column). High-stakes "save this now" warning + zero tools to act on it.** L4 flow completion, L7 feedback meaningfulness, L8 recovery (zero recovery if window closed).
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:123-153, 208-214`
  `packages/server/src/routes/giftCards.routes.ts:253-323`
  <!-- meta: fix=success-modal-row-of-actions:-Copy-(navigator.clipboard.writeText)+Email-(POST-/notifications/send-gift-card-receipt)+SMS-(POST-/notifications/send-sms)+Print-(window.print-w/-printable-card-layout)+server-add-notification-helper-that-emails-recipient-when-recipient_email-set-(opt-in-checkbox-on-form) -->

#### Blocker — orphan from main navigation

- [ ] WEB-UIUX-1429. **[BLOCKER] `/gift-cards` has no Sidebar entry. `packages/web/src/components/layout/Sidebar.tsx` (549 lines) contains zero `/gift-cards` references — only Cmd+K (`CommandPalette.tsx:73`) and a notification deep-link for the `gift_card` event type (`notificationRoutes.ts:28`) reach the page. Operator who has not memorised Cmd+K has no way to discover gift-card management exists. Compounds with WEB-UIUX-1427: not only can't they redeem, they can't even find the list to know cards have been issued.** L1, L6 discoverability, L4 flow completion.
  `packages/web/src/components/layout/Sidebar.tsx:1-549 (no /gift-cards)`
  `packages/web/src/components/shared/CommandPalette.tsx:73`
  <!-- meta: fix=add-Gift-Cards-nav-item-under-Billing-or-Customers-section+Gift-icon+permission-gate-on-gift_cards.issue-OR-gift_cards.redeem -->

#### Major — Issue flow truthfulness + completeness

- [ ] WEB-UIUX-1430. **[MAJOR] IssueModal form is missing `customer_id` field — server schema accepts it (`giftCards.routes.ts:260,269-277,300`) and validates against `customers` table, but the UI form (`GiftCardsListPage.tsx:38-43,86-91,104-109`) has no customer picker. Cards are always issued unlinked. Customer Detail page therefore has no "Gift cards held by this customer" section to show. Operator selling to a known regular cannot tie the card to that account, breaking analytics + future "lookup by customer" expectations.** L4 flow completion, L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:38-43,86-91,104-109`
  `packages/server/src/routes/giftCards.routes.ts:260,269-277,300`
  <!-- meta: fix=add-CustomerPicker-(reuse-component-from-InvoiceDetail/UnifiedPos)+include-customer_id-in-issueMutation-payload+populate-from-?customer_id-query-string-when-deep-linked-from-CustomerDetailPage -->

- [ ] WEB-UIUX-1431. **[MAJOR] IssueModal "Save this code now — it will not be shown again." copy contradicts `GiftCardDetailPage.tsx:237-243` which lets ANY user with read access click the Eye toggle and reveal the full 32-char plaintext code from `card.code`. The detail page returns plaintext from `GET /gift-cards/:id` (`giftCards.routes.ts:441-451` returns `card.*` including `code` column). Either the warning is wrong (code IS still retrievable) or the detail page Show button is a security leak (server intends migration to drop the `code` column per `:293-296`). Today reality: warning is misleading + plaintext code leaks to anyone who can open the detail page (no extra permission gate beyond list-read).** L2 label truthfulness, L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:139-141`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:235-243`
  `packages/server/src/routes/giftCards.routes.ts:441-451`
  <!-- meta: fix=decide-policy:-(a)-keep-Eye-toggle+update-IssueModal-copy-to-"Show-this-code-or-email/print-now"+gate-Eye-behind-gift_cards.reveal_code-permission-OR-(b)-strip-code-from-GET-/:id-payload+remove-Eye-toggle+keep-the-warning-truthful -->

- [ ] WEB-UIUX-1432. **[MAJOR] No `notes` field on IssueModal — server schema accepts notes up to 1000 chars (`giftCards.routes.ts:260,284-286,300`) and renders them on detail/transactions, but the form (`GiftCardsListPage.tsx:38-43,177-227`) doesn't expose the input. Operator cannot annotate "given as goodwill credit for missed appointment" or "marketing campaign Q2". Reporting later cannot segment.** L4 flow, L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:38-43,177-227`
  `packages/server/src/routes/giftCards.routes.ts:260,284-286,300`
  <!-- meta: fix=add-textarea-"Notes-(optional,-internal)"-with-1000-char-max+wire-to-issueMutation-payload -->

- [ ] WEB-UIUX-1433. **[MAJOR] `GIFT_CARD_MAX_AMOUNT = $10,000` server cap (`giftCards.routes.ts:29,262-264`) never advertised in UI. Operator creating a corporate gift of $15,000 types the amount, hits Issue, gets toast "Gift card amount cannot exceed $10,000" with no inline hint or `max=` attribute on the input (`GiftCardsListPage.tsx:182-190`). Same opaque ceiling on Reload (`:402-404`).** L7 feedback meaningfulness.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:178-190`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:124-135`
  <!-- meta: fix=helper-text-below-amount-input-"Max-$10,000-per-card."+set-input-max=10000+disable-Issue-button-when-value>10000+inline-red-error-on-blur -->

- [ ] WEB-UIUX-1434. **[MAJOR] Expiry-date input is `type=date` (`GiftCardsListPage.tsx:220-225`) — picks a calendar date with no time. Server stores via `validateIsoDate` then UPDATE WHERE clause uses `expires_at > datetime('now')` UTC (`giftCards.routes.ts:365`). A card "expiring 2026-12-31" picked by a US-East cashier becomes invalid at 7pm local time on 2026-12-30 (UTC midnight rolls over) — recipient walking in at 8pm gets "Gift card expired". No timezone hint; no "End of day in your store's timezone" copy.** L7 feedback meaningfulness, L11 consistency (server stores UTC, UI ignores tz).
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:217-225`
  `packages/server/src/routes/giftCards.routes.ts:365,238-241`
  <!-- meta: fix=server-treat-expires_at-as-local-end-of-day-in-tenant-tz-(append-T23:59:59+offset)-OR-UI-helper-"Expires-at-midnight-UTC-on-this-date"+show-resolved-local-time -->

- [ ] WEB-UIUX-1435. **[MAJOR] No upfront indication that recipient_email gets nothing. Field placeholder is just "jane@example.com" (`:212`); cashier reasonably assumes filling it triggers an email of the gift-card code (Stripe / Square / every consumer SaaS does this). Reality: server stores the email but never sends anything (no notification call in the issue route). Recipient never receives the code unless cashier separately emails them outside the system. Field is decorative metadata, not an action.** L2 label truthfulness, L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:204-214`
  `packages/server/src/routes/giftCards.routes.ts:253-323`
  <!-- meta: fix=add-checkbox-"Email-this-code-to-recipient-on-issue"-(default-on-when-email-supplied)+server-honours-flag+sends-via-notificationApi+OR-rename-field-"Recipient-email-(for-records-only)" -->

#### Major — Lookup, list, filter gaps

- [ ] WEB-UIUX-1436. **[MAJOR] No code-lookup surface anywhere in UI. `GET /gift-cards/lookup/:code` (`giftCards.routes.ts:172-245`) is purpose-built for "cashier types code, system returns balance + status + expiry". Web client never invokes it. Even outside POS, an operator answering a phone call ("what's my balance on card XYZ?") has no input field — must scroll the masked-code list, and the list shows only `****XXXX` last-4 anyway, so they cannot find a card by anything but the last 4 hex chars (assuming the user can read their own code).** L1 primary action findability, L4 flow, L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:309-331`
  `packages/server/src/routes/giftCards.routes.ts:172-245`
  <!-- meta: fix=add-secondary-"Look-up-by-code"-button-next-to-"Issue-gift-card"+modal-with-code-input+barcode-scan-icon+POST-lookup→show-balance-card-(amount-status-recipient-expires)+actions-row-(redeem-disable-reload) -->

- [ ] WEB-UIUX-1437. **[MAJOR] List "Code" column shows only `****XXXX` (`GiftCardsListPage.tsx:65-68,371`) with no copy/reveal action. Cashier on the phone with customer reading "I think my code starts with A4..." cannot search by prefix — the search input matches plaintext `gc.code LIKE` (`giftCards.routes.ts:113`) BUT the list never shows the prefix. Compound problem with WEB-UIUX-1436: no lookup, no useful list view.** L4 flow, L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:65-68,370-372`
  <!-- meta: fix=show-first-4-+-last-4:-`A4F2****1234`+per-row-Eye-icon-(permission-gated)-to-reveal+per-row-Copy-icon -->

- [ ] WEB-UIUX-1438. **[MAJOR] Status filter dropdown lists only `active|used|disabled` (`GiftCardsListPage.tsx:326-330`) but `sweepExpiredGiftCards` cron sets `status='expired'` (`packages/server/src/index.ts:2647-2653`). Filter has no `expired` option → expired cards either invisible (filter='active' hides them) or jumbled into the unfiltered list with NO badge style (`statusBadge` switch cases are exhaustive over `'active'|'used'|'disabled'` per the TS type at `:16` — `expired` rows fall through and render with empty class string → unstyled grey blob).** L4 flow, L9 empty/loading/error state, L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:16,70-76,326-330`
  `packages/server/src/index.ts:2641-2653`
  <!-- meta: fix=widen-GiftCard.status-type-to-include-'expired'+add-statusBadge-case-(amber-tone)+add-<option-value="expired">Expired</option>-to-filter -->

- [ ] WEB-UIUX-1439. **[MAJOR] Status filter has `disabled` option but no UI ever sets a card to `disabled` — no Disable button on detail, no bulk action on list, server route absent. Selecting "Disabled" filter returns empty list always. Dead UI option that promises a workflow that does not exist. Either ship a Disable action (lost-card / fraud reporting) or remove the filter option.** L4 flow dead-end, L11 dead UI, L13 dead code.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:329`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-293`
  <!-- meta: fix=ship-DELETE-or-PATCH-/gift-cards/:id/disable-route+wire-Disable-button-on-detail-page-(red-secondary)-with-requireTyping-confirm+OR-remove-the-disabled-filter-option -->

- [ ] WEB-UIUX-1440. **[MAJOR] Search input has no debounce. Every keystroke into "Search code or recipient..." re-fires `useQuery` (`GiftCardsListPage.tsx:270-280,313-320`) — typing "JANE" issues 4 list+summary+count requests in under a second. Server lookup is rate-limited (`LOOKUP_RATE_LIMIT=10/min`), but the *list* endpoint isn't — still wasteful and causes flicker on the table.** L9 loading state, L11 perf hygiene.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:270-280,313-320`
  <!-- meta: fix=wrap-keyword-in-useDeferredValue-or-debounce-300ms-(reuse-existing-useDebounce-hook-from-InventoryList)-before-passing-into-queryKey -->

- [ ] WEB-UIUX-1441. **[MAJOR] No pagination controls on list. `GiftCardListData` exposes `pagination.total_pages` (`:30-35`), `useQuery` doesn't pass `page` (default page 1, per_page=50). Cards 51-N invisible. Tenants with seasonal gift-card promos pile up hundreds of cards; only the most recent 50 are reachable by the operator.** L4 flow, L9 loading state.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:264-281`
  <!-- meta: fix=add-page-state+pagination-controls-(reuse-component-used-on-CustomersListPage)+pass-{page,per_page}-into-giftCardApi.list -->

#### Major — Detail / Reload ergonomics

- [ ] WEB-UIUX-1442. **[MAJOR] Reload button hidden when `card.status === 'used'` (`GiftCardDetailPage.tsx:283-293`) — but server reload route accepts any status except `disabled` and explicitly flips back to `'active'` on success (`giftCards.routes.ts:408,415`). Customer redeems full card → status=used → operator wants to top-up the same physical card with $25 → UI hides the Reload button → operator must issue a new card and tell customer to discard the old one. Server-allowed flow, UI-blocked.** L4 flow completion, L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-293`
  `packages/server/src/routes/giftCards.routes.ts:396-438`
  <!-- meta: fix=show-Reload-when-status!=='disabled'+keep-existing-active-style+with-secondary-tone-when-status='used' -->

- [ ] WEB-UIUX-1443. **[MAJOR] Reload modal hides current balance. Operator opens modal — a single amount input + Reload button (`GiftCardDetailPage.tsx:115-155`). The big "current balance / of initial" tile lives BEHIND the modal at `:251-254`. Cashier mid-transaction asking "the customer wants me to add enough to make it $100, what's it at now?" has no in-modal info → must close modal, read balance, reopen. Add "Current: $X • New: $X+amount" line under input.** L7 feedback, L4 flow.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:115-155`
  <!-- meta: fix=pass-currentBalance-prop-to-ReloadModal+render-"Current:-$X.XX"-helper+computed-"After-reload:-$Y"-line-as-user-types -->

- [ ] WEB-UIUX-1444. **[MAJOR] `txLabel` for `'adjustment'` returns "Reload" (`GiftCardDetailPage.tsx:55-61`) — but adjustments may also be manual decrements (corrections, fraud claw-back) once that workflow exists. Hardcoding "Reload" assumes positive adjustment only. Server schema doesn't prevent a negative adjustment row. A reporting bug masquerading as a label.** L2 label truthfulness, L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:55-61`
  <!-- meta: fix=label-driven-by-sign:-amount>0?'Reload':'Adjustment'+OR-introduce-explicit-tx.subtype -->

#### Minor — labels, copy, ergonomics

- [ ] WEB-UIUX-1445. **[MINOR] Issued code is one 32-char run with `tracking-widest` (`GiftCardsListPage.tsx:142-144`) — `A4F2839B...` for 32 chars unbroken. Cashier reading aloud over phone or copying onto a card is error-prone. Industry pattern: 8x4 groups (`A4F2 839B 1C2D ...`) like credit-card formatting.** L7 feedback, L11 readability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:142-144`
  <!-- meta: fix=insert-spaces-every-4-chars+keep-select-all-(strip-spaces-on-paste-input-server-side-already-uppercases) -->

- [ ] WEB-UIUX-1446. **[MINOR] "Issue gift card" CTA appears twice on empty state (`GiftCardsListPage.tsx:300-307,345-352`) — header right-aligned button + centered empty-state button. Visually competing primary actions. Empty-state pattern usually omits the header CTA when no rows exist (or vice versa).** L5 hierarchy.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:300-307,345-352`
  <!-- meta: fix=hide-header-CTA-when-cards.length===0+rely-on-empty-state-CTA-only -->

- [ ] WEB-UIUX-1447. **[MINOR] Reload modal Cancel + Reload buttons positioned right-aligned (`GiftCardDetailPage.tsx:136-152`) but not full-width on mobile/narrow widths — viewport <420px causes button overflow under the input padding. Add `flex-col sm:flex-row` for narrow layouts.** L11 responsive.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:136-152`
  <!-- meta: fix=flex-col-gap-2-sm:flex-row-sm:justify-end-sm:gap-3+w-full-sm:w-auto-on-each-button -->

- [ ] WEB-UIUX-1448. **[MINOR] List page "Code" cell mixes monospace `font-mono` with last-4 of plaintext code (`:370-372`); recipient cell has 160px-truncated email below name (`:376-377`) but no tooltip — overflowing email is unreadable + uncopyable. Add `title={card.recipient_email}` or replace truncate with hover-expand.** L7 feedback, L11 a11y.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:373-378`
  <!-- meta: fix=add-title={card.recipient_email}-attribute+optional-aria-label -->

- [ ] WEB-UIUX-1449. **[MINOR] IssueModal close behaviour inconsistent with other modals: backdrop click closes (`:159`), Escape closes via `onKeyDown` on the wrapper (`:160`) — but `onKeyDown` only fires when the modal has focus, which it never gets after open (initial focus stays in body). Esc-to-dismiss therefore broken on first render. Compare ReloadModal which uses a `window.addEventListener('keydown', ...)` (`GiftCardDetailPage.tsx:107-113`) — works.** L11 a11y, L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:127-129,160-162`
  <!-- meta: fix=replace-onKeyDown-with-useEffect-window.addEventListener('keydown')→Escape→onClose+remove-from-wrapper -->

- [ ] WEB-UIUX-1450. **[MINOR] Issue success modal Done button is full-width primary (`GiftCardsListPage.tsx:145-150`) but offers no destination — closes the modal, drops user back at list with the new card on top. After issuing, common next step is "now hand the receipt to the customer" or "issue another for the next walk-in". A secondary "Issue another" button would shave clicks for sales bursts.** L4 flow continuity.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:145-150`
  <!-- meta: fix=add-secondary-"Issue-another"-button-(resets-form-keeps-modal-open)+primary-Done-stays -->

- [ ] WEB-UIUX-1451. **[MINOR] Detail page eye-toggle icon button has no `aria-label` (`GiftCardDetailPage.tsx:237-243`) — only a `title` attribute. Screen readers announce the icon's accessible name as nothing. Add `aria-label={showCode ? 'Hide code' : 'Show full code'}`.** L11 a11y.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:237-243`
  <!-- meta: fix=add-aria-label-prop-mirroring-title -->

- [ ] WEB-UIUX-1452. **[MINOR] No "Customer" link on Detail page even when `card.customer_id` is set on server. The detail render block (`GiftCardDetailPage.tsx:258-281`) shows recipient_name and recipient_email but never the linked customer (server includes it via JOIN on list but `GET /gift-cards/:id` returns the raw card without joining customers — `giftCards.routes.ts:441-451`). Operator on detail cannot click through to customer record. (Compound with WEB-UIUX-1430 which fixes the issue side.)** L4 flow, L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:258-281`
  `packages/server/src/routes/giftCards.routes.ts:441-451`
  <!-- meta: fix=server-LEFT-JOIN-customers-on-GET-/:id-and-include-customer-summary+UI-render-"Customer:-<Link-to=/customers/:id>name</Link>" -->

- [ ] WEB-UIUX-1453. **[NIT] Status badge for `'used'` uses surface tone (`GiftCardsListPage.tsx:73`) — visually identical to placeholder/empty state pills used elsewhere. Adds no signal that the card was actually drained vs simply inactive. Switch `'used'` to a distinct neutral with a checkmark prefix, or grey-with-strikethrough on the balance cell.** L5 hierarchy, L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:73`
  <!-- meta: fix=used-badge-grey-with-Check-icon-h-3-w-3-prefix+OR-balance-cell-line-through-when-status=used -->

- [ ] WEB-UIUX-1454. **[NIT] `formatCurrency` cents/dollars heuristic (`GiftCardsListPage.tsx:57-63`, mirrored on Detail `:41-44`) treats integers >=1000 as cents. A $999.99 card stored as float 999.99 renders as $999.99 (correct); a $10.00 card stored as integer 1000 cents renders as $10.00 (correct); but a $10 card mistakenly stored as integer 10 (dollars, not cents) renders as $10 — looks fine until you hit edge case $1500 → 1500 dollars vs 1500 cents=15 ambiguity. Comment acknowledges fragility ("if it does, it'll still render correctly because 1000.5...") but it's a ticking interpretation bomb. Drop the heuristic the moment server picks one representation.** L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:46-63`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:38-53`
  <!-- meta: fix=spike-server-→-emit-cents-only-on-/gift-cards-routes+remove-heuristic+single-formatCurrencyShared(amountCents/100) -->

- [ ] WEB-UIUX-1455. **[NIT] Lookup-rate-limit feedback (when WEB-UIUX-1436 lands) must distinguish "Too many lookup attempts" (429) from "Gift card not found" (404) and "Gift card is used/expired" (400). Server returns these as separate AppError messages (`giftCards.routes.ts:196,232,236,240`) — UI should branch on status code, not blindly toast `e.message`. 429 should also show a countdown until window reset (1 min from first failure).** L7 feedback meaningfulness, L8 recovery.
  `packages/server/src/routes/giftCards.routes.ts:196,232,236,240`
  <!-- meta: fix=on-Lookup-modal-mutation-error-branch-on-status:-429→banner-with-countdown;404→inline-"No-card-with-that-code";400→show-server-message-(used/expired);else→generic -->

### Web UI/UX Audit — Pass 31 (2026-05-05, flow walk: Approve Estimate — staff Approve, Send-via-SMS, customer-portal Approve, e-sign gap, Reject reversibility)

#### Blocker — flow integrity / state truthfulness

- [ ] WEB-UIUX-1456. **[BLOCKER] "This cannot be undone" warning on Reject is a lie. Confirm copy says `'Mark this estimate as rejected? This cannot be undone.'` (`EstimateDetailPage.tsx:237`). Server `/estimates/:id/reject` only blocks status `'rejected'` and `'converted'` (`estimates.routes.ts:1034-1035`); it does NOT block subsequent Approve. Server `/estimates/:id/approve` only blocks `'approved'` and `'converted'` (`:1068-1069`). So a rejected estimate can be Approved (admin override path), reverting status silently. UI even hides Approve when status `'rejected'` (`EstimateDetailPage.tsx:206`) but the route stays open; the customer portal flow blocks itself with `WHERE status='sent'` (`portal.routes.ts:1446`), but staff can still flip via API. Pick one truth: either server enforces the lie (add `if (status==='rejected') throw` to `/approve` + `/send`) OR UI relabels confirm to "Reject this estimate? You can re-approve later from the same page." and shows Approve on rejected.** L2 truthfulness, L4 flow integrity, L7 feedback.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:206-218,237`
  `packages/server/src/routes/estimates.routes.ts:1034-1035,1068-1069`
  <!-- meta: fix=server-/approve-rejects-status-IN-('rejected','signed')+restore-Approve-button-on-rejected-only-if-route-allows+update-confirm-copy-to-match-actual-server-behavior -->

- [ ] WEB-UIUX-1457. **[BLOCKER] `status='signed'` (set by `/public/api/v1/estimate-sign/:token` POST in `estimateSign.routes.ts:617-619`) is invisible to web. `STATUS_COLORS` in `EstimateDetailPage.tsx:16-22` and `ESTIMATE_STATUSES` in `EstimateListPage.tsx:17-24` both omit `'signed'` — falls through to grey `#6b7280` with raw `status` string label, looking identical to a `'draft'` placeholder pill. Operator opening a signed estimate has no visual cue that the customer e-signed; the legally-binding state of the estimate is rendered as "untouched draft". Same gap on portal `EstimateStatusBadge` (`PortalEstimatesView.tsx:158-169`) — but portal additionally hides `'signed'` rows via the `status IN (...)` filter (`portal.routes.ts:1382`), so the customer cannot see their own signed estimate after they sign it.** L2 truthfulness, L4 flow integrity, L11 consistency.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:16-22`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:17-24`
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:158-169`
  `packages/server/src/routes/portal.routes.ts:1382`
  <!-- meta: fix=add-{value:'signed',label:'Signed',color:'#0ea5e9'}-to-ESTIMATE_STATUSES+STATUS_COLORS+EstimateStatusBadge.colors+include-'signed'-in-portal-WHERE-status-IN-list -->

- [ ] WEB-UIUX-1458. **[BLOCKER] Portal customer Approve has NO confirm. Single tap on `'Approve Estimate'` (`PortalEstimatesView.tsx:132-140`) → optimistic flip to `approved` + immediate POST. No "Are you sure?", no "Total: $X — proceed?", no terms acceptance, no signature capture. Compare with the staff-side admin override which uses a `confirm()` modal (`EstimateDetailPage.tsx:209`) — i.e. the LOWER-stakes action (staff manually approving) requires a confirm, the HIGHER-stakes action (customer authorizing the bill) does not. Backwards. A drunk thumb-tap on the wrong row commits the customer to a $5,000 bill they meant to read first. No undo path on portal at all (no Reject, no "I changed my mind").** L4 flow, L5 hierarchy, L8 recovery, L7 feedback.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:132-140`
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:208-211`
  <!-- meta: fix=portal-Approve-opens-confirm-sheet-with-total+terms+typed-or-checkbox-acknowledgement+optional-signature-pad+single-button-"I-Approve-$X.XX" -->

- [ ] WEB-UIUX-1459. **[BLOCKER] Portal Approve doesn't enforce expiry. `valid_until` is rendered as plain text ("Valid until: Jan 5") on `PortalEstimatesView.tsx:128-130`, but Approve button shows whenever `est.status==='sent'` regardless of expiry. Server `/portal/estimates/:id/approve` (`portal.routes.ts:1437-1452`) doesn't check `valid_until` either. Customer can approve an expired estimate three months after the quote — shop is then bound to a stale price. Compare with detail page's expiry visual (`EstimateDetailPage.tsx:472`) which only renders red text but doesn't block actions.** L2 truthfulness, L4 flow integrity, L7 feedback.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:128-140`
  `packages/server/src/routes/portal.routes.ts:1437-1457`
  <!-- meta: fix=server-rejects-approve-when-valid_until-IS-NOT-NULL-AND-valid_until<datetime('now')+UI-replaces-Approve-with-"Estimate-expired-—-request-new-quote"+Re-quote-CTA -->

#### Major — discoverability / dead features

- [ ] WEB-UIUX-1460. **[MAJOR] No web UI to issue a customer e-sign URL. `estimateSign.routes.ts:233-310` ships `POST /api/v1/estimates/:id/sign-url` (HMAC-signed, single-use, signature pad capture) but `endpoints.ts:893-913` deliberately omits the `estimateApi.signUrl` wrapper with a comment "mobile-only today" — meaning **web-only shops cannot capture customer signatures at all**. The `EstimateDetailPage` has Send (SMS quote with no sign link), Approve (admin override, no signature), Convert, Reject — but no "Send for signature" button. Counter-signed work-orders are a legal requirement in many states for electronics repair. Wire `estimateApi.signUrl(id, ttl)` + a `<SignLinkModal>` that copies the URL / triggers SMS via existing `/send` and shows captured signatures via existing `/signatures` GET (`estimateSign.routes.ts:316-352`).** L4 flow, L6 discoverability.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:190-256`
  `packages/web/src/api/endpoints.ts:886-896`
  `packages/server/src/routes/estimateSign.routes.ts:233-352`
  <!-- meta: fix=add-estimateApi.signUrl(id,ttl_minutes)+estimateApi.signatures(id)+SignLinkModal-with-copy/SMS/QR+section-on-EstimateDetail-listing-captured-signatures+make-mobile-only-comment-obsolete -->

- [ ] WEB-UIUX-1461. **[MAJOR] Send button on `EstimateDetailPage.tsx:191-205` and `EstimateListPage.tsx:737-764` confirms `'Send this estimate to the customer via SMS?'` with no preview of (a) destination phone, (b) message body, (c) channel choice. Server hardcodes the message `Hi ${first_name}, your estimate ${order_id} for $${total} is ready. Reply YES to approve or view details at your repair shop.` (`estimates.routes.ts:984`) — operator can't see what customer will receive, can't see masked recipient phone, can't catch a stale customer record. Standard SaaS pattern: confirm shows "To: ***-***-1234 — [Edit phone]" plus a collapsible "Message preview". Bonus: "Reply YES to approve" is a promise the inbound-SMS handler may not honor (no YES auto-approval handler in `sms.routes.ts` last grep) — see WEB-UIUX-1462.** L7 feedback, L1 findability.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:193-204`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:744-763`
  `packages/server/src/routes/estimates.routes.ts:984`
  <!-- meta: fix=replace-confirm()-with-SendEstimateModal:-show-masked-phone+message-preview+"Edit-phone"-link+optional-edit-message-textarea -->

- [ ] WEB-UIUX-1462. **[MAJOR] SMS body promises `'Reply YES to approve'` (`estimates.routes.ts:984`) but no inbound SMS handler maps `YES`→approve. Customer texts YES, gets either nothing or off-hours auto-reply. The Approve flow today is portal login + tap, OR staff admin override. Either drop the false promise from the SMS template (e.g. `"View at <portal-link>"`) or wire the inbound handler in `sms.routes.ts` to call `/portal/estimates/:id/approve` when the matched customer's most-recent sent estimate gets a YES inside the rate window.** L2 truthfulness, L4 flow.
  `packages/server/src/routes/estimates.routes.ts:984`
  <!-- meta: fix=verify-no-YES-handler-then-either-(a)-replace-template-with-"View+approve:-${portalLink}"-OR-(b)-implement-inbound-YES-handler-with-1-recent-estimate-disambiguation -->

- [ ] WEB-UIUX-1463. **[MAJOR] Self-approval block surfaces as runtime toast, not pre-disabled button. Server returns `403 'Cannot approve your own estimate. Another admin must approve this one.'` (`estimates.routes.ts:1138-1143`) when creator===approver; UI shows the Approve button regardless then surprises with the toast on click. Pre-disable when `req.user.id === estimate.created_by` and tooltip "You created this estimate — another admin must approve."** L1 findability, L7 feedback, L8 recovery.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:206-218`
  `packages/server/src/routes/estimates.routes.ts:1138-1143`
  <!-- meta: fix=use-useAuthStore-currentUser.id-vs-estimate.created_by+disable+tooltip+also-grey-out-on-list-row-action-button -->

- [ ] WEB-UIUX-1464. **[MAJOR] Reject has no creator self-block. Server `/reject` (`estimates.routes.ts:1021-1047`) lets the creator reject their own estimate — asymmetric with Approve. If two-party authorization is the policy (Approve enforces it), Reject should too: an angry creator can silently kill their own estimate without peer review. Or the policy is "self-Reject is fine because no money moved" — make it explicit in code + audit row.** L11 consistency, L4 flow integrity.
  `packages/server/src/routes/estimates.routes.ts:1021-1047`
  <!-- meta: fix=mirror-self-approve-block:-if-(req.user?.id===existing.created_by)-throw-403-OR-explicitly-document-asymmetric-policy-via-comment+changelog -->

- [ ] WEB-UIUX-1465. **[MAJOR] Portal hides estimate history once nothing is pending. `PortalDashboard.tsx:89-92,146-152` only render the "Pending Estimates" card and "View Estimates" CTA when `dashboard.pending_estimates > 0`. Customer with three approved estimates and no new ones cannot reach the estimate list page from the dashboard at all (no nav link, no "All estimates" tab). Past quotes / line-item history / "what was that estimate from June for again?" inaccessible. Add a persistent "Estimates" link with a `(N total)` count when pending=0.** L4 flow, L6 discoverability.
  `packages/web/src/pages/portal/PortalDashboard.tsx:89-103,144-162`
  <!-- meta: fix=always-render-Estimates-CTA-(disabled-grey-when-total=0)+badge-shows-pending-count-only-when>0+secondary-style-when-no-action-needed -->

- [ ] WEB-UIUX-1466. **[MAJOR] Portal estimate list mixes draft + sent + approved + converted in raw `created_at DESC` order (`portal.routes.ts:1378-1385`). Newest-first is fine for shop-side; for customer-side the ranking should be (a) action-required first (sent), (b) recent-history second (approved/converted), (c) drafts hidden entirely (drafts are works-in-progress not meant for customer eyes). Today a customer browsing sees a `'draft'` row with no Approve button — looks like a broken estimate. Server should drop `'draft'` from the IN-list (or UI should hide draft rows).** L11 consistency, L4 flow integrity.
  `packages/server/src/routes/portal.routes.ts:1382`
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:94-148`
  <!-- meta: fix=server-WHERE-status-IN-('sent','approved','converted','signed')+ORDER-BY-CASE-status-WHEN-'sent'-THEN-0-ELSE-1-END,created_at-DESC -->

#### Major — feedback / recovery

- [ ] WEB-UIUX-1467. **[MAJOR] Portal Approve error messaging swallows server intent. Server returns 404 with `code:ERR_RESOURCE_NOT_FOUND` and message `'Estimate not found or already processed'` (`portal.routes.ts:1450`); UI swallows the entire branch and toasts generic `'Failed to approve estimate. Please try again.'` (`PortalEstimatesView.tsx:47`). Customer who already approved on another tab gets "try again" → infinite loop. Surface the server message instead, and on 404 refresh the list so the optimistic flip sticks (the row is now genuinely approved server-side).** L7 feedback, L8 recovery.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:37-50`
  `packages/server/src/routes/portal.routes.ts:1450`
  <!-- meta: fix=read-err.response.data.message+if-404-call-getEstimates()-to-refresh+toast.success-"Already-approved"-when-server-confirms -->

- [ ] WEB-UIUX-1468. **[MAJOR] No "no phone on file" recovery on Send. Server returns `sent:false` + `warning:'Customer has no phone number on file.'` (`estimates.routes.ts:1010-1011`), UI surfaces the warning as a single toast (`EstimateDetailPage.tsx:77`, `EstimateListPage.tsx:459`) — no "Add phone" button, no link to the customer record. Operator must manually navigate Customers → search → edit → save → back to estimate → Send again. 5 clicks for a missing field that's one-tap to fix inline.** L8 recovery, L4 flow.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:71-83`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:454-466`
  `packages/server/src/routes/estimates.routes.ts:1009-1012`
  <!-- meta: fix=on-no-phone-warning-toast-includes-action-button-"Add-phone"-opening-an-inline-PhoneEditModal-then-auto-retries-Send-on-save -->

- [ ] WEB-UIUX-1469. **[MAJOR] `estimateApi.send(id, method?: 'sms' | 'email')` (`endpoints.ts:906`) advertises an `email` channel but server explicitly rejects it: `if (rawMethod !== 'sms') throw new AppError(...)` (`estimates.routes.ts:967-969`). Lying API surface — first time a future caller types `.send(id, 'email')` they get a runtime 400 instead of a TS error. Either implement email send (uses existing email provider in `sendEstimate` flow elsewhere) or narrow the type to `method?: 'sms'`.** L2 truthfulness, L11 consistency.
  `packages/web/src/api/endpoints.ts:906`
  `packages/server/src/routes/estimates.routes.ts:963-970`
  <!-- meta: fix=narrow-method-type-to-'sms'-OR-implement-email-via-emailProvider+respect-customer.contact_preference -->

- [ ] WEB-UIUX-1470. **[MAJOR] Portal Approve success has no toast / next-step prompt. After successful approve (`PortalEstimatesView.tsx:38-40`) UI just keeps the optimistic flip and renders the green Approved badge. No "Thanks — your shop has been notified, expect a call within 24h", no "Add to calendar", no link to View Repairs page (where ticket appears once status flips). Customer left on same screen wondering "did anything happen?". Worst: optimistic UI means the visual change happens BEFORE the server confirms — the customer sees Approved even on a stalled request that hasn't yet failed.** L7 feedback, L4 flow.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:37-50`
  <!-- meta: fix=on-success-show-success-banner-"Estimate-approved.-Shop-has-been-notified."-+CTA-"View-your-repair"-deep-link-to-ticket-detail+optional-toast-with-undo-(server-allows-via-staff-Reject-still) -->

#### Minor — labels, copy, hierarchy

- [ ] WEB-UIUX-1471. **[MINOR] Approve confirm copy `'Mark this estimate as approved?'` (`EstimateDetailPage.tsx:209`) doesn't disclose this is the *staff override* path — bypasses customer signature, customer ack, customer SMS-reply. In jurisdictions requiring written customer consent for repair work (CA BPC §9844, NY GBL §399-aa, etc.) this matters. Add subline: "This bypasses customer signature. Use only when customer has authorized in person and you have noted authorization in the work-order."** L2 truthfulness, L7 feedback.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:209`
  <!-- meta: fix=confirm-with-{title:'Approve-on-customer-behalf?',body:'This-bypasses-the-e-sign-flow.-Use-only-when-customer-has-authorized-in-person-and-you-have-recorded-authorization.',confirmLabel:'Approve-on-behalf'} -->

- [ ] WEB-UIUX-1472. **[MINOR] `'Convert to Ticket'` button shows on `'rejected'` estimates? No — UI hides at `EstimateDetailPage.tsx:219`. But it DOES show on `'signed'` estimates, and Convert clobbers the signed status (`status='converted'` overwrites). The captured signature stays in `estimate_signatures` table but the estimate's status no longer reflects "customer signed before conversion" — operator looking back at a converted ticket has to dig into a separate Signatures admin view (which doesn't exist on web — see WEB-UIUX-1460). Convert should preserve signed-state somewhere visible: e.g. converted ticket carries `signed_by` and `signed_at` from the original estimate.** L11 consistency, L4 flow integrity.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:219-231`
  `packages/server/src/routes/estimates.routes.ts:865-873`
  <!-- meta: fix=on-convert-copy-signed_by/signed_at/signature_id-onto-tickets-table+render-"Customer-signed-on-Date-by-Name"-on-ticket-detail-when-source-estimate-was-signed -->

- [ ] WEB-UIUX-1473. **[MINOR] Reject button shows on `'approved'` estimates without warning. UI gates Reject on `status !== 'converted' && status !== 'rejected'` (`EstimateDetailPage.tsx:233`) — so an approved estimate can be Rejected, silently nuking the customer authorization. Confirm copy doesn't mention "this estimate is currently approved by the customer". Add: when status==='approved', confirm body adds "Customer approved this on Mar 5. Rejecting will revoke their authorization."** L7 feedback, L8 recovery.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:233-247`
  <!-- meta: fix=conditional-confirm-body-string-when-estimate.status==='approved'-or-'signed'-with-approved_at-formatted -->

- [ ] WEB-UIUX-1474. **[MINOR] Approve / Reject / Send / Convert buttons sit in a horizontal `flex` group (`EstimateDetailPage.tsx:190`) with no visual ranking — Send (border-primary), Approve (border-emerald), Convert (border-green), Reject (border-red), Print (border-surface). Five buttons, four colors of "outline-with-tint". The destructive (Reject) and the legally-binding (Approve) have similar visual weight to the routine (Send, Print). Hierarchy: highest-leverage = solid filled button, secondary = outline, destructive = red outline at far end with separator. Today a sleepy operator could miss-click Reject for Send (both icon-+-text in identical button shells).** L5 hierarchy, L11 consistency.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:190-255`
  <!-- meta: fix=primary-CTA-is-context-dependent-(Send-when-draft;-Convert-when-approved);-secondary-outline-for-others;-Reject-pinned-right-with-`ml-auto`-divider+red-outline -->

- [ ] WEB-UIUX-1475. **[MINOR] No pagination on portal estimate list (`PortalEstimatesView.tsx:94-152`). Server hard-caps at 50 (`portal.routes.ts:1384`). Customer with 51+ historical estimates sees only newest 50, no warning, no "Load more". Compare with staff `EstimateListPage` which has full pagination + per-page selector (`:840-913`).** L4 flow, L9 loading state.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:94-152`
  `packages/server/src/routes/portal.routes.ts:1384`
  <!-- meta: fix=portal-route-takes-?page+?per_page-with-bounds+UI-renders-load-more-button-or-paginator -->

- [ ] WEB-UIUX-1476. **[MINOR] Portal Approve button is `bg-green-600` solid white-text (`PortalEstimatesView.tsx:136`) — same green as success toasts, success badges, "Save" buttons elsewhere in the portal. No visual signal that this is a financial commitment. Conventional accounting-software pattern: amber or "review" tone with explicit "$X" in the button label, e.g. `'Approve & authorize $1,234.56'`. Embeds the amount so the click is contextual, not abstract.** L5 hierarchy, L7 feedback.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:132-140`
  <!-- meta: fix=button-label-includes-formatted-total+secondary-amber-tone+optional-icon-CreditCard-or-FileSignature -->

- [ ] WEB-UIUX-1477. **[MINOR] No filter / sort options on staff estimate list for `'signed'`. `ESTIMATE_STATUSES` filter pills (`EstimateListPage.tsx:17-24`) cover `draft|sent|approved|rejected|converted` but not `signed`. After WEB-UIUX-1457 lands the pill must be added so operators can find recently-signed estimates pending conversion. Compare with the workflow expectation: customer e-signs → estimate.status='signed' → operator's queue should surface "ready to convert".** L1 findability, L6 discoverability.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:17-24`
  <!-- meta: fix=add-{value:'signed',label:'Signed',color:'#0ea5e9'}-as-fifth-pill-AFTER-Approved -->

- [ ] WEB-UIUX-1478. **[MINOR] EstimateDetailPage Approve+Convert+Send+Reject all use `await confirm(...)` wrapped in try/catch with `formatApiError(err)` (`:197,210,223,239`). The `confirm()` rejection on backdrop-cancel is treated as an error path — toast.error fires with whatever `formatApiError` returns from a non-Error rejection. Backdrop-cancel should be a no-op, not an error toast. (Same pattern in `EstimateListPage.tsx:751,776,798` — comment WEB-FM-020 documents this as deliberate but the user-facing effect is a noisy spurious toast on every cancel.)** L7 feedback, L8 recovery.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:193-247`
  `packages/web/src/pages/estimates/EstimateListPage.tsx:744-820`
  `packages/web/src/stores/confirmStore.ts`
  <!-- meta: fix=confirm()-resolves-false-on-cancel/Esc/backdrop-(not-rejects)+remove-try/catch-or-narrow-catch-to-unexpected-throws -->

- [ ] WEB-UIUX-1479. **[NIT] Approve mutation success toast says `'Estimate approved'` (`EstimateDetailPage.tsx:89`) but doesn't surface follow-on side effects: server auto-flips linked ticket status when `store_config.ticket_status_after_estimate` is set (`estimates.routes.ts:1187-1204`). Operator approves an estimate, ticket status silently changes from "Awaiting Estimate" to "Approved — Ready for Repair" — neither toast nor refetch invalidates the ticket query. Cross-page state drift. Toast: `'Estimate approved — ticket #1234 advanced to "Ready for Repair"'`.** L7 feedback, L11 consistency.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:85-92`
  `packages/server/src/routes/estimates.routes.ts:1187-1204`
  <!-- meta: fix=server-returns-ticket_status_changed:{id,name}-in-approve-response+UI-toast-with-link+queryClient.invalidateQueries(['ticket',ticketId]) -->

- [ ] WEB-UIUX-1480. **[NIT] EstimateDetailPage doesn't refetch the estimates LIST cache after approve/reject/send/convert; only `['estimate',id]` is invalidated (`:74,88,107,119,131`). Returning to `/estimates` shows stale status badge until a manual refresh. Add `queryClient.invalidateQueries({ queryKey: ['estimates'] })` everywhere (parallels the list page which does this correctly at `:463,485,495`).** L11 consistency, L7 feedback.
  `packages/web/src/pages/estimates/EstimateDetailPage.tsx:74,88,107,119,131`
  <!-- meta: fix=add-invalidateQueries(['estimates'])-alongside-each-invalidateQueries(['estimate',id]) -->

- [ ] WEB-UIUX-1481. **[NIT] `EstimateStatusBadge` on portal capitalizes status with `status.charAt(0).toUpperCase() + status.slice(1)` (`PortalEstimatesView.tsx:167`). For multi-word future statuses (`partially_paid`, `awaiting_signature`) it'll render `Partially_paid`. Replace with `replace(/_/g,' ').replace(/\b\w/g, c => c.toUpperCase())` or label-from-config map (matches the staff side `ESTIMATE_STATUSES.label` pattern).** L2 truthfulness, L11 consistency.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:158-169`
  <!-- meta: fix=labelMap={sent:'Awaiting-approval',approved:'Approved',signed:'Signed',rejected:'Declined',converted:'In-progress',draft:'Draft'}+badge-uses-label-not-status -->

- [ ] WEB-UIUX-1482. **[NIT] Portal `EstimateSummary.line_items[].discount` (`portalApi.ts:155`) is always `0` — server `portal.routes.ts:1421-1428` hardcodes `discount: 0` even when the estimate has a header-level discount. Customer sees Total = subtotal+tax with no Discount line, then questions "where did the discount go?". Render header-level discount above Total (server already returns `discount` on the summary `:1414`).** L7 feedback, L2 truthfulness.
  `packages/web/src/pages/portal/PortalEstimatesView.tsx:120-125`
  `packages/server/src/routes/portal.routes.ts:1421-1428`
  <!-- meta: fix=portal-renders-Subtotal+Discount-(if>0)+Tax+Total-block-instead-of-just-Total -->

- [ ] WEB-UIUX-1483. **[NIT] EstimateListPage row Send confirm and Approve confirm don't pass `confirmLabel` (`:747,770,815`) — defaults to "Confirm" / "OK" depending on the confirmStore implementation. Reject correctly passes `{confirmLabel:'Reject', danger:true}` (`:794`). Standardize: every confirm gets a verb-matching label. Generic "Confirm" loses the action context for screen readers reading the dialog title.** L7 feedback, L11 a11y.
  `packages/web/src/pages/estimates/EstimateListPage.tsx:747,770,815`
  <!-- meta: fix=Send-confirmLabel:'Send'+Convert-confirmLabel:'Convert'+Delete-confirmLabel:'Delete'+danger:true-on-Delete -->

### Web UI/UX Audit — Pass 32 (2026-05-05, flow walk: Cancel Subscription — admin list, customer detail, server gates, past_due retry, customer-portal self-service)

#### Blocker — flow-breaking, dead actions, compliance

- [ ] WEB-UIUX-1484. **[BLOCKER] CustomerDetailPage Cancel button (`CustomerDetailPage.tsx:998-1005`) fires `cancelMut.mutate()` directly on click — NO confirm modal. Sibling SubscriptionsListPage wraps cancel in `confirm({ danger: true })` (`SubscriptionsListPage.tsx:158-164`). Single misclick on member card = instant immediate cancel + `customers.active_subscription_id = NULL`. Same destructive op, two paths, only one gated.** L8 recovery, L1 truthfulness, L7 feedback.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:998-1005`
  <!-- meta: fix=wrap-cancelMut.mutate()-in-await-confirm({title,confirmLabel:'Cancel-membership',danger:true})+match-list-page-pattern -->

- [ ] WEB-UIUX-1485. **[BLOCKER] Cancel UI is immediate-only. SubscriptionsListPage hardcodes `{ immediate: true }` (`:114`); CustomerDetailPage does the same (`:905`). Server `/membership/:id/cancel` supports `immediate: false` → sets `cancel_at_period_end = 1` (`membership.routes.ts:233-234`). UI never sends that path. Customer paid for the month, gets zero remaining-period access. Industry default = end-of-period cancel. Worse: the "Cancels {date}" badge (`SubscriptionsListPage.tsx:244-249`) and "Cancels at period end" pill (`CustomerDetailPage.tsx:983-985`) are dead branches — UI displays them but no UI codepath sets the flag.** L1 truthfulness, L3 hierarchy, L8 recovery.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:113-114,158-164,244-249`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:904-911,983-985`
  <!-- meta: fix=add-radio-in-confirm-modal:Cancel-now-vs-Cancel-at-period-end+default-to-period-end+pass-immediate:false-when-selected -->

- [ ] WEB-UIUX-1486. **[BLOCKER] No customer-portal self-service cancel/pause. `/membership/:id/cancel` is gated `requireAdmin` (`membership.routes.ts:222-224`); customer portal (`CustomerPortalPage.tsx`) has zero membership management surface. Customer must call/email staff to cancel a recurring charge. FTC Click-to-Cancel rule (effective 2026-07) and CA SB-313 require self-service cancel as easy as enrollment — `/membership/payment-link` enrolls with one tap. Compliance + churn-blocker.** L1 truthfulness, L8 recovery, L6 discoverability.
  `packages/server/src/routes/membership.routes.ts:222-239`
  `packages/web/src/pages/portal/CustomerPortalPage.tsx (no membership panel)`
  <!-- meta: fix=add-portal-route-/portal/membership+server-route-/portal/membership/cancel-(token-auth-not-requireAdmin)+optional-survey-+-confirmation-email -->

- [ ] WEB-UIUX-1487. **[BLOCKER] Duplicate `POST /:id/run-billing` route registrations on the same router (`membership.routes.ts:317` AND `:452`). Express resolves first match → second handler is dead code. The dead handler has the more useful `?force=1` override (`:460,483-491`); the live handler has none (`:344-353`). "Bill now" button hits the no-force handler — if `current_period_end` still in future, returns 409 "Subscription is not yet due" with no recourse. Manual retry of failed billing on a still-current period is impossible.** L8 recovery, L1 truthfulness.
  `packages/server/src/routes/membership.routes.ts:317-402,452-545`
  <!-- meta: fix=delete-second-handler-OR-delete-first+keep-the-?force=1-supporting-one+add-Force-billing-checkbox-in-Bill-now-confirm -->

#### Major — recovery gaps, discoverability, role gates

- [ ] WEB-UIUX-1488. **[MAJOR] "Bill now" button hidden for `past_due` rows (`SubscriptionsListPage.tsx:260` — guard is `sub.status === 'active' && sub.blockchyp_token`). past_due is the primary use case for manual retry; "active" rows aren't due yet (server returns 409 unless force). Admin literally cannot retry a failed charge from list view; must wait for nightly cron or use server console. Server permits past_due (`:334-335` blocks only cancelled/paused).** L8 recovery, L3 hierarchy.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:260`
  <!-- meta: fix=guard-(sub.status==='active'||sub.status==='past_due')&&sub.blockchyp_token+rename-button-to-'Retry-charge'-when-past_due -->

- [ ] WEB-UIUX-1489. **[MAJOR] SubscriptionsListPage has no sidebar/nav entry. Page registered at `App.tsx:540` but no Sidebar/AppLayout link references `/subscriptions` (only `CommandPalette.tsx:72` aliases it). Admin must know the URL or hit Cmd-K. Memberships are a primary revenue surface — invisible navigation. Compare: Customers, Tickets, Inventory all have sidebar entries.** L6 discoverability, L3 hierarchy.
  `packages/web/src/App.tsx:540` + missing sidebar entry
  <!-- meta: fix=add-Sidebar-entry-{label:'Memberships',path:'/subscriptions',icon:Crown,group:'Customers'}+gate-by-feature-flag-isMembershipsEnabled -->

- [ ] WEB-UIUX-1490. **[MAJOR] Cancel/Pause/Resume buttons rendered for every authenticated user with no role gate (`SubscriptionsListPage.tsx:275-284`, `CustomerDetailPage.tsx:988-1018`). Server returns 403 for non-admins (`requireAdmin` on cancel/pause/resume routes). Cashier clicks Cancel → confirm dialog → 403 → "Failed to cancel subscription" toast (`:121`). Bill-now button correctly uses `<AdminOnly>` wrapper (`:261-273`); cancel does not. Same role rules, inconsistent gating.** L1 truthfulness, L7 feedback.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:275-284`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:988-1018`
  <!-- meta: fix=wrap-Cancel/Pause/Resume-in-AdminOnly+OR-disable-with-tooltip-'Admin-only'-for-staff -->

- [ ] WEB-UIUX-1491. **[MAJOR] `POST /:id/resume` does not check current status (`membership.routes.ts:251-258`). Calling resume on a `cancelled` row sets `status='active'` — but `customers.active_subscription_id` was nulled on immediate cancel (`:232`), never restored. Result: cs.status='active' but customer.active_subscription_id=NULL → POS won't apply membership discount, list shows row as active, customer detail shows no membership card (queries by active_subscription_id). Data inconsistency reachable via API. UI hides resume for cancelled but server is the source of truth.** L4 flow completion, L1 truthfulness.
  `packages/server/src/routes/membership.routes.ts:251-258`
  <!-- meta: fix=if-status==='cancelled'-throw-AppError('Cancelled-subs-cannot-be-resumed-create-new-subscription')+OR-also-restore-active_subscription_id-on-resume -->

- [ ] WEB-UIUX-1492. **[MAJOR] Cancel mutation onError swallows server detail (`SubscriptionsListPage.tsx:120-122` and `CustomerDetailPage.tsx:910`): `toast.error('Failed to cancel subscription')`. Sibling subscribe/runBilling mutations correctly surface `err?.response?.data?.message` (`:135-138, 901`). Cancel failures (403 admin-required, 404 not-found, 503 feature-disabled) all collapse to the same opaque toast. Admin can't distinguish "bug" from "permission".** L7 feedback meaningfulness.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:120-122`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:910`
  <!-- meta: fix=onError:(err)=>toast.error(err?.response?.data?.message||formatApiError(err)||'Failed-to-cancel-subscription') -->

- [ ] WEB-UIUX-1493. **[MAJOR] After immediate cancel, customer-detail Membership card disappears entirely. `getCustomerMembership` returns null when `active_subscription_id` is NULL (set on cancel `membership.routes.ts:232`); UI then renders the enroll prompt (`CustomerDetailPage.tsx:1024+`). Lost context: admin opening cancelled customer can't see prior tier, tenure, last charge, or churn date. No way to view past memberships at all (only payment-history endpoint, no UI).** L9 empty/loading/error, L8 recovery.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:935,1024+`
  `packages/server/src/routes/membership.routes.ts:129-150`
  <!-- meta: fix=server-include-most-recent-cancelled-sub-when-no-active+UI-render-'Previously:-{tier}-cancelled-{date}'-collapsed-card+add-View-history-link-to-payments-table -->

#### Minor — labels, copy, missing capture

- [ ] WEB-UIUX-1494. **[MINOR] "Run billing now" header button (`SubscriptionsListPage.tsx:81-95`) is fake — clicking shows toast "Billing cron runs nightly automatically. Use server console to trigger manually." Visual button affordance, no action. Admins click expecting an action; get a "go elsewhere" message. Either remove the button or make it post `/membership/admin/run-cron-now` (route doesn't exist — would need adding) instead of dressing up a tooltip as a button.** L1 truthfulness, L7 feedback.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:81-95`
  <!-- meta: fix=remove-RunBillingButton-OR-add-server-route-POST-/membership/admin/run-billing-cron+wire-button-to-call-it+show-progress-toast-with-counts -->

- [ ] WEB-UIUX-1495. **[MINOR] Cancel button label is bare "Cancel" on both pages (`SubscriptionsListPage.tsx:282`, `CustomerDetailPage.tsx:1004`). Ambiguous — "cancel this dialog" vs "cancel membership", especially in CustomerDetailPage where there is no preceding modal. Convention for destructive subscription ops: "Cancel membership" / "End plan". Single-word "Cancel" next to "Pause" reads as parallel verbs but they're not — Pause is reversible, Cancel is terminal.** L1 truthfulness, L5 hierarchy.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:282`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:1003-1004`
  <!-- meta: fix=label-'Cancel-membership'-OR-'End-plan'+keep-confirm-modal-confirmLabel-'Cancel-subscription' -->

- [ ] WEB-UIUX-1496. **[MINOR] Pause action takes no reason despite server `pause_reason` column + API supporting `{ reason }` body (`membership.routes.ts:241-249`, `endpoints.ts:1324-1325`). UI calls `membershipApi.pause(id)` with no body (`CustomerDetailPage.tsx:914`). Reason is exactly the kind of data ops needs to triage paused members ("vacation", "financial", "switching tier") — column will always be NULL.** L7 feedback, L1 truthfulness.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:913-920`
  <!-- meta: fix=pause-opens-small-modal-with-reason-textarea-(or-preset-pills:Vacation/Financial/Other)+pass-reason-to-pause-mutation -->

- [ ] WEB-UIUX-1497. **[MINOR] No cancellation reason capture. Confirm dialog (`SubscriptionsListPage.tsx:158-161`) accepts only yes/no. Standard SaaS retention flow asks "Why are you cancelling?" with preset pills + optional comment — feeds the churn dashboard. Currently the only data point on cancel is the audit row (`:237`), which records `subscription_id, immediate` and nothing else.** L7 feedback, L9 empty/loading/error.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:155-168`
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:904-911`
  `packages/server/src/routes/membership.routes.ts:222-239`
  <!-- meta: fix=replace-confirm-with-CancelReasonModal+server-accept-reason-string+store-in-customer_subscriptions.cancel_reason+audit-payload -->

- [ ] WEB-UIUX-1498. **[MINOR] Cancel confirm copy: "Cancel ... membership immediately?" (`SubscriptionsListPage.tsx:159`) — word "immediately" only meaningful relative to a cancel-at-period-end alternative the UI doesn't offer (see -1485). Even with both options added, dialog should surface impact: "Customer loses {tier_name} discount + benefits today. Last charge {date}, ${amount}. No refund issued." Currently customer has no idea what they're giving up.** L7 feedback.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:158-161`
  <!-- meta: fix=confirm-body-include-tier-name+last_charge_amount+current_period_end+'No-refund'-line+benefits-list -->

- [ ] WEB-UIUX-1499. **[MINOR] No proration / refund logic on immediate cancel. Server immediately flips status + nulls active_subscription_id (`membership.routes.ts:229-232`); customer paid for month, loses access today, receives no refund. Either the cancel flow should offer "Cancel at period end" (preferred default — see -1485) or trigger a prorated credit-note. Currently there is no automatic refund and the UI shows no refund affordance after cancel.** L8 recovery, L1 truthfulness.
  `packages/server/src/routes/membership.routes.ts:222-239`
  <!-- meta: fix=on-immediate-cancel-compute-prorated-amount=last_charge*(remaining_days/period_days)+offer-refund-or-credit-note+OR-default-to-cancel-at-period-end -->

- [ ] WEB-UIUX-1500. **[NIT] Subscription rows for cancelled subs disappear from list (`membership.routes.ts:283` filters `IN ('active','past_due','paused')`). No history view for admins to audit churn — "did Anya cancel last week or did her card decline?" requires reading the audit log table directly. Add a `?status=cancelled` query param + a "Show cancelled" toggle on the list page.** L9 empty/loading, L6 discoverability.
  `packages/server/src/routes/membership.routes.ts:274-289`
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:104-111`
  <!-- meta: fix=server-accept-?include=cancelled+UI-toggle-'Show-cancelled'-default-off+sort-cancelled-to-bottom -->

- [ ] WEB-UIUX-1501. **[NIT] Cancel and Pause icons missing on SubscriptionsListPage row actions (`:275-284`) but present on CustomerDetailPage (`Pause`, `X` icons `:995,1003`). List view shows just text buttons, customer-detail shows icon+text. Inconsistent visual weight; users scanning the list lose the affordance cue. Either both icon+text or both text-only.** L5 hierarchy, L11 visual consistency.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:275-284`
  <!-- meta: fix=add-X-icon-before-Cancel-text+add-Pause-button-on-list-page-(missing-entirely)-with-Pause-icon -->

- [ ] WEB-UIUX-1502. **[NIT] Pause button missing entirely from SubscriptionsListPage. Customer Detail offers Pause + Cancel for active subs (`CustomerDetailPage.tsx:988-1006`); list view offers only Cancel (`:275-284`). Admin processing many "going on vacation" pauses must drill into each customer detail. List should expose pause as the lower-friction reversible alternative to cancel.** L4 flow completion, L8 recovery.
  `packages/web/src/pages/subscriptions/SubscriptionsListPage.tsx:275-284`
  <!-- meta: fix=add-Pause-button-row-action-mirror-CustomerDetailPage-pattern+pauseMut-with-reason-capture -->

- [ ] WEB-UIUX-1503. **[NIT] CustomerDetailPage status pill (`:952-954`) renders raw enum value `{memberData.status}` — shows "past_due" verbatim instead of "Past due". SubscriptionsListPage uses `statusLabel(status)` helper (`:51-58`) for the same data. Same enum, two render paths, inconsistent capitalization.** L11 readability.
  `packages/web/src/pages/customers/CustomerDetailPage.tsx:952-954`
  <!-- meta: fix=import-statusLabel-from-shared-helper-OR-inline-replace('_',' ')-+-titleCase -->

## Deferred operational items

- [ ] OPS-DEFERRED-001. **Multi-platform setup migration (`setup.bat` → `setup.mjs`) + cross-platform auto-startup adapter.**
  - [x] **Phase 0 LANDED 2026-05-05**: per-OS gateway shims (`setup.bat` + `setup.command` + `setup.sh`) verify Node v22-24 and best-effort install via winget / Homebrew / apt-dnf-yum-pacman-zypper-apk-NodeSource, falling back to opening `https://nodejs.org/en/download/` on any failure.
  - [x] **Phase 1 LANDED 2026-05-05**: `setup.mjs` is now a full cross-platform 12-step install/update flow (preflight → git pull → pm2 stop → npm install → .env → certs → build → Android APK conditional → dashboard build → pm2 start+save → autostart register → open browser). Cross-platform autostart adapter at `scripts/autostart/{index,linux,darwin,win32}.mjs` with one entrypoint and three OS-specific implementations (Linux: `pm2 startup systemd` + `pm2 save`; macOS: `pm2 startup launchd` + `pm2 save`; Windows: Task Scheduler XML via `schtasks` — NO vendored binaries, NO PowerShell scripts). Single transitional Windows-only branch in setup.mjs for the Electron-package step (electron-builder is `--win`-flagged in packages/management/package.json); goes away when [dashboard-migration-plan.md](./docs/dashboard-migration-plan.md) Phase E ships. `scripts/setup-windows.bat` retained as escape hatch + reference; no longer invoked by setup.mjs.
  - Verified: bash -n + node --check pass on all 7 setup files; partial smoke run on macOS (preflight → pm2 stop → npm install) reaches step 4 cleanly; autostart adapter exports verified via direct module import + status() call.
  - [ ] **Phase 2** (when unblocked): delete `scripts/setup-windows.bat`. Requires soak time on Windows operators using the new `setup.bat → setup.mjs` flow without falling back. Also: Windows host validation of Task Scheduler XML adapter (untested — author has no Windows host).
  - Acceptance when fully unblocked: fresh boot on Linux/macOS/Windows brings CRM online without user login; zero `process.platform === 'win32'` branches outside the three adapter files (pending Electron-package transition); `scripts/setup-windows.bat` deleted.
  - Related: [dashboard-migration-plan.md](./docs/dashboard-migration-plan.md) Phase C-pre — `setup.mjs` also drops the Electron build/launch from this script and replaces with `vite build` of the static dashboard + open-in-browser to `https://localhost/super-admin/`. Once that lands, the only Windows-only branch in setup.mjs disappears.

- [ ] OPS-DEFERRED-002. **Browser-served super-admin dashboard (deprecate Electron `packages/management/`).**
  - [ ] BLOCKED: planning doc complete at [dashboard-migration-plan.md](./docs/dashboard-migration-plan.md) 2026-05-05; implementation gated on team capacity (~4 weeks for one engineer). Replaces ~4500 lines of Electron main + ~89 IPC handlers + Chromium binary + per-OS code-signing pipeline with: server-side `/super-admin/api/management/*` REST routes + static SPA at `/super-admin/` + a tiny `bizarre-crm-rescue` PM2 app for the crashed-server case.
  - Pairs with `OPS-DEFERRED-001` — Phase C-pre of this plan modifies `setup.bat`/`setup.mjs` to drop Electron build/launch and open browser instead. Independent of (3)/(4) of dashboardplan can start any time; (5)/(6)/(8) gate on multi-OS setup migration.
  - Acceptance: `packages/management/` deleted, fresh `setup.mjs` opens default browser to `https://localhost/super-admin/`, phone/tablet remote management works on LAN, Rescue Agent at `http://localhost:7474/rescue` handles crashed-main-server case.

### Web UI/UX Audit — Pass 33 (2026-05-05, flow walk: Send Bulk SMS — segment pick, preview token, confirm, partial-fail visibility)

#### Blocker — feedback mismatch / wording invisibility

- [ ] WEB-UIUX-1504. **[BLOCKER] Success toast literally shows `Enqueued undefined messages`. Client `BulkSmsModal.tsx:92` reads `r.enqueued` from the confirmed response, but server `inbox.routes.ts:693-703` returns `{ attempted, sent, failed, segment, template, confirmed: true }` — no `enqueued` field exists. Server changed contract (comment at `:620-625` notes the move from enqueue-only to inline dispatch with truthful counts) but client never updated. Admin sends to 12,000 customers, sees a green "Enqueued undefined messages" — no idea if 0 went through, 12,000 went through, or anything in between. Modal closes immediately after, so even the successful detail screen never shows. Update modal to read `r.sent + r.failed` and show e.g. `Sent ${r.sent} / Failed ${r.failed} of ${r.attempted}`; keep modal open if `failed > 0` so admin can act on the partial fail.** L7 feedback meaningfulness, L2 truthfulness.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:91-98`
  `packages/server/src/routes/inbox.routes.ts:693-703`
  <!-- meta: fix=update-onSuccess-handler-to-read-{attempted,sent,failed}+show-failure-aware-toast+keep-modal-open-when-failed>0-with-link-to-/inbox-retry-queue -->

- [ ] WEB-UIUX-1505. **[BLOCKER] Admin never sees template body before blasting. Template `<select>` at `BulkSmsModal.tsx:171-185` shows name only ("Repair ready", "Promo Aug"). Preview banner at `:188-196` only shows recipient count + 5-min expiry, NEVER the SMS body. Admin picks "Repair ready", clicks Preview → "12,003 recipients", clicks "Send to 12,003" — wording could be "TEST {{customer_first_name}} ignore" from a half-finished template and 12k customers receive it before anyone notices. Render `templates.find(t => t.id === templateId)?.content` in a read-only preview block above the recipient banner; show variable substitution against a sample row.** L2 truthfulness, L7 feedback, L9 empty/loading/error states.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:167-196`
  <!-- meta: fix=add-message-body-preview-block-with-variable-substitution-rendered-against-first-segment-row+character-count+segment-count-(SMS=160-chars-per-segment) -->

#### Major — usability / recovery / hierarchy

- [ ] WEB-UIUX-1506. **[MAJOR] Segment hints lie about consent. `SEGMENTS` at `BulkSmsModal.tsx:29-33` describes "All customers" as "Every customer with a mobile number", "Open tickets" as "Customers with tickets in progress", "Recent purchases" as "Customers who bought in last 30 days". Server `previewBulkSegment` filters every segment by `sms_opt_in = 1 AND sms_consent_marketing = 1` (`inbox.routes.ts:396-397, 404-405, 415-416`). Admin expecting 50,000 sees preview "9,200" and thinks the count is wrong; admin running compliance review reads the hint and concludes the system blasts non-consented numbers. Hints should say "…with marketing-SMS consent" — match the actual filter.** L2 truthfulness.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:29-33`
  `packages/server/src/routes/inbox.routes.ts:377-380,396-397,404-405,415-416`
  <!-- meta: fix=update-SEGMENTS-hints-to-mention-marketing-opt-in-+-consent;-add-tiny-help-line-"recipients-filtered-to-marketing-SMS-consent" -->

- [ ] WEB-UIUX-1507. **[MAJOR] Backdrop click after preview destroys 5-min token + segment + template. Modal root `BulkSmsModal.tsx:117` is `<div onClick={onClose}>`. After admin spends time picking segment, clicks Preview, reads "12,003 recipients", and accidentally clicks outside the inner card while reaching for Send → onClose fires, all state resets (preview cleared by re-open via `setPreview(null)` patterns at `:148, :175`). On reopen, admin must wait again for preview, get fresh token. No "are you sure?" guard. For destructive bulk ops, backdrop click should NOT close once preview is materialized.** L8 recovery, L5 hierarchy.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:117`
  <!-- meta: fix=disable-backdrop-onClose-when-preview-non-null;-or-route-backdrop-click-through-confirmation-"Discard-this-send?" -->

- [ ] WEB-UIUX-1508. **[MAJOR] No "send test to me" option. Industry standard for mass-mail / mass-SMS: send a single test to the operator's own phone before the blast, to verify wording/links/variable substitution. Missing entirely from BulkSmsModal. Admin's only options are: send to 12k recipients, or don't. No middle ground.** L6 discoverability, L4 flow integrity.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:188-223`
  <!-- meta: fix=add-"Send-test-to-my-number"-button-next-to-Preview;-uses-req.user.mobile-or-prompts-for-number;-doesn't-decrement-hourly-quota;-doesn't-mutate-token -->

- [ ] WEB-UIUX-1509. **[MAJOR] Modal closes on success → partial failures vanish. `BulkSmsModal.tsx:91-96` always calls `onClose()` on confirmed response, regardless of `failed` count. The retry queue UI (`FailedSendRetryList`) is only rendered in `CommunicationPage.tsx:1848` on the EMPTY-conversation pane (`<div ... grid w-full max-w-xl ...>`) — once any thread is selected (which is the default after closing the modal), `FailedSendRetryList` is unmounted. So 50 failed sends out of 12k get logged to `sms_retry_queue` but the admin who initiated the blast has no surfaced indication. Either (a) keep modal open with a "View N failures →" link to a dedicated retry page, or (b) move FailedSendRetryList into a persistent surface (sidebar, header bell badge).** L7 feedback, L9 error states, L8 recovery.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:91-96`
  `packages/web/src/pages/communications/CommunicationPage.tsx:1846-1850`
  <!-- meta: fix=keep-modal-open-when-failed>0-with-failure-summary+route-link-to-/inbox/retry-queue-page;-OR-promote-retry-queue-to-persistent-toolbar-badge -->

- [ ] WEB-UIUX-1510. **[MAJOR] Provider-not-configured surfaced only at confirm step. Server `inbox.routes.ts:626-635` checks `getSmsProvider()` and throws "SMS provider is not configured…" only after token verification, after segment-drift check. Admin builds full campaign (segment + template + Preview), reads "12,003 recipients", clicks "Send to 12,003" — gets a toast saying configure provider first. All effort wasted; banner blocks every attempt until Settings is fixed. Move provider real-or-simulated check to the preview branch (`:552-571`) and either (a) refuse preview with the same error, or (b) show a yellow "Provider not configured — sends will be queued in retry queue" banner inline before Send is enabled.** L7 feedback, L4 flow integrity, L9 error states.
  `packages/server/src/routes/inbox.routes.ts:552-571,626-635`
  <!-- meta: fix=move-isProviderRealOrSimulated-check-into-preview-branch+return-provider_status-in-preview-response;-modal-renders-warning-or-disables-Send -->

- [ ] WEB-UIUX-1511. **[MAJOR] 409 segment-drift leaves stale preview state in modal. Server returns 409 with `Segment changed since preview — re-preview to continue` (`inbox.routes.ts:602-609`). Modal `onError` at `BulkSmsModal.tsx:97` toasts the message but does NOT clear `preview` state. So admin clicks "Send to 12,003" again → server checks token vs latest segment hash → same 409 → same toast → infinite loop. Admin must Cancel + reopen. On 409 specifically, set `preview = null` and auto-call `previewMut.mutate()` to issue a fresh token+count, then prompt "Audience changed; new count = N. Send?". L8 recovery, L7 feedback.** 
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:78-98`
  `packages/server/src/routes/inbox.routes.ts:602-609`
  <!-- meta: fix=on-error.response.status===409-{setPreview(null);-previewMut.mutate()};-show-banner-"Audience-changed:-was-N1-now-N2" -->

- [ ] WEB-UIUX-1512. **[MAJOR] No live segment count alongside segment buttons. `BulkSmsModal.tsx:142-164` renders 3 segment buttons, each shows label + hint but no count. Admin must commit to a segment and click "Preview" to learn it's 12k vs 50. Switching segments after preview clears state (`:148-149`). Pre-fetch counts via `GET /inbox/bulk-send-segment-counts` (or extend an existing endpoint) and render `{count}` on each segment button (e.g., "Open tickets — 47", "All customers — 12,003"). Lets admin sanity-check audience size before committing.** L6 discoverability, L7 feedback.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:142-164`
  <!-- meta: fix=add-server-endpoint-returning-{open_tickets:N,all_customers:N,recent_purchases:N};-render-counts-as-trailing-badges-on-segment-cards;-keep-token-issuance-on-explicit-Preview -->

- [ ] WEB-UIUX-1513. **[MAJOR] No typed-confirmation for destructive scale. "Send to 12,003" red button (`BulkSmsModal.tsx:215-223`) is single-click → 12,003 SMS dispatched, irreversible. Established pattern (Stripe destructive ops, GitHub repo deletion, AWS termination): type the recipient count or template name to enable Send. For sends ≥ a threshold (e.g., 100), require typing the count or template name to enable the red button. Below threshold, current single-click stays.** L5 hierarchy of destructive, L8 recovery.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:215-223`
  <!-- meta: fix=if-preview.preview_count>=100-render-text-input-"Type-{count}-to-confirm";-Send-disabled-until-input.value===String(count) -->

#### Minor — clarity / scale safety

- [ ] WEB-UIUX-1514. **[MINOR] No countdown timer for 5-min token. Banner at `BulkSmsModal.tsx:189-196` says "Confirmation expires in 5 minutes" but no live counter. Admin gets pulled into a meeting at minute 4, returns at minute 6, clicks Send → 400 "Invalid or expired confirmation token". Should render `mm:ss` countdown derived from token issuance timestamp; switch banner to red and surface a "Re-Preview" button when expired or near (≤ 30s).** L7 feedback, L8 recovery.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:188-196`
  <!-- meta: fix=track-issuedAt=Date.now()-on-preview-success;-render-Math.max(0,300-elapsed)-as-mm:ss;-when<30s-flip-banner-color+show-Re-Preview-button -->

- [ ] WEB-UIUX-1515. **[MINOR] No SMS character / segment / cost preview. Twilio bills per 160-char SMS segment (70 chars for unicode). A 200-char promo template × 12k recipients = 24k billable segments, not 12k. Modal never surfaces this. Add character count under template, segments-per-message, total billable segments = `segments_per_msg * recipient_count`, and (if pricing known) estimated cost.** L6 discoverability, L7 feedback.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:167-196`
  <!-- meta: fix=compute-segments=Math.ceil(content.length/(hasUnicode?70:160));-render-"{segments}-segment(s)-x-{count}-recipients-=-{total}-billable-segments" -->

- [ ] WEB-UIUX-1516. **[MINOR] No scheduling option in BulkSmsModal. `ScheduledSendModal.tsx` already exists in the same `components/` folder for 1:1 scheduled sends. Bulk SMS is send-now only — admin who wants to blast Tuesday 10am has to set a personal reminder and re-build the campaign. Wire a "Schedule for later" checkbox; defer to existing scheduler infra.** L6 discoverability.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:198-224`
  `packages/web/src/pages/communications/components/ScheduledSendModal.tsx`
  <!-- meta: fix=add-"Schedule-for-later"-toggle+datetime-picker;-on-confirm-route-to-scheduled-bulk-send-endpoint-instead-of-immediate-/inbox/bulk-send -->

- [ ] WEB-UIUX-1517. **[MINOR] No remaining-quota indicator. Server hourly cap = 3 successful sends / admin / hour (`inbox.routes.ts:62`). Admin doesn't know how many they've used. 4th attempt → 429 → modal toast `Bulk send failed` (server message comes through but quota mechanic isn't explained). Add a small `Bulk sends used this hour: {used}/3 — resets in {mm:ss}` line near the modal footer, fed by an existing `/inbox/bulk-send-quota` or piggy-backed on the preview response.** L6 discoverability, L7 feedback.
  `packages/server/src/routes/inbox.routes.ts:62-63,583-589`
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:198-224`
  <!-- meta: fix=server-returns-{used,limit,resets_at_iso}-on-preview-response;-modal-renders-status-line-+-disables-Send-when-used>=limit -->

- [ ] WEB-UIUX-1518. **[MINOR] No segment audit / sample list. Preview shows count only — admin cannot spot-check "is John Doe really in this segment? Did we exclude staff?". Render up to 10 sample rows (first name + last 4 digits of phone) below the recipient banner so admin can sanity-check before pulling the trigger.** L7 feedback.
  `packages/server/src/routes/inbox.routes.ts:550-571`
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:188-196`
  <!-- meta: fix=server-preview-returns-{preview_count,sample:[{first,phone_last4}]-up-to-10};-modal-renders-sample-list-with-"+N-more"-tail -->

- [ ] WEB-UIUX-1519. **[MINOR] Template `<select>` shows name only — no search. Native `<select>` dropdown becomes ungrep-able past ~20 templates; admin scrolls. Replace with a searchable combobox (Headless UI `Combobox` or existing template-picker component used elsewhere in the app); show body excerpt as supporting text.** L6 discoverability.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:171-185`
  <!-- meta: fix=swap-native-<select>-for-Combobox-with-content-excerpt-as-secondary-line;-preserve-aria-labelling -->

- [ ] WEB-UIUX-1520. **[MINOR] Re-Preview button missing. Once `preview` is set, footer renders Cancel + Send only (`BulkSmsModal.tsx:206-223`). No way to refresh count/token without Cancel + reopen. If admin sees 12,003 and suspects opt-ins changed, only path is to back out. Add a "Re-Preview" link button next to the recipient banner (or as a third footer button when `preview != null`).** L8 recovery.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:188-223`
  <!-- meta: fix=render-"Re-Preview"-button-when-preview-non-null;-on-click-setPreview(null)+previewMut.mutate() -->

- [ ] WEB-UIUX-1521. **[MINOR] No focus trap / initial focus mgmt. Modal has `role="dialog" aria-modal="true"` (`BulkSmsModal.tsx:113-115`) — good — but no focus trap: tabbing past Cancel/Send moves focus to the underlying CommunicationPage. Also no autofocus on first interactive element when opened. Wrap inner card with `FocusTrap` (or use existing modal primitive used elsewhere) and `autoFocus` the first segment button.** a11y / L6.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:111-135`
  <!-- meta: fix=use-shared-Modal-primitive-with-focus-trap-(see-other-modals-in-pages/);-or-add-react-focus-lock;-autoFocus-segment[0] -->

#### Nit — copy / polish

- [ ] WEB-UIUX-1522. **[NIT] Header icon is `Users` — same icon as the trigger button (`CommunicationPage.tsx:1552`). Inside the modal it reads as decorative redundancy with the title "Bulk SMS". Swap for `Megaphone` or `Send` to reinforce broadcast semantic.** L1 visual hierarchy.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:124-127`

- [ ] WEB-UIUX-1523. **[NIT] Preview banner copy "Confirmation expires in 5 minutes" is static — doesn't actually expire visibly (see WEB-UIUX-1514). Even without a countdown, tighten to "Confirmation valid for 5 min — re-preview if you wait longer."** L2 truthfulness.
  `packages/web/src/pages/communications/components/BulkSmsModal.tsx:191-194`

### Web UI/UX Audit — Pass 34 (2026-05-05, flow walk: Record Payment on Invoice — modal entry, methods, dedup, receipt, recovery)

#### Blocker — wrong response shape, dedup blocks legitimate split tender

- [ ] WEB-UIUX-1524. **[BLOCKER] Custom payment methods configured in Settings never reach the Record Payment modal. Server returns `{ success: true, data: <array of methods> }` (`settings.routes.ts:840-841`), but client reads `pmData?.data?.data?.payment_methods` (`InvoiceDetailPage.tsx:92`) — `<array>.payment_methods` is `undefined`, so `paymentMethods` is always `[]` and the hardcoded fallback `[Cash, Credit Card, Debit Card, Other]` runs every time. Tenant adds Zelle / Venmo / Wire / Cashier's Check via Settings → SettingsPage shows them (it parses `res.data.data` correctly at `SettingsPage.tsx:1346`) → cashier opens Record Payment → none of the custom methods appear → every non-default tender gets booked as "Other" → ledger reports collapse all wires + ACH + crypto into a single bucket, and the Settings UI looks broken to admins ("I added Zelle, why isn't it offered?"). Fix: read `pmData?.data?.data` as the array directly, mirror `SettingsPage`'s shape.** L2 truthfulness, L11 consistency, L4 flow integrity.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:77-92`
  `packages/server/src/routes/settings.routes.ts:838-842`
  <!-- meta: fix=replace-`pmData?.data?.data?.payment_methods`-with-`Array.isArray(pmData?.data?.data)?pmData.data.data:[]`;-typed-as-PaymentMethod[];-keep-fallback-only-when-array-is-empty -->

- [ ] WEB-UIUX-1525. **[BLOCKER] Same-amount-same-user dedup window (5s in-memory + 10s DB at `invoices.routes.ts:763-776`) blocks a legitimate split tender. Two friends each hand the cashier $50 cash for a $100 invoice. Cashier records first $50 → success. Records second $50 immediately → server returns 409 "Duplicate payment detected. Please wait before retrying." Toast message implies the prior write didn't land, so cashier waits, retries, fails again. Common workarounds: change second amount to $50.01, or split into two payments by method (cash + cash again later) — both falsify the ledger. Either (a) require an explicit `force` flag with an "Yes, this is a separate tender" confirmation when dedup hits, or (b) include an idempotency key from the client so the dedup is keyed on intent not amount.** L2 truthfulness, L4 flow integrity, L8 recovery.
  `packages/server/src/routes/invoices.routes.ts:760-777`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:94-105`
  <!-- meta: fix=client-sends-Idempotency-Key-uuid-on-mutate;-server-dedup-on-key-not-amount;-on-409-toast-"Looks-like-duplicate-(prior-payment-of-$X-recorded-Ns-ago).-Record-this-as-a-separate-tender?"-with-Force-button -->

#### Major — recovery / hierarchy / feedback

- [ ] WEB-UIUX-1526. **[MAJOR] No way to reverse a single mis-typed payment. Cashier fat-fingers $5,000 instead of $50; only paths back are (a) Void Invoice (`InvoiceDetailPage.tsx:384-388`) which marks every payment on the invoice as `[VOIDED]` (`invoices.routes.ts:930`) — including legitimate prior payments — and restores stock + cancels commission, or (b) Credit Note (`:377-380`) which is capped at `amount_paid`, requires a structured reason picker, and is bookkept as a refund. The payment timeline (`:484-547`) renders each payment row but offers no per-row action. Add a per-payment "Reverse" affordance (manager-PIN gated, time-windowed e.g. 30 min, marks the row [VOIDED] without nuking the rest of the invoice).** L8 recovery, L13 forgiveness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:484-547`
  `packages/server/src/routes/invoices.routes.ts:925-935`
  <!-- meta: fix=add-DELETE-/invoices/:id/payments/:paymentId-(or-POST-/payments/:id/void)-gated-on-invoices.void_payment-+-time-window;-render-Reverse-button-on-each-non-voided-row-in-timeline -->

- [ ] WEB-UIUX-1527. **[MAJOR] Receipt prompt closes on backdrop click without confirmation. `InvoiceDetailPage.tsx:677` wraps the prompt in `<div ... onClick={() => setShowReceiptPrompt(false)}>`. Cashier records payment, modal swaps to "Send Receipt?", customer is mid-conversation, cashier instinctively clicks outside to dismiss the modal → receipt is silently skipped, no acknowledgment. Customer leaves expecting an SMS that never arrives. Either (a) require an explicit Skip/Send choice (no backdrop close), or (b) on backdrop dismiss show a tiny toast "Receipt skipped — re-send from invoice detail" so cashier knows.** L7 feedback, L8 recovery, L13 forgiveness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:677-735`
  <!-- meta: fix=remove-backdrop-onClose-OR-on-dismiss-toast.success("Receipt-skipped — Re-send-from-Payment-Timeline")-with-link-to-resend-flow -->

- [ ] WEB-UIUX-1528. **[MAJOR] SMS receipt body lies on partial payment. `:704` builds `Receipt for Invoice #${invoice.order_id}: Total ${formatCurrency(invoice.total)}. Thank you for your business!` — uses `invoice.total` (the headline), not the payment amount or remaining balance. Customer pays $50 deposit on a $500 invoice, gets SMS "Total $500.00. Thank you for your business!" → reads like the whole invoice is paid; customer assumes job is done, won't pay the rest. Body must include payment_amount + balance_due + method (e.g., "Received $50.00 cash on INV-1234. Balance remaining: $450.00.").** L2 truthfulness, L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:700-714`
  <!-- meta: fix=template="Received-${formatCurrency(paid)}-${method}-on-${order_id}.${amount_due>0?`-Balance:-${formatCurrency(amount_due)}.`:`-Paid-in-full.`}-Thanks!" -->

- [ ] WEB-UIUX-1529. **[MAJOR] Backdrop click destroys typed payment in flight. Modal root at `:597` is `onClick={(e) => { if (e.target === e.currentTarget) setShowPayment(false); }}`. Cashier types `$1,250.00`, picks Credit Card, types auth code into Notes, then accidentally clicks outside the inner card while reaching for "Record Payment" → modal closes, all state cleared (`setPaymentForm` reset never fires here, but next open re-mounts and starts blank because the `useState` lives at component scope and is preserved — actually re-opening with state intact would help, BUT the modal mount is conditional on `showPayment` so state persists across close/reopen). Still: backdrop dismissal during a financial entry is too easy. Either disable backdrop close entirely on this modal, or warn before discarding non-empty input ("Discard payment entry?").** L8 recovery, L13 forgiveness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:591-672`
  <!-- meta: fix=remove-backdrop-close;-or-on-dismiss-when-(amount||notes||method!=='cash')-show-confirm-"Discard-payment-entry?" -->

- [ ] WEB-UIUX-1530. **[MAJOR] Overpayment guard uses native `window.confirm()` (`InvoiceDetailPage.tsx:236`). Native dialog is unstyled, can be muted by browser site settings, and looks identical for "$50 overage on a $50 invoice (likely tip)" vs "$4,950 overage on a $50 invoice (definitely typo)". The guard accepts any amount on Yes — no typed confirmation, no "Record overage as $X store credit?" preview, no breakdown showing where the excess will land. Replace with a styled ConfirmDialog that surfaces the planned store_credit insert and requires typed confirmation when overage > e.g. 50% of invoice total.** L5 destructive hierarchy, L7 feedback, L13 forgiveness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:225-242`
  `packages/server/src/routes/invoices.routes.ts:792-798,825-861`
  <!-- meta: fix=swap-window.confirm-for-ConfirmDialog-with-{amount,balance,overage,store_credit_target,customer_name};-requireTyping=overage>balance*0.5 -->

- [ ] WEB-UIUX-1531. **[MAJOR] No structured `transaction_id` field — auth codes get buried in `notes`. Server schema has a dedicated `payments.transaction_id` column (`invoices.routes.ts:780`) and the route accepts it (`:750`). Client never renders an input for it; the only freeform field is "Notes (optional)" with placeholder "Transaction ID, check number, etc." (`InvoiceDetailPage.tsx:643`). Cashier types AUTH-12345 into notes — not searchable, not surfaced on the timeline, never reconcilable against processor reports. For non-terminal card flows (offline backup, manual cash imprint, ACH wire confirmations) this is the only place to capture it. Add a `Reference / Transaction ID` field that conditionally appears for non-cash methods.** L6 discoverability, L11 consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:641-644`
  `packages/server/src/routes/invoices.routes.ts:750,780-783`
  <!-- meta: fix=add-{transaction_id}-to-paymentForm;-render-input-conditional-on-method!=='cash';-pass-through-on-payMutation;-render-on-timeline-row -->

- [ ] WEB-UIUX-1532. **[MAJOR] No deposit / payment-type toggle. Server distinguishes `payment_type` ∈ {payment, deposit} (`invoices.routes.ts:750-758`). Client never exposes it; every record posts as `payment` (default). Shops that take a 30% deposit on a custom build use this UI for the deposit, then again for the balance — but reporting that splits revenue accrual vs deferred-revenue can't tell them apart. Either expose a `Deposit` checkbox in the modal, or default `payment_type='deposit'` when invoice has zero prior payments and `amount_due == total` and the entered amount is < total.** L6 discoverability, L11 consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:43,101,225-242`
  `packages/server/src/routes/invoices.routes.ts:750,754-758`
  <!-- meta: fix=add-payment_type-toggle-or-derive-from-(amount<total&&amount_paid===0);-pass-through-on-mutate -->

- [ ] WEB-UIUX-1533. **[MAJOR] Invoice list has no inline "Record Payment" — collections workflow loses scroll/filter on every row. `InvoiceListPage.tsx:533-538` action column shows "View" only; the row is also clickable as a whole, so selection or quick action requires `e.stopPropagation()` plumbing already in place. A cashier reviewing the overdue tab (50 rows) and calling each customer in turn must click row → land on detail → click Record Payment → record → navigate back → scroll back to position. Add a small "$" / "Pay" icon button beside View on rows with `amount_due > 0`, opening the same payment modal in-list (or via a side drawer).** L4 flow integrity, L6 discoverability.
  `packages/web/src/pages/invoices/InvoiceListPage.tsx:483-540`
  <!-- meta: fix=add-quick-pay-button-on-rows-with-amount_due>0;-mount-shared-PaymentModal-component-with-invoiceId-+-onClose;-extract-modal-from-InvoiceDetailPage.tsx-into-components/billing/RecordPaymentModal.tsx -->

#### Minor — clarity / consistency

- [ ] WEB-UIUX-1534. **[MINOR] Amount placeholder is currency-naive. `InvoiceDetailPage.tsx:611` renders `placeholder={Number(invoice.amount_due).toFixed(2)}` (e.g., "1234.56") inside an input prefixed with a hardcoded `$` glyph (`:605`). Same file uses `formatCurrency()` everywhere else (totals, payment timeline, max-credit hint). Tenants on EUR / GBP / MXN see "$1234.56" alongside €/£/$ totals on the surrounding card — currency cognitive whiplash. Use `formatCurrency(invoice.amount_due)` for the placeholder and drop the static `$` prefix; render the currency glyph from tenant settings.** L2 truthfulness, L11 consistency.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:603-617`
  <!-- meta: fix=placeholder=formatCurrency(invoice.amount_due);-remove-hardcoded-$-prefix-OR-derive-from-tenant.currency_symbol -->

- [ ] WEB-UIUX-1535. **[MINOR] "Pay full balance" is a tiny text link, not the primary action. `InvoiceDetailPage.tsx:618-621` renders the most-common-case ("collect the full outstanding balance") as a 12px underline-on-hover link below the input. Most cashiers type the amount manually because the link doesn't read as a button. Promote it: make the input default-empty with a prominent "Pay {formatCurrency(amount_due)} (full balance)" preset button at the top of the modal, and a "Custom amount" toggle for partial.** L1 visual hierarchy, L6 discoverability.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:602-622`
  <!-- meta: fix=primary-CTA="Pay-{full}";-secondary-toggle-"Custom-amount"-reveals-input;-existing-link-replaced-by-button -->

- [ ] WEB-UIUX-1536. **[MINOR] Method `<button>` highlight depends on a normalize that breaks on rename. `InvoiceDetailPage.tsx:629,631` matches `paymentForm.method === pm.name.toLowerCase().replace(/\s+/g, '_')`. Admin renames "Credit Card" → "Credit" in Settings → method string becomes `credit` not `credit_card` → all historical reports keyed on `credit_card` lose continuity. The `payment_methods` table has a stable `id` column (`settings.routes.ts:849`); use that as the wire value, with `name` only for display. Same fix unblocks WEB-UIUX-1524.** L11 consistency, L10 trust (reports).
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:626-639`
  `packages/server/src/routes/settings.routes.ts:838-851`
  <!-- meta: fix=submit-pm.id-(or-canonical-slug)-as-method;-server-resolves-to-display-name;-historical-reports-keep-stable-key-across-renames -->

- [ ] WEB-UIUX-1537. **[MINOR] Initial method state hardcoded `'cash'`, may not match any rendered button. `InvoiceDetailPage.tsx:43` initializes `method: 'cash'`. If tenant disables Cash in Settings (e.g., card-only retail, no register float), cash is no longer in `payment_methods`, but the form still defaults to `'cash'` and submits it on Record Payment — server accepts the string blindly. No method button is highlighted on first open → cashier sees four equally-unselected buttons → confused which is active. Initialize `method` from `paymentMethods[0]?.id` once data loads.** L2 truthfulness, L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:43,77-92`
  <!-- meta: fix=useEffect-once-pmData-loads-{setPaymentForm(p=>({...p,method:paymentMethods[0]?.id||'cash'}))} -->

- [ ] WEB-UIUX-1538. **[MINOR] Customer cache not invalidated after payment. `InvoiceDetailPage.tsx:96-98` invalidates `['invoice', id]` and `['invoices']` on success but not `['customer', invoice.customer_id]`. Customer profile page renders a "Lifetime Value" + "Outstanding Balance" pair that the server updates via `recordCustomerInteraction` (`:822`) — values become stale until the user manually navigates away and back, or the staleTime expires. Add `['customer', invoice.customer_id]` to the invalidation list.** L11 consistency, L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:94-105`
  `packages/server/src/routes/invoices.routes.ts:820-823`
  <!-- meta: fix=add-queryClient.invalidateQueries({queryKey:['customer',invoice.customer_id]});-also-on-credit-note-success-+-void -->

- [ ] WEB-UIUX-1539. **[MINOR] No focus trap on Record Payment modal. `:591-596` sets `role="dialog" aria-modal="true"`. autoFocus lands on the amount input (`:615`) — good — but tabbing past Cancel/Record cycles into the underlying invoice page (Print / Void / etc.). Screen-reader user listening to "Record Payment" suddenly hears "Void" buttons read out from outside the dialog. Wrap inner card with `react-focus-lock` or the existing modal primitive used elsewhere (e.g., `ConfirmDialog`).** L12 a11y.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:591-672`
  <!-- meta: fix=use-shared-Modal-primitive-OR-react-focus-lock;-trap-focus-within-card;-restore-focus-to-Record-Payment-button-on-close -->

#### Nit — copy / polish

- [ ] WEB-UIUX-1540. **[NIT] Notes placeholder invites unstructured data dumping. "Transaction ID, check number, etc." (`InvoiceDetailPage.tsx:643`) trains the cashier to pour structured fields into notes. After WEB-UIUX-1531 lands (dedicated `transaction_id` field), update the notes placeholder to "Memo (e.g., 'invoice paid at front desk')".** L2 truthfulness.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:642-644`

- [ ] WEB-UIUX-1541. **[NIT] Receipt prompt header "Send Receipt?" doesn't acknowledge partial payment. `:680`. If the just-recorded payment leaves `invoice.amount_due > 0`, the prompt should say "Send Partial Receipt?" with the remaining balance shown beneath, so the cashier deliberately picks SMS / Email / Skip with full context (the partial-vs-full distinction is critical when WEB-UIUX-1528 is fixed and the SMS body is honest).** L2 truthfulness, L7 feedback.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:679-685`

- [ ] WEB-UIUX-1542. **[NIT] Method buttons forced into 2-col grid — odd layout when payment_methods has 5+ entries. `:625` `grid grid-cols-2 gap-2`. Five methods → 2-2-1 with a half-width orphan. Switch to flex-wrap with min-width buttons so 1-3-5 wrap gracefully.** L1 visual hierarchy.
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:625`

### Web UI/UX Audit — Pass 35 (2026-05-05, flow walk: Issue Gift Card — entry, reveal-once, code reveal truthfulness, recipient delivery, end-to-end redeem path)

#### Blocker — broken end-to-end flow / lying copy / missing controls

- [ ] WEB-UIUX-1543. **[BLOCKER] No redeem surface anywhere in POS or invoice. Server exposes `POST /gift-cards/:id/redeem` (`giftCards.routes.ts:328`) and `GET /gift-cards/lookup/:code` (`:172`); web client wires `giftCardApi.redeem` and `giftCardApi.lookup` (`endpoints.ts:1274-1276`) but NO UI calls them. `CashRegisterPage.tsx` has zero references to "gift", "redeem", "giftCard"; `InvoiceDetailPage.tsx` payment-method buttons render only what `payment_methods` table returns (no built-in gift-card tender). Cashier issues a $200 gift card, customer returns to redeem → cashier physically cannot accept it. End-to-end flow does not close. Either (a) add Gift Card as a payment-method option in the Record Payment modal that opens a code-lookup-first flow, or (b) build a dedicated Redeem page and link it from the Gift Cards list.** L4 flow completion, L6 discoverability.
  `packages/web/src/pages/pos/CashRegisterPage.tsx`
  `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:625-639`
  `packages/server/src/routes/giftCards.routes.ts:328-392`
  <!-- meta: fix=add-Gift-Card-method-button-in-RecordPaymentModal+lookup-by-code-step+redeem-mutation;-OR-add-/gift-cards/redeem-route-with-LookupForm+RedeemForm -->

- [ ] WEB-UIUX-1544. **[BLOCKER] "Save this code now — it will not be shown again" is a lie. Issue success modal copy at `GiftCardsListPage.tsx:139-141` claims one-time reveal. Detail page `GiftCardDetailPage.tsx:235` toggles full plaintext code via Eye/EyeOff button — server `GET /gift-cards/:id` returns full `code` column unconditionally (`giftCards.routes.ts:444-450`, `code` selected via `SELECT *`). Worse: GET has no `requirePermission` gate — only `authMiddleware` (`server/index.ts:1623`). ANY authed user (including base-role cashiers without `gift_cards.issue`/`gift_cards.redeem` perms) can iterate `/gift-cards/:id` and harvest plaintext codes for redemption elsewhere. Either (a) finish the SEC-H38 hash-rollover (drop plaintext `code` column, never return it from GET) and remove the false claim, or (b) gate the plaintext branch behind a manager-PIN re-auth + audit log entry per reveal.** L2 truthfulness, L10 trust, security overlap.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:138-143`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:233-244`
  `packages/server/src/routes/giftCards.routes.ts:441-451`
  `packages/server/src/index.ts:1623`
  <!-- meta: fix=server-GET-/:id-strips-code+code_hash-from-response;-detail-page-removes-Eye-toggle;-OR-keep-reveal-but-add-requirePermission('gift_cards.view_code')-+-audit-on-each-fetch -->

- [ ] WEB-UIUX-1545. **[BLOCKER] `recipient_email` is collected, validated, persisted — never delivered. Issue modal asks for "Recipient email (optional)" with placeholder "jane@example.com" (`GiftCardsListPage.tsx:204-215`). Server `validateTextLength(recipient_email, 200)` then INSERTs (`giftCards.routes.ts:281-300`). Zero `email`/`sms`/`notify`/`sendgrid`/`twilio` references anywhere in the route. Customer pays $100 to gift to Jane, types Jane's email, hits Issue → Jane gets nothing. Cashier never warned. The whole "send a gift" mental model the field implies does not exist. Either (a) wire post-issue email (Mailgun/SendGrid client used elsewhere in repo) with the code rendered in the body, or (b) drop the recipient_email field and rename the modal to "Issue gift card (cashier hands code to customer)".** L2 truthfulness, L4 flow completion, L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:204-215`
  `packages/server/src/routes/giftCards.routes.ts:253-323`
  <!-- meta: fix=after-INSERT-success-call-mailer.send({to:recipient_email,template:'gift-card-issued',vars:{recipient_name,code,initial_balance,expires_at,sender:tenant.name}});-add-Settings-toggle-"send-gift-on-issue" -->

- [ ] WEB-UIUX-1546. **[BLOCKER] No way to disable / void / mark-lost a gift card. Server `giftCards.routes.ts` ends at line 451 with no DELETE / PATCH / POST :id/disable route. Customer reports their card stolen → admin opens detail page → no "Disable" button. Status enum has `disabled` value (`:117`) but nothing flips a card to it. Stolen card stays redeemable until drained. Add `POST /gift-cards/:id/disable` (manager+ role, audited) and a Disable button on the detail page next to Reload.** L4 flow completion, L8 recovery.
  `packages/server/src/routes/giftCards.routes.ts:441-453`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:283-293`
  <!-- meta: fix=server-POST-/:id/disable-{reason}-flips-status='disabled'+audit;-detail-page-renders-Disable-button-(red-secondary)-with-reason-prompt;-list-page-row-action -->

#### Major — discoverability / hierarchy / recovery

- [ ] WEB-UIUX-1547. **[MAJOR] Gift Cards page is orphaned from primary navigation. `App.tsx:98,536-538` registers the routes with comment "§ gift-cards orphan UI". `Sidebar.tsx` has zero "gift" matches. Only entry points: Cmd-K palette (`CommandPalette.tsx:73`) and direct URL. Cashier asked to issue a gift card cannot find the page without prior knowledge. Add to Sidebar under Sales/Billing group with `gift_cards.issue` perm gate so non-issuers don't see a button they can't use.** L6 discoverability.
  `packages/web/src/components/layout/Sidebar.tsx`
  `packages/web/src/App.tsx:536-538`
  <!-- meta: fix=add-NavItem{label:'Gift Cards',icon:Gift,path:'/gift-cards',permission:'gift_cards.issue'}-under-Sales-section -->

- [ ] WEB-UIUX-1548. **[MAJOR] Past expiry dates accepted on issue; immediately-expired card is silent. `<input type="date">` at `GiftCardsListPage.tsx:220-225` has no `min={today}` attribute. Server `validateIsoDate` (`validate.ts:169-195`) checks ISO format only — does NOT reject past dates. Cashier mis-types "2025" instead of "2026" → card issued with `expires_at=2025-05-05` → next redemption attempt errors "Gift card expired". No client warning, no server reject, no `expires_at < created_at` constraint at INSERT. Add `min` on the input + a server-side `if (expires_at && new Date(expires_at) <= new Date()) throw 400`.** L2 truthfulness, L4 flow integrity.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:220-225`
  `packages/server/src/routes/giftCards.routes.ts:287-289`
  `packages/server/src/utils/validate.ts:169-195`
  <!-- meta: fix=client-min={new Date().toISOString().slice(0,10)};-server-rejects-expires_at<=now()-with-"Expiry-must-be-in-the-future" -->

- [ ] WEB-UIUX-1549. **[MAJOR] Date-only expiry parsed as UTC midnight — card expires the night before in user's local time. `isExpired()` at `giftCards.routes.ts:38-46` calls `Date.parse('2026-05-05')` → `2026-05-05T00:00:00Z`. A US Pacific (UTC-7/8) tenant's card showing "Expires May 5" is dead at 5pm May 4 local time. Customer walks in May 5 morning, gets "Gift card expired" error. Either (a) coerce expiry to end-of-day in tenant timezone (`expires_at + 'T23:59:59' + tenantTz`), or (b) interpret a date-only expiry as "valid through end of that day local" by appending `T23:59:59.999Z` and accepting the wider window.** L2 truthfulness.
  `packages/server/src/routes/giftCards.routes.ts:38-46,287-289`
  <!-- meta: fix=at-INSERT-store-expires_at-as-{date}T23:59:59-in-tenant-tz;-OR-isExpired-treats-date-only-as-end-of-day-local -->

- [ ] WEB-UIUX-1550. **[MAJOR] Lookup-by-code UI does not exist. Server has rate-limited `GET /gift-cards/lookup/:code` (`giftCards.routes.ts:172`) and client wires `giftCardApi.lookup` (`endpoints.ts:1274`) but no page calls it. List `keyword` search hits `gc.code LIKE` (`:113`), but list rows display `maskCode` (`****XXXX`) — cashier cannot see if their typed prefix matches. Customer hands physical card "C7E2-4F11-..." and cashier has no quick lookup form. Add a "Look up code" input above the list table (or a /gift-cards/lookup route) that hits the lookup endpoint and routes to detail on hit.** L4 flow completion, L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:309-331`
  `packages/server/src/routes/giftCards.routes.ts:172`
  <!-- meta: fix=add-LookupBar-component-above-filters-with-code-input+Enter→navigate(`/gift-cards/${data.id}`);-error-toast-on-404 -->

- [ ] WEB-UIUX-1551. **[MAJOR] Cents/dollars heuristic silently mangles legitimate large balances. `formatCurrency` at `GiftCardsListPage.tsx:57-63` and identical in `GiftCardDetailPage.tsx:41-43` treats integer values >= 1000 as cents. `GIFT_CARD_MAX_AMOUNT = 10_000` (`giftCards.routes.ts:29`) — corporate gifting ($1,000 / $5,000 / $10,000 cards) is an explicit allowed range. A $1,000 card with `current_balance = 1000` (dollars) falls into the heuristic and renders as `$10.00`. Comment at `:51-53` admits "no real-world gift-card balance reaches $1000 in float-dollars outside corporate gifting" — but corporate gifting is exactly the workflow this product enables. Heuristic should die: pin server to one representation (dollars OR cents), update SELECT, drop the if-branch.** L2 truthfulness, L10 trust.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:46-63`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:41-53`
  `packages/server/src/routes/giftCards.routes.ts:29,297-300`
  <!-- meta: fix=pick-one-representation-(recommend-cents-everywhere-since-rest-of-POS-is-migrating-to-cents);-update-INSERT-to-multiply-by-100;-formatCurrency-collapses-to-formatCurrencyShared(n/100) -->

- [ ] WEB-UIUX-1552. **[MAJOR] Issued-code reveal modal closes on backdrop click — code lost in <100ms reflex. Modal root `GiftCardsListPage.tsx:125-130` is `<div ... onClick={onClose}>`. Cashier reads code aloud, clicks anywhere outside the inner card to dismiss → modal closes → list refetches → row shows masked `****XXXX`. Code is recoverable via detail Eye toggle (until WEB-UIUX-1544 lands), but cashier doesn't know that. While the reveal screen is up, backdrop click should be inert; only Done/X/Esc dismisses. Pair with a "Copy code" button next to Done so the friction of code capture isn't a single visual scan.** L8 recovery, L13 forgiveness.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:123-153`
  <!-- meta: fix=removed-onClick=onClose-on-issuedCode-screen;-add-Copy-button-(navigator.clipboard.writeText(code)+toast)-+-Print-button -->

- [ ] WEB-UIUX-1553. **[MAJOR] Issue success "Done" button does literally nothing useful. `GiftCardsListPage.tsx:145-150` renders single button labeled "Done" wired to `onClose`. No copy-to-clipboard, no print receipt, no "Email to recipient", no "SMS to phone" — even though `recipient_email` is in scope and a printer is the canonical POS hardware. Cashier reads the code on screen, manually transcribes onto a paper card, customer leaves. Replace with a 4-button bar: Copy / Print receipt / Email to recipient (if filled) / Done.** L4 flow completion, L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:142-150`
  <!-- meta: fix=render-{Copy,Print,Email-to-${recipient_email||'…'},Done};-Email-disabled-when-no-recipient_email;-Print-opens-thermal-receipt-template -->

- [ ] WEB-UIUX-1554. **[MAJOR] Issue modal: no denomination presets. `GiftCardsListPage.tsx:182-190` is a single freeform `type="number"` input. Most retail flows are $25/$50/$100/$200/$500. Cashier types every time → typo risk on a financial entry. Render preset buttons above the input, plus a "Custom" toggle that falls back to the freeform input.** L1 hierarchy, L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:177-191`
  <!-- meta: fix=presets=[25,50,100,200,500];-render-grid-of-buttons-that-setForm({amount:String(v)});-keep-input-as-Custom-fallback -->

- [ ] WEB-UIUX-1555. **[MAJOR] Status filter has no `expired` option. `GiftCardsListPage.tsx:325-329` offers active/used/disabled. Server doesn't persist an `expired` status — `isExpired` is computed at lookup/redeem only. Manager wants to email customers whose cards expire next month — no UI path. Either (a) persist a `gift_card_expired` daemon (the `giftCardExpirySweep` service exists at `packages/server/src/services/giftCardExpirySweep.ts` — wire its output to the status column), or (b) add a virtual `expired` filter that translates to `expires_at < datetime('now')` on the server.** L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:321-330`
  `packages/server/src/services/giftCardExpirySweep.ts`
  `packages/server/src/routes/giftCards.routes.ts:117`
  <!-- meta: fix=add-<option-value="expired">+server-translates-status=expired-to-WHERE-status='active'-AND-expires_at<datetime('now');-also-"expiring_soon"-(within-30d) -->

- [ ] WEB-UIUX-1556. **[MAJOR] No bulk issue. `IssueModal` issues one card per submission. HR wanting to drop 50 holiday gift cards has to repeat the form 50 times. Add a "Bulk issue" path that takes a CSV (recipient_name, recipient_email, amount, expires_at) or a count + flat amount, returns a downloadable CSV of {recipient, code} for handoff.** L6 discoverability.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:84-248`
  `packages/server/src/routes/giftCards.routes.ts:253-323`
  <!-- meta: fix=server-POST-/gift-cards/bulk-{rows}-loops-with-single-tx-+-rate-cap;-client-BulkIssueModal-with-CSV-paste-+-download-result -->

#### Minor — clarity / consistency / a11y

- [ ] WEB-UIUX-1557. **[MINOR] Client doesn't enforce `GIFT_CARD_MAX_AMOUNT`. Issue input has `min="0.01"` but no `max` (`GiftCardsListPage.tsx:184`). User types $50,000 → submit → server 400 "Gift card amount cannot exceed $10,000" → toast shows, but admin spent time filling in recipient + email. Mirror server cap: `max="10000"` + helper text "Up to $10,000".** L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:182-190`
  `packages/server/src/routes/giftCards.routes.ts:29,262-264`
  <!-- meta: fix=add-max="10000"+helper-"Maximum-$10,000-per-card";-disable-Submit-when-amount>10000 -->

- [ ] WEB-UIUX-1558. **[MINOR] Detail page reload toast lacks the new balance. `GiftCardDetailPage.tsx:96-100` toasts "Gift card reloaded". Server response includes `new_balance` (`giftCards.routes.ts:437`) but client ignores it. Should toast "Reloaded $25 — new balance $150.00".** L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:90-104`
  <!-- meta: fix=onSuccess(res)→toast.success(`Reloaded ${formatCurrency(amount)} — new balance ${formatCurrency(res.data.data.new_balance)}`) -->

- [ ] WEB-UIUX-1559. **[MINOR] "of $X initial" line is meaningless after reload. `GiftCardDetailPage.tsx:252-253` shows "$current of $initial initial". Reload a $50 card 3× by $25 → balance $125, "of $50.00 initial" is jarring. Replace with "Loaded total $X" (initial + sum of reloads) computed from transactions, or drop the line when `initial_balance < current_balance`.** L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:251-254`
  <!-- meta: fix=loadedTotal=initial_balance+sum(adjustment-reload-tx);-render-"of-${formatBalance(loadedTotal)}-loaded";-OR-suppress-line-when-current>initial -->

- [ ] WEB-UIUX-1560. **[MINOR] `txLabel('adjustment')` hardcoded "Reload". Server uses `'adjustment'` for the reload write (`giftCards.routes.ts:423`) and that's the only adjustment write today, but if a future feature adds manual corrections / refund credits / promo bumps under the same enum, history rows mislabel. Either (a) split into `'reload'` and `'adjustment'` enums on the server, or (b) read the `notes` field for label discrimination ("Reloaded" → Reload, otherwise → Adjustment).** L2 truthfulness, L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:55-61`
  `packages/server/src/routes/giftCards.routes.ts:421-424`
  <!-- meta: fix=widen-tx.type-enum-to-include-'reload'+migration-to-relabel-existing-adjustments-where-notes='Reloaded' -->

- [ ] WEB-UIUX-1561. **[MINOR] Issue modal: no autofocus on amount field on open. `GiftCardsListPage.tsx:182-190` lacks `autoFocus`. Reload modal has it (`GiftCardDetailPage.tsx:133`). Inconsistent. Cashier opening Issue modal must click into the amount field before typing.** L11 consistency, a11y.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:182-190`
  <!-- meta: fix=add-autoFocus-to-amount-input;-mirror-pattern-from-ReloadModal -->

- [ ] WEB-UIUX-1562. **[MINOR] Issue modal: no focus trap. `role="dialog" aria-modal="true"` set (`:164-166`), but tab past Cancel/Issue cycles into list table actions in the page below. Same on Reload modal (`GiftCardDetailPage.tsx:115-122`). Wrap inner card with `react-focus-lock` or shared modal primitive.** a11y / L12.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:163-247`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:115-155`
  <!-- meta: fix=use-shared-Modal-primitive-OR-react-focus-lock-around-inner-card;-restore-focus-to-trigger-button-on-close -->

- [ ] WEB-UIUX-1563. **[MINOR] List `keyword` search matches `gc.code LIKE` but display masks the code. `giftCards.routes.ts:113-115` does `code LIKE %keyword%`, but row renders `****XXXX`. Cashier searching for "C7E2" can't visually confirm the match. Either (a) only search by recipient_name when keyword is short (< full-code length), or (b) when keyword matches a code prefix, reveal the matched chars in the row (e.g., `C7E2****`).** L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:65-68,370-372`
  `packages/server/src/routes/giftCards.routes.ts:112-116`
  <!-- meta: fix=if-keyword-looks-like-code-prefix-(/^[A-F0-9]{4,}/i)-render-${prefix}****${suffix};-else-mask-fully -->

- [ ] WEB-UIUX-1564. **[MINOR] Email input has no client-side validity feedback before submit. `GiftCardsListPage.tsx:208-214` is `<input type="email">` — browser silently fails the constraint check on submit but the issue button is wired via React `onClick` not `<form onSubmit>`, so native validation never runs. Server `validateTextLength(recipient_email, 200)` accepts "not-an-email" up to 200 chars. Card issued with garbage email → if WEB-UIUX-1545 ships email delivery, dispatch silently fails. Wrap inputs in `<form onSubmit>` to enable native validity OR validate with a regex before mutate.** L2 truthfulness, L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:204-215`
  `packages/server/src/routes/giftCards.routes.ts:281-283`
  <!-- meta: fix=client-/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.recipient_email)-before-mutate;-server-add-validateEmail-helper -->

#### Nit — copy / polish

- [ ] WEB-UIUX-1565. **[NIT] Title-case mismatch. List header "Gift Cards" (`:292`), modal title "Issue gift card" (`:171`), success modal "Gift card issued" (`:138`), Reload modal "Reload gift card" (`GiftCardDetailPage.tsx:124`). Three different cases for the same noun. Standardize on sentence case ("Issue gift card" / "Gift card issued" / "Gift cards") or Title Case — pick one.** L11 consistency.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:138,171,292`
  `packages/web/src/pages/gift-cards/GiftCardDetailPage.tsx:124`

- [ ] WEB-UIUX-1566. **[NIT] Initial value placeholder "25.00" with `min="0.01"` and `step="0.01"`. A $0.01 gift card is nonsense; server enforces only `validatePositiveAmount` which accepts any > 0. Bump `min="1"` and consider `step="1"` (whole-dollar) — fewer fat-finger options and matches real-world denominations.** L13 forgiveness.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:182-190`

- [ ] WEB-UIUX-1567. **[NIT] List date columns lose intra-day ordering. `formatDate(card.created_at)` (`:388`) renders date only on most locale impls — issuing 5 cards on a busy day all show same date with `ORDER BY created_at DESC` driving the list. Fine for at-a-glance, but tooltip with full timestamp would help reconcile against shift logs.** L7 feedback.
  `packages/web/src/pages/gift-cards/GiftCardsListPage.tsx:387-389`
