import { useEffect, useMemo, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, ArrowLeft, Save, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { inventoryApi, settingsApi } from '@/api/endpoints';
import type { TaxClassRecord } from '@/api/endpoints';
import { formatApiError } from '@/utils/apiError';
import { formatCurrencySymbol } from '@/utils/format';

// WEB-FL-023 (Fixer-C9 2026-04-25): replace `any[]` / `any` soup on tax-class
// API result, mutation arg, mutation success res, and onError handler. Tax
// classes only need {id, name, rate} for the <option>; mutation arg accepts
// the form shape after coerce-to-numbers; success returns the created item id.
type TaxClassOption = Pick<TaxClassRecord, 'id' | 'name' | 'rate' | 'is_default'>;
type TaxDefaultConfig = Partial<Record<'tax_default_parts' | 'tax_default_services' | 'tax_default_accessories', string>>;
type InventoryCreatePayload = Omit<typeof initialForm, 'cost_price' | 'retail_price' | 'in_stock' | 'reorder_level' | 'stock_warning' | 'tax_class_id' | 'tax_inclusive' | 'is_serialized' | 'item_type'> & {
  item_type: 'product' | 'part' | 'service';
  cost_price: number;
  retail_price: number;
  in_stock: number;
  reorder_level: number;
  stock_warning: number;
  tax_class_id: number | undefined;
  tax_inclusive: boolean;
  is_serialized: boolean;
};
type InventoryCreateResponse = { data: { data: { id: number } } };

const initialForm = {
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
};

function findTaxClassFromConfigValue(value: string | undefined, taxClasses: TaxClassOption[]): TaxClassOption | undefined {
  const trimmed = value?.trim();
  if (!trimmed || !/^\d+$/.test(trimmed)) return undefined;
  const id = Number(trimmed);
  return taxClasses.find((tc) => tc.id === id);
}

export function InventoryCreatePage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const currencySymbol = formatCurrencySymbol();

  const [form, setForm] = useState<typeof initialForm>(initialForm);
  const [taxClassTouched, setTaxClassTouched] = useState(false);

  const taxClassesQuery = useQuery({
    queryKey: ['settings', 'tax-classes'],
    queryFn: () => settingsApi.getTaxClasses(),
  });

  const configQuery = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: () => settingsApi.getConfig(),
  });

  const taxClasses = useMemo<TaxClassOption[]>(
    () => taxClassesQuery.data?.data.data ?? [],
    [taxClassesQuery.data],
  );
  const taxDefaults = (configQuery.data?.data.data ?? {}) as TaxDefaultConfig;

  const defaultTaxClass = useMemo(() => {
    const configuredDefaults = form.item_type === 'part'
      ? [taxDefaults.tax_default_parts, taxDefaults.tax_default_accessories]
      : [taxDefaults.tax_default_accessories, taxDefaults.tax_default_parts];
    for (const configuredDefault of configuredDefaults) {
      const match = findTaxClassFromConfigValue(configuredDefault, taxClasses);
      if (match) return match;
    }
    return taxClasses.find((tc) => Number(tc.is_default) === 1)
      ?? (taxClasses.length === 1 ? taxClasses[0] : undefined);
  }, [form.item_type, taxClasses, taxDefaults.tax_default_accessories, taxDefaults.tax_default_parts]);

  useEffect(() => {
    if (taxClassTouched || !defaultTaxClass) return;
    const defaultId = String(defaultTaxClass.id);
    setForm((current) => (
      current.tax_class_id === defaultId
        ? current
        : { ...current, tax_class_id: defaultId }
    ));
  }, [defaultTaxClass, taxClassTouched]);

  const hasStoredTaxDefaults = Boolean(
    taxDefaults.tax_default_parts ||
    taxDefaults.tax_default_services ||
    taxDefaults.tax_default_accessories,
  );
  const taxSelectPlaceholder = taxClassesQuery.isLoading
    ? 'Loading tax classes...'
    : taxClassesQuery.isError
      ? 'Tax classes unavailable'
      : 'No tax classes available';

  const mutation = useMutation({
    mutationFn: (data: InventoryCreatePayload) => inventoryApi.create(data),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      toast.success('Item created');
      const id = (res as unknown as InventoryCreateResponse).data.data.id;
      navigate(`/inventory/${id}`);
    },
    onError: (e: unknown) => toast.error(formatApiError(e)),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return toast.error('Name is required');
    const parsedRetailPrice = parseFloat(form.retail_price);
    if (!form.retail_price || isNaN(parsedRetailPrice)) return toast.error('Retail price is required');
    if (parsedRetailPrice <= 0) {
      const confirmed = window.confirm(
        'Retail price is $0.00. Is this intentional (e.g. gift or promotional item)?'
      );
      if (!confirmed) return;
    }
    mutation.mutate({
      ...form,
      item_type: form.item_type as 'product' | 'part' | 'service',
      cost_price: parseFloat(form.cost_price) || 0,
      retail_price: parseFloat(form.retail_price) || 0,
      in_stock: parseInt(form.in_stock) || 0,
      reorder_level: parseInt(form.reorder_level) || 0,
      stock_warning: parseInt(form.stock_warning) || 5,
      tax_class_id: form.tax_class_id ? parseInt(form.tax_class_id) : undefined,
      tax_inclusive: form.tax_inclusive,
      is_serialized: form.is_serialized,
    });
  };

  // WEB-FL-023: typed setter — `K extends keyof typeof initialForm` keeps the
  // value compatible with each individual field rather than `any`.
  const set = <K extends keyof typeof initialForm>(field: K, value: typeof initialForm[K]) =>
    setForm((f) => ({ ...f, [field]: value }));

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
                    {/* CROSS3: "service" option removed — services live in the
                        `repair_services` table, not inventory_items. */}
                    <select value={form.item_type} onChange={(e) => set('item_type', e.target.value)} className="input w-full">
                      <option value="product">Product</option>
                      <option value="part">Part</option>
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
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">{currencySymbol}</span>
                    <input type="number" step="0.01" min="0" value={form.cost_price} onChange={(e) => set('cost_price', e.target.value)} className="input w-full pl-12" placeholder="0.00" />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Retail Price <span className="text-red-500">*</span></label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">{currencySymbol}</span>
                    <input type="number" step="0.01" min="0" required value={form.retail_price} onChange={(e) => set('retail_price', e.target.value)} className="input w-full pl-12" placeholder="0.00" />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Tax Class</label>
                  <select
                    value={form.tax_class_id}
                    onChange={(e) => {
                      setTaxClassTouched(true);
                      set('tax_class_id', e.target.value);
                    }}
                    disabled={taxClasses.length === 0}
                    className="input w-full"
                  >
                    {taxClasses.length === 0 ? (
                      <option value="">{taxSelectPlaceholder}</option>
                    ) : (
                      <option value="">No Tax</option>
                    )}
                    {taxClasses.map((tc) => <option key={tc.id} value={tc.id}>{tc.name} ({tc.rate}%)</option>)}
                  </select>
                  {/* WEB-UIUX-862: the setup wizard's Tax step writes default
                      rates to `store_config.tax_default_parts/_services` but
                      does NOT seed the `tax_classes` table — so this dropdown
                      shows only "No Tax" on a fresh shop and the owner picks
                      that silently. Flag the empty state + link to Settings
                      so they create a Tax Class before booking the first
                      taxable line. */}
                  {taxClassesQuery.isError ? (
                    <div className="mt-2 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800 dark:border-amber-900/60 dark:bg-amber-950/30 dark:text-amber-200" role="alert">
                      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                      <span>Tax classes could not be loaded. Creating now will save this item without tax unless you retry.</span>
                    </div>
                  ) : !taxClassesQuery.isLoading && taxClasses.length === 0 ? (
                    <div className="mt-2 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800 dark:border-amber-900/60 dark:bg-amber-950/30 dark:text-amber-200" role="alert">
                      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                      <span>
                        No tax classes are configured, so this item will be created with no tax.
                        {hasStoredTaxDefaults ? ' Setup saved tax defaults separately, but inventory needs a tax class row before it can apply them.' : ' '}
                        {' '}
                        <Link to="/settings/tax" className="font-medium underline underline-offset-2 hover:text-amber-900 dark:hover:text-amber-100">Add a tax class</Link>.
                      </span>
                    </div>
                  ) : null}
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
              <button type="submit" disabled={mutation.isPending} className="w-full inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-on-primary rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none mb-3">
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
