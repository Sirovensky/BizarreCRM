import { useState, useCallback, DragEvent } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { GripVertical } from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency, timeAgo } from '@/utils/format';

// ─── Types ─────────────────────────────────────────────────────────

interface KanbanStatus {
  id: number;
  name: string;
  color: string;
  sort_order: number;
  is_closed: boolean;
  is_cancelled: boolean;
}

interface KanbanTicket {
  id: number;
  order_id: string | number;
  customer_id: number | null;
  status_id: number;
  assigned_to: number | null;
  total: number;
  due_on: string | null;
  labels: string[];
  created_at: string;
  updated_at: string;
  customer: { id: number; first_name: string | null; last_name: string | null } | null;
  assigned_user: { id: number; first_name: string | null; last_name: string | null } | null;
}

interface KanbanColumn {
  status: KanbanStatus;
  tickets: KanbanTicket[];
}

// ─── Helpers ───────────────────────────────────────────────────────

function formatTicketId(orderId: string | number): string {
  const str = String(orderId);
  return str.startsWith('T-') ? str : `T-${str.padStart(4, '0')}`;
}

function daysSince(iso: string): number {
  const ts = iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z';
  return Math.floor((Date.now() - new Date(ts).getTime()) / 86400000);
}

function customerName(ticket: KanbanTicket): string {
  if (!ticket.customer) return 'Walk-in';
  const { first_name, last_name } = ticket.customer;
  if (first_name && last_name) return `${first_name} ${last_name}`;
  return first_name || last_name || 'Walk-in';
}

function assignedName(ticket: KanbanTicket): string | null {
  if (!ticket.assigned_user) return null;
  const { first_name, last_name } = ticket.assigned_user;
  if (first_name && last_name) return `${first_name} ${last_name}`;
  return first_name || last_name || null;
}

// ─── Card Component ────────────────────────────────────────────────

interface CardProps {
  ticket: KanbanTicket;
  statusColor: string;
  onDragStart: (e: DragEvent, ticketId: number) => void;
}

function KanbanCard({ ticket, statusColor, onDragStart }: CardProps) {
  const navigate = useNavigate();
  const days = daysSince(ticket.updated_at);
  const tech = assignedName(ticket);

  return (
    <div
      draggable
      onDragStart={(e) => onDragStart(e, ticket.id)}
      onClick={() => navigate(`/tickets/${ticket.id}`)}
      className={cn(
        'group relative cursor-pointer rounded-lg border border-surface-200 bg-white p-3 shadow-sm transition-shadow hover:shadow-md dark:border-surface-700 dark:bg-surface-800',
        days >= 7 && 'bg-red-50 dark:bg-red-950/20',
        days >= 3 && days < 7 && 'bg-amber-50 dark:bg-amber-950/20',
      )}
      style={{ borderLeftWidth: '3px', borderLeftColor: statusColor }}
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-xs font-bold text-primary-600 dark:text-primary-400">
          {formatTicketId(ticket.order_id)}
        </span>
        <span className="text-xs text-surface-400">{timeAgo(ticket.updated_at)}</span>
      </div>
      <div className="mt-1 text-sm font-medium text-surface-900 dark:text-surface-100 truncate">
        {customerName(ticket)}
      </div>
      <div className="mt-2 flex items-center justify-between gap-2">
        {tech && (
          <span className="truncate text-xs text-surface-500 dark:text-surface-400">
            {tech}
          </span>
        )}
        {!tech && <span />}
        <span className="shrink-0 text-xs font-semibold text-surface-700 dark:text-surface-300">
          {formatCurrency(ticket.total || 0)}
        </span>
      </div>
      <GripVertical className="absolute top-2 right-1 h-3.5 w-3.5 text-surface-300 opacity-0 group-hover:opacity-100 transition-opacity" />
    </div>
  );
}

// ─── Kanban Board ──────────────────────────────────────────────────

