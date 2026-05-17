import { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { AlertCircle, Loader2, Search, GitMerge } from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi, settingsApi, invoiceApi, employeeApi, smsApi, benchApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { BackButton } from '@/components/shared/BackButton';
import { QuickSmsModal } from '@/components/shared/QuickSmsModal';
import { useAuthStore } from '@/stores/authStore';
// WEB-FAE-003: per-user namespacing for `recent_views` so a kiosk handoff
// doesn't bleed the previous user's recent ticket numbers into the next
// user's sidebar. Reader is `Sidebar.RecentViews`.
import { recentViewsKey } from '@/components/layout/recentViewsKey';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useEscClose } from '@/hooks/useEscClose';
import { formatTicketId, formatCurrency } from '@/utils/format';
import type { Ticket, TicketStatus, TicketNote, TicketDevice, TicketHistory } from '@bizarre-crm/shared';

import { TicketActions } from './TicketActions';
import { TicketDevices } from './TicketDevices';
import { TicketNotes } from './TicketNotes';
import { TicketPayments } from './TicketPayments';
import { TicketSidebar } from './TicketSidebar';
// D4-4: granular ErrorBoundary isolates a sub-component crash to its own tab
// instead of collapsing the entire route to the PageErrorBoundary fallback.
import { ErrorBoundary } from '@/components/shared/PageErrorBoundary';

// Audit section 44 — technician bench workflow. Additive-only imports; the
// components are safe no-ops when their feature flag is off.
import { BenchTimer } from '@/components/tickets/BenchTimer';
import { DeviceTemplatePicker } from '@/components/tickets/DeviceTemplatePicker';
import { CustomerHistorySidebar } from '@/components/tickets/CustomerHistorySidebar';
import { QcSignOffModal } from '@/components/tickets/QcSignOffModal';
// FA-M8: Ticket handoff lives in the overflow menu now so techs can transfer
// a ticket with a required reason (server logs the handoff audit row).
import { TicketHandoffModal } from '@/components/team/TicketHandoffModal';
import { CheckCircle2, XCircle } from 'lucide-react';

// ─── Helpers ────────────────────────────────────────────────────────

function isRequestCanceled(err: unknown): boolean {
  if (typeof err !== 'object' || err === null) return false;
  const maybe = err as { code?: unknown; name?: unknown };
  return maybe.code === 'ERR_CANCELED' || maybe.name === 'CanceledError' || maybe.name === 'AbortError';
}

function statusFlagEnabled(value: unknown): boolean {
  return value === true || value === 1 || value === '1';
}

interface TicketMutationScope {
  controller: AbortController;
  routeTicketId: number;
}

interface TicketStatusMutationScope extends TicketMutationScope {
  statusId: number;
}

interface TicketCacheEnvelope {
  data: { data: Ticket & { status_id: number } };
}

interface StatusRollbackCtx {
  prev: TicketCacheEnvelope | undefined;
  prevStatusId: number | null;
}

interface TicketListItem {
  id: number;
  order_id: string | number | null;
  customer?: { first_name: string; last_name: string } | null;
  first_device?: { device_name: string } | null;
  devices?: { device_name: string }[] | null;
}

// ─── Loading skeleton ───────────────────────────────────────────────

function DetailSkeleton() {
  return (
    <div className="animate-pulse space-y-6">
      <div className="flex items-center gap-4">
        <div className="h-8 w-8 rounded bg-surface-200 dark:bg-surface-700" />
        <div className="h-7 w-48 rounded bg-surface-200 dark:bg-surface-700" />
        <div className="h-7 w-24 rounded-full bg-surface-200 dark:bg-surface-700" />
      </div>
      <div className="grid grid-cols-3 gap-6">
        <div className="col-span-2 space-y-6">
          <div className="card h-48 p-6"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
          <div className="card h-64 p-6"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
        </div>
        <div className="space-y-4">
          <div className="card h-40 p-4"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
          <div className="card h-32 p-4"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
        </div>
      </div>
    </div>
  );
}

// ─── Merge Dialog ───────────────────────────────────────────────────

