import { useState, useEffect, useRef, useCallback } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Search, Plus, UserPlus, ChevronLeft, ChevronRight, Trash2, Eye,
  ArrowRightLeft, Phone, Mail, X, Loader2, ChevronDown, BarChart3,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { leadApi, settingsApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { cn } from '@/utils/cn';
import { formatPhone, formatDate } from '@/utils/format';

// ─── Status config ───────────────────────────────────────────────
const LEAD_STATUSES = [
  { value: '', label: 'All' },
  { value: 'new', label: 'New', color: '#3b82f6' },
  { value: 'contacted', label: 'Contacted', color: '#8b5cf6' },
  { value: 'scheduled', label: 'Scheduled', color: '#f59e0b' },
  { value: 'converted', label: 'Converted', color: '#22c55e' },
  { value: 'lost', label: 'Lost', color: '#ef4444' },
] as const;

const SERVICE_TYPE_LABELS: Record<number, string> = {
  1: 'Mail In',
  2: 'Walk In',
  3: 'On Site',
  4: 'Pick Up',
  5: 'Drop Off',
};

function getStatusConfig(status: string) {
  return LEAD_STATUSES.find((s) => s.value === status) ?? { value: status, label: status, color: '#6b7280' };
}

function StatusBadge({ status }: { status: string }) {
  const cfg = getStatusConfig(status);
  const color = 'color' in cfg ? cfg.color : '#6b7280';
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
      style={{ backgroundColor: `${color}18`, color }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
      {cfg.label}
    </span>
  );
}

function formatPhoneDisplay(phone: string): string {
  if (!phone) return '';
  return formatPhone(phone);
}

function getScoreColor(score: number): string {
  if (score >= 70) return '#22c55e';
  if (score >= 40) return '#f59e0b';
  return '#ef4444';
}

function LeadScoreBadge({ score }: { score: number }) {
  const color = getScoreColor(score);
  return (
    <div className="flex items-center gap-1.5">
      <div className="h-1.5 w-12 rounded-full bg-surface-200 dark:bg-surface-700">
        <div
          className="h-full rounded-full transition-all"
          style={{ width: `${score}%`, backgroundColor: color }}
        />
      </div>
      <span className="text-xs font-medium" style={{ color }}>{score}</span>
    </div>
  );
}

// ─── Skeleton rows ──────────────────────────────────────────────
function SkeletonRow() {
  return (
    <tr className="animate-pulse">
      {Array.from({ length: 10 }).map((_, i) => (
        <td key={i} className="px-4 py-3">
          <div className="h-4 w-20 rounded bg-surface-200 dark:bg-surface-700" />
        </td>
      ))}
    </tr>
  );
}

// ─── Create Lead Modal ──────────────────────────────────────────
function CreateLeadModal({
  open,
  onClose,
  users,
}: {
  open: boolean;
  onClose: () => void;
  users: { id: number; first_name: string; last_name: string }[];
}) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    first_name: '',
    last_name: '',
    email: '',
    phone: '',
    source: '',
    notes: '',
    assigned_to: '',
  });

  const createMut = useMutation({
    mutationFn: (data: any) => leadApi.create(data),
    onSuccess: () => {
      toast.success('Lead created');
      queryClient.invalidateQueries({ queryKey: ['leads'] });
      onClose();
      setForm({ first_name: '', last_name: '', email: '', phone: '', source: '', notes: '', assigned_to: '' });
    },
    onError: () => toast.error('Failed to create lead'),
  });

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div className="w-full max-w-lg rounded-xl bg-white shadow-2xl dark:bg-surface-800">
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">New Lead</h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5" />
          </button>
        </div>
        <form
          className="space-y-4 px-6 py-4"
          onSubmit={(e) => {
            e.preventDefault();
            createMut.mutate({
              ...form,
              assigned_to: form.assigned_to ? Number(form.assigned_to) : null,
            });
          }}
        >
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">First Name *</label>
              <input
                required
                value={form.first_name}
                onChange={(e) => setForm((f) => ({ ...f, first_name: e.target.value }))}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Last Name</label>
              <input
                value={form.last_name}
                onChange={(e) => setForm((f) => ({ ...f, last_name: e.target.value }))}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Phone</label>
              <input
                value={form.phone}
                onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Email</label>
              <input
                type="email"
                value={form.email}
                onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Source</label>
              <input
                value={form.source}
                onChange={(e) => setForm((f) => ({ ...f, source: e.target.value }))}
                placeholder="Walk-in, Phone, Web..."
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
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
              Create Lead
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────
export function LeadListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Number(searchParams.get('page') || '1');
  const pageSize = Number(searchParams.get('pagesize') || localStorage.getItem('leads_pagesize') || '25');
  const keyword = searchParams.get('keyword') || '';
  const statusFilter = searchParams.get('status') || '';

  const [searchInput, setSearchInput] = useState(keyword);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [showCreate, setShowCreate] = useState(false);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        if (searchInput) next.set('keyword', searchInput); else next.delete('keyword');
        next.set('page', '1');
        return next;
      });
    }, 400);
    return () => clearTimeout(debounceRef.current);
  }, [searchInput, setSearchParams]);

  // Fetch users
  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => settingsApi.getUsers(),
  });
  const users: { id: number; first_name: string; last_name: string }[] =
    usersData?.data?.data?.users || usersData?.data?.data || [];

  // Fetch leads
  const leadParams = {
    page,
    pagesize: pageSize,
    ...(keyword ? { keyword } : {}),
    ...(statusFilter ? { status: statusFilter } : {}),
  };

  const { data: leadData, isLoading, isFetching } = useQuery({
    queryKey: ['leads', leadParams],
    queryFn: () => leadApi.list(leadParams),
    placeholderData: (prev: any) => prev,
  });

  const leads: any[] = leadData?.data?.data?.leads || [];
  const pagination = leadData?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1, per_page: 20 };

  // Convert mutation
  const convertMut = useMutation({
    mutationFn: (id: number) => leadApi.convert(id),
    onSuccess: (res, leadId) => {
      const ticketId = res?.data?.data?.ticket?.id;
      toast.success('Lead converted to ticket');
      queryClient.invalidateQueries({ queryKey: ['leads'] });
      // Invalidate the specific lead detail cache so its page reflects the converted state
      queryClient.invalidateQueries({ queryKey: ['leads', leadId] });
      queryClient.invalidateQueries({ queryKey: ['lead', leadId] });
      if (ticketId) navigate(`/tickets/${ticketId}`);
    },
    onError: (err: any) => {
      console.error('Lead convert failed:', err);
      const msg = err?.response?.data?.message
        || err?.message
        || 'Failed to convert lead. Please try again.';
      toast.error(msg);
    },
  });

  // Delete mutation
  // Lead delete wrapped in a 5s undo window (D4-5). Optimistically drop the
  // row from cached lead lists, then fire the server delete after 5s unless
  // Undo is clicked.
  const deleteUndo = useUndoableAction<{ id: number; name?: string }>(
    async ({ id }) => {
      await leadApi.delete(id);
      queryClient.invalidateQueries({ queryKey: ['leads'] });
    },
    {
      timeoutMs: 5000,
      pendingMessage: ({ name }) => (name ? `Deleting lead "${name}"…` : 'Deleting lead…'),
      successMessage: 'Lead deleted',
      errorMessage: (_a, err: unknown) => {
        const e = err as { response?: { data?: { message?: string } }; message?: string };
        console.error('Lead delete failed:', err);
        return e?.response?.data?.message || e?.message || 'Failed to delete lead. Please try again.';
      },
      onUndo: () => {
        queryClient.invalidateQueries({ queryKey: ['leads'] });
      },
    },
  );

  const scheduleLeadDelete = useCallback(
    (id: number, name?: string) => {
      queryClient.setQueriesData({ queryKey: ['leads'] }, (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.leads || clone?.data?.leads;
        if (Array.isArray(list)) {
          const filtered = list.filter((l: any) => l.id !== id);
          if (clone?.data?.data?.leads) clone.data.data.leads = filtered;
          else if (clone?.data?.leads) clone.data.leads = filtered;
        }
        return clone;
      });
      deleteUndo.trigger({ id, name });
    },
    [queryClient, deleteUndo],
  );

  function setParam(key: string, value: string) {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      if (value) next.set(key, value); else next.delete(key);
      next.set('page', '1');
      return next;
    });
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Leads</h1>
          <p className="text-surface-500 dark:text-surface-400">Track potential customers and follow-ups</p>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" />
          New Lead
        </button>
      </div>

      {/* Status filter pills */}
      <div className="mb-4 flex flex-wrap gap-2">
        {LEAD_STATUSES.map((s) => {
          const color = 'color' in s ? s.color : '#6b7280';
          const isActive = statusFilter === s.value;
          return (
            <button
              key={s.value}
              onClick={() => setParam('status', s.value)}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition-all',
                isActive
                  ? 'ring-2 ring-offset-1 ring-offset-white dark:ring-offset-surface-900'
                  : 'hover:opacity-80',
              )}
              style={
                s.value
                  ? { backgroundColor: `${color}18`, color, ...(isActive ? { ringColor: color } : {}) }
                  : isActive
                    ? { backgroundColor: '#6b728018', color: '#6b7280' }
                    : { backgroundColor: '#6b728010', color: '#9ca3af' }
              }
            >
              {s.value && <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />}
              {s.label}
            </button>
          );
        })}
      </div>

      <div className="card relative">
        {/* Search bar */}
        <div className="flex items-center gap-3 border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <div className="relative flex-1 max-w-sm">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="text"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Search leads..."
              className="w-full rounded-lg border border-surface-200 bg-surface-50 py-1.5 pl-9 pr-4 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
            />
          </div>
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-surface-200 dark:border-surface-700">
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Lead ID</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Name</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Phone</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Email</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Status</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Score</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Source</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Assigned To</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Created</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {isLoading ? (
                Array.from({ length: 6 }).map((_, i) => <SkeletonRow key={i} />)
              ) : leads.length === 0 ? (
                <tr>
                  <td colSpan={10}>
                    <div className="flex flex-col items-center justify-center py-20">
                      <UserPlus className="mb-4 h-16 w-16 text-surface-300 dark:text-surface-600" />
                      <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">No Leads</h2>
                      <p className="mt-1 max-w-sm text-center text-sm text-surface-400 dark:text-surface-500">
                        {keyword || statusFilter
                          ? 'No leads match your filters. Try adjusting your search or status filter.'
                          : 'Create leads from the POS check-in flow, from an inbound call, or by clicking "New Lead" above.'}
                      </p>
                    </div>
                  </td>
                </tr>
              ) : (
                leads.map((lead) => (
                  <tr
                    key={lead.id}
                    onClick={() => navigate(`/leads/${lead.id}`)}
                    className="cursor-pointer transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/50"
                  >
                    <td className="px-4 py-3 font-medium text-primary-600 dark:text-primary-400">
                      {lead.order_id || `L-${String(lead.id).padStart(4, '0')}`}
                    </td>
                    <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">
                      {lead.first_name} {lead.last_name}
                    </td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400">
                      {lead.phone ? (
                        <a href={`tel:${lead.phone}`} onClick={(e) => e.stopPropagation()} className="inline-flex items-center gap-1 hover:text-primary-600">
                          <Phone className="h-3.5 w-3.5" />
                          {formatPhoneDisplay(lead.phone)}
                        </a>
                      ) : (
                        <span className="text-surface-300 dark:text-surface-600">--</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400">
                      {lead.email ? (
                        <span className="inline-flex items-center gap-1 max-w-[180px] truncate">
                          <Mail className="h-3.5 w-3.5 shrink-0" />
                          {lead.email}
                        </span>
                      ) : (
                        <span className="text-surface-300 dark:text-surface-600">--</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <StatusBadge status={lead.status} />
                    </td>
                    <td className="px-4 py-3">
                      <LeadScoreBadge score={lead.lead_score ?? 0} />
                    </td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400">
                      {lead.source || <span className="text-surface-300 dark:text-surface-600 italic">Not set</span>}
                    </td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400">
                      {lead.assigned_first_name
                        ? `${lead.assigned_first_name} ${lead.assigned_last_name}`
                        : <span className="text-surface-300 dark:text-surface-600 italic">Not set</span>}
                    </td>
                    <td className="px-4 py-3 text-surface-500 dark:text-surface-400">
                      {lead.created_at ? formatDate(lead.created_at) : '--'}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center justify-end gap-1">
                        <button
                          onClick={(e) => { e.stopPropagation(); navigate(`/leads/${lead.id}`); }}
                          className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-700 dark:hover:text-surface-200"
                          title="View Lead"
                        >
                          <Eye className="h-4 w-4" />
                        </button>
                        {lead.status !== 'converted' && (
                          <button
                            onClick={async (e) => {
                              e.stopPropagation();
                              if (await confirm('Convert this lead to a ticket?')) {
                                convertMut.mutate(lead.id);
                              }
                            }}
                            disabled={convertMut.isPending}
                            className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-green-50 hover:text-green-600 dark:hover:bg-green-950/30 dark:hover:text-green-400"
                            title="Convert to Ticket"
                          >
                            <ArrowRightLeft className="h-4 w-4" />
                          </button>
                        )}
                        <button
                          onClick={async (e) => {
                            e.stopPropagation();
                            if (await confirm('Delete this lead?', { danger: true })) {
                              scheduleLeadDelete(lead.id, lead.name);
                            }
                          }}
                          className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-950/30 dark:hover:text-red-400"
                          title="Delete Lead"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
          <div className="flex items-center justify-between border-t border-surface-200 px-4 py-3 dark:border-surface-700">
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-1.5">
                <span className="text-xs text-surface-500 dark:text-surface-400">Show</span>
                <select
                  value={pageSize}
                  onChange={(e) => {
                    const v = e.target.value;
                    localStorage.setItem('leads_pagesize', v);
                    const p = new URLSearchParams(searchParams);
                    p.set('pagesize', v);
                    p.set('page', '1');
                    setSearchParams(p, { replace: true });
                  }}
                  className="text-xs rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-2 py-1 focus:outline-none focus:ring-1 focus:ring-primary-500"
                >
                  {[10, 25, 50, 100, 250].map((n) => (
                    <option key={n} value={n}>{n}</option>
                  ))}
                </select>
                <span className="text-xs text-surface-500 dark:text-surface-400">per page</span>
              </div>
              <p className="text-sm text-surface-500 dark:text-surface-400">
                {pagination.total === 0 ? (
                  'No results'
                ) : (
                  <>
                    Showing {(page - 1) * pagination.per_page + 1}
                    &ndash;
                    {Math.min(page * pagination.per_page, pagination.total)} of {pagination.total}
                  </>
                )}
              </p>
            </div>
            {pagination.total_pages > 1 && (
            <div className="flex items-center gap-1">
              <button
                aria-label="Previous page"
                disabled={page <= 1}
                onClick={() => setParam('page', String(page - 1))}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700 min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              {Array.from({ length: Math.min(pagination.total_pages, 7) }, (_, i) => {
                let pageNum: number;
                if (pagination.total_pages <= 7) {
                  pageNum = i + 1;
                } else if (page <= 4) {
                  pageNum = i + 1;
                } else if (page >= pagination.total_pages - 3) {
                  pageNum = pagination.total_pages - 6 + i;
                } else {
                  pageNum = page - 3 + i;
                }
                return (
                  <button
                    key={pageNum}
                    onClick={() => setParam('page', String(pageNum))}
                    className={cn(
                      'inline-flex items-center justify-center rounded-lg text-sm font-medium transition-colors min-h-[44px] min-w-[44px] md:h-8 md:w-8 md:min-h-0 md:min-w-0',
                      pageNum === page
                        ? 'bg-primary-600 text-white'
                        : 'text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700',
                    )}
                  >
                    {pageNum}
                  </button>
                );
              })}
              <button
                aria-label="Next page"
                disabled={page >= pagination.total_pages}
                onClick={() => setParam('page', String(page + 1))}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700 min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
            )}
          </div>

        {/* Loading overlay */}
        {isFetching && !isLoading && (
          <div className="absolute inset-0 flex items-center justify-center bg-white/40 dark:bg-surface-900/40">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary-200 border-t-primary-600" />
          </div>
        )}
      </div>

      {/* Create modal */}
      <CreateLeadModal open={showCreate} onClose={() => setShowCreate(false)} users={users} />
    </div>
  );
}
