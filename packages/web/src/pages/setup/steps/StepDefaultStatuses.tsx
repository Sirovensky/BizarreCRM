import { useCallback, useEffect, useState } from 'react';
import type { JSX } from 'react';
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Bell,
  BellOff,
  Loader2,
  MessageSquareText,
} from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { settingsApi } from '@/api/endpoints';

/**
 * Step 9 — Default ticket statuses (notification defaults).
 *
 * Mirrors `#screen-9` in `docs/setup-wizard-preview.html`. Surfaces the seeded
 * ticket statuses so the shop owner can decide which ones auto-send an SMS to
 * the customer. The seed (`packages/shared/src/constants/statuses.ts`) ships
 * sensible defaults — customer-facing states like "Ready for pickup" default
 * to `notify_customer = true`, internal states like "Diagnosis - In progress"
 * default to false. This step lets the owner override BEFORE the first ticket
 * is created so SMS flows match the shop's actual communication style.
 *
 * Root cause this fixes: section 3 of the pre-production audit. The original
 * seed hardcoded `notify_customer = 0` for every status, which meant
 * `services/notifications.ts#sendTicketStatusNotification` silently returned
 * on every ticket creation and no customer ever got an auto-SMS.
 *
 * Persistence model — this step does NOT use the `pending` bundle. Status
 * notification flags live in the `ticket_statuses` table, not in
 * `store_config`, so we PATCH each dirty row directly via
 * `settingsApi.updateStatus`. Step bookkeeping (which steps were
 * completed/skipped) is otherwise tracked at the wizard shell.
 *
 * H1: rewritten from `SubStepProps` (Extras Hub) to the linear-flow
 * `StepProps` contract — adds `WizardBreadcrumb`, Back/Continue/Skip footer.
 */

interface StatusRow {
  id: number;
  name: string;
  color: string;
  sort_order: number;
  is_default: number | boolean;
  is_closed: number | boolean;
  is_cancelled: number | boolean;
  notify_customer: number | boolean;
}

type StatusGroup = 'open' | 'hold' | 'closed' | 'cancelled';

interface GroupMeta {
  id: StatusGroup;
  label: string;
  description: string;
  accent: string;
}

const GROUPS: GroupMeta[] = [
  {
    id: 'open',
    label: 'Open',
    description: 'Active work in progress',
    accent: 'bg-blue-500',
  },
  {
    id: 'hold',
    label: 'On Hold',
    description: 'Waiting on parts, customer, or approval',
    accent: 'bg-amber-500',
  },
  {
    id: 'closed',
    label: 'Closed',
    description: 'Repair complete / shipped / collected',
    accent: 'bg-green-500',
  },
  {
    id: 'cancelled',
    label: 'Cancelled',
    description: 'Cancelled, BER, or disposed',
    accent: 'bg-red-500',
  },
];

function classify(status: StatusRow): StatusGroup {
  if (Number(status.is_cancelled) === 1) return 'cancelled';
  if (Number(status.is_closed) === 1) return 'closed';
  // Heuristic: amber/orange hex family → "On Hold" group. Cheap and stable
  // because the seed always uses these exact colours, and owners who change
  // colours later go through the full Settings screen anyway.
  const hex = (status.color || '').toLowerCase();
  if (hex === '#f97316' || hex === '#f59e0b' || hex === '#d97706') return 'hold';
  return 'open';
}

