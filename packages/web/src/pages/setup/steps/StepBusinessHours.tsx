import { useState, useEffect, useMemo } from 'react';
import { ArrowLeft, Check, Clock } from 'lucide-react';
import type { SubStepProps } from '../wizardTypes';

/** Shape stored as JSON in store_config.business_hours */
interface DayHours {
  open: boolean;
  from: string; // "HH:MM"
  to: string;   // "HH:MM"
}
type WeekHours = Record<'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun', DayHours>;

const DEFAULT_HOURS: WeekHours = {
  mon: { open: true, from: '09:00', to: '17:00' },
  tue: { open: true, from: '09:00', to: '17:00' },
  wed: { open: true, from: '09:00', to: '17:00' },
  thu: { open: true, from: '09:00', to: '17:00' },
  fri: { open: true, from: '09:00', to: '17:00' },
  sat: { open: false, from: '10:00', to: '14:00' },
  sun: { open: false, from: '10:00', to: '14:00' },
};

const DAY_LABELS: Array<[keyof WeekHours, string]> = [
  ['mon', 'Monday'],
  ['tue', 'Tuesday'],
  ['wed', 'Wednesday'],
  ['thu', 'Thursday'],
  ['fri', 'Friday'],
  ['sat', 'Saturday'],
  ['sun', 'Sunday'],
];

/**
 * Sub-step — Business Hours.
 * Edits a WeekHours JSON object, toggles open/closed per day and lets the user
 * pick open/close times. Saved as a JSON string in business_hours.
 */
export function StepBusinessHours({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const [hours, setHours] = useState<WeekHours>(() => {
    if (pending.business_hours) {
      try {
        const parsed = JSON.parse(pending.business_hours);
        return { ...DEFAULT_HOURS, ...parsed };
      } catch { /* fall through to defaults */ }
    }
    return DEFAULT_HOURS;
  });

  // Persist on every change (keeps hub in sync if user goes back/forward)
  useEffect(() => {
    onUpdate({ business_hours: JSON.stringify(hours) });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hours]);

  const updateDay = (day: keyof WeekHours, patch: Partial<DayHours>) => {
    setHours((prev) => ({ ...prev, [day]: { ...prev[day], ...patch } }));
  };

  // WEB-S4-013: validate that 'to' > 'from' for open days
  const timeErrors = useMemo(() => {
    const errors: Partial<Record<keyof WeekHours, string>> = {};
    for (const [day] of DAY_LABELS) {
      const h = hours[day];
      if (h.open && h.from && h.to && h.to <= h.from) {
        errors[day] = 'Close time must be after open time';
      }
    }
    return errors;
  }, [hours]);

  const hasErrors = Object.keys(timeErrors).length > 0;

  return (
    <div className="mx-auto max-w-2xl">
      <SubStepHeader title="Business Hours" icon={<Clock className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
        subtitle="Used for off-hours SMS auto-replies and the customer portal's 'currently open' indicator." />

      <div className="space-y-3 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {DAY_LABELS.map(([day, label]) => {
          const h = hours[day];
          const dayError = timeErrors[day];
          return (
            <div key={day} className="flex flex-col gap-1">
              <div className="flex items-center gap-3">
                <label className="flex w-28 items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
                  <input
                    type="checkbox"
                    checked={h.open}
                    onChange={(e) => updateDay(day, { open: e.target.checked })}
                    className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                  />
                  <span className="font-medium">{label}</span>
                </label>
                <input
                  type="time"
                  value={h.from}
                  onChange={(e) => updateDay(day, { from: e.target.value })}
                  disabled={!h.open}
                  aria-invalid={!!dayError}
                  className={`rounded-lg border bg-surface-50 px-3 py-2 text-sm text-surface-900 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:bg-surface-700 dark:text-surface-100 ${dayError ? 'border-red-400 dark:border-red-500' : 'border-surface-300 dark:border-surface-600'}`}
                />
                <span className="text-sm text-surface-400">to</span>
                <input
                  type="time"
                  value={h.to}
                  onChange={(e) => updateDay(day, { to: e.target.value })}
                  disabled={!h.open}
                  aria-invalid={!!dayError}
                  className={`rounded-lg border bg-surface-50 px-3 py-2 text-sm text-surface-900 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:bg-surface-700 dark:text-surface-100 ${dayError ? 'border-red-400 dark:border-red-500' : 'border-surface-300 dark:border-surface-600'}`}
                />
                {!h.open && <span className="text-xs text-surface-400">Closed</span>}
              </div>
              {dayError && (
                <p role="alert" className="ml-32 text-xs text-red-500">{dayError}</p>
              )}
            </div>
          );
        })}
      </div>

      <SubStepFooter onCancel={onCancel} onComplete={onComplete} completeLabel="Save business hours" completeDisabled={hasErrors} />
    </div>
  );
}

// ── Shared sub-step chrome ───────────────────────────────────────────────────

export function SubStepHeader({ title, subtitle, icon }: { title: string; subtitle: string; icon: React.ReactNode }) {
  return (
    <div className="mb-6 text-center">
      <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
        {icon}
      </div>
      <h2 className="font-['League_Spartan'] text-2xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
        {title}
      </h2>
      <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">{subtitle}</p>
    </div>
  );
}

export function SubStepFooter({
  onCancel,
  onComplete,
  completeLabel = 'Save',
  completeDisabled = false,
}: {
  onCancel: () => void;
  onComplete: () => void;
  completeLabel?: string;
  completeDisabled?: boolean;
}) {
  return (
    <div className="mt-6 flex items-center justify-between">
      <button
        type="button"
        onClick={onCancel}
        className="flex items-center gap-1 text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to hub
      </button>
      <button
        type="button"
        onClick={onComplete}
        disabled={completeDisabled}
        className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
      >
        <Check className="h-4 w-4" />
        {completeLabel}
      </button>
    </div>
  );
}
