/**
 * StepSmsProvider — Setup wizard Step 16.
 *
 * Picks an SMS provider (Twilio / Telnyx / Bandwidth / Plivo / Vonage / None)
 * and collects the per-provider credentials. Values land on `pending` via
 * `onUpdate(...)` and are flushed to `store_config` in the wizard's bulk PUT
 * at the end (encrypted at rest by the server — AES-256-GCM).
 *
 * Linear-flow rewrite (Agent W5-18) — replaces the legacy `SubStepProps`
 * version that lived inside the deprecated Extras Hub. Mirrors the layout
 * defined by `<section id="screen-16">` in `docs/setup-wizard-preview.html`.
 *
 * "None" is a sentinel — picking it clears `sms_provider_type` and any
 * provider-specific creds so they don't leak into the bulk PUT. The owner
 * can wire SMS later from Settings → SMS & Voice (which has the richer UI
 * with 10DLC etc — this step is deliberately minimal).
 */
import { useState } from 'react';
import type { JSX } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  ArrowLeft,
  ArrowRight,
  CheckCircle,
  Loader2,
  Send,
  XCircle,
} from 'lucide-react';
import type { PendingWrites, StepProps } from '../wizardTypes';
import { api } from '@/api/client';

type ProviderId = 'bizarresms' | 'twilio' | 'telnyx' | 'bandwidth' | 'plivo' | 'vonage';
type Choice = ProviderId | 'none';

type ProviderVisibility = 'enabled' | 'tease' | 'hidden';

interface ProviderEntry {
  id: Choice;
  label: string;
  /** Resolves visibility per (isMultiTenant, tier) context.
   *    enabled — selectable, normal rendering
   *    tease   — visible but disabled, "Upgrade to Pro" pill, click opens billing
   *    hidden  — not rendered at all
   *  Defaults to always-`enabled`. Used to gate bizarresms.
   */
  visibility?: (ctx: { isMultiTenant: boolean; tier: string | null }) => ProviderVisibility;
  /** When true the entry gets a "Recommended" pill + becomes the default
   *  selection if the user hasn't picked something else. Only meaningful
   *  when the entry is currently `enabled`. */
  recommended?: boolean;
}

// PROVIDER VISIBILITY RULES (per memory project_communications.md):
//
//   - bizarresms — DEFAULT recommended for hosted-tier paid shops (Pro,
//     Pro+, or active 14-day trial). Hosted-tier free shops see it as a
//     TEASE — disabled card with "Upgrade to Pro" CTA — so they discover
//     the value-add without being able to silently opt into a non-billed
//     relay. Self-host shops never see it at all (irrelevant; their
//     traffic doesn't route through Bizarre's infrastructure).
//
//   - twilio — fallback default for self-host shops + any hosted shop
//     who wants BYO creds. Always enabled.
//
//   - telnyx / bandwidth / plivo / vonage — alternative BYO creds
//     for shops with existing vendor relationships. Always enabled.
//     Don't expand this list further without adoption evidence — each
//     adapter's webhook auth differs and is real maintenance cost.
//
//   - none — sentinel; clears sms_provider_type so SMS stays disabled
//     until the shop comes back to Settings.
const PAID_TIERS = new Set(['trial', 'pro', 'pro_plus']);
function bizarresmsVisibility(ctx: { isMultiTenant: boolean; tier: string | null }): ProviderVisibility {
  if (!ctx.isMultiTenant) return 'hidden';
  if (ctx.tier && PAID_TIERS.has(ctx.tier)) return 'enabled';
  return 'tease';
}

const PROVIDERS: ReadonlyArray<ProviderEntry> = [
  { id: 'bizarresms', label: 'BizarreSMS', recommended: true, visibility: bizarresmsVisibility },
  { id: 'twilio', label: 'Twilio' },
  { id: 'telnyx', label: 'Telnyx' },
  { id: 'bandwidth', label: 'Bandwidth' },
  { id: 'plivo', label: 'Plivo' },
  { id: 'vonage', label: 'Vonage' },
  { id: 'none', label: 'None' },
];

