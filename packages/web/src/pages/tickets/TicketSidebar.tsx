import { useState, useEffect, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  User, Phone, Mail, Tag, MessageSquare, CheckCircle2,
  Receipt, ExternalLink, Calendar, Link2, Plus, X,
  Search, Loader2, Clock, CalendarPlus,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi, voiceApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { cn } from '@/utils/cn';
import { formatDate, formatDateTime, formatPhone, timeAgo } from '@/utils/format';
import { safeColor } from '@/utils/safeColor';
import type { Ticket, TicketDevice } from '@bizarre-crm/shared';

// ─── Phone Action Row ───────────────────────────────────────────────

function PhoneActionRow({ phone, customerName, ticketId, onSms }: { phone: string; customerName: string; ticketId: number; onSms: () => void }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div ref={ref} className="relative flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400">
      <Phone className="h-3.5 w-3.5 text-surface-400" />
      <button
        onClick={() => setOpen(!open)}
        className="hover:text-primary-600 dark:hover:text-primary-400 underline decoration-dotted underline-offset-2 transition-colors"
      >
        {phone}
      </button>
      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-44 rounded-lg border border-surface-200 bg-white p-1 shadow-lg dark:border-surface-700 dark:bg-surface-800">
          <a
            href={`tel:${phone}`}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
            onClick={() => setOpen(false)}
          >
            <Phone className="h-3.5 w-3.5 text-green-500" />
            Call {customerName.split(' ')[0]}
          </a>
          <button
            onClick={() => { setOpen(false); onSms(); }}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
          >
            <MessageSquare className="h-3.5 w-3.5 text-blue-500" />
            Send SMS
          </button>
          <button
            onClick={() => { setOpen(false); navigate(`/communications?phone=${encodeURIComponent(phone)}`); }}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
          >
            <ExternalLink className="h-3.5 w-3.5 text-surface-400" />
            SMS History
          </button>
        </div>
      )}
    </div>
  );
}

// ─── Linked Tickets Card (ENR-T8) ──────────────────────────────────

function formatTicketId(orderId: string | number) {
  const str = String(orderId);
  if (str.startsWith('T-')) return str;
  return `T-${str.padStart(4, '0')}`;
}

const LINK_TYPE_LABELS: Record<string, string> = {
  related: 'Related',
  duplicate: 'Duplicate',
  warranty_followup: 'Warranty Follow-up',
};