export default function KanbanBoard() {
  const queryClient = useQueryClient();
  const [dragTicketId, setDragTicketId] = useState<number | null>(null);
  const [dragOverStatus, setDragOverStatus] = useState<number | null>(null);
  const [showEmpty, setShowEmpty] = useState(false);
  const [showClosed, setShowClosed] = useState(false);

  const { data: kanbanData, isLoading } = useQuery({
    queryKey: ['tickets-kanban'],
    queryFn: () => ticketApi.kanban(),
    refetchInterval: 30000,
  });

  const allColumns: KanbanColumn[] = kanbanData?.data?.data?.columns || [];

  // Filter columns: hide empty (unless toggled), hide closed/cancelled (unless toggled)
  const columns = allColumns.filter(col => {
    if (!showClosed && (col.status.is_closed || col.status.is_cancelled)) return false;
    if (!showEmpty && col.tickets.length === 0) return false;
    return true;
  });

  const hiddenEmpty = allColumns.filter(c => c.tickets.length === 0 && !c.status.is_closed && !c.status.is_cancelled).length;
  const hiddenClosed = allColumns.filter(c => c.status.is_closed || c.status.is_cancelled).length;

  const statusMutation = useMutation({
    mutationFn: ({ id, statusId }: { id: number; statusId: number }) =>
      ticketApi.changeStatus(id, statusId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tickets-kanban'] });
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
    },
    onError: () => {
      toast.error('Failed to update ticket status');
    },
  });

  const handleDragStart = useCallback((e: DragEvent, ticketId: number) => {
    setDragTicketId(ticketId);
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', String(ticketId));
  }, []);

  const handleDragOver = useCallback((e: DragEvent, statusId: number) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    setDragOverStatus(statusId);
  }, []);

  const handleDragLeave = useCallback(() => {
    setDragOverStatus(null);
  }, []);

  const handleDrop = useCallback(
    (e: DragEvent, targetStatusId: number) => {
      e.preventDefault();
      setDragOverStatus(null);
      if (dragTicketId == null) return;

      // Find current status of the ticket (search allColumns so filtered-out columns are still found)
      const sourceColumn = allColumns.find((col) =>
        col.tickets.some((t) => t.id === dragTicketId),
      );
      if (!sourceColumn || sourceColumn.status.id === targetStatusId) {
        setDragTicketId(null);
        return;
      }

      statusMutation.mutate({ id: dragTicketId, statusId: targetStatusId });
      setDragTicketId(null);
    },
    [dragTicketId, allColumns, statusMutation],
  );

  const handleDragEnd = useCallback(() => {
    setDragTicketId(null);
    setDragOverStatus(null);
  }, []);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20 text-surface-500">
        Loading kanban board...
      </div>
    );
  }

  if (columns.length === 0) {
    return (
      <div className="flex items-center justify-center py-20 text-surface-500">
        No statuses configured.
      </div>
    );
  }

  return (
    <div>
      {/* Board filters */}
      <div className="flex items-center gap-3 mb-3">
        {hiddenEmpty > 0 && (
          <button
            onClick={() => setShowEmpty(!showEmpty)}
            className={cn(
              'text-xs px-3 py-2.5 min-h-[44px] md:min-h-0 md:px-2.5 md:py-1 rounded-md border transition-colors',
              showEmpty
                ? 'bg-surface-200 dark:bg-surface-700 border-surface-300 dark:border-surface-600 text-surface-700 dark:text-surface-300'
                : 'border-surface-200 dark:border-surface-700 text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800'
            )}
          >
            {showEmpty ? 'Hide' : 'Show'} empty columns ({hiddenEmpty})
          </button>
        )}
        <button
          onClick={() => setShowClosed(!showClosed)}
          className={cn(
            'text-xs px-3 py-2.5 min-h-[44px] md:min-h-0 md:px-2.5 md:py-1 rounded-md border transition-colors',
            showClosed
              ? 'bg-surface-200 dark:bg-surface-700 border-surface-300 dark:border-surface-600 text-surface-700 dark:text-surface-300'
              : 'border-surface-200 dark:border-surface-700 text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800'
          )}
        >
          {showClosed ? 'Hide' : 'Show'} Closed/Cancelled ({hiddenClosed})
        </button>
        <span className="text-xs text-surface-400 ml-auto">
          {columns.length} columns · {columns.reduce((s, c) => s + c.tickets.length, 0)} tickets
        </span>
      </div>

      <div
        className="flex gap-4 overflow-x-auto pb-4"
        style={{ minHeight: 'calc(100vh - 290px - var(--dev-banner-h, 0px))' }}
      >
      {columns.map((col) => (
        <div
          key={col.status.id}
          className={cn(
            'flex flex-col rounded-xl border border-surface-200 bg-surface-50 dark:border-surface-700 dark:bg-surface-900/50',
            'min-w-[280px] w-[300px] shrink-0',
            dragOverStatus === col.status.id && 'ring-2 ring-primary-400 dark:ring-primary-600',
          )}
          onDragOver={(e) => handleDragOver(e, col.status.id)}
          onDragLeave={handleDragLeave}
          onDrop={(e) => handleDrop(e, col.status.id)}
        >
          {/* Column header */}
          <div className="flex items-center gap-2 border-b border-surface-200 px-4 py-3 dark:border-surface-700">
            <span
              className="h-3 w-3 rounded-full shrink-0"
              style={{ backgroundColor: col.status.color || '#6b7280' }}
            />
            <span className="text-sm font-semibold text-surface-900 dark:text-surface-100 truncate">
              {col.status.name}
            </span>
            <span className="ml-auto shrink-0 rounded-full bg-surface-200 px-2 py-0.5 text-xs font-medium text-surface-600 dark:bg-surface-700 dark:text-surface-300">
              {col.tickets.length}
            </span>
          </div>

          {/* Scrollable ticket list */}
          <div
            className="flex flex-col gap-2 overflow-y-auto p-3"
            style={{ maxHeight: 'calc(100vh - 320px - var(--dev-banner-h, 0px))' }}
          >
            {col.tickets.length === 0 && (
              <div className="py-8 text-center text-xs text-surface-400">
                No tickets
              </div>
            )}
            {col.tickets.map((ticket) => (
              <KanbanCard
                key={ticket.id}
                ticket={ticket}
                statusColor={col.status.color || '#6b7280'}
                onDragStart={handleDragStart}
              />
            ))}
          </div>
        </div>
      ))}
      </div>
    </div>
  );
}
