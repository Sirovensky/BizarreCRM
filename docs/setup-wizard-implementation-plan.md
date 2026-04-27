# Setup Wizard Implementation Plan

**Branch:** `todofixes426` (DO NOT branch off; all agents commit here)
**Visual source of truth:** `docs/setup-wizard-preview.html` — every requirement below maps to a `<section id="screen-N">` in that file. When in doubt, open that file and read the corresponding section's annotations panel.
**Tenancy modes:** Self-host (single-tenant LAN) and SaaS (multi-tenant). Wizard reads `isMultiTenant` from `GET /api/v1/auth/setup-status` and renders mode-specific entry screens.

---

## Workflow rules (binding for every agent)

1. **Branch:** Stay on `todofixes426`. No new branches. Pull before commit.
2. **Scope:** One agent = one file (or one tightly-coupled file group). No cross-file edits outside your scope. If your task requires editing a file owned by another agent, **stop and report back** so the human merges.
3. **Shared contracts (frozen — humans only edit these):**
   - `packages/web/src/pages/setup/wizardTypes.ts` — `WizardPhase`, `PendingWrites`, `StepProps`, `SubStepProps`
   - `packages/web/src/pages/setup/SetupPage.tsx` — phase machine wiring
   - `packages/server/src/routes/settings.routes.ts` `ALLOWED_CONFIG_KEYS` — backend config-key allowlist
   - `packages/web/src/api/endpoints.ts` — typed API surface
   Treat these as read-only. Use the keys/types defined here. If you need a new key/phase, request it.
4. **Response shape reminder:** Every endpoint returns `{ success: true, data: <payload> }`; axios wraps once more, so frontend reads `res.data.data`. See `CLAUDE.md` "Things that WILL bite you #1".
5. **Validation:** Reuse `packages/web/src/services/validationService.ts` (already built). Do not duplicate validators.
6. **Brand color:** Cream `#fdeed0` lives at `primary-500` in `packages/web/tailwind.config.ts`. Use Tailwind utilities (`bg-primary-500`, `text-primary-900`, etc.) — never hex literals.
7. **No Material 3 Expressive on web.** Plain Tailwind + lucide-react icons. M3 is Android-only.
8. **Done condition per agent:**
   - File compiles (`npx tsc --noEmit -p packages/web/tsconfig.json` for web; `tsc -p packages/server` for server)
   - No runtime references to nonexistent ALLOWED_CONFIG_KEYS / endpoints
   - Visual matches the corresponding mockup screen at desktop width 1280+
   - Report back with the file path(s) touched + a 3-line summary

---

## Temporary dev shortcut: SKIP-EMAIL-CHECK

Email outbound is not wired yet. To unblock SaaS-mode testing of the wizard end-to-end:

- **Backend:** `POST /api/v1/auth/verify-email/dev-skip` — marks the current pending account as verified WITHOUT sending or checking a code. Gated behind `process.env.NODE_ENV !== 'production'` AND `process.env.WIZARD_DEV_SKIP_EMAIL === '1'`. Returns 404 in production. Audit-logs every call.
- **Frontend:** `StepVerifyEmail` shows a yellow "Skip email check (dev only)" button below the code input when `import.meta.env.DEV === true`. Calls the dev-skip endpoint, then advances.
- **Removal:** Track in `TODO.md` as `WIZARD-EMAIL-1` — must be ripped out before SaaS launch. Do not ship to production with this enabled.

---

## What humans build first (UNBLOCKS all agents)

These three edits land before any sub-agent fires. They are the contract every agent codes against.

### H1 — `wizardTypes.ts` extension
Add new phase strings and PendingWrites keys for the 26-screen flow.

