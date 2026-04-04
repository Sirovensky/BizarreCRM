import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Save, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { inventoryApi, settingsApi } from '@/api/endpoints';

export function InventoryCreatePage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [form, setForm] = useState({
    name: '',
    item_type: 'product',
    sku: '',
    upc: '',
    category: '',
    manufacturer: '',
    device_type: '',
    description: '',
    cost_price: '',
    retail_price: '',
    in_stock: '0',
    reorder_level: '0',
    stock_warning: '5',
    tax_class_id: '',
    tax_inclusive: false,
    is_serialized: false,
  });

  const { data: taxData } = useQuery({
    queryKey: ['tax-classes'],
    queryFn: () => settingsApi.getTaxClasses(),
  });
  const taxClasses: any[] = taxData?.data?.data?.tax_classes || [];

  const mutation = useMutation({
    mutationFn: (data: any) => inventoryApi.create(data),
    onSuccess: (res: any) => {
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      toast.success('Item created');
      navigate(`/inventory/${res.data.data.id}`);
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to create item'),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return toast.error('Name is required');
    if (!form.retail_price) return toast.error('Retail price is required');
    mutation.mutate({
      ...form,
      cost_price: parseFloat(form.cost_price) || 0,
      retail_price: parseFloat(form.retail_price) || 0,
      in_stock: parseInt(form.in_stock) || 0,
      reorder_level: parseInt(form.reorder_level) || 0,
      stock_warning: parseInt(form.stock_warning) || 5,
      tax_class_id: form.tax_class_id ? parseInt(form.tax_class_id) : null,
      tax_inclusive: form.tax_inclusive ? 1 : 0,
      is_serialized: form.is_serialized ? 1 : 0,
    });
  };

  const set = (field: string, value: any) => setForm((f) => ({ ...f, [field]: value }));

  return (
    <div>
      <div className="mb-6">
        <Link to="/inventory" className="inline-flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200 mb-3 transition-colors">
          <ArrowLeft className="h-4 w-4" /> Back to Inventory
        </Link>
        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">New Inventory Item</h1>
      </div>

      <form onSubmit={handleSubmit}>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-6">
            {/* Basic Info */}
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Basic Info</h2>
              <div className="space-y-4">
                <div className="grid grid-cols-3 gap-4">
                  <div className="col-span-2">
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Name <span className="text-red-500">*</span></label>
                    <input value={form.name} onChange={(e) => set('name', e.target.value)} required className="input w-full" placeholder="e.g. iPhone 14 Screen" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Type <span className="text-red-500">*</span></label>
                    <select value={form.item_type} onChange={(e) => set('item_type', e.target.value)} className="input w-full">
                      <option value="product">Product</option>
                      <option value="part">Part</option>
                      <option value="service">Service</option>
                    </select>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">SKU</label>
                    <input value={form.sku} onChange={(e) => set('sku', e.target.value)} className="input w-full" placeholder="e.g. IPH14-SCR-BLK" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">UPC / Barcode</label>
                    <input value={form.upc} onChange={(e) => set('upc', e.target.value)} className="input w-full" placeholder="Scan or enter barcode" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Category</label>
                    <input value={form.category} onChange={(e) => set('category', e.target.value)} className="input w-full" placeholder="e.g. Screens, Batteries" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Manufacturer</label>
                    <input value={form.manufacturer} onChange={(e) => set('manufacturer', e.target.value)} className="input w-full" placeholder="e.g. Apple" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Device Type</label>
                    <input value={form.device_type} onChange={(e) => set('device_type', e.target.value)} className="input w-full" placeholder="e.g. Phone, Laptop" />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Description</label>
                  <textarea value={form.description} onChange={(e) => set('description', e.target.value)} rows={2} className="input w-full" placeholder="Optional description..." />
                </div>
              </div>
            </div>

            {/* Pricing */}
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Pricing</h2>
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Cost Price</label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">$</span>
                    <input type="number" step="0.01" min="0" value={form.cost_price} onChange={(e) => set('cost_price', e.target.value)} className="input w-full pl-6" placeholder="0.00" />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Retail Price <span className="text-red-500">*</span></label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">$</span>
                    <input type="number" step="0.01" min="0" required value={form.retail_price} onChange={(e) => set('retail_price', e.target.value)} className="input w-full pl-6" placeholder="0.00" />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Tax Class</label>
                  <select value={form.tax_class_id} onChange={(e) => set('tax_class_id', e.target.value)} className="input w-full">
                    <option value="">No Tax</option>
                    {taxClasses.map((tc: any) => <option key={tc.id} value={tc.id}>{tc.name} ({tc.rate}%)</option>)}
                  </select>
                </div>
              </div>
              <div className="mt-3 flex items-center gap-2">
                <input type="checkbox" id="tax_inclusive" checked={form.tax_inclusive} onChange={(e) => set('tax_inclusive', e.target.checked)} className="rounded" />
                <label htmlFor="tax_inclusive" className="text-sm text-surface-600 dark:text-surface-300">Price is tax-inclusive</label>
              </div>
            </div>

            {/* Stock (not for services) */}
            {form.item_type !== 'service' && (
              <div className="card p-6">
                <h2 className="text-sm font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider mb-4">Stock</h2>
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Initial Stock</label>
                    <input type="number" min="0" value={form.in_stock} onChange={(e) => set('in_stock', e.target.value)} className="input w-full" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Reorder Level</label>
                    <input type="number" min="0" value={form.reorder_level} onChange={(e) => set('reorder_level', e.target.value)} className="input w-full" />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Stock Warning</label>
                    <input type="number" min="0" value={form.stock_warning} onChange={(e) => set('stock_warning', e.target.value)} className="input w-full" />
                  </div>
                </div>
                <div className="mt-3 flex items-center gap-2">
                  <input type="checkbox" id="is_serialized" checked={form.is_serialized} onChange={(e) => set('is_serialized', e.target.checked)} className="rounded" />
                  <label htmlFor="is_serialized" className="text-sm text-surface-600 dark:text-surface-300">Track serial numbers</label>
                </div>
              </div>
            )}
          </div>

          {/* Sidebar */}
          <div>
            <div className="card p-6 sticky top-6">
              <button type="submit" disabled={mutation.isPending} className="w-full inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium transition-colors disabled:opacity-50 mb-3">
                {mutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                Create Item
              </button>
              <Link to="/inventory" className="block w-full text-center px-4 py-2.5 text-sm font-medium text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 rounded-lg transition-colors">
                Cancel
              </Link>
            </div>
          </div>
        </div>
      </form>
    </div>
  );
}
