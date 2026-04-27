import { useState, useEffect } from 'react';
import { useParams, useNavigate, Link, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Package, Pencil, Save, X, Plus, Minus, Loader2, TrendingUp, TrendingDown, Printer, History, MapPin } from 'lucide-react';
import toast from 'react-hot-toast';
import { inventoryApi, settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { formatCurrency } from '@/utils/format';

// Covers every field the detail form reads or writes. Loose `number | string`
// types on numeric columns mirror the edit-field state shape (inputs return
// strings before `parseFloat` / `parseInt` finalise them on blur).
interface InventoryFormItem {
  id?: number;
  item_type?: string;
  name?: string;
  sku?: string | null;
  upc?: string | null;
  description?: string | null;
  retail_price?: number | string | null;
  cost_price?: number | string | null;
  wholesale_price?: number | string | null;
  tax_class_id?: number | string | null;
  quantity?: number | string | null;
  reorder_level?: number | string | null;
  [key: string]: unknown;
}

export function InventoryDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const itemId = Number(id);
  const isValidId = id != null && !isNaN(itemId) && itemId > 0;
  const [searchParams] = useSearchParams();
  const isEditing = searchParams.get('edit') === 'true';
  const [editMode, setEditMode] = useState(isEditing);
  const [adjustQty, setAdjustQty] = useState('');
  const [adjustType, setAdjustType] = useState('adjustment');
  const [adjustNotes, setAdjustNotes] = useState('');
  const [showAdjust, setShowAdjust] = useState(false);
  const [form, setForm] = useState<InventoryFormItem | null>(null);
  const [barcodeUrl, setBarcodeUrl] = useState<string | null>(null);
  const [barcodeLoading, setBarcodeLoading] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['inventory', id],
    queryFn: () => inventoryApi.get(itemId),
    enabled: isValidId,
  });

  useEffect(() => {
    // Server returns { success: true, data: { item, movements, group_prices } }.
    // Axios wraps once more, so the actual item lives at data.data.data.item.
    const loadedItem = data?.data?.data?.item;
    if (loadedItem && !form) {
      setForm(loadedItem);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]); // intentional: only seed form on first load (guarded by !form)

  const { data: taxData } = useQuery({
    queryKey: ['tax-classes'],
    queryFn: () => settingsApi.getTaxClasses(),
  });

  const item: any = data?.data?.data?.item;
  const movements: any[] = data?.data?.data?.movements || [];
  const taxClasses: any[] = taxData?.data?.data || [];

  // WEB-S6-009: Price history (admin/manager only)
  const { data: priceHistoryData } = useQuery({
    queryKey: ['inventory-price-history', id],
    queryFn: () => inventoryApi.priceHistory(itemId),
    enabled: isValidId,
    staleTime: 60_000,
  });
  const priceHistory: any[] = priceHistoryData?.data?.data || [];

  // WEB-S6-010: Multi-location stock
  const { data: locationStockData } = useQuery({
    queryKey: ['inventory-location-stock', id],
    queryFn: () => inventoryApi.locationStock(itemId),
    enabled: isValidId,
    staleTime: 60_000,
  });
  const locationStock: any = locationStockData?.data?.data;

  const updateMutation = useMutation({
    mutationFn: (d: InventoryFormItem) => inventoryApi.update(itemId, d as Parameters<typeof inventoryApi.update>[1]),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['inventory', id] });
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      toast.success('Item updated');
      setEditMode(false);
    },
    onError: () => toast.error('Failed to update item'),
  });

  const adjustMutation = useMutation({
    mutationFn: (d: any) => inventoryApi.adjustStock(itemId, d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['inventory', id] });
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      toast.success('Stock adjusted');
      setShowAdjust(false);
      setAdjustQty('');
      setAdjustNotes('');
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to adjust stock'),
  });

  if (isLoading && isValidId) return (
    <div className="flex items-center justify-center h-64"><Loader2 className="h-8 w-8 animate-spin text-surface-400" /></div>
  );
  if (!isValidId) return <div className="text-center py-20 text-surface-400">Invalid Inventory Item ID</div>;
  if (!item) return <div className="text-center py-20 text-surface-400">Item not found</div>;

  const f = form || item;

  const handleSave = () => {
    if (!form) return;
    updateMutation.mutate(form);
  };

  const handleAdjust = () => {
    const qty = parseInt(adjustQty);
    if (!adjustQty || isNaN(qty)) return toast.error('Enter a valid quantity');
    adjustMutation.mutate({ quantity: qty, type: adjustType, notes: adjustNotes });
  };

  const handlePrintBarcode = async () => {
    setBarcodeLoading(true);
    try {
      const res = await inventoryApi.getBarcode(itemId);
      const dataUrl = res.data.data.barcode_data_url;
      setBarcodeUrl(dataUrl);
      // Open print window — build DOM programmatically instead of
      // `document.write` with interpolation. A server-supplied sku/upc/name
      // containing `</title><script>…</script>` would otherwise execute in
      // the new window (classic XSS). Only the base64 data URL is set via
      // element properties, which browsers treat as a value, not HTML.
      const printWindow = window.open('', '_blank', 'width=400,height=300,noopener,noreferrer');
      if (printWindow) {
        const doc = printWindow.document;
        doc.open();
        doc.close();
        const titleText = `Barcode - ${item.sku || item.upc || item.name || ''}`;
        doc.title = titleText;
        const style = doc.createElement('style');
        style.textContent = 'body{display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;} img{max-width:100%;}';
        doc.head.appendChild(style);
        const img = doc.createElement('img');
        img.src = dataUrl;
        img.alt = 'Barcode';
        img.onload = () => printWindow.print();
        doc.body.appendChild(img);
      }
    } catch {
      toast.error('Failed to generate barcode. Item may not have a SKU or UPC.');
    } finally {
      setBarcodeLoading(false);
    }
  };

  const typeColor = item.item_type === 'product' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
    : item.item_type === 'part' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400'
    : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400';

  return (
    <div>
      <Breadcrumb items={[
        { label: 'Inventory', href: '/inventory' },
        { label: item.name || 'Item' },
      ]} />
      {/* Back + Header */}
      <div className="mb-6">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="h-12 w-12 rounded-xl bg-surface-100 dark:bg-surface-800 flex items-center justify-center">
              <Package className="h-6 w-6 text-surface-500" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">{item.name}</h1>
                <span className={cn('inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize', typeColor)}>{item.item_type}</span>
              </div>
              {item.sku && <p className="text-sm text-surface-500 font-mono">SKU: {item.sku}</p>}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {editMode ? (
              <>
                <button type="button" aria-label="Cancel edit" onClick={() => { setEditMode(false); setForm(item); }} className="px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                  <X className="h-4 w-4" />
                </button>
                <button type="button" onClick={handleSave} disabled={updateMutation.isPending} className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors disabled:opacity-50">
                  {updateMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                  Save
                </button>
              </>
            ) : (
              <>
                {(item.sku || item.upc) && (
                  <button type="button" onClick={handlePrintBarcode} disabled={barcodeLoading} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors disabled:opacity-50">
                    {barcodeLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Printer className="h-4 w-4" />}
                    Print Barcode
                  </button>
                )}
                {item.item_type !== 'service' && (
                  <button type="button" onClick={() => setShowAdjust(true)} className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                    Adjust Stock
                  </button>
                )}
                <button type="button" onClick={() => { setForm(item); setEditMode(true); }} className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors">
                  <Pencil className="h-4 w-4" /> Edit
                </button>
              </>
            )}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Info */}
        <div className="lg:col-span-2 space-y-6">
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Item Details</h2>
            <div className="grid grid-cols-2 gap-4">
              {[
                { label: 'Name', field: 'name', required: true },
                { label: 'SKU', field: 'sku' },
                { label: 'UPC / Barcode', field: 'upc' },
                { label: 'Category', field: 'category' },
                { label: 'Manufacturer', field: 'manufacturer' },
                { label: 'Device Type', field: 'device_type' },
                { label: 'Location', field: 'location' },
                { label: 'Shelf', field: 'shelf' },
                { label: 'Bin', field: 'bin' },
              ].map(({ label, field, required }) => (
                <div key={field}>
                  <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">{label}</label>
                  {editMode ? (
                    <input
                      value={f[field] || ''}
                      onChange={(e) => setForm({ ...f, [field]: e.target.value })}
                      required={required}
                      className="input w-full text-sm"
                    />
                  ) : (
                    <p className="text-sm text-surface-900 dark:text-surface-100">{item[field] || '—'}</p>
                  )}
                </div>
              ))}
              <div className="col-span-2">
                <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Description</label>
                {editMode ? (
                  <textarea value={f.description || ''} onChange={(e) => setForm({ ...f, description: e.target.value })} rows={2} className="input w-full text-sm" />
                ) : (
                  <p className="text-sm text-surface-900 dark:text-surface-100">{item.description || '—'}</p>
                )}
              </div>
            </div>
          </div>

          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Pricing</h2>
            <div className="grid grid-cols-3 gap-4">
              {[
                { label: 'Cost Price', field: 'cost_price', prefix: '$' },
                { label: 'Retail Price', field: 'retail_price', prefix: '$' },
              ].map(({ label, field, prefix }) => (
                <div key={field}>
                  <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">{label}</label>
                  {editMode ? (
                    <div className="relative">
                      <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400 text-sm">{prefix}</span>
                      <input type="number" step="0.01" min="0" value={f[field] || ''} onChange={(e) => setForm({ ...f, [field]: parseFloat(e.target.value) || 0 })} className="input w-full text-sm pl-6" />
                    </div>
                  ) : (
                    <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{prefix}{Number(item[field]).toFixed(2)}</p>
                  )}
                </div>
              ))}
              <div>
                <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Tax Class</label>
                {editMode ? (
                  <select value={f.tax_class_id || ''} onChange={(e) => setForm({ ...f, tax_class_id: e.target.value || null })} className="input w-full text-sm">
                    <option value="">No Tax</option>
                    {taxClasses.map((tc: any) => <option key={tc.id} value={tc.id}>{tc.name} ({tc.rate}%)</option>)}
                  </select>
                ) : (
                  <p className="text-sm text-surface-900 dark:text-surface-100">
                    {taxClasses.find((tc: any) => tc.id === item.tax_class_id)?.name || 'No Tax'}
                  </p>
                )}
              </div>
            </div>
          </div>

          {item.item_type !== 'service' && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Stock Settings</h2>
              <div className="grid grid-cols-3 gap-4">
                {[
                  { label: 'Reorder Level', field: 'reorder_level' },
                  { label: 'Stock Warning', field: 'stock_warning' },
                ].map(({ label, field }) => (
                  <div key={field}>
                    <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">{label}</label>
                    {editMode ? (
                      <input type="number" min="0" value={f[field] || 0} onChange={(e) => setForm({ ...f, [field]: parseInt(e.target.value) || 0 })} className="input w-full text-sm" />
                    ) : (
                      <p className="text-sm text-surface-900 dark:text-surface-100">{item[field]}</p>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Right Panel */}
        <div className="space-y-6">
          {item.item_type !== 'service' && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Stock Level</h2>
              <div className={cn(
                'text-4xl font-bold mb-1',
                item.in_stock === 0 ? 'text-red-600 dark:text-red-400' :
                item.in_stock <= (item.reorder_level || 0) ? 'text-amber-600 dark:text-amber-400' :
                'text-surface-900 dark:text-surface-100'
              )}>
                {item.in_stock}
              </div>
              <p className="text-sm text-surface-500">units in stock</p>
              {item.in_stock <= (item.reorder_level || 0) && (
                <div className="mt-3 px-3 py-2 rounded-lg bg-amber-50 dark:bg-amber-900/20 text-amber-700 dark:text-amber-400 text-xs font-medium">
                  Below reorder level ({item.reorder_level})
                </div>
              )}
            </div>
          )}

          {/* Stock Adjustment Modal */}
          {showAdjust && (
            <div className="card p-6 border-2 border-primary-200 dark:border-primary-800">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100 mb-4">Adjust Stock</h3>
              <div className="space-y-3">
                <div>
                  <label className="block text-xs font-medium text-surface-500 mb-1">Type</label>
                  <select value={adjustType} onChange={(e) => setAdjustType(e.target.value)} className="input w-full text-sm">
                    <option value="adjustment">Manual Adjustment</option>
                    <option value="purchase">Purchase / Received</option>
                    <option value="return">Customer Return</option>
                    <option value="defective">Defective / Write-off</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium text-surface-500 mb-1">Quantity (+ to add, - to remove)</label>
                  <input
                    type="number"
                    value={adjustQty}
                    onChange={(e) => setAdjustQty(e.target.value)}
                    placeholder="e.g. +5 or -2"
                    className="input w-full text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-surface-500 mb-1">Notes</label>
                  <input value={adjustNotes} onChange={(e) => setAdjustNotes(e.target.value)} className="input w-full text-sm" placeholder="Reason for adjustment..." />
                </div>
                <div className="flex gap-2 pt-1">
                  <button type="button" onClick={() => setShowAdjust(false)} className="flex-1 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">Cancel</button>
                  <button type="button" onClick={handleAdjust} disabled={adjustMutation.isPending} className="flex-1 px-3 py-2 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors disabled:opacity-50">
                    {adjustMutation.isPending ? 'Saving...' : 'Apply'}
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* Barcode Preview */}
          {barcodeUrl && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Barcode</h2>
              <div className="flex justify-center">
                <img src={barcodeUrl} alt="Barcode" loading="lazy" decoding="async" className="max-w-full" />
              </div>
            </div>
          )}

          {/* Stock Movements Log */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">
              Stock Movements {movements.length > 0 && <span className="text-surface-400 font-normal">({movements.length})</span>}
            </h2>
            {movements.length === 0 ? (
              <p className="text-xs text-surface-400 italic">No stock movements recorded</p>
            ) : (
              <div className="space-y-2 max-h-96 overflow-y-auto">
                {movements.map((m: any) => (
                  <div key={m.id} className="flex items-start gap-2 text-sm border-b border-surface-100 dark:border-surface-800 pb-2 last:border-0">
                    <span className={cn('mt-0.5 flex-shrink-0', m.quantity > 0 ? 'text-green-500' : 'text-red-500')}>
                      {m.quantity > 0 ? <TrendingUp className="h-4 w-4" /> : <TrendingDown className="h-4 w-4" />}
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-surface-700 dark:text-surface-300 capitalize">{m.type.replace(/_/g, ' ')}</span>
                        <span className={cn('font-mono font-bold', m.quantity > 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
                          {m.quantity > 0 ? '+' : ''}{m.quantity}
                        </span>
                      </div>
                      {m.notes && <div className="text-xs text-surface-500 dark:text-surface-400 truncate">{m.notes}</div>}
                      <div className="text-xs text-surface-400">
                        {m.user_name && <span>{m.user_name} · </span>}
                        {new Date(m.created_at).toLocaleString()}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* WEB-S6-009: Cost Price History — admin/manager only */}
          {priceHistory.length > 0 && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4 flex items-center gap-2">
                <History className="h-4 w-4" /> Cost Price History
              </h2>
              <div className="space-y-2 max-h-64 overflow-y-auto">
                {priceHistory.map((h: any) => (
                  <div key={h.id} className="flex items-center justify-between text-sm border-b border-surface-100 dark:border-surface-800 pb-2 last:border-0">
                    <div>
                      <span className="text-surface-500 text-xs">
                        {h.old_price != null ? formatCurrency(h.old_price) : '—'} → <strong>{formatCurrency(h.new_price)}</strong>
                      </span>
                      {h.changed_by_name && (
                        <span className="ml-2 text-xs text-surface-400">{h.changed_by_name}</span>
                      )}
                    </div>
                    <span className="text-xs text-surface-400">{new Date(h.created_at).toLocaleDateString()}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* WEB-S6-010: Multi-location stock */}
          {locationStock && locationStock.locations && locationStock.locations.length > 1 && (
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4 flex items-center gap-2">
                <MapPin className="h-4 w-4" /> Stock by Location
              </h2>
              <div className="space-y-2">
                {locationStock.locations.map((loc: any) => (
                  <div key={loc.id} className="flex items-center justify-between text-sm">
                    <div className="flex items-center gap-1.5">
                      <span className={cn(
                        'h-2 w-2 rounded-full flex-shrink-0',
                        loc.is_primary ? 'bg-primary-500' : 'bg-surface-300',
                      )} />
                      <span className="text-surface-700 dark:text-surface-300">{loc.location_name}</span>
                      {loc.is_default === 1 && (
                        <span className="text-xs text-surface-400">(default)</span>
                      )}
                    </div>
                    <span className={cn(
                      'font-mono font-semibold',
                      loc.is_primary ? 'text-surface-900 dark:text-surface-100' : 'text-surface-400',
                    )}>
                      {loc.in_stock}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
