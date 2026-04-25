import { useState, useMemo, useCallback, useEffect, Fragment } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Calendar, ChevronLeft, ChevronRight, Plus, X, Clock,
  User, Loader2,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { leadApi, settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { useSettings } from '@/hooks/useSettings';

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
  customer_first_name?: string;
  customer_last_name?: string;
  assigned_first_name?: string;
  assigned_last_name?: string;
  lead_order_id?: string;
}

type ViewMode = 'month' | 'week' | 'day';

// ─── Constants ───────────────────────────────────────────────────
const STATUS_COLORS: Record<string, string> = {
  scheduled: '#3b82f6',
  confirmed: '#22c55e',
  completed: '#6b7280',
  cancelled: '#ef4444',
  'no-show': '#f59e0b',
};

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
// Default business-hours range when no store setting is present.
// CalendarPage now overrides via `calendar_start_hour` / `calendar_end_hour`
// settings (FA-L9) — passed down to DayView/WeekView as a prop.
const DEFAULT_HOURS = Array.from({ length: 13 }, (_, i) => i + 7); // 7am to 7pm

function getStatusColor(status: string) {
  return STATUS_COLORS[status] || '#6b7280';
}

// WEB-FF-011 (Fixer-FFF 2026-04-25): drop hardcoded 'en-US' so non-US tenants
// see locale-appropriate compact dates (e.g. "24 Apr" instead of "Apr 24") and
// 24h time where the locale prefers it. `undefined` lets Intl pick the
// browser's runtime locale — the same behaviour the shared formatDate helpers
// in utils/format.ts use. The compact format-options stay so the calendar grid
// keeps its tight layout.
function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

function formatDateShort(date: Date) {
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function isSameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
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

// ─── Appointment Detail Modal ────────────────────────────────────
function AppointmentDetailModal({
  appointment,
  onClose,
}: {
  appointment: Appointment;
  onClose: () => void;
}) {
  const color = getStatusColor(appointment.status);
  // Esc closes the appointment-detail dialog so keyboard users aren't trapped.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="appointment-detail-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 id="appointment-detail-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">Appointment Details</h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5" />
          </button>
        </div>
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
                {formatTime(appointment.start_time)}
                {appointment.end_time && ` - ${formatTime(appointment.end_time)}`}
              </p>
            </div>
            <div>
              <p className="text-sm font-medium text-surface-500 dark:text-surface-400">Status</p>
              <span
                className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
                style={{ backgroundColor: `${color}18`, color }}
              >
                <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
                {appointment.status}
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
        </div>
      </div>
    </div>
  );
}

// ─── Create Appointment Modal ────────────────────────────────────
function CreateAppointmentModal({
  open,
  onClose,
  defaultDate,
  users,
}: {
  open: boolean;
  onClose: () => void;
  defaultDate: Date;
  users: { id: number; first_name: string; last_name: string }[];
}) {
  const queryClient = useQueryClient();
  const dateStr = defaultDate.toISOString().slice(0, 10);

  const [form, setForm] = useState({
    title: '',
    start_date: dateStr,
    start_hour: '09',
    start_min: '00',
    end_hour: '10',
    end_min: '00',
    assigned_to: '',
    status: 'scheduled',
    notes: '',
  });

  // Reset default date when it changes
  const createMut = useMutation({
    mutationFn: (data: any) => leadApi.createAppointment(data),
    onSuccess: () => {
      toast.success('Appointment created');
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

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="appointment-create-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="w-full max-w-lg rounded-xl bg-white shadow-2xl dark:bg-surface-800">
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 id="appointment-create-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">New Appointment</h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5" />
          </button>
        </div>
        <form
          className="space-y-4 px-6 py-4"
          onSubmit={(e) => {
            e.preventDefault();
            const startTime = `${form.start_date}T${form.start_hour}:${form.start_min}:00`;
            const endTime = `${form.start_date}T${form.end_hour}:${form.end_min}:00`;
            if (endTime <= startTime) {
              toast.error('End time must be after start time');
              return;
            }
            createMut.mutate({
              title: form.title,
              start_time: startTime,
              end_time: endTime,
              assigned_to: form.assigned_to ? Number(form.assigned_to) : null,
              status: form.status,
              notes: form.notes || null,
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
                <select value={form.start_hour} onChange={(e) => setForm((f) => ({ ...f, start_hour: e.target.value }))}
                  className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100">
                  {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0')).map((h) => (
                    <option key={h} value={h}>{h}</option>
                  ))}
                </select>
                <span className="flex items-center text-surface-400">:</span>
                <select value={form.start_min} onChange={(e) => setForm((f) => ({ ...f, start_min: e.target.value }))}
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
                  {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0')).map((h) => (
                    <option key={h} value={h}>{h}</option>
                  ))}
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
                <option value="scheduled">Scheduled</option>
                <option value="confirmed">Confirmed</option>
                <option value="completed">Completed</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </div>
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
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary-700 disabled:opacity-50"
            >
              {createMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Create
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
}: {
  currentDate: Date;
  appointments: Appointment[];
  onSelectAppointment: (a: Appointment) => void;
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
          ? appointments.filter((a) => isSameDay(new Date(a.start_time), cellDate))
          : [];
        const isToday = cellDate && isSameDay(cellDate, today);

        return (
          <div
            key={i}
            className={cn(
              'min-h-[100px] border-b border-r border-surface-200 p-1.5 dark:border-surface-700',
              !day && 'bg-surface-50/50 dark:bg-surface-800/30',
            )}
          >
            {day && (
              <>
                <div className={cn(
                  'mb-1 text-right text-xs font-medium',
                  isToday
                    ? 'inline-flex h-6 w-6 float-right items-center justify-center rounded-full bg-primary-600 text-white'
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
                        {formatTime(appt.start_time)} {appt.title || 'Appointment'}
                      </button>
                    );
                  })}
                  {dayAppts.length > 3 && (
                    <p className="text-[10px] text-surface-400 px-1">+{dayAppts.length - 3} more</p>
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
  hours = DEFAULT_HOURS,
}: {
  currentDate: Date;
  appointments: Appointment[];
  hours?: number[];
  onSelectAppointment: (a: Appointment) => void;
}) {
  const weekStart = startOfWeek(currentDate);
  const today = new Date();
  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));

  return (
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
                className="min-h-[48px] border-b border-r border-surface-200 p-0.5 dark:border-surface-700"
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
                      {formatTime(appt.start_time)} {appt.title || 'Appt'}
                    </button>
                  );
                })}
              </div>
            );
          })}
        </Fragment>
      ))}
    </div>
  );
}

