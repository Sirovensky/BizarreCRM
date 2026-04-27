/**
 * DunningPage — manage dunning sequences + run the scheduler manually.
 * §52 ideas 3 & 4. Lives at /billing/dunning.
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

interface DunningStep {
  days_offset: number;
  action: string;
  template_id?: string;
}

/**
 * Known notification template IDs. Until the server exposes a
 * `GET /notifications/templates` enum, this list is the contract that
 * `dunningScheduler.ts` honors. Keep in sync.
 *
 * WEB-FA-018 / FIXED-by-Fixer-U 2026-04-25 — replace the previous bare
 * `"overdue_1"` literal in the textarea placeholder with the first entry
 * from this list and surface the full set as a datalist hint so operators
 * don't invent template IDs that the dispatcher will silently drop.
 */
const KNOWN_TEMPLATE_IDS = ['overdue_1', 'overdue_2', 'overdue_final'] as const;
const DEFAULT_TEMPLATE_ID = KNOWN_TEMPLATE_IDS[0];

interface DunningSequence {
  id: number;
  name: string;
  is_active: number;
  steps: DunningStep[];
  created_at: string;
}

/**
 * Mirror of the server-side DunningSummary returned by
 * `POST /api/v1/dunning/run-now` (see `dunningScheduler.ts`). The scheduler
 * distinguishes four outcomes per step so the UI can warn operators about
 * non-dispatched rows instead of treating every recorded row as "sent".
 */
interface DunningSummary {
  sequences_evaluated: number;
  /** Steps whose notification was actually sent through SMS/email/etc. */
  steps_dispatched: number;
  /**
   * Steps recorded in dunning_runs but NOT actually sent because the action
   * is a manual/non-dispatch type (call_queue, escalate, …) or the channel
   * was not wired. Operators must treat these as "logged, not delivered".
   */
  steps_recorded_pending_dispatch: number;
  /** Steps whose provider dispatch threw. */
  steps_failed: number;
  steps_skipped: number;
  invoices_touched: number;
  failures: number;
  rate_limited?: boolean;
  warnings: string[];
}

