import { CheckCircle2, Loader2, ArrowLeft, AlertTriangle } from 'lucide-react';
import type { PendingWrites, ExtraCardId } from '../wizardTypes';
import { checkMandatoryFields } from '@/services/validationService';

const SENSITIVE_KEYS = new Set<keyof PendingWrites>([
  'sms_twilio_auth_token',
  'sms_telnyx_api_key',
  'sms_bandwidth_password',
  'sms_plivo_auth_token',
  'sms_vonage_api_secret',
  'smtp_pass',
]);

interface StepReviewProps {
  pending: PendingWrites;
  completedCards: Set<ExtraCardId>;
  onBack: () => void;
  onComplete: () => void;
  onSkip: () => void;
  saving: boolean;
  error: string;
}

/**
 * Final step — review + commit.
 *
 * Calls checkMandatoryFields before render. If any required fields are
 * missing or invalid, shows a prominent banner and blocks the Complete
 * button. The Skip button remains available so the user can still bail.
 *
 * Shows a summary of what was collected across the wizard (mandatory fields +
 * any extras the user configured), masking sensitive credentials. Two CTAs:
 *   "Complete Setup" flushes everything with wizard_completed='true'
 *   "Skip extras" flushes everything with wizard_completed='skipped'
 *     (use this if the user filled out mandatory steps but wants to bail on
 *     the hub extras — their data is still saved)
 */
export function StepReview({ pending, completedCards, onBack, onComplete, onSkip, saving, error }: StepReviewProps) {
  // Run mandatory-field check before rendering CTAs
  const missingFields = checkMandatoryFields(pending);
  const isBlocked = missingFields.length > 0;

  const mandatoryRows: Array<[string, string]> = [];
  if (pending.store_name) mandatoryRows.push(['Store name', pending.store_name]);
  if (pending.theme) mandatoryRows.push(['Theme', pending.theme]);
  if (pending.store_address) mandatoryRows.push(['Address', pending.store_address]);
  if (pending.store_phone) mandatoryRows.push(['Phone', pending.store_phone]);
  if (pending.store_email) mandatoryRows.push(['Email', pending.store_email]);
  if (pending.store_timezone) mandatoryRows.push(['Timezone', pending.store_timezone]);
  if (pending.store_currency) mandatoryRows.push(['Currency', pending.store_currency]);

  const extraRows: Array<[string, string]> = [];
  if (completedCards.has('notifications')) extraRows.push(['Customer notifications', 'Configured']);
  if (completedCards.has('hours')) extraRows.push(['Business hours', 'Configured']);
  if (completedCards.has('tax')) extraRows.push(['Tax rate', 'Configured']);
  if (completedCards.has('logo')) extraRows.push(['Logo & branding', 'Configured']);
  if (completedCards.has('receipts')) extraRows.push(['Receipt layout', 'Configured']);
  if (completedCards.has('import')) extraRows.push(['Data import', 'Started']);
  if (completedCards.has('sms')) extraRows.push(['SMS provider', pending.sms_provider_type || 'Configured']);
  if (completedCards.has('email')) extraRows.push(['Email (SMTP)', pending.smtp_host || 'Configured']);

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 text-center">
        <div className={`mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl ${isBlocked ? 'bg-amber-100 dark:bg-amber-500/10' : 'bg-green-100 dark:bg-green-500/10'}`}>
          {isBlocked
            ? <AlertTriangle className="h-7 w-7 text-amber-600 dark:text-amber-400" />
            : <CheckCircle2 className="h-7 w-7 text-green-600 dark:text-green-400" />
          }
        </div>
        <h2 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          {isBlocked ? 'Almost there' : 'Ready to go'}
        </h2>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          {isBlocked
            ? 'Fix the issues below, then click Complete Setup.'
            : <>Review what you've configured. Click <strong>Complete Setup</strong> to save and enter your dashboard.</>
          }
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">

        {/* Missing-field banner — shown when mandatory fields are invalid */}
        {isBlocked && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 p-4 dark:border-amber-500/30 dark:bg-amber-500/10">
            <div className="mb-2 flex items-center gap-2 text-sm font-semibold text-amber-800 dark:text-amber-300">
              <AlertTriangle className="h-4 w-4 flex-shrink-0" />
              Cannot complete setup. Missing or invalid:
            </div>
            <ul className="space-y-1 pl-6">
              {missingFields.map(({ label, error: fieldError }) => (
                <li key={label} className="flex items-start gap-2 text-sm text-amber-700 dark:text-amber-400">
                  <span className="font-medium">{label}:</span>
                  <span>{fieldError}</span>
                </li>
              ))}
            </ul>
            <button
              type="button"
              onClick={onBack}
              className="mt-3 text-sm font-medium text-amber-800 underline underline-offset-2 hover:text-amber-900 dark:text-amber-300 dark:hover:text-amber-200"
            >
              Go back and fix these fields
            </button>
          </div>
        )}

        {/* Mandatory info */}
        <section>
          <h3 className="mb-3 text-xs font-bold uppercase tracking-wide text-surface-500 dark:text-surface-400">
            Store info
          </h3>
          <dl className="space-y-1.5">
            {mandatoryRows.map(([label, value]) => (
              <div key={label} className="flex justify-between gap-4 text-sm">
                <dt className="text-surface-500 dark:text-surface-400">{label}</dt>
                <dd className="text-right font-medium text-surface-900 dark:text-surface-100">
                  {SENSITIVE_KEYS.has(label as keyof PendingWrites) ? '••••••' : value}
                </dd>
              </div>
            ))}
          </dl>
        </section>

        {/* Extras */}
        {extraRows.length > 0 ? (
          <section>
            <h3 className="mb-3 text-xs font-bold uppercase tracking-wide text-surface-500 dark:text-surface-400">
              Extras configured
            </h3>
            <dl className="space-y-1.5">
              {extraRows.map(([label, value]) => (
                <div key={label} className="flex justify-between gap-4 text-sm">
                  <dt className="flex items-center gap-2 text-surface-500 dark:text-surface-400">
                    <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
                    {label}
                  </dt>
                  <dd className="text-right font-medium text-surface-900 dark:text-surface-100">{value}</dd>
                </div>
              ))}
            </dl>
          </section>
        ) : (
          <p className="rounded-lg bg-surface-50 p-3 text-center text-xs text-surface-500 dark:bg-surface-700/30 dark:text-surface-400">
            No extras configured — that's fine, you can set them up later in Settings.
          </p>
        )}

        {error && (
          <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300">
            {error}
          </p>
        )}

        {/* CTAs */}
        <div className="flex items-center justify-between pt-2">
          <button
            type="button"
            onClick={onBack}
            disabled={saving}
            className="flex items-center gap-1 text-sm font-medium text-surface-600 hover:text-surface-900 disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-100"
          >
            <ArrowLeft className="h-4 w-4" />
            Back to hub
          </button>
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={onSkip}
              disabled={saving}
              className="text-xs font-medium text-surface-500 hover:text-surface-900 disabled:opacity-50 dark:text-surface-400 dark:hover:text-surface-100"
            >
              Skip extras for now
            </button>
            <button
              type="button"
              onClick={onComplete}
              disabled={saving || isBlocked}
              title={isBlocked ? 'Fix missing fields before completing setup' : undefined}
              className="flex items-center gap-2 rounded-lg bg-green-600 px-6 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-green-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {saving ? <Loader2 className="h-5 w-5 animate-spin" /> : <CheckCircle2 className="h-5 w-5" />}
              Complete Setup
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