/** Credential payload sent to `/settings/sms/test-send`. */
function buildCredentials(
  provider: ProviderId,
  pending: PendingWrites,
): Record<string, string> {
  switch (provider) {
    case 'bizarresms':
      // No credentials — relay through hosted infrastructure. Auth uses the
      // tenant's existing JWT; the upstream Bizarre Twilio account is
      // platform-owned. Empty payload is intentional.
      return {};
    case 'twilio':
      return {
        account_sid: pending.sms_twilio_account_sid || '',
        auth_token: pending.sms_twilio_auth_token || '',
        from_number: pending.sms_twilio_from_number || '',
      };
    case 'telnyx':
      return {
        api_key: pending.sms_telnyx_api_key || '',
        from_number: pending.sms_telnyx_from_number || '',
      };
    case 'bandwidth':
      return {
        account_id: pending.sms_bandwidth_account_id || '',
        username: pending.sms_bandwidth_username || '',
        password: pending.sms_bandwidth_password || '',
        application_id: pending.sms_bandwidth_application_id || '',
        from_number: pending.sms_bandwidth_from_number || '',
      };
    case 'plivo':
      return {
        auth_id: pending.sms_plivo_auth_id || '',
        auth_token: pending.sms_plivo_auth_token || '',
        from_number: pending.sms_plivo_from_number || '',
      };
    case 'vonage':
      return {
        api_key: pending.sms_vonage_api_key || '',
        api_secret: pending.sms_vonage_api_secret || '',
        from_number: pending.sms_vonage_from_number || '',
      };
  }
}

