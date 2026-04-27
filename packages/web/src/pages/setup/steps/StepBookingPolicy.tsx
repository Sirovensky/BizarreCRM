/**
 * StepBookingPolicy — Setup wizard Step 21.
 *
 * Captures the shop's appointment policy: whether customers can self-book
 * online (with lead-time + max-future-day guards) and whether walk-ins are
 * accepted at all. The two toggles are independent — a shop can accept
 * walk-ins only, online bookings only, both, or neither (rare but allowed).
 *
 * Persists via `onUpdate` to the wizard's `pendingWrites` bag, which is
 * flushed in a single `PUT /settings/config` call at wizard completion.
 * Keys (`booking_online_enabled`, `booking_lead_hours`,
 * `booking_max_days_ahead`, `booking_walkins_enabled`) are allow-listed
 * server-side in `settings.routes.ts`.
 *
 * Mockup: `docs/setup-wizard-preview.html` `<section id="screen-21">`.
 * The mockup shows a radio + dropdown layout, but the agreed contract for
 * this step is a pair of independent pill toggles plus two numeric inputs
 * that reveal only when online booking is on. This matches the actual
 * `booking_*` config keys the portal calendar will read.
 */
import { useState } from 'react';
import type { JSX } from 'react';
import { Calendar, Clock, UserCheck } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { WizardBreadcrumb } from '../components/WizardBreadcrumb';

const DEFAULT_LEAD_HOURS = 2;
const DEFAULT_MAX_DAYS_AHEAD = 60;
const LEAD_MIN = 0;
const LEAD_MAX = 720;
const DAYS_MIN = 1;
const DAYS_MAX = 365;

function clamp(value: number, min: number, max: number): number {
  if (Number.isNaN(value)) return min;
  return Math.min(Math.max(value, min), max);
}

interface PillToggleProps {
  on: boolean;
  onChange: (next: boolean) => void;
  ariaLabel: string;
}

/** 44px-wide pill switch — primary-500 when on, surface-300 when off. */
function PillToggle({ on, onChange, ariaLabel }: PillToggleProps): JSX.Element {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={ariaLabel}
      onClick={() => onChange(!on)}
      className={
        'relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/40 ' +
        (on
          ? 'bg-primary-500'
          : 'bg-surface-300 dark:bg-surface-600')
      }
    >
      <span
        className={
          'inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ' +
          (on ? 'translate-x-5' : 'translate-x-0.5')
        }
      />
    </button>
  );
}