export function DunningPage() {
  const qc = useQueryClient();
  const [name, setName] = useState('');
  const [stepsText, setStepsText] = useState(
    `[{"days_offset":3,"action":"email","template_id":"${DEFAULT_TEMPLATE_ID}"}]`,
  );

  const { data: sequences, isLoading } = useQuery({
    queryKey: ['dunning-sequences'],
    queryFn: async () => {
      const res = await api.get('/dunning/sequences');
      return res.data.data as DunningSequence[];
    },
  });

  const createMutation = useMutation({
    mutationFn: async () => {
      let steps: DunningStep[];
      try {
        steps = JSON.parse(stepsText);
      } catch {
        throw new Error('steps must be valid JSON array');
      }
      if (!Array.isArray(steps) || steps.length === 0) {
        throw new Error('steps must be a non-empty JSON array');
      }
      // WEB-FA-018: warn when an unknown template_id slips through —
      // the dispatcher will skip the step rather than crash, so the
      // user gets a chance to fix it before submission.
      const unknown = steps
        .map((s) => s?.template_id)
        .filter((t): t is string => typeof t === 'string' && t.length > 0)
        .filter((t) => !(KNOWN_TEMPLATE_IDS as readonly string[]).includes(t));
      if (unknown.length > 0) {
        throw new Error(
          `Unknown template_id(s): ${unknown.join(', ')}. Known: ${KNOWN_TEMPLATE_IDS.join(', ')}`,
        );
      }
      const res = await api.post('/dunning/sequences', { name, steps });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Sequence created');
      setName('');
      qc.invalidateQueries({ queryKey: ['dunning-sequences'] });
    },
    onError: (err: unknown) =>
      toast.error(err instanceof Error ? err.message : 'Failed to create sequence'),
  });

  const toggleMutation = useMutation({
    mutationFn: async ({ id, is_active }: { id: number; is_active: boolean }) =>
      api.put(`/dunning/sequences/${id}`, { is_active }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['dunning-sequences'] }),
  });

  const [lastSummary, setLastSummary] = useState<DunningSummary | null>(null);

  const runNowMutation = useMutation<DunningSummary>({
    mutationFn: async () => {
      const res = await api.post('/dunning/run-now');
      return res.data.data;
    },
    onSuccess: (summary) => {
      setLastSummary(summary);
      const dispatched = summary.steps_dispatched ?? 0;
      const pending = summary.steps_recorded_pending_dispatch ?? 0;
      const failed = summary.steps_failed ?? 0;
      const skipped = summary.steps_skipped ?? 0;
      const touched = summary.invoices_touched ?? 0;
      if (summary.rate_limited) {
        toast('Rate-limited — previous run was too recent.', { icon: '\u26a0\ufe0f', duration: 6000 });
        return;
      }
      if (failed > 0) {
        toast.error(
          `Dunning ran: ${dispatched} sent, ${failed} failed, ${pending} pending, ${skipped} skipped across ${touched} invoices.`,
          { duration: 7000 },
        );
      } else {
        toast.success(
          `Dunning ran: ${dispatched} sent, ${pending} pending dispatch, ${skipped} skipped across ${touched} invoices.`,
          { duration: 5000 },
        );
      }
      if (summary.warnings?.length) {
        for (const w of summary.warnings) toast(w, { icon: '\u26a0\ufe0f', duration: 6000 });
      }
    },
    onError: () => toast.error('Run failed — admin only'),
  });

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Dunning Sequences</h1>
        <button type="button"
          onClick={() => runNowMutation.mutate()}
          disabled={runNowMutation.isPending}
          className="rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 disabled:opacity-50"
        >
          {runNowMutation.isPending ? 'Running…' : 'Run dunning now'}
        </button>
      </div>

      {lastSummary && (
        <div className="rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4 shadow-sm">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-surface-700 dark:text-surface-200">Last run summary</h2>
            <span className="text-xs text-surface-400">
              {lastSummary.invoices_touched} invoice{lastSummary.invoices_touched === 1 ? '' : 's'} touched
            </span>
          </div>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <SummaryCell
              label="Dispatched"
              value={lastSummary.steps_dispatched ?? 0}
              tone="green"
              hint="Sent via SMS/email/etc."
            />
            <SummaryCell
              label="Pending dispatch"
              value={lastSummary.steps_recorded_pending_dispatch ?? 0}
              tone="amber"
              hint="Logged for manual follow-up (call_queue, escalate, unwired channel)."
            />
            <SummaryCell
              label="Failed"
              value={lastSummary.steps_failed ?? 0}
              tone={(lastSummary.steps_failed ?? 0) > 0 ? 'red' : 'gray'}
              hint="Provider dispatch threw — check warnings."
            />
            <SummaryCell
              label="Skipped"
              value={lastSummary.steps_skipped ?? 0}
              tone="gray"
              hint="Rate-limited or already recorded this run."
            />
          </div>
          {lastSummary.warnings?.length ? (
            <ul className="mt-3 space-y-1 rounded-md border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
              {lastSummary.warnings.map((w, idx) => (
                <li key={idx}>• {w}</li>
              ))}
            </ul>
          ) : null}
        </div>
      )}

      <div className="rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4 shadow-sm space-y-3">
        <h2 className="text-lg font-semibold">Create sequence</h2>
        <input
          type="text"
          placeholder="Sequence name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full rounded-md border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm"
        />
        <label className="block text-sm text-surface-600 dark:text-surface-300">
          Steps (JSON array):
          <textarea
            rows={4}
            value={stepsText}
            onChange={(e) => setStepsText(e.target.value)}
            className="mt-1 w-full rounded-md border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 font-mono text-xs"
          />
        </label>
        <p className="text-xs text-surface-500">
          Known template_id values:{' '}
          {KNOWN_TEMPLATE_IDS.map((t) => (
            <code
              key={t}
              className="mr-1 rounded bg-surface-100 dark:bg-surface-800 text-surface-700 dark:text-surface-200 px-1 py-0.5 font-mono text-[11px]"
            >
              {t}
            </code>
          ))}
        </p>
        <button type="button"
          onClick={() => createMutation.mutate()}
          disabled={!name.trim() || createMutation.isPending}
          className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 hover:bg-primary-700 disabled:opacity-50"
        >
          Create
        </button>
      </div>

      <div className="overflow-x-auto rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 dark:bg-surface-800 text-surface-600 dark:text-surface-300">
            <tr>
              <th className="px-3 py-2 text-left">Name</th>
              <th className="px-3 py-2 text-left">Steps</th>
              <th className="px-3 py-2 text-left">Active</th>
              <th className="px-3 py-2 text-right">Toggle</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={4} className="px-3 py-6 text-center text-surface-400">Loading…</td></tr>
            ) : !sequences || sequences.length === 0 ? (
              <tr><td colSpan={4} className="px-3 py-6 text-center text-surface-400">No sequences</td></tr>
            ) : (
              sequences.map((seq) => (
                <tr key={seq.id} className="border-t border-surface-100 dark:border-surface-800">
                  <td className="px-3 py-2 font-medium">{seq.name}</td>
                  <td className="px-3 py-2">
                    {seq.steps.map((s, i) => (
                      <span
                        key={i}
                        className="mr-1 inline-flex rounded bg-surface-100 dark:bg-surface-800 text-surface-700 dark:text-surface-200 px-2 py-0.5 text-xs"
                      >
                        d+{s.days_offset} {s.action}
                      </span>
                    ))}
                  </td>
                  <td className="px-3 py-2">
                    {seq.is_active ? (
                      <span className="rounded-full bg-green-100 px-2 py-0.5 text-xs text-green-800">Active</span>
                    ) : (
                      <span className="rounded-full bg-surface-100 dark:bg-surface-800 px-2 py-0.5 text-xs text-surface-700 dark:text-surface-200">Off</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-right">
                    <button type="button"
                      className="rounded border border-surface-300 dark:border-surface-600 px-2 py-1 text-xs hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-50"
                      onClick={() =>
                        toggleMutation.mutate({ id: seq.id, is_active: !seq.is_active })
                      }
                      disabled={toggleMutation.isPending && toggleMutation.variables?.id === seq.id}
                      aria-label={`${seq.is_active ? 'Disable' : 'Enable'} dunning sequence ${seq.name}`}
                    >
                      {seq.is_active ? 'Disable' : 'Enable'}
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

type SummaryTone = 'green' | 'amber' | 'red' | 'gray';

const TONE_CLASSES: Record<SummaryTone, string> = {
  green: 'border-green-200 bg-green-50 text-green-800',
  amber: 'border-amber-200 bg-amber-50 text-amber-900',
  red: 'border-red-200 bg-red-50 text-red-800',
  gray: 'border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 text-surface-700 dark:text-surface-200',
};

function SummaryCell({
  label,
  value,
  tone,
  hint,
}: {
  label: string;
  value: number;
  tone: SummaryTone;
  hint?: string;
}) {
  return (
    <div
      className={`rounded-md border px-3 py-2 ${TONE_CLASSES[tone]}`}
      title={hint}
    >
      <div className="text-[11px] font-medium uppercase tracking-wide opacity-80">
        {label}
      </div>
      <div className="mt-0.5 text-lg font-semibold tabular-nums">{value}</div>
    </div>
  );
}
