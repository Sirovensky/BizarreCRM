import { type FormEvent, useState, useMemo, useCallback, useEffect, Fragment } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Calendar, ChevronLeft, ChevronRight, Plus, X, Clock,
  User, Loader2, Edit3, Ban, Trash2,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { leadApi, settingsApi, customerApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { useSettings } from '@/hooks/useSettings';
import { formatTime } from '@/utils/format';
import { formatApiError } from '@/utils/apiError';

// ─── Types ───────────────────────────────────────────────────────
interface Appointment {
  id: number;
  lead_id: number | null;
  customer_id: number | null;
  title: string;
  start_time: string;
  end_time: string | null;
  assigned_to: number | null;
  status: string;
  notes: string | null;
  no_show?: number | boolean | null;
  customer_first_name?: string;
  customer_last_name?: string;
  assigned_first_name?: string;
  assigned_last_name?: string;
  lead_order_id?: string;
}

type ViewMode = 'month' | 'week' | 'day';

// ─── TZ-aware time formatter ─────────────────────────────────────
// WEB-UIUX-780: format a time string in the shop's configured timezone so
// a receptionist in a different TZ sees the correct local time for the shop.
function formatTimeTz(iso: string | Date | null | undefined, tz?: string): string {
  if (iso == null) return '—';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d.getTime())) return '—';
  const opts: Intl.DateTimeFormatOptions = { hour: 'numeric', minute: '2-digit' };
  if (tz) {
    try { opts.timeZone = tz; } catch { /* invalid tz — fall back to browser */ }
  }
  return d.toLocaleTimeString(undefined, opts);
}

// ─── Constants ───────────────────────────────────────────────────
const STATUS_COLORS: Record<string, string> = {
  scheduled: '#3b82f6',
  confirmed: '#22c55e',
  completed: '#6b7280',
  cancelled: '#ef4444',
  'no-show': '#f59e0b',
};

// WEB-UIUX-1335: explicit label map so "no-show" renders "No-Show" (not "No-show"
// from CSS `capitalize` which only uppercases the first letter of the whole string).
const STATUS_LABELS: Record<string, string> = {
  scheduled: 'Scheduled',
  confirmed: 'Confirmed',
  completed: 'Completed',
  cancelled: 'Cancelled',
  'no-show': 'No-Show',
};

const APPOINTMENT_STATUS_OPTIONS = [
  { value: 'scheduled', label: 'Scheduled' },
  { value: 'confirmed', label: 'Confirmed' },
  { value: 'completed', label: 'Completed' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'no-show', label: 'No-show' },
];

const BASE_MINUTE_OPTIONS = ['00', '15', '30', '45'];

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
// Default business-hours range when no store setting is present.
// CalendarPage now overrides via `calendar_start_hour` / `calendar_end_hour`
// settings (FA-L9) — passed down to DayView/WeekView as a prop.
const DEFAULT_HOURS = Array.from({ length: 13 }, (_, i) => i + 7); // 7am to 7pm

function getStatusColor(status: string) {
  return STATUS_COLORS[status] || '#6b7280';
}

// WEB-UIUX-1335: use STATUS_LABELS map for correct casing ("No-Show" not "No-show").
function formatStatus(status: string) {
  return STATUS_LABELS[status] ?? APPOINTMENT_STATUS_OPTIONS.find((option) => option.value === status)?.label ?? status;
}

