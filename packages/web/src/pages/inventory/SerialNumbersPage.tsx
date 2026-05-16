/**
 * Serialized part units — bulk paste serials for an item, then manage status
 * (in stock / sold / returned / defective / RMA).
 *
 * Cross-ref: criticalaudit.md §48 idea #6.
 */
import { useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, Hash, Plus, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';
import { confirm } from '@/stores/confirmStore';
import { formatDate } from '@/utils/format';
import { InventoryItemPicker } from '@/components/inventory/InventoryItemPicker';

interface SerialRow {
  id: number;
  inventory_item_id: number;
  serial_number: string;
  status: 'in_stock' | 'sold' | 'returned' | 'defective' | 'rma';
  received_at: string;
  sold_at: string | null;
  invoice_id: number | null;
  ticket_id: number | null;
  notes: string | null;
}

interface SerialReferenceDraft {
  invoiceId: string;
  ticketId: string;
  notes: string;
}

interface SerialStatusUpdate {
  serialId: number;
  status: SerialRow['status'];
  invoiceId: string;
  ticketId: string;
  notes: string;
}

const STATUS_COLORS: Record<SerialRow['status'], string> = {
  in_stock: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
  sold: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300',
  returned: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
  defective: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
  rma: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300',
};

const STATUS_LABELS: Record<SerialRow['status'], string> = {
  in_stock: 'In stock',
  sold: 'Sold',
  returned: 'Returned',
  defective: 'Defective',
  rma: 'RMA',
};

const SENSITIVE_STATUSES = new Set<SerialRow['status']>(['sold', 'defective', 'rma']);

export function SerialNumbersPage() {
  const queryClient = useQueryClient();
  const [searchParams] = useSearchParams();
  const initialItemId = Number(searchParams.get('item'));
  const [itemId, setItemId] = useState<number | null>(Number.isFinite(initialItemId) && initialItemId > 0 ? initialItemId : null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [bulkInput, setBulkInput] = useState('');
  const [referenceDrafts, setReferenceDrafts] = useState<Record<number, SerialReferenceDraft>>({});

  const { data: serialsData } = useQuery({
    queryKey: ['serials', itemId, statusFilter],
    queryFn: async () => {
      if (!itemId) return [];
      const url = statusFilter
        ? `/inventory-enrich/${itemId}/serials?status=${statusFilter}`
        : `/inventory-enrich/${itemId}/serials`;
      const res = await api.get<{ success: boolean; data: SerialRow[] }>(url);
      return res.data.data;
    },
    enabled: !!itemId,
    staleTime: 30_000,
  });
  const serials: SerialRow[] = serialsData || [];

  const addMut = useMutation({
    mutationFn: async () => {
      const serialsArr = bulkInput
        .split(/[\n,]+/)
        .map((s) => s.trim())
        .filter(Boolean);
      const res = await api.post(`/inventory-enrich/${itemId}/serials`, { serials: serialsArr });
      return res.data.data;
    },
    onSuccess: (data: any) => {
      toast.success(`Added ${data.count} serials (${data.duplicates?.length || 0} duplicates)`);
      queryClient.invalidateQueries({ queryKey: ['serials'] });
      setBulkInput('');
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to add'),
  });

  const getReferenceDraft = (serial: SerialRow): SerialReferenceDraft =>
    referenceDrafts[serial.id] ?? {
      invoiceId: serial.invoice_id ? String(serial.invoice_id) : '',
      ticketId: serial.ticket_id ? String(serial.ticket_id) : '',
      notes: '',
    };

  const updateReferenceDraft = (
    serial: SerialRow,
    patch: Partial<SerialReferenceDraft>,
  ) => {
    setReferenceDrafts((current) => ({
      ...current,
      [serial.id]: {
        ...(current[serial.id] ?? {
          invoiceId: serial.invoice_id ? String(serial.invoice_id) : '',
          ticketId: serial.ticket_id ? String(serial.ticket_id) : '',
          notes: '',
        }),
        ...patch,
      },
    }));
  };

  const statusMut = useMutation({
    mutationFn: async ({ serialId, status, invoiceId, ticketId, notes }: SerialStatusUpdate) => {
      const payload: Record<string, unknown> = { status };
      if (invoiceId.trim()) payload.invoice_id = Number(invoiceId);
      if (ticketId.trim()) payload.ticket_id = Number(ticketId);
      if (notes.trim()) payload.notes = notes.trim();
      const res = await api.put(`/inventory-enrich/serials/${serialId}`, payload);
      return res.data.data;
    },
    onSuccess: (data: SerialRow & { stock_delta?: number }) => {
      queryClient.invalidateQueries({ queryKey: ['serials'] });
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      setReferenceDrafts((current) => {
        const next = { ...current };
        delete next[data.id];
        return next;
      });
      toast.success(
        typeof data.stock_delta === 'number' && data.stock_delta !== 0
          ? `Status updated; stock ${data.stock_delta > 0 ? '+' : ''}${data.stock_delta}`
          : 'Status updated',
      );
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to update'),
  });

  const requestStatusChange = async (
    serial: SerialRow,
    status: SerialRow['status'],
    draft: SerialReferenceDraft,
  ) => {
    if (status === serial.status) return;
    const ok = await confirm(
      `Change serial ${serial.serial_number} from ${STATUS_LABELS[serial.status]} to ${STATUS_LABELS[status]}? This can update inventory counts and stored invoice/ticket references.`,
      {
        title: 'Confirm serial status',
        confirmLabel: 'Change status',
        danger: SENSITIVE_STATUSES.has(serial.status) || SENSITIVE_STATUSES.has(status),
      },
    );
    if (!ok) return;
    statusMut.mutate({
      serialId: serial.id,
      status,
      invoiceId: draft.invoiceId,
      ticketId: draft.ticketId,
      notes: draft.notes,
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
          <ChevronLeft className="h-4 w-4" /> Back to Inventory
        </Link>
        <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
          <Hash className="h-6 w-6" /> Serial Numbers
        </h1>
        <p className="text-sm text-surface-500">Track individual units with per-unit status</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <InventoryItemPicker
          value={itemId}
          onChange={(item) => setItemId(item?.id ?? null)}
          label="Inventory item"
          placeholder="Search serialized item..."
        />
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
        >
          <option value="">All statuses</option>
          <option value="in_stock">In stock</option>
          <option value="sold">Sold</option>
          <option value="returned">Returned</option>
          <option value="defective">Defective</option>
          <option value="rma">RMA</option>
        </select>
      </div>

      {itemId && (
        <div className="rounded-lg border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800">
          <h3 className="font-semibold mb-2 flex items-center gap-2">
            <Plus className="h-4 w-4" /> Bulk add serials
          </h3>
          <textarea
            value={bulkInput}
            onChange={(e) => setBulkInput(e.target.value)}
            placeholder="Paste serials, one per line or comma-separated"
            className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-sm font-mono text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
            rows={4}
          />
          <button
            onClick={() => addMut.mutate()}
            disabled={!bulkInput.trim() || addMut.isPending}
            className="mt-2 rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-on-primary disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            {addMut.isPending && <Loader2 className="inline h-4 w-4 animate-spin mr-1" />}
            Add {bulkInput.split(/[\n,]+/).filter((s) => s.trim()).length} serials
          </button>
        </div>
      )}

      <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto dark:border-surface-700 dark:bg-surface-800">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200 dark:border-surface-700 dark:bg-surface-900">
            <tr>
              <th className="text-left px-3 py-2">Serial</th>
              <th className="text-left px-3 py-2">Status</th>
              <th className="text-left px-3 py-2">Received</th>
              <th className="text-left px-3 py-2">Sold</th>
              <th className="text-left px-3 py-2">Refs / notes</th>
              <th className="text-left px-3 py-2">Change status</th>
            </tr>
          </thead>
          <tbody>
            {!itemId && (
              <tr>
                <td colSpan={6} className="text-center py-8 text-surface-400">
                  Enter an inventory item ID to view serials
                </td>
              </tr>
            )}
            {itemId && serials.length === 0 && (
              <tr>
                <td colSpan={6} className="text-center py-8 text-surface-400">
                  No serials for this item yet
                </td>
              </tr>
            )}
            {serials.map((s) => {
              const draft = getReferenceDraft(s);
              const isUpdating = statusMut.isPending && statusMut.variables?.serialId === s.id;
              return (
                <tr key={s.id} className="border-b border-surface-100 last:border-0 align-top dark:border-surface-700">
                  <td className="px-3 py-2 font-mono">{s.serial_number}</td>
                  <td className="px-3 py-2">
                    <span
                      className={cn(
                        'px-2 py-0.5 rounded-full text-xs font-medium',
                        STATUS_COLORS[s.status],
                      )}
                    >
                      {s.status.replace('_', ' ')}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-xs text-surface-500">
                    {formatDate(s.received_at)}
                  </td>
                  <td className="px-3 py-2 text-xs text-surface-500">
                    {formatDate(s.sold_at)}
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex min-w-[220px] flex-col gap-1">
                      <div className="grid grid-cols-2 gap-1">
                        <input
                          value={draft.invoiceId}
                          onChange={(e) => updateReferenceDraft(s, { invoiceId: e.target.value })}
                          type="number"
                          min="1"
                          placeholder="Invoice #"
                          aria-label={`Invoice reference for serial ${s.serial_number}`}
                          disabled={isUpdating}
                          className="w-full rounded border border-surface-300 bg-white px-2 py-1 text-xs text-surface-900 placeholder:text-surface-400 disabled:opacity-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
                        />
                        <input
                          value={draft.ticketId}
                          onChange={(e) => updateReferenceDraft(s, { ticketId: e.target.value })}
                          type="number"
                          min="1"
                          placeholder="Ticket #"
                          aria-label={`Ticket reference for serial ${s.serial_number}`}
                          disabled={isUpdating}
                          className="w-full rounded border border-surface-300 bg-white px-2 py-1 text-xs text-surface-900 placeholder:text-surface-400 disabled:opacity-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
                        />
                      </div>
                      <input
                        value={draft.notes}
                        onChange={(e) => updateReferenceDraft(s, { notes: e.target.value })}
                        placeholder={s.notes || 'Movement notes'}
                        aria-label={`Movement notes for serial ${s.serial_number}`}
                        disabled={isUpdating}
                        className="w-full rounded border border-surface-300 bg-white px-2 py-1 text-xs text-surface-900 placeholder:text-surface-400 disabled:opacity-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
                      />
                      {(s.invoice_id || s.ticket_id) && (
                        <div className="text-[11px] text-surface-500">
                          {s.invoice_id ? `Invoice #${s.invoice_id}` : ''}
                          {s.invoice_id && s.ticket_id ? ' · ' : ''}
                          {s.ticket_id ? `Ticket #${s.ticket_id}` : ''}
                        </div>
                      )}
                    </div>
                  </td>
                  <td className="px-3 py-2">
                    <select
                      value={s.status}
                      onChange={(e) => {
                        void requestStatusChange(s, e.target.value as SerialRow['status'], draft);
                      }}
                      disabled={isUpdating}
                      className="rounded border border-surface-300 bg-white px-2 py-1 text-xs text-surface-900 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                    >
                      <option value="in_stock">{STATUS_LABELS.in_stock}</option>
                      <option value="sold">{STATUS_LABELS.sold}</option>
                      <option value="returned">{STATUS_LABELS.returned}</option>
                      <option value="defective">{STATUS_LABELS.defective}</option>
                      <option value="rma">{STATUS_LABELS.rma}</option>
                    </select>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