```ts
export type WizardPhase =
  // Pre-wizard auth (mode-specific)
  | 'firstLogin'        // self-host only — Step 1
  | 'forcePassword'     // self-host only — Step 2
  | 'signup'            // SaaS only — Step 1
  | 'verifyEmail'       // SaaS only — Step 2
  | 'twoFactorSetup'    // both — Step 3
  // Wizard body (linear)
  | 'welcome'           // Step 4
  | 'shopType'          // Step 5
  | 'store'             // Step 6
  | 'importHandoff'     // Step 7
  | 'repairPricing'     // Step 8 (NEW)
  | 'defaultStatuses'   // Step 9
  | 'businessHours'     // Step 10
  | 'tax'               // Step 11
  | 'receipts'          // Step 12
  | 'logo'              // Step 13
  | 'paymentTerminal'   // Step 14 (NEW)
  | 'firstEmployees'    // Step 15 (NEW)
  | 'smsProvider'       // Step 16
  | 'emailSmtp'         // Step 17
  | 'notificationTemplates' // Step 18 (NEW)
  | 'receiptPrinter'    // Step 19 (NEW)
  | 'cashDrawer'        // Step 20 (NEW)
  | 'bookingPolicy'     // Step 21 (NEW)
  | 'warrantyDefaults'  // Step 22 (NEW)
  | 'backupDestination' // Step 23 (NEW)
  | 'mobileAppQr'       // Step 24 (NEW)
  | 'review'            // Step 25
  | 'done';             // Step 26
```

`PendingWrites` adds keys for every new step (see per-agent specs below for exact key names).

### H2 — `ALLOWED_CONFIG_KEYS` extension in `settings.routes.ts`
Add every new key referenced by new steps. List enumerated per-agent below.

### H3 — `SetupPage.tsx` linearization
Replace the welcome→store→hub→review machine with a strict linear `WIZARD_ORDER: WizardPhase[]`. Each `Step*` component receives `{ pending, onUpdate, onNext, onBack, onSkip }`. The `WizardBreadcrumb` component (Agent 17) is rendered above every step.

---

## Agent assignments

Format: **Agent N — owner of FILE(S)** | mockup screen | scope summary | exit criteria.

### Pre-wizard auth screens

#### Agent 1 — `packages/web/src/pages/setup/steps/StepFirstLogin.tsx` (NEW)
- Mockup: `#screen-1` (self-host only)
- Login form with username/password fields, default-credential warning banner (amber), "Sign in" button.
- Reads `force_password_change` flag from `GET /api/v1/auth/setup-status`. If true and login succeeds with default creds, advance to `forcePassword`. Otherwise advance to `twoFactorSetup`.
- Uses existing `authApi.login()`. No new endpoints.
- ALLOWED_CONFIG_KEYS: none.
- Done: typecheck clean; renders identically to mockup at 1280px; "Sign in" with admin/admin123 transitions to next step.

#### Agent 2 — `packages/web/src/pages/setup/steps/StepForcePassword.tsx` (NEW)
- Mockup: `#screen-2` (self-host only)
- New password + confirm fields. Strength meter (reuse `validationService.passwordStrength` if exists; else add ad-hoc check ≥10 chars, mixed case, digit).
- POST to existing `authApi.changePassword()` (verify shape — `auth.routes.ts` has `/auth/change-password`).
- On success: `onNext()` → `twoFactorSetup`.
- ALLOWED_CONFIG_KEYS: none.

#### Agent 3 — `packages/web/src/pages/setup/steps/StepSignup.tsx` (NEW)
- Mockup: `#screen-saas-1` (SaaS only)
- Fields: name, email, password (≥10), shop slug. Slug input has live `.bizarrecrm.com` suffix and availability check (debounced 400ms) calling new endpoint (Agent 19).
- Validators from `validationService.ts`: `validateEmail`, plus a new `validateShopSlug` (3-30 chars, lowercase a-z 0-9 dash, no leading/trailing dash). Add validator into `validationService.ts` as a single isolated export — coordinate with the human; do not edit other validators.
- Submit calls Agent-19's `POST /api/v1/auth/signup`. On success: store token, advance to `verifyEmail`.
- ALLOWED_CONFIG_KEYS: none (signup populates tenant DB, not `store_config`).