function formatDateShort(date: Date) {
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function isSameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// WEB-FF-025 (Fixer-TTT 2026-04-25): build a YYYY-MM-DD key once so the month
// grid can do an O(1) Map lookup per cell instead of filtering every
// appointment 42× per render. On a busy month with 500 appts this drops
// 21k Date constructions per render to ~500 (one per appt).
function dayKey(d: Date) {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function startOfWeek(date: Date) {
  const d = new Date(date);
  d.setDate(d.getDate() - d.getDay());
  d.setHours(0, 0, 0, 0);
  return d;
}

function addDays(date: Date, n: number) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

function toDateInputValue(date: Date) {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function timeParts(date: Date) {
  return {
    hour: String(date.getHours()).padStart(2, '0'),
    min: String(date.getMinutes()).padStart(2, '0'),
  };
}

function editFormFromAppointment(appointment: Appointment) {
  const start = new Date(appointment.start_time);
  const safeStart = Number.isFinite(start.getTime()) ? start : new Date();
  const parsedEnd = appointment.end_time ? new Date(appointment.end_time) : null;
  const safeEnd = parsedEnd && Number.isFinite(parsedEnd.getTime())
    ? parsedEnd
    : new Date(safeStart.getTime() + 60 * 60 * 1000);
  const startParts = timeParts(safeStart);
  const endParts = timeParts(safeEnd);

  return {
    title: appointment.title || '',
    start_date: toDateInputValue(safeStart),
    start_hour: startParts.hour,
    start_min: startParts.min,
    end_hour: endParts.hour,
    end_min: endParts.min,
    assigned_to: appointment.assigned_to ? String(appointment.assigned_to) : '',
    status: appointment.no_show ? 'no-show' : (appointment.status || 'scheduled'),
    notes: appointment.notes || '',
  };
}

function minuteOptions(...mins: string[]) {
  return Array.from(new Set([...BASE_MINUTE_OPTIONS, ...mins])).sort();
}

type AppointmentEditForm = ReturnType<typeof editFormFromAppointment>;
type UpdateAppointmentPayload = Omit<Parameters<typeof leadApi.updateAppointment>[1], 'assigned_to' | 'notes'> & {
  assigned_to?: number | null;
  notes?: string | null;
  title?: string;
  status?: string;
  no_show?: boolean;
};

// ─── Appointment Detail Modal ────────────────────────────────────
function AppointmentDetailModal({
  appointment,
  onClose,
  users,
  existingAppointments,
  onAppointmentUpdated,
  shopTz,
}: {
  appointment: Appointment;
  onClose: () => void;
  users: { id: number; first_name: string; last_name: string }[];
  existingAppointments: Appointment[];
  onAppointmentUpdated: (appointment: Appointment) => void;
  shopTz?: string;
}) {
  const queryClient = useQueryClient();
  const displayStatus = appointment.no_show ? 'no-show' : appointment.status;
  const color = getStatusColor(displayStatus);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<AppointmentEditForm>(() => editFormFromAppointment(appointment));
  const [confirmAction, setConfirmAction] = useState<'cancel' | 'delete' | null>(null);
  const [overlapWarning, setOverlapWarning] = useState<string | null>(null);

  useEffect(() => {
    setEditing(false);
    setForm(editFormFromAppointment(appointment));
    setConfirmAction(null);
    setOverlapWarning(null);
  }, [appointment]);

  const updateMut = useMutation({
    mutationFn: (data: UpdateAppointmentPayload) =>
      leadApi.updateAppointment(appointment.id, data as Parameters<typeof leadApi.updateAppointment>[1]),
    onSuccess: (res, variables) => {
      const updated = res.data?.data ?? {};
      const assignedUser = variables.assigned_to
        ? users.find((u) => u.id === variables.assigned_to)
        : null;
      onAppointmentUpdated({
        ...appointment,
        ...updated,
        ...(Object.prototype.hasOwnProperty.call(variables, 'assigned_to')
          ? {
            assigned_first_name: assignedUser?.first_name,
            assigned_last_name: assignedUser?.last_name,
          }
          : {}),
      });
      queryClient.invalidateQueries({ queryKey: ['appointments'] });
      toast.success('Appointment updated');
      setEditing(false);
      setConfirmAction(null);
      setOverlapWarning(null);
    },
    onError: (err: unknown) => toast.error(formatApiError(err) || 'Failed to update appointment'),
  });

  const deleteMut = useMutation({
    mutationFn: () => leadApi.deleteAppointment(appointment.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['appointments'] });
      toast.success('Appointment removed');
      setConfirmAction(null);
      onClose();
    },
    onError: (err: unknown) => toast.error(formatApiError(err) || 'Failed to remove appointment'),
  });

  // Esc closes the appointment-detail dialog so keyboard users aren't trapped.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || confirmAction) return;
      if (editing) {
        setEditing(false);
        setForm(editFormFromAppointment(appointment));
        setOverlapWarning(null);
        return;
      }
      onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [appointment, confirmAction, editing, onClose]);

  function checkOverlap(startIso: string, endIso: string, assignedUserId: number | null): string | null {
    if (!assignedUserId) return null;
    const start = new Date(startIso).getTime();
    const end = new Date(endIso).getTime();
    const conflict = existingAppointments.find((a) => {
      if (a.id === appointment.id || a.assigned_to !== assignedUserId || a.status === 'cancelled') return false;
      const aStart = new Date(a.start_time).getTime();
      const aEnd = a.end_time ? new Date(a.end_time).getTime() : aStart + 3600_000;
      return start < aEnd && end > aStart;
    });
    if (!conflict) return null;
    const name = users.find((u) => u.id === assignedUserId);
    const assigneeName = name ? `${name.first_name} ${name.last_name}` : 'this person';
    return `${assigneeName} already has "${conflict.title || 'an appointment'}" overlapping this time slot.`;
  }

  // WEB-UIUX-1324: cross-viewport overlap check. The local `existingAppointments`
  // array is just the viewport; this asks the server for any conflicting appt
  // for the same assignee anywhere in their calendar. Run on submit (not on
  // every keystroke) so we trade one extra round-trip per save for a true
  // cross-window guarantee.
  async function checkOverlapCrossWindow(
    startIso: string,
    endIso: string,
    assignedUserId: number | null,
    excludeId: number,
  ): Promise<string | null> {
    if (!assignedUserId) return null;
    try {
      const res = await leadApi.getAppointmentOverlaps({
        assigned_to: assignedUserId,
        start_time: startIso,
        end_time: endIso,
        exclude_id: excludeId,
      });
      const overlaps = res.data?.data?.overlaps ?? [];
      if (overlaps.length === 0) return null;
      const conflict = overlaps[0];
      const name = users.find((u) => u.id === assignedUserId);
      const assigneeName = name ? `${name.first_name} ${name.last_name}` : 'this person';
      return `${assigneeName} already has "${conflict.title || 'an appointment'}" overlapping this time slot (outside the current view).`;
    } catch {
      // Best-effort — if the cross-window check fails we still let the
      // server-side POST guard catch it; don't block the operator.
      return null;
    }
  }

  function updateAppointment(data: UpdateAppointmentPayload) {
    updateMut.mutate(data);
  }

  async function handleSave(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const startTime = toISOWithOffset(form.start_date, form.start_hour, form.start_min);
    const endTime = toISOWithOffset(form.start_date, form.end_hour, form.end_min);
    if (endTime <= startTime) {
      toast.error('End time must be after start time');
      return;
    }
    const assignedId = form.assigned_to ? Number(form.assigned_to) : null;
    // Local-viewport first (cheap), cross-window if local clears (WEB-UIUX-1324).
    const warn =
      checkOverlap(startTime, endTime, assignedId)
      ?? await checkOverlapCrossWindow(startTime, endTime, assignedId, appointment.id);
    if (warn && !overlapWarning) {
      setOverlapWarning(warn);
      return;
    }
    setOverlapWarning(null);
    updateAppointment({
      title: form.title.trim(),
      start_time: startTime,
      end_time: endTime,
      assigned_to: assignedId,
      status: form.status as 'scheduled' | 'confirmed' | 'completed' | 'cancelled' | 'no-show',
      notes: form.notes.trim() ? form.notes : null,
      no_show: form.status === 'no-show',
    });
  }

  const detail = (
    <div className="space-y-4 px-6 py-4">
      <div>
        <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Title</p>
        <p className="text-surface-900 dark:text-surface-100">{appointment.title || 'Untitled'}</p>
      </div>
      <div className="flex gap-6">
        <div>
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Time</p>
          <p className="inline-flex items-center gap-1.5 text-surface-900 dark:text-surface-100">
            <Clock className="h-4 w-4 text-surface-400" />
            {formatTimeTz(appointment.start_time, shopTz)}
            {appointment.end_time && ` - ${formatTimeTz(appointment.end_time, shopTz)}`}
            {/* WEB-UIUX-1333: show the timezone in effect next to the time */}
            <span className="ml-1 text-xs text-surface-400 dark:text-surface-500">
              {shopTz ?? Intl.DateTimeFormat().resolvedOptions().timeZone}
            </span>
          </p>
        </div>
        <div>
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Status</p>
          <span
            className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium"
            style={{ backgroundColor: `${color}18`, color }}
          >
            <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
            {formatStatus(displayStatus)}
          </span>
        </div>
      </div>
      {(appointment.customer_first_name || appointment.customer_last_name) && (
        <div>
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Customer</p>
          <p className="inline-flex items-center gap-1.5 text-surface-900 dark:text-surface-100">
            <User className="h-4 w-4 text-surface-400" />
            {appointment.customer_first_name} {appointment.customer_last_name}
          </p>
        </div>
      )}
      {(appointment.assigned_first_name || appointment.assigned_last_name) && (
        <div>
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Assigned To</p>
          <p className="text-surface-900 dark:text-surface-100">
            {appointment.assigned_first_name} {appointment.assigned_last_name}
          </p>
        </div>
      )}
      {appointment.lead_order_id && (
        <div>
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Lead</p>
          <p className="text-primary-600 dark:text-primary-400">{appointment.lead_order_id}</p>
        </div>
      )}
      {appointment.notes && (
        <div>
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Notes</p>
          <p className="text-surface-700 dark:text-surface-300 whitespace-pre-wrap">{appointment.notes}</p>
        </div>
      )}
      <div className="flex flex-wrap gap-2 border-t border-surface-200 pt-4 dark:border-surface-700">
        <button
          type="button"
          onClick={() => setEditing(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-3 py-2 text-sm font-medium text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
        >
          <Edit3 className="h-4 w-4" />
          Edit / Reschedule
        </button>
        {displayStatus !== 'cancelled' && (
          <button
            type="button"
            disabled={updateMut.isPending}
            onClick={() => setConfirmAction('cancel')}
            className="inline-flex items-center gap-2 rounded-lg border border-amber-300 px-3 py-2 text-sm font-medium text-amber-700 transition-colors hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-amber-700 dark:text-amber-300 dark:hover:bg-amber-950/30"
          >
            <Ban className="h-4 w-4" />
            Cancel Appointment
          </button>
        )}
        {displayStatus !== 'no-show' && (
          <button
            type="button"
            disabled={updateMut.isPending}
            onClick={() => updateAppointment({ status: 'no-show', no_show: true })}
            className="rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
          >
            Mark No-show
          </button>
        )}
        <button
          type="button"
          disabled={deleteMut.isPending}
          onClick={() => setConfirmAction('delete')}
          className="ml-auto inline-flex items-center gap-2 rounded-lg border border-error-300 px-3 py-2 text-sm font-medium text-error-700 transition-colors hover:bg-error-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-error-700 dark:text-error-300 dark:hover:bg-error-950/30"
        >
          <Trash2 className="h-4 w-4" />
          Remove
        </button>
      </div>
    </div>
  );

  const edit = (
    <form className="space-y-4 px-6 py-4" onSubmit={handleSave}>
      <div>
        <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Title *</label>
        <input
          required
          value={form.title}
          onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
          className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Date</label>
        <input
          type="date"
          value={form.start_date}
          onChange={(e) => setForm((f) => ({ ...f, start_date: e.target.value }))}
          className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
        />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Start Time</label>
          <div className="flex gap-1">
            <select
              value={form.start_hour}
              onChange={(e) => setForm((f) => ({ ...f, start_hour: e.target.value }))}
              className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            >
              {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0')).map((h) => {
                const n = Number(h);
                const label = `${((n % 12) || 12)} ${n < 12 ? 'AM' : 'PM'}`;
                return <option key={h} value={h}>{label}</option>;
              })}
            </select>
            <span className="flex items-center text-surface-400">:</span>
            <select
              value={form.start_min}
              onChange={(e) => setForm((f) => ({ ...f, start_min: e.target.value }))}
              className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            >
              {minuteOptions(form.start_min).map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </div>
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">End Time</label>
          <div className="flex gap-1">
            <select
              value={form.end_hour}
              onChange={(e) => setForm((f) => ({ ...f, end_hour: e.target.value }))}
              className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            >
              {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0')).map((h) => {
                const n = Number(h);
                const label = `${((n % 12) || 12)} ${n < 12 ? 'AM' : 'PM'}`;
                return <option key={h} value={h}>{label}</option>;
              })}
            </select>
            <span className="flex items-center text-surface-400">:</span>
            <select
              value={form.end_min}
              onChange={(e) => setForm((f) => ({ ...f, end_min: e.target.value }))}
              className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            >
              {minuteOptions(form.end_min).map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </div>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Assigned To</label>
          <select
            value={form.assigned_to}
            onChange={(e) => setForm((f) => ({ ...f, assigned_to: e.target.value }))}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
          >
            <option value="">Unassigned</option>
            {users.map((u) => (
              <option key={u.id} value={u.id}>{u.first_name} {u.last_name}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Status</label>
          <select
            value={form.status}
            onChange={(e) => setForm((f) => ({ ...f, status: e.target.value }))}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
          >
            {APPOINTMENT_STATUS_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
          </select>
        </div>
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Notes</label>
        <textarea
          value={form.notes}
          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
          rows={3}
          className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
        />
      </div>
      {overlapWarning && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-400">
          <strong>Scheduling conflict:</strong> {overlapWarning} Save again to keep this time anyway.
        </div>
      )}
      <div className="flex justify-end gap-3 pt-2">
        <button
          type="button"
          onClick={() => {
            setEditing(false);
            setForm(editFormFromAppointment(appointment));
            setOverlapWarning(null);
          }}
          className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
        >
          Back
        </button>
        <button
          type="submit"
          disabled={updateMut.isPending}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 shadow-sm hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none"
        >
          {updateMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          {overlapWarning ? 'Save Anyway' : 'Save Changes'}
        </button>
      </div>
    </form>
  );

  return (
    <>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="appointment-detail-title"
        className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
        onClick={onClose}
      >
        <div
          className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl bg-white shadow-xl dark:bg-surface-800"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
            <h2 id="appointment-detail-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
              {editing ? 'Edit Appointment' : 'Appointment Details'}
            </h2>
            <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
              <X className="h-5 w-5" />
            </button>
          </div>
          {editing ? edit : detail}
        </div>
      </div>
      <ConfirmDialog
        open={confirmAction === 'cancel'}
        title="Cancel appointment?"
        message="This keeps the appointment on the calendar history and changes its status to cancelled."
        confirmLabel={updateMut.isPending ? 'Cancelling...' : 'Cancel appointment'}
        danger
        onCancel={() => setConfirmAction(null)}
        onConfirm={() => {
          if (!updateMut.isPending) updateAppointment({ status: 'cancelled', no_show: false });
        }}
      />
      <ConfirmDialog
        open={confirmAction === 'delete'}
        title="Remove appointment?"
        message="This removes the appointment from the active calendar. Use this only for duplicate or mistaken appointments."
        confirmLabel={deleteMut.isPending ? 'Removing...' : 'Remove'}
        danger
        onCancel={() => setConfirmAction(null)}
        onConfirm={() => {
          if (!deleteMut.isPending) deleteMut.mutate();
        }}
      />
    </>
  );
}

// WEB-FK-015: convert a "YYYY-MM-DD", hour, minute triple to a UTC ISO string
// using the browser's local timezone. The naive string (no offset) would be
// interpreted differently by different browsers / server parsers — attaching
// the local offset makes the intent unambiguous for SQLite datetime storage.
function toISOWithOffset(dateStr: string, hour: string, min: string): string {
  const local = new Date(`${dateStr}T${hour}:${min}:00`);
  // toISOString() is UTC; we want the same instant with local-tz offset embedded.
  // Build ±HH:MM offset string manually from getTimezoneOffset().
  const off = -local.getTimezoneOffset(); // minutes, positive = ahead of UTC
  const sign = off >= 0 ? '+' : '-';
  const absOff = Math.abs(off);
  const hh = String(Math.floor(absOff / 60)).padStart(2, '0');
  const mm = String(absOff % 60).padStart(2, '0');
  const yyyy = local.getFullYear();
  const mo = String(local.getMonth() + 1).padStart(2, '0');
  const dd = String(local.getDate()).padStart(2, '0');
  return `${yyyy}-${mo}-${dd}T${hour}:${min}:00${sign}${hh}:${mm}`;
}

// ─── Create Appointment Modal ────────────────────────────────────
function CreateAppointmentModal({
  open,
  onClose,
  defaultDate,
  defaultHour,
  users,
  existingAppointments,
}: {
  open: boolean;
  onClose: () => void;
  defaultDate: Date;
  // WEB-UIUX-1328: override the hardcoded 9am start when the modal was opened
  // via click-to-create on a Week/Day slot. End time is start + 1h.
  defaultHour?: number;
  users: { id: number; first_name: string; last_name: string }[];
  existingAppointments: Appointment[];
}) {
  const queryClient = useQueryClient();
  // WEB-UIUX-1322: use the local date components, not toISOString(), so a
  // user clicking "+New Appointment" at 5pm Dec 31 PST gets Dec 31, not
  // Jan 1 (UTC). Off-by-one would otherwise fire at every edge hour.
  const toLocalDateStr = (d: Date) => {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  };
  const dateStr = toLocalDateStr(defaultDate);

  const createInitialForm = useCallback(() => {
    // WEB-UIUX-1328: honor click-to-create slot hour. Clamp to 0..23 and
    // compute end as start+1h (also clamped, wrapping at 23→23 keeps the
    // form valid; the operator can edit to span past midnight via dates).
    const startH = Number.isInteger(defaultHour) && defaultHour! >= 0 && defaultHour! <= 23 ? defaultHour! : 9;
    const endH = Math.min(startH + 1, 23);
    return {
      title: '',
      start_date: dateStr,
      start_hour: String(startH).padStart(2, '0'),
      start_min: '00',
      end_hour: String(endH).padStart(2, '0'),
      end_min: '00',
      assigned_to: '',
      status: 'scheduled',
      notes: '',
      location_id: '1', // WEB-UIUX-1321: default location; overridable via select below
      customer_id: '' as string,
      customer_label: '' as string,
      recurrence: 'none' as 'none' | 'weekly' | 'biweekly' | 'monthly',
    };
  }, [dateStr, defaultHour]);

  const [form, setForm] = useState(() => createInitialForm());
  // WEB-UIUX-1315: customer picker — typeahead against /customers/search.
  const [customerQuery, setCustomerQuery] = useState('');
  const [customerDropdownOpen, setCustomerDropdownOpen] = useState(false);
  const { data: customerSearchData } = useQuery({
    queryKey: ['appt-customer-search', customerQuery],
    queryFn: ({ signal }) => customerApi.search(customerQuery, signal),
    enabled: customerQuery.length >= 2 && customerDropdownOpen,
  });
  const customerResults = (customerSearchData?.data?.data as Array<{ id: number; first_name?: string; last_name?: string; phone?: string; email?: string }>) ?? [];
  // WEB-FK-015: overlap warning state
  const [overlapWarning, setOverlapWarning] = useState<string | null>(null);

  // Start each create flow from the date currently selected in the calendar.
  useEffect(() => {
    if (!open) return;
    setForm(createInitialForm());
    setOverlapWarning(null);
  }, [createInitialForm, open]);

  // WEB-UIUX-1323: re-pre-fill start/end date whenever the modal reopens on a
  // different calendar date so the date field reflects the clicked day, not
  // the date from the previous open.
  useEffect(() => {
    if (!open) return;
    // WEB-UIUX-1322: local-date components, not UTC.
    const newDateStr = toLocalDateStr(defaultDate);
    setForm((f) => ({ ...f, start_date: newDateStr }));
  }, [open, defaultDate]);

  // WEB-FC-017: narrow the mutation payload type from `any` to the minimal
  // shape the API endpoint accepts.
  interface CreateAppointmentPayload {
    title: string;
    start_time: string;
    end_time?: string;
    assigned_to?: number;
    status: 'scheduled' | 'confirmed' | 'completed' | 'cancelled' | 'no-show';
    notes?: string;
    location_id?: number; // WEB-UIUX-1321
    customer_id?: number; // WEB-UIUX-1315
    recurrence?: 'none' | 'weekly' | 'biweekly' | 'monthly'; // WEB-UIUX-1320
  }
  const createMut = useMutation({
    mutationFn: (data: CreateAppointmentPayload) => leadApi.createAppointment(data),
    // WEB-UIUX-1319: read server `warning` field from response; show warning toast
    // instead of success when the server signals a partial-success condition.
    onSuccess: (res) => {
      const warning = res?.data?.warning;
      if (warning) {
        toast.error(warning);
      } else {
        toast.success('Appointment created');
      }
      queryClient.invalidateQueries({ queryKey: ['appointments'] });
      onClose();
    },
    onError: () => toast.error('Failed to create appointment'),
  });

  // Esc cancels the create flow without losing the rest of the page state.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  // WEB-FK-015: check for overlapping appointments for the selected assignee
  function checkOverlap(startIso: string, endIso: string, assignedUserId: number | null): string | null {
    if (!assignedUserId) return null;
    const start = new Date(startIso).getTime();
    const end = new Date(endIso).getTime();
    const conflict = existingAppointments.find((a) => {
      if (a.assigned_to !== assignedUserId) return false;
      const aStart = new Date(a.start_time).getTime();
      const aEnd = a.end_time ? new Date(a.end_time).getTime() : aStart + 3600_000;
      return start < aEnd && end > aStart;
    });
    if (!conflict) return null;
    const name = users.find((u) => u.id === assignedUserId);
    const assigneeName = name ? `${name.first_name} ${name.last_name}` : 'this person';
    return `${assigneeName} already has "${conflict.title || 'an appointment'}" overlapping this time slot.`;
  }

  // WEB-UIUX-1324: cross-viewport overlap check via the dedicated server route.
  async function checkOverlapCrossWindow(
    startIso: string,
    endIso: string,
    assignedUserId: number | null,
  ): Promise<string | null> {
    if (!assignedUserId) return null;
    try {
      const res = await leadApi.getAppointmentOverlaps({
        assigned_to: assignedUserId,
        start_time: startIso,
        end_time: endIso,
      });
      const overlaps = res.data?.data?.overlaps ?? [];
      if (overlaps.length === 0) return null;
      const conflict = overlaps[0];
      const name = users.find((u) => u.id === assignedUserId);
      const assigneeName = name ? `${name.first_name} ${name.last_name}` : 'this person';
      return `${assigneeName} already has "${conflict.title || 'an appointment'}" overlapping this time slot (outside the current view).`;
    } catch {
      return null;
    }
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="appointment-create-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="w-full max-w-lg rounded-xl bg-white shadow-xl dark:bg-surface-800">
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 id="appointment-create-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">New Appointment</h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5" />
          </button>
        </div>
        <form
          className="space-y-4 px-6 py-4"
          onSubmit={async (e) => {
            e.preventDefault();
            // WEB-FK-015: use TZ-aware ISO strings so the server stores the
            // correct instant regardless of server timezone.
            const startTime = toISOWithOffset(form.start_date, form.start_hour, form.start_min);
            const endTime = toISOWithOffset(form.start_date, form.end_hour, form.end_min);
            if (endTime <= startTime) {
              toast.error('End time must be after start time');
              return;
            }
            // Overlap check — warn but still allow user to proceed after seeing the warning.
            // WEB-UIUX-1324: local-viewport check first (cheap), then cross-window if local clears.
            const assignedId = form.assigned_to ? Number(form.assigned_to) : null;
            const warn =
              checkOverlap(startTime, endTime, assignedId)
              ?? await checkOverlapCrossWindow(startTime, endTime, assignedId);
            if (warn && !overlapWarning) {
              // Show warning on first submit; second submit proceeds.
              setOverlapWarning(warn);
              return;
            }
            setOverlapWarning(null);
            createMut.mutate({
              title: form.title,
              start_time: startTime,
              end_time: endTime,
              assigned_to: assignedId ?? undefined,
              status: form.status as 'scheduled' | 'confirmed' | 'completed' | 'cancelled' | 'no-show',
              notes: form.notes || undefined,
              location_id: form.location_id ? Number(form.location_id) : 1, // WEB-UIUX-1321
              customer_id: form.customer_id ? Number(form.customer_id) : undefined, // WEB-UIUX-1315
              recurrence: form.recurrence !== 'none' ? form.recurrence : undefined, // WEB-UIUX-1320
            });
          }}
        >
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Title *</label>
            <input
              required
              value={form.title}
              onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
              placeholder="e.g. Screen repair consultation"
              className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            />
          </div>
          {/* WEB-UIUX-1315: customer picker. Optional but pre-filled when present
              avoids the "orphan appointment" failure mode where staff book a
              repair consultation with no customer attached and lose the link. */}
          <div className="relative">
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Customer (optional)</label>
            {form.customer_id ? (
              <div className="flex items-center justify-between gap-2 rounded-lg border border-primary-200 bg-primary-50 px-3 py-2 text-sm dark:border-primary-700 dark:bg-primary-900/20">
                <span className="truncate">{form.customer_label}</span>
                <button
                  type="button"
                  onClick={() => setForm((f) => ({ ...f, customer_id: '', customer_label: '' }))}
                  className="text-xs text-primary-700 hover:underline dark:text-primary-300"
                >
                  Change
                </button>
              </div>
            ) : (
              <input
                type="search"
                value={customerQuery}
                onChange={(e) => { setCustomerQuery(e.target.value); setCustomerDropdownOpen(true); }}
                onFocus={() => setCustomerDropdownOpen(true)}
                placeholder="Search by name, phone, or email"
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            )}
            {customerDropdownOpen && !form.customer_id && customerResults.length > 0 && (
              <ul role="listbox" className="absolute z-10 mt-1 max-h-44 w-full overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                {customerResults.slice(0, 8).map((c) => {
                  const label = [c.first_name, c.last_name].filter(Boolean).join(' ') || c.phone || c.email || `#${c.id}`;
                  return (
                    <li key={c.id}>
                      <button
                        type="button"
                        onClick={() => {
                          setForm((f) => ({ ...f, customer_id: String(c.id), customer_label: label }));
                          setCustomerDropdownOpen(false);
                          setCustomerQuery('');
                        }}
                        className="block w-full px-3 py-2 text-left text-sm hover:bg-surface-100 dark:hover:bg-surface-700"
                      >
                        <div className="font-medium text-surface-900 dark:text-surface-100">{label}</div>
                        <div className="text-xs text-surface-500">{c.phone || c.email || ''}</div>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Date</label>
            <input
              type="date"
              value={form.start_date}
              onChange={(e) => setForm((f) => ({ ...f, start_date: e.target.value }))}
              className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Start Time</label>
              <div className="flex gap-1">
                {/* WEB-UIUX-1330: bumping start auto-slides end by +1h so an
                    operator who picks 18:00 doesn't get blocked by the
                    "End time must be after start time" toast. */}
                <select value={form.start_hour} onChange={(e) => setForm((f) => {
                  const newStartHour = e.target.value;
                  const newEndHour = String((Number(newStartHour) + 1) % 24).padStart(2, '0');
                  return { ...f, start_hour: newStartHour, end_hour: newEndHour, end_min: f.start_min };
                })}
                  className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100">
                  {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0')).map((h) => {
                    const n = Number(h);
                    const label = `${((n % 12) || 12)} ${n < 12 ? 'AM' : 'PM'}`;
                    return <option key={h} value={h}>{label}</option>;
                  })}
                </select>
                <span className="flex items-center text-surface-400">:</span>
                <select value={form.start_min} onChange={(e) => setForm((f) => ({ ...f, start_min: e.target.value, end_min: e.target.value }))}
                  className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100">
                  {['00', '15', '30', '45'].map((m) => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">End Time</label>
              <div className="flex gap-1">
                <select value={form.end_hour} onChange={(e) => setForm((f) => ({ ...f, end_hour: e.target.value }))}
                  className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100">
                  {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0')).map((h) => {
                    const n = Number(h);
                    const label = `${((n % 12) || 12)} ${n < 12 ? 'AM' : 'PM'}`;
                    return <option key={h} value={h}>{label}</option>;
                  })}
                </select>
                <span className="flex items-center text-surface-400">:</span>
                <select value={form.end_min} onChange={(e) => setForm((f) => ({ ...f, end_min: e.target.value }))}
                  className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100">
                  {['00', '15', '30', '45'].map((m) => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Assigned To</label>
              <select
                value={form.assigned_to}
                onChange={(e) => setForm((f) => ({ ...f, assigned_to: e.target.value }))}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              >
                <option value="">Unassigned</option>
                {users.map((u) => (
                  <option key={u.id} value={u.id}>{u.first_name} {u.last_name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Status</label>
              <select
                value={form.status}
                onChange={(e) => setForm((f) => ({ ...f, status: e.target.value }))}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              >
                {/* WEB-UIUX-1325: include no-show option */}
                <option value="scheduled">Scheduled</option>
                <option value="confirmed">Confirmed</option>
                <option value="completed">Completed</option>
                <option value="cancelled">Cancelled</option>
                <option value="no-show">No-Show</option>
              </select>
            </div>
          </div>
          {/* WEB-UIUX-1321: location_id field — text input (locations list API not yet exposed);
              defaults to 1 (primary location). Replace with a select when getLocations is available. */}
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Location ID</label>
            <input
              type="number"
              min={1}
              value={form.location_id}
              onChange={(e) => setForm((f) => ({ ...f, location_id: e.target.value }))}
              className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Notes</label>
            <textarea
              value={form.notes}
              onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
              rows={2}
              className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            />
          </div>
          {/* WEB-UIUX-1320: recurrence picker. Server auto-creates 4 occurrences
              for weekly/biweekly/monthly; leave as "none" for a single appt. */}
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Recurrence</label>
            <select
              value={form.recurrence}
              onChange={(e) => setForm((f) => ({ ...f, recurrence: e.target.value as 'none' | 'weekly' | 'biweekly' | 'monthly' }))}
              className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            >
              <option value="none">One-time only</option>
              <option value="weekly">Weekly (creates 4 occurrences)</option>
              <option value="biweekly">Bi-weekly (creates 4 occurrences)</option>
              <option value="monthly">Monthly (creates 4 occurrences)</option>
            </select>
          </div>
          {/* WEB-FK-015: overlap warning — shown after first submit attempt if conflict found */}
          {overlapWarning && (
            <div className="rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20 px-3 py-2 text-sm text-amber-700 dark:text-amber-400">
              <strong>Scheduling conflict:</strong> {overlapWarning} Submit again to create anyway.
            </div>
          )}
          {/* WEB-UIUX-1336: surface server send-behaviour so staff aren't left
              guessing. `POST /appointments` does not auto-send a confirmation
              today (messaging-sprint work), so booked customers won't receive
              any notification until the operator messages them. Closes the
              "opaque" half of the bullet; the actual auto-send + opt-out
              toggle still waits on SMS infrastructure. */}
          <p className="rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-xs text-surface-600 dark:border-surface-700 dark:bg-surface-900/40 dark:text-surface-400">
            <strong className="font-semibold text-surface-700 dark:text-surface-300">No automatic confirmation is sent.</strong>{' '}
            Booking the appointment does not message the customer — copy the
            date and time over manually until automated reminders ship.
          </p>
          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={createMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 shadow-sm hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {createMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              {overlapWarning ? 'Create Anyway' : 'Create'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Month View ──────────────────────────────────────────────────
function MonthView({
  currentDate,
  appointments,
  onSelectAppointment,
  onDrillDown,
  onCreateAt,
  shopTz,
}: {
  currentDate: Date;
  appointments: Appointment[];
  onSelectAppointment: (a: Appointment) => void;
  // WEB-UIUX-1327: callback to switch to day view on a given date when "+N more" is clicked
  onDrillDown?: (day: Date) => void;
  // WEB-UIUX-1328: callback fires when the user clicks empty space on a day cell,
  // opening CreateAppointmentModal pre-filled with that calendar day.
  onCreateAt?: (slot: Date) => void;
  shopTz?: string;
}) {
  const year = currentDate.getFullYear();
  const month = currentDate.getMonth();
  const firstDay = new Date(year, month, 1);
  const lastDay = new Date(year, month + 1, 0);
  const startDay = firstDay.getDay();
  const daysInMonth = lastDay.getDate();
  const today = new Date();

  const cells: (number | null)[] = [];
  for (let i = 0; i < startDay; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);
  while (cells.length % 7 !== 0) cells.push(null);

  // WEB-FF-025: bucket appointments by day-key once so each of the 42 cells
  // does an O(1) Map lookup instead of an O(N) filter.
  const apptsByDay = useMemo(() => {
    const map = new Map<string, Appointment[]>();
    for (const a of appointments) {
      const k = dayKey(new Date(a.start_time));
      const list = map.get(k);
      if (list) list.push(a);
      else map.set(k, [a]);
    }
    return map;
  }, [appointments]);

  return (
    <div className="grid grid-cols-7 border-l border-t border-surface-200 dark:border-surface-700">
      {WEEKDAYS.map((day) => (
        <div key={day} className="border-b border-r border-surface-200 bg-surface-50 px-2 py-2 text-center text-xs font-medium text-surface-500 dark:border-surface-700 dark:bg-surface-800/50 dark:text-surface-400">
          {day}
        </div>
      ))}
      {cells.map((day, i) => {
        const cellDate = day ? new Date(year, month, day) : null;
        const dayAppts = cellDate
          ? (apptsByDay.get(dayKey(cellDate)) ?? [])
          : [];
        const isToday = cellDate && isSameDay(cellDate, today);

        return (
          <div
            key={i}
            // WEB-UIUX-1328: click empty space on a populated day cell to open
            // the create modal pre-filled with that day. Skipped on padding
            // cells (no day) and only fires when the click target IS the cell
            // itself (so appt buttons + "+N more" keep their existing behavior
            // via event bubbling).
            onClick={(e) => {
              if (!day || !cellDate || !onCreateAt) return;
              if (e.target === e.currentTarget) onCreateAt(cellDate);
            }}
            className={cn(
              'min-h-[100px] border-b border-r border-surface-200 p-1.5 dark:border-surface-700',
              !day && 'bg-surface-50/50 dark:bg-surface-800/30',
              day && onCreateAt && 'cursor-pointer hover:bg-surface-50 dark:hover:bg-surface-800/50',
            )}
          >
            {day && (
              <>
                <div className={cn(
                  'mb-1 text-right text-xs font-medium',
                  isToday
                    ? 'inline-flex h-6 w-6 float-right items-center justify-center rounded-full bg-primary-600 text-primary-950'
                    : 'text-surface-600 dark:text-surface-400',
                )}>
                  {day}
                </div>
                <div className="clear-both space-y-0.5">
                  {dayAppts.slice(0, 3).map((appt) => {
                    const color = getStatusColor(appt.status);
                    return (
                      <button
                        key={appt.id}
                        onClick={() => onSelectAppointment(appt)}
                        className="block w-full truncate rounded px-1 py-0.5 text-left text-[10px] font-medium leading-tight transition-opacity hover:opacity-80"
                        style={{ backgroundColor: `${color}20`, color }}
                      >
                        {formatTimeTz(appt.start_time, shopTz)} {appt.title || 'Appointment'}
                      </button>
                    );
                  })}
                  {/* WEB-UIUX-1327: make "+N more" a button that drills into day view */}
                  {dayAppts.length > 3 && (
                    <button
                      type="button"
                      onClick={() => cellDate && onDrillDown?.(cellDate)}
                      className="block w-full px-1 text-left text-[10px] text-primary-500 hover:text-primary-700 hover:underline dark:text-primary-400 dark:hover:text-primary-300"
                    >
                      +{dayAppts.length - 3} more
                    </button>
                  )}
                </div>
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ─── Week View ───────────────────────────────────────────────────
function WeekView({
  currentDate,
  appointments,
  onSelectAppointment,
  onCreateAt,
  hours = DEFAULT_HOURS,
  shopTz,
}: {
  currentDate: Date;
  appointments: Appointment[];
  hours?: number[];
  onSelectAppointment: (a: Appointment) => void;
  // WEB-UIUX-1328: click an empty hour slot to open the create modal pre-filled
  // with that day + hour. `slot.getHours()` is the start hour for the new appt.
  onCreateAt?: (slot: Date) => void;
  shopTz?: string;
}) {
  const weekStart = startOfWeek(currentDate);
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));

  // WEB-UIUX-1318: count appts that fall outside the configured hours range
  // for any day in this week. The grid only renders rows for `hours`, so
  // out-of-range rows would silently disappear without this banner.
  const minHour = hours.length ? hours[0] : 0;
  const maxHour = hours.length ? hours[hours.length - 1] : 23;
  const outOfRange = appointments.filter((a) => {
    const d = new Date(a.start_time);
    if (!days.some((day) => isSameDay(d, day))) return false;
    const h = d.getHours();
    return h < minHour || h > maxHour;
  });

  return (
    <>
    {outOfRange.length > 0 && (
      <div className="mb-2 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300">
        <span aria-hidden="true">⚠</span>
        <span>
          <strong>{outOfRange.length}</strong>{' '}
          appointment{outOfRange.length === 1 ? '' : 's'} this week fall outside the visible hour window
          ({minHour}:00–{maxHour + 1}:00). Switch to month view or widen <code className="font-mono">calendar_start_hour</code>/<code className="font-mono">calendar_end_hour</code> in Settings.
        </span>
      </div>
    )}
    <div className="grid grid-cols-[60px_repeat(7,1fr)] border-l border-surface-200 dark:border-surface-700">
      {/* Header row */}
      <div className="border-b border-r border-surface-200 dark:border-surface-700" />
      {days.map((day) => {
        const isToday = isSameDay(day, today);
        return (
          <div
            key={day.toISOString()}
            className={cn(
              'border-b border-r border-surface-200 px-2 py-2 text-center dark:border-surface-700',
              isToday && 'bg-primary-50 dark:bg-primary-950/20',
            )}
          >
            <div className="text-xs text-surface-400">{WEEKDAYS[day.getDay()]}</div>
            <div className={cn(
              'text-sm font-semibold',
              isToday ? 'text-primary-600 dark:text-primary-400' : 'text-surface-700 dark:text-surface-300',
            )}>
              {day.getDate()}
            </div>
          </div>
        );
      })}

      {/* Time slots */}
      {hours.map((hour) => (
        <Fragment key={hour}>
          <div className="border-b border-r border-surface-200 px-1 py-2 text-right text-[10px] text-surface-400 dark:border-surface-700">
            {hour > 12 ? `${hour - 12}pm` : hour === 12 ? '12pm' : `${hour}am`}
          </div>
          {days.map((day) => {
            const hourAppts = appointments.filter((a) => {
              const d = new Date(a.start_time);
              return isSameDay(d, day) && d.getHours() === hour;
            });
            return (
              <div
                key={day.toISOString()}
                // WEB-UIUX-1328: click an empty hour slot to create. Skipped
                // when the click target is one of the inner appt buttons so
                // existing select-detail behavior keeps working via bubbling.
                onClick={(e) => {
                  if (!onCreateAt) return;
                  if (e.target !== e.currentTarget) return;
                  const slot = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, 0, 0, 0);
                  onCreateAt(slot);
                }}
                className={cn(
                  'min-h-[48px] border-b border-r border-surface-200 p-0.5 dark:border-surface-700',
                  onCreateAt && 'cursor-pointer hover:bg-surface-50 dark:hover:bg-surface-800/50',
                )}
              >
                {hourAppts.map((appt) => {
                  const color = getStatusColor(appt.status);
                  return (
                    <button
                      key={appt.id}
                      onClick={() => onSelectAppointment(appt)}
                      className="block w-full truncate rounded px-1 py-0.5 text-left text-[10px] font-medium leading-tight transition-opacity hover:opacity-80"
                      style={{ backgroundColor: `${color}20`, color }}
                    >
                      {formatTimeTz(appt.start_time, shopTz)} {appt.title || 'Appt'}
                    </button>
                  );
                })}
              </div>
            );
          })}
        </Fragment>
      ))}
    </div>
    </>
  );
}

// ─── Day View ────────────────────────────────────────────────────
function DayView({
  currentDate,
  appointments,
  onSelectAppointment,
  onCreateAt,
  hours = DEFAULT_HOURS,
  shopTz,
}: {
  currentDate: Date;
  appointments: Appointment[];
  hours?: number[];
  onSelectAppointment: (a: Appointment) => void;
  // WEB-UIUX-1328: click an empty hour row to open the create modal pre-filled
  // with this day + the clicked hour.
  onCreateAt?: (slot: Date) => void;
  shopTz?: string;
}) {
  const dayAppts = appointments.filter((a) => isSameDay(new Date(a.start_time), currentDate));

  // WEB-UIUX-1318: same out-of-range count for DayView.
  const dayMinHour = hours.length ? hours[0] : 0;
  const dayMaxHour = hours.length ? hours[hours.length - 1] : 23;
  const dayOutOfRange = dayAppts.filter((a) => {
    const h = new Date(a.start_time).getHours();
    return h < dayMinHour || h > dayMaxHour;
  });

  return (
    <>
    {dayOutOfRange.length > 0 && (
      <div className="mb-2 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300">
        <span aria-hidden="true">⚠</span>
        <span>
          <strong>{dayOutOfRange.length}</strong>{' '}
          appointment{dayOutOfRange.length === 1 ? '' : 's'} on this day fall outside the visible hour window
          ({dayMinHour}:00–{dayMaxHour + 1}:00). Switch to month view or widen
          {' '}<code className="font-mono">calendar_start_hour</code>/<code className="font-mono">calendar_end_hour</code> in Settings.
        </span>
      </div>
    )}
    <div className="border-l border-surface-200 dark:border-surface-700">
      {hours.map((hour) => {
        const hourAppts = dayAppts.filter((a) => new Date(a.start_time).getHours() === hour);
        const label = hour > 12 ? `${hour - 12}:00 PM` : hour === 12 ? '12:00 PM' : `${hour}:00 AM`;

        return (
          <div key={hour} className="flex border-b border-surface-200 dark:border-surface-700">
            <div className="w-20 shrink-0 border-r border-surface-200 px-2 py-3 text-right text-xs text-surface-400 dark:border-surface-700">
              {label}
            </div>
            <div
              // WEB-UIUX-1328: click empty hour slot creates an appt at that hour.
              onClick={(e) => {
                if (!onCreateAt) return;
                if (e.target !== e.currentTarget) return;
                const slot = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate(), hour, 0, 0, 0);
                onCreateAt(slot);
              }}
              className={cn(
                'flex-1 min-h-[56px] p-1 space-y-1',
                onCreateAt && 'cursor-pointer hover:bg-surface-50 dark:hover:bg-surface-800/50',
              )}
            >
              {hourAppts.map((appt) => {
                const color = getStatusColor(appt.status);
                return (
                  <button
                    key={appt.id}
                    onClick={() => onSelectAppointment(appt)}
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left transition-opacity hover:opacity-80"
                    style={{ backgroundColor: `${color}15` }}
                  >
                    <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: color }} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium" style={{ color }}>
                        {appt.title || 'Appointment'}
                      </p>
                      <p className="text-xs text-surface-500">
                        {formatTimeTz(appt.start_time, shopTz)}
                        {appt.end_time && ` - ${formatTimeTz(appt.end_time, shopTz)}`}
                        {appt.customer_first_name && ` | ${appt.customer_first_name} ${appt.customer_last_name}`}
                      </p>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
    </>
  );
}

// Fragment is imported at the top of the file.

// ─── Main Component ─────────────────────────────────────────────
export function CalendarPage() {
  // Honor `?view=day|week|month` so deep-links from the POS gate land on
  // the right view (gate "+N more · view all" routes to ?view=day for a
  // vertical timeline). Falls back to month on unknown / missing values.
  const initialView = (() => {
    if (typeof window === 'undefined') return 'month' as ViewMode;
    const param = new URLSearchParams(window.location.search).get('view');
    return param === 'day' || param === 'week' || param === 'month' ? (param as ViewMode) : 'month';
  })();
  const [viewMode, setViewMode] = useState<ViewMode>(initialView);
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedAppt, setSelectedAppt] = useState<Appointment | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  // WEB-UIUX-1328: click-to-create slot Date — when set, CreateAppointmentModal
  // pre-fills date AND start hour from the clicked Month/Week/Day cell. Reset
  // to null when the modal closes so the next "+ New Appointment" button click
  // reverts to the today/9am default.
  const [createSlot, setCreateSlot] = useState<Date | null>(null);
  const openCreateAt = useCallback((slot: Date) => {
    setCreateSlot(slot);
    setShowCreate(true);
  }, []);
  const { getSetting } = useSettings();

  // WEB-UIUX-780: read shop timezone from store_config so display times are
  // always in the shop's local time, not the viewer's browser timezone.
  const shopTz = getSetting('timezone', '') || undefined;
  const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const tzMismatch = shopTz && shopTz !== browserTz;

  // FA-L9: read business hours from settings when present; fall back to 7am-7pm.
  // calendar_start_hour / calendar_end_hour are simple int-in-string settings,
  // editable via Settings → Store (future) or admin dashboard.
  const hours = useMemo(() => {
    const startRaw = parseInt(getSetting('calendar_start_hour', '7'), 10);
    const endRaw = parseInt(getSetting('calendar_end_hour', '19'), 10);
    const start = Number.isFinite(startRaw) && startRaw >= 0 && startRaw <= 23 ? startRaw : 7;
    const endExclusive = Number.isFinite(endRaw) && endRaw > start && endRaw <= 24 ? endRaw : 19;
    return Array.from({ length: endExclusive - start + 1 }, (_, i) => i + start);
  }, [getSetting]);

  // Fetch users
  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => settingsApi.getUsers(),
  });
  const users: { id: number; first_name: string; last_name: string }[] =
    usersData?.data?.data?.users || usersData?.data?.data || [];

  // Compute date range for query.
  // appointments.start_time is stored as a naive `YYYY-MM-DD HH:MM:SS`
  // string in shop-local time. Passing `toISOString()` (UTC w/ Z suffix)
  // makes SQLite's lex compare disagree with chronological order — a
  // PT-shop's `2026-05-08 12:27:51` row falls outside a window that opens
  // at `2026-05-09T00:00:00.000Z` ("tomorrow" in UTC) even though the
  // appointment is today. Format the boundary as the same naive shape so
  // the lex compare matches the wall clock the shop actually uses.
  const fmtNaive = (d: Date, suffix = '00:00:00') => {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day} ${suffix}`;
  };
  const dateRange = useMemo(() => {
    const y = currentDate.getFullYear();
    const m = currentDate.getMonth();
    if (viewMode === 'month') {
      const from = fmtNaive(new Date(y, m, 1));
      const to = fmtNaive(new Date(y, m + 1, 0), '23:59:59');
      return { from_date: from, to_date: to };
    }
    if (viewMode === 'week') {
      const ws = startOfWeek(currentDate);
      const from = fmtNaive(ws);
      const to = fmtNaive(addDays(ws, 6), '23:59:59');
      return { from_date: from, to_date: to };
    }
    // day
    const from = fmtNaive(new Date(y, m, currentDate.getDate()));
    const to = fmtNaive(new Date(y, m, currentDate.getDate()), '23:59:59');
    return { from_date: from, to_date: to };
  }, [currentDate, viewMode]);

  // Fetch appointments
  const { data: apptData, isLoading } = useQuery({
    queryKey: ['appointments', dateRange],
    queryFn: () => leadApi.appointments(dateRange),
  });

  const appointments: Appointment[] = apptData?.data?.data?.appointments ?? apptData?.data?.data ?? [];

  // Navigation
  const navigate = useCallback(
    (dir: -1 | 1) => {
      setCurrentDate((prev) => {
        const d = new Date(prev);
        if (viewMode === 'month') d.setMonth(d.getMonth() + dir);
        else if (viewMode === 'week') d.setDate(d.getDate() + dir * 7);
        else d.setDate(d.getDate() + dir);
        return d;
      });
    },
    [viewMode],
  );

  // WEB-UIUX-1334: Today also swaps to day view so the operator lands on
  // today's hour grid (the most common "show me right now" intent).
  const goToToday = useCallback(() => {
    setCurrentDate(new Date());
    setViewMode('day');
  }, []);

  // Title
  const title = useMemo(() => {
    if (viewMode === 'month') {
      return currentDate.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
    }
    if (viewMode === 'week') {
      const ws = startOfWeek(currentDate);
      const we = addDays(ws, 6);
      return `${formatDateShort(ws)} - ${formatDateShort(we)}, ${we.getFullYear()}`;
    }
    return currentDate.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
  }, [currentDate, viewMode]);

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Calendar</h1>
          <p className="text-surface-500 dark:text-surface-400">Schedule appointments and follow-ups</p>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" />
          New Appointment
        </button>
      </div>

      {/* WEB-UIUX-780: shop TZ banner — always shown when a timezone is configured
          so staff know which timezone times are displayed in. */}
      {shopTz && (
        <div className={cn(
          'mb-4 flex items-center gap-2 rounded-lg px-4 py-2.5 text-sm',
          tzMismatch
            ? 'border border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-300'
            : 'border border-surface-200 bg-surface-50 text-surface-600 dark:border-surface-700 dark:bg-surface-800/50 dark:text-surface-400',
        )}>
          <Clock className="h-4 w-4 shrink-0" />
          <span>
            Times shown in <strong>{shopTz}</strong>
            {tzMismatch && (
              <span className="ml-1">(your browser is in {browserTz})</span>
            )}
          </span>
        </div>
      )}

      <div className="card">
        {/* Toolbar */}
        <div className="flex flex-col gap-3 border-b border-surface-200 px-4 py-3 dark:border-surface-700 sm:flex-row sm:items-center sm:justify-between">
          {/* Left: nav + title */}
          <div className="flex items-center gap-3">
            <button
              aria-label="Previous"
              onClick={() => navigate(-1)}
              className="rounded-lg p-1.5 text-surface-500 transition-colors hover:bg-surface-100 dark:hover:bg-surface-700"
            >
              <ChevronLeft className="h-5 w-5" />
            </button>
            <button
              aria-label="Next"
              onClick={() => navigate(1)}
              className="rounded-lg p-1.5 text-surface-500 transition-colors hover:bg-surface-100 dark:hover:bg-surface-700"
            >
              <ChevronRight className="h-5 w-5" />
            </button>
            <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">{title}</h2>
            {/* WEB-UIUX-1334: aria-pressed flips when the calendar is
                already showing today's day-view so SR users hear the active
                state. */}
            <button
              onClick={goToToday}
              aria-pressed={viewMode === 'day' && isSameDay(currentDate, new Date())}
              className="rounded-lg border border-surface-200 px-3 py-1 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-700 aria-pressed:bg-primary-100 aria-pressed:text-primary-800 dark:aria-pressed:bg-primary-900/40 dark:aria-pressed:text-primary-200"
            >
              Today
            </button>
            {/* WEB-UIUX-1333: timezone pill in calendar header */}
            <span className="text-xs text-surface-500 dark:text-surface-400 ml-2" title="Displayed timezone">
              {Intl.DateTimeFormat().resolvedOptions().timeZone}
            </span>
          </div>

          {/* Right: view toggle */}
          <div className="flex rounded-lg border border-surface-200 dark:border-surface-700">
            {(['month', 'week', 'day'] as ViewMode[]).map((mode) => (
              <button
                key={mode}
                onClick={() => setViewMode(mode)}
                className={cn(
                  'px-4 py-1.5 text-sm font-medium capitalize transition-colors',
                  mode === viewMode
                    ? 'bg-primary-600 text-primary-950'
                    : 'text-surface-600 hover:bg-surface-50 dark:text-surface-400 dark:hover:bg-surface-700',
                  mode === 'month' && 'rounded-l-lg',
                  mode === 'day' && 'rounded-r-lg',
                )}
              >
                {mode}
              </button>
            ))}
          </div>
        </div>

        {/* Calendar content */}
        {isLoading ? (
          <div className="flex items-center justify-center py-32">
            <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary-200 border-t-primary-600" />
          </div>
        ) : (
          <div className="overflow-x-auto">
            {viewMode === 'month' && (
              <MonthView
                currentDate={currentDate}
                appointments={appointments}
                onSelectAppointment={setSelectedAppt}
                // WEB-UIUX-1327: drill down to day view when "+N more" is clicked
                onDrillDown={(day) => { setCurrentDate(day); setViewMode('day'); }}
                onCreateAt={openCreateAt}
                shopTz={shopTz}
              />
            )}
            {viewMode === 'week' && (
              <WeekView
                currentDate={currentDate}
                appointments={appointments}
                onSelectAppointment={setSelectedAppt}
                onCreateAt={openCreateAt}
                hours={hours}
                shopTz={shopTz}
              />
            )}
            {viewMode === 'day' && (
              <DayView
                currentDate={currentDate}
                appointments={appointments}
                onSelectAppointment={setSelectedAppt}
                onCreateAt={openCreateAt}
                hours={hours}
                shopTz={shopTz}
              />
            )}
          </div>
        )}

        {/* WEB-UIUX-1329: empty banner only for week/day — month view already shows
            the date grid so a full-page banner would obscure it. */}
        {!isLoading && appointments.length === 0 && viewMode !== 'month' && (
          <div className="flex flex-col items-center justify-center py-16">
            <Calendar className="mb-4 h-12 w-12 text-surface-300 dark:text-surface-600" />
            <p className="text-sm text-surface-500 dark:text-surface-400">No appointments in this period</p>
            <button
              type="button"
              onClick={() => setShowCreate(true)}
              className="mt-3 text-sm font-medium text-primary-600 hover:text-primary-700 hover:underline dark:text-primary-400"
            >
              + Schedule one
            </button>
          </div>
        )}
      </div>

      {/* Detail modal */}
      {selectedAppt && (
        <AppointmentDetailModal
          appointment={selectedAppt}
          onClose={() => setSelectedAppt(null)}
          users={users}
          existingAppointments={appointments}
          onAppointmentUpdated={setSelectedAppt}
          shopTz={shopTz}
        />
      )}

      {/* Create modal */}
      <CreateAppointmentModal
        open={showCreate}
        onClose={() => { setShowCreate(false); setCreateSlot(null); }}
        defaultDate={createSlot ?? currentDate}
        // WEB-UIUX-1328: when the user click-to-creates from a Week/Day slot,
        // honor the clicked hour. Month-cell clicks pass a date at midnight
        // (hour=0), which we treat as "no preference" so the default 9am rule
        // still applies. createSlot is null when "+ New Appointment" button
        // is used, also keeping the default.
        defaultHour={createSlot && createSlot.getHours() !== 0 ? createSlot.getHours() : undefined}
        users={users}
        existingAppointments={appointments}
      />
    </div>
  );
}
