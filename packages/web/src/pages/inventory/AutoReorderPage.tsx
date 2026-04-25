/**
 * Auto-reorder rules page — exposes the previously hidden POST
 * /inventory/auto-reorder endpoint as a proper UI, plus per-item rule
 * configuration.
 *
 * Cross-ref: criticalaudit.md §48 idea #3.
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, RefreshCw, Zap, Loader2, Trash2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';
// WEB-FB-007 (Fixer-KKK 2026-04-25): themed async confirm — matches the
// pattern used on Estimates / POS / Customers / Tickets / Invoices.
import { confirm } from '@/stores/confirmStore';

interface AutoReorderRule {
  inventory_item_id: number;
  name: string;
  sku: string | null;
  in_stock: number;
  min_qty: number;
  reorder_qty: number;
  preferred_supplier_id: number | null;
  lead_time_days: number | null;
  is_enabled: number;
  supplier_name: string | null;
}

export function AutoReorderPage() {
  const queryClient = useQueryClient();
  const [searchTerm, setSearchTerm] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [itemId, setItemId] = useState('');
  const [minQty, setMinQty] = useState('');
  const [reorderQty, setReorderQty] = useState('');
  const [supplierId, setSupplierId] = useState('');
  const [leadTime, setLeadTime] = useState('');

  const { data: rulesData, isLoading } = useQuery({
    queryKey: ['auto-reorder-rules'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: AutoReorderRule[] }>(
        '/inventory-enrich/auto-reorder-rules',
      );
      return res.data.data;
    },
  });
  const rules: AutoReorderRule[] = rulesData || [];

  const runMut = useMutation({
    mutationFn: async () => {
      const res = await api.post('/inventory/auto-reorder');
      return res.data.data;
    },
    onSuccess: (data: any) => {
      if (data.orders_created === 0) {
        toast.success('Nothing to reorder — all stock levels OK');
      } else {
        toast.success(
          `Created ${data.orders_created} PO${data.orders_created > 1 ? 's' : ''} with ${data.items_ordered} items`,
        );
      }
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Auto-reorder failed'),
  });

  const upsertMut = useMutation({
    mutationFn: async () => {
      // SCAN-1133: `parseInt('')` returns NaN, which the server then rejects
      // with a generic 400 and the UI surfaces as "Save failed". Validate
      // each required numeric up front so the user gets a clear toast
      // naming the bad field. Optional ids/leads still allow empty → null.
      const itemIdN = parseInt(itemId, 10);
      const minQtyN = parseInt(minQty, 10);
      const reorderQtyN = parseInt(reorderQty, 10);
      if (!Number.isFinite(itemIdN) || itemIdN <= 0) {
        throw new Error('Item is required');
      }
      if (!Number.isFinite(minQtyN) || minQtyN < 0) {
        throw new Error('Minimum quantity must be a non-negative number');
      }
      if (!Number.isFinite(reorderQtyN) || reorderQtyN <= 0) {
        throw new Error('Reorder quantity must be a positive number');
      }
      const supplierIdN = supplierId ? parseInt(supplierId, 10) : null;
      const leadTimeN = leadTime ? parseInt(leadTime, 10) : null;
      if (supplierIdN !== null && (!Number.isFinite(supplierIdN) || supplierIdN <= 0)) {
        throw new Error('Preferred supplier id is invalid');
      }
      if (leadTimeN !== null && (!Number.isFinite(leadTimeN) || leadTimeN < 0)) {
        throw new Error('Lead time days is invalid');
      }
      const res = await api.post('/inventory-enrich/auto-reorder-rules', {
        inventory_item_id: itemIdN,
        min_qty: minQtyN,
        reorder_qty: reorderQtyN,
        preferred_supplier_id: supplierIdN,
        lead_time_days: leadTimeN,
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Rule saved');
      queryClient.invalidateQueries({ queryKey: ['auto-reorder-rules'] });
      setShowAdd(false);
      setItemId('');
      setMinQty('');
      setReorderQty('');
      setSupplierId('');
      setLeadTime('');
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Save failed'),
  });

  const deleteMut = useMutation({
    mutationFn: async (itemId: number) => {
      await api.delete(`/inventory-enrich/auto-reorder-rules/${itemId}`);
    },
    onSuccess: () => {
      toast.success('Rule removed');
      queryClient.invalidateQueries({ queryKey: ['auto-reorder-rules'] });
    },
  });

  const filteredRules = rules.filter(
    (r) =>
      !searchTerm ||
      r.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (r.sku || '').toLowerCase().includes(searchTerm.toLowerCase()),
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
            <ChevronLeft className="h-4 w-4" /> Back to Inventory
          </Link>
          <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
            <RefreshCw className="h-6 w-6" /> Auto-Reorder
          </h1>
          <p className="text-sm text-surface-500">
            Per-item reorder rules + one-click PO generation for low stock
          </p>
        </div>
        <button
          onClick={async () => {
            const ok = await confirm('Run auto-reorder? This creates purchase orders for all low-stock items.', {
              title: 'Run auto-reorder',
              confirmLabel: 'Run now',
            });
            if (ok) runMut.mutate();
          }}
          disabled={runMut.isPending}
          className="inline-flex items-center gap-2 rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 disabled:opacity-50"
        >
          {runMut.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Zap className="h-4 w-4" />
          )}
          Run Auto-Reorder Now
        </button>
      </div>

      <div className="flex items-center justify-between">
        <input
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          placeholder="Search rules..."
          className="rounded-md border border-surface-300 px-3 py-2 text-sm w-64"
        />
        <button
          onClick={() => setShowAdd(!showAdd)}
          className="rounded-md border border-surface-300 px-3 py-2 text-sm"
        >
          {showAdd ? 'Close' : 'Add Rule'}
        </button>
      </div>

      {showAdd && (
        <div className="rounded-lg border border-surface-200 bg-white p-4">
          <h3 className="font-semibold mb-3">Add / update rule</h3>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
            <input
              value={itemId}
              onChange={(e) => setItemId(e.target.value)}
              placeholder="Item ID"
              type="number"
              className="rounded border border-surface-300 px-2 py-1 text-sm"
            />
            <input
              value={minQty}
              onChange={(e) => setMinQty(e.target.value)}
              placeholder="Min qty"
              type="number"
              className="rounded border border-surface-300 px-2 py-1 text-sm"
            />
            <input
              value={reorderQty}
              onChange={(e) => setReorderQty(e.target.value)}
              placeholder="Reorder qty"
              type="number"
              className="rounded border border-surface-300 px-2 py-1 text-sm"
            />
            <input
              value={supplierId}
              onChange={(e) => setSupplierId(e.target.value)}
              placeholder="Supplier ID"
              type="number"
              className="rounded border border-surface-300 px-2 py-1 text-sm"
            />
            <input
              value={leadTime}
              onChange={(e) => setLeadTime(e.target.value)}
              placeholder="Lead time (days)"
              type="number"
              className="rounded border border-surface-300 px-2 py-1 text-sm"
            />
          </div>
          <button
            onClick={() => upsertMut.mutate()}
            disabled={!itemId || !minQty || !reorderQty || upsertMut.isPending}
            className="mt-3 rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
          >
            Save
          </button>
        </div>
      )}

      <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200">
            <tr>
              <th className="text-left px-3 py-2">Item</th>
              <th className="text-right px-3 py-2">In Stock</th>
              <th className="text-right px-3 py-2">Min</th>
              <th className="text-right px-3 py-2">Reorder Qty</th>
              <th className="text-left px-3 py-2">Supplier</th>
              <th className="text-right px-3 py-2">Lead Time</th>
              <th className="text-center px-3 py-2">Enabled</th>
              <th className="w-12"></th>
            </tr>
          </thead>
          <tbody>
            {isLoading && (
              <tr>
                <td colSpan={8} className="text-center py-8 text-surface-400">
                  Loading...
                </td>
              </tr>
            )}
            {!isLoading && filteredRules.length === 0 && (
              <tr>
                <td colSpan={8} className="text-center py-8 text-surface-400">
                  No rules configured yet. Click "Add Rule" to create one.
                </td>
              </tr>
            )}
            {filteredRules.map((r) => (
              <tr key={r.inventory_item_id} className="border-b border-surface-100 last:border-0">
                <td className="px-3 py-2">
                  <div className="font-medium">{r.name}</div>
                  <div className="text-xs text-surface-500">{r.sku}</div>
                </td>
                <td
                  className={cn(
                    'text-right px-3 py-2 font-semibold',
                    r.in_stock <= r.min_qty && 'text-red-600',
                  )}
                >
                  {r.in_stock}
                </td>
                <td className="text-right px-3 py-2">{r.min_qty}</td>
                <td className="text-right px-3 py-2">{r.reorder_qty}</td>
                <td className="px-3 py-2">{r.supplier_name || '—'}</td>
                <td className="text-right px-3 py-2">{r.lead_time_days ? `${r.lead_time_days}d` : '—'}</td>
                <td className="text-center px-3 py-2">
                  {r.is_enabled ? (
                    <span className="px-2 py-0.5 rounded-full bg-green-100 text-green-700 text-xs">
                      Enabled
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 rounded-full bg-surface-100 text-surface-500 text-xs">
                      Off
                    </span>
                  )}
                </td>
                <td className="px-2 py-2">
                  <button
                    onClick={async () => {
                      const ok = await confirm(`Remove rule for ${r.name}?`, {
                        title: 'Remove auto-reorder rule',
                        confirmLabel: 'Remove',
                        danger: true,
                      });
                      if (ok) deleteMut.mutate(r.inventory_item_id);
                    }}
                    className="text-red-500 hover:text-red-700 disabled:opacity-40"
                    disabled={deleteMut.isPending && deleteMut.variables === r.inventory_item_id}
                    aria-label={`Remove auto-reorder rule for ${r.name}`}
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