#### Agent 4 — `packages/web/src/pages/setup/steps/StepVerifyEmail.tsx` (NEW) + dev-skip button
- Mockup: `#screen-saas-2` (SaaS only)
- Read-only echoed email from `pending.signup_email` (set by Agent 3). 6-digit code input. "Resend" link (POSTs to Agent-20 endpoint). "Skip email check (dev only)" button visible only when `import.meta.env.DEV` — calls Agent-20's `/dev-skip`.
- On verify success: `onNext()` → `twoFactorSetup`.
- ALLOWED_CONFIG_KEYS: none.

#### Agent 5 — `packages/web/src/pages/setup/steps/StepTwoFactorSetup.tsx` (NEW)
- Mockup: `#screen-3`
- QR code (use `qrcode` npm dep — already installed; check `package.json`) for `otpauth://totp/...`. 6-digit code verification field. "Show backup codes" panel after success.
- Endpoints: `POST /api/v1/auth/2fa/enroll` (returns secret + provisioning URI), `POST /api/v1/auth/2fa/verify` (returns backup codes). If these don't exist, Agent 21 builds them.
- ALLOWED_CONFIG_KEYS: none (2FA secret in `users` table, not `store_config`).

### Wizard body — existing files to UPDATE only (not rewrite)

#### Agent 6 — `packages/web/src/pages/setup/steps/StepWelcome.tsx` (EDIT)
- Mockup: `#screen-4`
- Replace existing welcome with: shop name field, theme picker (light/dark/system), continue button. Drop any reference to "Let's get started in 5 minutes" if it duplicates the description below the title.
- Wire `onNext` to advance phase machine (no longer a phase-machine internal — just call prop).
- ALLOWED_CONFIG_KEYS: `store_name`, `theme` (already exist).

#### Agent 7 — `packages/web/src/pages/setup/steps/StepShopType.tsx` (EDIT)
- Mockup: `#screen-5`
- 4 large radio cards: "Phone repair", "Console & PC", "TV repair", "Mixed". Selection seeds default service templates downstream.
- Persists `shop_type` in pending writes.
- ALLOWED_CONFIG_KEYS: `shop_type` (NEW — add to H2 list).

#### Agent 8 — `packages/web/src/pages/setup/steps/StepStoreInfo.tsx` (EDIT)
- Mockup: `#screen-6`
- Address, phone (intl), shop email (PRE-FILLED from `pending.signup_email` for SaaS, blank for self-host), timezone (dropdown from `validationService.ALLOWED_TIMEZONES`), currency (`ALLOWED_CURRENCIES`).
- Helper text under email: "Pre-filled from your signup. Change if your shop uses a separate contact address." (SaaS only.)
- ALLOWED_CONFIG_KEYS: `store_address`, `store_phone`, `store_email`, `store_timezone`, `store_currency` (already exist).

#### Agent 9 — `packages/web/src/pages/setup/steps/StepImportHandoff.tsx` (EDIT — already exists)
- Mockup: `#screen-7`
- Already built. Verify deep-link: clicking "Yes, import now" should `navigate('/settings?tab=data&section=import')` (after Data tab merge from prior session). Update if the route still uses `tab=data-import`.

### NEW step files for wizard body

#### Agent 10 — `packages/web/src/pages/setup/steps/StepRepairPricing.tsx` (NEW)
- Mockup: `#screen-8`
- Three tier cards (A flagship / B mainstream / C legacy) with editable labor prices per service category (Screen, Battery, Charge port, Back glass, Camera). Default values from mockup.
- "Apply industry medians" button (no-op for now — wires to DPI-13 later).
- Banner: "Per-device override available later in Settings → Repair pricing → Matrix."
- Persists 15 keys: `pricing_tier_a_screen`, `..._battery`, `..._charge_port`, `..._back_glass`, `..._camera`, repeat for `_b_` and `_c_`.
- ALLOWED_CONFIG_KEYS: 15 NEW keys above.

#### Agent 11 — `packages/web/src/pages/setup/steps/StepDefaultStatuses.tsx` (EDIT)
- Mockup: `#screen-9`
- Already exists. Verify visual matches mockup. No backend changes.