function LinkedTicketsCard({ ticketId }: { ticketId: number }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [showAdd, setShowAdd] = useState(false);
  const [search, setSearch] = useState('');
  const [linkType, setLinkType] = useState<string>('related');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(debounceRef.current);
  }, [search]);

  const { data: linksData } = useQuery({
    queryKey: ['ticket-links', ticketId],
    queryFn: () => ticketApi.getLinks(ticketId),
  });
  const links: any[] = linksData?.data?.data || [];

  const { data: searchData, isLoading: searchLoading } = useQuery({
    queryKey: ['tickets-link-search', debouncedSearch],
    queryFn: () => ticketApi.list({ keyword: debouncedSearch, pagesize: 8 }),
    enabled: showAdd && debouncedSearch.length >= 2,
  });
  const searchResults = (searchData?.data?.data?.tickets || searchData?.data?.tickets || [])
    .filter((t: any) => t.id !== ticketId && !links.some((l: any) => l.linked_ticket_id === t.id));

  const linkMut = useMutation({
    mutationFn: (linkedTicketId: number) =>
      ticketApi.link(ticketId, { linked_ticket_id: linkedTicketId, link_type: linkType }),
    onSuccess: () => {
      toast.success('Tickets linked');
      queryClient.invalidateQueries({ queryKey: ['ticket-links', ticketId] });
      setShowAdd(false);
      setSearch('');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to link'),
  });

  const unlinkMut = useMutation({
    mutationFn: (linkId: number) => ticketApi.deleteLink(linkId),
    onSuccess: () => {
      toast.success('Link removed');
      queryClient.invalidateQueries({ queryKey: ['ticket-links', ticketId] });
    },
    onError: () => toast.error('Failed to remove link'),
  });

  return (
    <div className="card p-5">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Link2 className="h-4 w-4 text-surface-400" />
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Linked Tickets</h3>
          {links.length > 0 && (
            <span className="ml-1 rounded-full bg-surface-200 px-1.5 py-0.5 text-[10px] font-medium dark:bg-surface-700">
              {links.length}
            </span>
          )}
        </div>
        <button
          onClick={() => setShowAdd(!showAdd)}
          className="rounded p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-700 dark:hover:text-surface-300"
          title="Link a ticket"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>

      {showAdd && (
        <div className="mb-3 space-y-2 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          <select
            value={linkType}
            onChange={(e) => setLinkType(e.target.value)}
            className="w-full rounded border border-surface-200 bg-surface-50 px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
          >
            <option value="related">Related</option>
            <option value="duplicate">Duplicate</option>
            <option value="warranty_followup">Warranty Follow-up</option>
          </select>
          <div className="relative">
            <Search className="absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-surface-400" />
            <input
              autoFocus
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search ticket ID or customer..."
              className="w-full rounded border border-surface-200 bg-surface-50 py-1.5 pl-7 pr-2 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
            />
          </div>
          {searchLoading && debouncedSearch.length >= 2 && (
            <div className="flex justify-center py-2"><Loader2 className="h-4 w-4 animate-spin text-surface-400" /></div>
          )}
          {searchResults.length > 0 && (
            <div className="max-h-32 overflow-y-auto space-y-0.5">
              {searchResults.map((t: any) => (
                <button
                  key={t.id}
                  onClick={() => linkMut.mutate(t.id)}
                  className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-xs hover:bg-surface-50 dark:hover:bg-surface-700"
                >
                  <span className="font-medium text-primary-600 dark:text-primary-400">
                    {formatTicketId(t.order_id || t.id)}
                  </span>
                  <span className="text-surface-600 dark:text-surface-300 truncate">
                    {t.customer ? `${t.customer.first_name} ${t.customer.last_name}` : '--'}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {links.length === 0 && !showAdd && (
        <p className="text-xs text-surface-400 italic">No linked tickets</p>
      )}

      <div className="space-y-1.5">
        {links.map((link: any) => (
          <div key={link.id} className="flex items-center gap-2 group">
            <button
              onClick={() => navigate(`/tickets/${link.linked_ticket_id}`)}
              className="flex-1 flex items-center gap-2 rounded px-2 py-1.5 text-xs hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
            >
              <span className="font-medium text-primary-600 dark:text-primary-400">
                {formatTicketId(link.linked_order_id)}
              </span>
              <span
                className="rounded-full px-1.5 py-0.5 text-[10px] font-medium"
                style={{
                  /* @audit-fixed: pass through safeColor to prevent CSS injection from server-supplied color */
                  backgroundColor: `${safeColor(link.linked_status?.color)}18`,
                  color: safeColor(link.linked_status?.color),
                }}
              >
                {link.linked_status?.name || 'Unknown'}
              </span>
              <span className="text-surface-400 text-[10px]">
                {LINK_TYPE_LABELS[link.link_type] || link.link_type}
              </span>
            </button>
            <button
              onClick={() => unlinkMut.mutate(link.id)}
              className="opacity-0 group-hover:opacity-100 rounded p-0.5 text-surface-400 hover:text-red-500 transition-all"
              title="Remove link"
            >
              <X className="h-3 w-3" />
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Appointments Card (ENR-T12) ───────────────────────────────────

function AppointmentsCard({ ticketId }: { ticketId: number }) {
  const queryClient = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [startTime, setStartTime] = useState('');
  const [endTime, setEndTime] = useState('');
  const [note, setNote] = useState('');

  const { data: apptData } = useQuery({
    queryKey: ['ticket-appointments', ticketId],
    queryFn: () => ticketApi.getAppointments(ticketId),
  });
  const appointments: any[] = apptData?.data?.data || [];

  const createMut = useMutation({
    mutationFn: () => ticketApi.createAppointment(ticketId, {
      start_time: startTime,
      end_time: endTime || undefined,
      note: note || undefined,
    }),
    onSuccess: () => {
      toast.success('Appointment created');
      queryClient.invalidateQueries({ queryKey: ['ticket-appointments', ticketId] });
      queryClient.invalidateQueries({ queryKey: ['ticket-history', ticketId] });
      setShowForm(false);
      setStartTime('');
      setEndTime('');
      setNote('');
    },
    onError: () => toast.error('Failed to create appointment'),
  });

  return (
    <div className="card p-5">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Calendar className="h-4 w-4 text-surface-400" />
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Appointments</h3>
          {appointments.length > 0 && (
            <span className="ml-1 rounded-full bg-surface-200 px-1.5 py-0.5 text-[10px] font-medium dark:bg-surface-700">
              {appointments.length}
            </span>
          )}
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="rounded p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-700 dark:hover:text-surface-300"
          title="Schedule appointment"
        >
          <CalendarPlus className="h-3.5 w-3.5" />
        </button>
      </div>

      {showForm && (
        <div className="mb-3 space-y-2 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          <div>
            <label className="block text-[10px] font-medium text-surface-500 mb-0.5">Start Time *</label>
            <input
              type="datetime-local"
              value={startTime}
              onChange={(e) => setStartTime(e.target.value)}
              className="w-full rounded border border-surface-200 bg-surface-50 px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
            />
          </div>
          <div>
            <label className="block text-[10px] font-medium text-surface-500 mb-0.5">End Time</label>
            <input
              type="datetime-local"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              className="w-full rounded border border-surface-200 bg-surface-50 px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
            />
          </div>
          <div>
            <label className="block text-[10px] font-medium text-surface-500 mb-0.5">Note</label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Optional note..."
              className="w-full rounded border border-surface-200 bg-surface-50 px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
            />
          </div>
          <div className="flex gap-2 pt-1">
            <button
              onClick={() => setShowForm(false)}
              className="rounded px-2 py-1 text-xs text-surface-500 hover:bg-surface-50 dark:hover:bg-surface-700"
            >
              Cancel
            </button>
            <button
              onClick={() => createMut.mutate()}
              disabled={!startTime || createMut.isPending}
              className="rounded bg-primary-600 px-3 py-1 text-xs font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50"
            >
              {createMut.isPending ? 'Creating...' : 'Schedule'}
            </button>
          </div>
        </div>
      )}

      {appointments.length === 0 && !showForm && (
        <p className="text-xs text-surface-400 italic">No appointments</p>
      )}

      <div className="space-y-1.5">
        {appointments.map((appt: any) => {
          const start = new Date(appt.start_time);
          const isPast = start < new Date();
          return (
            <div key={appt.id} className={cn(
              'rounded-lg border px-3 py-2 text-xs',
              isPast
                ? 'border-surface-200 bg-surface-50 dark:border-surface-700 dark:bg-surface-800/50'
                : 'border-primary-200 bg-primary-50 dark:border-primary-800 dark:bg-primary-950/30',
            )}>
              {/* @audit-fixed: use formatDateTime helper instead of browser locale */}
              <div className="flex items-center gap-1.5">
                <Clock className="h-3 w-3 text-surface-400" />
                <span className="font-medium text-surface-700 dark:text-surface-200">
                  {formatDateTime(appt.start_time)}
                </span>
                {appt.end_time && (
                  <span className="text-surface-400">
                    - {new Date(appt.end_time).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
                  </span>
                )}
              </div>
              {appt.notes && (
                <p className="mt-0.5 text-surface-500 dark:text-surface-400">{appt.notes}</p>
              )}
              {appt.assigned_first && (
                <p className="mt-0.5 text-surface-400">
                  Assigned: {appt.assigned_first} {appt.assigned_last}
                </p>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Props ──────────────────────────────────────────────────────────

export interface TicketSidebarProps {
  ticket: Ticket;
  ticketId: number;
  devices: TicketDevice[];
  employees: any[];
  onShowSms: () => void;
  invalidateTicket: () => void;
}

// ─── Main Export ────────────────────────────────────────────────────

export function TicketSidebar({
  ticket,
  ticketId,
  devices,
  employees,
  onShowSms,
  invalidateTicket,
}: TicketSidebarProps) {
  const currentUser = useAuthStore((s) => s.user);
  const customer = ticket?.customer;
  const assigned = ticket?.assigned_user;
  const [showAssignDropdown, setShowAssignDropdown] = useState(false);

  // D4-1: Optimistic assignee swap so the sidebar flips to the new tech
  // immediately instead of waiting for the server PUT + refetch. Picks the
  // full employee object out of the passed-in list so the rendered name
  // matches without the cache being stale.
  const queryClient = useQueryClient();
  const assignMut = useMutation({
    mutationFn: (userId: number | null) => ticketApi.update(ticketId, { assigned_to: userId }),
    onMutate: async (userId) => {
      await queryClient.cancelQueries({ queryKey: ['ticket', ticketId] });
      const prev = queryClient.getQueryData(['ticket', ticketId]);
      queryClient.setQueryData(['ticket', ticketId], (old: any) => {
        if (!old) return old;
        const clone = structuredClone(old); // WEB-FO-012: structuredClone preserves Dates/undefined
        const t = clone?.data?.data;
        if (t) {
          t.assigned_to = userId;
          if (userId == null) {
            t.assigned_user = null;
          } else {
            const emp = employees.find((e: any) => e.id === userId);
            if (emp) {
              t.assigned_user = {
                id: emp.id,
                first_name: emp.first_name ?? null,
                last_name: emp.last_name ?? null,
                avatar_url: emp.avatar_url ?? null,
              };
            }
          }
        }
        return clone;
      });
      return { prev };
    },
    onError: (_err, _vars, ctx: any) => {
      if (ctx?.prev) queryClient.setQueryData(['ticket', ticketId], ctx.prev);
      toast.error('Failed to assign');
    },
    onSuccess: () => toast.success('Ticket assigned'),
    onSettled: () => invalidateTicket(),
  });

  return (
    <div className="space-y-4">
      {/* Customer Information */}
      {customer && (
        <div className="card p-5">
          <div className="mb-3 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <User className="h-4 w-4 text-surface-400" />
              <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Customer Information</h3>
            </div>
            <div className="flex items-center gap-1">
              {(customer.mobile || customer.phone) && (
                <button
                  onClick={async () => {
                    try {
                      const phone = customer.mobile || customer.phone || '';
                      const res = await voiceApi.call({ to: phone, mode: 'bridge', entity_type: 'ticket', entity_id: ticket.id });
                      if (res.data?.success) toast.success('Calling via provider...');
                      else toast.error((res.data as any)?.message || 'Call failed');
                    } catch { toast.error('Call failed'); }
                  }}
                  className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 hover:bg-green-100 dark:hover:bg-green-900/30 transition-colors"
                  title="Call customer via CRM"
                >
                  <Phone className="h-3 w-3" /> Call
                </button>
              )}
              <button onClick={onShowSms}
                className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-primary-50 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400 hover:bg-primary-100 dark:hover:bg-primary-900/30 transition-colors"
                title="Send SMS">
                <MessageSquare className="h-3 w-3" /> SMS
              </button>
              {customer.email && (
                <a href={`mailto:${customer.email}`}
                  className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors"
                  title="Email">
                  <Mail className="h-3 w-3" /> Email
                </a>
              )}
            </div>
          </div>
          <div className="space-y-2.5">
            <Link to={`/customers/${customer.id}`}
              className="text-sm font-semibold text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300">
              {customer.first_name} {customer.last_name}
            </Link>
            {customer.email && (
              <div className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400">
                <Mail className="h-3.5 w-3.5 text-surface-400" />
                <a href={`mailto:${customer.email}`} className="hover:text-primary-600 truncate">{customer.email}</a>
              </div>
            )}
            {(customer.mobile || customer.phone) && (
              <PhoneActionRow
                phone={(customer.mobile || customer.phone)!}
                customerName={`${customer.first_name} ${customer.last_name}`}
                ticketId={ticketId}
                onSms={onShowSms}
              />
            )}
            {customer.organization && (
              <div className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400">
                <Tag className="h-3.5 w-3.5 text-surface-400" />
                <span>{customer.organization}</span>
              </div>
            )}
            <div className="pt-2 flex gap-2">
              <Link to={`/customers/${customer.id}`}
                className="flex-1 text-center rounded-lg border border-surface-200 dark:border-surface-700 px-2 py-1.5 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
                More
              </Link>
              <Link to={`/customers/${customer.id}#assets`}
                className="flex-1 text-center rounded-lg border border-surface-200 dark:border-surface-700 px-2 py-1.5 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
                Customer Assets
              </Link>
            </div>
          </div>
        </div>
      )}

      {/* Warranty Information */}
      {devices.some((d) => d.warranty) && (
        <div className="card p-5">
          <div className="mb-3 flex items-center gap-2">
            <CheckCircle2 className="h-4 w-4 text-surface-400" />
            <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Warranty Information</h3>
          </div>
          {devices.filter((d) => d.warranty).map((d) => {
            const daysRemaining = d.warranty_days ? Math.max(0, d.warranty_days - Math.floor((Date.now() - new Date(d.created_at).getTime()) / 86400000)) : 0;
            return (
              <div key={d.id} className="flex items-center justify-between text-sm mb-1.5 last:mb-0">
                <span className="text-surface-600 dark:text-surface-400">{d.service?.name || d.device_name}</span>
                <span className={cn(
                  'rounded-full px-2 py-0.5 text-xs font-medium',
                  daysRemaining > 30 ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
                    : daysRemaining > 0 ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300'
                    : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300'
                )}>
                  {daysRemaining > 0 ? `${daysRemaining} days left` : 'Expired'}
                </span>
              </div>
            );
          })}
        </div>
      )}

      {/* Ticket Summary */}
      <div className="card p-5">
        <div className="mb-3 flex items-center gap-2">
          <Receipt className="h-4 w-4 text-surface-400" />
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Ticket Summary</h3>
        </div>
        <div className="space-y-2 text-sm">
          <div className="flex justify-between items-center relative">
            <span className="text-surface-500 dark:text-surface-400">Assignee</span>
            <div className="relative">
              <button
                onClick={() => setShowAssignDropdown(!showAssignDropdown)}
                className="text-surface-700 dark:text-surface-300 hover:text-teal-600 dark:hover:text-teal-400 border-b border-dashed border-surface-300 dark:border-surface-600 cursor-pointer"
              >
                {assigned ? `${assigned.first_name} ${assigned.last_name}` : 'Unassigned'}
              </button>
              {showAssignDropdown && (
                <div className="absolute right-0 top-full z-20 mt-1 w-48 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                  {currentUser && (!assigned || assigned.id !== currentUser.id) && (
                    <button
                      onClick={() => { assignMut.mutate(currentUser.id); setShowAssignDropdown(false); }}
                      className="w-full px-3 py-2 text-left text-xs font-medium text-teal-600 hover:bg-teal-50 dark:text-teal-400 dark:hover:bg-teal-900/20"
                    >
                      Assign to me
                    </button>
                  )}
                  {employees.map((emp: any) => (
                    <button
                      key={emp.id}
                      onClick={() => { assignMut.mutate(emp.id); setShowAssignDropdown(false); }}
                      className={cn('w-full px-3 py-1.5 text-left text-xs hover:bg-surface-50 dark:hover:bg-surface-700',
                        ticket?.assigned_to === emp.id ? 'font-bold text-teal-600 dark:text-teal-400' : 'text-surface-700 dark:text-surface-300'
                      )}
                    >
                      {emp.first_name} {emp.last_name}
                    </button>
                  ))}
                  {assigned && (
                    <button
                      onClick={() => { assignMut.mutate(null); setShowAssignDropdown(false); }}
                      className="w-full border-t border-surface-200 px-3 py-1.5 text-left text-xs text-red-500 hover:bg-red-50 dark:border-surface-700 dark:hover:bg-red-900/10"
                    >
                      Unassign
                    </button>
                  )}
                </div>
              )}
            </div>
          </div>
          <div className="flex justify-between">
            <span className="text-surface-500 dark:text-surface-400">Created</span>
            <span className="text-surface-700 dark:text-surface-300">{formatDateTime(ticket.created_at)}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-surface-500 dark:text-surface-400">Updated</span>
            <span className="text-surface-700 dark:text-surface-300">{formatDateTime(ticket.updated_at)}</span>
          </div>
          {ticket.due_on && (
            <div className="flex justify-between">
              <span className="text-surface-500 dark:text-surface-400">Due Date</span>
              <span className="font-medium text-surface-800 dark:text-surface-200">{formatDate(ticket.due_on)}</span>
            </div>
          )}
          {ticket.source && (
            <div className="flex justify-between">
              <span className="text-surface-500 dark:text-surface-400">Source</span>
              <span className="text-surface-700 dark:text-surface-300">{ticket.source}</span>
            </div>
          )}
          {ticket.referral_source && (
            <div className="flex justify-between">
              <span className="text-surface-500 dark:text-surface-400">Referral</span>
              <span className="text-surface-700 dark:text-surface-300">{ticket.referral_source}</span>
            </div>
          )}
        </div>
      </div>

      {/* Labels */}
      {ticket.labels && ticket.labels.length > 0 && (
        <div className="card p-5">
          <div className="mb-3 flex items-center gap-2">
            <Tag className="h-4 w-4 text-surface-400" />
            <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Labels</h3>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {ticket.labels.map((label: string) => (
              <span key={label}
                className="inline-flex items-center rounded-full bg-surface-100 px-2.5 py-0.5 text-xs font-medium text-surface-700 dark:bg-surface-700 dark:text-surface-300">
                {label}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Linked Tickets (ENR-T8) */}
      <LinkedTicketsCard ticketId={ticketId} />

      {/* Appointments (ENR-T12) */}
      <AppointmentsCard ticketId={ticketId} />
    </div>
  );
}