export function StepBookingPolicy({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const [onlineEnabled, setOnlineEnabled] = useState<boolean>(
    pending.booking_online_enabled === '1',
  );
  const [walkinsEnabled, setWalkinsEnabled] = useState<boolean>(
    // Default ON — only off when explicitly persisted as '0'.
    pending.booking_walkins_enabled !== '0',
  );
  const [leadHours, setLeadHours] = useState<number>(() => {
    const raw = pending.booking_lead_hours;
    const parsed = raw ? Number.parseInt(raw, 10) : DEFAULT_LEAD_HOURS;
    return clamp(parsed, LEAD_MIN, LEAD_MAX);
  });
  const [maxDaysAhead, setMaxDaysAhead] = useState<number>(() => {
    const raw = pending.booking_max_days_ahead;
    const parsed = raw ? Number.parseInt(raw, 10) : DEFAULT_MAX_DAYS_AHEAD;
    return clamp(parsed, DAYS_MIN, DAYS_MAX);
  });

  const persist = (overrides?: {
    online?: boolean;
    walkins?: boolean;
    lead?: number;
    days?: number;
  }) => {
    const o = overrides?.online ?? onlineEnabled;
    const w = overrides?.walkins ?? walkinsEnabled;
    const l = overrides?.lead ?? leadHours;
    const d = overrides?.days ?? maxDaysAhead;
    onUpdate({
      booking_online_enabled: o ? '1' : '0',
      booking_walkins_enabled: w ? '1' : '0',
      booking_lead_hours: String(clamp(l, LEAD_MIN, LEAD_MAX)),
      booking_max_days_ahead: String(clamp(d, DAYS_MIN, DAYS_MAX)),
    });
  };

  const handleOnlineToggle = (next: boolean) => {
    setOnlineEnabled(next);
    persist({ online: next });
  };

  const handleWalkinsToggle = (next: boolean) => {
    setWalkinsEnabled(next);
    persist({ walkins: next });
  };

  const handleLeadChange = (raw: string) => {
    const parsed = Number.parseInt(raw, 10);
    const next = clamp(parsed, LEAD_MIN, LEAD_MAX);
    setLeadHours(next);
    persist({ lead: next });
  };

  const handleDaysChange = (raw: string) => {
    const parsed = Number.parseInt(raw, 10);
    const next = clamp(parsed, DAYS_MIN, DAYS_MAX);
    setMaxDaysAhead(next);
    persist({ days: next });
  };

  const handleContinue = () => {
    persist();
    onNext();
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
        <WizardBreadcrumb
          prevLabel="Step 20 · Cash drawer"
          currentLabel="Step 21 · Booking policy"
          nextLabel="Step 22 · Warranty"
        />
      </div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Calendar className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Booking policy
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          How customers schedule. You can change either of these later in
          Settings — they don't affect existing tickets.
        </p>
      </div>

      <div className="mx-auto max-w-2xl rounded-2xl border border-surface-200 bg-white p-8 dark:border-surface-700 dark:bg-surface-800">
        {/* ─── Online booking ────────────────────────────────────── */}
        <section>
          <div className="flex items-start justify-between gap-4">
            <div className="flex items-start gap-3">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400">
                <Clock className="h-5 w-5" />
              </div>
              <div>
                <div className="text-sm font-semibold text-surface-900 dark:text-surface-100">
                  Allow customers to book online
                </div>
                <p className="mt-0.5 text-xs text-surface-500">
                  Customers self-book through the customer portal. Slots
                  respect business hours and the limits below.
                </p>
              </div>
            </div>
            <PillToggle
              on={onlineEnabled}
              onChange={handleOnlineToggle}
              ariaLabel="Allow customers to book online"
            />
          </div>

          {onlineEnabled ? (
            <div className="mt-4 space-y-4 rounded-xl border border-surface-200 bg-surface-50 p-4 dark:border-surface-700 dark:bg-surface-900/40">
              <div className="flex items-center justify-between gap-4">
                <div>
                  <label
                    htmlFor="booking-lead-hours"
                    className="block text-sm font-medium text-surface-700 dark:text-surface-300"
                  >
                    Minimum lead time
                  </label>
                  <p className="text-xs text-surface-500">
                    Earliest appointment from now. Stops customers booking a
                    slot you can't realistically prep for.
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <input
                    id="booking-lead-hours"
                    type="number"
                    min={LEAD_MIN}
                    max={LEAD_MAX}
                    value={leadHours}
                    onChange={(e) => handleLeadChange(e.target.value)}
                    className="w-32 rounded-lg border border-surface-200 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
                  />
                  <span className="text-xs text-surface-400">hours</span>
                </div>
              </div>

              <div className="flex items-center justify-between gap-4">
                <div>
                  <label
                    htmlFor="booking-max-days"
                    className="block text-sm font-medium text-surface-700 dark:text-surface-300"
                  >
                    Max future booking
                  </label>
                  <p className="text-xs text-surface-500">
                    Furthest a customer can book in advance. Keeps the
                    calendar from filling up with appointments months out.
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <input
                    id="booking-max-days"
                    type="number"
                    min={DAYS_MIN}
                    max={DAYS_MAX}
                    value={maxDaysAhead}
                    onChange={(e) => handleDaysChange(e.target.value)}
                    className="w-32 rounded-lg border border-surface-200 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
                  />
                  <span className="text-xs text-surface-400">days</span>
                </div>
              </div>
            </div>
          ) : null}
        </section>

        <div className="my-6 border-t border-surface-200 dark:border-surface-700" />

        {/* ─── Walk-ins ──────────────────────────────────────────── */}
        <section>
          <div className="flex items-start justify-between gap-4">
            <div className="flex items-start gap-3">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400">
                <UserCheck className="h-5 w-5" />
              </div>
              <div>
                <div className="text-sm font-semibold text-surface-900 dark:text-surface-100">
                  Accept walk-ins
                </div>
                <p className="mt-0.5 text-xs text-surface-500">
                  First-come, first-served customers without an appointment.
                  Independent of online booking — you can run either, both,
                  or (rarely) neither.
                </p>
              </div>
            </div>
            <PillToggle
              on={walkinsEnabled}
              onChange={handleWalkinsToggle}
              ariaLabel="Accept walk-ins"
            />
          </div>
        </section>

        {/* ─── Footer ────────────────────────────────────────────── */}
        <div className="mt-8 flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={onBack}
            className="rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            Back
          </button>
          <div className="flex items-center gap-2">
            {onSkip ? (
              <button
                type="button"
                onClick={onSkip}
                className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
              >
                Skip
              </button>
            ) : null}
            <button
              type="button"
              onClick={handleContinue}
              className="rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
            >
              Continue
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepBookingPolicy;
