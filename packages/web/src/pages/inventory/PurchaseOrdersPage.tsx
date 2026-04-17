import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Package, ChevronLeft, ChevronRight, Loader2, Check, Clock, Truck, AlertCircle } from 'lucide-react';
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

export function PurchaseOrdersPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [showCreate, setShowCreate] = useState(false);
  const [newPo, setNewPo] = useState({ supplier: '', notes: '', items: [{ name: '', quantity: 1, unit_cost: 0 }] });

  const { data, isLoading } = useQuery({
    queryKey: ['purchase-orders', page],
    queryFn: () => inventoryApi.listPurchaseOrders({ page, pagesize: 25 }),
  });

  const orders = data?.data?.data?.orders || data?.data?.data?.purchase_orders || [];
  const pagination = data?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1 };

  const createMut = useMutation({
    mutationFn: (d: any) => inventoryApi.createPurchaseOrder(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('Purchase order created');
      setShowCreate(false);
      setNewPo({ supplier: '', notes: '', items: [{ name: '', quantity: 1, unit_cost: 0 }] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to create PO'),
  });

  const addItem = () => setNewPo({ ...newPo, items: [...newPo.items, { name: '', quantity: 1, unit_cost: 0 }] });
  const removeItem = (i: number) => setNewPo({ ...newPo, items: newPo.items.filter((_, idx) => idx !== i) });
  const updateItem = (i: number, field: string, value: any) => {
    const items = [...newPo.items];
    items[i] = { ...items[i], [field]: value };
    setNewPo({ ...newPo, items });
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Purchase Orders</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">Manage supplier orders</p>
        </div>
        <button onClick={() => setShowCreate(!showCreate)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 transition-colors">
          <Plus className="h-4 w-4" /> New Purchase Order
        </button>
      </div>

      {/* Create form */}
      {showCreate && (
        <div className="card p-5 mb-6">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">New Purchase Order</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
            <input value={newPo.supplier} onChange={(e) => setNewPo({ ...newPo, supplier: e.target.value })}
              placeholder="Supplier name" className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            <input value={newPo.notes} onChange={(e) => setNewPo({ ...newPo, notes: e.target.value })}
              placeholder="Notes (optional)" className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
          </div>
          <p className="text-xs font-medium text-surface-500 mb-2">Items</p>
          <div className="space-y-2 mb-3">
            {newPo.items.map((item, i) => (
              <div key={i} className="flex gap-2 items-center">
                <input value={item.name} onChange={(e) => updateItem(i, 'name', e.target.value)}
                  placeholder="Item name / SKU" className="flex-1 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
                <input type="number" min="1" value={item.quantity} onChange={(e) => updateItem(i, 'quantity', parseInt(e.target.value) || 1)}
                  className="w-20 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" placeholder="Qty" />
                <input type="number" step="0.01" min="0" value={item.unit_cost || ''} onChange={(e) => updateItem(i, 'unit_cost', parseFloat(e.target.value) || 0)}
                  className="w-28 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" placeholder="Unit cost" />
                {newPo.items.length > 1 && (
                  <button onClick={() => removeItem(i)} className="text-red-400 hover:text-red-600 text-xs">Remove</button>
                )}
              </div>
            ))}
          </div>
          <div className="flex gap-2">
            <button onClick={addItem} className="text-xs text-primary-600 hover:underline">+ Add Item</button>
            <div className="ml-auto flex gap-2">
              <button onClick={() => setShowCreate(false)} className="px-3 py-1.5 text-sm text-surface-500">Cancel</button>
              <button onClick={() => createMut.mutate(newPo)} disabled={!newPo.supplier || newPo.items.every(i => !i.name)}
                className="px-4 py-1.5 text-sm bg-primary-600 text-white rounded-lg hover:bg-primary-700 disabled:opacity-50">
                Create PO
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
              <tr><td colSpan={6} className="text-center py-12"><Loader2 className="h-6 w-6 animate-spin text-surface-400 mx-auto" /></td></tr>
            ) : orders.length === 0 ? (
              <tr><td colSpan={6} className="text-center py-12">
                <Package className="h-12 w-12 text-surface-300 dark:text-surface-600 mx-auto mb-3" />
                <p className="text-sm font-medium text-surface-500 dark:text-surface-400">No purchase orders yet</p>
                <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">Create a purchase order to track parts and supplies from your suppliers.</p>
              </td></tr>
            ) : (
              orders.map((po: any) => (
                <tr key={po.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
                  <td className="px-4 py-3 font-medium text-primary-600 dark:text-primary-400">{po.order_id || `PO-${po.id}`}</td>
                  <td className="px-4 py-3 text-surface-700 dark:text-surface-300">{po.supplier || '—'}</td>
                  <td className="px-4 py-3">
                    <span className={cn('inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize', STATUS_COLORS[po.status] || STATUS_COLORS.draft)}>
                      {po.status || 'draft'}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-surface-500">{po.item_count || (po.items?.length ?? 0)} items</td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(po.total || 0)}</td>
                  <td className="px-4 py-3 text-surface-400 text-xs">{po.created_at ? new Date(po.created_at).toLocaleDateString() : '—'}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>

        {pagination.total_pages > 1 && (
          <div className="flex items-center justify-between border-t border-surface-200 dark:border-surface-700 px-4 py-3">
            <p className="text-sm text-surface-500">Page {page} of {pagination.total_pages}</p>
            <div className="flex gap-1">
              <button aria-label="Previous page" disabled={page <= 1} onClick={() => setPage(page - 1)} className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 disabled:opacity-50"><ChevronLeft className="h-4 w-4" /></button>
              <button aria-label="Next page" disabled={page >= pagination.total_pages} onClick={() => setPage(page + 1)} className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 disabled:opacity-50"><ChevronRight className="h-4 w-4" /></button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
