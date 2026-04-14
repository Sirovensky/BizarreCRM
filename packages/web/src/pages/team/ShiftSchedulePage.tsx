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
import { useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Loader2, X, Check } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { useAuthStore } from '@/stores/authStore';

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
      const res = await api.post('/team/shifts', {
        user_id: Number(newUserId),
        start_at: newStart,
        end_at: newEnd,
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
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to create shift'),
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
    onError: (e: any) => toast.error(e?.response?.data?.error || e?.message || 'Failed to delete shift'),
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
    onError: (e: any) => toast.error(e?.response?.data?.error || e?.message || 'Failed to update time-off'),
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
          <h1 className="text-2xl font-bold text-gray-800">Shift Schedule</h1>
          <p className="text-sm text-gray-500">Week of {weekStart.toLocaleDateString()}</p>
        </div>
        <div className="flex gap-2">
          <button
            className="px-3 py-1.5 bg-white border rounded text-sm hover:bg-gray-50"
            onClick={() => {
              const d = new Date(weekStart);
              d.setDate(d.getDate() - 7);
              setWeekStart(d);
            }}
          >
            ← Prev
          </button>
          <button
            className="px-3 py-1.5 bg-white border rounded text-sm hover:bg-gray-50"
            onClick={() => setWeekStart(startOfWeek(new Date()))}
          >
            This week
          </button>
          <button
            className="px-3 py-1.5 bg-white border rounded text-sm hover:bg-gray-50"
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
              className="px-3 py-1.5 bg-blue-600 text-white rounded text-sm hover:bg-blue-700 inline-flex items-center"
              onClick={() => setShowNew(true)}
            >
              <Plus className="w-4 h-4 mr-1" /> New shift
            </button>
          ) : null}
        </div>
      </header>
      {!canManageSchedule && (
        <div className="mb-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700">
          You can view the schedule and pending time-off requests. Shift and time-off changes are limited to admins and managers.
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_280px] gap-6">
        <div className="bg-white rounded-lg shadow border overflow-hidden">
          <div className="grid grid-cols-7 border-b text-xs font-semibold uppercase text-gray-600">
            {days.map((d) => (
              <div key={d.toISOString()} className="px-3 py-2 border-r last:border-r-0">
                {d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}
              </div>
            ))}
          </div>
          <div className="grid grid-cols-7 min-h-[280px]">
            {days.map((d) => {
              const dayShifts = shiftsByDay.get(d.toDateString()) || [];
              return (
                <div key={d.toISOString()} className="border-r last:border-r-0 p-2 space-y-1">
                  {dayShifts.length === 0 && (
                    <div className="text-xs text-gray-300 text-center py-4">no shifts</div>
                  )}
                  {dayShifts.map((s) => (
                    <div key={s.id} className="bg-blue-50 border border-blue-200 rounded p-2 text-xs">
                      <div className="font-semibold text-blue-800 truncate">
                        {s.first_name} {s.last_name}
                      </div>
                      <div className="text-blue-600">
                        {new Date(s.start_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        {' - '}
                        {new Date(s.end_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </div>
                      {s.role && <div className="text-blue-500 truncate">{s.role}</div>}
                      {canManageSchedule ? (
                        <button
                          className="text-red-500 hover:text-red-700 mt-1 inline-flex items-center disabled:opacity-40"
                          onClick={() => deleteMut.mutate(s.id)}
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
          <div className="bg-white rounded-lg shadow border p-4">
            <h2 className="text-sm font-semibold text-gray-800 mb-3">Pending time-off</h2>
            {timeOffPending.length === 0 && (
              <p className="text-xs text-gray-500">No pending requests.</p>
            )}
            {timeOffPending.map((r) => (
              <div key={r.id} className="border-b last:border-b-0 py-2 text-xs">
                <div className="font-semibold text-gray-800">
                  {r.first_name} {r.last_name}
                </div>
                <div className="text-gray-500">
                  {r.start_date} → {r.end_date}
                </div>
                {r.reason && <div className="text-gray-600 italic mt-1 line-clamp-2">{r.reason}</div>}
                {canManageSchedule ? (
                  <div className="flex gap-2 mt-2">
                    <button
                      className="flex-1 bg-green-600 text-white rounded px-2 py-1 inline-flex items-center justify-center hover:bg-green-700 disabled:opacity-50"
                      onClick={() => reviewMut.mutate({ id: r.id, status: 'approved' })}
                      disabled={reviewMut.isPending && reviewMut.variables?.id === r.id}
                    >
                      <Check className="w-3 h-3 mr-1" /> Approve
                    </button>
                    <button
                      className="flex-1 bg-red-600 text-white rounded px-2 py-1 inline-flex items-center justify-center hover:bg-red-700 disabled:opacity-50"
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
        </aside>
      </div>

      {showNew && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5">
            <h2 className="text-lg font-bold mb-4">New shift</h2>
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
                <span className="text-xs font-semibold text-gray-600">Start</span>
                <input
                  type="datetime-local"
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newStart}
                  onChange={(e) => setNewStart(e.target.value)}
                />
              </label>
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">End</span>
                <input
                  type="datetime-local"
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newEnd}
                  onChange={(e) => setNewEnd(e.target.value)}
                />
              </label>
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Role (optional)</span>
                <input
                  type="text"
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newRole}
                  onChange={(e) => setNewRole(e.target.value)}
                  placeholder="e.g. Bench tech"
                />
              </label>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-gray-50"
                onClick={() => setShowNew(false)}
                disabled={createMut.isPending}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700 inline-flex items-center justify-center"
                disabled={!newUserId || !newStart || !newEnd || createMut.isPending}
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