function MergeDialog({ ticketId, orderId, onClose, onMerged }: {
  ticketId: number; orderId: string; onClose: () => void; onMerged: () => void;
}) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [isPending, setIsPending] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const mergeAbortRef = useRef<AbortController | null>(null);
  const dialogActiveRef = useRef(true);
  const trapRef = useFocusTrap<HTMLDivElement>(true);
  useEscClose(onClose, true);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(debounceRef.current);
  }, [search]);

  useEffect(() => {
    dialogActiveRef.current = true;
    return () => {
      dialogActiveRef.current = false;
      mergeAbortRef.current?.abort();
      mergeAbortRef.current = null;
    };
  }, []);

  const { data: results, isLoading } = useQuery({
    queryKey: ['tickets-merge-search', debouncedSearch],
    queryFn: () => ticketApi.list({ keyword: debouncedSearch, pagesize: 10 }),
    enabled: debouncedSearch.length >= 2,
  });

  const candidates = ((results?.data?.data?.tickets || results?.data?.tickets || []) as TicketListItem[])
    .filter((t) => t.id !== ticketId);

  async function handleMerge() {
    if (!selectedId) return;
    mergeAbortRef.current?.abort();
    const controller = new AbortController();
    mergeAbortRef.current = controller;
    setIsPending(true);
    try {
      await ticketApi.merge(ticketId, selectedId, controller.signal);
      if (controller.signal.aborted || !dialogActiveRef.current) return;
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
      toast.success('Tickets merged successfully');
      onMerged();
      onClose();
    } catch (err: unknown) {
      if (controller.signal.aborted || !dialogActiveRef.current || isRequestCanceled(err)) return;
      const msg = err instanceof Error ? err.message : 'Merge failed';
      toast.error(msg);
    } finally {
      if (mergeAbortRef.current === controller) mergeAbortRef.current = null;
      if (!controller.signal.aborted && dialogActiveRef.current) setIsPending(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
      role="presentation"
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="merge-ticket-title"
        className="w-full max-w-md rounded-xl bg-white p-6 shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center gap-2">
          <GitMerge className="h-5 w-5 text-primary-500" />
          <h2 id="merge-ticket-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
            Merge Ticket {formatTicketId(orderId)}
          </h2>
        </div>
        <p className="mb-3 text-sm text-surface-500 dark:text-surface-400">
          Select the ticket to merge INTO this one. All devices, notes, and history from the selected ticket will be moved here, and the selected ticket will be deleted.
        </p>
        <div className="relative mb-3">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
          <input
            autoFocus
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by ticket ID, customer, device..."
            className="w-full rounded-lg border border-surface-200 bg-surface-50 py-2 pl-9 pr-4 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus-visible:outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>
        <div className="max-h-48 overflow-y-auto rounded-lg border border-surface-200 dark:border-surface-700">
          {isLoading && debouncedSearch.length >= 2 ? (
            <div className="flex justify-center py-6"><Loader2 className="h-5 w-5 animate-spin text-surface-400" /></div>
          ) : candidates.length === 0 ? (
            <p className="px-3 py-4 text-center text-sm text-surface-400">
              {debouncedSearch.length < 2 ? 'Type to search for tickets...' : 'No matching tickets found'}
            </p>
          ) : (
            candidates.map((t) => (
              <button
                key={t.id}
                onClick={() => setSelectedId(t.id)}
                className={`flex w-full items-center gap-3 px-3 py-2.5 text-left text-sm transition-colors hover:bg-surface-50 dark:hover:bg-surface-700 ${
                  selectedId === t.id ? 'bg-primary-50 dark:bg-primary-950/30 ring-1 ring-primary-300 dark:ring-primary-700' : ''
                }`}
              >
                <span className="font-medium text-primary-600 dark:text-primary-400">
                  {formatTicketId(t.order_id || t.id)}
                </span>
                <span className="text-surface-600 dark:text-surface-300 truncate">
                  {t.customer ? `${t.customer.first_name} ${t.customer.last_name}` : '--'}
                </span>
                <span className="ml-auto text-xs text-surface-400 shrink-0">
                  {t.first_device?.device_name || t.devices?.[0]?.device_name || ''}
                </span>
              </button>
            ))
          )}
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button onClick={onClose}
            className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800">
            Cancel
          </button>
          <button
            onClick={handleMerge}
            disabled={!selectedId || isPending}
            className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-on-primary shadow-sm hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            {isPending ? 'Merging...' : 'Merge'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────

export function TicketDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const ticketId = Number(id);
  const isValidId = id != null && !isNaN(ticketId) && ticketId > 0;
  const ticketMutationControllersRef = useRef<Set<AbortController>>(new Set());
  const activeTicketIdRef = useRef(ticketId);
  const detailMountedRef = useRef(true);

  useEffect(() => {
    detailMountedRef.current = true;
    activeTicketIdRef.current = ticketId;
    return () => {
      detailMountedRef.current = false;
      ticketMutationControllersRef.current.forEach((controller) => controller.abort());
      ticketMutationControllersRef.current.clear();
    };
  }, [ticketId]);

  const beginTicketMutation = useCallback((): TicketMutationScope => {
    const controller = new AbortController();
    ticketMutationControllersRef.current.add(controller);
    return { controller, routeTicketId: ticketId };
  }, [ticketId]);

  const beginStatusMutation = useCallback((statusId: number): TicketStatusMutationScope => ({
    ...beginTicketMutation(),
    statusId,
  }), [beginTicketMutation]);

  const finishTicketMutation = useCallback((controller: AbortController) => {
    ticketMutationControllersRef.current.delete(controller);
  }, []);

  const shouldSuppressTicketMutationFeedback = useCallback((scope: TicketMutationScope, err?: unknown) => (
    scope.controller.signal.aborted ||
    !detailMountedRef.current ||
    scope.routeTicketId !== activeTicketIdRef.current ||
    isRequestCanceled(err)
  ), []);

  // ─── Fetch ticket ─────────────────────────────────────────────────
  const { data: ticketData, isLoading, error } = useQuery({
    queryKey: ['ticket', ticketId],
    queryFn: () => ticketApi.get(ticketId),
    enabled: isValidId,
  });
  const ticket: Ticket | undefined = ticketData?.data?.data;

  // ─── Fetch statuses ───────────────────────────────────────────────
  const { data: statusData } = useQuery({
    queryKey: ['ticket-statuses'],
    queryFn: () => settingsApi.getStatuses(),
  });
  // Server: res.json({ success: true, data: statuses }) — array directly, no .statuses nesting.
  const statuses: TicketStatus[] = statusData?.data?.data || [];

  // ─── Fetch history ────────────────────────────────────────────────
  const { data: historyData } = useQuery({
    queryKey: ['ticket-history', ticketId],
    queryFn: () => ticketApi.getHistory(ticketId),
    enabled: isValidId,
  });
  const history: TicketHistory[] = (() => {
    const d = historyData?.data?.data;
    return Array.isArray(d) ? d : d?.history || ticket?.history || [];
  })();

  // ─── Fetch SMS for customer ───────────────────────────────────────
  const customerPhone = ticket?.customer?.mobile || ticket?.customer?.phone;
  const { data: smsData } = useQuery({
    queryKey: ['ticket-sms', customerPhone],
    queryFn: () => smsApi.messages(encodeURIComponent(customerPhone!)),
    enabled: !!customerPhone,
  });
  // WEB-FC-017: narrow away from any[] — SMS messages have a stable wire shape.
  interface SmsMessageMin { id: number; direction: string; message: string; created_at: string; [key: string]: unknown }
  const smsMessages: SmsMessageMin[] = (() => {
    const d = smsData?.data?.data;
    return d?.messages || (Array.isArray(d) ? d : []);
  })();

  // ─── Fetch invoice (if linked) ────────────────────────────────────
  const { data: invoiceData } = useQuery({
    queryKey: ['invoice', ticket?.invoice_id],
    queryFn: () => invoiceApi.get(ticket!.invoice_id!),
    enabled: !!ticket?.invoice_id,
  });
  // Server: res.json({ success: true, data: <flat invoice> }) — no .invoice nesting.
  const invoice = invoiceData?.data?.data;

  // ─── Fetch employees ──────────────────────────────────────────────
  const { data: employeesData } = useQuery({
    queryKey: ['employees'],
    queryFn: () => employeeApi.list(),
    staleTime: 60_000,
  });
  // WEB-FC-017: minimal employee shape — only id + name used in this page.
  interface EmployeeMin { id: number; first_name?: string; last_name?: string; full_name?: string; [key: string]: unknown }
  const employees: EmployeeMin[] = employeesData?.data?.data || [];

  // ─── Fetch QC sign-off status (WEB-UIUX-880) ─────────────────────
  // Always fetch so the summary card stays visible on completed tickets.
  const { data: qcStatusData } = useQuery({
    queryKey: ['qc-status', ticketId],
    queryFn: () => benchApi.qc.status(ticketId),
    enabled: isValidId,
    retry: false,
  });

  // WEB-UIUX-1105: fetch QC history on demand (when user toggles the panel)
  // so the latest-only /status query stays cheap on every render.
  const [qcHistoryOpen, setQcHistoryOpen] = useState(false);
  const { data: qcHistoryData, isLoading: qcHistoryLoading } = useQuery({
    queryKey: ['qc-history', ticketId],
    queryFn: () => benchApi.qc.history(ticketId),
    enabled: isValidId && qcHistoryOpen,
    retry: false,
  });
  const qcHistory = qcHistoryData?.data?.data?.sign_offs ?? [];
  interface QcSignOffRow {
    id: number;
    tech_user_id: number;
    checklist_results: Array<{ item_id: number; passed: boolean; name?: string }>;
    checklist_results_json?: string;
    notes?: string | null;
    signed_at: string;
    working_photo_path?: string | null;
    tech_signature_path?: string | null;
  }
  const qcStatus: { qc_required: boolean; signed: boolean; sign_off: QcSignOffRow | null } | undefined =
    qcStatusData?.data?.data;

  // ─── Mutations ────────────────────────────────────────────────────
  const invalidateTicketById = useCallback((targetTicketId: number) => {
    queryClient.invalidateQueries({ queryKey: ['ticket', targetTicketId] });
    queryClient.invalidateQueries({ queryKey: ['ticket-history', targetTicketId] });
    queryClient.invalidateQueries({ queryKey: ['tickets', 'kanban'] });
    queryClient.invalidateQueries({ queryKey: ['tickets'] });
  }, [queryClient]);

  const invalidateTicket = useCallback(() => {
    invalidateTicketById(ticketId);
  }, [invalidateTicketById, ticketId]);

  // D4-1: Optimistic status swap on the detail cache so the status pill
  // updates instantly instead of after the server round-trip + refetch.
  const changeStatusMut = useMutation({
    mutationFn: ({ routeTicketId, statusId, controller }: TicketStatusMutationScope) =>
      ticketApi.changeStatus(routeTicketId, statusId, controller.signal),
    onMutate: async ({ routeTicketId, statusId: newStatusId }) => {
      await queryClient.cancelQueries({ queryKey: ['ticket', routeTicketId] });
      const prev = queryClient.getQueryData<TicketCacheEnvelope>(['ticket', routeTicketId]);
      queryClient.setQueryData(['ticket', routeTicketId], (old: TicketCacheEnvelope | undefined) => {
        if (!old) return old;
        // WEB-FO-012 (Fixer-B14 2026-04-25): structuredClone over
        // JSON.parse(JSON.stringify(...)) — preserves Dates/undefined that
        // ticket payloads carry (created_at, etc.) and is faster on hot path.
        const clone = structuredClone(old);
        const t = clone?.data?.data;
        if (t) {
          t.status_id = newStatusId;
          const s = statuses.find((st) => st.id === newStatusId);
          if (s) t.status = s;
        }
        return clone;
      });
      return { prev, prevStatusId: prev?.data?.data?.status_id ?? null } satisfies StatusRollbackCtx;
    },
    onError: (err, vars, ctx: StatusRollbackCtx | undefined) => {
      if (ctx?.prev) queryClient.setQueryData(['ticket', vars.routeTicketId], ctx.prev);
      if (shouldSuppressTicketMutationFeedback(vars, err)) return;
      toast.error('Failed to change status');
    },
    onSuccess: (_data, vars, ctx: StatusRollbackCtx | undefined) => {
      if (shouldSuppressTicketMutationFeedback(vars)) return;
      const prevStatusId = ctx?.prevStatusId ?? ticket?.status_id;
      const newStatusId = vars.statusId;
      const newName = statuses.find((s) => s.id === newStatusId)?.name ?? 'Unknown';
      toast((t) => (
        <span className="flex items-center gap-2 text-sm">
          Status changed to <b>{newName}</b>
          {prevStatusId != null && prevStatusId !== newStatusId && (
            <button
              className="ml-2 rounded bg-surface-200 px-2 py-0.5 text-xs font-medium hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
              onClick={() => { toast.dismiss(t.id); changeStatusMut.mutate(beginStatusMutation(prevStatusId)); }}
            >
              Undo
            </button>
          )}
        </span>
      ), { duration: 5000 });
    },
    onSettled: (_data, err, vars) => {
      finishTicketMutation(vars.controller);
      if (shouldSuppressTicketMutationFeedback(vars, err)) return;
      invalidateTicketById(vars.routeTicketId);
    },
  });

  // Delete wrapped in a 5s undo window (D4-5). We navigate away immediately
  // so the user sees the result, then fire the real delete after 5s unless
  // Undo is clicked. Undo invalidates to restore the ticket in caches.
  const deleteUndo = useUndoableAction<void>(
    async () => {
      await ticketApi.delete(ticketId);
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
    {
      timeoutMs: 5000,
      pendingMessage: 'Deleting ticket…',
      successMessage: 'Ticket deleted',
      errorMessage: 'Failed to delete ticket',
      onUndo: () => {
        queryClient.invalidateQueries({ queryKey: ['tickets'] });
        queryClient.invalidateQueries({ queryKey: ['ticket', ticketId] });
      },
    },
  );

  const scheduleTicketDelete = () => {
    // Optimistic hide: remove the ticket from every cached list so if the
    // user navigates back they don't see the row. The detail cache stays —
    // we keep the page's data so if Undo is clicked, state just works.
    queryClient.setQueriesData({ queryKey: ['tickets'] }, (old: any) => {
      if (!old) return old;
      // WEB-FO-012 (Fixer-B14 2026-04-25): structuredClone — see note above.
      const clone = structuredClone(old);
      const list = clone?.data?.data?.tickets || clone?.data?.tickets;
      if (Array.isArray(list)) {
        const filtered = list.filter((t: any) => t.id !== ticketId);
        if (clone?.data?.data?.tickets) clone.data.data.tickets = filtered;
        else if (clone?.data?.tickets) clone.data.tickets = filtered;
      }
      return clone;
    });
    deleteUndo.trigger();
    navigate('/tickets');
  };

  const cloneWarrantyMut = useMutation({
    mutationFn: (scope: TicketMutationScope) =>
      ticketApi.cloneWarranty(scope.routeTicketId, scope.controller.signal),
    onSuccess: (res, scope) => {
      if (shouldSuppressTicketMutationFeedback(scope)) return;
      const newTicket = res?.data?.data;
      toast.success('Warranty case created');
      if (newTicket?.id) navigate(`/tickets/${newTicket.id}`);
    },
    onError: (err, scope) => {
      if (shouldSuppressTicketMutationFeedback(scope, err)) return;
      toast.error('Failed to clone ticket as warranty');
    },
    onSettled: (_data, _err, scope) => {
      finishTicketMutation(scope.controller);
    },
  });

  const duplicateMut = useMutation({
    mutationFn: (scope: TicketMutationScope) =>
      ticketApi.duplicate(scope.routeTicketId, scope.controller.signal),
    onSuccess: (res, scope) => {
      if (shouldSuppressTicketMutationFeedback(scope)) return;
      const newTicket = res?.data?.data;
      toast.success('Ticket duplicated');
      if (newTicket?.id) navigate(`/tickets/${newTicket.id}`);
    },
    onError: (err, scope) => {
      if (shouldSuppressTicketMutationFeedback(scope, err)) return;
      toast.error('Failed to duplicate ticket');
    },
    onSettled: (_data, _err, scope) => {
      finishTicketMutation(scope.controller);
    },
  });

  const currentUser = useAuthStore((s) => s.user);

  // ─── UI state ─────────────────────────────────────────────────────
  const [showSms, setShowSms] = useState(false);
  const [editingDeviceId, setEditingDeviceId] = useState<number | null>(null);
  const [partsSearchDeviceId, setPartsSearchDeviceId] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'notes' | 'photos' | 'parts'>('overview');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [showMerge, setShowMerge] = useState(false);
  // FA-M8 — handoff modal state
  const [showHandoff, setShowHandoff] = useState(false);
  // Audit 44.10 — QC sign-off modal state
  const [showQcSignOff, setShowQcSignOff] = useState(false);

  // ─── Track recent views ───────────────────────────────────────────
  // WEB-FO-005 (FIXED-by-Fixer-A3 2026-04-25): same RMW race as
  // sms_reminders — two tabs viewing different tickets concurrently each
  // read the same `recent_views`, push their own entry, write back, and
  // one entry vanishes. Serialize via `navigator.locks` when available;
  // otherwise apply a best-effort CAS verification + retry.
  useEffect(() => {
    if (!ticket) return;
    const key = recentViewsKey(currentUser?.id);
    type RecentEntry = { type: string; id: number; label: string; path: string };
    const entry: RecentEntry = { type: 'ticket', id: ticket.id, label: formatTicketId(ticket.order_id || ticket.id), path: `/tickets/${ticket.id}` };
    const apply = () => {
      try {
        const existing: RecentEntry[] = JSON.parse(localStorage.getItem(key) || '[]');
        const list = Array.isArray(existing) ? existing : [];
        const filtered = list.filter((e) => !(e?.type === 'ticket' && e?.id === ticket.id));
        filtered.unshift(entry);
        localStorage.setItem(key, JSON.stringify(filtered.slice(0, 5)));
        // WEB-UIUX-470: notify Sidebar.RecentViews to refresh from cache without
        // re-parsing on every route nav.
        window.dispatchEvent(new CustomEvent('bizarre-crm:recent-views-updated', { detail: { key } }));
      } catch { /* ignore */ }
    };
    const locks = (navigator as Navigator & {
      locks?: { request: (name: string, cb: () => void | Promise<void>) => Promise<void> };
    }).locks;
    if (locks?.request) {
      void locks.request(`recent_views:${currentUser?.id ?? 'anon'}`, () => { apply(); });
    } else {
      apply();
      try {
        const verify = JSON.parse(localStorage.getItem(key) || '[]');
        const seen = Array.isArray(verify) && verify[0]?.type === 'ticket' && verify[0]?.id === ticket.id;
        if (!seen) apply();
      } catch { /* ignore */ }
    }
    // Only depend on the IDs — re-running on every ticket-object reswap
    // would spam localStorage on each refetch tick.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ticket?.id, currentUser?.id]);

  // ─── Derived data ─────────────────────────────────────────────────
  const customer = ticket?.customer;
  const devices: TicketDevice[] = ticket?.devices || [];
  const notes: TicketNote[] = ticket?.notes || [];
  const currentStatus = statuses.find((s) => s.id === ticket?.status_id) || ticket?.status;

  // Billing totals — WEB-FC-017: use TicketDevice (typed) + narrow payment/part shapes.
  interface PartMin { cost_price?: number | null; quantity?: number; [key: string]: unknown }
  interface PaymentMin { amount?: number | string | null; [key: string]: unknown }
  const allParts = devices.flatMap((d) => ((d as unknown as { parts?: PartMin[]; device_name?: string }).parts || []).map((p) => ({ ...p, deviceName: (d as unknown as { device_name?: string }).device_name })));
  const paidAmount = (invoice?.payments as PaymentMin[] | undefined)?.reduce((sum: number, p) => sum + Number(p.amount ?? 0), 0) || 0;
  const hasOpenPayments = paidAmount > 0;
  const dueAmount = (ticket?.total || 0) - paidAmount;
  const totalCost = allParts.reduce((sum: number, p) => sum + ((p.cost_price || 0) * (p.quantity || 0)), 0);
  const estimatedProfit = (ticket?.total || 0) - totalCost;

  // Repair time. BUGHUNT-2026-05-16: SQLite returns 'YYYY-MM-DD HH:MM:SS'
  // (UTC, no 'Z' suffix); V8 parses that as LOCAL time, shifting the elapsed
  // count by the browser's UTC offset.
  const ticketCreatedMs = ticket
    ? new Date(
        ticket.created_at.includes('T') || ticket.created_at.endsWith('Z') || ticket.created_at.includes('+')
          ? ticket.created_at
          : `${ticket.created_at.replace(' ', 'T')}Z`
      ).getTime()
    : 0;
  const repairTimeMs = ticket ? Date.now() - ticketCreatedMs : 0;
  const repairDays = Math.floor(repairTimeMs / 86400000);
  const repairHours = Math.floor((repairTimeMs % 86400000) / 3600000);

  // Tab badge counts — WEB-FC-017: TicketDevice has parts; photos is an extra field.
  const photosCount = devices.reduce((sum, d) => sum + (((d as unknown as { photos?: unknown[] }).photos?.length) || 0), 0);
  const partsCount = devices.reduce((sum, d) => sum + ((d.parts?.length) || 0), 0);
  const notesCount = notes.length + history.length + smsMessages.length;
  const isClosedStatus = statusFlagEnabled(currentStatus?.is_closed);
  const isCancelledStatus = statusFlagEnabled(currentStatus?.is_cancelled);
  const isTerminalTicketStatus = isClosedStatus || isCancelledStatus;
  const qcSignOffBlockedMessage = isTerminalTicketStatus
    ? `QC sign-off is unavailable after a ticket is ${isCancelledStatus ? 'cancelled' : 'closed'}. Move it to an active repair status to sign off.`
    : null;

  useEffect(() => {
    if (isTerminalTicketStatus && showQcSignOff) setShowQcSignOff(false);
  }, [isTerminalTicketStatus, showQcSignOff]);

  // ─── Loading state ────────────────────────────────────────────────
  if (isLoading) {
    return (
      <div>
        <div className="mb-6 flex items-center gap-4">
          <BackButton to="/tickets" />
          <div className="h-7 w-32 animate-pulse rounded bg-surface-200 dark:bg-surface-700" />
        </div>
        <DetailSkeleton />
      </div>
    );
  }

  // ─── Error state ──────────────────────────────────────────────────
  if (!isValidId || error || !ticket) {
    return (
      <div>
        <div className="mb-6 flex items-center gap-4">
          <BackButton to="/tickets" />
        </div>
        <div className="card flex flex-col items-center justify-center py-20">
          <AlertCircle className="mb-4 h-16 w-16 text-red-300" />
          <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">
            {!isValidId ? 'Invalid Ticket ID' : 'Ticket Not Found'}
          </h2>
          <p className="text-sm text-surface-400">
            {!isValidId
              ? 'The URL contains an invalid ticket ID.'
              : 'The ticket you are looking for does not exist or has been deleted.'}
          </p>
        </div>
      </div>
    );
  }

  // ─── Render ───────────────────────────────────────────────────────
  return (
    <>
    <div>
      {/* Header bar + tabs */}
      <TicketActions
        ticket={ticket}
        ticketId={ticketId}
        devices={devices}
        statuses={statuses}
        currentStatus={currentStatus}
        isChangingStatus={changeStatusMut.isPending}
        onChangeStatus={(sId) => changeStatusMut.mutate(beginStatusMutation(sId))}
        onDelete={() => setShowDeleteConfirm(true)}
        hasOpenPayments={hasOpenPayments}
        onMerge={() => {
          if (currentUser?.role !== 'admin') { toast.error('Only admins can merge tickets'); return; }
          setShowMerge(true);
        }}
        onCloneWarranty={() => cloneWarrantyMut.mutate(beginTicketMutation())}
        onDuplicate={() => duplicateMut.mutate(beginTicketMutation())}
        onHandoff={() => setShowHandoff(true)}
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        notesCount={notesCount}
        photosCount={photosCount}
        partsCount={partsCount}
      />

      {/* Two-column layout */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1fr_380px]">
        {/* Left panel (main content) */}
        <div className="space-y-6">
          {/* Device cards + photos tab — isolated so a render bug in the parts
              search or photo grid doesn't take down the activity timeline. */}
          <ErrorBoundary variant="section" boundaryName="TicketDevicesBoundary">
            <TicketDevices
              ticket={ticket}
              ticketId={ticketId}
              devices={devices}
              activeTab={activeTab}
              repairDays={repairDays}
              repairHours={repairHours}
              editingDeviceId={editingDeviceId}
              setEditingDeviceId={setEditingDeviceId}
              partsSearchDeviceId={partsSearchDeviceId}
              setPartsSearchDeviceId={setPartsSearchDeviceId}
              invalidateTicket={invalidateTicket}
            />
          </ErrorBoundary>

          {/* Activity timeline — isolated so a malformed note or history row
              doesn't block the user from editing devices. */}
          <ErrorBoundary variant="section" boundaryName="TicketNotesBoundary">
            <TicketNotes
              ticketId={ticketId}
              notes={notes}
              history={history}
              smsMessages={smsMessages}
              customerPhone={customerPhone}
              customerEmail={customer?.email}
              activeTab={activeTab}
              invalidateTicket={invalidateTicket}
            />
          </ErrorBoundary>
        </div>

        {/* Right panel (sidebar) */}
        <div className="space-y-4">
          <TicketSidebar
            ticket={ticket}
            ticketId={ticketId}
            devices={devices}
            employees={employees}
            onShowSms={() => setShowSms(true)}
            invalidateTicket={invalidateTicket}
          />

          {/* Audit 44 — Bench Timer (auto-hides when feature disabled) */}
          <BenchTimer
            ticketId={ticketId}
            ticketDeviceId={devices[0]?.id}
            employees={employees}
          />

          {/* Audit 44.1 — Repair template picker */}
          <DeviceTemplatePicker
            ticketId={ticketId}
            ticketDeviceId={devices[0]?.id}
            suggestedCategory={devices[0]?.device_type ?? undefined}
            onApplied={invalidateTicket}
          />

          {/* Audit 44.8 — Customer history at a glance */}
          {customer?.id && (
            <CustomerHistorySidebar
              customerId={customer.id}
              currentTicketId={ticketId}
              currentDeviceName={devices[0]?.device_name || ''}
            />
          )}

          {/* WEB-UIUX-880 — QC sign-off summary (read-only, shown when signed) */}
          {qcStatus?.signed && qcStatus.sign_off && (() => {
            const so = qcStatus.sign_off;
            const results: Array<{ item_id: number; passed: boolean; name?: string }> =
              so.checklist_results ?? [];
            const passedCount = results.filter((r) => r.passed).length;
            const failedCount = results.length - passedCount;
            const allPassed = failedCount === 0 && results.length > 0;
            // Derive tech display name from employees list (tech_user_id → name).
            const techEmployee = employees.find((e) => e.id === so.tech_user_id);
            const techName = techEmployee
              ? (techEmployee.full_name || `${techEmployee.first_name ?? ''} ${techEmployee.last_name ?? ''}`.trim())
              : `Tech #${so.tech_user_id}`;
            const signedDate = so.signed_at
              ? new Date(so.signed_at).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
              : null;
            return (
              <div
                className={`rounded-lg border p-3 text-sm ${
                  allPassed
                    ? 'border-green-300 bg-green-50 dark:border-green-700 dark:bg-green-900/20'
                    : 'border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20'
                }`}
              >
                <div className="flex items-center gap-2 font-semibold mb-1">
                  {allPassed ? (
                    <CheckCircle2 className="h-4 w-4 text-green-600 dark:text-green-400 shrink-0" />
                  ) : (
                    <XCircle className="h-4 w-4 text-amber-600 dark:text-amber-400 shrink-0" />
                  )}
                  <span className={allPassed ? 'text-green-800 dark:text-green-200' : 'text-amber-800 dark:text-amber-200'}>
                    QC {allPassed ? 'Passed' : 'Failed'}
                  </span>
                </div>
                <dl className="grid grid-cols-[auto_1fr] gap-x-2 gap-y-0.5 text-xs">
                  <dt className="text-surface-500 dark:text-surface-400">Tech</dt>
                  <dd className="text-surface-700 dark:text-surface-200 font-medium">{techName}</dd>
                  {signedDate && (
                    <>
                      <dt className="text-surface-500 dark:text-surface-400">Date</dt>
                      <dd className="text-surface-700 dark:text-surface-200">{signedDate}</dd>
                    </>
                  )}
                  {results.length > 0 && (
                    <>
                      <dt className="text-surface-500 dark:text-surface-400">Checklist</dt>
                      <dd className="text-surface-700 dark:text-surface-200">
                        {passedCount}/{results.length} passed
                        {failedCount > 0 && (
                          <span className="ml-1 text-amber-700 dark:text-amber-400">
                            ({failedCount} failed)
                          </span>
                        )}
                      </dd>
                    </>
                  )}
                </dl>
                {so.notes && (
                  <p className="mt-1.5 text-xs text-surface-600 dark:text-surface-300 border-t border-surface-200 dark:border-surface-700 pt-1.5">
                    {so.notes}
                  </p>
                )}
                {/* WEB-UIUX-1105: history panel */}
                <button
                  type="button"
                  onClick={() => setQcHistoryOpen((v) => !v)}
                  className="mt-2 text-xs font-medium text-primary-600 hover:underline dark:text-primary-400"
                >
                  {qcHistoryOpen ? 'Hide past sign-offs' : 'View past sign-offs'}
                </button>
                {qcHistoryOpen && (
                  <div className="mt-2 space-y-1.5 border-t border-surface-200 pt-2 dark:border-surface-700">
                    {qcHistoryLoading ? (
                      <p className="text-xs text-surface-500">Loading history…</p>
                    ) : qcHistory.length === 0 ? (
                      <p className="text-xs text-surface-500">No prior sign-offs.</p>
                    ) : (
                      qcHistory.map((row) => {
                        const histTech = employees.find((e) => e.id === row.tech_user_id);
                        const histTechName = histTech
                          ? (histTech.full_name || `${histTech.first_name ?? ''} ${histTech.last_name ?? ''}`.trim())
                          : [row.first_name, row.last_name].filter(Boolean).join(' ') || `Tech #${row.tech_user_id}`;
                        const histDate = row.signed_at
                          ? new Date(row.signed_at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
                          : '—';
                        const histPassed = row.checklist_results.filter((c) => c.passed).length;
                        const histTotal = row.checklist_results.length;
                        return (
                          <div key={row.id} className="rounded border border-surface-200 bg-white px-2 py-1.5 text-xs dark:border-surface-700 dark:bg-surface-800">
                            <div className="flex items-center justify-between gap-2">
                              <span className="font-medium">{histTechName}</span>
                              <span className="text-surface-500">{histDate}</span>
                            </div>
                            <div className="mt-0.5 flex flex-wrap items-center gap-2 text-surface-500 dark:text-surface-400">
                              <span>{histPassed}/{histTotal} passed</span>
                              {row.outcome && <span className="capitalize">· {row.outcome}</span>}
                              {row.working_photo_path && (
                                <a
                                  href={`/uploads/${row.working_photo_path}`}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="text-primary-600 hover:underline dark:text-primary-400"
                                >
                                  photo
                                </a>
                              )}
                            </div>
                          </div>
                        );
                      })
                    )}
                  </div>
                )}
              </div>
            );
          })()}

          {/* WEB-UIUX-1098: only show QC launcher when the shop has qc_required
              enabled AND the ticket hasn't already been signed off. The signed
              summary card above replaces the launcher once a pass row exists.
              Terminal-status (closed/cancelled) keeps the disabled-with-reason
              affordance instead of disappearing, so admins know why it's gone. */}
          {qcStatus?.qc_required && !qcStatus.signed && (
            <>
              <button
                type="button"
                onClick={() => {
                  if (isTerminalTicketStatus) return;
                  setShowQcSignOff(true);
                }}
                disabled={isTerminalTicketStatus}
                aria-describedby={qcSignOffBlockedMessage ? 'qc-signoff-terminal-note' : undefined}
                title={qcSignOffBlockedMessage ?? undefined}
                className={`flex w-full items-center justify-center gap-2 rounded-lg border px-3 py-2 text-sm font-semibold transition-colors ${
                  isTerminalTicketStatus
                    ? 'cursor-not-allowed border-surface-200 bg-surface-50 text-surface-400 dark:border-surface-700 dark:bg-surface-800/60 dark:text-surface-500'
                    : 'border-green-200 bg-green-50 text-green-700 hover:bg-green-100 dark:border-green-800 dark:bg-green-900/20 dark:text-green-300 dark:hover:bg-green-900/40'
                }`}
              >
                <CheckCircle2 className="h-4 w-4" />
                {isTerminalTicketStatus ? 'QC sign-off locked' : 'QC sign-off'}
              </button>
              {qcSignOffBlockedMessage && (
                <p
                  id="qc-signoff-terminal-note"
                  className="-mt-2 text-xs leading-5 text-surface-500 dark:text-surface-400"
                >
                  {qcSignOffBlockedMessage}
                </p>
              )}
            </>
          )}

          {/* Billing + Invoice cards */}
          <TicketPayments
            ticket={ticket}
            ticketId={ticketId}
            devices={devices}
            invoice={invoice}
            paidAmount={paidAmount}
            dueAmount={dueAmount}
            allParts={allParts}
            totalCost={totalCost}
            estimatedProfit={estimatedProfit}
            invalidateTicket={invalidateTicket}
            onNavigate={navigate}
          />
        </div>
      </div>
    </div>

    {/* SMS Modal */}
    {showSms && customer && (
      <QuickSmsModal
        onClose={() => setShowSms(false)}
        customer={{ first_name: customer.first_name, last_name: customer.last_name, phone: customer.phone ?? undefined, mobile: customer.mobile ?? undefined }}
        ticket={{ id: ticketId, order_id: ticket.order_id || '' }}
        device={devices[0] ? { name: devices[0].device_name || '' } : undefined}
      />
    )}

    <ConfirmDialog
      open={showDeleteConfirm}
      title={`Delete Ticket ${ticket ? `T-${String(ticket.order_id).padStart(4, '0')}` : ''}`}
      message={
        <div className="space-y-2">
          {ticket && (
            <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs">
              <dt className="text-surface-400 dark:text-surface-500">Customer</dt>
              <dd className="font-medium text-surface-700 dark:text-surface-200">
                {customer
                  ? `${customer.first_name} ${customer.last_name}`
                  : <span className="italic text-surface-400">Walk-in</span>}
              </dd>
              <dt className="text-surface-400 dark:text-surface-500">Device(s)</dt>
              <dd className="font-medium text-surface-700 dark:text-surface-200">
                {devices.length > 0
                  ? devices.map((d) => (d as unknown as { device_name?: string }).device_name).filter(Boolean).join(', ')
                  : <span className="italic text-surface-400">None</span>}
              </dd>
              <dt className="text-surface-400 dark:text-surface-500">Invoice total</dt>
              <dd className="font-medium text-surface-700 dark:text-surface-200">
                {ticket.total != null
                  ? formatCurrency(ticket.total)
                  : <span className="italic text-surface-400">—</span>}
              </dd>
            </dl>
          )}
          <p className="text-sm text-surface-500 dark:text-surface-400">
            This ticket will be removed from all views. All associated notes, photos, and parts will no longer be accessible.
          </p>
        </div>
      }
      confirmLabel="Delete"
      danger
      requireTyping
      confirmText={ticket ? `T-${String(ticket.order_id).padStart(4, '0')}` : 'DELETE'}
      onConfirm={() => { setShowDeleteConfirm(false); scheduleTicketDelete(); }}
      onCancel={() => setShowDeleteConfirm(false)}
    />

    {/* Merge Modal (ENR-T3) */}
    {showMerge && (
      <MergeDialog
        ticketId={ticketId}
        orderId={String(ticket.order_id || ticket.id)}
        onClose={() => setShowMerge(false)}
        onMerged={() => { invalidateTicket(); queryClient.invalidateQueries({ queryKey: ['tickets'] }); }}
      />
    )}

    {/* Audit 44.10 — QC Sign-Off Modal */}
    {showQcSignOff && !isTerminalTicketStatus && (
      <QcSignOffModal
        ticketId={ticketId}
        ticketDeviceId={devices[0]?.id}
        deviceCategory={devices[0]?.device_type ?? undefined}
        onClose={() => setShowQcSignOff(false)}
        onSigned={invalidateTicket}
      />
    )}

    {/* FA-M8 — Handoff Modal */}
    {showHandoff && (
      <TicketHandoffModal
        ticketId={ticketId}
        currentAssigneeId={ticket.assigned_to ?? null}
        onClose={() => setShowHandoff(false)}
        onHandedOff={() => {
          invalidateTicket();
          queryClient.invalidateQueries({ queryKey: ['team', 'my-queue'] });
        }}
      />
    )}
    </>
  );
}
