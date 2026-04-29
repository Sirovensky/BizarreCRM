import { useRef, useState } from 'react';
import type { JSX } from 'react';
import { Inbox, PackageCheck, Receipt, Send, Code, ArrowLeft, ArrowRight } from 'lucide-react';
import toast from 'react-hot-toast';
import type { StepProps, PendingWrites } from '../wizardTypes';

/**
 * Step 18 — Notification templates.
 *
 * Mirrors `#screen-18` in `docs/setup-wizard-preview.html`. Owner reviews and
 * tweaks the three default customer-facing message templates the CRM fires on
 * common ticket events:
 *
 *   1. Ticket received  — auto-ack when a ticket is created.
 *   2. Ticket ready     — sent when a ticket flips to ready-for-pickup.
 *   3. Invoice paid     — receipt confirmation after a successful payment.
 *
 * Each template has a subject and body; bodies use `{curly_brace}` variable
 * tokens that the notification service substitutes at send time. The variable
 * cheatsheet inserts a token at the textarea cursor on click.
 *
 * Persists 6 keys via `onUpdate` on every change. The shell's bulk
 * PUT /settings/config flushes them at the end of the wizard.
 *
 * "Send test" is a stub for now — actual SMS/email send wires up once
 * the SMS provider (Step 16) and SMTP (Step 17) are configured.
 */

type TemplateKey =
  | 'received'
  | 'ready'
  | 'invoice_paid'
  | 'appt_reminder';

interface TemplateDef {
  key: TemplateKey;
  title: string;
  description: string;
  Icon: typeof Inbox;
  enabledKey: keyof PendingWrites;
  subjKey: keyof PendingWrites;
  bodyKey: keyof PendingWrites;
  /** '1' → enabled by default; '0' → disabled by default. Owner can flip
   *  the per-template toggle before flush. */
  defaultEnabled: '1' | '0';
  defaultSubj: string;
  defaultBody: string;
}

const TEMPLATES: ReadonlyArray<TemplateDef> = [
  {
    key: 'received',
    title: 'Ticket received',
    description: 'Auto-ack when a new repair ticket is created.',
    Icon: Inbox,
    enabledKey: 'notif_tpl_received_enabled',
    subjKey: 'notif_tpl_received_subj',
    bodyKey: 'notif_tpl_received_body',
    defaultEnabled: '1',
    defaultSubj: 'We got your repair ticket #{ticket_id}',
    defaultBody:
      "Hi {customer_name}, we received your {device} for repair. We'll update you when there's news.\n\n{shop_name}",
  },
  {
    key: 'ready',
    title: 'Ticket ready for pickup',
    description: 'Sent when a ticket flips to ready-for-pickup.',
    Icon: PackageCheck,
    enabledKey: 'notif_tpl_ready_enabled',
    subjKey: 'notif_tpl_ready_subj',
    bodyKey: 'notif_tpl_ready_body',
    defaultEnabled: '1',
    defaultSubj: 'Your repair is ready — ticket #{ticket_id}',
    defaultBody:
      'Hi {customer_name}, your {device} is ready for pickup. Total: {total}.\n\n{shop_name}\n{shop_address}',
  },
  {
    key: 'invoice_paid',
    title: 'Invoice paid',
    description: 'Receipt confirmation after a successful payment.',
    Icon: Receipt,
    enabledKey: 'notif_tpl_invoice_paid_enabled',
    subjKey: 'notif_tpl_invoice_paid_subj',
    bodyKey: 'notif_tpl_invoice_paid_body',
    defaultEnabled: '1',
    defaultSubj: 'Receipt from {shop_name} — invoice #{invoice_id}',
    defaultBody:
      'Thanks {customer_name}! Payment of {total} received. Receipt: {receipt_link}.\n\n{shop_name}',
  },
  {
    key: 'appt_reminder',
    title: 'Appointment reminder',
    description: '24h before a booked appointment. Off by default — turn on if you take bookings.',
    Icon: PackageCheck,
    enabledKey: 'notif_tpl_appt_reminder_enabled',
    subjKey: 'notif_tpl_appt_reminder_subj',
    bodyKey: 'notif_tpl_appt_reminder_body',
    defaultEnabled: '0',
    defaultSubj: 'Reminder: {service} appointment tomorrow at {shop_name}',
    defaultBody:
      'Hi {customer_name}, reminder: {service} appt at {shop_name} tomorrow at {time}. Reply C to cancel.\n\n{shop_address}',
  },
];

