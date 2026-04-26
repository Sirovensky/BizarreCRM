import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Package, ChevronLeft, ChevronRight, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { inventoryApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';

const STATUS_COLORS: Record<string, string> = {
  draft: 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400',
  pending: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  ordered: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  partial: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
  received: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  cancelled: 'bg-red-100 text-red-500 dark:bg-red-900/30 dark:text-red-400',
};

interface PoLineItem {
  inventory_item_id: number | '';
  quantity_ordered: number;
  cost_price: number;
}

interface NewPoForm {
  supplier_id: number | '';
  notes: string;
  items: PoLineItem[];
}

const EMPTY_ITEM: PoLineItem = { inventory_item_id: '', quantity_ordered: 1, cost_price: 0 };

export function PurchaseOrdersPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [showCreate, setShowCreate] = useState(false);
  const [newPo, setNewPo] = useState<NewPoForm>({ supplier_id: '', notes: '', items: [{ ...EMPTY_ITEM }] });

  const { data, isLoading } = useQuery({
    queryKey: ['purchase-orders', page],
    queryFn: () => inventoryApi.listPurchaseOrders({ page, pagesize: 25 }),
    staleTime: 30_000,
  });

  const { data: suppliersData } = useQuery({
    queryKey: ['suppliers'],
    queryFn: () => inventoryApi.listSuppliers(),
    enabled: showCreate,
    staleTime: 30_000,
  });
  const suppliers: Array<{ id: number; name: string }> = suppliersData?.data?.data || [];

  const { data: inventoryData } = useQuery({
    queryKey: ['inventory-items-select'],
    queryFn: () => inventoryApi.list({ pagesize: 250 }),
    enabled: showCreate,
    staleTime: 30_000,
  });
  const inventoryItems: Array<{ id: number; name: string; sku: string; cost_price: number }> =
    inventoryData?.data?.data?.items || [];

  const orders = data?.data?.data?.orders || data?.data?.data?.purchase_orders || [];
  const pagination = data?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1 };

  const createMut = useMutation({
    mutationFn: () => {
      if (!newPo.supplier_id) throw new Error('Supplier is required');
      const validItems = newPo.items.filter(
        (i): i is { inventory_item_id: number; quantity_ordered: number; cost_price: number } =>
          typeof i.inventory_item_id === 'number' && i.inventory_item_id > 0 && i.quantity_ordered > 0,
      );
      return inventoryApi.createPurchaseOrder({
        supplier_id: newPo.supplier_id as number,
        notes: newPo.notes || undefined,
        items: validItems,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('Purchase order created');
      setShowCreate(false);
      setNewPo({ supplier_id: '', notes: '', items: [{ ...EMPTY_ITEM }] });
    },
    onError: (e: unknown) => {
      const msg =
        e instanceof Error
          ? e.message
          : (e as { response?: { data?: { message?: string } } })?.response?.data?.message ||
            'Failed to create PO';
      toast.error(msg);
    },
  });

  const addItem = () => setNewPo({ ...newPo, items: [...newPo.items, { ...EMPTY_ITEM }] });
  const removeItem = (i: number) => setNewPo({ ...newPo, items: newPo.items.filter((_, idx) => idx !== i) });
  const updateItem = (i: number, patch: Partial<PoLineItem>) => {
    const items = newPo.items.map((item, idx) => (idx === i ? { ...item, ...patch } : item));
    setNewPo({ ...newPo, items });
  };

  const canSubmit =
    !!newPo.supplier_id &&
    newPo.items.some(
      (i) => typeof i.inventory_item_id === 'number' && i.inventory_item_id > 0,
    );

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Purchase Orders</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">Manage supplier orders</p>
        </div>
        <button
          onClick={() => setShowCreate(!showCreate)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 hover:bg-primary-700 transition-colors"
        >
          <Plus className="h-4 w-4" /> New Purchase Order
        </button>
      </div>

      {/* Create form */}
      {showCreate && (
        <div className="card p-5 mb-6">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">New Purchase Order</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
            <div>
              <label className="block text-xs font-medium text-surface-500 mb-1">Supplier <span className="text-red-500">*</span></label>
              <select
                value={newPo.supplier_id}
                onChange={(e) => setNewPo({ ...newPo, supplier_id: e.target.value ? Number(e.target.value) : '' })}
                className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
              >
                <option value="">Select supplier…</option>
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-500 mb-1">Notes</label>
              <input
                value={newPo.notes}
                onChange={(e) => setNewPo({ ...newPo, notes: e.target.value })}
                placeholder="Notes (optional)"
                className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
              />
            </div>
          </div>

          <p className="text-xs font-medium text-surface-500 mb-2">Items</p>
          <div className="space-y-2 mb-3">
            {newPo.items.map((item, i) => (
              <div key={i} className="flex gap-2 items-center">
                <select
                  value={item.inventory_item_id}
                  onChange={(e) => {
                    const invId = e.target.value ? Number(e.target.value) : ('' as const);
                    const found = typeof invId === 'number'
                      ? inventoryItems.find((it) => it.id === invId)
                      : undefined;
                    updateItem(i, {
                      inventory_item_id: invId,
                      cost_price: found ? found.cost_price : item.cost_price,
                    });
                  }}
                  className="flex-1 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                >
                  <option value="">Select inventory item…</option>
                  {inventoryItems.map((it) => (
                    <option key={it.id} value={it.id}>
                      {it.name}{it.sku ? ` (${it.sku})` : ''}
                    </option>
                  ))}
                </select>
                <input
                  type="number"
                  min="1"
                  value={item.quantity_ordered}
                  onChange={(e) => updateItem(i, { quantity_ordered: parseInt(e.target.value) || 1 })}
                  className="w-20 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                  placeholder="Qty"
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={item.cost_price || ''}
                  onChange={(e) => updateItem(i, { cost_price: parseFloat(e.target.value) || 0 })}
                  className="w-28 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                  placeholder="Unit cost"
                />
                {newPo.items.length > 1 && (
                  <button onClick={() => removeItem(i)} className="text-red-400 hover:text-red-600 text-xs">
                    Remove
                  </button>
                )}
              </div>
            ))}
          </div>

          <div className="flex gap-2">
            <button onClick={addItem} className="text-xs text-primary-600 hover:underline">
              + Add Item
            </button>
            <div className="ml-auto flex gap-2">
              <button onClick={() => setShowCreate(false)} className="px-3 py-1.5 text-sm text-surface-500">
                Cancel
              </button>
              <button
                onClick={() => createMut.mutate()}
                disabled={!canSubmit || createMut.isPending}
                className="px-4 py-1.5 text-sm bg-primary-600 text-primary-950 rounded-lg hover:bg-primary-700 disabled:opacity-50"
              >
                {createMut.isPending ? <Loader2 className="h-4 w-4 animate-spin inline" /> : 'Create PO'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* List */}
      <div className="card overflow-x-auto">
        <table className="w-full text-sm text-left">
          <thead className="bg-surface-50 dark:bg-surface-800/50">
            <tr className="border-b border-surface-200 dark:border-surface-700">
              <th className="px-4 py-3 font-medium text-surface-500">PO #</th>
              <th className="px-4 py-3 font-medium text-surface-500">Supplier</th>
              <th className="px-4 py-3 font-medium text-surface-500">Status</th>
              <th className="px-4 py-3 font-medium text-surface-500">Items</th>
              <th className="px-4 py-3 font-medium text-surface-500 text-right">Total</th>
              <th className="px-4 py-3 font-medium text-surface-500">Created</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
            {isLoading ? (
              <tr>
                <td colSpan={6} className="text-center py-12">
                  <Loader2 className="h-6 w-6 animate-spin text-surface-400 mx-auto" />
                </td>
              </tr>
            ) : orders.length === 0 ? (
              <tr>
                <td colSpan={6} className="text-center py-12">
                  <Package className="h-12 w-12 text-surface-300 dark:text-surface-600 mx-auto mb-3" />
                  <p className="text-sm font-medium text-surface-500 dark:text-surface-400">No purchase orders yet</p>
                  <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">
                    Create a purchase order to track parts and supplies from your suppliers.
                  </p>
                </td>
              </tr>
            ) : (
              orders.map((po: Record<string, unknown>) => (
                <tr key={po.id as number} className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
                  <td className="px-4 py-3 font-medium text-primary-600 dark:text-primary-400">
                    {(po.order_id as string) || `PO-${po.id}`}
                  </td>
                  <td className="px-4 py-3 text-surface-700 dark:text-surface-300">
                    {(po.supplier_name as string) || '—'}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={cn(
                        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize',
                        STATUS_COLORS[(po.status as string)] || STATUS_COLORS.draft,
                      )}
                    >
                      {(po.status as string) || 'draft'}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-surface-500">
                    {(po.item_count as number) || 0} items
                  </td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">
                    {formatCurrency((po.total as number) || 0)}
                  </td>
                  <td className="px-4 py-3 text-surface-400 text-xs">
                    {po.created_at ? new Date(po.created_at as string).toLocaleDateString() : '—'}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>

        {(pagination.total_pages as number) > 1 && (
          <div className="flex items-center justify-between border-t border-surface-200 dark:border-surface-700 px-4 py-3">
            <p className="text-sm text-surface-500">
              Page {page} of {pagination.total_pages}
            </p>
            <div className="flex gap-1">
              <button
                aria-label="Previous page"
                disabled={page <= 1}
                onClick={() => setPage(page - 1)}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 hover:bg-surface-100 disabled:opacity-50 min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              <button
                aria-label="Next page"
                disabled={page >= (pagination.total_pages as number)}
                onClick={() => setPage(page + 1)}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 hover:bg-surface-100 disabled:opacity-50 min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
