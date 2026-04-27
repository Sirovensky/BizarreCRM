import { Mail } from 'lucide-react';
import type { SubStepProps, PendingWrites } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';

/**
 * Sub-step — Email (SMTP).
 * Collects outgoing mail server credentials for customer emails (receipts,
 * notifications, portal links). smtp_pass is encrypted at rest on the server.
 */
export function StepEmailSmtp({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const field = (key: keyof PendingWrites, label: string, placeholder: string, sensitive = false, type = 'text') => (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">{label}</label>
      <input
        type={sensitive ? 'password' : type}
        value={(pending[key] as string) || ''}
        onChange={(e) => onUpdate({ [key]: e.target.value } as Partial<PendingWrites>)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
      />
    </div>
  );

  const canSave = !!(pending.smtp_host && pending.smtp_port && pending.smtp_from);

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
