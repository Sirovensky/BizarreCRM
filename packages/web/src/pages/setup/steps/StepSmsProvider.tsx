import { useState } from 'react';
import { MessageSquare } from 'lucide-react';
import type { SubStepProps, PendingWrites } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';

type ProviderId = 'twilio' | 'telnyx' | 'bandwidth' | 'plivo' | 'vonage';

/**
 * Sub-step — SMS Provider.
 *
 * Picks an SMS provider and collects the per-provider credentials. These are
 * stored as encrypted store_config values via the main flush at wizard finish.
 * The existing Settings > SMS & Voice page has a much richer UI with 10DLC
 * registration etc — this wizard step is deliberately minimal, just enough to
 * enable outgoing SMS. Users can refine later.
 *
 * Only the fields for the selected provider are collected — all keys are
 * typed in wizardTypes.ts.
 */
export function StepSmsProvider({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const [provider, setProvider] = useState<ProviderId | null>(
    (pending.sms_provider_type as ProviderId) || null,
  );

  const handleProvider = (id: ProviderId) => {
    setProvider(id);
    onUpdate({ sms_provider_type: id });
  };

  const field = (key: keyof PendingWrites, label: string, placeholder?: string, sensitive = false) => (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">{label}</label>
      <input
        type={sensitive ? 'password' : 'text'}
        value={(pending[key] as string) || ''}
        onChange={(e) => onUpdate({ [key]: e.target.value } as Partial<PendingWrites>)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
      />
    </div>
  );

  return (
    <div className="mx-auto max-w-xl">
      <SubStepHeader
        title="SMS Notifications"
        subtitle="Pick a provider and enter your API credentials. You can change this later in Settings."
        icon={<MessageSquare className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
      />

      <div className="space-y-4 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div>
          <label className="mb-2 block text-sm font-medium text-surface-700 dark:text-surface-300">Provider</label>
          <div className="grid grid-cols-3 gap-2">
            {(['twilio', 'telnyx', 'bandwidth', 'plivo', 'vonage'] as ProviderId[]).map((id) => (
              <button
                key={id}
                type="button"
                onClick={() => handleProvider(id)}
                className={`rounded-lg border-2 px-3 py-2 text-xs font-semibold capitalize transition-colors ${
                  provider === id
                    ? 'border-primary-500 bg-primary-50 text-primary-700 dark:border-primary-400 dark:bg-primary-500/10 dark:text-primary-300'
                    : 'border-surface-200 text-surface-700 hover:border-surface-300 dark:border-surface-700 dark:text-surface-300'
                }`}
              >
                {id}
              </button>
            ))}
          </div>
        </div>

        {provider === 'twilio' && (
          <>
            {field('sms_twilio_account_sid', 'Account SID', 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')}
            {field('sms_twilio_auth_token', 'Auth token', '', true)}
            {field('sms_twilio_from_number', 'From number', 'Your Twilio phone number in E.164 format')}
          </>
        )}
        {provider === 'telnyx' && (
          <>
            {field('sms_telnyx_api_key', 'API key', '', true)}
            {field('sms_telnyx_from_number', 'From number', 'Your Telnyx phone number in E.164 format')}
          </>
        )}
        {provider === 'bandwidth' && (
          <>
            {field('sms_bandwidth_account_id', 'Account ID')}
            {field('sms_bandwidth_username', 'Username')}
            {field('sms_bandwidth_password', 'Password', '', true)}
            {field('sms_bandwidth_application_id', 'Application ID')}
            {field('sms_bandwidth_from_number', 'From number', 'Your Bandwidth phone number in E.164 format')}
          </>
        )}
        {provider === 'plivo' && (
          <>
            {field('sms_plivo_auth_id', 'Auth ID')}
            {field('sms_plivo_auth_token', 'Auth token', '', true)}
            {field('sms_plivo_from_number', 'From number', 'Your Plivo phone number in E.164 format')}
          </>
        )}
        {provider === 'vonage' && (
          <>
            {field('sms_vonage_api_key', 'API key')}
            {field('sms_vonage_api_secret', 'API secret', '', true)}
            {field('sms_vonage_from_number', 'From number', 'Your Vonage phone number in E.164 format')}
          </>
        )}

        {!provider && (
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Pick a provider above to enter credentials.
          </p>
        )}

        <p className="text-xs text-surface-500 dark:text-surface-400">
          Auth tokens, passwords, and API secrets are encrypted at rest in your shop's database
          (AES-256-GCM). Account IDs and phone numbers are stored as plaintext.
        </p>
      </div>

      <SubStepFooter
        onCancel={onCancel}
        onComplete={onComplete}
        completeLabel="Save SMS settings"
        completeDisabled={!provider}
      />
    </div>
  );
}