#### Agent 12 — `packages/web/src/pages/setup/steps/StepBusinessHours.tsx` (EDIT)
- Mockup: `#screen-10`
- Already exists. Verify visual matches.

#### Agent 13 — `packages/web/src/pages/setup/steps/StepTax.tsx` (EDIT)
- Mockup: `#screen-11`. Already exists.

#### Agent 14 — `packages/web/src/pages/setup/steps/StepReceipts.tsx` (EDIT)
- Mockup: `#screen-12`. Already exists.

#### Agent 15 — `packages/web/src/pages/setup/steps/StepLogo.tsx` (EDIT)
- Mockup: `#screen-13`. Already exists. Confirm primary-color picker uses Tailwind primary scale, not raw hex.

#### Agent 16 — `packages/web/src/pages/setup/steps/StepPaymentTerminal.tsx` (NEW)
- Mockup: `#screen-14`
- Two cards: "BlockChyp credentials" (api_key, bearer_token, signing_key) + "Pair terminal" (terminal name, IP). "Test connection" button.
- Endpoints: existing `POST /api/v1/payments/blockchyp/heartbeat` (verify it exists; if not, Agent 22 stubs it).
- ALLOWED_CONFIG_KEYS: `blockchyp_api_key`, `blockchyp_bearer_token`, `blockchyp_signing_key`, `blockchyp_terminal_name`, `blockchyp_terminal_ip`.

#### Agent 17 — `packages/web/src/pages/setup/steps/StepFirstEmployees.tsx` (NEW)
- Mockup: `#screen-15`
- Editable list of employee invites: name, email, role (admin/tech/cashier). "Add another" button. "Send invites" button at submit.
- Endpoints: existing `POST /api/v1/users` for each invite. Loops on submit.
- ALLOWED_CONFIG_KEYS: none (writes to `users` table).

#### Agent 18 — `packages/web/src/pages/setup/steps/StepSmsProvider.tsx` (EDIT)
- Mockup: `#screen-16`. Already exists.

#### Agent 19 — `packages/web/src/pages/setup/steps/StepEmailSmtp.tsx` (EDIT)
- Mockup: `#screen-17`. Already exists.

#### Agent 20 — `packages/web/src/pages/setup/steps/StepNotificationTemplates.tsx` (NEW)
- Mockup: `#screen-18`
- Three template editors: "Ticket received", "Ticket ready for pickup", "Invoice paid". Each with subject + body textareas, variable cheatsheet (`{customer_name}`, `{ticket_id}`, etc.). "Send test SMS/email" button.
- ALLOWED_CONFIG_KEYS: `notif_tpl_received_subj`, `_body`, `notif_tpl_ready_subj`, `_body`, `notif_tpl_invoice_paid_subj`, `_body`.

#### Agent 21 — `packages/web/src/pages/setup/steps/StepReceiptPrinter.tsx` (NEW)
- Mockup: `#screen-19`
- Driver picker (ESC/POS, Star, Brother, none). Connection: USB / network IP. "Print test receipt" button.
- ALLOWED_CONFIG_KEYS: `receipt_printer_driver`, `receipt_printer_connection`, `receipt_printer_address`.

#### Agent 22 — `packages/web/src/pages/setup/steps/StepCashDrawer.tsx` (NEW)
- Mockup: `#screen-20`
- Driver picker (kicked-by-printer, network, none). "Pop drawer" test button.
- ALLOWED_CONFIG_KEYS: `cash_drawer_driver`, `cash_drawer_address`.

#### Agent 23 — `packages/web/src/pages/setup/steps/StepBookingPolicy.tsx` (NEW)
- Mockup: `#screen-21`
- Online booking on/off. Min lead time (hours). Max future booking (days). Walk-in accept toggle.
- ALLOWED_CONFIG_KEYS: `booking_online_enabled`, `booking_lead_hours`, `booking_max_days_ahead`, `booking_walkins_enabled`.

