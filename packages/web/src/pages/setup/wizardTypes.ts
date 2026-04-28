/**
 * Shared type definitions for the first-run setup wizard.
 *
 * H1 (2026-04-27): expanded to the full 26-screen flow defined in
 * `docs/setup-wizard-implementation-plan.md`. Previous welcome→store→hub→review
 * machine is replaced with a strict linear `WIZARD_ORDER` sequence. Each Step*
 * component receives `{ pending, onUpdate, onNext, onBack, onSkip }` and the
 * shell handles all phase transitions.
 *
 * `pendingWrites` collects values across all steps and is flushed to the server
 * in a single `PUT /settings/config` call at the end (either Complete or Skip).
 */

export type WizardPhase =
  // Pre-wizard auth (mode-specific entry — gated on isMultiTenant)
  | 'firstLogin'        // Step 1 self-host — admin/admin123 default + force-pw warning
  | 'forcePassword'     // Step 2 self-host — change default password
  | 'signup'            // Step 1 SaaS — name/email/password/slug
  | 'verifyEmail'       // Step 2 SaaS — 6-digit code (with TEMP dev-skip in dev mode)
  | 'twoFactorSetup'    // Step 3 both — TOTP enroll + backup codes
  // Wizard body (linear)
  | 'welcome'           // Step 4 — shop name + theme
  | 'shopType'          // Step 5 — phone / console-pc / tv / mixed (NEW)
  | 'store'             // Step 6 — address/phone/email/timezone/currency
  | 'importHandoff'     // Step 7 — will-import / later / fresh
  | 'repairPricing'     // Step 8 — tier-based labor matrix (NEW)
  | 'defaultStatuses'   // Step 9 — ticket status seed
  | 'businessHours'     // Step 10 — open/close per weekday
  | 'tax'               // Step 11 — tax classes + rates
  | 'receipts'          // Step 12 — receipt header/footer/title
  | 'logo'              // Step 13 — logo + brand color
  | 'paymentTerminal'   // Step 14 — BlockChyp creds + terminal pairing (NEW)
  | 'firstEmployees'    // Step 15 — invite first staff (NEW)
  | 'smsProvider'       // Step 16 — Twilio/Telnyx/etc.
  | 'emailSmtp'         // Step 17 — SMTP credentials
  | 'notificationTemplates' // Step 18 — ticket received / ready / invoice paid (NEW)
  | 'receiptPrinter'    // Step 19 — driver + connection (NEW)
  | 'cashDrawer'        // Step 20 — drawer driver (NEW)
  | 'bookingPolicy'     // Step 21 — online booking on/off + lead times (NEW)
  | 'warrantyDefaults'  // Step 22 — default warranty months per category (NEW)
  | 'backupDestination' // Step 23 — local / S3 / Tailscale (NEW)
  | 'mobileAppQr'       // Step 24 — staff mobile-app QR (NEW)
  | 'review'            // Step 25 — summary
  | 'done';             // Step 26 — non-duplicate Settings deep-links + Go to dashboard

/**
 * Strict linear order. SetupPage advances along this array using
 * orderedPhases.indexOf(phase) + 1. Pre-wizard auth phases are inserted
 * conditionally (self-host vs SaaS) but the ordering within each branch
 * is fixed.
 */
export const WIZARD_ORDER_SELF: WizardPhase[] = [
  'firstLogin', 'forcePassword', 'twoFactorSetup',
  'welcome', 'shopType', 'store', 'importHandoff', 'repairPricing',
  'defaultStatuses', 'businessHours', 'tax', 'receipts', 'logo',
  'paymentTerminal', 'firstEmployees',
  'smsProvider', 'emailSmtp', 'notificationTemplates',
  'receiptPrinter', 'cashDrawer', 'bookingPolicy',
  'warrantyDefaults', 'backupDestination', 'mobileAppQr',
  'review', 'done',
];

export const WIZARD_ORDER_SAAS: WizardPhase[] = [
  'signup', 'verifyEmail', 'twoFactorSetup',
  'welcome', 'shopType', 'store', 'importHandoff', 'repairPricing',
  'defaultStatuses', 'businessHours', 'tax', 'receipts', 'logo',
  'paymentTerminal', 'firstEmployees',
  'smsProvider', 'emailSmtp', 'notificationTemplates',
  'receiptPrinter', 'cashDrawer', 'bookingPolicy',
  'warrantyDefaults', 'backupDestination', 'mobileAppQr',
  'review', 'done',
];

/**
 * Post-auth wizard body order (welcome → done). SetupPage runs behind
 * ProtectedRoute so the user is ALWAYS authenticated by the time it
 * mounts; the pre-auth phases (firstLogin/forcePassword/signup/
 * verifyEmail/twoFactorSetup) live in the SELF/SAAS orders only for
 * forward-compat in case we later route /signup itself through the
 * wizard shell. Today they are dead within SetupPage and the Back
 * button must NOT walk into them — so SetupPage uses this body order
 * exclusively. Both modes share the same body sequence.
 */
