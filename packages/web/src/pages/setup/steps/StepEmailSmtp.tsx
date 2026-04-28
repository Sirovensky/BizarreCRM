import { useState } from 'react';
import type { JSX } from 'react';
import { Mail, CheckCircle, XCircle, Loader2, ArrowLeft, ArrowRight } from 'lucide-react';
import type { StepProps, PendingWrites } from '../wizardTypes';
import { api } from '@/api/client';

/**
 * Step 17 — Email (SMTP).
 *
 * Mirrors `#screen-17` in `docs/setup-wizard-preview.html`. Collects outgoing
 * mail server credentials for customer emails (receipts, notifications, portal
 * links). `smtp_pass` is encrypted at rest on the server.
 *
 * Linear-flow rewrite (H1): converted from legacy `SubStepProps` (hub-mode)
 * to `StepProps` so the shell drives Back / Continue / Skip transitions.
 * Form fields, "Test connection" button, and validation rules unchanged.
 *
 * Persists 5 keys via `onUpdate` on every change:
 *   smtp_host, smtp_port, smtp_user, smtp_pass, smtp_from
 *
 * The shell flushes the bundle in a single PUT /settings/config at the end
 * of the wizard. "Test connection" hits POST /settings/email/test-smtp without
 * saving (WEB-S4-009 / WEB-W1-034).
 */
export function StepEmailSmtp({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(null);

  const field = (
    key: keyof PendingWrites,
    label: string,
    placeholder: string,
    sensitive = false,
    type = 'text',
  ) => (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
        {label}
      </label>
      <input
        type={sensitive ? 'password' : type}
        value={(pending[key] as string) || ''}
        onChange={(e) => {
          onUpdate({ [key]: e.target.value } as Partial<PendingWrites>);
          setTestResult(null);
        }}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
      />
    </div>
  );

  const canTest = !!(pending.smtp_host && pending.smtp_port);

  const handleTestConnection = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await api.post('/settings/email/test-smtp', {
        host: pending.smtp_host,
        port: pending.smtp_port,
        user: pending.smtp_user,
        pass: pending.smtp_pass,
      });
      const msg =
        (res?.data as { data?: { message?: string } })?.data?.message ||
        'SMTP connection verified.';
      setTestResult({ ok: true, message: msg });
    } catch (err: unknown) {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ||
        'SMTP connection failed.';
      setTestResult({ ok: false, message: msg });
    } finally {
      setTesting(false);
    }
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  return (
    <div className="mx-auto max-w-xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-primary-100 dark:bg-primary-500/10">
          <Mail className="h-6 w-6 text-primary-700 dark:text-primary-300" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Email (SMTP)
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          For invoices, receipts, password resets. Common providers: SendGrid, Mailgun, Amazon SES, Gmail SMTP.
        </p>
      </div>

      <div className="space-y-4 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <p className="text-xs text-surface-500 dark:text-surface-400">
          Tip: Gmail requires an{' '}
          <a
            href="https://support.google.com/accounts/answer/185833"
            target="_blank"
            rel="noopener noreferrer"
            className="text-primary-700 underline hover:text-primary-800 dark:text-primary-300"
          >
            app password
          </a>
          . Most providers use port 587 with STARTTLS.
        </p>

        <div className="grid grid-cols-2 gap-3">
          {field('smtp_host', 'Host', 'smtp.gmail.com')}
          {field('smtp_port', 'Port', '587', false, 'number')}
        </div>
        {field('smtp_user', 'Username', 'invoices@yourshop.com')}
        {field('smtp_pass', 'Password / app password', '', true)}
        {field('smtp_from', 'From address', 'shop@yourshop.com', false, 'email')}

        <p className="text-xs text-surface-500 dark:text-surface-400">
          Password is encrypted at rest.
        </p>

        {/* WEB-S4-009: Test Connection */}
        <div className="border-t border-surface-100 pt-3 dark:border-surface-700">
          <button
            type="button"
            onClick={handleTestConnection}
            disabled={!canTest || testing}
            className="flex items-center gap-2 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:pointer-events-none disabled:opacity-50 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
          >
            {testing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />}
            {testing ? 'Testing…' : 'Test connection'}
          </button>
          {testResult && (
            <div
              className={`mt-2 flex items-center gap-2 rounded-lg px-3 py-2 text-sm ${
                testResult.ok
                  ? 'bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-300'
                  : 'bg-red-50 text-red-700 dark:bg-red-500/10 dark:text-red-300'
              }`}
            >
              {testResult.ok ? (
                <CheckCircle className="h-4 w-4 shrink-0" />
              ) : (
                <XCircle className="h-4 w-4 shrink-0" />
              )}
              <span>{testResult.message}</span>
            </div>
          )}
        </div>
      </div>

      <div className="mt-6 flex items-center justify-between gap-3">
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
            Skip
          </button>
          <button
            type="button"
            onClick={onNext}
            className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
          >
            <ArrowRight className="h-4 w-4" />
            Continue
          </button>
        </div>
      </div>
    </div>
  );
}

export default StepEmailSmtp;
