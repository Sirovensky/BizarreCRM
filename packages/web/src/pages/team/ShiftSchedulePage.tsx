/**
 * Weekly shift schedule — criticalaudit.md §53 idea #1.
 *
 * Renders a 7-column day grid for the current week. Click an empty cell to
 * add a shift; click a populated row to edit. Time-off requests visible in a
 * sidebar with one-click approve/deny for managers.
 *
 * Drag-drop is intentionally NOT implemented in v1 — too much overhead for an
 * MVP. The CRUD is in place so a follow-up can layer dnd on top.
 */
import { type ReactNode, type RefObject, useMemo, useState } from 'react';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useEscClose } from '@/hooks/useEscClose';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Loader2, X, Check } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { useAuthStore } from '@/stores/authStore';
import { extractApiError } from '@/utils/apiError';
import { dstSpringForwardAnomaly } from '@/utils/format';

interface Shift {
  id: number;
  user_id: number;
  start_at: string;
  end_at: string;
  role: string | null;
  notes: string | null;
  status: string;
  first_name: string | null;
  last_name: string | null;
}

interface TimeOffRow {
  id: number;
  user_id: number;
  start_date: string;
  end_date: string;
  reason: string | null;
  status: 'pending' | 'approved' | 'denied' | 'cancelled';
  first_name: string | null;
  last_name: string | null;
}

interface Employee {
  id: number;
  first_name: string;
  last_name: string;
}

function startOfWeek(d: Date): Date {
  const date = new Date(d);
  const day = date.getDay();
  const diff = date.getDate() - day + (day === 0 ? -6 : 1);
  date.setHours(0, 0, 0, 0);
  date.setDate(diff);
  return date;
}

