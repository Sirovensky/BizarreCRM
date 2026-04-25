import { useState, useEffect, useRef, useCallback, useMemo, Fragment, memo } from 'react';
import { useSearchParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Search, Plus, Wrench, ChevronLeft, ChevronRight, Trash2, Eye,
  ChevronDown, X, MoreHorizontal, Check, Settings2, MessageSquare, Stethoscope, Package,
  ArrowUp, ArrowDown, ArrowUpDown, Printer, Pin, List, CalendarDays, Send, Kanban,
  Download, Bookmark, BookmarkX, AlertTriangle,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi, settingsApi, smsApi } from '@/api/endpoints';
import { CustomerPreviewPopover } from '@/components/shared/CustomerPreviewPopover';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { cn } from '@/utils/cn';
import { CopyButton } from '@/components/shared/CopyButton';
import { useSettings } from '@/hooks/useSettings';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { PrintPreviewModal } from '@/components/shared/PrintPreviewModal';
import KanbanBoard from './KanbanBoard';
import type { Ticket, TicketStatus } from '@bizarre-crm/shared';
import { formatCurrency, formatDate, timeAgo } from '@/utils/format';

// ─── Optional column definitions ──────────────────────────────────
type OptionalColumn = 'internal_note' | 'diagnostic_note' | 'ticket_items' | 'assigned_to';

const OPTIONAL_COLUMNS: { key: OptionalColumn; label: string; icon: any }[] = [
  { key: 'internal_note', label: 'Internal Note', icon: MessageSquare },
  { key: 'diagnostic_note', label: 'Diagnostic Note', icon: Stethoscope },
  { key: 'ticket_items', label: 'Ticket Items', icon: Package },
  { key: 'assigned_to', label: 'Assigned To', icon: Settings2 },
];

// ─── Date filter tabs ───────────────────────────────────────────────
const DATE_TABS = [
  { label: 'ALL', value: '' },
  { label: 'TODAY', value: 'today' },
  { label: 'YESTERDAY', value: 'yesterday' },
  { label: '7D', value: '7days' },
  { label: '14D', value: '14days' },
  { label: '30D', value: '30days' },
] as const;

// ─── Sortable columns ──────────────────────────────────────────────
type SortColumn = 'order_id' | 'created_at' | 'total' | 'status_id' | 'urgency';

const SORT_COLUMNS: Record<SortColumn, string> = {
  order_id: 'order_id',
  created_at: 'created_at',
  total: 'total',
  status_id: 'status_id',
  urgency: 'urgency',
};

// ─── Helpers ────────────────────────────────────────────────────────
function formatTicketId(orderId: string | number) {
  const str = String(orderId);
  if (str.startsWith('T-')) return str;
  return `T-${str.padStart(4, '0')}`;
}


// ─── Hex color validation ────────────────────────────────────────────
const HEX_RE = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;
function safeColor(color?: string | null): string {
  return color && HEX_RE.test(color) ? color : '#6b7280';
}


// ─── Urgency config ─────────────────────────────────────────────────
const URGENCY_CONFIG: Record<string, { label: string; color: string; dotColor: string }> = {
  critical: { label: 'Critical', color: 'text-red-600 dark:text-red-400', dotColor: '#dc2626' },
  high:     { label: 'High',     color: 'text-orange-600 dark:text-orange-400', dotColor: '#ea580c' },
  medium:   { label: 'Medium',   color: 'text-amber-600 dark:text-amber-400', dotColor: '#d97706' },
  normal:   { label: 'Normal',   color: 'text-surface-500 dark:text-surface-400', dotColor: '#6b7280' },
  low:      { label: 'Low',      color: 'text-surface-400 dark:text-surface-500', dotColor: '#9ca3af' },
};

const UrgencyDot = memo(function UrgencyDot({ urgency, showLabel = false }: { urgency?: string; showLabel?: boolean }) {
  const cfg = URGENCY_CONFIG[urgency || 'normal'] || URGENCY_CONFIG.normal;
  return (
    <span className="inline-flex items-center gap-1 shrink-0" title={cfg.label}>
      <span
        className="inline-block h-2.5 w-2.5 rounded-full shrink-0"
        style={{ backgroundColor: cfg.dotColor }}
      />
      {showLabel && <span className={`text-[10px] font-medium ${cfg.color}`}>{cfg.label}</span>}
    </span>
  );
});