export function StepSmsProvider({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  // Tenancy + tier context for provider visibility rules. isMultiTenant
  // comes from authApi.setupStatus(); tier comes from store_config — Agent
  // 31's signup route writes 'trial' on tenant creation, billing flow
  // updates it later. Both queries use react-query so this component just
  // reads cached values without spawning new requests on every render.
  const setupStatus = useQuery({
    queryKey: ['auth-setup-status'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: { needsSetup: boolean; isMultiTenant: boolean } }>(
        '/auth/setup-status',
      );
      return res.data;
    },
    staleTime: 60_000,
  });
  const isMultiTenant = Boolean(setupStatus.data?.data?.isMultiTenant);
  const tier = (pending.tier as string | undefined) ?? null;
  const visibilityCtx = { isMultiTenant, tier };

  // Resolve each PROVIDERS entry to one of: enabled / tease / hidden, then
  // drop hidden ones. This is the rendering source-of-truth.
  const visibleProviders = PROVIDERS.map((p) => ({
    ...p,
    visState: (p.visibility ?? (() => 'enabled' as ProviderVisibility))(visibilityCtx),
  })).filter((p) => p.visState !== 'hidden');

  // Pick the default selection: persisted value if any → first 'enabled'
  // entry marked recommended → 'none'.
  const initial: Choice = (() => {
    const persisted = pending.sms_provider_type as Choice | undefined;
    if (persisted) return persisted;
    const recommendedEnabled = visibleProviders.find(
      (p) => p.recommended && p.visState === 'enabled',
    );
    if (recommendedEnabled) return recommendedEnabled.id;
    return 'none';
  })();
  const [choice, setChoice] = useState<Choice>(initial);
  const [testPhone, setTestPhone] = useState('');
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(
    null,
  );

  const handleProvider = (id: Choice) => {
    setChoice(id);
    setTestResult(null);
    if (id === 'none') {
      // Clear the provider key so the bulk PUT doesn't carry stale state.
      onUpdate({ sms_provider_type: undefined });
    } else {
      onUpdate({ sms_provider_type: id });
    }
  };

  const handleField = (key: keyof PendingWrites, value: string) => {
    onUpdate({ [key]: value } as Partial<PendingWrites>);
    setTestResult(null);
  };

  const handleTestSms = async () => {
    if (choice === 'none' || !testPhone.trim()) return;
    setTesting(true);
    setTestResult(null);
    try {
      const credentials = buildCredentials(choice, pending);
      const res = await api.post('/settings/sms/test-send', {
        provider_type: choice,
        credentials,
        to: testPhone.trim(),
        body: 'Test SMS from BizarreCRM setup wizard.',
      });
      const msg =
        (res?.data as { data?: { message?: string } })?.data?.message ||
        'Test SMS sent.';
      setTestResult({ ok: true, message: msg });
    } catch (err: unknown) {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data
          ?.message || 'SMS send failed.';
      setTestResult({ ok: false, message: msg });
    } finally {
      setTesting(false);
    }
  };

  const handleSkip = () => {
    if (onSkip) onSkip();
    else onNext();
  };

  const renderField = (
    key: keyof PendingWrites,
    label: string,
    placeholder?: string,
    sensitive = false,
  ) => (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
        {label}
      </label>
      <input
        type={sensitive ? 'password' : 'text'}
        value={(pending[key] as string | undefined) || ''}
        onChange={(e) => handleField(key, e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
      />
    </div>
  );

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          SMS provider
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          For appointment reminders, ticket updates, and marketing. You can
          change this later in Settings.
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {/* Provider picker */}
        <div>
          <label className="mb-2 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Provider
          </label>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-7">
            {visibleProviders.map(({ id, label, visState, recommended }) => {
              const selected = choice === id;
              const teasing = visState === 'tease';
              if (teasing) {
                // Free-tier hosted shop: BizarreSMS is locked. Render as a
                // disabled card with an "Upgrade to Pro" pill so the user
                // discovers the value-add. Click routes to billing.
                return (
                  <button
                    key={id}
                    type="button"
                    onClick={() => {
                      window.location.href = '/settings?tab=billing';
                    }}
                    aria-disabled="true"
                    title="Upgrade to a paid plan to use BizarreSMS"
                    className="relative cursor-pointer rounded-xl border-2 border-dashed border-surface-300 bg-surface-50 px-3 py-3 text-xs font-medium text-surface-500 transition-colors hover:border-primary-400 hover:bg-primary-50/40 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-400 dark:hover:border-primary-500/40 dark:hover:bg-primary-500/5"
                  >
                    <span className="opacity-70">{label}</span>
                    <span className="ml-1 inline-flex rounded-full bg-amber-100 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-amber-900 dark:bg-amber-900/40 dark:text-amber-200">
                      Pro
                    </span>
                  </button>
                );
              }
              return (
                <button
                  key={id}
                  type="button"
                  onClick={() => handleProvider(id)}
                  aria-pressed={selected}
                  className={
                    selected
                      ? 'relative rounded-xl border-2 border-primary-500 bg-primary-50 px-3 py-3 text-xs font-semibold text-primary-700 transition-colors dark:border-primary-400 dark:bg-primary-500/10 dark:text-primary-300'
                      : 'relative rounded-xl border-2 border-surface-200 px-3 py-3 text-xs font-medium text-surface-700 transition-colors hover:border-surface-300 dark:border-surface-700 dark:text-surface-300 dark:hover:border-surface-600'
                  }
                >
                  {label}
                  {recommended && (
                    <span className="ml-1 inline-flex rounded-full bg-primary-500 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-primary-950">
                      Default
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Per-provider credential fields */}
        {choice === 'bizarresms' && (
          <div className="rounded-xl border border-primary-300 bg-primary-50 p-4 text-sm text-primary-900 dark:border-primary-500/30 dark:bg-primary-900/20 dark:text-primary-200">
            <p className="font-semibold">No credentials needed.</p>
            <p className="mt-1 text-xs leading-relaxed">
              BizarreSMS routes through your hosted plan's SMS allotment.
              Outbound segments count against your monthly cap; inbound is
              free. Per-tenant sender ID + spam-reputation isolation are
              handled platform-side. View usage in Settings → Billing.
            </p>
          </div>
        )}
        {choice === 'twilio' && (
          <div className="space-y-4">
            <p className="text-xs text-surface-500 dark:text-surface-400">
              Find your Account SID and Auth Token in the Twilio Console.
            </p>
            {renderField('sms_twilio_account_sid', 'Account SID', 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')}
            {renderField('sms_twilio_auth_token', 'Auth token', '', true)}
            {renderField('sms_twilio_from_number', 'From number (E.164)', '+15552341090')}
          </div>
        )}
        {choice === 'telnyx' && (
          <div className="space-y-4">
            {renderField('sms_telnyx_api_key', 'API key', '', true)}
            {renderField('sms_telnyx_from_number', 'From number (E.164)', '+15552341090')}
          </div>
        )}
        {choice === 'bandwidth' && (
          <div className="space-y-4">
            {renderField('sms_bandwidth_account_id', 'Account ID')}
            {renderField('sms_bandwidth_username', 'Username')}
            {renderField('sms_bandwidth_password', 'Password', '', true)}
            {renderField('sms_bandwidth_application_id', 'Application ID')}
            {renderField('sms_bandwidth_from_number', 'From number (E.164)', '+15552341090')}
          </div>
        )}
        {choice === 'plivo' && (
          <div className="space-y-4">
            {renderField('sms_plivo_auth_id', 'Auth ID')}
            {renderField('sms_plivo_auth_token', 'Auth token', '', true)}
            {renderField('sms_plivo_from_number', 'From number (E.164)', '+15552341090')}
          </div>
        )}
        {choice === 'vonage' && (
          <div className="space-y-4">
            {renderField('sms_vonage_api_key', 'API key')}
            {renderField('sms_vonage_api_secret', 'API secret', '', true)}
            {renderField('sms_vonage_from_number', 'From number (E.164)', '+15552341090')}
          </div>
        )}

        {choice === 'none' && (
          <p className="rounded-xl bg-surface-50 p-4 text-sm text-surface-600 dark:bg-surface-700/30 dark:text-surface-300">
            SMS will stay disabled. Continue without configuring — you can wire
            a provider later in Settings &rarr; SMS &amp; Voice.
          </p>
        )}

        {choice !== 'none' && (
          <p className="text-xs text-surface-500 dark:text-surface-400">
            Auth tokens, passwords, and API secrets are encrypted at rest in
            your shop's database (AES-256-GCM). Account IDs and phone numbers
            are stored as plaintext.
          </p>
        )}

        {/* Test SMS — only when a real provider is picked */}
        {choice !== 'none' && (
          <div className="border-t border-surface-100 pt-4 dark:border-surface-700">
            <p className="mb-2 text-xs font-medium text-surface-700 dark:text-surface-300">
              Test SMS — send a real message to verify your credentials.
            </p>
            <div className="flex gap-2">
              <input
                type="tel"
                value={testPhone}
                onChange={(e) => {
                  setTestPhone(e.target.value);
                  setTestResult(null);
                }}
                placeholder="+15551234567"
                inputMode="tel"
                className="flex-1 rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
              <button
                type="button"
                onClick={handleTestSms}
                disabled={!testPhone.trim() || testing}
                className="flex shrink-0 items-center gap-2 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
              >
                {testing ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Send className="h-4 w-4" />
                )}
                {testing ? 'Sending…' : 'Send test'}
              </button>
            </div>
            {testResult && (
              <div
                className={
                  testResult.ok
                    ? 'mt-2 flex items-center gap-2 rounded-lg bg-green-50 px-3 py-2 text-sm text-green-700 dark:bg-green-500/10 dark:text-green-300'
                    : 'mt-2 flex items-center gap-2 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-300'
                }
              >
                {testResult.ok ? (
                  <CheckCircle className="h-4 w-4 shrink-0" />
                ) : (
                  <XCircle className="h-4 w-4 shrink-0" />
                )}
                <span>{testResult.message}</span>
              </div>
            )}
            <p className="mt-3 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 dark:border-blue-700 dark:bg-blue-900/20 dark:text-blue-300">
              Self-host tip: to receive inbound SMS replies, expose the webhook
              via Tailscale Funnel or your router's port-forward.
            </p>
          </div>
        )}

        {/* Footer — Back / Skip / Continue */}
        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip — no SMS yet
            </button>
            <button
              type="button"
              onClick={onNext}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400"
            >
              Continue
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepSmsProvider;