export function ShiftSchedulePage() {
  const queryClient = useQueryClient();
  const userRole = useAuthStore((s) => s.user?.role);
  const canManageSchedule = userRole === 'admin' || userRole === 'manager';
  const [weekStart, setWeekStart] = useState<Date>(() => startOfWeek(new Date()));
  const [showNew, setShowNew] = useState(false);
  const [showAllTimeOff, setShowAllTimeOff] = useState(false);
  const TIME_OFF_PREVIEW = 5;
  const [newUserId, setNewUserId] = useState<number | ''>('');
  const [newStart, setNewStart] = useState('');
  const [newEnd, setNewEnd] = useState('');
  const [newRole, setNewRole] = useState('');

  const weekEnd = useMemo(() => {
    const d = new Date(weekStart);
    d.setDate(d.getDate() + 7);
    return d;
  }, [weekStart]);

  const { data: shiftsData } = useQuery({
    queryKey: ['team', 'shifts', weekStart.toISOString()],
    queryFn: async () => {
      const params = new URLSearchParams({
        from: weekStart.toISOString(),
        to: weekEnd.toISOString(),
      });
      const res = await api.get<{ success: boolean; data: Shift[] }>(`/team/shifts?${params}`);
      return res.data.data;
    },
  });
  const shifts: Shift[] = shiftsData || [];

  const { data: timeOffData } = useQuery({
    queryKey: ['team', 'time-off', 'pending'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: TimeOffRow[] }>('/team/time-off?status=pending');
      return res.data.data;
    },
  });
  const timeOffPending: TimeOffRow[] = timeOffData || [];

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
      if (!canManageSchedule) throw new Error('Only admins and managers can create shifts');
      // datetime-local values are local-time strings with no TZ offset; convert
      // to UTC ISO before sending so the server stores canonical UTC regardless
      // of the user's timezone or DST offset.
      const startD = new Date(newStart);
      const endD = new Date(newEnd);
      // WEB-UIUX-781: reject DST spring-forward non-existent local times so
      // a shift that supposedly starts 02:30 doesn't silently land at 03:30.
      if (dstSpringForwardAnomaly(newStart, startD) === 'nonexistent') {
        throw new Error('Shift start time does not exist on the selected date (daylight-saving spring forward). Pick a different time.');
      }
      if (dstSpringForwardAnomaly(newEnd, endD) === 'nonexistent') {
        throw new Error('Shift end time does not exist on the selected date (daylight-saving spring forward). Pick a different time.');
      }
      const res = await api.post('/team/shifts', {
        user_id: Number(newUserId),
        start_at: startD.toISOString(),
        end_at: endD.toISOString(),
        role: newRole || null,
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Shift created');
      queryClient.invalidateQueries({ queryKey: ['team', 'shifts'] });
      setShowNew(false);
      setNewUserId('');
      setNewStart('');
      setNewEnd('');
      setNewRole('');
    },
    onError: (e: unknown) => toast.error(extractApiError(e).message || 'Failed to create shift'),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: number) => {
      if (!canManageSchedule) throw new Error('Only admins and managers can delete shifts');
      await api.delete(`/team/shifts/${id}`);
    },
    onSuccess: () => {
      toast.success('Shift deleted');
      queryClient.invalidateQueries({ queryKey: ['team', 'shifts'] });
    },
    onError: (e: unknown) => toast.error(extractApiError(e).message || 'Failed to delete shift'),
  });

  const reviewMut = useMutation({
    mutationFn: async ({ id, status }: { id: number; status: 'approved' | 'denied' }) => {
      if (!canManageSchedule) throw new Error('Only admins and managers can review time-off');
      await api.put(`/team/time-off/${id}`, { status });
    },
    onSuccess: (_data, vars) => {
      toast.success(`Time-off ${vars.status}`);
      queryClient.invalidateQueries({ queryKey: ['team', 'time-off', 'pending'] });
    },
    onError: (e: unknown) => toast.error(extractApiError(e).message || 'Failed to update time-off'),
  });

  const days = useMemo(() => {
    const out: Date[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart);
      d.setDate(d.getDate() + i);
      out.push(d);
    }
    return out;
  }, [weekStart]);

  const shiftsByDay = useMemo(() => {
    const map = new Map<string, Shift[]>();
    for (const s of shifts) {
      const key = new Date(s.start_at).toDateString();
      const arr = map.get(key) || [];
      arr.push(s);
      map.set(key, arr);
    }
    return map;
  }, [shifts]);

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <header className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-surface-800 dark:text-surface-100">Shift Schedule</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">Week of {weekStart.toLocaleDateString()}</p>
        </div>
        <div className="flex gap-2">
          <button
            className="px-3 py-1.5 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded text-sm text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700"
            aria-label="Previous week"
            onClick={() => {
              const d = new Date(weekStart);
              d.setDate(d.getDate() - 7);
              setWeekStart(d);
            }}
          >
            ← Prev
          </button>
          <button
            className="px-3 py-1.5 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded text-sm text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700"
            aria-label="This week"
            onClick={() => setWeekStart(startOfWeek(new Date()))}
          >
            This week
          </button>
          <button
            className="px-3 py-1.5 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded text-sm text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700"
            aria-label="Next week"
            onClick={() => {
              const d = new Date(weekStart);
              d.setDate(d.getDate() + 7);
              setWeekStart(d);
            }}
          >
            Next →
          </button>
          {canManageSchedule ? (
            <button
              className="px-3 py-1.5 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center"
              onClick={() => setShowNew(true)}
            >
              <Plus className="w-4 h-4 mr-1" /> New shift
            </button>
          ) : null}
        </div>
      </header>
      {!canManageSchedule && (
        <div className="mb-4 rounded-md border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 px-4 py-3 text-sm text-surface-700 dark:text-surface-200">
          You can view the schedule and pending time-off requests. Shift and time-off changes are limited to admins and managers.
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_280px] gap-6">
        <div className="bg-white dark:bg-surface-900 rounded-lg shadow border border-surface-200 dark:border-surface-700 overflow-hidden">
          <div className="grid grid-cols-7 border-b border-surface-200 bg-surface-50 text-xs font-semibold uppercase text-surface-600 dark:border-surface-700 dark:bg-surface-800/50 dark:text-surface-300">
            {days.map((d) => (
              <div key={d.toISOString()} className="px-3 py-2 border-r border-surface-200 last:border-r-0 dark:border-surface-700">
                {d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}
              </div>
            ))}
          </div>
          <div className="grid grid-cols-7 min-h-[280px]">
            {days.map((d) => {
              const dayShifts = shiftsByDay.get(d.toDateString()) || [];
              return (
                <div key={d.toISOString()} className="border-r border-surface-200 last:border-r-0 p-2 space-y-1 dark:border-surface-700">
                  {dayShifts.length === 0 && (
                    <div className="text-xs text-surface-300 dark:text-surface-600 text-center py-4">no shifts</div>
                  )}
                  {dayShifts.map((s) => (
                    <div key={s.id} className="bg-primary-50 border border-primary-200 rounded p-2 text-xs dark:border-primary-500/30 dark:bg-primary-500/10">
                      <div className="font-semibold text-primary-800 truncate dark:text-primary-200">
                        {s.first_name} {s.last_name}
                      </div>
                      <div className="text-primary-600 dark:text-primary-300">
                        {new Date(s.start_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        {' - '}
                        {new Date(s.end_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </div>
                      {s.role && <div className="text-primary-500 truncate dark:text-primary-400">{s.role}</div>}
                      {canManageSchedule ? (
                        <button
                          className="text-red-500 hover:text-red-700 mt-1 inline-flex items-center dark:text-red-400 dark:hover:text-red-300 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                          onClick={() => {
                            if (window.confirm('Delete this shift? Cannot be undone.')) {
                              deleteMut.mutate(s.id);
                            }
                          }}
                          disabled={deleteMut.isPending && deleteMut.variables === s.id}
                          aria-label={`Remove shift for ${s.first_name ?? ''} ${s.last_name ?? ''}`}
                        >
                          <X className="w-3 h-3 mr-0.5" /> remove
                        </button>
                      ) : null}
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
        </div>

        <aside className="space-y-4">
          <div className="bg-white dark:bg-surface-900 rounded-lg shadow border border-surface-200 dark:border-surface-700 p-4">
            <h2 className="text-sm font-semibold text-surface-800 dark:text-surface-100 mb-3">
              Pending time-off
              {timeOffPending.length > 0 && (
                <span className="ml-1.5 text-xs font-normal text-surface-400 dark:text-surface-500">
                  ({timeOffPending.length})
                </span>
              )}
            </h2>
            {timeOffPending.length === 0 && (
              <p className="text-xs text-surface-500 dark:text-surface-400">No pending requests.</p>
            )}
            <div className="max-h-80 overflow-y-auto -mx-1 px-1">
              {(showAllTimeOff ? timeOffPending : timeOffPending.slice(0, TIME_OFF_PREVIEW)).map((r) => (
                <div key={r.id} className="border-b border-surface-200 last:border-b-0 py-2 text-xs dark:border-surface-700">
                  <div className="font-semibold text-surface-800 dark:text-surface-100">
                    {r.first_name} {r.last_name}
                  </div>
                  <div className="text-surface-500 dark:text-surface-400">
                    {r.start_date} → {r.end_date}
                  </div>
                  {r.reason && <div className="text-surface-600 dark:text-surface-300 italic mt-1 line-clamp-2">{r.reason}</div>}
                  {canManageSchedule ? (
                    <div className="flex gap-2 mt-2">
                      <button
                        className="flex-1 bg-green-600 text-white rounded px-2 py-1 inline-flex items-center justify-center hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                        onClick={() => reviewMut.mutate({ id: r.id, status: 'approved' })}
                        disabled={reviewMut.isPending && reviewMut.variables?.id === r.id}
                      >
                        <Check className="w-3 h-3 mr-1" /> Approve
                      </button>
                      <button
                        className="flex-1 bg-red-600 text-white rounded px-2 py-1 inline-flex items-center justify-center hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                        onClick={() => reviewMut.mutate({ id: r.id, status: 'denied' })}
                        disabled={reviewMut.isPending && reviewMut.variables?.id === r.id}
                      >
                        <X className="w-3 h-3 mr-1" /> Deny
                      </button>
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
            {timeOffPending.length > TIME_OFF_PREVIEW && (
              <button
                className="mt-2 w-full text-xs text-primary-600 dark:text-primary-400 hover:underline text-center"
                onClick={() => setShowAllTimeOff((v) => !v)}
              >
                {showAllTimeOff
                  ? `Show ${TIME_OFF_PREVIEW}`
                  : `Show all ${timeOffPending.length}`}
              </button>
            )}
          </div>
        </aside>
      </div>

      {showNew && (
        <NewShiftModal open={showNew} onClose={() => setShowNew(false)}>
          <div className="bg-white dark:bg-surface-900 rounded-lg shadow-xl max-w-md w-full p-5 text-surface-900 dark:text-surface-100" onClick={(e) => e.stopPropagation()}>
            <h2 id="new-shift-title" className="text-lg font-bold mb-4">New shift</h2>
            <div className="space-y-3">
              <label className="block">
                <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Employee</span>
                <select
                  className="mt-1 w-full border border-surface-300 bg-white rounded px-2 py-1.5 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
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
                <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Start</span>
                <input
                  type="datetime-local"
                  className="mt-1 w-full border border-surface-300 bg-white rounded px-2 py-1.5 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                  value={newStart}
                  onChange={(e) => setNewStart(e.target.value)}
                />
              </label>
              <label className="block">
                <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">End</span>
                <input
                  type="datetime-local"
                  className="mt-1 w-full border border-surface-300 bg-white rounded px-2 py-1.5 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                  value={newEnd}
                  onChange={(e) => setNewEnd(e.target.value)}
                />
              </label>
              <p className="text-xs text-surface-400 dark:text-surface-500">
                Times in your local time ({Intl.DateTimeFormat().resolvedOptions().timeZone})
              </p>
              <label className="block">
                <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Role (optional)</span>
                <input
                  type="text"
                  className="mt-1 w-full border border-surface-300 bg-white rounded px-2 py-1.5 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100 dark:placeholder:text-surface-500"
                  value={newRole}
                  onChange={(e) => setNewRole(e.target.value)}
                  placeholder="e.g. Bench tech"
                />
              </label>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                className="flex-1 px-3 py-2 border border-surface-200 dark:border-surface-700 rounded text-sm text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-800"
                onClick={() => setShowNew(false)}
                disabled={createMut.isPending}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center justify-center"
                disabled={!newUserId || !newStart || !newEnd || createMut.isPending}
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                Save
              </button>
            </div>
          </div>
        </NewShiftModal>
      )}

    </div>
  );
}

// NewShiftModal — wraps the shift form in a backdrop with Esc + click-outside
// dismissal so keyboard users aren't trapped and a misclick can't strand them
// inside a transparent overlay (criticalaudit.md §53 a11y pass).
function NewShiftModal({
  children,
  onClose,
  open,
}: {
  children: ReactNode;
  onClose: () => void;
  open: boolean;
}) {
  const trapRef = useFocusTrap(open, { initialFocusSelector: 'input,select' });
  useEscClose(onClose, open);
  return (
    <div
      ref={trapRef as RefObject<HTMLDivElement>}
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-shift-title"
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      {children}
    </div>
  );
}