export function StepDefaultStatuses({
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const [statuses, setStatuses] = useState<StatusRow[]>([]);
  // Local override map keyed by status id — only populated when the user
  // actually flips a row so we send a minimal PUT per dirty row instead of
  // re-sending the full list.
  const [overrides, setOverrides] = useState<Record<number, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Pull the current statuses from the server on mount. We always show the
  // live DB copy — a shop owner may have edited statuses already (e.g. on a
  // re-setup) and we don't want to silently revert their work.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await settingsApi.getStatuses();
        const data = (res as any)?.data?.data ?? [];
        if (!cancelled) setStatuses(Array.isArray(data) ? (data as StatusRow[]) : []);
      } catch (err: any) {
        if (!cancelled) {
          setError(err?.response?.data?.message || 'Could not load ticket statuses.');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const effectiveNotify = useCallback(
    (status: StatusRow): boolean => {
      if (Object.prototype.hasOwnProperty.call(overrides, status.id)) {
        return overrides[status.id];
      }
      return Number(status.notify_customer) === 1;
    },
    [overrides],
  );

  const toggle = useCallback((status: StatusRow) => {
    setOverrides((prev) => {
      const current = Object.prototype.hasOwnProperty.call(prev, status.id)
        ? prev[status.id]
        : Number(status.notify_customer) === 1;
      return { ...prev, [status.id]: !current };
    });
  }, []);

  const enableAll = useCallback(() => {
    setOverrides(() => {
      const next: Record<number, boolean> = {};
      for (const s of statuses) next[s.id] = true;
      return next;
    });
  }, [statuses]);

  const disableAll = useCallback(() => {
    setOverrides(() => {
      const next: Record<number, boolean> = {};
      for (const s of statuses) next[s.id] = false;
      return next;
    });
  }, [statuses]);

  const resetToDefaults = useCallback(() => {
    setOverrides({});
  }, []);

  // Save dirty rows + advance. We only PATCH rows the user actually changed,
  // so we don't clobber other customisations. Partial failures are surfaced
  // but don't block advancing — owners can retry from Settings → Statuses.
  const handleContinue = useCallback(async () => {
    setSaving(true);
    setError('');
    try {
      const dirty = Object.entries(overrides).filter(([id, value]) => {
        const current = statuses.find((s) => s.id === Number(id));
        if (!current) return false;
        return (Number(current.notify_customer) === 1) !== value;
      });

      // WEB-S4-017: per-request error capture so partial failures are visible
      // rather than silently swallowed.
      const failures: string[] = [];
      await Promise.all(
        dirty.map(async ([id, value]) => {
          try {
            await settingsApi.updateStatus(Number(id), { notify_customer: value });
          } catch {
            const name = statuses.find((s) => s.id === Number(id))?.name ?? `#${id}`;
            failures.push(name);
          }
        }),
      );

      if (failures.length > 0) {
        setError(
          `Some statuses could not be saved: ${failures.join(', ')}. You can retry from Settings → Statuses.`,
        );
        // Don't block — most likely all but one saved fine.
      }
      onNext();
    } catch (err: any) {
      setError(err?.response?.data?.message || 'Failed to save notification defaults.');
    } finally {
      setSaving(false);
    }
  }, [overrides, statuses, onNext]);

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  // Summary counts — always computed off the effective (overrides-applied) view.
  const enabledCount = statuses.filter((s) => effectiveNotify(s)).length;
  const totalCount = statuses.length;

  const grouped: Record<StatusGroup, StatusRow[]> = {
    open: [],
    hold: [],
    closed: [],
    cancelled: [],
  };
  for (const s of statuses) {
    grouped[classify(s)].push(s);
  }
  for (const group of Object.keys(grouped) as StatusGroup[]) {
    grouped[group].sort((a, b) => a.sort_order - b.sort_order);
  }

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mb-2 inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-primary-100 text-primary-700 dark:bg-primary-500/20 dark:text-primary-300">
          <MessageSquareText className="h-6 w-6" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Ticket statuses
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Pick which statuses trigger an automatic SMS to the customer. You can change these any time in Settings → Statuses.
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {/* Why-it-matters banner — the whole reason this step exists. */}
        <div className="flex items-start gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-500/40 dark:bg-amber-500/10 dark:text-amber-100">
          <AlertTriangle className="mt-0.5 h-5 w-5 flex-shrink-0 text-amber-600 dark:text-amber-400" />
          <div className="space-y-1">
            <p className="font-semibold">Why this matters</p>
            <p className="text-amber-800 dark:text-amber-200">
              Your shop will not send a single automated SMS unless at least one status has
              notifications enabled. We've pre-enabled customer-facing statuses (Waiting for
              inspection, Ready, Repaired, Picked Up, etc.) and left internal workshop states
              (Diagnosis, QC) turned off.
            </p>
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center rounded-xl border border-surface-200 bg-surface-50 p-10 dark:border-surface-700 dark:bg-surface-900/40">
            <Loader2 className="h-6 w-6 animate-spin text-primary-600" />
          </div>
        ) : statuses.length === 0 ? (
          <div className="rounded-xl border border-surface-200 bg-surface-50 p-6 text-sm text-surface-600 dark:border-surface-700 dark:bg-surface-900/40 dark:text-surface-300">
            No ticket statuses found yet. Finish the wizard and add statuses from Settings → Statuses.
          </div>
        ) : (
          <>
            {/* Summary + bulk actions */}
            <div className="flex flex-col gap-3 border-b border-surface-200 pb-4 dark:border-surface-700 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex items-center gap-2 text-sm">
                <span
                  className={`inline-flex h-8 w-8 items-center justify-center rounded-full ${
                    enabledCount === 0
                      ? 'bg-red-100 text-red-700 dark:bg-red-500/20 dark:text-red-300'
                      : 'bg-primary-100 text-primary-700 dark:bg-primary-500/20 dark:text-primary-300'
                  }`}
                >
                  {enabledCount === 0 ? <BellOff className="h-4 w-4" /> : <Bell className="h-4 w-4" />}
                </span>
                <div>
                  <div className="font-semibold text-surface-900 dark:text-surface-100">
                    {enabledCount} of {totalCount} statuses notify the customer
                  </div>
                  {enabledCount === 0 && (
                    <div className="text-xs text-red-600 dark:text-red-300">
                      No auto-SMS will be sent until at least one status is enabled.
                    </div>
                  )}
                </div>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={enableAll}
                  className="rounded-lg border border-surface-300 bg-surface-50 px-3 py-1.5 text-xs font-medium text-surface-700 transition-colors hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
                >
                  Enable all
                </button>
                <button
                  type="button"
                  onClick={disableAll}
                  className="rounded-lg border border-surface-300 bg-surface-50 px-3 py-1.5 text-xs font-medium text-surface-700 transition-colors hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
                >
                  Disable all
                </button>
                <button
                  type="button"
                  onClick={resetToDefaults}
                  className="rounded-lg border border-surface-300 bg-surface-50 px-3 py-1.5 text-xs font-medium text-surface-700 transition-colors hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200 dark:hover:bg-surface-600"
                >
                  Reset defaults
                </button>
              </div>
            </div>

            {/* Grouped list */}
            <div className="space-y-5">
              {GROUPS.map((group) => {
                const items = grouped[group.id];
                if (!items || items.length === 0) return null;
                return (
                  <div key={group.id}>
                    <div className="mb-2 flex items-center gap-2">
                      <span className={`h-2 w-2 rounded-full ${group.accent}`} />
                      <h4 className="text-xs font-bold uppercase tracking-wider text-surface-700 dark:text-surface-300">
                        {group.label}
                      </h4>
                      <span className="text-xs text-surface-400 dark:text-surface-500">
                        {group.description}
                      </span>
                    </div>
                    <ul className="space-y-1.5">
                      {items.map((status) => {
                        const enabled = effectiveNotify(status);
                        return (
                          <li key={status.id}>
                            <button
                              type="button"
                              onClick={() => toggle(status)}
                              className={`flex w-full items-center justify-between gap-3 rounded-lg border px-3 py-2.5 text-left text-sm transition-colors ${
                                enabled
                                  ? 'border-primary-300 bg-primary-50 dark:border-primary-500/40 dark:bg-primary-500/10'
                                  : 'border-surface-200 bg-surface-50 hover:border-surface-300 dark:border-surface-700 dark:bg-surface-700/40 dark:hover:border-surface-600'
                              }`}
                            >
                              <div className="flex items-center gap-2.5">
                                <span
                                  className="h-2.5 w-2.5 flex-shrink-0 rounded-full"
                                  style={{ backgroundColor: status.color }}
                                />
                                <span
                                  className={`font-medium ${
                                    enabled
                                      ? 'text-surface-900 dark:text-surface-50'
                                      : 'text-surface-700 dark:text-surface-300'
                                  }`}
                                >
                                  {status.name}
                                </span>
                                {Number(status.is_default) === 1 && (
                                  <span className="rounded-full bg-surface-200 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-surface-600 dark:bg-surface-600 dark:text-surface-300">
                                    default
                                  </span>
                                )}
                              </div>
                              <ToggleSwitch enabled={enabled} />
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                );
              })}
            </div>
          </>
        )}

        {error && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300">
            {error}
          </div>
        )}

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
              Skip
            </button>
            <button
              type="button"
              onClick={handleContinue}
              disabled={saving || loading}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {saving ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Saving…
                </>
              ) : (
                <>
                  <ArrowRight className="h-4 w-4" />
                  Continue
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * Tiny visual-only toggle switch. The parent button handles the click; this
 * component just renders the state. Local because the wizard step is
 * self-contained and there's no other consumer.
 */
function ToggleSwitch({ enabled }: { enabled: boolean }) {
  return (
    <span
      className={`relative inline-flex h-5 w-9 flex-shrink-0 items-center rounded-full transition-colors ${
        enabled ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600'
      }`}
      aria-hidden="true"
    >
      <span
        className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow transition-transform ${
          enabled ? 'translate-x-[18px]' : 'translate-x-[2px]'
        }`}
      />
    </span>
  );
}

export default StepDefaultStatuses;
