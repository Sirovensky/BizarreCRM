import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { AlertCircle, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi, settingsApi, invoiceApi, employeeApi, smsApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { BackButton } from '@/components/shared/BackButton';
import { QuickSmsModal } from '@/components/shared/QuickSmsModal';
import type { Ticket, TicketStatus, TicketNote, TicketDevice, TicketHistory } from '@bizarre-crm/shared';

import { TicketActions } from './TicketActions';
import { TicketDevices } from './TicketDevices';
import { TicketNotes } from './TicketNotes';
import { TicketPayments } from './TicketPayments';
import { TicketSidebar } from './TicketSidebar';

// ─── Helpers ────────────────────────────────────────────────────────

function formatTicketId(orderId: string | number) {
  const str = String(orderId);
  if (str.startsWith('T-')) return str;
  return `T-${str.padStart(4, '0')}`;
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

// ─── Main Component ─────────────────────────────────────────────────

export function TicketDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const ticketId = Number(id);
  const isValidId = id != null && !isNaN(ticketId) && ticketId > 0;

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
  const statuses: TicketStatus[] = statusData?.data?.data?.statuses || statusData?.data?.statuses || [];

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
  const smsMessages: any[] = (() => {
    const d = smsData?.data?.data;
    return d?.messages || (Array.isArray(d) ? d : []);
  })();

  // ─── Fetch invoice (if linked) ────────────────────────────────────
  const { data: invoiceData } = useQuery({
    queryKey: ['invoice', ticket?.invoice_id],
    queryFn: () => invoiceApi.get(ticket!.invoice_id!),
    enabled: !!ticket?.invoice_id,
  });
  const invoice = invoiceData?.data?.data?.invoice;

  // ─── Fetch employees ──────────────────────────────────────────────
  const { data: employeesData } = useQuery({
    queryKey: ['employees'],
    queryFn: () => employeeApi.list(),
    staleTime: 60_000,
  });
  const employees: any[] = employeesData?.data?.data || [];

  // ─── Mutations ────────────────────────────────────────────────────
  const invalidateTicket = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['ticket', ticketId] });
    queryClient.invalidateQueries({ queryKey: ['ticket-history', ticketId] });
  }, [queryClient, ticketId]);

  const changeStatusMut = useMutation({
    mutationFn: (statusId: number) => ticketApi.changeStatus(ticketId, statusId),
    onSuccess: (_data, newStatusId) => {
      const prevStatusId = ticket?.status_id;
      const newName = statuses.find((s) => s.id === newStatusId)?.name ?? 'Unknown';
      invalidateTicket();
      toast((t) => (
        <span className="flex items-center gap-2 text-sm">
          Status changed to <b>{newName}</b>
          {prevStatusId != null && prevStatusId !== newStatusId && (
            <button
              className="ml-2 rounded bg-surface-200 px-2 py-0.5 text-xs font-medium hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
              onClick={() => { toast.dismiss(t.id); changeStatusMut.mutate(prevStatusId); }}
            >
              Undo
            </button>
          )}
        </span>
      ), { duration: 5000 });
    },
    onError: () => toast.error('Failed to change status'),
  });

  const deleteMut = useMutation({
    mutationFn: () => ticketApi.delete(ticketId),
    onSuccess: () => { toast.success('Ticket deleted'); navigate('/tickets'); },
    onError: () => toast.error('Failed to delete ticket'),
  });

  // ─── UI state ─────────────────────────────────────────────────────
  const [showSms, setShowSms] = useState(false);
  const [editingDeviceId, setEditingDeviceId] = useState<number | null>(null);
  const [partsSearchDeviceId, setPartsSearchDeviceId] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'notes' | 'photos' | 'parts'>('overview');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  // ─── Track recent views ───────────────────────────────────────────
  useEffect(() => {
    if (!ticket) return;
    const key = 'recent_views';
    try {
      const existing: { type: string; id: number; label: string; path: string }[] = JSON.parse(localStorage.getItem(key) || '[]');
      const entry = { type: 'ticket', id: ticket.id, label: formatTicketId(ticket.order_id || ticket.id), path: `/tickets/${ticket.id}` };
      const filtered = existing.filter((e) => !(e.type === 'ticket' && e.id === ticket.id));
      filtered.unshift(entry);
      localStorage.setItem(key, JSON.stringify(filtered.slice(0, 5)));
    } catch { /* ignore */ }
  }, [ticket?.id]);

  // ─── Derived data ─────────────────────────────────────────────────
  const customer = ticket?.customer;
  const devices: TicketDevice[] = ticket?.devices || [];
  const notes: TicketNote[] = ticket?.notes || [];
  const currentStatus = statuses.find((s) => s.id === ticket?.status_id) || ticket?.status;

  // Billing totals
  const allParts = devices.flatMap((d: any) => (d.parts || []).map((p: any) => ({ ...p, deviceName: d.device_name })));
  const paidAmount = invoice?.payments?.reduce((sum: number, p: any) => sum + Number(p.amount), 0) || 0;
  const dueAmount = (ticket?.total || 0) - paidAmount;
  const totalCost = allParts.reduce((sum: number, p: any) => sum + ((p.cost_price || 0) * p.quantity), 0);
  const estimatedProfit = (ticket?.total || 0) - totalCost;

  // Repair time
  const repairTimeMs = ticket ? Date.now() - new Date(ticket.created_at).getTime() : 0;
  const repairDays = Math.floor(repairTimeMs / 86400000);
  const repairHours = Math.floor((repairTimeMs % 86400000) / 3600000);

  // Tab badge counts
  const photosCount = devices.reduce((sum, d: any) => sum + (d.photos?.length || 0), 0);
  const partsCount = devices.reduce((sum, d: any) => sum + (d.parts?.length || 0), 0);
  const notesCount = notes.length + history.length + smsMessages.length;

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
        onChangeStatus={(sId) => changeStatusMut.mutate(sId)}
        onDelete={() => setShowDeleteConfirm(true)}
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
          {/* Device cards + photos tab */}
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

          {/* Activity timeline */}
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
        customer={customer as any}
        ticket={{ id: ticketId, order_id: (ticket as any)?.order_id || '' }}
        device={devices[0] ? { name: (devices[0] as any).device_name || (devices[0] as any).name || '' } : undefined}
      />
    )}

    <ConfirmDialog
      open={showDeleteConfirm}
      title={`Delete Ticket ${ticket ? `T-${String(ticket.order_id).padStart(4, '0')}` : ''}`}
      message="This action cannot be undone. All ticket data, notes, photos, and parts will be permanently deleted."
      confirmLabel="Delete"
      danger
      requireTyping
      confirmText={ticket ? `T-${String(ticket.order_id).padStart(4, '0')}` : 'DELETE'}
      onConfirm={() => { setShowDeleteConfirm(false); deleteMut.mutate(); }}
      onCancel={() => setShowDeleteConfirm(false)}
    />
    </>
  );
}
