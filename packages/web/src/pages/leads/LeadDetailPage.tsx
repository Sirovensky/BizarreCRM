import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Loader2, ArrowRightLeft, Pencil, Save, Phone, Mail,
  MapPin, User, Wrench, Calendar, X, Bell, Plus, Clock, Activity,
  AlertTriangle,
} from 'lucide-react';
import { useEffect, useState, useMemo } from 'react';
import toast from 'react-hot-toast';
import { leadApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate, formatShortDateTime } from '@/utils/format';
import { Breadcrumb } from '@/components/shared/Breadcrumb';

const STATUS_COLORS: Record<string, string> = {
  new: '#3b82f6',
  contacted: '#f59e0b',
  scheduled: '#f59e0b',
  qualified: '#8b5cf6',
  proposal: '#ec4899',
  converted: '#22c55e',
  lost: '#ef4444',
};

const LOST_REASONS = [
  { value: 'price', label: 'Price too high' },
  { value: 'competitor', label: 'Went to competitor' },
  { value: 'no_response', label: 'No response' },
  { value: 'changed_mind', label: 'Changed mind' },
  { value: 'other', label: 'Other' },
] as const;

function getScoreColor(score: number): string {
  if (score >= 70) return '#22c55e';
  if (score >= 40) return '#f59e0b';
  return '#ef4444';
}

function getScoreLabel(score: number): string {
  if (score >= 70) return 'Hot';
  if (score >= 40) return 'Warm';
  return 'Cold';
}

// ─── Lead Score Gauge ──────────────────────────────────────────
function LeadScoreGauge({ score }: { score: number }) {
  const color = getScoreColor(score);
  const label = getScoreLabel(score);
  const circumference = 2 * Math.PI * 40;
  const dashOffset = circumference - (score / 100) * circumference;

  return (
    <div className="flex flex-col items-center">
      <div className="relative h-24 w-24">
        <svg className="h-full w-full -rotate-90" viewBox="0 0 100 100">
          <circle cx="50" cy="50" r="40" fill="none" stroke="currentColor" strokeWidth="8"
            className="text-surface-200 dark:text-surface-700" />
          <circle cx="50" cy="50" r="40" fill="none" strokeWidth="8" strokeLinecap="round"
            stroke={color} strokeDasharray={circumference} strokeDashoffset={dashOffset}
            className="transition-all duration-500" />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xl font-bold" style={{ color }}>{score}</span>
        </div>
      </div>
      <span className="mt-1 text-xs font-semibold" style={{ color }}>{label} Lead</span>
    </div>
  );
}

// ─── Lost Reason Modal ─────────────────────────────────────────
function LostReasonModal({
  open,
  onClose,
  onConfirm,
  isPending,
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: (reason: string) => void;
  isPending: boolean;
}) {
  const [reason, setReason] = useState('');

  // WEB-FX-003: Esc closes the modal so keyboard users aren't trapped.
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="lead-lost-title"
        className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 id="lead-lost-title" className="font-semibold text-surface-900 dark:text-surface-100 flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-red-500" />
            Mark as Lost
          </h3>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="px-5 py-4 space-y-3">
          <p className="text-sm text-surface-600 dark:text-surface-400">Select the reason this lead was lost:</p>
          <div className="space-y-1.5">
            {LOST_REASONS.map((r) => (
              <label
                key={r.value}
                className={`flex cursor-pointer items-center gap-2 rounded-lg border px-3 py-2 text-sm transition-colors ${
                  reason === r.value
                    ? 'border-red-300 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950/30 dark:text-red-400'
                    : 'border-surface-200 text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700'
                }`}
              >
                <input type="radio" name="lost_reason" value={r.value} checked={reason === r.value}
                  onChange={() => setReason(r.value)} className="sr-only" />
                <span className={`h-3 w-3 rounded-full border-2 ${
                  reason === r.value ? 'border-red-500 bg-red-500' : 'border-surface-300 dark:border-surface-600'
                }`} />
                {r.label}
              </label>
            ))}
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t border-surface-200 px-5 py-3 dark:border-surface-700">
          <button onClick={onClose}
            className="rounded-lg border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300">
            Cancel
          </button>
          <button
            onClick={() => { if (reason) onConfirm(reason); }}
            disabled={!reason || isPending}
            className="rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
          >
            {isPending ? 'Saving...' : 'Mark as Lost'}
          </button>
        </div>
      </div>
    </div>
  );
}

