import { useState, useMemo } from 'react';
import { X, CalendarClock, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

/**
 * Scheduled send modal — audit §51 preamble.
 *
 * The sms_messages table already has a `send_at` column (migration 049) but
 * no UI exposes it. This modal wraps smsApi.sendScheduled so users can set
 * a date/time before dispatching. Snooze presets cover the common cases.
 *
 * No background worker required: sms.routes.ts already polls the send_at
 * column and dispatches ready messages.
 */

interface ScheduledSendModalProps {
  open: boolean;
  onClose: () => void;
  onScheduled?: () => void;
  /** Phone number and draft body from the compose area */
  toPhone: string;
  body: string;
}

function toLocalIsoInput(d: Date): string {
  // datetime-local expects "YYYY-MM-DDTHH:mm" in local time (no TZ suffix).
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function addMinutes(mins: number): Date {
  return new Date(Date.now() + mins * 60_000);
}

export function ScheduledSendModal({
  open,
  onClose,
  onScheduled,
  toPhone,
  body,
}: ScheduledSendModalProps) {
  const defaultWhen = useMemo(() => toLocalIsoInput(addMinutes(60)), []);
  const [when, setWhen] = useState(defaultWhen);
  const [sending, setSending] = useState(false);

  const presets: { label: string; mins: number }[] = [
    { label: 'In 1 hour', mins: 60 },
    { label: 'In 4 hours', mins: 240 },
    { label: 'Tomorrow 9am', mins: -1 }, // special case
  ];

  const pickPreset = (p: { label: string; mins: number }) => {
    if (p.mins >= 0) {
      setWhen(toLocalIsoInput(addMinutes(p.mins)));
      return;
    }
    // Tomorrow 9am (local)
    const d = new Date();
    d.setDate(d.getDate() + 1);
    d.setHours(9, 0, 0, 0);
    setWhen(toLocalIsoInput(d));
  };

  async function submit() {
    if (!body.trim() || !toPhone) {
      toast.error('Phone and message are required');
      return;
    }
    const target = new Date(when);
    if (isNaN(target.getTime()) || target.getTime() <= Date.now()) {
      toast.error('Scheduled time must be in the future');
      return;
    }
    setSending(true);
    try {
      await smsApi.send({
        to: toPhone,
        message: body,
        send_at: target.toISOString(),
      } as any);
      toast.success(`Scheduled for ${target.toLocaleString()}`);
      onScheduled?.();
      onClose();
    } catch (e: any) {
      toast.error(e?.response?.data?.error || 'Failed to schedule');
    } finally {
      setSending(false);
    }
  }

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <h3 className="flex items-center gap-2 text-base font-semibold text-surface-900 dark:text-surface-100">
            <CalendarClock className="h-4 w-4 text-amber-500" />
            Schedule Send
          </h3>
          <button onClick={onClose} aria-label="Close">
            <X className="h-5 w-5 text-surface-500" />
          </button>
        </div>
        <div className="space-y-3 p-4">
          <div className="flex flex-wrap gap-1">
            {presets.map((p) => (
              <button
                key={p.label}
                onClick={() => pickPreset(p)}
                className="rounded-full border border-surface-200 px-2 py-0.5 text-[11px] text-surface-600 hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:text-surface-400"
              >
                {p.label}
              </button>
            ))}
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300">
              Send at
            </label>
            <input
              type="datetime-local"
              value={when}
              onChange={(e) => setWhen(e.target.value)}
              className="w-full rounded-lg border border-surface-300 bg-white px-2 py-1.5 text-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
          <div className="rounded-lg border border-surface-200 bg-surface-50 p-2 text-[11px] text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-400">
            <div className="font-medium">To: {toPhone || '—'}</div>
            <div className={cn('mt-1 whitespace-pre-wrap', !body && 'italic text-surface-400')}>
              {body || '(message empty)'}
            </div>
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t border-surface-200 px-4 py-3 dark:border-surface-700">
          <button
            onClick={onClose}
            className="rounded-lg px-3 py-1.5 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Cancel
          </button>
          <button
            onClick={submit}
            disabled={sending || !body.trim() || !toPhone}
            className="inline-flex items-center gap-1 rounded-lg bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50"
          >
            <Send className="h-3.5 w-3.5" />
            {sending ? 'Scheduling…' : 'Schedule'}
          </button>
        </div>
      </div>
    </div>
  );
}
