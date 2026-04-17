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
    '[{"days_offset":3,"action":"email","template_id":"overdue_1"}]',
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
        <button
          onClick={() => runNowMutation.mutate()}
          disabled={runNowMutation.isPending}
          className="rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 disabled:opacity-50"
        >
          {runNowMutation.isPending ? 'Running…' : 'Run dunning now'}
        </button>
      </div>

      {lastSummary && (
        <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-gray-700">Last run summary</h2>
            <span className="text-xs text-gray-400">
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

      <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm space-y-3">
        <h2 className="text-lg font-semibold">Create sequence</h2>
        <input
          type="text"
          placeholder="Sequence name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
        />
        <label className="block text-sm text-gray-600">
          Steps (JSON array):
          <textarea
            rows={4}
            value={stepsText}
            onChange={(e) => setStepsText(e.target.value)}
            className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-xs"
          />
        </label>
        <button
          onClick={() => createMutation.mutate()}
          disabled={!name.trim() || createMutation.isPending}
          className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:opacity-50"
        >
          Create
        </button>
      </div>

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="px-3 py-2 text-left">Name</th>
              <th className="px-3 py-2 text-left">Steps</th>
              <th className="px-3 py-2 text-left">Active</th>
              <th className="px-3 py-2 text-right">Toggle</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={4} className="px-3 py-6 text-center text-gray-400">Loading…</td></tr>
            ) : !sequences || sequences.length === 0 ? (
              <tr><td colSpan={4} className="px-3 py-6 text-center text-gray-400">No sequences</td></tr>
            ) : (
              sequences.map((seq) => (
                <tr key={seq.id} className="border-t border-gray-100">
                  <td className="px-3 py-2 font-medium">{seq.name}</td>
                  <td className="px-3 py-2">
                    {seq.steps.map((s, i) => (
                      <span
                        key={i}
                        className="mr-1 inline-flex rounded bg-gray-100 px-2 py-0.5 text-xs"
                      >
                        d+{s.days_offset} {s.action}
                      </span>
                    ))}
                  </td>
                  <td className="px-3 py-2">
                    {seq.is_active ? (
                      <span className="rounded-full bg-green-100 px-2 py-0.5 text-xs text-green-800">Active</span>
                    ) : (
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-700">Off</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-right">
                    <button
                      className="rounded border border-gray-300 px-2 py-1 text-xs hover:bg-gray-50 disabled:opacity-50"
                      onClick={() =>
                        toggleMutation.mutate({ id: seq.id, is_active: !seq.is_active })
                      }
                      disabled={toggleMutation.isPending && toggleMutation.variables?.id === seq.id}
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
  gray: 'border-gray-200 bg-gray-50 text-gray-700',
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
