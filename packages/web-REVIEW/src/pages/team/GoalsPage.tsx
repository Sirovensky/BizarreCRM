/**
 * Goals + targets per tech — criticalaudit.md §53 idea #11.
 *
 * Lists every goal with a progress bar pulled from the server. Managers can
 * create + delete goals; everyone can view.
 */
import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Target, Trash2, Plus, Loader2, Pencil } from 'lucide-react';
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

// WEB-W3-037: Static fallback labels for metrics not yet loaded from server.
// The GoalsPage fetches /team/goal-metrics on mount; until that resolves these
// cover the 3 legacy values so existing goals render correctly.
const METRIC_LABELS_FALLBACK: Record<string, string> = {
  tickets_closed_week: 'Tickets closed',
  revenue_week: 'Revenue',
  csat: 'CSAT',
};

interface GoalMetricDef {
  key: string;
  label: string;
  unit: string;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function plusDaysIso(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

// @audit-fixed (WEB-FG-010 / Fixer-B1 2026-04-25): clamp to a sane window so
// managers can't save a goal for the year 9999 or 0001 via a stray keystroke
// in a date input. Server validation is the source of truth, but failing fast
// in the UI saves a roundtrip + a confusing 400 toast.
const GOAL_DATE_MIN = '2020-01-01';
const GOAL_DATE_MAX = '2100-12-31';

export function GoalsPage() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [newUserId, setNewUserId] = useState<number | ''>('');
  const [newMetric, setNewMetric] = useState('tickets_closed_week');
  const [newTarget, setNewTarget] = useState('');
  const [newStart, setNewStart] = useState(todayIso());
  const [newEnd, setNewEnd] = useState(plusDaysIso(7));

  // WEB-S6-027: edit state
  const [editingGoalId, setEditingGoalId] = useState<number | null>(null);
  const [editUserId, setEditUserId] = useState<number | ''>('');
  const [editMetric, setEditMetric] = useState('tickets_closed_week');
  const [editTarget, setEditTarget] = useState('');
  const [editStart, setEditStart] = useState(todayIso());
  const [editEnd, setEditEnd] = useState(plusDaysIso(7));

  // WEB-W3-037: Load supported metric types from server enum instead of hardcoding.
  const { data: metricsData } = useQuery({
    queryKey: ['team', 'goal-metrics'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: GoalMetricDef[] }>('/team/goal-metrics');
      return res.data.data;
    },
    staleTime: 5 * 60 * 1000, // Metric list rarely changes; cache for 5 min.
  });
  const metricDefs: GoalMetricDef[] = metricsData || [];
  // Build label map — merge server defs over static fallback so legacy goals
  // that use a key not yet in the server list still show a readable label.
  const metricLabels: Record<string, string> = {
    ...METRIC_LABELS_FALLBACK,
    ...Object.fromEntries(metricDefs.map((m) => [m.key, m.label])),
  };

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

