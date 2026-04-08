import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Package, Plus, Minus, Search, AlertTriangle, Pencil, Trash2, Eye, ChevronLeft, ChevronRight, Loader2, Download, Upload, X, Check, Filter, EyeOff, Columns } from 'lucide-react';
import toast from 'react-hot-toast';
import { inventoryApi, preferencesApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';

const TABS = [
  { key: '', label: 'All' },
  { key: 'product', label: 'Products' },
  { key: 'part', label: 'Parts' },
  { key: 'service', label: 'Services' },
];

const ALL_COLUMNS = [
  { key: 'sku', label: 'SKU' },
  { key: 'name', label: 'Name' },
  { key: 'type', label: 'Type' },
  { key: 'category', label: 'Category' },
  { key: 'stock', label: 'In Stock' },
  { key: 'cost', label: 'Cost' },
  { key: 'price', label: 'Price' },
] as const;
type ColKey = (typeof ALL_COLUMNS)[number]['key'];

const DEFAULT_VISIBLE: ColKey[] = ['sku', 'name', 'type', 'category', 'stock', 'cost', 'price'];

export function InventoryListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  const tab = searchParams.get('type') || '';
  const page = Number(searchParams.get('page') || '1');
  const [savedPageSize, setSavedPageSize] = useState(() => {
    const stored = localStorage.getItem('inventory_pagesize');
    return stored ? Number(stored) : 25;
  });
  const pageSize = Number(searchParams.get('pagesize') || savedPageSize);
  const keyword = searchParams.get('keyword') || '';
  const [searchInput, setSearchInput] = useState(keyword);
  const searchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Advanced filters state
  const [showFilters, setShowFilters] = useState(false);
  const [manufacturer, setManufacturer] = useState(searchParams.get('manufacturer') || '');
  const [supplierId, setSupplierId] = useState(searchParams.get('supplier_id') || '');
  const [minPrice, setMinPrice] = useState(searchParams.get('min_price') || '');
  const [maxPrice, setMaxPrice] = useState(searchParams.get('max_price') || '');
  const [hideOutOfStock, setHideOutOfStock] = useState(searchParams.get('hide_out_of_stock') === 'true');

  // Bulk selection
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  const [bulkAction, setBulkAction] = useState('');
  const [showBulkPriceModal, setShowBulkPriceModal] = useState(false);
  const [priceAdjustPct, setPriceAdjustPct] = useState('');
  const [showImportModal, setShowImportModal] = useState(false);
  const [importText, setImportText] = useState('');
  const [importPreview, setImportPreview] = useState<any[]>([]);

  // Column visibility
  const [visibleCols, setVisibleCols] = useState<ColKey[]>(DEFAULT_VISIBLE);
  const [showColPicker, setShowColPicker] = useState(false);

  // Load saved column prefs
  useEffect(() => {
    preferencesApi.get('inventory_columns').then(res => {
      const val = res?.data?.data?.value;
      if (Array.isArray(val) && val.length > 0) setVisibleCols(val as ColKey[]);
    }).catch(() => {});
  }, []);

  const toggleCol = (key: ColKey) => {
    setVisibleCols(prev => {
      const next = prev.includes(key) ? prev.filter(k => k !== key) : [...prev, key];
      if (next.length === 0) return prev; // must keep at least one
      preferencesApi.set('inventory_columns', next).catch(() => {});
      return next;
    });
  };

  const isColVisible = (key: ColKey) => visibleCols.includes(key);

  const setParam = (key: string, val: string) => {
    const p = new URLSearchParams(searchParams);
    if (val) p.set(key, val); else p.delete(key);
    p.set('page', '1');
    setSearchParams(p, { replace: true });
  };

  const applyFilters = () => {
    const p = new URLSearchParams(searchParams);
    if (manufacturer) p.set('manufacturer', manufacturer); else p.delete('manufacturer');
    if (supplierId) p.set('supplier_id', supplierId); else p.delete('supplier_id');
    if (minPrice) p.set('min_price', minPrice); else p.delete('min_price');
    if (maxPrice) p.set('max_price', maxPrice); else p.delete('max_price');
    if (hideOutOfStock) p.set('hide_out_of_stock', 'true'); else p.delete('hide_out_of_stock');
    p.set('page', '1');
    setSearchParams(p, { replace: true });
  };

  const clearFilters = () => {
    setManufacturer('');
    setSupplierId('');
    setMinPrice('');
    setMaxPrice('');
    setHideOutOfStock(false);
    const p = new URLSearchParams(searchParams);
    ['manufacturer', 'supplier_id', 'min_price', 'max_price', 'hide_out_of_stock'].forEach(k => p.delete(k));
    p.set('page', '1');
    setSearchParams(p, { replace: true });
  };

  const activeFilterCount = [
    searchParams.get('manufacturer'),
    searchParams.get('supplier_id'),
    searchParams.get('min_price'),
    searchParams.get('max_price'),
    searchParams.get('hide_out_of_stock'),
  ].filter(Boolean).length;

  const handleSearchChange = (val: string) => {
    setSearchInput(val);
    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
    searchTimerRef.current = setTimeout(() => setParam('keyword', val), 300);
  };

  const reorderableFilter = searchParams.get('reorderable') === 'true';
  const lowStockFilter = searchParams.get('low_stock') === 'true';
  const sortBy = searchParams.get('sort_by') || 'name';
  const sortOrder = searchParams.get('sort_order') || 'ASC';

  const toggleSort = (col: string) => {
    const p = new URLSearchParams(searchParams);
    if (sortBy === col) {
      p.set('sort_order', sortOrder === 'ASC' ? 'DESC' : 'ASC');
    } else {
      p.set('sort_by', col);
      p.set('sort_order', 'ASC');
    }
    setSearchParams(p, { replace: true });
  };

  const queryParams: Record<string, any> = {
    page, pagesize: pageSize,
    keyword: keyword || undefined,
    item_type: tab || undefined,
    manufacturer: searchParams.get('manufacturer') || undefined,
    supplier_id: searchParams.get('supplier_id') || undefined,
    min_price: searchParams.get('min_price') || undefined,
    max_price: searchParams.get('max_price') || undefined,
    hide_out_of_stock: searchParams.get('hide_out_of_stock') || undefined,
    reorderable_only: reorderableFilter ? 'true' : undefined,
    low_stock: lowStockFilter ? 'true' : undefined,
    sort_by: sortBy,
    sort_order: sortOrder,
  };

  const { data, isLoading } = useQuery({
    queryKey: ['inventory', queryParams],
    queryFn: () => inventoryApi.list(queryParams),
  });

  const { data: lowStockData } = useQuery({
    queryKey: ['inventory-low-stock'],
    queryFn: () => inventoryApi.lowStock(),
  });

  const { data: manufacturersData } = useQuery({
    queryKey: ['inventory-manufacturers'],
    queryFn: () => inventoryApi.manufacturers(),
  });

  const { data: suppliersData } = useQuery({
    queryKey: ['inventory-suppliers'],
    queryFn: () => inventoryApi.listSuppliers(),
  });

  const items: any[] = data?.data?.data?.items || [];
  const pagination = data?.data?.data?.pagination;

  // Stock adjust confirmation for low-stock view
  const [stockConfirm, setStockConfirm] = useState<{ id: number; name: string; delta: number } | null>(null);
  const [dismissConfirm, setDismissConfirm] = useState(false);
  const lowStockCount = lowStockData?.data?.data?.items?.length || 0;
  const manufacturers: string[] = manufacturersData?.data?.data?.manufacturers || [];
  const suppliers: any[] = suppliersData?.data?.data?.suppliers || [];

  const deleteMutation = useMutation({
    mutationFn: (id: number) => inventoryApi.delete(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      toast.success('Item deactivated');
    },
    onError: () => toast.error('Failed to delete item'),
  });

  const bulkMutation = useMutation({
    mutationFn: ({ ids, action, value }: { ids: number[]; action: string; value?: string | number }) =>
      inventoryApi.bulkAction(ids, action, value),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      setSelectedIds(new Set());
      setBulkAction('');
      toast.success(`Bulk ${vars.action} applied to ${vars.ids.length} items`);
    },
    onError: () => toast.error('Bulk action failed'),
  });

  const importMutation = useMutation({
    mutationFn: (csvItems: any[]) => inventoryApi.importCsv(csvItems),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      const d = res?.data?.data;
      toast.success(`Imported ${d?.created || 0} items${d?.errors?.length ? `, ${d.errors.length} errors` : ''}`);
      setShowImportModal(false);
      setImportText('');
      setImportPreview([]);
    },
    onError: () => toast.error('Import failed'),
  });

  const handleDelete = useCallback(async (e: React.MouseEvent, id: number, name: string) => {
    e.stopPropagation();
    if (await confirm(`Deactivate "${name}"? It won't appear in lists but existing records are preserved.`, { danger: true })) {
      deleteMutation.mutate(id);
    }
  }, [deleteMutation]);

  const setPage = (n: number) => {
    const p = new URLSearchParams(searchParams);
    p.set('page', String(n));
    setSearchParams(p, { replace: true });
  };

  const toggleSelect = (id: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const toggleSelectAll = () => {
    if (selectedIds.size === items.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(items.map(i => i.id)));
    }
  };

  const handleBulkAction = async (action: string) => {
    if (selectedIds.size === 0) return;
    if (action === 'update_price') {
      setShowBulkPriceModal(true);
      return;
    }
    if (action === 'delete') {
      if (!await confirm(`Deactivate ${selectedIds.size} items?`, { danger: true })) return;
    }
    bulkMutation.mutate({ ids: Array.from(selectedIds), action });
  };

  const handlePriceUpdate = () => {
    const pct = parseFloat(priceAdjustPct);
    if (isNaN(pct)) { toast.error('Enter a valid percentage'); return; }
    bulkMutation.mutate({ ids: Array.from(selectedIds), action: 'update_price', value: pct });
    setShowBulkPriceModal(false);
    setPriceAdjustPct('');
  };

  // CSV Export
  const handleExport = () => {
    const headers = ['id', 'name', 'sku', 'item_type', 'in_stock', 'cost_price', 'retail_price', 'reorder_level', 'manufacturer', 'category'];
    const rows = items.map(i => headers.map(h => String(i[h] ?? '')));
    const csv = [headers.join(','), ...rows.map(r => r.map(v => `"${v.replace(/"/g, '""')}"`).join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `inventory-export-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // CSV Import parse
  const parseImportCsv = (text: string) => {
    const lines = text.trim().split('\n');
    if (lines.length < 2) { toast.error('CSV must have a header row and at least one data row'); return; }
    const headers = lines[0].split(',').map(h => h.trim().replace(/^"|"$/g, '').toLowerCase());
    const rows = lines.slice(1).map(line => {
      const vals = line.split(',').map(v => v.trim().replace(/^"|"$/g, ''));
      const obj: Record<string, string> = {};
      headers.forEach((h, i) => { obj[h] = vals[i] || ''; });
      return obj;
    });
    setImportPreview(rows);
  };

  // Price preview for bulk update
  const pricePreviewItems = useMemo(() => {
    const pct = parseFloat(priceAdjustPct);
    if (isNaN(pct)) return [];
    return items.filter(i => selectedIds.has(i.id)).map(i => ({
      name: i.name,
      current: Number(i.retail_price),
      new: Math.round(Number(i.retail_price) * (1 + pct / 100) * 100) / 100,
    }));
  }, [priceAdjustPct, items, selectedIds]);

  return (
    <div className="flex flex-col h-full">
      <div className="mb-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Inventory</h1>
          <p className="text-surface-500 dark:text-surface-400">Products, parts, and services</p>
        </div>
        <div className="flex items-center gap-2">
          {lowStockCount > 0 && (
            <Link
              to="/inventory?reorderable=true&low_stock=true"
              className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-amber-50 text-amber-700 border border-amber-200 dark:bg-amber-900/20 dark:text-amber-400 dark:border-amber-800 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors"
            >
              <AlertTriangle className="h-4 w-4" />
              {lowStockCount} low stock
            </Link>
          )}
          <div className="relative">
            <button onClick={() => setShowColPicker(!showColPicker)} className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
              <Columns className="h-4 w-4" /> Columns
            </button>
            {showColPicker && (
              <div className="absolute right-0 top-full mt-1 z-30 bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-700 rounded-lg shadow-lg p-2 w-44">
                {ALL_COLUMNS.map(col => (
                  <label key={col.key} className="flex items-center gap-2 px-2 py-1.5 text-sm text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 rounded cursor-pointer">
                    <input type="checkbox" checked={isColVisible(col.key)} onChange={() => toggleCol(col.key)}
                      className="rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500" />
                    {col.label}
                  </label>
                ))}
              </div>
            )}
          </div>
          <button onClick={handleExport} className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
            <Download className="h-4 w-4" /> Export
          </button>
          <button onClick={() => setShowImportModal(true)} className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
            <Upload className="h-4 w-4" /> Import
          </button>
          <Link
            to="/inventory/new"
            className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium text-sm transition-colors shadow-sm"
          >
            <Plus className="h-4 w-4" />
            New Item
          </Link>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-0 mb-4 border-b border-surface-200 dark:border-surface-700">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => setParam('type', t.key)}
            className={cn(
              'px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
              tab === t.key
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200'
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Search + Filter Toggle */}
      <div className="mb-4 flex items-center gap-2">
        <div className="relative max-w-md flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
          <input
            type="text"
            placeholder="Search by name, SKU, UPC..."
            value={searchInput}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="w-full pl-10 pr-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500 transition-colors"
          />
        </div>
        <button
          onClick={() => setShowFilters(!showFilters)}
          className={cn(
            'inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border transition-colors',
            activeFilterCount > 0
              ? 'border-primary-300 bg-primary-50 text-primary-700 dark:border-primary-700 dark:bg-primary-900/20 dark:text-primary-400'
              : 'border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800'
          )}
        >
          <Filter className="h-4 w-4" />
          Filters{activeFilterCount > 0 && ` (${activeFilterCount})`}
        </button>
        <label className="inline-flex items-center gap-2 cursor-pointer select-none">
          <span className={cn('text-sm font-medium', reorderableFilter ? 'text-teal-600 dark:text-teal-400' : 'text-surface-500 dark:text-surface-400')}>
            PLP / MS
          </span>
          <button
            role="switch"
            aria-checked={reorderableFilter}
            onClick={() => {
              const p = new URLSearchParams(searchParams);
              if (reorderableFilter) { p.delete('reorderable'); if (lowStockFilter) p.delete('low_stock'); }
              else { p.set('reorderable', 'true'); }
              p.set('page', '1');
              setSearchParams(p, { replace: true });
            }}
            className={cn(
              'relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors duration-200',
              reorderableFilter ? 'bg-teal-500' : 'bg-surface-300 dark:bg-surface-600'
            )}
          >
            <span className={cn(
              'pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow-sm transition-transform duration-200',
              reorderableFilter ? 'translate-x-5' : 'translate-x-0'
            )} />
          </button>
        </label>
        {reorderableFilter && (
          <label className="inline-flex items-center gap-2 cursor-pointer select-none">
            <span className={cn('text-sm font-medium', lowStockFilter ? 'text-amber-600 dark:text-amber-400' : 'text-surface-500 dark:text-surface-400')}>
              Low Stock
            </span>
            <button
              role="switch"
              aria-checked={lowStockFilter}
              onClick={() => {
                const p = new URLSearchParams(searchParams);
                if (lowStockFilter) { p.delete('low_stock'); } else { p.set('low_stock', 'true'); }
                p.set('page', '1');
                setSearchParams(p, { replace: true });
              }}
              className={cn(
                'relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors duration-200',
                lowStockFilter ? 'bg-amber-500' : 'bg-surface-300 dark:bg-surface-600'
              )}
            >
              <span className={cn(
                'pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow-sm transition-transform duration-200',
                lowStockFilter ? 'translate-x-5' : 'translate-x-0'
              )} />
            </button>
          </label>
        )}
      </div>

      {/* Advanced Filters Panel */}
      {showFilters && (
        <div className="mb-4 p-4 rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Manufacturer</label>
            <select value={manufacturer} onChange={e => setManufacturer(e.target.value)}
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5">
              <option value="">All</option>
              {manufacturers.map(m => <option key={m} value={m}>{m}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Supplier</label>
            <select value={supplierId} onChange={e => setSupplierId(e.target.value)}
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5">
              <option value="">All</option>
              {suppliers.map((s: any) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Min Price</label>
            <input type="number" value={minPrice} onChange={e => setMinPrice(e.target.value)} placeholder="0"
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5" />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Max Price</label>
            <input type="number" value={maxPrice} onChange={e => setMaxPrice(e.target.value)} placeholder="999"
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5" />
          </div>
          <div className="flex items-end gap-2">
            <label className="inline-flex items-center gap-2 cursor-pointer text-sm text-surface-600 dark:text-surface-300">
              <input type="checkbox" checked={hideOutOfStock} onChange={e => setHideOutOfStock(e.target.checked)}
                className="rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500" />
              <EyeOff className="h-3.5 w-3.5" /> Hide OOS
            </label>
          </div>
          <div className="col-span-full flex gap-2 mt-1">
            <button onClick={applyFilters} className="px-3 py-1.5 text-sm font-medium rounded-md bg-primary-600 text-white hover:bg-primary-700 transition-colors">
              Apply
            </button>
            <button onClick={clearFilters} className="px-3 py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 transition-colors">
              Clear
            </button>
          </div>
        </div>
      )}

      {/* Bulk Actions Bar */}
      {selectedIds.size > 0 && (
        <div className="mb-3 flex items-center gap-3 px-4 py-2 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-800">
          <span className="text-sm font-medium text-primary-700 dark:text-primary-300">{selectedIds.size} selected</span>
          <select value={bulkAction} onChange={e => { const v = e.target.value; setBulkAction(v); if (v) handleBulkAction(v); }}
            className="text-sm rounded-md border border-primary-200 dark:border-primary-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1">
            <option value="">Bulk Actions...</option>
            <option value="update_price">Update Price (%)</option>
            <option value="delete">Delete Selected</option>
          </select>
          <button onClick={() => { setSelectedIds(new Set()); setBulkAction(''); }} className="text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400">
            Clear selection
          </button>
        </div>
      )}

      {/* Table */}
      <div className="card overflow-hidden flex-1 flex flex-col min-h-0">
        {isLoading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20">
            <Package className="h-16 w-16 text-surface-300 dark:text-surface-600 mb-4" />
            <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">No items found</h2>
            <p className="text-sm text-surface-400 mt-1">Add your first inventory item to get started</p>
            <Link to="/inventory/new" className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-primary-600 text-white rounded-lg text-sm font-medium hover:bg-primary-700 transition-colors">
              <Plus className="h-4 w-4" /> Add First Item
            </Link>
          </div>
        ) : (
          <>
            {(reorderableFilter || lowStockFilter) && (
              <div className={cn('flex items-center gap-3 px-4 py-2 border-b',
                lowStockFilter ? 'bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800' : 'bg-teal-50 dark:bg-teal-900/20 border-teal-200 dark:border-teal-800'
              )}>
                <span className={cn('text-sm font-medium', lowStockFilter ? 'text-amber-700 dark:text-amber-300' : 'text-teal-700 dark:text-teal-300')}>
                  {lowStockFilter ? `PLP / Mobilesentrix parts below reorder level (${pagination?.total ?? items.length})` : 'Showing PLP / Mobilesentrix parts only'}
                </span>
                <div className="ml-auto flex items-center gap-2">
                  {lowStockFilter && items.length > 0 && (
                    <>
                      <button
                        onClick={() => {
                          // Group items by supplier source and open cart URLs
                          const plpItems = items.filter((i: any) => i.supplier_url && i.supplier_source === 'phonelcdparts');
                          const msItems = items.filter((i: any) => i.supplier_url && i.supplier_source === 'mobilesentrix');
                          let opened = 0;
                          // Open each supplier URL (browsers may block after first few)
                          for (const item of [...plpItems, ...msItems].slice(0, 20)) {
                            window.open(item.supplier_url, '_blank');
                            opened++;
                          }
                          if (opened > 0) toast.success(`Opened ${opened} supplier pages`);
                          if (plpItems.length + msItems.length > 20) toast(`Showing first 20 of ${plpItems.length + msItems.length}. Open rest manually.`);
                          if (opened === 0) toast.error('No supplier URLs found for these items');
                        }}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md bg-teal-600 text-white hover:bg-teal-700 transition-colors"
                      >
                        Order All on Supplier Sites
                      </button>
                      <button
                        onClick={() => setDismissConfirm(true)}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md border border-surface-300 dark:border-surface-600 text-surface-600 dark:text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700 transition-colors"
                      >
                        Dismiss All
                      </button>
                    </>
                  )}
                  <button onClick={() => { const p = new URLSearchParams(searchParams); p.delete('low_stock'); p.delete('reorderable'); setSearchParams(p, { replace: true }); }}
                    className="text-xs text-surface-500 hover:underline">Show all</button>
                </div>
              </div>
            )}
            <div className="overflow-auto flex-1 min-h-0">
              <table className="w-full">
                <thead className="sticky top-0 z-10">
                  <tr className="border-b border-surface-200 dark:border-surface-700">
                    <th className="px-2 py-3 bg-surface-50 dark:bg-surface-800/50 w-10">
                      <input type="checkbox" checked={selectedIds.size === items.length && items.length > 0}
                        onChange={toggleSelectAll}
                        className="rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500" />
                    </th>
                    {ALL_COLUMNS.filter(c => isColVisible(c.key)).map((c) => {
                      const sortCol = c.key === 'stock' ? 'in_stock' : c.key === 'cost' ? 'cost_price' : c.key === 'price' ? 'retail_price' : c.key;
                      const isSorted = sortBy === sortCol;
                      return (
                        <th key={c.key}
                          onClick={() => toggleSort(sortCol)}
                          className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50 cursor-pointer hover:text-surface-700 dark:hover:text-surface-200 select-none"
                        >
                          {c.label}
                          {isSorted && <span className="ml-1">{sortOrder === 'ASC' ? '▲' : '▼'}</span>}
                        </th>
                      );
                    })}
                    <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                  {items.map((item: any) => (
                    <tr
                      key={item.id}
                      onClick={() => navigate(`/inventory/${item.id}`)}
                      className="hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer transition-colors"
                    >
                      <td className="px-2 py-3" onClick={e => e.stopPropagation()}>
                        <input type="checkbox" checked={selectedIds.has(item.id)}
                          onChange={() => toggleSelect(item.id)}
                          className="rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500" />
                      </td>
                      {isColVisible('sku') && (
                      <td className="px-4 py-3 text-sm">
                        <span className="font-mono text-xs px-2 py-0.5 rounded bg-surface-100 dark:bg-surface-700 text-surface-600 dark:text-surface-300">
                          {item.sku || '\u2014'}
                        </span>
                      </td>
                      )}
                      {isColVisible('name') && (
                      <td className="px-4 py-3 text-sm">
                        <div className="font-medium text-surface-900 dark:text-surface-100">{item.name}</div>
                        {item.manufacturer && <div className="text-xs text-surface-400">{item.manufacturer}</div>}
                      </td>
                      )}
                      {isColVisible('type') && (
                      <td className="px-4 py-3 text-sm">
                        <span className={cn(
                          'inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize',
                          item.item_type === 'product' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400' :
                          item.item_type === 'part' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400' :
                          'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                        )}>
                          {item.item_type}
                        </span>
                      </td>
                      )}
                      {isColVisible('category') && (
                      <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">{item.category || item.item_type || item.manufacturer || <span className="text-surface-300 dark:text-surface-600">Not set</span>}</td>
                      )}
                      {isColVisible('stock') && (
                      <td className="px-4 py-3 text-sm" onClick={(e) => e.stopPropagation()}>
                        {item.item_type !== 'service' ? (
                          <div className="flex items-center gap-1">
                            <button
                              onClick={() => {
                                if (item.in_stock <= 0) return;
                                if (lowStockFilter || reorderableFilter) {
                                  setStockConfirm({ id: item.id, name: item.name, delta: -1 });
                                } else {
                                  inventoryApi.adjustStock(item.id, { quantity: -1, type: 'manual_adjustment', notes: 'Quick -1 from list' }).then(() => {
                                    queryClient.invalidateQueries({ queryKey: ['inventory'] });
                                  }).catch(() => toast.error('Failed to adjust stock'));
                                }
                              }}
                              className="rounded p-0.5 text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:text-red-400 dark:hover:bg-red-900/20 transition-colors disabled:opacity-30"
                              disabled={item.in_stock <= 0}
                              title="Decrease stock by 1"
                            >
                              <Minus className="h-3 w-3" />
                            </button>
                            <span className={cn(
                              'font-medium min-w-[24px] text-center',
                              item.in_stock === 0 ? 'text-red-600 dark:text-red-400' :
                              item.in_stock > 10000 ? 'text-amber-600 dark:text-amber-400' :
                              item.in_stock <= (item.reorder_level || 0) ? 'text-amber-600 dark:text-amber-400' :
                              'text-surface-900 dark:text-surface-100'
                            )}>
                              {item.in_stock}
                              {item.in_stock > 10000 && (
                                <span title="Unrealistic stock value"><AlertTriangle className="inline h-3 w-3 ml-0.5 text-amber-500" /></span>
                              )}
                              {item.in_stock > 0 && item.in_stock <= 10000 && item.in_stock <= (item.reorder_level || 0) && (
                                <AlertTriangle className="inline h-3 w-3 ml-0.5 text-amber-500" />
                              )}
                            </span>
                            <button
                              onClick={() => {
                                if (lowStockFilter || reorderableFilter) {
                                  setStockConfirm({ id: item.id, name: item.name, delta: 1 });
                                } else {
                                  inventoryApi.adjustStock(item.id, { quantity: 1, type: 'manual_adjustment', notes: 'Quick +1 from list' }).then(() => {
                                    queryClient.invalidateQueries({ queryKey: ['inventory'] });
                                  }).catch(() => toast.error('Failed to adjust stock'));
                                }
                              }}
                              className="rounded p-0.5 text-surface-400 hover:text-green-600 hover:bg-green-50 dark:hover:text-green-400 dark:hover:bg-green-900/20 transition-colors"
                              title="Increase stock by 1"
                            >
                              <Plus className="h-3 w-3" />
                            </button>
                            {item.in_stock <= (item.reorder_level || 0) && item.in_stock >= 0 && (
                              <Link to="/purchase-orders" onClick={(e) => e.stopPropagation()}
                                className="ml-1 text-[10px] font-medium text-amber-600 dark:text-amber-400 hover:underline" title="Create purchase order">
                                Order
                              </Link>
                            )}
                          </div>
                        ) : (
                          <span className="text-surface-400 text-xs italic">Unlimited</span>
                        )}
                      </td>
                      )}
                      {isColVisible('cost') && (
                      <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">
                        {item.cost_price > 0 ? `$${Number(item.cost_price).toFixed(2)}` : '\u2014'}
                      </td>
                      )}
                      {isColVisible('price') && (
                      <td className="px-4 py-3 text-sm font-medium text-surface-900 dark:text-surface-100">
                        {Number(item.retail_price) === 0 ? (
                          <span className="text-surface-400 dark:text-surface-500 italic">No price</span>
                        ) : (
                          <>${Number(item.retail_price).toFixed(2)}</>
                        )}
                      </td>
                      )}
                      <td className="px-4 py-3 text-sm">
                        <div className="flex items-center justify-end gap-1">
                          <Link to={`/inventory/${item.id}`} onClick={(e) => e.stopPropagation()}
                            className="p-1.5 rounded-md text-surface-400 hover:text-primary-600 hover:bg-primary-50 dark:hover:text-primary-400 dark:hover:bg-primary-900/20 transition-colors" title="View">
                            <Eye className="h-4 w-4" />
                          </Link>
                          <Link to={`/inventory/${item.id}?edit=true`} onClick={(e) => e.stopPropagation()}
                            className="p-1.5 rounded-md text-surface-400 hover:text-amber-600 hover:bg-amber-50 dark:hover:text-amber-400 dark:hover:bg-amber-900/20 transition-colors" title="Edit">
                            <Pencil className="h-4 w-4" />
                          </Link>
                          <button onClick={(e) => handleDelete(e, item.id, item.name)}
                            className="p-1.5 rounded-md text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:text-red-400 dark:hover:bg-red-900/20 transition-colors" title="Deactivate">
                            <Trash2 className="h-4 w-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {pagination && (
              <div className="flex items-center justify-between px-4 py-3 border-t border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/30">
                <div className="flex items-center gap-3">
                  <div className="flex items-center gap-1.5">
                    <span className="text-xs text-surface-500 dark:text-surface-400">Show</span>
                    <select
                      value={pageSize}
                      onChange={(e) => { const v = e.target.value; localStorage.setItem('inventory_pagesize', v); setSavedPageSize(Number(v)); const p = new URLSearchParams(searchParams); p.set('pagesize', v); p.set('page', '1'); setSearchParams(p, { replace: true }); }}
                      className="text-xs rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-2 py-1 focus:outline-none focus:ring-1 focus:ring-primary-500"
                    >
                      {[10, 25, 50, 100, 250].map((n) => (
                        <option key={n} value={n}>{n}</option>
                      ))}
                    </select>
                    <span className="text-xs text-surface-500 dark:text-surface-400">per page</span>
                  </div>
                  <p className="text-sm text-surface-500 dark:text-surface-400">
                    Page {pagination.page} of {pagination.total_pages}
                    <span className="ml-2 text-surface-400">({pagination.total} total)</span>
                  </p>
                </div>
                {pagination.total_pages > 1 && (
                  <div className="flex items-center gap-2">
                    <button onClick={() => setPage(page - 1)} disabled={page <= 1}
                      className="inline-flex items-center gap-1 px-3 py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                      <ChevronLeft className="h-4 w-4" /> Previous
                    </button>
                    <button onClick={() => setPage(page + 1)} disabled={page >= pagination.total_pages}
                      className="inline-flex items-center gap-1 px-3 py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                      Next <ChevronRight className="h-4 w-4" />
                    </button>
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {/* Bulk Price Update Modal */}
      {showBulkPriceModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-md max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Update Prices</h3>
              <button onClick={() => { setShowBulkPriceModal(false); setPriceAdjustPct(''); }} className="text-surface-400 hover:text-surface-600">
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="mb-4">
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                Price adjustment (%)
              </label>
              <input type="number" value={priceAdjustPct} onChange={e => setPriceAdjustPct(e.target.value)}
                placeholder="e.g. 10 for +10%, -15 for -15%"
                className="w-full text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2" />
            </div>
            {pricePreviewItems.length > 0 && (
              <div className="flex-1 overflow-auto mb-4 max-h-60">
                <table className="w-full text-sm">
                  <thead><tr className="border-b border-surface-200 dark:border-surface-700">
                    <th className="text-left py-1 text-xs text-surface-500">Item</th>
                    <th className="text-right py-1 text-xs text-surface-500">Current</th>
                    <th className="text-right py-1 text-xs text-surface-500">New</th>
                  </tr></thead>
                  <tbody>
                    {pricePreviewItems.slice(0, 20).map((p, i) => (
                      <tr key={i} className="border-b border-surface-100 dark:border-surface-700/50">
                        <td className="py-1 truncate max-w-[200px]">{p.name}</td>
                        <td className="py-1 text-right text-surface-500">${p.current.toFixed(2)}</td>
                        <td className={cn('py-1 text-right font-medium', p.new > p.current ? 'text-green-600' : p.new < p.current ? 'text-red-600' : '')}>
                          ${p.new.toFixed(2)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <div className="flex justify-end gap-2">
              <button onClick={() => { setShowBulkPriceModal(false); setPriceAdjustPct(''); }}
                className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300">
                Cancel
              </button>
              <button onClick={handlePriceUpdate} disabled={!priceAdjustPct}
                className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50">
                Apply to {selectedIds.size} items
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Import CSV Modal */}
      {showImportModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-2xl max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Import Inventory CSV</h3>
              <button onClick={() => { setShowImportModal(false); setImportText(''); setImportPreview([]); }} className="text-surface-400 hover:text-surface-600">
                <X className="h-5 w-5" />
              </button>
            </div>
            <p className="text-sm text-surface-500 mb-2">
              Paste CSV with headers: name, sku, item_type, category, manufacturer, cost_price, retail_price, in_stock, reorder_level
            </p>
            <textarea
              value={importText}
              onChange={e => { setImportText(e.target.value); if (e.target.value) parseImportCsv(e.target.value); else setImportPreview([]); }}
              placeholder={'name,sku,item_type,cost_price,retail_price,in_stock\niPhone 15 Screen,PRT-10001,part,45.00,89.99,5'}
              rows={6}
              className="w-full text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 font-mono mb-3"
            />
            <div className="mb-2 flex items-center gap-2">
              <label className="px-3 py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 cursor-pointer">
                <Upload className="h-4 w-4 inline mr-1" /> Upload File
                <input type="file" accept=".csv" className="hidden" onChange={e => {
                  const file = e.target.files?.[0];
                  if (!file) return;
                  const reader = new FileReader();
                  reader.onload = ev => {
                    const text = ev.target?.result as string;
                    setImportText(text);
                    parseImportCsv(text);
                  };
                  reader.readAsText(file);
                }} />
              </label>
            </div>
            {importPreview.length > 0 && (
              <div className="flex-1 overflow-auto mb-3 max-h-48 border border-surface-200 dark:border-surface-700 rounded-lg">
                <table className="w-full text-xs">
                  <thead><tr className="bg-surface-50 dark:bg-surface-800">
                    {Object.keys(importPreview[0]).slice(0, 6).map(h => (
                      <th key={h} className="px-2 py-1.5 text-left font-medium text-surface-500">{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>
                    {importPreview.slice(0, 10).map((row, i) => (
                      <tr key={i} className="border-t border-surface-100 dark:border-surface-700/50">
                        {Object.values(row).slice(0, 6).map((v, j) => (
                          <td key={j} className="px-2 py-1 text-surface-700 dark:text-surface-300 truncate max-w-[120px]">{String(v)}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {importPreview.length > 10 && <p className="text-xs text-surface-400 p-2">...and {importPreview.length - 10} more rows</p>}
              </div>
            )}
            <div className="flex justify-end gap-2">
              <button onClick={() => { setShowImportModal(false); setImportText(''); setImportPreview([]); }}
                className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300">
                Cancel
              </button>
              <button
                onClick={() => importMutation.mutate(importPreview)}
                disabled={importPreview.length === 0 || importMutation.isPending}
                className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50 inline-flex items-center gap-1.5"
              >
                {importMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Import {importPreview.length} items
              </button>
            </div>
          </div>
        </div>
      )}
      {/* Dismiss all low stock confirmation */}
      {dismissConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900 p-6">
            <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100 mb-2">
              Dismiss All Low Stock Alerts
            </h3>
            <p className="text-sm text-surface-600 dark:text-surface-400 mb-1">
              This will hide all {pagination?.total ?? items.length} low stock alerts until the items are restocked and run out again.
            </p>
            <p className="text-xs text-surface-400 dark:text-surface-500 mb-4">
              Items will reappear if they get restocked and then drop below reorder level again.
            </p>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setDismissConfirm(false)}
                className="px-4 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  inventoryApi.dismissLowStock().then((res) => {
                    const count = res?.data?.data?.dismissed ?? 0;
                    toast.success(`Dismissed ${count} low stock alerts`);
                    queryClient.invalidateQueries({ queryKey: ['inventory'] });
                    queryClient.invalidateQueries({ queryKey: ['inventory-low-stock'] });
                  }).catch(() => toast.error('Failed to dismiss'));
                  setDismissConfirm(false);
                }}
                className="px-4 py-2 text-sm font-semibold rounded-lg bg-amber-600 text-white hover:bg-amber-700"
              >
                Dismiss All
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Stock adjustment confirmation dialog */}
      {stockConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900 p-6">
            <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100 mb-2">
              Adjust Stock
            </h3>
            <p className="text-sm text-surface-600 dark:text-surface-400 mb-4">
              {stockConfirm.delta > 0 ? 'Increase' : 'Decrease'} stock by 1 for{' '}
              <span className="font-medium text-surface-900 dark:text-surface-100">
                {stockConfirm.name.length > 60 ? stockConfirm.name.slice(0, 60) + '...' : stockConfirm.name}
              </span>?
            </p>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setStockConfirm(null)}
                className="px-4 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  inventoryApi.adjustStock(stockConfirm.id, {
                    quantity: stockConfirm.delta,
                    type: 'manual_adjustment',
                    notes: `Quick ${stockConfirm.delta > 0 ? '+1' : '-1'} from list`,
                  }).then(() => {
                    queryClient.invalidateQueries({ queryKey: ['inventory'] });
                    toast.success(`Stock ${stockConfirm.delta > 0 ? 'increased' : 'decreased'}`);
                  }).catch(() => toast.error('Failed to adjust stock'));
                  setStockConfirm(null);
                }}
                className={cn(
                  'px-4 py-2 text-sm font-semibold rounded-lg text-white',
                  stockConfirm.delta > 0
                    ? 'bg-green-600 hover:bg-green-700'
                    : 'bg-red-600 hover:bg-red-700'
                )}
              >
                {stockConfirm.delta > 0 ? '+1 Stock' : '-1 Stock'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