export function LeadDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [editingNotes, setEditingNotes] = useState(false);
  const [notes, setNotes] = useState('');
  const [editingStatus, setEditingStatus] = useState(false);
  const [showLostModal, setShowLostModal] = useState(false);
  const [showAddReminder, setShowAddReminder] = useState(false);
  const [reminderDate, setReminderDate] = useState('');
  const [reminderNote, setReminderNote] = useState('');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['lead', id],
    queryFn: () => leadApi.get(Number(id)),
  });

  const lead = data?.data?.data;

  // Fetch reminders
  const { data: remindersData } = useQuery({
    queryKey: ['lead-reminders', id],
    queryFn: () => leadApi.reminders(Number(id)),
    enabled: !!id,
  });
  const reminders: any[] = remindersData?.data?.data ?? [];

  const convertMut = useMutation({
    mutationFn: () => leadApi.convert(Number(id)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['lead', id] });
      toast.success('Converted to ticket');
      const ticketId = res.data?.data?.ticket?.id || res.data?.data?.ticket_id;
      if (ticketId) navigate(`/tickets/${ticketId}`);
    },
    onError: () => toast.error('Failed to convert'),
  });

  const updateMut = useMutation({
    mutationFn: (d: any) => leadApi.update(Number(id), d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['lead', id] });
      queryClient.invalidateQueries({ queryKey: ['leads'] });
      setEditingNotes(false);
      setEditingStatus(false);
      setShowLostModal(false);
      toast.success('Lead updated');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to update'),
  });

  // Status change wrapped in a 5s undo window (D4-5). Optimistically update
  // the cached lead so the badge flips instantly, then fire the real update
  // after 5s. If Undo is clicked we invalidate to restore the previous status.
  const statusUndo = useUndoableAction<{ to: string; from: string }>(
    async ({ to }) => {
      await leadApi.update(Number(id), { status: to });
      queryClient.invalidateQueries({ queryKey: ['lead', id] });
      queryClient.invalidateQueries({ queryKey: ['leads'] });
    },
    {
      timeoutMs: 5000,
      pendingMessage: ({ to }) => `Status changed to ${to}`,
      errorMessage: (_a, err: unknown) => {
        const e = err as { response?: { data?: { message?: string } } };
        return e?.response?.data?.message || 'Failed to update status';
      },
      onUndo: () => {
        queryClient.invalidateQueries({ queryKey: ['lead', id] });
        queryClient.invalidateQueries({ queryKey: ['leads'] });
      },
    },
  );

  const scheduleStatusChange = (to: string, from: string) => {
    if (to === from) return;
    queryClient.setQueriesData({ queryKey: ['lead', id] }, (old: any) => {
      if (!old) return old;
      const clone = JSON.parse(JSON.stringify(old));
      const rec = clone?.data?.data;
      if (rec) rec.status = to;
      return clone;
    });
    setEditingStatus(false);
    statusUndo.trigger({ to, from });
  };

  const createReminderMut = useMutation({
    mutationFn: (data: { remind_at: string; note?: string }) =>
      leadApi.createReminder(Number(id), data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['lead-reminders', id] });
      setShowAddReminder(false);
      setReminderDate('');
      setReminderNote('');
      toast.success('Reminder created');
    },
    onError: () => toast.error('Failed to create reminder'),
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
      </div>
    );
  }

  if (isError || !lead) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <p className="text-lg font-medium text-surface-600 dark:text-surface-400">Lead not found</p>
        <Link to="/leads" className="mt-4 text-sm text-primary-600 hover:underline">Back to leads</Link>
      </div>
    );
  }

  const color = STATUS_COLORS[lead.status] || '#6b7280';
  const devices: any[] = lead.devices || [];
  const appointments: any[] = lead.appointments || [];
  const statuses = ['new', 'contacted', 'scheduled', 'qualified', 'proposal', 'converted', 'lost'];

  // Activity timeline: merge appointments + reminders into a unified list
  const timeline = useMemo(() => {
    const items: { type: string; date: string; title: string; detail?: string }[] = [];
    for (const a of appointments) {
      items.push({
        type: 'appointment',
        date: a.start_time,
        title: a.title || 'Appointment',
        detail: a.status === 'cancelled' ? 'Cancelled' : a.status,
      });
    }
    for (const r of reminders) {
      items.push({
        type: 'reminder',
        date: r.remind_at,
        title: r.note || 'Follow-up reminder',
        detail: r.is_dismissed ? 'Dismissed' : (new Date(r.remind_at) < new Date() ? 'Overdue' : 'Pending'),
      });
    }
    if (lead.created_at) {
      items.push({ type: 'created', date: lead.created_at, title: 'Lead created' });
    }
    if (lead.status === 'converted' && lead.updated_at) {
      items.push({ type: 'converted', date: lead.updated_at, title: 'Converted to ticket' });
    }
    if (lead.status === 'lost' && lead.updated_at) {
      items.push({
        type: 'lost',
        date: lead.updated_at,
        title: 'Lead marked as lost',
        detail: lead.lost_reason ? LOST_REASONS.find(r => r.value === lead.lost_reason)?.label ?? lead.lost_reason : undefined,
      });
    }
    items.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
    return items;
  }, [appointments, reminders, lead]);

  return (
    <div>
      <Breadcrumb items={[
        { label: 'Leads', href: '/leads' },
        { label: lead.order_id ? `Lead ${lead.order_id}` : `Lead #${id}` },
      ]} />
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate('/leads')} className="rounded-lg p-2 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
                Lead {lead.order_id}
              </h1>
              {editingStatus ? (
                <div className="flex items-center gap-1 flex-wrap">
                  {statuses.map((s) => (
                    <button
                      key={s}
                      onClick={() => {
                        if (s === 'lost' && lead.status !== 'lost') {
                          setShowLostModal(true);
                          setEditingStatus(false);
                        } else {
                          scheduleStatusChange(s, lead.status);
                        }
                      }}
                      className={cn(
                        'rounded-full px-2.5 py-0.5 text-xs font-medium capitalize transition-colors',
                        lead.status === s
                          ? 'ring-2 ring-offset-1 ring-primary-500'
                          : 'hover:opacity-80',
                      )}
                      style={{ backgroundColor: `${STATUS_COLORS[s] || '#6b7280'}18`, color: STATUS_COLORS[s] || '#6b7280' }}
                    >
                      {s}
                    </button>
                  ))}
                  <button onClick={() => setEditingStatus(false)} aria-label="Cancel status edit" className="p-0.5 text-surface-400"><X className="h-3.5 w-3.5" /></button>
                </div>
              ) : (
                <button
                  onClick={() => setEditingStatus(true)}
                  className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
                  style={{ backgroundColor: `${color}18`, color }}
                >
                  <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
                  {lead.status}
                </button>
              )}
            </div>
            <p className="text-sm text-surface-500">{lead.first_name} {lead.last_name} &middot; Created {formatDate(lead.created_at)}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {lead.status !== 'converted' && (
            <button
              onClick={async () => { if (await confirm('Convert this lead to a ticket? This will create a new ticket with the lead data.')) convertMut.mutate(); }}
              disabled={convertMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
            >
              <ArrowRightLeft className="h-4 w-4" />
              {convertMut.isPending ? 'Converting...' : 'Convert to Ticket'}
            </button>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Contact info */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Contact Information</h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="flex items-center gap-2 text-sm">
                <User className="h-4 w-4 text-surface-400" />
                <span className="text-surface-900 dark:text-surface-100 font-medium">{lead.first_name} {lead.last_name}</span>
              </div>
              {lead.phone && (
                <div className="flex items-center gap-2 text-sm">
                  <Phone className="h-4 w-4 text-surface-400" />
                  <span className="text-surface-600 dark:text-surface-400">{lead.phone}</span>
                </div>
              )}
              {lead.email && (
                <div className="flex items-center gap-2 text-sm">
                  <Mail className="h-4 w-4 text-surface-400" />
                  <span className="text-surface-600 dark:text-surface-400">{lead.email}</span>
                </div>
              )}
              {(lead.address || lead.zip_code) && (
                <div className="flex items-center gap-2 text-sm">
                  <MapPin className="h-4 w-4 text-surface-400" />
                  <span className="text-surface-600 dark:text-surface-400">{lead.address}{lead.zip_code && ` ${lead.zip_code}`}</span>
                </div>
              )}
            </div>
          </div>

          {/* Devices/Services */}
          {devices.length > 0 && (
            <div className="card overflow-hidden">
              <div className="p-4 border-b border-surface-100 dark:border-surface-800">
                <h3 className="font-semibold text-surface-900 dark:text-surface-100 flex items-center gap-2">
                  <Wrench className="h-4 w-4" /> Devices / Services
                </h3>
              </div>
              <div className="divide-y divide-surface-100 dark:divide-surface-800">
                {devices.map((d: any) => (
                  <div key={d.id} className="px-4 py-3">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{d.device_name || 'Device'}</p>
                        {d.problem && <p className="text-xs text-surface-500 mt-0.5">{d.problem}</p>}
                        {d.customer_notes && <p className="text-xs text-surface-400 mt-0.5 italic">{d.customer_notes}</p>}
                      </div>
                      {d.price > 0 && (
                        <span className="text-sm font-medium text-surface-700 dark:text-surface-300">{formatCurrency(d.price)}</span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Notes */}
          <div className="card p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider">Notes</h3>
              {!editingNotes && (
                <button onClick={() => { setEditingNotes(true); setNotes(lead.notes || ''); }}
                  className="text-xs text-primary-600 hover:text-primary-700 font-medium flex items-center gap-1">
                  <Pencil className="h-3 w-3" /> Edit
                </button>
              )}
            </div>
            {editingNotes ? (
              <div className="space-y-2">
                <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3}
                  className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2" />
                <div className="flex gap-2">
                  <button onClick={() => updateMut.mutate({ notes })} disabled={updateMut.isPending}
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 disabled:opacity-50">
                    <Save className="h-3 w-3" /> Save
                  </button>
                  <button onClick={() => setEditingNotes(false)} className="text-xs text-surface-500">Cancel</button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-surface-600 dark:text-surface-400 whitespace-pre-wrap">
                {lead.notes || <span className="italic text-surface-400">No notes</span>}
              </p>
            )}
          </div>

          {/* Follow-up Reminders */}
          <div className="card p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider flex items-center gap-2">
                <Bell className="h-4 w-4" /> Follow-up Reminders
              </h3>
              <button
                onClick={() => setShowAddReminder(!showAddReminder)}
                className="text-xs text-primary-600 hover:text-primary-700 font-medium flex items-center gap-1"
              >
                <Plus className="h-3 w-3" /> Add
              </button>
            </div>
            {showAddReminder && (
              <div className="mb-3 space-y-2 rounded-lg border border-primary-200 bg-primary-50/50 p-3 dark:border-primary-900 dark:bg-primary-950/20">
                <input
                  type="datetime-local"
                  value={reminderDate}
                  onChange={(e) => setReminderDate(e.target.value)}
                  className="w-full rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
                />
                <input
                  type="text"
                  value={reminderNote}
                  onChange={(e) => setReminderNote(e.target.value)}
                  placeholder="Reminder note (optional)"
                  className="w-full rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
                />
                <div className="flex gap-2">
                  <button
                    onClick={() => {
                      if (!reminderDate) { toast.error('Pick a date/time'); return; }
                      createReminderMut.mutate({
                        remind_at: new Date(reminderDate).toISOString(),
                        note: reminderNote || undefined,
                      });
                    }}
                    disabled={createReminderMut.isPending}
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 disabled:opacity-50"
                  >
                    {createReminderMut.isPending && <Loader2 className="h-3 w-3 animate-spin" />}
                    Save Reminder
                  </button>
                  <button onClick={() => setShowAddReminder(false)} className="text-xs text-surface-500">Cancel</button>
                </div>
              </div>
            )}
            {reminders.length === 0 && !showAddReminder ? (
              <p className="text-sm text-surface-400 italic">No reminders set</p>
            ) : (
              <div className="space-y-2">
                {reminders.map((r: any) => {
                  const isOverdue = !r.is_dismissed && new Date(r.remind_at) < new Date();
                  return (
                    <div
                      key={r.id}
                      className={`rounded-lg border p-2.5 text-sm ${
                        isOverdue
                          ? 'border-amber-300 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/20'
                          : 'border-surface-200 dark:border-surface-700'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-surface-900 dark:text-surface-100 font-medium text-xs">
                          {r.note || 'Follow-up'}
                        </span>
                        {isOverdue && (
                          <span className="rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700 dark:bg-amber-900/40 dark:text-amber-400">
                            Overdue
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-surface-500 mt-0.5">
                        {formatShortDateTime(r.remind_at)}
                        {r.created_by_first_name && ` - by ${r.created_by_first_name}`}
                      </p>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Activity Timeline */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3 flex items-center gap-2">
              <Activity className="h-4 w-4" /> Activity Timeline
            </h3>
            {timeline.length === 0 ? (
              <p className="text-sm text-surface-400 italic">No activity yet</p>
            ) : (
              <div className="relative space-y-0">
                {timeline.map((item, idx) => {
                  const isLast = idx === timeline.length - 1;
                  let dotColor = '#6b7280';
                  let icon = <Clock className="h-3 w-3" />;
                  if (item.type === 'appointment') { dotColor = '#3b82f6'; icon = <Calendar className="h-3 w-3" />; }
                  if (item.type === 'reminder') { dotColor = '#f59e0b'; icon = <Bell className="h-3 w-3" />; }
                  if (item.type === 'created') { dotColor = '#22c55e'; icon = <Plus className="h-3 w-3" />; }
                  if (item.type === 'converted') { dotColor = '#22c55e'; icon = <ArrowRightLeft className="h-3 w-3" />; }
                  if (item.type === 'lost') { dotColor = '#ef4444'; icon = <AlertTriangle className="h-3 w-3" />; }

                  return (
                    <div key={`${item.type}-${item.date}-${idx}`} className="relative flex gap-3 pb-4">
                      {/* Vertical line */}
                      {!isLast && (
                        <div className="absolute left-[11px] top-6 bottom-0 w-px bg-surface-200 dark:bg-surface-700" />
                      )}
                      {/* Dot */}
                      <div
                        className="mt-0.5 flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full text-white"
                        style={{ backgroundColor: dotColor }}
                      >
                        {icon}
                      </div>
                      {/* Content */}
                      <div className="min-w-0">
                        <p className="text-xs font-medium text-surface-900 dark:text-surface-100">{item.title}</p>
                        <div className="flex items-center gap-2">
                          <span className="text-[10px] text-surface-400">
                            {formatShortDateTime(item.date)}
                          </span>
                          {item.detail && (
                            <span className="text-[10px] text-surface-500 capitalize">{item.detail}</span>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Lead Score */}
          <div className="card p-5 flex flex-col items-center">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3 self-start">Lead Score</h3>
            <LeadScoreGauge score={lead.lead_score ?? 0} />
          </div>

          {/* Details */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Details</h3>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-surface-500">Created</dt>
                <dd className="text-surface-900 dark:text-surface-100">{formatDate(lead.created_at)}</dd>
              </div>
              {lead.source && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Source</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{lead.source}</dd>
                </div>
              )}
              {lead.referred_by && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Referred By</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{lead.referred_by}</dd>
                </div>
              )}
              {lead.assigned_first_name && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Assigned To</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{lead.assigned_first_name} {lead.assigned_last_name}</dd>
                </div>
              )}
              {lead.customer_id && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Customer</dt>
                  <dd>
                    <Link to={`/customers/${lead.customer_id}`} className="text-primary-600 hover:underline">
                      {lead.customer_first_name} {lead.customer_last_name}
                    </Link>
                  </dd>
                </div>
              )}
              {lead.ticket_id && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Ticket</dt>
                  <dd>
                    <Link to={`/tickets/${lead.ticket_id}`} className="text-primary-600 hover:underline">View Ticket</Link>
                  </dd>
                </div>
              )}
              {lead.status === 'lost' && lead.lost_reason && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Lost Reason</dt>
                  <dd className="text-red-600 dark:text-red-400 font-medium capitalize">
                    {LOST_REASONS.find(r => r.value === lead.lost_reason)?.label ?? lead.lost_reason}
                  </dd>
                </div>
              )}
            </dl>
          </div>

          {/* Appointments */}
          {appointments.length > 0 && (
            <div className="card p-5">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3 flex items-center gap-2">
                <Calendar className="h-4 w-4" /> Appointments
              </h3>
              <div className="space-y-2">
                {appointments.map((a: any) => {
                  const apptColor = a.status === 'cancelled' ? '#ef4444' : a.status === 'completed' ? '#22c55e' : '#3b82f6';
                  return (
                    <div key={a.id} className="rounded-lg border border-surface-200 dark:border-surface-700 p-3 text-sm">
                      <div className="flex items-center justify-between">
                        <p className="font-medium text-surface-900 dark:text-surface-100">{a.title}</p>
                        <span
                          className="rounded-full px-1.5 py-0.5 text-[10px] font-medium capitalize"
                          style={{ backgroundColor: `${apptColor}18`, color: apptColor }}
                        >
                          {a.status}
                        </span>
                      </div>
                      <p className="text-xs text-surface-500 mt-0.5">
                        {formatShortDateTime(a.start_time)}
                        {a.end_time && ` - ${new Date(a.end_time).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`}
                      </p>
                      {a.no_show === 1 && (
                        <span className="mt-1 inline-block rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700 dark:bg-amber-900/40 dark:text-amber-400">
                          No-show
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Lost Reason Modal */}
      <LostReasonModal
        open={showLostModal}
        onClose={() => setShowLostModal(false)}
        onConfirm={(reason) => updateMut.mutate({ status: 'lost', lost_reason: reason })}
        isPending={updateMut.isPending}
      />
    </div>
  );
}
