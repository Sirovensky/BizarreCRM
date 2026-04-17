/**
 * Goals + targets per tech — criticalaudit.md §53 idea #11.
 *
 * Lists every goal with a progress bar pulled from the server. Managers can
 * create + delete goals; everyone can view.
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Target, Trash2, Plus, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { formatCurrency } from '@/utils/format';
// FA-L4: CommissionPeriodLock gives managers a visible control to freeze
// payroll windows once commissions are finalized. Goals + payroll live in
// the same manager workflow so we mount both on this page.
import { CommissionPeriodLock } from '@/components/team/CommissionPeriodLock';

interface Goal {
  id: number;
  user_id: number;
  metric: string;
  target_value: number;
  period_start: string;
  period_end: string;
  first_name: string | null;
  last_name: string | null;
  progress: number;
}

interface Employee {
  id: number;
  first_name: string;
  last_name: string;
}

const METRIC_LABELS: Record<string, string> = {
  tickets_closed_week: 'Tickets closed',
  revenue_week: 'Revenue',
  csat: 'CSAT',
};

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function plusDaysIso(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export function GoalsPage() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [newUserId, setNewUserId] = useState<number | ''>('');
  const [newMetric, setNewMetric] = useState('tickets_closed_week');
  const [newTarget, setNewTarget] = useState('');
  const [newStart, setNewStart] = useState(todayIso());
  const [newEnd, setNewEnd] = useState(plusDaysIso(7));

  const { data: goalsData } = useQuery({
    queryKey: ['team', 'goals'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Goal[] }>('/team/goals');
      return res.data.data;
    },
  });
  const goals: Goal[] = goalsData || [];

  const { data: employeesData } = useQuery({
    queryKey: ['employees', 'simple'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Employee[] }>('/employees');
      return res.data.data;
    },
  });
  const employees: Employee[] = employeesData || [];

  const createMut = useMutation({
    mutationFn: async () => {
      await api.post('/team/goals', {
        user_id: Number(newUserId),
        metric: newMetric,
        target_value: Number(newTarget),
        period_start: newStart,
        period_end: newEnd,
      });
    },
    onSuccess: () => {
      toast.success('Goal created');
      queryClient.invalidateQueries({ queryKey: ['team', 'goals'] });
      setShowNew(false);
      setNewUserId('');
      setNewTarget('');
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to create goal'),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: number) => {
      await api.delete(`/team/goals/${id}`);
    },
    onSuccess: () => {
      toast.success('Goal deleted');
      queryClient.invalidateQueries({ queryKey: ['team', 'goals'] });
    },
  });

  return (
    <div className="p-6 max-w-5xl mx-auto">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 inline-flex items-center">
            <Target className="w-6 h-6 mr-2 text-green-500" /> Goals
          </h1>
          <p className="text-sm text-gray-500">Per-tech weekly targets with live progress.</p>
        </div>
        <button
          className="px-3 py-1.5 bg-green-600 text-white rounded text-sm hover:bg-green-700 inline-flex items-center"
          onClick={() => setShowNew(true)}
        >
          <Plus className="w-4 h-4 mr-1" /> New goal
        </button>
      </header>

      {goals.length === 0 && (
        <div className="bg-white border rounded-lg p-12 text-center text-gray-500">
          No goals yet. Add your first one with the button above.
        </div>
      )}

      {/* FA-L4 — Commission/payroll period locks live on the manager's
          team-targets page so once a period is finalized it can be frozen
          from the same screen as the goals that funded it. */}
      <div className="mt-6">
        <CommissionPeriodLock />
      </div>

      <div className="space-y-3">
        {goals.map((g) => {
          const pct = g.target_value > 0
            ? Math.min(100, (g.progress / g.target_value) * 100)
            : 0;
          const done = pct >= 100;
          return (
            <div key={g.id} className="bg-white rounded-lg shadow border p-4">
              <div className="flex items-center justify-between mb-2">
                <div>
                  <div className="font-semibold text-gray-800">
                    {g.first_name} {g.last_name}
                  </div>
                  <div className="text-xs text-gray-500">
                    {METRIC_LABELS[g.metric] || g.metric} · {g.period_start} → {g.period_end}
                  </div>
                </div>
                <button
                  className="text-red-500 hover:text-red-700 disabled:opacity-40"
                  onClick={() => deleteMut.mutate(g.id)}
                  disabled={deleteMut.isPending && deleteMut.variables === g.id}
                  aria-label={`Delete goal for ${g.first_name ?? ''} ${g.last_name ?? ''}`}
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
              <div className="h-3 bg-gray-100 rounded-full overflow-hidden">
                <div
                  className={`h-full ${done ? 'bg-green-500' : 'bg-blue-500'}`}
                  style={{ width: `${pct}%` }}
                />
              </div>
              <div className="text-xs text-gray-600 mt-1">
                {g.metric === 'revenue_week'
                  ? `${formatCurrency(Number(g.progress))} / ${formatCurrency(Number(g.target_value))}`
                  : `${Number(g.progress).toFixed(0)} / ${Number(g.target_value).toFixed(0)}`}
                {' '}({pct.toFixed(0)}%)
              </div>
            </div>
          );
        })}
      </div>

      {showNew && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5">
            <h2 className="text-lg font-bold mb-4">New goal</h2>
            <div className="space-y-3">
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Employee</span>
                <select
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newUserId}
                  onChange={(e) => setNewUserId(e.target.value ? Number(e.target.value) : '')}
                >
                  <option value="">— pick —</option>
                  {employees.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.first_name} {e.last_name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Metric</span>
                <select
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newMetric}
                  onChange={(e) => setNewMetric(e.target.value)}
                >
                  <option value="tickets_closed_week">Tickets closed</option>
                  <option value="revenue_week">Revenue</option>
                  <option value="csat">CSAT score</option>
                </select>
              </label>
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Target value</span>
                <input
                  type="number"
                  step="0.01"
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newTarget}
                  onChange={(e) => setNewTarget(e.target.value)}
                  placeholder="e.g. 15"
                />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">Start</span>
                  <input
                    type="date"
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={newStart}
                    onChange={(e) => setNewStart(e.target.value)}
                  />
                </label>
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">End</span>
                  <input
                    type="date"
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={newEnd}
                    onChange={(e) => setNewEnd(e.target.value)}
                  />
                </label>
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-gray-50"
                onClick={() => setShowNew(false)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-green-600 text-white rounded text-sm hover:bg-green-700 inline-flex items-center justify-center"
                disabled={!newUserId || !newTarget || createMut.isPending}
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                Save
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
