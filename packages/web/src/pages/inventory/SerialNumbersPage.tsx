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

const STATUS_COLORS: Record<SerialRow['status'], string> = {
  in_stock: 'bg-green-100 text-green-700',
  sold: 'bg-blue-100 text-blue-700',
  returned: 'bg-amber-100 text-amber-700',
  defective: 'bg-red-100 text-red-700',
  rma: 'bg-purple-100 text-purple-700',
};

export function SerialNumbersPage() {
  const queryClient = useQueryClient();
  const [searchParams] = useSearchParams();
  const [itemId, setItemId] = useState(searchParams.get('item') || '');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [bulkInput, setBulkInput] = useState('');

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

  const statusMut = useMutation({
    mutationFn: async ({ serialId, status }: { serialId: number; status: string }) => {
      const res = await api.put(`/inventory-enrich/serials/${serialId}`, { status });
      return res.data.data;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['serials'] }),
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to update'),
  });

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
        <input
          value={itemId}
          onChange={(e) => setItemId(e.target.value)}
          placeholder="Inventory item ID"
          type="number"
          className="rounded-md border border-surface-300 px-3 py-2 text-sm"
        />
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-md border border-surface-300 px-3 py-2 text-sm"
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
        <div className="rounded-lg border border-surface-200 bg-white p-4">
          <h3 className="font-semibold mb-2 flex items-center gap-2">
            <Plus className="h-4 w-4" /> Bulk add serials
          </h3>
          <textarea
            value={bulkInput}
            onChange={(e) => setBulkInput(e.target.value)}
            placeholder="Paste serials, one per line or comma-separated"
            className="w-full rounded-md border border-surface-300 px-3 py-2 text-sm font-mono"
            rows={4}
          />
          <button
            onClick={() => addMut.mutate()}
            disabled={!bulkInput.trim() || addMut.isPending}
            className="mt-2 rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 disabled:opacity-50"
          >
            {addMut.isPending && <Loader2 className="inline h-4 w-4 animate-spin mr-1" />}
            Add {bulkInput.split(/[\n,]+/).filter((s) => s.trim()).length} serials
          </button>
        </div>
      )}

      <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200">
            <tr>
              <th className="text-left px-3 py-2">Serial</th>
              <th className="text-left px-3 py-2">Status</th>
              <th className="text-left px-3 py-2">Received</th>
              <th className="text-left px-3 py-2">Sold</th>
              <th className="text-left px-3 py-2">Change status</th>
            </tr>
          </thead>
          <tbody>
            {!itemId && (
              <tr>
                <td colSpan={5} className="text-center py-8 text-surface-400">
                  Enter an inventory item ID to view serials
                </td>
              </tr>
            )}
            {itemId && serials.length === 0 && (
              <tr>
                <td colSpan={5} className="text-center py-8 text-surface-400">
                  No serials for this item yet
                </td>
              </tr>
            )}
            {serials.map((s) => (
              <tr key={s.id} className="border-b border-surface-100 last:border-0">
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
                  {new Date(s.received_at).toLocaleDateString()}
                </td>
                <td className="px-3 py-2 text-xs text-surface-500">
                  {s.sold_at ? new Date(s.sold_at).toLocaleDateString() : '—'}
                </td>
                <td className="px-3 py-2">
                  <select
                    value={s.status}
                    onChange={(e) => statusMut.mutate({ serialId: s.id, status: e.target.value })}
                    disabled={statusMut.isPending && statusMut.variables?.serialId === s.id}
                    className="rounded border border-surface-300 px-2 py-1 text-xs disabled:opacity-50"
                  >
                    <option value="in_stock">In stock</option>
                    <option value="sold">Sold</option>
                    <option value="returned">Returned</option>
                    <option value="defective">Defective</option>
                    <option value="rma">RMA</option>
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
