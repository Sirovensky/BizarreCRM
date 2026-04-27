import { useState } from 'react';
import { Mail, CheckCircle, XCircle, Loader2 } from 'lucide-react';
import type { SubStepProps, PendingWrites } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';
import { api } from '@/api/client';

/**
 * Sub-step — Email (SMTP).
 * Collects outgoing mail server credentials for customer emails (receipts,
 * notifications, portal links). smtp_pass is encrypted at rest on the server.
 *
 * WEB-S4-009 / WEB-W1-034: Test Connection button verifies SMTP connectivity
 * against POST /settings/email/test-smtp without saving credentials.
 */
export function StepEmailSmtp({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(null);

  const field = (key: keyof PendingWrites, label: string, placeholder: string, sensitive = false, type = 'text') => (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">{label}</label>
      <input
        type={sensitive ? 'password' : type}
        value={(pending[key] as string) || ''}
        onChange={(e) => { onUpdate({ [key]: e.target.value } as Partial<PendingWrites>); setTestResult(null); }}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
      />
    </div>
  );

  const canSave = !!(pending.smtp_host && pending.smtp_port && pending.smtp_from);
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
      const msg = (res?.data as { data?: { message?: string } })?.data?.message || 'SMTP connection verified.';
      setTestResult({ ok: true, message: msg });
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message || 'SMTP connection failed.';
      setTestResult({ ok: false, message: msg });
    } finally {
      setTesting(false);
    }
  };

  return (
    <div className="mx-auto max-w-xl">
      <SubStepHeader
        title="Email (SMTP)"
        subtitle="Outgoing mail server for customer emails. Common providers: SendGrid, Mailgun, Amazon SES, Gmail SMTP."
        icon={<Mail className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
      />

      <div className="space-y-4 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {field('smtp_host', 'SMTP host', 'smtp.sendgrid.net')}
        <div className="grid grid-cols-2 gap-3">
          {field('smtp_port', 'Port', '587', false, 'number')}
          {field('smtp_from', 'From address', 'shop@yourshop.com', false, 'email')}
        </div>
        {field('smtp_user', 'Username (optional)', 'apikey')}
        {field('smtp_pass', 'Password / API key', '', true)}

        <p className="text-xs text-surface-500 dark:text-surface-400">
          Tip: most providers use port 587 with STARTTLS. Password is encrypted at rest.
        </p>

        {/* WEB-S4-009: Test Connection */}
        <div className="border-t border-surface-100 pt-3 dark:border-surface-700">
          <button
            type="button"
            onClick={handleTestConnection}
            disabled={!canTest || testing}
            className="flex items-center gap-2 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
          >
            {testing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />}
            {testing ? 'Testing…' : 'Test connection'}
          </button>
          {testResult && (
            <div className={`mt-2 flex items-center gap-2 rounded-lg px-3 py-2 text-sm ${testResult.ok ? 'bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-300' : 'bg-red-50 text-red-700 dark:bg-red-500/10 dark:text-red-300'}`}>
              {testResult.ok
                ? <CheckCircle className="h-4 w-4 shrink-0" />
                : <XCircle className="h-4 w-4 shrink-0" />}
              <span>{testResult.message}</span>
            </div>
          )}
        </div>
      </div>

      <SubStepFooter
        onCancel={onCancel}
        onComplete={onComplete}
        completeLabel="Save email settings"
        completeDisabled={!canSave}
      />
    </div>
  );
}