export const WIZARD_BODY_ORDER: WizardPhase[] = [
  'welcome', 'shopType', 'store', 'importHandoff', 'repairPricing',
  'defaultStatuses', 'businessHours', 'tax', 'receipts', 'logo',
  'paymentTerminal', 'firstEmployees',
  'smsProvider', 'emailSmtp', 'notificationTemplates',
  'receiptPrinter', 'cashDrawer', 'bookingPolicy',
  'warrantyDefaults', 'backupDestination', 'mobileAppQr',
  'review', 'done',
];

/** Human-readable label per phase (used by WizardBreadcrumb). */
export const WIZARD_PHASE_LABELS: Record<WizardPhase, string> = {
  firstLogin: 'First login',
  forcePassword: 'Set password',
  signup: 'Signup',
  verifyEmail: 'Verify email',
  twoFactorSetup: '2FA setup',
  welcome: 'Welcome',
  shopType: 'Shop type',
  store: 'Store info',
  importHandoff: 'Import',
  repairPricing: 'Repair pricing',
  defaultStatuses: 'Default statuses',
  businessHours: 'Business hours',
  tax: 'Tax',
  receipts: 'Receipts',
  logo: 'Logo',
  paymentTerminal: 'Payment terminal',
  firstEmployees: 'First employees',
  smsProvider: 'SMS provider',
  emailSmtp: 'Email SMTP',
  notificationTemplates: 'Notification templates',
  receiptPrinter: 'Receipt printer',
  cashDrawer: 'Cash drawer',
  bookingPolicy: 'Booking policy',
  warrantyDefaults: 'Warranty defaults',
  backupDestination: 'Backup',
  mobileAppQr: 'Mobile app',
  review: 'Review',
  done: 'Done',
};

/**
 * Hub-extras card IDs — preserved for backward compatibility with
 * StepImport / sub-step components that still receive `SubStepProps`.
 * The new linear flow does not use the hub, but the type stays so old
 * step files compile until they're rewritten.
 */
export type ExtraCardId =
  | 'hours'
  | 'tax'
  | 'logo'
  | 'receipts'
  | 'import'
  | 'sms'
  | 'email'
  | 'notifications';

/**
 * Values collected across the wizard that will be bulk-written to `store_config`
 * via `settingsApi.updateConfig` on commit. All fields are optional — only the
 * steps the user actually completes populate them. Mandatory steps (welcome,
 * store) always populate their fields before advancing.
 *
 * Keys must match the ALLOWED_CONFIG_KEYS set in settings.routes.ts (H2).
 * Special keys NOT persisted to store_config (used only for in-flow state):
 *   signup_email — captured in Step 1 SaaS, pre-fills Step 6 store_email.
 */
export interface PendingWrites {
  // ─── In-flow only (NOT persisted) ────────────────────────────────
  signup_email?: string;              // SaaS: account email captured at signup, pre-fills store_email

  // ─── Welcome step ────────────────────────────────────────────────
  store_name?: string;
  theme?: 'light' | 'dark' | 'system';

  // ─── Shop type step (NEW) ────────────────────────────────────────
  shop_type?: 'phone' | 'console_pc' | 'tv' | 'mixed';

  // ─── Store info step ─────────────────────────────────────────────
  store_address?: string;
  store_phone?: string;
  store_email?: string;
  store_timezone?: string;
  store_currency?: string;

  // ─── Repair pricing step (NEW — tier-based labor) ────────────────
  pricing_tier_a_screen?: string;
  pricing_tier_a_battery?: string;
  pricing_tier_a_charge_port?: string;
  pricing_tier_a_back_glass?: string;
  pricing_tier_a_camera?: string;
  pricing_tier_b_screen?: string;
  pricing_tier_b_battery?: string;
  pricing_tier_b_charge_port?: string;
  pricing_tier_b_back_glass?: string;
  pricing_tier_b_camera?: string;
  pricing_tier_c_screen?: string;
  pricing_tier_c_battery?: string;
  pricing_tier_c_charge_port?: string;
  pricing_tier_c_back_glass?: string;
  pricing_tier_c_camera?: string;

  // ─── Business hours card ─────────────────────────────────────────
  business_hours?: string;

  // ─── Tax defaults (per-category %) ───────────────────────────────
  tax_default_parts?: string;
  tax_default_services?: string;
  tax_default_accessories?: string;

  // ─── Logo & branding ─────────────────────────────────────────────
  store_logo?: string;
  theme_primary_color?: string;

  // ─── Receipts ────────────────────────────────────────────────────
  receipt_header?: string;
  receipt_footer?: string;
  receipt_title?: string;

  // ─── Payment terminal (NEW) ──────────────────────────────────────
  blockchyp_api_key?: string;
  blockchyp_bearer_token?: string;
  blockchyp_signing_key?: string;
  blockchyp_terminal_name?: string;
  blockchyp_terminal_ip?: string;

