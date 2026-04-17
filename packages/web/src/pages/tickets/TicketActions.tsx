import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowLeft, ChevronDown, Check, MoreHorizontal, Trash2,
  Printer, ShoppingCart, Loader2, GitMerge, Shield, ArrowRightLeft,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { cn } from '@/utils/cn';
import { CopyButton } from '@/components/shared/CopyButton';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { PrintPreviewModal } from '@/components/shared/PrintPreviewModal';
import { safeColor } from '@/utils/safeColor';
import type { Ticket, TicketStatus, TicketDevice } from '@bizarre-crm/shared';

// ─── Helpers ────────────────────────────────────────────────────────

function formatTicketId(orderId: string | number) {
  const str = String(orderId);
  if (str.startsWith('T-')) return str;
  return `T-${str.padStart(4, '0')}`;
}

// ─── Status Dropdown ────────────────────────────────────────────────

function HeaderStatusDropdown({
  currentStatus,
  statuses,
  onSelect,
  isPending,
}: {
  currentStatus?: TicketStatus;
  statuses: TicketStatus[];
  onSelect: (id: number) => void;
  isPending: boolean;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  // @audit-fixed: status colors now go through safeColor (prevents CSS injection from server-supplied hex)
  const headerColor = safeColor(currentStatus?.color);
  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        disabled={isPending}
        className="inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold transition-opacity hover:opacity-80 disabled:opacity-50 border"
        style={{
          backgroundColor: `${headerColor}15`,
          color: headerColor,
          borderColor: `${headerColor}40`,
        }}
      >
        {isPending ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: headerColor }} />
        )}
        {currentStatus?.name ?? 'Unknown'}
        <ChevronDown className="h-4 w-4" />
      </button>

      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 min-w-[18rem] rounded-xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-800">
          <div className="max-h-80 overflow-y-auto py-1">
            {statuses.map((s) => (
              <button
                key={s.id}
                onClick={() => { onSelect(s.id); setOpen(false); }}
                className={cn(
                  'flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm transition-colors hover:bg-surface-50 dark:hover:bg-surface-700',
                  s.id === currentStatus?.id && 'bg-surface-50 dark:bg-surface-700',
                )}
              >
                <span className="h-2.5 w-2.5 rounded-full shrink-0" style={{ backgroundColor: safeColor(s.color) }} />
                <span className="text-surface-700 dark:text-surface-200" title={s.name}>{s.name}</span>
                {s.id === currentStatus?.id && <Check className="ml-auto h-4 w-4 shrink-0 text-primary-500" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Actions Dropdown ───────────────────────────────────────────────

// FA-M1: `onDuplicate` removed — the menu item used to call a toast
// placeholder ("Duplicate not yet implemented") because no backend route
// exists. Hiding the entry is a better user experience than a dead click.
// Restore both the prop and the menu item once a server-side duplicate
// endpoint ships.
function ActionsDropdown({ onDelete, onMerge, onCloneWarranty, onHandoff }: {
  onDelete: () => void; onMerge: () => void; onCloneWarranty: () => void; onHandoff: () => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800"
      >
        <MoreHorizontal className="h-4 w-4" /> More
      </button>
      {open && (
        <div className="absolute right-0 top-full z-50 mt-1 w-48 rounded-xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-800">
          <div className="py-1">
            <button onClick={() => { onMerge(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 transition-colors hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-700">
              <GitMerge className="h-4 w-4" /> Merge Into...
            </button>
            <button onClick={() => { onCloneWarranty(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 transition-colors hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-700">
              <Shield className="h-4 w-4" /> Clone as Warranty
            </button>
            <button onClick={() => { onHandoff(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 transition-colors hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-700">
              <ArrowRightLeft className="h-4 w-4" /> Hand off…
            </button>
            <hr className="my-1 border-surface-200 dark:border-surface-700" />
            <button onClick={() => { onDelete(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-red-600 transition-colors hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/30">
              <Trash2 className="h-4 w-4" /> Delete
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Print Button ───────────────────────────────────────────────────

function PrintButton({ ticketId, invoiceId }: { ticketId: number; invoiceId?: number | null }) {
  const [showModal, setShowModal] = useState(false);
  return (
    <>
      <button
        onClick={() => setShowModal(true)}
        className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800"
      >
        <Printer className="h-4 w-4" /> Print
      </button>
      {showModal && (
        <PrintPreviewModal ticketId={ticketId} invoiceId={invoiceId} onClose={() => setShowModal(false)} />
      )}
    </>
  );
}

// ─── Props ──────────────────────────────────────────────────────────

export interface TicketActionsProps {
  ticket: Ticket;
  ticketId: number;
  devices: TicketDevice[];
  statuses: TicketStatus[];
  currentStatus?: TicketStatus;
  isChangingStatus: boolean;
  onChangeStatus: (statusId: number) => void;
  onDelete: () => void;
  onMerge: () => void;
  onCloneWarranty: () => void;
  onHandoff: () => void;
  activeTab: 'overview' | 'notes' | 'photos' | 'parts';
  setActiveTab: (tab: 'overview' | 'notes' | 'photos' | 'parts') => void;
  notesCount: number;
  photosCount: number;
  partsCount: number;
}

// ─── Main Export ────────────────────────────────────────────────────

export function TicketActions({
  ticket,
  ticketId,
  devices,
  statuses,
  currentStatus,
  isChangingStatus,
  onChangeStatus,
  onDelete,
  onMerge,
  onCloneWarranty,
  onHandoff,
  activeTab,
  setActiveTab,
  notesCount,
  photosCount,
  partsCount,
}: TicketActionsProps) {
  const navigate = useNavigate();

  return (
    <>
      {/* Sticky top header bar */}
      <div className="sticky -top-6 z-20 -mx-6 mb-6 border-b border-transparent bg-surface-50/95 px-6 pt-6 pb-4 backdrop-blur-sm dark:bg-surface-950/95 [.scrolled_&]:border-surface-200 dark:[.scrolled_&]:border-surface-800 [.scrolled_&]:shadow-sm">
        <Breadcrumb items={[
          { label: 'Tickets', href: '/tickets' },
          { label: formatTicketId(ticket.order_id || ticket.id) },
        ]} />

        {/* Main header row */}
        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={() => navigate('/tickets')}
            className="rounded-lg p-2 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-800 dark:hover:text-surface-300"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>

          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100 flex items-center gap-1.5">
            Ticket {formatTicketId(ticket.order_id || ticket.id)}
            <CopyButton text={formatTicketId(ticket.order_id || ticket.id)} />
          </h1>

          {/* Device name pill(s) */}
          {devices.map((d: any) => (
            <span key={d.id} className="inline-flex items-center gap-1.5 rounded-full bg-surface-100 dark:bg-surface-800 px-3 py-1 text-xs font-medium text-surface-600 dark:text-surface-300">
              {(d.imei || d.serial) && <span className="h-2 w-2 rounded-full bg-green-500" title="Has IMEI/Serial" />}
              {d.device_name}
            </span>
          ))}

          {/* Status dropdown */}
          <HeaderStatusDropdown
            currentStatus={currentStatus}
            statuses={statuses}
            onSelect={onChangeStatus}
            isPending={isChangingStatus}
          />

          {/* Checkout button + other actions */}
          <div className="ml-auto flex items-center gap-2">
            <button
              onClick={() => navigate(`/pos?ticket=${ticketId}`)}
              className="inline-flex items-center gap-2 rounded-lg bg-teal-600 px-5 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-teal-700 active:bg-teal-800"
            >
              <ShoppingCart className="h-4 w-4" />
              Checkout
            </button>
            <PrintButton ticketId={ticketId} invoiceId={(ticket as any)?.invoice_id} />
            <ActionsDropdown
              onDelete={onDelete}
              onMerge={onMerge}
              onCloneWarranty={onCloneWarranty}
              onHandoff={onHandoff}
            />
          </div>
        </div>
      </div>

      {/* Tab buttons */}
      <div className="mb-4 flex gap-1 border-b border-surface-200 dark:border-surface-700">
        {([
          { key: 'overview', label: 'Overview' },
          { key: 'notes', label: 'Activity', count: notesCount },
          { key: 'photos', label: 'Photos', count: photosCount },
          { key: 'parts', label: 'Parts & Billing', count: partsCount },
        ] as const).map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={cn(
              'whitespace-nowrap px-4 py-2.5 text-sm font-medium border-b-2 transition-colors',
              activeTab === tab.key
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300',
            )}
          >
            {tab.label}
            {'count' in tab && tab.count > 0 && (
              <span className="ml-1.5 text-[10px] bg-surface-200 dark:bg-surface-700 rounded-full px-1.5 py-0.5">{tab.count}</span>
            )}
          </button>
        ))}
      </div>
    </>
  );
}