// ─── Day View ────────────────────────────────────────────────────
function DayView({
  currentDate,
  appointments,
  onSelectAppointment,
  hours = DEFAULT_HOURS,
}: {
  currentDate: Date;
  appointments: Appointment[];
  hours?: number[];
  onSelectAppointment: (a: Appointment) => void;
}) {
  const dayAppts = appointments.filter((a) => isSameDay(new Date(a.start_time), currentDate));

  return (
    <div className="border-l border-surface-200 dark:border-surface-700">
      {hours.map((hour) => {
        const hourAppts = dayAppts.filter((a) => new Date(a.start_time).getHours() === hour);
        const label = hour > 12 ? `${hour - 12}:00 PM` : hour === 12 ? '12:00 PM' : `${hour}:00 AM`;

        return (
          <div key={hour} className="flex border-b border-surface-200 dark:border-surface-700">
            <div className="w-20 shrink-0 border-r border-surface-200 px-2 py-3 text-right text-xs text-surface-400 dark:border-surface-700">
              {label}
            </div>
            <div className="flex-1 min-h-[56px] p-1 space-y-1">
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
                        {formatTime(appt.start_time)}
                        {appt.end_time && ` - ${formatTime(appt.end_time)}`}
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
  );
}

// Fragment is imported at the top of the file.

// ─── Main Component ─────────────────────────────────────────────
export function CalendarPage() {
  const [viewMode, setViewMode] = useState<ViewMode>('month');
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedAppt, setSelectedAppt] = useState<Appointment | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const { getSetting } = useSettings();

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

  // Compute date range for query
  const dateRange = useMemo(() => {
    const y = currentDate.getFullYear();
    const m = currentDate.getMonth();
    if (viewMode === 'month') {
      const from = new Date(y, m, 1).toISOString();
      const to = new Date(y, m + 1, 0, 23, 59, 59).toISOString();
      return { from_date: from, to_date: to };
    }
    if (viewMode === 'week') {
      const ws = startOfWeek(currentDate);
      const from = ws.toISOString();
      const to = addDays(ws, 7).toISOString();
      return { from_date: from, to_date: to };
    }
    // day
    const from = new Date(y, m, currentDate.getDate()).toISOString();
    const to = new Date(y, m, currentDate.getDate(), 23, 59, 59).toISOString();
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

  const goToToday = useCallback(() => setCurrentDate(new Date()), []);

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
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" />
          New Appointment
        </button>
      </div>

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
            <button
              onClick={goToToday}
              className="rounded-lg border border-surface-200 px-3 py-1 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Today
            </button>
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
                    ? 'bg-primary-600 text-white'
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
              />
            )}
            {viewMode === 'week' && (
              <WeekView
                currentDate={currentDate}
                appointments={appointments}
                onSelectAppointment={setSelectedAppt}
                hours={hours}
              />
            )}
            {viewMode === 'day' && (
              <DayView
                currentDate={currentDate}
                appointments={appointments}
                onSelectAppointment={setSelectedAppt}
                hours={hours}
              />
            )}
          </div>
        )}

        {/* Empty state for week/day with no appointments */}
        {!isLoading && appointments.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16">
            <Calendar className="mb-4 h-12 w-12 text-surface-300 dark:text-surface-600" />
            <p className="text-sm text-surface-500 dark:text-surface-400">No appointments in this period</p>
          </div>
        )}
      </div>

      {/* Detail modal */}
      {selectedAppt && (
        <AppointmentDetailModal
          appointment={selectedAppt}
          onClose={() => setSelectedAppt(null)}
        />
      )}

      {/* Create modal */}
      <CreateAppointmentModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        defaultDate={currentDate}
        users={users}
      />
    </div>
  );
}