  // ─── SMS provider ────────────────────────────────────────────────
  sms_provider_type?: string;
  sms_twilio_account_sid?: string;
  sms_twilio_auth_token?: string;
  sms_twilio_from_number?: string;
  sms_telnyx_api_key?: string;
  sms_telnyx_from_number?: string;
  sms_bandwidth_account_id?: string;
  sms_bandwidth_username?: string;
  sms_bandwidth_password?: string;
  sms_bandwidth_application_id?: string;
  sms_bandwidth_from_number?: string;
  sms_plivo_auth_id?: string;
  sms_plivo_auth_token?: string;
  sms_plivo_from_number?: string;
  sms_vonage_api_key?: string;
  sms_vonage_api_secret?: string;
  sms_vonage_from_number?: string;

  // ─── Email SMTP ──────────────────────────────────────────────────
  smtp_host?: string;
  smtp_port?: string;
  smtp_user?: string;
  smtp_pass?: string;
  smtp_from?: string;

  // ─── Notification templates (NEW) ────────────────────────────────
  // Per-template enabled flags ('1' | '0'). Three lifecycle events default
  // to enabled; appointment reminder defaults disabled because not every
  // shop takes bookings.
  notif_tpl_received_enabled?: '1' | '0';
  notif_tpl_received_subj?: string;
  notif_tpl_received_body?: string;
  notif_tpl_ready_enabled?: '1' | '0';
  notif_tpl_ready_subj?: string;
  notif_tpl_ready_body?: string;
  notif_tpl_invoice_paid_enabled?: '1' | '0';
  notif_tpl_invoice_paid_subj?: string;
  notif_tpl_invoice_paid_body?: string;
  notif_tpl_appt_reminder_enabled?: '1' | '0';
  notif_tpl_appt_reminder_subj?: string;
  notif_tpl_appt_reminder_body?: string;

  // ─── Receipt printer (NEW) ───────────────────────────────────────
  receipt_printer_driver?: string;
  receipt_printer_connection?: string;
  receipt_printer_address?: string;

  // ─── Cash drawer (NEW) ───────────────────────────────────────────
  cash_drawer_driver?: string;
  cash_drawer_address?: string;

  // ─── Booking policy (NEW) ────────────────────────────────────────
  booking_online_enabled?: string;
  booking_lead_hours?: string;
  booking_max_days_ahead?: string;
  booking_walkins_enabled?: string;

  // ─── Warranty defaults (NEW) ─────────────────────────────────────
  warranty_default_months_screen?: string;
  warranty_default_months_battery?: string;
  warranty_default_months_charge_port?: string;
  warranty_default_months_back_glass?: string;
  warranty_default_months_camera?: string;
  warranty_disclaimer?: string;

  // ─── Backup destination (NEW) ────────────────────────────────────
  backup_destination_type?: 'local' | 's3' | 'tailscale';
  backup_destination_path?: string;
  backup_s3_endpoint?: string;
  backup_s3_bucket?: string;
  backup_s3_access_key?: string;
  backup_s3_secret_key?: string;

  // ─── Import handoff ──────────────────────────────────────────────
  setup_imported_legacy_data?: 'will_import' | 'later' | 'fresh';

  // ─── Trial / tier (SaaS — written by Agent 31 signup route) ──────
  trial_started_at?: string;
  trial_expires_at?: string;
  tier?: 'trial' | 'free' | 'pro';

  // ─── Final flag — always written last ────────────────────────────
  wizard_completed?: 'true' | 'skipped';
}

/**
 * Props that every step component receives from the wizard shell.
 * Steps don't manage their own navigation — they call back to the shell
 * via onNext/onBack/onUpdate and the shell handles phase transitions.
 *
 * H1: added `onSkip` so any step can fire the global skip-to-dashboard
 * action (previously only the top-bar SkipToDashboard button could).
 */
export interface StepProps {
  /** Values collected so far across all steps */
  pending: PendingWrites;
  /** Merge-update the pending writes bundle */
  onUpdate: (patch: Partial<PendingWrites>) => void;
  /** Advance to next step */
  onNext: () => void;
  /** Back to previous step (no-op on first step) */
  onBack: () => void;
  /** Optional: skip the entire wizard and flush partial state */
  onSkip?: () => void;
}

/**
 * Additional props for sub-step components rendered inside the legacy
 * Extras Hub. Kept for backward compatibility while old step files
 * (StepImport, etc.) still reference SubStepProps. New linear-flow
 * step files MUST use StepProps instead.
 *
 * @deprecated New steps use StepProps. This interface is kept only to
 *   avoid breaking pre-H1 step files until they're rewritten.
 */
export interface SubStepProps extends Omit<StepProps, 'onNext' | 'onBack'> {
  /** Mark this card as complete and return to hub */
  onComplete: () => void;
  /** Return to hub without marking complete (discard any local state) */
  onCancel: () => void;
}