// ─── StatusDropdown (inline, with outside-click close) ──────────────
function StatusDropdown({
  ticket,
  statuses,
  onChangeStatus,
}: {
  ticket: Ticket;
  statuses: TicketStatus[];
  onChangeStatus: (ticketId: number, statusId: number) => void;
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

  const current = ticket.status;

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={(e) => { e.stopPropagation(); setOpen((v) => !v); }}
        className="inline-flex items-center gap-1 rounded-full px-3 py-2 min-h-[44px] md:min-h-0 md:px-2.5 md:py-0.5 text-xs font-medium transition-opacity hover:opacity-80"
        style={{ backgroundColor: `${safeColor(current?.color)}18`, color: safeColor(current?.color) }}
      >
        <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: safeColor(current?.color) }} />
        <span className="min-w-[80px] max-w-[180px] leading-tight" title={current?.name ?? 'Unknown'}>{current?.name ?? 'Unknown'}</span>
        <ChevronDown className="h-3 w-3" />
      </button>

      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-56 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
          <div className="max-h-64 overflow-y-auto py-1">
            {statuses.map((s) => (
              <button
                key={s.id}
                onClick={(e) => {
                  e.stopPropagation();
                  onChangeStatus(ticket.id, s.id);
                  setOpen(false);
                }}
                className={cn(
                  'flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-surface-50 dark:hover:bg-surface-700',
                  s.id === ticket.status_id && 'bg-surface-50 dark:bg-surface-700',
                )}
              >
                <span className="h-2 w-2 rounded-full shrink-0" style={{ backgroundColor: safeColor(s.color) }} />
                <span className="truncate text-surface-700 dark:text-surface-200">{s.name}</span>
                {s.id === ticket.status_id && <Check className="ml-auto h-3.5 w-3.5 text-primary-500" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── SortHeader ─────────────────────────────────────────────────────
function SortHeader({
  label,
  column,
  currentSort,
  currentOrder,
  onSort,
  className,
}: {
  label: string;
  column: SortColumn;
  currentSort: string;
  currentOrder: string;
  onSort: (col: SortColumn) => void;
  className?: string;
}) {
  const isActive = currentSort === column;
  const isAsc = isActive && currentOrder === 'ASC';
  const isDesc = isActive && currentOrder === 'DESC';

  return (
    <th
      className={cn(
        'px-4 py-3 font-medium text-surface-500 dark:text-surface-400 cursor-pointer select-none hover:text-surface-700 dark:hover:text-surface-200 transition-colors',
        className,
      )}
      onClick={() => onSort(column)}
    >
      <div className={cn('inline-flex items-center gap-1', className?.includes('text-right') && 'justify-end')}>
        {label}
        {isAsc ? (
          <ArrowUp className="h-3.5 w-3.5 text-primary-500" />
        ) : isDesc ? (
          <ArrowDown className="h-3.5 w-3.5 text-primary-500" />
        ) : (
          <ArrowUpDown className="h-3.5 w-3.5 opacity-30" />
        )}
      </div>
    </th>
  );
}

// ─── SavedFiltersDropdown ───────────────────────────────────────────
function SavedFiltersDropdown({
  currentFilters,
  onApply,
}: {
  currentFilters: Record<string, string | number | undefined>;
  onApply: (filters: Record<string, string>) => void;
}) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [filterName, setFilterName] = useState('');
  const ref = useRef<HTMLDivElement>(null);
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
        setSaving(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  const { data: savedData } = useQuery({
    queryKey: ['ticket-saved-filters'],
    queryFn: () => ticketApi.savedFilters.list(),
    enabled: open,
  });
  const savedFilters: { id: number; name: string; filters: Record<string, string> }[] =
    savedData?.data?.data || [];

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="hidden sm:inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-surface-50 px-2.5 py-1.5 text-xs font-medium text-surface-600 transition-colors hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700"
        title="Saved filter presets"
      >
        <Bookmark className="h-3.5 w-3.5" /> Filters
      </button>
      {open && (
        <div className="absolute right-0 top-full z-50 mt-1 w-64 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
          <div className="p-2 text-xs font-medium text-surface-500 uppercase tracking-wider border-b border-surface-100 dark:border-surface-700">
            Saved Filters
          </div>
          <div className="max-h-48 overflow-y-auto">
            {savedFilters.length === 0 && (
              <p className="px-3 py-2 text-xs text-surface-400 italic">No saved filters</p>
            )}
            {savedFilters.map((sf) => (
              <div key={sf.id} className="flex items-center justify-between px-3 py-2 hover:bg-surface-50 dark:hover:bg-surface-700">
                <button
                  onClick={() => { onApply(sf.filters); setOpen(false); }}
                  className="text-sm text-surface-700 dark:text-surface-200 hover:text-primary-600 dark:hover:text-primary-400 truncate flex-1 text-left"
                >
                  {sf.name}
                </button>
                <button
                  onClick={async () => {
                    await ticketApi.savedFilters.delete(sf.id);
                    queryClient.invalidateQueries({ queryKey: ['ticket-saved-filters'] });
                    toast.success('Filter deleted');
                  }}
                  className="ml-2 text-surface-400 hover:text-red-500 shrink-0"
                  title="Delete filter"
                >
                  <BookmarkX className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}
          </div>
          <div className="border-t border-surface-100 dark:border-surface-700 p-2">
            {saving ? (
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  if (!filterName.trim()) return;
                  await ticketApi.savedFilters.create({ name: filterName.trim(), filters: currentFilters });
                  queryClient.invalidateQueries({ queryKey: ['ticket-saved-filters'] });
                  toast.success('Filter saved');
                  setFilterName('');
                  setSaving(false);
                }}
                className="flex gap-1.5"
              >
                <input
                  autoFocus
                  value={filterName}
                  onChange={(e) => setFilterName(e.target.value)}
                  placeholder="Filter name..."
                  className="flex-1 rounded border border-surface-200 px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
                />
                <button type="submit" className="rounded bg-primary-600 px-2 py-1 text-xs font-medium text-white hover:bg-primary-700">
                  Save
                </button>
              </form>
            ) : (
              <button
                onClick={() => setSaving(true)}
                className="w-full text-left px-1 py-1 text-xs font-medium text-primary-600 hover:text-primary-700 dark:text-primary-400"
              >
                + Save current filters
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Skeleton rows ──────────────────────────────────────────────────
// ─── TicketRow (memoized to avoid re-rendering unchanged rows) ────
interface TicketRowProps {
  ticket: Ticket;
  statuses: TicketStatus[];
  visibleColumns: Set<OptionalColumn>;
  isSelected: boolean;
  isExpanded: boolean;
  onNavigate: (path: string) => void;
  onToggleSelect: (id: number) => void;
  onToggleExpand: (id: number | null) => void;
  onChangeStatus: (ticketId: number, statusId: number) => void;
  onPin: (id: number) => void;
  onPrint: (val: { id: number; invoiceId?: number | null }) => void;
  onDelete: (val: { open: boolean; ticketId: number; ticketLabel: string }) => void;
  onAddNote: (ticketId: number, content: string) => Promise<void>;
  onSendSms: (to: string, message: string, ticketId: number) => Promise<void>;
}

const TicketRow = memo(function TicketRow({
  ticket,
  statuses,
  visibleColumns,
  isSelected,
  isExpanded,
  onNavigate,
  onToggleSelect,
  onToggleExpand,
  onChangeStatus,
  onPin,
  onPrint,
  onDelete,
  onAddNote,
  onSendSms,
}: TicketRowProps) {
  const customer = ticket.customer;
  const firstDevice = (ticket as any).first_device;
  const deviceCount = (ticket as any).device_count || 0;
  const devices = ticket.devices || [];
  const deviceName = firstDevice?.device_name || (devices[0]?.device_name) || '--';
  const issue = firstDevice?.service_name || (devices[0] as any)?.service_name || firstDevice?.additional_notes || (devices[0] as any)?.additional_notes || '';
  const assigned = ticket.assigned_user;

  return (<Fragment>
    <tr
      onClick={() => onNavigate(`/tickets/${ticket.id}`)}
      className={cn(
        'cursor-pointer transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/50',
        isSelected && 'bg-primary-50/50 dark:bg-primary-950/20',
        isExpanded && 'bg-surface-50/60 dark:bg-surface-800/30',
        (() => {
          if (ticket.status?.is_closed || ticket.status?.is_cancelled) return '';
          const ua = ticket.updated_at;
          const days = (Date.now() - new Date(ua.endsWith('Z') ? ua : ua + 'Z').getTime()) / 86400000;
          if (days > 7) return 'border-l-4 border-l-red-400 dark:border-l-red-500';
          if (days > 3) return 'border-l-4 border-l-amber-400 dark:border-l-amber-500';
          return '';
        })(),
      )}
    >
      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
        <input
          type="checkbox"
          checked={isSelected}
          onChange={() => onToggleSelect(ticket.id)}
          className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
        />
      </td>
      <td className="px-4 py-3 whitespace-nowrap">
        <div className="flex items-center gap-1">
          <button
            onClick={(e) => { e.stopPropagation(); onToggleExpand(isExpanded ? null : ticket.id); }}
            className="flex items-center justify-center h-8 w-8 rounded text-surface-400 hover:text-surface-600 hover:bg-surface-100 dark:text-surface-500 dark:hover:text-surface-300 dark:hover:bg-surface-700 transition-all"
            title={isExpanded ? 'Collapse' : 'Expand preview'}
          >
            <ChevronRight className={cn('h-5 w-5 transition-transform', isExpanded && 'rotate-90')} />
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); onPin(ticket.id); }}
            className={cn(
              'rounded p-0.5 transition-colors',
              (ticket as any).is_pinned
                ? 'text-amber-500 hover:text-amber-600'
                : 'text-surface-400 hover:text-surface-600 dark:text-surface-500 dark:hover:text-surface-300',
            )}
            title={(ticket as any).is_pinned ? 'Unpin ticket' : 'Pin ticket'}
          >
            <Pin className="h-3.5 w-3.5" style={(ticket as any).is_pinned ? { fill: 'currentColor' } : undefined} />
          </button>
          <span className="font-medium text-primary-600 dark:text-primary-400">
            {formatTicketId(ticket.order_id || ticket.id)}
          </span>
          <CopyButton text={formatTicketId(ticket.order_id || ticket.id)} />
        </div>
      </td>
      <td className="px-2 py-3 text-center">
        <UrgencyDot urgency={(ticket as any).urgency} showLabel />
      </td>
      {visibleColumns.has('internal_note') && (
        <td className="px-4 py-3 max-w-[180px]">
          <span className="text-xs text-surface-500 dark:text-surface-400 truncate block" title={(ticket as any).latest_internal_note || ''}>
            {(ticket as any).latest_internal_note || <span className="text-surface-300 dark:text-surface-600 italic">—</span>}
          </span>
        </td>
      )}
      {visibleColumns.has('diagnostic_note') && (
        <td className="px-4 py-3 max-w-[180px]">
          <span className="text-xs text-amber-600 dark:text-amber-400 truncate block" title={(ticket as any).latest_diagnostic_note || ''}>
            {(ticket as any).latest_diagnostic_note || <span className="text-surface-300 dark:text-surface-600 italic">—</span>}
          </span>
        </td>
      )}
      <td className="px-4 py-3 text-surface-600 dark:text-surface-400 max-w-[180px]">
        <span className="truncate block" title={deviceName}>
          {deviceName}
          {deviceCount > 1 && (
            <span className="ml-1 text-xs text-surface-400">+{deviceCount - 1}</span>
          )}
        </span>
      </td>
      <td className="px-4 py-3">
        {customer ? (
          <div>
            <CustomerPreviewPopover customerId={customer.id}>
              <Link
                to={`/customers/${customer.id}`}
                onClick={(e) => e.stopPropagation()}
                className="text-surface-800 dark:text-surface-200 hover:text-primary-600 dark:hover:text-primary-400 hover:underline"
              >
                {customer.first_name} {customer.last_name}
              </Link>
            </CustomerPreviewPopover>
            {(customer.phone || customer.mobile) && (
              <a
                href={`tel:${customer.mobile || customer.phone}`}
                onClick={(e) => e.stopPropagation()}
                className="block text-xs text-surface-400 hover:text-primary-500 transition-colors"
              >
                {customer.mobile || customer.phone}
              </a>
            )}
          </div>
        ) : (
          <span className="text-surface-400">--</span>
        )}
      </td>
      <td className="px-4 py-3 text-surface-500 dark:text-surface-400 max-w-[200px]">
        {issue ? (
          <span className="truncate block text-xs" title={issue}>
            {issue.length > 60 ? issue.slice(0, 60) + '...' : issue}
          </span>
        ) : (
          <span className="text-surface-300 dark:text-surface-600">--</span>
        )}
      </td>
      {visibleColumns.has('ticket_items') && (
        <td className="px-4 py-3 text-surface-600 dark:text-surface-400 text-xs max-w-[180px]">
          {devices.length > 0 ? (
            <span title={devices.flatMap((d: any) => (d.parts || []).map((p: any) => p.name)).join(', ')}>
              {(() => {
                const allParts = devices.flatMap((d: any) => d.parts || []);
                if (allParts.length === 0) return <span className="text-surface-400">No parts</span>;
                return (
                  <span className="truncate block">
                    {allParts.length} part{allParts.length !== 1 ? 's' : ''}
                    {allParts[0]?.name ? `: ${allParts[0].name}` : ''}
                    {allParts.length > 1 ? '...' : ''}
                  </span>
                );
              })()}
            </span>
          ) : '--'}
        </td>
      )}
      <td className="px-4 py-3 text-surface-500 dark:text-surface-400 whitespace-nowrap">
        <span title={`Created: ${formatDate(ticket.created_at)}\nUpdated: ${formatDate(ticket.updated_at)}`}>{timeAgo(ticket.created_at)}</span>
      </td>
      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
        <StatusDropdown
          ticket={ticket}
          statuses={statuses}
          onChangeStatus={onChangeStatus}
        />
      </td>
      <td className="px-4 py-3 whitespace-nowrap text-xs">
        {(() => {
          const dueOn = (ticket as any).due_on;
          if (!dueOn) return <span className="text-surface-300 dark:text-surface-600">--</span>;
          const dueTs = dueOn.endsWith('Z') || dueOn.includes('+') ? dueOn : dueOn + 'Z';
          const dueDate = new Date(dueTs);
          const now = new Date();
          const diffDays = Math.ceil((dueDate.getTime() - now.getTime()) / 86400000);
          let label: string;
          let colorCls: string;
          if (ticket.status?.is_closed || ticket.status?.is_cancelled) {
            label = formatDate(dueOn);
            colorCls = 'text-surface-400';
          } else if (diffDays < 0) {
            label = `Overdue ${Math.abs(diffDays)}d`;
            colorCls = 'text-red-600 dark:text-red-400 font-medium';
          } else if (diffDays === 0) {
            label = 'Due today';
            colorCls = 'text-amber-600 dark:text-amber-400 font-medium';
          } else if (diffDays === 1) {
            label = 'Due tomorrow';
            colorCls = 'text-green-600 dark:text-green-400';
          } else {
            label = `Due in ${diffDays}d`;
            colorCls = 'text-green-600 dark:text-green-400';
          }
          return <span className={colorCls} title={formatDate(dueOn)}>{label}</span>;
        })()}
      </td>
      {visibleColumns.has('assigned_to') && (
        <td className="px-4 py-3 text-surface-600 dark:text-surface-400 whitespace-nowrap">
          {assigned ? `${assigned.first_name} ${assigned.last_name}` : '--'}
        </td>
      )}
      <td className="px-4 py-3 text-right font-medium text-surface-800 dark:text-surface-200 whitespace-nowrap">
        {formatCurrency(ticket.total)}
      </td>
      <td className="px-4 py-3 text-right" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-end gap-1">
          <button
            onClick={() => onNavigate(`/tickets/${ticket.id}`)}
            className="rounded-lg px-2 py-1 text-xs font-medium text-primary-600 hover:bg-primary-50 dark:text-primary-400 dark:hover:bg-primary-950/30 transition-colors"
          >
            View
          </button>
          {customer?.phone && (
            <button
              onClick={() => onNavigate(`/communications?phone=${encodeURIComponent(customer.phone!)}`)}
              className="rounded-lg p-1.5 text-green-500 transition-colors hover:bg-green-50 dark:hover:bg-green-950/30"
              title={`SMS ${customer.first_name} ${customer.last_name}`}
            >
              <MessageSquare className="h-3.5 w-3.5" />
            </button>
          )}
          <div className="relative group">
            <button aria-label="More options" className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-surface-100 dark:hover:bg-surface-700">
              <MoreHorizontal className="h-4 w-4" />
            </button>
            <div className="absolute right-0 top-full z-50 mt-1 hidden w-36 rounded-lg border border-surface-200 bg-white shadow-lg group-hover:block dark:border-surface-700 dark:bg-surface-800">
              <button
                onClick={() => onPrint({ id: ticket.id, invoiceId: ticket.invoice_id })}
                className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-surface-600 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
              >
                <Printer className="h-3.5 w-3.5" /> Print
              </button>
              <button
                onClick={() => onDelete({ open: true, ticketId: ticket.id, ticketLabel: formatTicketId(ticket.order_id) })}
                className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/30"
              >
                <Trash2 className="h-3.5 w-3.5" /> Delete
              </button>
            </div>
          </div>
        </div>
      </td>
    </tr>
    {isExpanded && (
      <tr className="bg-surface-50/80 dark:bg-surface-800/40" onClick={(e) => e.stopPropagation()}>
        <td colSpan={20} className="px-6 py-3">
          <div className="grid grid-cols-[1fr_auto_auto] gap-4 text-sm">
            <div className="min-w-0 space-y-2">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <span className="font-semibold text-surface-900 dark:text-surface-100">{deviceName}</span>
                {firstDevice?.service_name && (
                  <span className="rounded bg-primary-100 px-1.5 py-0.5 text-[11px] font-medium text-primary-700 dark:bg-primary-900/30 dark:text-primary-300">
                    {firstDevice.service_name}
                  </span>
                )}
                {deviceCount > 1 && (
                  <span className="text-xs text-surface-400">+{deviceCount - 1} more device{deviceCount > 2 ? 's' : ''}</span>
                )}
              </div>
              {(firstDevice?.imei || firstDevice?.serial || firstDevice?.security_code) && (
                <div className="flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-surface-500 font-mono">
                  {firstDevice?.imei && <span>IMEI: {firstDevice.imei}</span>}
                  {firstDevice?.serial && <span>S/N: {firstDevice.serial}</span>}
                  {firstDevice?.security_code && <span>Code: {firstDevice.security_code}</span>}
                </div>
              )}
              {issue && (
                <p className="text-xs text-surface-600 dark:text-surface-400" title={issue}>
                  <span className="font-medium text-surface-500 dark:text-surface-500">Issue:</span> {issue.length > 200 ? issue.slice(0, 200) + '...' : issue}
                </p>
              )}
              {(ticket as any).parts_count > 0 && (
                <p className="text-xs text-surface-500">
                  <span className="font-medium">Parts ({(ticket as any).parts_count}):</span>{' '}
                  {((ticket as any).parts_names || []).slice(0, 3).join(', ')}
                  {(ticket as any).parts_count > 3 && ` +${(ticket as any).parts_count - 3} more`}
                </p>
              )}
              <div className="flex flex-wrap gap-x-6 gap-y-1">
                {(ticket as any).latest_internal_note && (
                  <p className="text-xs text-amber-600 dark:text-amber-400 max-w-md truncate" title={(ticket as any).latest_internal_note}>
                    <span className="font-medium">Note:</span> {(ticket as any).latest_internal_note}
                  </p>
                )}
                {(ticket as any).latest_diagnostic_note && (
                  <p className="text-xs text-blue-600 dark:text-blue-400 max-w-md truncate" title={(ticket as any).latest_diagnostic_note}>
                    <span className="font-medium">Diagnostic:</span> {(ticket as any).latest_diagnostic_note}
                  </p>
                )}
              </div>
              {(ticket as any).latest_sms && (
                <p className="text-xs text-surface-500 max-w-lg truncate" title={(ticket as any).latest_sms.message}>
                  <span className="font-medium">{(ticket as any).latest_sms.direction === 'inbound' ? 'Customer SMS:' : 'Our SMS:'}</span>{' '}
                  {(ticket as any).latest_sms.message?.slice(0, 120)}
                </p>
              )}
              <div className="flex flex-wrap gap-3 pt-1">
                <form className="flex gap-1.5" onClick={(e) => e.stopPropagation()} onSubmit={(e) => {
                  e.preventDefault();
                  const input = (e.target as HTMLFormElement).elements.namedItem('quicknote') as HTMLInputElement;
                  if (!input.value.trim()) return;
                  onAddNote(ticket.id, input.value.trim()).then(() => { input.value = ''; });
                }}>
                  <input name="quicknote" type="text" placeholder="Quick note..." className="w-48 rounded-lg border border-surface-200 bg-white px-2.5 py-1.5 text-xs dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400" />
                  {/* WEB-FQ-017 (Fixer-C12 2026-04-25): bare ">Add<" was ambiguous next
                      to the "Add Customer" / "Add Ticket" / "Create" labels elsewhere.
                      Spelled-out object name keeps the same row-CRUD verb but disambiguates
                      from the page-level "Add Ticket" CTA. */}
                  <button type="submit" className="rounded-lg bg-surface-200 px-2.5 py-1.5 text-xs font-medium dark:bg-surface-700 hover:bg-surface-300 dark:hover:bg-surface-600">Add note</button>
                </form>
                {customer?.phone && (
                  <form className="flex gap-1.5" onClick={(e) => e.stopPropagation()} onSubmit={(e) => {
                    e.preventDefault();
                    const input = (e.target as HTMLFormElement).elements.namedItem('quicksms') as HTMLInputElement;
                    if (!input.value.trim()) return;
                    const btn = (e.target as HTMLFormElement).querySelector('button[type=submit]') as HTMLButtonElement;
                    btn.disabled = true;
                    onSendSms(customer.phone || '', input.value.trim(), ticket.id).then(() => {
                      input.value = '';
                    }).finally(() => { btn.disabled = false; });
                  }}>
                    <input name="quicksms" type="text" placeholder="Quick SMS..." className="w-48 rounded-lg border border-green-200 bg-white px-2.5 py-1.5 text-xs dark:border-green-800 dark:bg-surface-800 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-green-500 focus-visible:border-green-500" />
                    <button type="submit" className="rounded-lg bg-green-600 px-2.5 py-1.5 text-xs font-medium text-white hover:bg-green-700 disabled:opacity-50 flex items-center gap-1">
                      <Send className="h-3 w-3" /> Send
                    </button>
                  </form>
                )}
              </div>
            </div>
            <div className="shrink-0 text-right space-y-1 min-w-[140px]">
              {customer?.phone && (
                <a href={`tel:${customer.phone}`} className="text-xs text-primary-600 hover:underline dark:text-primary-400 block font-medium">
                  {customer.phone}
                </a>
              )}
              {customer?.email && <p className="text-xs text-surface-400 truncate max-w-[180px]">{customer.email}</p>}
              {assigned && (
                <p className="text-xs text-surface-500">
                  <span className="text-surface-400">Tech:</span> {assigned.first_name} {assigned.last_name}
                </p>
              )}
              <p className="text-xs text-surface-400">
                Created: {formatDate(ticket.created_at)}
              </p>
            </div>
            <div className="shrink-0 flex flex-col gap-2 items-end">
              <button
                onClick={() => onNavigate(`/tickets/${ticket.id}`)}
                className="rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 transition-colors"
              >
                Open Full
              </button>
              <button
                onClick={() => onPrint({ id: ticket.id, invoiceId: ticket.invoice_id })}
                className="rounded-lg border border-surface-200 px-3 py-1.5 text-xs font-medium text-surface-600 hover:bg-surface-100 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700 transition-colors"
              >
                Print
              </button>
            </div>
          </div>
        </td>
      </tr>
    )}
  </Fragment>);
});

const SkeletonRow = memo(function SkeletonRow() {
  return (
    <tr className="animate-pulse">
      <td className="px-4 py-3"><div className="h-4 w-4 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-16 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-28 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-24 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-20 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-5 w-20 rounded-full bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-20 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-14 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-16 rounded bg-surface-200 dark:bg-surface-700" /></td>
    </tr>
  );
});

// ─── Main Component ─────────────────────────────────────────────────
export function TicketListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const { getSetting } = useSettings();

  // F21: ticket_default_* settings used as fallbacks when URL params not set
  const page = Number(searchParams.get('page') || '1');
  const pageSize = Number(searchParams.get('pagesize') || localStorage.getItem('tickets_pagesize') || getSetting('ticket_default_pagination', '25') || '25');
  const keyword = searchParams.get('keyword') || '';
  const statusFilter = searchParams.get('status_id') || getSetting('ticket_default_filter', '');
  const statusGroupFilter = searchParams.get('status_group') || '';
  const assignedTo = searchParams.get('assigned_to') || '';
  const dateFilter = searchParams.get('date_filter') || '';
  const sortBy = (searchParams.get('sort_by') || getSetting('ticket_default_sort', 'urgency')) as SortColumn;
  const sortOrder = searchParams.get('sort_order') || getSetting('ticket_default_sort_order', 'DESC');

  // CROSS1: ticket assignment feature toggle. When ticket_all_employees_view_all is '1'
  // (default), assignment feature is OFF — hide "Assigned To" filter dropdown + column.
  // When '0', techs only see their own; admins/managers see all.
  const assignmentEnabled = getSetting('ticket_all_employees_view_all', '1') === '0';

  // Column visibility (optional columns)
  const [visibleColumns, setVisibleColumns] = useState<Set<OptionalColumn>>(() => {
    try {
      const saved = localStorage.getItem('ticket-list-columns');
      if (saved) return new Set(JSON.parse(saved));
    } catch {
      // Invalid saved columns — use defaults
    }
    return new Set<OptionalColumn>();
  });
  // CROSS1: when assignment feature is off, strip assigned_to from the set used for rendering
  // (user's saved preference remains intact; feature only suppresses display).
  const effectiveVisibleColumns = useMemo(() => {
    if (assignmentEnabled || !visibleColumns.has('assigned_to')) return visibleColumns;
    const next = new Set(visibleColumns);
    next.delete('assigned_to');
    return next;
  }, [assignmentEnabled, visibleColumns]);
  const [columnMenuOpen, setColumnMenuOpen] = useState(false);
  const columnMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!columnMenuOpen) return;
    function handleClick(e: MouseEvent) {
      if (columnMenuRef.current && !columnMenuRef.current.contains(e.target as Node)) setColumnMenuOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [columnMenuOpen]);

  function toggleColumn(col: OptionalColumn) {
    setVisibleColumns((prev) => {
      const next = new Set(prev);
      if (next.has(col)) next.delete(col); else next.add(col);
      localStorage.setItem('ticket-list-columns', JSON.stringify(Array.from(next)));
      return next;
    });
  }

  // Local search input with debounce
  const [searchInput, setSearchInput] = useState(keyword);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const prevKeywordRef = useRef(keyword);

  useEffect(() => {
    // Skip if search hasn't actually changed (prevents page reset on mount)
    if (searchInput === prevKeywordRef.current) return;
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      prevKeywordRef.current = searchInput;
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        if (searchInput) next.set('keyword', searchInput); else next.delete('keyword');
        next.set('page', '1');
        return next;
      });
    }, 400);
    return () => clearTimeout(debounceRef.current);
  }, [searchInput, setSearchParams]);

  // View mode (list vs calendar)
  const [viewMode, setViewMode] = useState<'list' | 'calendar' | 'kanban'>(() => {
    const saved = localStorage.getItem('ticket-view-mode');
    if (saved === 'list' || saved === 'calendar' || saved === 'kanban') return saved;
    const setting = getSetting('ticket_default_view', 'list');
    return setting === 'calendar' || setting === 'kanban' ? setting : 'list';
  });
  const [calendarMonth, setCalendarMonth] = useState(() => {
    const d = new Date();
    return { year: d.getFullYear(), month: d.getMonth() };
  });

  function toggleViewMode(mode: 'list' | 'calendar' | 'kanban') {
    setViewMode(mode);
    localStorage.setItem('ticket-view-mode', mode);
  }

  // Checkbox state
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [confirmDlg, setConfirmDlg] = useState<{ open: boolean; ticketId?: number; ticketLabel?: string; bulk?: boolean }>({ open: false });
  const [printTicket, setPrintTicket] = useState<{ id: number; invoiceId?: number | null } | null>(null);

  // ─── Fetch statuses ───────────────────────────────────────────────
  const { data: statusData } = useQuery({
    queryKey: ['ticket-statuses'],
    queryFn: () => settingsApi.getStatuses(),
    staleTime: 30_000, // refresh every 30s to pick up new statuses
  });
  // Server: res.json({ success: true, data: statuses }) — array directly.
  const statuses: TicketStatus[] = statusData?.data?.data || [];

  // ─── Fetch users (for Assigned To filter) ─────────────────────────
  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => settingsApi.getUsers(),
  });
  const users: { id: number; first_name: string; last_name: string }[] =
    usersData?.data?.data?.users || usersData?.data?.data || [];

  // ─── Fetch tickets ────────────────────────────────────────────────
  const ticketParams = {
    page,
    pagesize: pageSize,
    ...(keyword ? { keyword } : {}),
    ...(statusFilter ? (/^\d+$/.test(statusFilter) ? { status_id: Number(statusFilter) } : { status_id: statusFilter }) : {}),
    ...(statusGroupFilter ? { status_group: statusGroupFilter } : {}),
    ...(assignedTo ? { assigned_to: assignedTo === 'me' ? 'me' as const : Number(assignedTo) } : {}),
    ...(dateFilter ? { date_filter: dateFilter } : {}),
    sort_by: sortBy,
    sort_order: sortOrder,
  };

  const { data: ticketData, isLoading, isFetching } = useQuery({
    queryKey: ['tickets', ticketParams],
    queryFn: () => ticketApi.list(ticketParams),
    placeholderData: (prev) => prev,
  });

  // D4-3: only show the skeleton if loading persists past 150ms. Local SQLite
  // responses often resolve in <80ms; flashing the skeleton makes the whole
  // table jitter as it paints over. Defer the visual loading state.
  const [showSkeleton, setShowSkeleton] = useState(false);
  useEffect(() => {
    if (!isLoading) {
      setShowSkeleton(false);
      return;
    }
    const timer = setTimeout(() => setShowSkeleton(true), 150);
    return () => clearTimeout(timer);
  }, [isLoading]);

  const rawTickets: Ticket[] = ticketData?.data?.data?.tickets || ticketData?.data?.tickets || [];
  const pagination = ticketData?.data?.data?.pagination || ticketData?.data?.pagination || { page: 1, total: 0, total_pages: 1, per_page: 25 };

  // F19: ticket_show_closed — hide closed tickets when '0'
  // F20: ticket_show_empty — hide tickets with no devices when '0'
  const showClosed = getSetting('ticket_show_closed', '1') !== '0';
  const showEmpty = getSetting('ticket_show_empty', '1') !== '0';

  const tickets = useMemo(() => {
    let filtered = rawTickets;
    if (!showClosed) {
      const closedStatuses = statuses.filter(s => s.is_closed).map(s => s.id);
      filtered = filtered.filter(t => !closedStatuses.includes(t.status_id));
    }
    if (!showEmpty) {
      filtered = filtered.filter(t => (t.devices?.length ?? 0) > 0);
    }
    return filtered;
  }, [rawTickets, showClosed, showEmpty, statuses]);
  const statusCounts: { status_id?: number; id?: number; name?: string; status_name?: string; color: string; count: number }[] =
    ticketData?.data?.data?.status_counts || ticketData?.data?.status_counts || [];

  // Compute total created count
  const totalCreated = statusCounts.reduce((sum, sc) => sum + (sc.count || 0), 0);

  // ─── Mutations ────────────────────────────────────────────────────
  const changeStatusMut = useMutation({
    mutationFn: ({ ticketId, statusId }: { ticketId: number; statusId: number }) =>
      ticketApi.changeStatus(ticketId, statusId),
    onMutate: async ({ ticketId, statusId }) => {
      await queryClient.cancelQueries({ queryKey: ['tickets'] });
      const prev = queryClient.getQueryData(['tickets', ticketParams]);
      queryClient.setQueryData(['tickets', ticketParams], (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.tickets || clone?.data?.tickets || [];
        const t = list.find((t: any) => t.id === ticketId);
        if (t) {
          t.status_id = statusId;
          const s = statuses.find((s) => s.id === statusId);
          if (s) t.status = s;
        }
        return clone;
      });
      return { prev };
    },
    onError: (_err, _vars, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(['tickets', ticketParams], ctx.prev);
      toast.error('Failed to change status');
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
    onSuccess: (_data, { ticketId: tId, statusId: newStatusId }) => {
      const prevTicket = rawTickets.find((t: any) => t.id === tId);
      const prevStatusId = prevTicket?.status_id;
      const newName = statuses.find((s) => s.id === newStatusId)?.name ?? 'Unknown';
      toast((t) => (
        <span className="flex items-center gap-2 text-sm">
          Status changed to <b>{newName}</b>
          {prevStatusId != null && prevStatusId !== newStatusId && (
            <button
              className="ml-2 rounded bg-surface-200 px-3 py-2 min-h-[44px] md:min-h-0 md:px-2 md:py-0.5 text-xs font-medium hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
              onClick={() => { toast.dismiss(t.id); changeStatusMut.mutate({ ticketId: tId, statusId: prevStatusId }); }}
            >
              Undo
            </button>
          )}
        </span>
      ), { duration: 5000 });
    },
  });

  // Ticket delete wrapped in a 5s undo window (D4-5). We optimistically hide
  // the row from the cached list, then fire the real delete after 5s. If the
  // user clicks Undo we invalidate to restore the row.
  const deleteUndo = useUndoableAction<{ id: number; label: string }>(
    async ({ id }) => {
      await ticketApi.delete(id);
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
    {
      timeoutMs: 5000,
      pendingMessage: ({ label }) => `Deleting ticket ${label}…`,
      successMessage: 'Ticket deleted',
      errorMessage: 'Failed to delete ticket',
      onUndo: () => {
        queryClient.invalidateQueries({ queryKey: ['tickets'] });
      },
    },
  );

  const scheduleTicketDelete = useCallback(
    (id: number, label: string) => {
      // Optimistic hide: drop the row from every cached tickets list page.
      queryClient.setQueriesData({ queryKey: ['tickets'] }, (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.tickets || clone?.data?.tickets;
        if (Array.isArray(list)) {
          const filtered = list.filter((t: any) => t.id !== id);
          if (clone?.data?.data?.tickets) clone.data.data.tickets = filtered;
          else if (clone?.data?.tickets) clone.data.tickets = filtered;
        }
        return clone;
      });
      deleteUndo.trigger({ id, label });
    },
    [queryClient, deleteUndo],
  );

  // Private comment mutation removed — notes come from the Notes module now
  const _unusedMut = useMutation({
    mutationFn: ({ id, note }: { id: number; note: string }) =>
      ticketApi.addNote(id, { type: 'internal', content: note }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
    onError: () => toast.error('Failed to save note'),
  });

  // Notes are now read-only in the list — edit in ticket detail page

  const bulkMut = useMutation({
    mutationFn: ({ action, value }: { action: string; value?: number }) =>
      ticketApi.bulkAction(Array.from(selected), action, value),
    onSuccess: () => {
      toast.success('Bulk action completed');
      setSelected(new Set());
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
    onError: () => toast.error('Bulk action failed'),
  });

  // ─── Calendar data ────────────────────────────────────────────────
  const calStartDate = new Date(calendarMonth.year, calendarMonth.month, 1).toISOString().slice(0, 10);
  const calEndDate = new Date(calendarMonth.year, calendarMonth.month + 1, 0).toISOString().slice(0, 10);

  const { data: calendarData } = useQuery({
    queryKey: ['tickets-calendar', calStartDate, calEndDate],
    queryFn: () => ticketApi.list({ pagesize: 500, from_date: calStartDate, to_date: calEndDate, sort_by: 'created_at', sort_order: 'ASC' }),
    enabled: viewMode === 'calendar',
  });
  const calendarTickets: Ticket[] = calendarData?.data?.data?.tickets || calendarData?.data?.tickets || [];

  const pinMut = useMutation({
    mutationFn: (id: number) => ticketApi.togglePin(id),
    onMutate: async (id) => {
      await queryClient.cancelQueries({ queryKey: ['tickets'] });
      const prev = queryClient.getQueryData(['tickets', ticketParams]);
      queryClient.setQueryData(['tickets', ticketParams], (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.tickets || clone?.data?.tickets || [];
        const t = list.find((t: any) => t.id === id);
        if (t) t.is_pinned = !t.is_pinned;
        return clone;
      });
      return { prev };
    },
    onError: (_err, _vars, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(['tickets', ticketParams], ctx.prev);
      toast.error('Failed to toggle pin');
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
  });

  // ─── Handlers ─────────────────────────────────────────────────────
  const handleChangeStatus = useCallback(
    (ticketId: number, statusId: number) => changeStatusMut.mutate({ ticketId, statusId }),
    [changeStatusMut],
  );

  // TicketRow callback handlers (stable references for memo)
  const handlePin = useCallback((id: number) => pinMut.mutate(id), [pinMut]);
  const handleAddNote = useCallback(async (ticketId: number, content: string) => {
    try {
      await ticketApi.addNote(ticketId, { type: 'internal', content });
      toast.success('Note added');
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } }; message?: string };
      toast.error(e?.response?.data?.message || e?.message || 'Failed to add note');
    }
  }, [queryClient]);
  const handleSendSms = useCallback(async (to: string, message: string, ticketId: number) => {
    try {
      await smsApi.send({ to, message, entity_type: 'ticket', entity_id: ticketId });
      toast.success('SMS sent');
    } catch { toast.error('Failed to send SMS'); }
  }, []);

  function setParam(key: string, value: string) {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      if (value) next.set(key, value); else next.delete(key);
      if (key === 'status_id') next.delete('status_group');
      if (key === 'status_group') next.delete('status_id');
      if (key !== 'page') next.set('page', '1'); // Reset page only when changing filters, not page itself
      return next;
    });
  }

  function handleSort(column: SortColumn) {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      if (sortBy === column) {
        // Toggle direction
        next.set('sort_order', sortOrder === 'DESC' ? 'ASC' : 'DESC');
      } else {
        next.set('sort_by', column);
        next.set('sort_order', 'DESC');
      }
      next.set('page', '1');
      return next;
    });
  }

  function toggleSelect(id: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  function toggleSelectAll() {
    if (selected.size === tickets.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(tickets.map((t) => t.id)));
    }
  }

  // Bulk status change state
  const [bulkStatusOpen, setBulkStatusOpen] = useState(false);
  const bulkStatusRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!bulkStatusOpen) return;
    function handleClick(e: MouseEvent) {
      if (bulkStatusRef.current && !bulkStatusRef.current.contains(e.target as Node)) setBulkStatusOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [bulkStatusOpen]);

  // ─── Render ───────────────────────────────────────────────────────
  return (
    <div className="flex flex-col h-full">
      {/* Page header */}
      <div className="mb-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 shrink-0">
        <div>
          <h1 className="text-xl md:text-2xl font-bold text-surface-900 dark:text-surface-100">Tickets</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">Manage repair tickets and work orders</p>
        </div>
        <div className="flex items-center gap-2">
          {/* View mode toggle */}
          <div className="inline-flex rounded-lg border border-surface-200 dark:border-surface-700">
            <button
              onClick={() => toggleViewMode('list')}
              className={cn(
                'inline-flex items-center gap-1 rounded-l-lg px-3 py-2 text-sm font-medium transition-colors',
                viewMode === 'list'
                  ? 'bg-primary-50 text-primary-700 dark:bg-primary-950/30 dark:text-primary-300'
                  : 'text-surface-500 hover:bg-surface-50 dark:hover:bg-surface-800',
              )}
              title="List View"
            >
              <List className="h-4 w-4" />
            </button>
            <button
              onClick={() => toggleViewMode('kanban')}
              className={cn(
                'inline-flex items-center gap-1 border-x border-surface-200 px-3 py-2 text-sm font-medium transition-colors dark:border-surface-700',
                viewMode === 'kanban'
                  ? 'bg-primary-50 text-primary-700 dark:bg-primary-950/30 dark:text-primary-300'
                  : 'text-surface-500 hover:bg-surface-50 dark:hover:bg-surface-800',
              )}
              title="Kanban Board"
            >
              <Kanban className="h-4 w-4" />
            </button>
            <button
              onClick={() => toggleViewMode('calendar')}
              className={cn(
                'inline-flex items-center gap-1 rounded-r-lg px-3 py-2 text-sm font-medium transition-colors',
                viewMode === 'calendar'
                  ? 'bg-primary-50 text-primary-700 dark:bg-primary-950/30 dark:text-primary-300'
                  : 'text-surface-500 hover:bg-surface-50 dark:hover:bg-surface-800',
              )}
              title="Calendar View"
            >
              <CalendarDays className="h-4 w-4" />
            </button>
          </div>
          <Link
            to="/tickets/new"
            className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700"
          >
            <Plus className="h-4 w-4" />
            New Ticket
          </Link>
        </div>
      </div>

      {/* Overview bar — grouped status counts + progress bar (like RepairDesk) */}
      {(() => {
        // Identify "on hold" statuses by name pattern
        const holdKeywords = ['hold', 'waiting', 'pending', 'transit'];
        const isOnHold = (name: string) => holdKeywords.some(k => name.toLowerCase().includes(k));

        // Group statuses: open (blue), on hold (orange), closed (green), cancelled (red)
        let openCount = 0;
        let onHoldCount = 0;
        let closedCount = 0;
        let cancelledCount = 0;

        for (const sc of statusCounts) {
          const s = statuses.find(st => st.id === (sc.status_id || sc.id));
          if (!s) continue;
          const count = sc.count || 0;
          if (s.is_cancelled) cancelledCount += count;
          else if (s.is_closed) closedCount += count;
          else if (isOnHold(s.name)) onHoldCount += count;
          else openCount += count;
        }

        const groups = [
          { label: 'Total Created', count: totalCreated, color: '#9ca3af', dotColor: '#9ca3af', filter: '' },
          { label: 'Open', count: openCount, color: '#60a5fa', dotColor: '#60a5fa', filter: 'open' },
          { label: 'On Hold', count: onHoldCount, color: '#fb923c', dotColor: '#fb923c', filter: 'on_hold' },
          { label: 'Closed', count: closedCount, color: '#4ade80', dotColor: '#4ade80', filter: 'closed' },
          { label: 'Cancelled', count: cancelledCount, color: '#f87171', dotColor: '#f87171', filter: 'cancelled' },
        ];

        // Progress bar segments — exclude cancelled
        const barTotal = (openCount + onHoldCount + closedCount) || 1;

        return (
          <div className="mb-3 card px-3 md:px-4 py-3 shrink-0">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-2">
              <span className="text-sm font-medium text-surface-700 dark:text-surface-300">Tickets</span>
              <div className="flex items-center gap-2 md:gap-4 flex-wrap">
                {groups.map((g) => (
                  <button
                    key={g.label}
                    onClick={() => setParam('status_id', statusFilter === g.filter ? '' : g.filter)}
                    className={cn(
                      'inline-flex items-center gap-1.5 text-xs font-medium cursor-pointer rounded-lg px-2.5 py-1.5 transition-all',
                      statusFilter === g.filter
                        ? 'ring-2 ring-offset-1 ring-offset-white dark:ring-offset-surface-900 shadow-sm'
                        : 'hover:bg-surface-50 dark:hover:bg-surface-800',
                    )}
                    style={{
                      backgroundColor: statusFilter === g.filter ? `${g.color}20` : undefined,
                      ...(statusFilter === g.filter ? { ringColor: g.color } : {}),
                    }}
                  >
                    <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: g.dotColor }} />
                    <span className="text-surface-700 dark:text-surface-300">{g.label}</span>
                    <span className="font-bold text-sm" style={{ color: g.color }}>{g.count}</span>
                  </button>
                ))}
              </div>
            </div>
            {/* Colored progress bar (brighter shades) */}
            <div className="flex h-2.5 w-full rounded-full overflow-hidden bg-surface-100 dark:bg-surface-800">
              {openCount > 0 && (
                <div style={{ width: `${(openCount / barTotal) * 100}%`, backgroundColor: '#60a5fa' }} title={`Open: ${openCount}`} />
              )}
              {onHoldCount > 0 && (
                <div style={{ width: `${(onHoldCount / barTotal) * 100}%`, backgroundColor: '#fb923c' }} title={`On hold: ${onHoldCount}`} />
              )}
              {closedCount > 0 && (
                <div style={{ width: `${(closedCount / barTotal) * 100}%`, backgroundColor: '#4ade80' }} title={`Closed: ${closedCount}`} />
              )}
            </div>
            {/* Legend + cancelled footnote */}
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-2">
              {[
                { label: 'Open', color: '#60a5fa' },
                { label: 'On Hold', color: '#fb923c' },
                { label: 'Closed', color: '#4ade80' },
              ].map((item) => (
                <span key={item.label} className="inline-flex items-center gap-1.5 text-xs text-surface-500 dark:text-surface-400">
                  <span className="h-2 w-2 rounded-full" style={{ backgroundColor: item.color }} />
                  {item.label}
                </span>
              ))}
              {cancelledCount > 0 && (
                <span className="text-xs text-surface-400 dark:text-surface-500 ml-auto">{cancelledCount} cancelled</span>
              )}
            </div>
          </div>
        );
      })()}

      {/* Calendar View */}
      {viewMode === 'calendar' && (() => {
        const year = calendarMonth.year;
        const month = calendarMonth.month;
        const firstDay = new Date(year, month, 1).getDay();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        // @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): hardcoded `'en-US'`
        // locale on calendar header → respect browser locale via `undefined`.
        // Could route through `formatDate` but month-only + year format isn't
        // covered by the canonical helpers and adding one for a single site
        // would be over-engineering; `undefined` matches the format.ts
        // `_locale` semantics for the common case.
        const monthName = new Date(year, month).toLocaleString(undefined, { month: 'long', year: 'numeric' });
        const today = new Date();
        const isToday = (d: number) => today.getFullYear() === year && today.getMonth() === month && today.getDate() === d;

        // Group tickets by day
        const ticketsByDay: Record<number, Ticket[]> = {};
        for (const t of calendarTickets) {
          const d = new Date(t.created_at).getDate();
          if (!ticketsByDay[d]) ticketsByDay[d] = [];
          ticketsByDay[d].push(t);
        }

        const cells = [];
        for (let i = 0; i < firstDay; i++) cells.push(null);
        for (let d = 1; d <= daysInMonth; d++) cells.push(d);

        return (
          <div className="card mb-4">
            <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
              <button aria-label="Previous month" onClick={() => setCalendarMonth((p) => {
                const d = new Date(p.year, p.month - 1);
                return { year: d.getFullYear(), month: d.getMonth() };
              })} className="rounded-lg p-1.5 hover:bg-surface-100 dark:hover:bg-surface-700">
                <ChevronLeft className="h-5 w-5 text-surface-600 dark:text-surface-400" />
              </button>
              <h2 className="text-lg font-semibold text-surface-800 dark:text-surface-200">{monthName}</h2>
              <button aria-label="Next month" onClick={() => setCalendarMonth((p) => {
                const d = new Date(p.year, p.month + 1);
                return { year: d.getFullYear(), month: d.getMonth() };
              })} className="rounded-lg p-1.5 hover:bg-surface-100 dark:hover:bg-surface-700">
                <ChevronRight className="h-5 w-5 text-surface-600 dark:text-surface-400" />
              </button>
            </div>
            <div className="grid grid-cols-7">
              {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d) => (
                <div key={d} className="border-b border-surface-200 px-2 py-2 text-center text-xs font-medium text-surface-500 dark:border-surface-700 dark:text-surface-400">
                  {d}
                </div>
              ))}
              {cells.map((day, i) => (
                <div
                  key={i}
                  className={cn(
                    'min-h-[100px] border-b border-r border-surface-100 p-1.5 dark:border-surface-800',
                    day && isToday(day) && 'bg-primary-50/50 dark:bg-primary-950/20',
                    !day && 'bg-surface-50/50 dark:bg-surface-900/30',
                  )}
                >
                  {day && (
                    <>
                      <div className={cn(
                        'mb-1 text-xs font-medium',
                        isToday(day) ? 'text-primary-600 dark:text-primary-400' : 'text-surface-500 dark:text-surface-400',
                      )}>
                        {day}
                      </div>
                      <div className="space-y-0.5">
                        {(ticketsByDay[day] || []).slice(0, 3).map((t) => (
                          <button
                            key={t.id}
                            onClick={() => navigate(`/tickets/${t.id}`)}
                            className="relative w-full truncate rounded px-1 py-0.5 text-left text-[10px] font-medium text-white transition-opacity hover:opacity-80 before:absolute before:inset-x-0 before:-inset-y-1 before:content-[''] md:before:hidden"
                            style={{ backgroundColor: safeColor(t.status?.color) }}
                            title={`${formatTicketId(t.order_id || t.id)} - ${t.customer?.first_name || ''} ${t.customer?.last_name || ''} - ${(t as any).device_name || ''}`}
                          >
                            {formatTicketId(t.order_id || t.id)} {(t as any).device_name ? `· ${(t as any).device_name}` : ''}
                          </button>
                        ))}
                        {(ticketsByDay[day] || []).length > 3 && (
                          <div className="text-[10px] text-surface-400">+{(ticketsByDay[day] || []).length - 3} more</div>
                        )}
                      </div>
                    </>
                  )}
                </div>
              ))}
            </div>
          </div>
        );
      })()}

      {/* Kanban View */}
      {viewMode === 'kanban' && <KanbanBoard />}

      {viewMode === 'list' && <div className="card relative flex-1 flex flex-col min-h-0 overflow-hidden">
        {/* Date tabs + search + filters */}
        <div className="flex flex-col gap-3 border-b border-surface-200 px-4 dark:border-surface-700 sm:flex-row sm:items-center sm:justify-between">
          {/* Date tabs */}
          <div className="flex gap-1 overflow-x-auto">
            {DATE_TABS.map((tab) => (
              <button
                key={tab.value}
                onClick={() => setParam('date_filter', dateFilter === tab.value ? '' : tab.value)}
                className={cn(
                  'whitespace-nowrap px-4 py-3 text-xs font-semibold tracking-wide border-b-2 transition-colors',
                  dateFilter === tab.value
                    ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                    : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300',
                )}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Search + Filters */}
          <div className="flex flex-wrap items-center gap-2 pb-3 sm:pb-0">
            <div className="relative flex-1 min-w-[150px] max-w-xs">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
              <input
                type="text"
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                placeholder="Search tickets..."
                className="w-full rounded-lg border border-surface-200 bg-surface-50 py-1.5 pl-9 pr-4 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
              />
            </div>

            {/* Column toggle (next to search) */}
            <div className="relative" ref={columnMenuRef}>
              <button
                onClick={() => setColumnMenuOpen((v) => !v)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-surface-50 px-2.5 py-1.5 text-xs font-medium text-surface-600 transition-colors hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700"
                title="Toggle columns"
              >
                <Settings2 className="h-3.5 w-3.5" /> Columns
              </button>
              {columnMenuOpen && (
                <div className="absolute left-0 top-full z-50 mt-1 w-48 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                  <div className="p-2 text-xs font-medium text-surface-500 uppercase tracking-wider">Toggle Columns</div>
                  {OPTIONAL_COLUMNS.filter((col) => assignmentEnabled || col.key !== 'assigned_to').map((col) => (
                    <label
                      key={col.key}
                      className="flex items-center gap-2 px-3 py-2 text-sm cursor-pointer hover:bg-surface-50 dark:hover:bg-surface-700"
                    >
                      <input
                        type="checkbox"
                        checked={visibleColumns.has(col.key)}
                        onChange={() => toggleColumn(col.key)}
                        className="h-3.5 w-3.5 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                      />
                      <col.icon className="h-3.5 w-3.5 text-surface-400" />
                      <span className="text-surface-700 dark:text-surface-200">{col.label}</span>
                    </label>
                  ))}
                </div>
              )}
            </div>

            {/* Status filter dropdown */}
            <select
              value={statusFilter}
              onChange={(e) => setParam('status_id', e.target.value)}
              className="hidden sm:block rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm text-surface-700 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
            >
              <option value="">All Statuses</option>
              {statuses.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </select>

            {/* Assigned To filter — CROSS1: hidden when assignment feature off */}
            {assignmentEnabled && (
              <select
                value={assignedTo}
                onChange={(e) => setParam('assigned_to', e.target.value)}
                className="hidden md:block rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm text-surface-700 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
              >
                <option value="">All Assigned</option>
                {assignedTo === 'me' && <option value="me">Me</option>}
                {users.map((u) => (
                  <option key={u.id} value={u.id}>{u.first_name} {u.last_name}</option>
                ))}
              </select>
            )}

            {/* Saved filter presets */}
            <SavedFiltersDropdown
              currentFilters={{ status_id: statusFilter, status_group: statusGroupFilter, assigned_to: assignedTo, date_filter: dateFilter, keyword, sort_by: sortBy, sort_order: sortOrder }}
              onApply={(filters) => {
                setSearchParams((prev) => {
                  const next = new URLSearchParams(prev);
                  for (const [k, v] of Object.entries(filters)) {
                    if (v) next.set(k, String(v)); else next.delete(k);
                  }
                  if (filters.status_id) next.delete('status_group');
                  else if (filters.status_group) next.delete('status_id');
                  next.set('page', '1');
                  return next;
                });
                if (filters.keyword != null) setSearchInput(filters.keyword || '');
              }}
            />

            {/* Export CSV */}
            <button
              onClick={async () => {
                try {
                  const resp = await ticketApi.exportCsv({
                    ...(keyword ? { keyword } : {}),
                    ...(statusFilter ? { status_id: statusFilter } : {}),
                    ...(statusGroupFilter ? { status_group: statusGroupFilter } : {}),
                    ...(assignedTo ? { assigned_to: assignedTo === 'me' ? 'me' as const : Number(assignedTo) } : {}),
                    ...(dateFilter ? { date_filter: dateFilter } : {}),
                    sort_by: sortBy,
                    sort_order: sortOrder,
                  });
                  const blob = new Blob([resp.data], { type: 'text/csv' });
                  const url = URL.createObjectURL(blob);
                  const a = document.createElement('a');
                  a.href = url;
                  a.download = 'tickets-export.csv';
                  a.click();
                  URL.revokeObjectURL(url);
                  toast.success('Exported tickets');
                } catch {
                  toast.error('Export failed');
                }
              }}
              className="hidden sm:inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-surface-50 px-2.5 py-1.5 text-xs font-medium text-surface-600 transition-colors hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700"
              title="Export tickets as CSV"
            >
              <Download className="h-3.5 w-3.5" /> Export
            </button>

          </div>
        </div>

        {/* Bulk action bar */}
        {selected.size > 0 && (
          <div className="flex items-center gap-3 border-b border-surface-200 bg-primary-50 px-4 py-2.5 dark:border-surface-700 dark:bg-primary-950/30">
            <span className="text-sm font-medium text-primary-700 dark:text-primary-300">
              {selected.size} selected
            </span>
            <div className="relative" ref={bulkStatusRef}>
              <button
                onClick={() => setBulkStatusOpen((v) => !v)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
              >
                Change Status <ChevronDown className="h-3.5 w-3.5" />
              </button>
              {bulkStatusOpen && (
                <div className="absolute left-0 top-full z-50 mt-1 w-56 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                  <div className="max-h-64 overflow-y-auto py-1">
                    {statuses.map((s) => (
                      <button
                        key={s.id}
                        onClick={() => {
                          bulkMut.mutate({ action: 'change_status', value: s.id });
                          setBulkStatusOpen(false);
                        }}
                        className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-surface-50 dark:hover:bg-surface-700"
                      >
                        <span className="h-2 w-2 rounded-full" style={{ backgroundColor: safeColor(s.color) }} />
                        <span className="text-surface-700 dark:text-surface-200">{s.name}</span>
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>
            <button
              onClick={() => setConfirmDlg({ open: true, bulk: true, ticketLabel: `${selected.size} ticket(s)` })}
              className="inline-flex items-center gap-1.5 rounded-lg border border-red-200 bg-white px-3 py-1.5 text-sm text-red-600 shadow-sm transition-colors hover:bg-red-50 dark:border-red-800 dark:bg-surface-800 dark:text-red-400"
            >
              <Trash2 className="h-3.5 w-3.5" /> Delete
            </button>
            <button
              onClick={() => setSelected(new Set())}
              className="ml-auto text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
            >
              Clear
            </button>
          </div>
        )}

        {/* Mobile card layout */}
        <div className="md:hidden overflow-auto flex-1 min-h-0">
          {isLoading ? (
            <div className="p-4 space-y-3">
              {Array.from({ length: 5 }).map((_, i) => (
                <div key={i} className="animate-pulse rounded-lg border border-surface-200 dark:border-surface-700 p-3 space-y-2">
                  <div className="h-4 w-24 bg-surface-200 dark:bg-surface-700 rounded" />
                  <div className="h-3 w-40 bg-surface-100 dark:bg-surface-800 rounded" />
                  <div className="h-3 w-20 bg-surface-100 dark:bg-surface-800 rounded" />
                </div>
              ))}
            </div>
          ) : tickets.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-20">
              <Wrench className="mb-4 h-12 w-12 text-surface-300 dark:text-surface-600" />
              <h2 className="text-base font-medium text-surface-600 dark:text-surface-400">No Tickets</h2>
            </div>
          ) : (
            <div className="divide-y divide-surface-100 dark:divide-surface-700/50">
              {tickets.map((ticket) => {
                const customer = ticket.customer;
                const firstDevice = (ticket as any).first_device;
                const devices = ticket.devices || [];
                const deviceName = firstDevice?.device_name || (devices[0]?.device_name) || '--';
                return (
                  <div
                    key={ticket.id}
                    onClick={() => navigate(`/tickets/${ticket.id}`)}
                    className={cn(
                      'p-3 cursor-pointer active:bg-surface-100 dark:active:bg-surface-800 transition-colors',
                      (() => {
                        if (ticket.status?.is_closed || ticket.status?.is_cancelled) return '';
                        const ua = ticket.updated_at;
                        const days = (Date.now() - new Date(ua.endsWith('Z') ? ua : ua + 'Z').getTime()) / 86400000;
                        if (days > 7) return 'border-l-4 border-l-red-400';
                        if (days > 3) return 'border-l-4 border-l-amber-400';
                        return '';
                      })(),
                    )}
                  >
                    <div className="flex items-center justify-between mb-1">
                      <div className="flex items-center gap-2">
                        <UrgencyDot urgency={(ticket as any).urgency} showLabel />
                        <span className="font-medium text-primary-600 dark:text-primary-400 text-sm">
                          {formatTicketId(ticket.order_id || ticket.id)}
                        </span>
                        <StatusDropdown ticket={ticket} statuses={statuses} onChangeStatus={handleChangeStatus} />
                      </div>
                      <span className="text-xs text-surface-400">{timeAgo(ticket.created_at)}</span>
                    </div>
                    <div className="text-sm text-surface-800 dark:text-surface-200">
                      {customer ? `${customer.first_name} ${customer.last_name}` : '--'}
                    </div>
                    <div className="flex items-center justify-between mt-1">
                      <span className="text-xs text-surface-500 dark:text-surface-400 truncate max-w-[200px]">{deviceName}</span>
                      <span className="text-sm font-medium text-surface-800 dark:text-surface-200">{formatCurrency(ticket.total)}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Desktop table */}
        <div className="hidden md:block overflow-auto flex-1 min-h-0">
          <table className="w-full text-left text-sm">
            <thead className="sticky top-0 z-10 bg-white dark:bg-surface-900">
              <tr className="border-b border-surface-200 dark:border-surface-700">
                <th className="px-4 py-3 w-10">
                  <input
                    type="checkbox"
                    checked={tickets.length > 0 && selected.size === tickets.length}
                    onChange={toggleSelectAll}
                    className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                  />
                </th>
                <SortHeader label="ID" column="order_id" currentSort={sortBy} currentOrder={sortOrder} onSort={handleSort} />
                <th className="px-2 py-3 w-8 font-medium text-surface-500 dark:text-surface-400" title="Priority">
                  <AlertTriangle className="h-3.5 w-3.5 mx-auto" />
                </th>
                {visibleColumns.has('internal_note') && (
                  <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Internal Note</th>
                )}
                {visibleColumns.has('diagnostic_note') && (
                  <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Diagnostic Note</th>
                )}
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Device</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Customer</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Issue</th>
                {visibleColumns.has('ticket_items') && (
                  <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Ticket Items</th>
                )}
                <SortHeader label="Created" column="created_at" currentSort={sortBy} currentOrder={sortOrder} onSort={handleSort} />
                <SortHeader label="Status" column="status_id" currentSort={sortBy} currentOrder={sortOrder} onSort={handleSort} />
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Due</th>
                {effectiveVisibleColumns.has('assigned_to') && (
                  <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Assigned To</th>
                )}
                <SortHeader label="Total" column="total" currentSort={sortBy} currentOrder={sortOrder} onSort={handleSort} className="text-right" />
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {showSkeleton ? (
                Array.from({ length: 8 }).map((_, i) => <SkeletonRow key={i} />)
              ) : isLoading && tickets.length === 0 ? (
                // Loading but under the 150ms threshold — render nothing
                // rather than flash a skeleton.
                null
              ) : tickets.length === 0 ? (
                <tr>
                  <td colSpan={10 + effectiveVisibleColumns.size}>
                    <div className="flex flex-col items-center justify-center py-20">
                      <Wrench className="mb-4 h-16 w-16 text-surface-300 dark:text-surface-600" />
                      <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">No Tickets</h2>
                      <p className="text-sm text-surface-400 dark:text-surface-500">
                        {keyword || statusFilter || dateFilter
                          ? 'No tickets match your filters'
                          : 'Create your first ticket to get started'}
                      </p>
                    </div>
                  </td>
                </tr>
              ) : (
                tickets.map((ticket) => (
                  <TicketRow
                    key={ticket.id}
                    ticket={ticket}
                    statuses={statuses}
                    visibleColumns={effectiveVisibleColumns}
                    isSelected={selected.has(ticket.id)}
                    isExpanded={expandedId === ticket.id}
                    onNavigate={navigate}
                    onToggleSelect={toggleSelect}
                    onToggleExpand={setExpandedId}
                    onChangeStatus={handleChangeStatus}
                    onPin={handlePin}
                    onPrint={setPrintTicket}
                    onDelete={setConfirmDlg}
                    onAddNote={handleAddNote}
                    onSendSms={handleSendSms}
                  />
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination — only render when real data is present. During the
            initial skeleton load, pagination.total is 0 (or stale from a
            previous query), and mixing skeleton rows with "Showing 1–0 of 0"
            looks broken. W9 fix. */}
        {!isLoading && tickets.length > 0 && (
          <div className="flex flex-col sm:flex-row items-center justify-between gap-2 border-t border-surface-200 px-3 md:px-4 py-3 dark:border-surface-700">
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-1.5">
                <span className="text-xs text-surface-500 dark:text-surface-400">Show</span>
                <select
                  value={pageSize}
                  onChange={(e) => {
                    const v = e.target.value;
                    localStorage.setItem('tickets_pagesize', v);
                    setSearchParams((prev) => {
                      const next = new URLSearchParams(prev);
                      next.set('pagesize', v);
                      next.set('page', '1');
                      return next;
                    });
                  }}
                  className="text-xs rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-2 py-1 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
                >
                  {[10, 25, 50, 100, 250].map((n) => (
                    <option key={n} value={n}>{n}</option>
                  ))}
                </select>
                <span className="text-xs text-surface-500 dark:text-surface-400">per page</span>
              </div>
              <p className="text-xs sm:text-sm text-surface-500 dark:text-surface-400">
                Showing {((page - 1) * pagination.per_page) + 1}–{Math.min(page * pagination.per_page, pagination.total)} of {pagination.total}
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
                    onClick={() => setSearchParams((prev) => {
                      const next = new URLSearchParams(prev);
                      next.set('page', String(pageNum));
                      return next;
                    })}
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
                onClick={() => setSearchParams((prev) => {
                  const next = new URLSearchParams(prev);
                  next.set('page', String(page + 1));
                  return next;
                })}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700 min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
            )}
          </div>
        )}

        {/* Loading overlay for background refetch */}
        {isFetching && !isLoading && (
          <div className="absolute inset-0 flex items-center justify-center bg-white/40 dark:bg-surface-900/40">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary-200 border-t-primary-600" />
          </div>
        )}
      </div>}

      {printTicket && (
        <PrintPreviewModal
          ticketId={printTicket.id}
          invoiceId={printTicket.invoiceId}
          onClose={() => setPrintTicket(null)}
        />
      )}
      <ConfirmDialog
        open={confirmDlg.open}
        title={confirmDlg.bulk ? `Delete ${confirmDlg.ticketLabel}` : `Delete Ticket ${confirmDlg.ticketLabel}`}
        message="This action cannot be undone. All ticket data will be permanently deleted."
        confirmLabel="Delete"
        danger
        requireTyping
        confirmText={confirmDlg.bulk ? 'DELETE' : (confirmDlg.ticketLabel || '')}
        onConfirm={() => {
          if (confirmDlg.bulk) {
            bulkMut.mutate({ action: 'delete' });
          } else if (confirmDlg.ticketId) {
            scheduleTicketDelete(confirmDlg.ticketId, confirmDlg.ticketLabel || String(confirmDlg.ticketId));
          }
          setConfirmDlg({ open: false });
        }}
        onCancel={() => setConfirmDlg({ open: false })}
      />
    </div>
  );
}