  // WEB-S6-027: editMut calls PUT /team/goals/:id
  const editMut = useMutation({
    mutationFn: async () => {
      const res = await api.put(`/team/goals/${editingGoalId}`, {
        user_id: Number(editUserId),
        metric: editMetric,
        target_value: Number(editTarget),
        period_start: editStart,
        period_end: editEnd,
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Goal updated');
      queryClient.invalidateQueries({ queryKey: ['team', 'goals'] });
      setEditingGoalId(null);
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to update goal'),
  });

  const openEditModal = (g: Goal) => {
    setEditingGoalId(g.id);
    setEditUserId(g.user_id);
    setEditMetric(g.metric);
    setEditTarget(String(g.target_value));
    setEditStart(g.period_start);
    setEditEnd(g.period_end);
  };

  return (
    <div className="p-6 max-w-5xl mx-auto">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 dark:text-surface-100 inline-flex items-center">
            <Target className="w-6 h-6 mr-2 text-green-500" /> Goals
          </h1>
          <p className="text-sm text-gray-500 dark:text-surface-400">Per-tech weekly targets with live progress.</p>
        </div>
        <button
          className="px-3 py-1.5 bg-green-600 text-white rounded text-sm hover:bg-green-700 inline-flex items-center"
          onClick={() => setShowNew(true)}
        >
          <Plus className="w-4 h-4 mr-1" /> New goal
        </button>
      </header>

      {goals.length === 0 && (
        <div className="bg-white dark:bg-surface-900 border dark:border-surface-700 rounded-lg p-12 text-center text-gray-500 dark:text-surface-400">
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
          const target = Number(g.target_value);
          const progress = Number(g.progress);
          const ratio = target > 0 ? (progress / target) * 100 : 0;
          // Guard NaN/Infinity (string targets, missing fields, denominator==0) so width never renders as `NaN%`.
          const pct = Number.isFinite(ratio) ? Math.max(0, Math.min(100, ratio)) : 0;
          const done = pct >= 100;
          return (
            <div key={g.id} className="bg-white dark:bg-surface-900 rounded-lg shadow border dark:border-surface-700 p-4">
              <div className="flex items-center justify-between mb-2">
                <div>
                  <div className="font-semibold text-gray-800 dark:text-surface-100">
                    {g.first_name} {g.last_name}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-surface-400">
                    {metricLabels[g.metric] || g.metric} · {g.period_start} → {g.period_end}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  {/* WEB-S6-027: edit button */}
                  <button
                    className="text-surface-400 hover:text-teal-600 dark:hover:text-teal-400 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                    onClick={() => openEditModal(g)}
                    aria-label={`Edit goal for ${g.first_name ?? ''} ${g.last_name ?? ''}`}
                  >
                    <Pencil className="w-4 h-4" />
                  </button>
                  <button
                    className="text-red-500 hover:text-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                    onClick={() => deleteMut.mutate(g.id)}
                    disabled={deleteMut.isPending && deleteMut.variables === g.id}
                    aria-label={`Delete goal for ${g.first_name ?? ''} ${g.last_name ?? ''}`}
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
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
        <NewGoalModal onClose={() => setShowNew(false)}>
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5" onClick={(e) => e.stopPropagation()}>
            <h2 id="new-goal-title" className="text-lg font-bold mb-4">New goal</h2>
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
                  {/* WEB-W3-037: options loaded from /team/goal-metrics; fall back
                      to the 3 static values if the request hasn't resolved yet. */}
                  {(metricDefs.length > 0 ? metricDefs : [
                    { key: 'tickets_closed_week', label: 'Tickets closed', unit: 'count' },
                    { key: 'revenue_week',         label: 'Revenue',        unit: 'currency' },
                    { key: 'csat',                 label: 'CSAT score',     unit: 'score' },
                  ]).map((m) => (
                    <option key={m.key} value={m.key}>{m.label}</option>
                  ))}
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
                    min={GOAL_DATE_MIN}
                    max={GOAL_DATE_MAX}
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={newStart}
                    onChange={(e) => setNewStart(e.target.value)}
                  />
                </label>
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">End</span>
                  <input
                    type="date"
                    min={newStart || GOAL_DATE_MIN}
                    max={GOAL_DATE_MAX}
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={newEnd}
                    onChange={(e) => setNewEnd(e.target.value)}
                  />
                </label>
              </div>
              {newStart && newEnd && newStart > newEnd && (
                <p role="alert" aria-live="polite" className="text-xs text-red-600 mt-1">End date must be on or after start date.</p>
              )}
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
                disabled={
                  !newUserId
                  || !newTarget
                  || !newStart
                  || !newEnd
                  || newStart > newEnd
                  || createMut.isPending
                }
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                Save
              </button>
            </div>
          </div>
        </NewGoalModal>
      )}

      {/* WEB-S6-027: edit goal modal */}
      {editingGoalId !== null && (
        <NewGoalModal onClose={() => setEditingGoalId(null)}>
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5" onClick={(e) => e.stopPropagation()}>
            <h2 id="new-goal-title" className="text-lg font-bold mb-4">Edit goal</h2>
            <div className="space-y-3">
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Employee</span>
                <select
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={editUserId}
                  onChange={(e) => setEditUserId(e.target.value ? Number(e.target.value) : '')}
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
                  value={editMetric}
                  onChange={(e) => setEditMetric(e.target.value)}
                >
                  {(metricDefs.length > 0 ? metricDefs : [
                    { key: 'tickets_closed_week', label: 'Tickets closed', unit: 'count' },
                    { key: 'revenue_week',         label: 'Revenue',        unit: 'currency' },
                    { key: 'csat',                 label: 'CSAT score',     unit: 'score' },
                  ]).map((m) => (
                    <option key={m.key} value={m.key}>{m.label}</option>
                  ))}
                </select>
              </label>
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Target value</span>
                <input
                  type="number"
                  step="0.01"
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={editTarget}
                  onChange={(e) => setEditTarget(e.target.value)}
                  placeholder="e.g. 15"
                />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">Start</span>
                  <input
                    type="date"
                    min={GOAL_DATE_MIN}
                    max={GOAL_DATE_MAX}
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={editStart}
                    onChange={(e) => setEditStart(e.target.value)}
                  />
                </label>
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">End</span>
                  <input
                    type="date"
                    min={editStart || GOAL_DATE_MIN}
                    max={GOAL_DATE_MAX}
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={editEnd}
                    onChange={(e) => setEditEnd(e.target.value)}
                  />
                </label>
              </div>
              {editStart && editEnd && editStart > editEnd && (
                <p role="alert" aria-live="polite" className="text-xs text-red-600 mt-1">End date must be on or after start date.</p>
              )}
            </div>
            <div className="flex gap-2 mt-5">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-gray-50"
                onClick={() => setEditingGoalId(null)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-green-600 text-white rounded text-sm hover:bg-green-700 inline-flex items-center justify-center"
                disabled={
                  !editUserId
                  || !editTarget
                  || !editStart
                  || !editEnd
                  || editStart > editEnd
                  || editMut.isPending
                }
                onClick={() => editMut.mutate()}
              >
                {editMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                Save
              </button>
            </div>
          </div>
        </NewGoalModal>
      )}
    </div>
  );
}

// NewGoalModal — keyboard a11y wrapper around the new-goal form. Esc closes,
// click on the dim backdrop closes, click inside the panel does not.
function NewGoalModal({
  children,
  onClose,
}: {
  children: React.ReactNode;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-goal-title"
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      {children}
    </div>
  );
}
