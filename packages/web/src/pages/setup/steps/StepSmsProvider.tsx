import { useState } from 'react';
import { MessageSquare, Send, CheckCircle, XCircle, Loader2 } from 'lucide-react';
import type { SubStepProps, PendingWrites } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';
import { api } from '@/api/client';

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
// Map PendingWrites fields to the credentials object expected by test-send
function buildCredentials(provider: ProviderId, pending: PendingWrites): Record<string, string> {
  if (provider === 'twilio') {
    return {
      account_sid: pending.sms_twilio_account_sid || '',
      auth_token: pending.sms_twilio_auth_token || '',
      from_number: pending.sms_twilio_from_number || '',
    };
  }
  if (provider === 'telnyx') {
    return {
      api_key: pending.sms_telnyx_api_key || '',
      from_number: pending.sms_telnyx_from_number || '',
    };
  }
  if (provider === 'bandwidth') {
    return {
      account_id: pending.sms_bandwidth_account_id || '',
      username: pending.sms_bandwidth_username || '',
      password: pending.sms_bandwidth_password || '',
      application_id: pending.sms_bandwidth_application_id || '',
      from_number: pending.sms_bandwidth_from_number || '',
    };
  }
  if (provider === 'plivo') {
    return {
      auth_id: pending.sms_plivo_auth_id || '',
      auth_token: pending.sms_plivo_auth_token || '',
      from_number: pending.sms_plivo_from_number || '',
    };
  }
  if (provider === 'vonage') {
    return {
      api_key: pending.sms_vonage_api_key || '',
      api_secret: pending.sms_vonage_api_secret || '',
      from_number: pending.sms_vonage_from_number || '',
    };
  }
  return {};
}

export function StepSmsProvider({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const [provider, setProvider] = useState<ProviderId | null>(
    (pending.sms_provider_type as ProviderId) || null,
  );
  const [testPhone, setTestPhone] = useState('');
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(null);

  const handleProvider = (id: ProviderId) => {
    setProvider(id);
    setTestResult(null);
    onUpdate({ sms_provider_type: id });
  };

  const handleTestSms = async () => {
    if (!provider || !testPhone.trim()) return;
    setTesting(true);
    setTestResult(null);
    try {
      const credentials = buildCredentials(provider, pending);
      const res = await api.post('/settings/sms/test-send', {
        provider_type: provider,
        credentials,
        to: testPhone.trim(),
        body: 'Test SMS from BizarreCRM setup wizard.',
      });
      const msg = (res?.data as { data?: { message?: string } })?.data?.message || 'Test SMS sent.';
      setTestResult({ ok: true, message: msg });
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message || 'SMS send failed.';
      setTestResult({ ok: false, message: msg });
    } finally {
      setTesting(false);
    }
  };

  const field = (key: keyof PendingWrites, label: string, placeholder?: string, sensitive = false) => (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">{label}</label>
      <input
        type={sensitive ? 'password' : 'text'}
        value={(pending[key] as string) || ''}
        onChange={(e) => { onUpdate({ [key]: e.target.value } as Partial<PendingWrites>); setTestResult(null); }}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
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

        {/* WEB-S4-010: Test SMS */}
        {provider && (
          <div className="border-t border-surface-100 pt-3 dark:border-surface-700">
            <p className="mb-2 text-xs font-medium text-surface-700 dark:text-surface-300">
              Test SMS — send a real message to verify your credentials
            </p>
            <div className="flex gap-2">
              <input
                type="tel"
                value={testPhone}
                onChange={(e) => { setTestPhone(e.target.value); setTestResult(null); }}
                placeholder="+15551234567"
                inputMode="tel"
                className="flex-1 rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
              <button
                type="button"
                onClick={handleTestSms}
                disabled={!testPhone.trim() || testing}
                className="flex shrink-0 items-center gap-2 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
              >
                {testing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                {testing ? 'Sending…' : 'Send test'}
              </button>
            </div>
            {testResult && (
              <div className={`mt-2 flex items-center gap-2 rounded-lg px-3 py-2 text-sm ${testResult.ok ? 'bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-300' : 'bg-red-50 text-red-700 dark:bg-red-500/10 dark:text-red-300'}`}>
                {testResult.ok
                  ? <CheckCircle className="h-4 w-4 shrink-0" />
                  : <XCircle className="h-4 w-4 shrink-0" />}
                <span>{testResult.message}</span>
              </div>
            )}
          </div>
        )}
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