#### Agent 24 — `packages/web/src/pages/setup/steps/StepWarrantyDefaults.tsx` (NEW)
- Mockup: `#screen-22`
- Default warranty months by category (Screen, Battery, Charge port, etc.). Disclaimer field.
- ALLOWED_CONFIG_KEYS: `warranty_default_months_screen`, `_battery`, `_charge_port`, `_back_glass`, `_camera`, `warranty_disclaimer`.

#### Agent 25 — `packages/web/src/pages/setup/steps/StepBackupDestination.tsx` (NEW)
- Mockup: `#screen-23`
- Three radio cards: Local folder / S3-compatible / Tailscale share. Conditional fields per choice. "Run test backup" button.
- ALLOWED_CONFIG_KEYS: `backup_destination_type`, `backup_destination_path`, `backup_s3_endpoint`, `backup_s3_bucket`, `backup_s3_access_key`, `backup_s3_secret_key`.

#### Agent 26 — `packages/web/src/pages/setup/steps/StepMobileAppQr.tsx` (NEW)
- Mockup: `#screen-24`
- QR code linking staff phones to the LAN IP. Reads `GET /api/v1/info` (exists per CLAUDE.md item #4) for `lan_ip` + port.
- ALLOWED_CONFIG_KEYS: none.

#### Agent 27 — `packages/web/src/pages/setup/steps/StepReview.tsx` (EDIT)
- Mockup: `#screen-25`
- Already exists. Update to display every new key category as collapsible section. Reuse the `checkMandatoryFields()` helper from `validationService`.

#### Agent 28 — `packages/web/src/pages/setup/steps/StepDone.tsx` (NEW)
- Mockup: `#screen-26`
- Three "next-step" cards (NON-DUPLICATE with the dashboard first-setup view):
  1. **Per-device pricing matrix** → `/settings?tab=repair-pricing&view=matrix`
  2. **Customer portal** → `/settings?tab=customer-portal`
  3. **Auto-reorder rules** → `/settings?tab=inventory&section=reorder`
- "Go to dashboard" primary button → `/dashboard`.
- Writes `wizard_completed = 'true'`.

### Shared infrastructure

#### Agent 29 — `packages/web/src/pages/setup/components/WizardBreadcrumb.tsx` (NEW)
- Pill-style top breadcrumb: `← Step N-1 · STEP N · Step N+1 →`. Center pill is `bg-primary-500 text-primary-950 font-bold`. Side pills muted.
- Props: `{ prevLabel?: string; currentLabel: string; nextLabel?: string; }`.
- Imported by every Step* component as the first child of its root div.

#### Agent 30 — `packages/web/src/components/TrialBanner.tsx` (NEW)
- Reads trial expiry from auth store. Renders ONLY when `daysUntilExpiry <= 3` AND mode === 'saas'. Amber background, dismissable per session.
- Mounts in `AppLayout.tsx` (the human will wire that line — agent only owns the component file).

### Backend

#### Agent 31 — `packages/server/src/routes/auth.signup.routes.ts` (NEW, mounted in `index.ts` by human)
- `POST /api/v1/auth/signup` — provisions tenant DB at `data/tenants/<slug>.db`, creates owner user, issues 14-day Pro trial, returns JWT + refresh.
- `GET /api/v1/auth/signup/slug-available?slug=foo` — returns `{ available: boolean }`.
- ALLOWED_CONFIG_KEYS: `trial_started_at`, `trial_expires_at`, `tier` (added by H2).

#### Agent 32 — `packages/server/src/routes/auth.verifyEmail.routes.ts` (NEW)
- `POST /api/v1/auth/verify-email/send` — sends 6-digit code (no-op if SMTP not configured; logs to server log instead — fine for dev).
- `POST /api/v1/auth/verify-email/verify` — checks code.
- `POST /api/v1/auth/verify-email/dev-skip` — TEMP. Gated as documented above.
- Audit-log every call.

#### Agent 33 — `packages/server/src/routes/auth.twoFactor.routes.ts` (NEW or EXTEND)
- `POST /api/v1/auth/2fa/enroll` — generates TOTP secret, returns provisioning URI + QR data URL.
- `POST /api/v1/auth/2fa/verify` — verifies code, persists `users.totp_secret`, returns 10 backup codes.
- Use `otplib` if not present.

---

## Summary — file ownership

| Owner | File |
|---|---|
| Human | `wizardTypes.ts` |
| Human | `SetupPage.tsx` |
| Human | `settings.routes.ts` ALLOWED_CONFIG_KEYS |
| Human | `validationService.ts` (single edit: add `validateShopSlug`) |
| Human | `AppLayout.tsx` (single line: mount `<TrialBanner />`) |
| Agent 1 | `StepFirstLogin.tsx` |
| Agent 2 | `StepForcePassword.tsx` |
| Agent 3 | `StepSignup.tsx` |
| Agent 4 | `StepVerifyEmail.tsx` |
| Agent 5 | `StepTwoFactorSetup.tsx` |
| Agent 6 | `StepWelcome.tsx` |
| Agent 7 | `StepShopType.tsx` |
| Agent 8 | `StepStoreInfo.tsx` |
| Agent 9 | `StepImportHandoff.tsx` |
| Agent 10 | `StepRepairPricing.tsx` |
| Agent 11 | `StepDefaultStatuses.tsx` |
| Agent 12 | `StepBusinessHours.tsx` |
| Agent 13 | `StepTax.tsx` |
| Agent 14 | `StepReceipts.tsx` |
| Agent 15 | `StepLogo.tsx` |
| Agent 16 | `StepPaymentTerminal.tsx` |
| Agent 17 | `StepFirstEmployees.tsx` |
| Agent 18 | `StepSmsProvider.tsx` |
| Agent 19 | `StepEmailSmtp.tsx` |
| Agent 20 | `StepNotificationTemplates.tsx` |
| Agent 21 | `StepReceiptPrinter.tsx` |
| Agent 22 | `StepCashDrawer.tsx` |
| Agent 23 | `StepBookingPolicy.tsx` |
| Agent 24 | `StepWarrantyDefaults.tsx` |
| Agent 25 | `StepBackupDestination.tsx` |
| Agent 26 | `StepMobileAppQr.tsx` |
| Agent 27 | `StepReview.tsx` |
| Agent 28 | `StepDone.tsx` |
| Agent 29 | `WizardBreadcrumb.tsx` |
| Agent 30 | `TrialBanner.tsx` |
| Agent 31 | `auth.signup.routes.ts` |
| Agent 32 | `auth.verifyEmail.routes.ts` |
| Agent 33 | `auth.twoFactor.routes.ts` |

---

## Execution order

1. **Human:** H1 → H2 → H3 (SetupPage uses placeholder `<div>Step N</div>` for each new phase so it compiles).
2. **Human:** add `validateShopSlug` to validationService.
3. **Wave 1 (parallel — backend):** Agents 31, 32, 33.
4. **Wave 2 (parallel — shared shell):** Agents 29, 30.
5. **Wave 3 (parallel — pre-wizard auth):** Agents 1, 2, 3, 4, 5.
6. **Wave 4 (parallel — wizard body new):** Agents 7, 10, 16, 17, 20, 21, 22, 23, 24, 25, 26, 28.
7. **Wave 5 (parallel — wizard body edit):** Agents 6, 8, 9, 11, 12, 13, 14, 15, 18, 19, 27.
8. **Human:** swap placeholder `<div>`s in `SetupPage.tsx` for real Step components after each wave lands.
9. **Human:** typecheck both packages, run the wizard end-to-end in dev mode using `/auth/verify-email/dev-skip` for SaaS, and merge to main.

Each wave is fully parallel within itself because every agent owns a distinct file.

---

## Skip-button cleanup task (already in TODO.md)

Add `WIZARD-EMAIL-1` to `TODO.md`:

> Remove `POST /api/v1/auth/verify-email/dev-skip` route + the dev-skip button in `StepVerifyEmail.tsx` before SaaS launch. Currently gated behind `NODE_ENV !== 'production'` + `WIZARD_DEV_SKIP_EMAIL=1` env, but a stray prod env var would expose it. Belt-and-suspenders: delete the code path entirely once SMTP is wired and verified.
