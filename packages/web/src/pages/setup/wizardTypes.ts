/**
 * Shared type definitions for the first-run setup wizard.
 *
 * The wizard has two levels of state:
 *   - Outer `phase` — where we are in the linear mandatory/info flow, or in the hub
 *   - `activeCard` — only meaningful when phase === 'hub'; which extra is currently being configured
 *
 * `pendingWrites` collects values across all steps and is flushed to the server
 * in a single `PUT /settings/config` call at the end (either Complete or Skip).
 */

export type WizardPhase =
  | 'welcome'    // Step 1 — store name + theme (mandatory)
  | 'store'      // Step 2 — address/phone/email/timezone/currency (mandatory)
  | 'shopType'   // Step 2.5 — shop type picker (audit section 42) — skippable
  | 'trialInfo'  // Step 3 — 14-day Pro trial info (informational)
  | 'hub'        // Extras hub — non-linear card grid
  | 'review'     // Final summary
  | 'done';      // Redirect to dashboard fires

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
 * Keys must match the ALLOWED_CONFIG_KEYS set in settings.routes.ts.
 */
export interface PendingWrites {
  // Welcome step
  store_name?: string;
  theme?: 'light' | 'dark' | 'system';

  // Store info step
  store_address?: string;
  store_phone?: string;
  store_email?: string;
  store_timezone?: string;
  store_currency?: string;

  // Business hours card (JSON blob — see StepBusinessHours for schema)
  business_hours?: string;

  // Logo & branding card
  store_logo?: string;
  theme_primary_color?: string;

  // Receipts card
  receipt_header?: string;
  receipt_footer?: string;
  receipt_title?: string;

  // SMS provider card
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

  // Email SMTP card
  smtp_host?: string;
  smtp_port?: string;
  smtp_user?: string;
  smtp_pass?: string;
  smtp_from?: string;

  // Final flag — always written last
  wizard_completed?: 'true' | 'skipped';
}

/**
 * Props that every step component receives from the wizard shell.
 * Steps don't manage their own navigation — they call back to the shell
 * via onNext/onBack/onUpdate and the shell handles phase transitions.
 */
export interface StepProps {
  /** Values collected so far across all steps */
  pending: PendingWrites;
  /** Merge-update the pending writes bundle */
  onUpdate: (patch: Partial<PendingWrites>) => void;
  /** Advance to next step (mandatory steps only; hub/sub-step exits use onReturnToHub) */
  onNext: () => void;
  /** Back to previous step (welcome has no back) */
  onBack: () => void;
}

/**
 * Additional props for sub-step components rendered inside the Extras Hub.
 * Sub-steps mark themselves complete via onComplete, which adds them to
 * completedCards and returns the user to the hub grid.
 */
export interface SubStepProps extends Omit<StepProps, 'onNext' | 'onBack'> {
  /** Mark this card as complete and return to hub */
  onComplete: () => void;
  /** Return to hub without marking complete (discard any local state) */
  onCancel: () => void;
}
