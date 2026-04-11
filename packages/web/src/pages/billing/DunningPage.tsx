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

interface DunningSummary {
  sequences_evaluated: number;
  steps_fired: number;
  steps_skipped: number;
  invoices_touched: number;
  failures: number;
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

  const runNowMutation = useMutation<DunningSummary>({
    mutationFn: async () => {
      const res = await api.post('/dunning/run-now');
      return res.data.data;
    },
    onSuccess: (summary) =>
      toast.success(
        `Ran: ${summary.steps_fired} fired, ${summary.steps_skipped} skipped, ${summary.invoices_touched} invoices.`,
      ),
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

      <div className="overflow-hidden rounded-lg border border-gray-200 bg-white">
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
                      className="rounded border border-gray-300 px-2 py-1 text-xs hover:bg-gray-50"
                      onClick={() =>
                        toggleMutation.mutate({ id: seq.id, is_active: !seq.is_active })
                      }
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
