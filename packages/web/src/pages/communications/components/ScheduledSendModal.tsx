import { useEffect, useState, useMemo, type RefObject } from 'react';
import { X, CalendarClock, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { useFocusTrap } from '@/hooks/useFocusTrap';

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
  const dialogRef = useFocusTrap(open);

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

  // WEB-UIUX-696: detect DST spring-forward "lost hour". `new Date(when)` is
  // permissive — picking 02:30 on a transition Sunday silently rolls to
  // 03:30. Detect by comparing the components we asked for to the components
  // the Date actually represents.
  function dstAnomaly(s: string, d: Date): 'nonexistent' | null {
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(s);
    if (!m) return null;
    const wantY = Number(m[1]), wantMo = Number(m[2]) - 1, wantD = Number(m[3]);
    const wantH = Number(m[4]), wantMi = Number(m[5]);
    if (
      d.getFullYear() !== wantY ||
      d.getMonth() !== wantMo ||
      d.getDate() !== wantD ||
      d.getHours() !== wantH ||
      d.getMinutes() !== wantMi
    ) {
      return 'nonexistent';
    }
    return null;
  }

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
    if (dstAnomaly(when, target) === 'nonexistent') {
      toast.error('That local time does not exist on the selected date (daylight-saving spring forward). Pick a different time.');
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

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="scheduled-send-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        ref={dialogRef as RefObject<HTMLDivElement>}
        className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <h3 id="scheduled-send-title" className="flex items-center gap-2 text-base font-semibold text-surface-900 dark:text-surface-100">
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
            {/* WEB-UIUX-696: show what the picker actually resolves to so the
                operator sees the absolute instant (UTC) before scheduling, and
                inline-flag a non-existent local time during DST spring-forward. */}
            {(() => {
              const parsed = new Date(when);
              if (Number.isNaN(parsed.getTime())) return null;
              const anomaly = dstAnomaly(when, parsed);
              const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'local';
              return (
                <div className="mt-1 text-[11px]">
                  {anomaly === 'nonexistent' ? (
                    <span className="text-red-600 dark:text-red-400">
                      This local time does not exist on the selected date (DST).
                    </span>
                  ) : (
                    <span className="text-surface-500 dark:text-surface-400">
                      Sends at <span className="font-mono">{parsed.toISOString().replace('T', ' ').slice(0, 16)}Z</span> ({tz})
                    </span>
                  )}
                </div>
              );
            })()}
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
            className="inline-flex items-center gap-1 rounded-lg bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            <Send className="h-3.5 w-3.5" />
            {sending ? 'Scheduling…' : 'Schedule'}
          </button>
        </div>
      </div>
    </div>
  );
}