const VARIABLES: ReadonlyArray<string> = [
  'customer_name',
  'ticket_id',
  'device',
  'total',
  'shop_name',
  'shop_address',
  'invoice_id',
  'receipt_link',
];

export function StepNotificationTemplates({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  // Keep refs to each template's textarea so we can insert variables at the
  // current cursor position. Keys match the TemplateDef.key for lookup.
  const textareaRefs = useRef<Record<TemplateKey, HTMLTextAreaElement | null>>({
    received: null,
    ready: null,
    invoice_paid: null,
    appt_reminder: null,
  });

  // Per-card cheatsheet expanded state — defaults to collapsed to keep the
  // page tidy on first render. Owner clicks "Show variables" to expand.
  const [expandedCheatsheet, setExpandedCheatsheet] = useState<Record<TemplateKey, boolean>>({
    received: false,
    ready: false,
    invoice_paid: false,
    appt_reminder: false,
  });

  const getValue = (key: keyof PendingWrites, fallback: string): string => {
    const v = pending[key];
    return typeof v === 'string' ? v : fallback;
  };

  const handleSubjChange = (subjKey: keyof PendingWrites, value: string) => {
    onUpdate({ [subjKey]: value } as Partial<PendingWrites>);
  };

  const handleBodyChange = (bodyKey: keyof PendingWrites, value: string) => {
    onUpdate({ [bodyKey]: value } as Partial<PendingWrites>);
  };

  const insertVariable = (
    tplKey: TemplateKey,
    bodyKey: keyof PendingWrites,
    currentValue: string,
    variable: string,
  ) => {
    const token = `{${variable}}`;
    const ta = textareaRefs.current[tplKey];

    if (ta) {
      const start = ta.selectionStart ?? currentValue.length;
      const end = ta.selectionEnd ?? currentValue.length;
      const next = currentValue.slice(0, start) + token + currentValue.slice(end);
      onUpdate({ [bodyKey]: next } as Partial<PendingWrites>);
      // Restore cursor just after the inserted token on next paint.
      requestAnimationFrame(() => {
        ta.focus();
        const pos = start + token.length;
        ta.setSelectionRange(pos, pos);
      });
      return;
    }

    // Fallback — append at the end if we can't find the textarea node.
    onUpdate({ [bodyKey]: currentValue + token } as Partial<PendingWrites>);
  };

  const handleSendTest = () => {
    toast('Test send will be wired once SMS + SMTP are configured.', { icon: 'i' });
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const toggleCheatsheet = (key: TemplateKey) => {
    setExpandedCheatsheet((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Customer notifications
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          4 events covered. Toggle off any you don't want firing. Variables in
          {' '}
          <span className="font-mono text-xs">{'{curly_braces}'}</span>
          {' '}
          auto-fill at send time.
        </p>
      </div>

      {TEMPLATES.map((tpl) => {
        const subjValue = getValue(tpl.subjKey, tpl.defaultSubj);
        const bodyValue = getValue(tpl.bodyKey, tpl.defaultBody);
        const isExpanded = expandedCheatsheet[tpl.key];
        const Icon = tpl.Icon;
        // Per-template enabled state. If the owner hasn't touched it yet,
        // fall back to the template's `defaultEnabled` (most lifecycle
        // events default '1', appt-reminder defaults '0' since not every
        // shop takes bookings).
        const enabledRaw = pending[tpl.enabledKey] as '1' | '0' | undefined;
        const enabled = (enabledRaw ?? tpl.defaultEnabled) === '1';

        return (
          <div
            key={tpl.key}
            className={`bg-white dark:bg-surface-800 rounded-xl border p-6 mb-4 transition-opacity ${
              enabled
                ? 'border-surface-200 dark:border-surface-700'
                : 'border-surface-200 dark:border-surface-700 opacity-60'
            }`}
          >
            <div className="mb-4 flex items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary-100 text-primary-700 dark:bg-primary-500/10 dark:text-primary-300">
                <Icon className="h-5 w-5" />
              </div>
              <div className="flex-1">
                <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100">
                  {tpl.title}
                </h3>
                <p className="text-xs text-surface-500 dark:text-surface-400">{tpl.description}</p>
              </div>
              {/* Enabled toggle — pill switch identical to other steps. When
                  off, the template is dimmed so the owner sees its content
                  but knows the system won't fire it. */}
              <label className="flex shrink-0 cursor-pointer items-center gap-2">
                <span className="text-xs font-medium text-surface-600 dark:text-surface-300">
                  {enabled ? 'Enabled' : 'Disabled'}
                </span>
                <span
                  className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors ${
                    enabled ? 'bg-primary-500' : 'bg-surface-300 dark:bg-surface-600'
                  }`}
                  role="switch"
                  aria-checked={enabled}
                  onClick={() =>
                    onUpdate({ [tpl.enabledKey]: enabled ? '0' : '1' } as Partial<PendingWrites>)
                  }
                >
                  <span
                    className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${
                      enabled ? 'translate-x-5' : 'translate-x-0.5'
                    }`}
                  />
                </span>
                <input
                  type="checkbox"
                  className="sr-only"
                  checked={enabled}
                  onChange={(e) =>
                    onUpdate({ [tpl.enabledKey]: e.target.checked ? '1' : '0' } as Partial<PendingWrites>)
                  }
                />
              </label>
            </div>

            <div className="space-y-3">
              <div>
                <label
                  htmlFor={`tpl-subj-${tpl.key}`}
                  className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300"
                >
                  Subject
                </label>
                <input
                  id={`tpl-subj-${tpl.key}`}
                  type="text"
                  value={subjValue}
                  onChange={(e) => handleSubjChange(tpl.subjKey, e.target.value)}
                  className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
                />
              </div>

              <div>
                <label
                  htmlFor={`tpl-body-${tpl.key}`}
                  className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300"
                >
                  Body
                </label>
                <textarea
                  id={`tpl-body-${tpl.key}`}
                  ref={(el) => { textareaRefs.current[tpl.key] = el; }}
                  value={bodyValue}
                  onChange={(e) => handleBodyChange(tpl.bodyKey, e.target.value)}
                  rows={8}
                  className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 font-mono text-xs text-surface-900 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100"
                />
              </div>

              {/* Variable cheatsheet — collapsible. Click chip to insert. */}
              <div>
                <button
                  type="button"
                  onClick={() => toggleCheatsheet(tpl.key)}
                  className="inline-flex items-center gap-1 text-xs font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
                  aria-expanded={isExpanded}
                  aria-controls={`tpl-cheatsheet-${tpl.key}`}
                >
                  <Code className="h-3.5 w-3.5" />
                  {isExpanded ? 'Hide variables' : 'Show variables'}
                </button>
                {isExpanded ? (
                  <div
                    id={`tpl-cheatsheet-${tpl.key}`}
                    className="mt-2 rounded-lg border border-surface-200 bg-surface-50 p-3 dark:border-surface-700 dark:bg-surface-900/40"
                  >
                    <p className="mb-2 text-[11px] text-surface-500 dark:text-surface-400">
                      Click a variable to insert it at the cursor.
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {VARIABLES.map((v) => (
                        <button
                          key={v}
                          type="button"
                          onClick={() => insertVariable(tpl.key, tpl.bodyKey, bodyValue, v)}
                          className="inline-flex bg-primary-100 dark:bg-primary-500/10 text-primary-900 dark:text-primary-300 px-2 py-1 rounded text-xs font-mono cursor-pointer hover:bg-primary-200"
                        >
                          {`{${v}}`}
                        </button>
                      ))}
                    </div>
                  </div>
                ) : null}
              </div>

              <div className="flex items-center gap-3 border-t border-surface-100 pt-3 dark:border-surface-700">
                <button
                  type="button"
                  onClick={handleSendTest}
                  className="inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-3 py-2 text-xs font-semibold text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
                >
                  <Send className="h-3.5 w-3.5" />
                  Send test
                </button>
                <span className="text-[11px] text-surface-500 dark:text-surface-400">
                  Splits between SMS / email — wired once providers are configured.
                </span>
              </div>
            </div>
          </div>
        );
      })}

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
            className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400"
          >
            Continue
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

export default StepNotificationTemplates;
